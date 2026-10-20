import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'api.dart';
import 'config.dart';
import 'printer.dart';
import 'realtime.dart';
import 'ticket.dart';

enum Health { setup, ok, degraded, error }

class TerminalStatus {
  const TerminalStatus({
    this.configured = false,
    this.connected = false,
    this.realtime = false,
    this.device = '',
    this.printerName = '',
    this.lastError = '',
    this.lastPrintAt,
    this.printed = 0,
  });

  final bool configured;

  /// Servidor respondeu.
  final bool connected;

  /// Inscrito no canal do Reverb.
  final bool realtime;
  final String device;

  /// Fila no PertoERP (caixa, cozinha…).
  final String printerName;
  final String lastError;
  final DateTime? lastPrintAt;
  final int printed;

  Health get health => switch (this) {
        TerminalStatus(configured: false) => Health.setup,
        TerminalStatus(connected: false) => Health.error,
        _ when lastError.isNotEmpty => Health.error,
        TerminalStatus(realtime: false) => Health.degraded,
        _ => Health.ok,
      };

  TerminalStatus copyWith({bool? configured, bool? connected, bool? realtime, String? device, String? printerName, String? lastError, DateTime? lastPrintAt, int? printed}) =>
      TerminalStatus(
        configured: configured ?? this.configured,
        connected: connected ?? this.connected,
        realtime: realtime ?? this.realtime,
        device: device ?? this.device,
        printerName: printerName ?? this.printerName,
        lastError: lastError ?? this.lastError,
        lastPrintAt: lastPrintAt ?? this.lastPrintAt,
        printed: printed ?? this.printed,
      );
}

/// Coração do terminal: busca a fila, imprime, confirma e mantém o tempo real. Mesmo comportamento da versão em Go.
class TerminalService extends ChangeNotifier {
  TerminalService(this._config, {TicketPrinter Function(TerminalConfig)? openPrinter, ApiClient Function(TerminalConfig)? apiFactory})
      : _openPrinter = openPrinter ?? TicketPrinter.open,
        _apiFactory = apiFactory ?? ((config) => ApiClient(config.serverUrl, config.token, insecureTls: config.insecureTls)),
        _status = TerminalStatus(configured: _config.configured);

  final TicketPrinter Function(TerminalConfig) _openPrinter;
  final ApiClient Function(TerminalConfig) _apiFactory;

  TerminalConfig _config;
  TerminalStatus _status;
  int _generation = 0;
  ApiClient? _client;
  RealtimeClient? _realtime;
  Completer<void>? _kick;

  /// Já impressos: evita imprimir de novo se a confirmação falhar.
  final Map<int, DateTime> _done = {};

  TerminalConfig get config => _config;

  TerminalStatus get status => _status;

  void _update(TerminalStatus Function(TerminalStatus status) change) {
    _status = change(_status);
    notifyListeners();
  }

  void start() => _restart();

  /// Grava a nova configuração e reinicia a conexão com ela.
  Future<void> apply(TerminalConfig config) async {
    _config = config.normalized();
    _config.save();
    await _restart();
  }

  /// Troca a aparência na hora, sem reconectar.
  void setAppearance(Appearance appearance) {
    _config = _config.copyWith(appearance: appearance);
    try {
      _config.save();
    } catch (error) {
      log('configuração: $error');
    }
    notifyListeners();
  }

  /// Pede uma consulta imediata da fila (evento do Reverb ou clique do usuário).
  void kick() {
    if (_kick != null && !_kick!.isCompleted) {
      _kick!.complete();
    }
  }

  Future<void> stop() async {
    _generation++;
    kick();
    await _realtime?.stop();
    _client?.close();
    _realtime = null;
    _client = null;
  }

  Future<void> _restart() async {
    await stop();
    final generation = _generation;

    _status = TerminalStatus(configured: _config.configured, printed: _status.printed, lastPrintAt: _status.lastPrintAt);
    notifyListeners();

    if (!_config.configured) {
      return;
    }

    unawaited(_run(generation, _config));
  }

  bool _alive(int generation) => generation == _generation;

  Future<void> _run(int generation, TerminalConfig config) async {
    final client = _apiFactory(config);
    _client = client;

    final me = await _identify(generation, client);
    if (me == null || !_alive(generation)) {
      return;
    }

    final realtime = me.realtime;
    if (realtime != null && me.channel.isNotEmpty) {
      _realtime = RealtimeClient(
        uri: realtime.uri,
        channel: me.channel,
        authorize: client.authorizeChannel,
        insecureTls: config.insecureTls,
        onEvent: (event) {
          log('evento $event: buscando a fila');
          kick();
        },
        onState: (connected, error) {
          if (!_alive(generation)) {
            return;
          }
          if (error != null) {
            log('tempo real: $error');
          }
          if (connected) {
            log('tempo real: inscrito em ${me.channel}');
          }
          _update((status) => status.copyWith(realtime: connected));
          if (connected) {
            kick(); // pode ter chegado algo enquanto estava desconectado
          }
        },
      )..start();
    }

    while (_alive(generation)) {
      await _processPending(generation, client, config);

      // Com tempo real, a consulta é só uma garantia.
      final wait = _status.realtime ? const Duration(seconds: 60) : Duration(seconds: config.pollSeconds);
      _kick = Completer<void>();
      await Future.any([Future<void>.delayed(wait), _kick!.future]);
    }
  }

  Future<Me?> _identify(int generation, ApiClient client) async {
    var backoff = const Duration(seconds: 2);

    while (_alive(generation)) {
      try {
        final me = await client.me();
        log('conectado como "${me.name}" (fila "${me.printerName}")');
        _update((status) => status.copyWith(connected: true, device: me.name, printerName: me.printerName, lastError: ''));

        return me;
      } catch (error) {
        if (!_alive(generation)) {
          return null;
        }
        log('servidor: $error');
        _update((status) => status.copyWith(connected: false, lastError: '$error'));
        if (error is UnauthorizedException) {
          backoff = const Duration(minutes: 1);
        }
      }

      _kick = Completer<void>();
      await Future.any([Future<void>.delayed(backoff), _kick!.future]);
      backoff = backoff * 2 > const Duration(minutes: 1) ? const Duration(minutes: 1) : backoff * 2;
    }

    return null;
  }

  Future<void> _processPending(int generation, ApiClient client, TerminalConfig config) async {
    final List<Job> jobs;
    try {
      jobs = await client.pendingJobs();
    } catch (error) {
      if (_alive(generation)) {
        log('fila: $error');
        _update((status) => status.copyWith(connected: false, lastError: '$error'));
      }

      return;
    }

    _update((status) => status.copyWith(connected: true, lastError: status.connected ? null : ''));

    for (final job in jobs) {
      if (!_alive(generation)) {
        return;
      }
      await _handle(client, config, job);
    }

    _done.removeWhere((_, at) => DateTime.now().difference(at) > const Duration(hours: 1));
  }

  Future<void> _handle(ApiClient client, TerminalConfig config, Job job) async {
    if (!_done.containsKey(job.id)) {
      try {
        await _send(config, 'PertoERP #${job.id}', Payload.fromJson(job.payload));
      } catch (error) {
        log('trabalho ${job.id}: $error');
        _update((status) => status.copyWith(lastError: 'Impressão: $error'));
        try {
          await client.report(job.id, printed: false, message: '$error');
        } catch (reportError) {
          log('trabalho ${job.id}: falha ao registrar o erro: $reportError');
        }

        return;
      }

      _done[job.id] = DateTime.now();
      _update((status) => status.copyWith(printed: status.printed + 1, lastPrintAt: DateTime.now(), lastError: ''));
      log('trabalho ${job.id} impresso');
    }

    // Se a confirmação falhar, o trabalho volta na próxima consulta e só a confirmação é refeita.
    try {
      await client.report(job.id, printed: true);
    } catch (error) {
      log('trabalho ${job.id}: confirmação pendente: $error');
    }
  }

  /// Página de teste com a configuração informada (ainda não salva).
  Future<void> testPrint(TerminalConfig config) => _send(config.normalized(), 'PertoERP - teste', samplePayload());

  Future<void> _send(TerminalConfig config, String document, Payload payload) async {
    final printer = _openPrinter(config);
    var openDrawer = config.openDrawer;

    for (var copy = 0; copy < (config.copies < 1 ? 1 : config.copies); copy++) {
      await printer.print(
        document,
        renderTicket(payload, RenderOptions(columns: config.columns, codePage: config.codePage, cut: config.cut, openDrawer: openDrawer)),
      );
      openDrawer = false;
    }
  }

  /// Testa o endereço e o token sem salvar nada.
  static Future<Me> check(TerminalConfig config) async {
    config = config.normalized();
    if (config.serverUrl.isEmpty || config.token.isEmpty) {
      throw ApiException('informe o endereço do PertoERP e o token do terminal');
    }

    final client = ApiClient(config.serverUrl, config.token, insecureTls: config.insecureTls);
    try {
      return await client.me().timeout(const Duration(seconds: 15));
    } finally {
      client.close();
    }
  }

  static IOSink? _log;

  /// Desligado nos testes, para não misturar com o log do terminal de verdade.
  static bool logToFile = true;

  /// Grava em terminal.log (recomeçando quando passa de 5 MB).
  static void log(String message) {
    final line = '${DateTime.now().toIso8601String().substring(0, 19).replaceFirst('T', ' ')} $message';
    debugPrint(line);
    if (!logToFile) {
      return;
    }

    try {
      if (_log == null) {
        TerminalConfig.directory.createSync(recursive: true);
        final file = File('${TerminalConfig.directory.path}${Platform.pathSeparator}terminal.log');
        if (file.existsSync() && file.lengthSync() > 5 << 20) {
          file.renameSync('${file.path}.old');
        }
        _log = file.openWrite(mode: FileMode.append);
      }
      _log!.writeln(line);
    } catch (_) {
      // Sem log em disco o terminal continua imprimindo.
    }
  }
}
