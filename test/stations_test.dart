import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:perto_terminal/src/config.dart';
import 'package:perto_terminal/src/printer.dart';
import 'package:perto_terminal/src/printer_settings.dart';
import 'package:perto_terminal/src/service.dart';

class _Spy implements TicketPrinter {
  _Spy(this.name, this.log);

  final String name;
  final List<String> log;

  @override
  Future<void> print(String document, Uint8List data) async => log.add('$name: $document');
}

/// PertoERP de mentira com setores: o terminal escolhe os dele e avisa por POST /queues.
class _Server {
  late HttpServer server;
  bool withStations = true;
  List<String> queues = ['caixa'];
  final posted = <List<String>>[];
  final jobs = <String, List<Map<String, dynamic>>>{};

  String get url => 'http://${server.address.host}:${server.port}';

  Map<String, dynamic> get me => {
        'name': 'PC da cozinha',
        'printer_name': queues.first,
        'queues': queues,
        'channel': 'private-company.1.printer.${queues.first}',
        'realtime': null,
        if (withStations)
          'stations': [
            {'queue': 'caixa', 'name': 'Caixa'},
            {'queue': 'cozinha', 'name': 'Cozinha'},
            {'queue': 'bar', 'name': 'Bar'},
          ],
      };

  Future<void> start() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      final body = await utf8.decoder.bind(request).join();
      request.response.headers.contentType = ContentType.json;
      final path = request.uri.path;

      if (path == '/api/v1/terminal/me') {
        request.response.write(jsonEncode(me));
      } else if (path == '/api/v1/terminal/queues') {
        queues = [for (final queue in (jsonDecode(body)['queues'] as List)) '$queue'];
        posted.add(queues);
        request.response.write(jsonEncode(me));
      } else if (path == '/api/v1/terminal/jobs') {
        final queue = request.uri.queryParameters['printer'] ?? queues.first;
        request.response.write(jsonEncode({'data': jobs[queue] ?? []}));
      } else if (path.endsWith('/status')) {
        final id = int.parse(request.uri.pathSegments[4]);
        for (final list in jobs.values) {
          list.removeWhere((job) => job['id'] == id);
        }
        request.response.write('{}');
      }
      await request.response.close();
    });
  }
}

Future<void> _eventually(bool Function() condition) async {
  for (var i = 0; i < 100 && !condition(); i++) {
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }
  expect(condition(), isTrue);
}

void main() {
  late _Server api;

  setUpAll(() => TerminalService.logToFile = false);

  setUp(() async {
    api = _Server();
    await api.start();
  });

  tearDown(() => api.server.close(force: true));

  test('os setores escolhidos aqui vão para o PertoERP e cada um sai na sua impressora', () async {
    api.jobs['cozinha'] = [{'id': 1, 'payload': {'items': []}}];
    api.jobs['bar'] = [{'id': 2, 'payload': {'items': []}}];
    final printed = <String>[];

    final service = TerminalService(
      TerminalConfig(
        serverUrl: api.url,
        token: 't',
        printerName: 'ELGIN',
        pollSeconds: 2,
        mainQueue: 'cozinha',
        extraPrinters: const {'bar': PrinterSettings(name: 'EPSON'), 'copa': PrinterSettings()},
      ),
      openPrinter: (config) => _Spy(config.printerName, printed),
    );
    service.start();
    await _eventually(() => printed.length == 2);
    await service.stop();

    // A copa foi ligada sem impressora: não é informada ao PertoERP.
    expect(api.posted.single, ['cozinha', 'bar']);
    expect(printed, containsAll(['ELGIN: PertoERP #1', 'EPSON: PertoERP #2']));
    expect(service.status.stations.map((station) => station.name), ['Caixa', 'Cozinha', 'Bar']);
    expect(service.status.printerName, 'cozinha');
  });

  test('não reenvia quando o PertoERP já tem os mesmos setores', () async {
    api.queues = ['cozinha', 'bar'];
    final service = TerminalService(
      TerminalConfig(serverUrl: api.url, token: 't', printerName: 'ELGIN', mainQueue: 'cozinha', extraPrinters: const {'bar': PrinterSettings(name: 'EPSON')}),
      openPrinter: (config) => _Spy(config.printerName, []),
    );
    service.start();
    await _eventually(() => service.status.connected);
    await service.stop();

    expect(api.posted, isEmpty);
  });

  test('servidor antigo, sem setores: segue a fila que o PertoERP manda', () async {
    api.withStations = false;
    final service = TerminalService(
      TerminalConfig(serverUrl: api.url, token: 't', printerName: 'ELGIN', mainQueue: 'cozinha'),
      openPrinter: (config) => _Spy(config.printerName, []),
    );
    service.start();
    await _eventually(() => service.status.connected);
    await service.stop();

    expect(api.posted, isEmpty);
    expect(service.status.printerName, 'caixa');
  });

  test('guarda o setor da impressora principal na configuração', () {
    const config = TerminalConfig(printerName: 'ELGIN', mainQueue: 'cozinha', extraPrinters: {'bar': PrinterSettings(name: 'EPSON')});

    final restored = TerminalConfig.fromJson(config.toJson());

    expect(restored.mainQueue, 'cozinha');
    expect(restored.chosenQueues, ['cozinha', 'bar']);
    expect(restored.withoutExtraPrinter('bar').chosenQueues, ['cozinha']);
  });
}
