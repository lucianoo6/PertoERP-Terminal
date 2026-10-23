import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:perto_terminal/src/api.dart';
import 'package:perto_terminal/src/config.dart';
import 'package:perto_terminal/src/printer.dart';
import 'package:perto_terminal/src/printer_settings.dart';
import 'package:perto_terminal/src/service.dart';

/// Impressora de mentira que lembra em qual impressora (nome no Windows) cada cupom saiu.
class _Spy implements TicketPrinter {
  _Spy(this.name, this.log);

  final String name;
  final List<String> log;

  @override
  Future<void> print(String document, Uint8List data) async => log.add('$name: $document');
}

void main() {
  late HttpServer server;
  final jobs = <String, List<Map<String, dynamic>>>{};
  final reports = <int>[];
  final queried = <String>[];

  setUpAll(() => TerminalService.logToFile = false);

  setUp(() async {
    jobs
      ..clear()
      ..addAll({
        'caixa': [{'id': 1, 'payload': {'items': []}}],
        'cozinha': [{'id': 2, 'payload': {'items': []}}],
        'bar': [{'id': 3, 'payload': {'items': []}}],
      });
    reports.clear();
    queried.clear();

    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      request.response.headers.contentType = ContentType.json;
      final path = request.uri.path;

      if (path == '/api/v1/terminal/me') {
        request.response.write(jsonEncode({
          'name': 'PC do salão',
          'printer_name': 'caixa',
          'queues': ['caixa', 'cozinha', 'bar'],
          'channel': 'private-company.1.printer.caixa',
          'realtime': null,
        }));
      } else if (path == '/api/v1/terminal/jobs') {
        final queue = request.uri.queryParameters['printer'] ?? 'caixa';
        queried.add(queue);
        request.response.write(jsonEncode({'data': jobs[queue] ?? []}));
      } else if (path.endsWith('/status')) {
        final id = int.parse(request.uri.pathSegments[4]);
        reports.add(id);
        for (final list in jobs.values) {
          list.removeWhere((job) => job['id'] == id);
        }
        request.response.write('{}');
      }
      await request.response.close();
    });
  });

  tearDown(() => server.close(force: true));

  test('cada fila sai na impressora dela; fila sem impressora espera no PertoERP', () async {
    final printed = <String>[];
    final config = TerminalConfig(
      serverUrl: 'http://${server.address.host}:${server.port}',
      token: 't',
      printerName: 'ELGIN caixa',
      pollSeconds: 2,
      extraPrinters: const {'cozinha': PrinterSettings(name: 'EPSON cozinha', columns: 32)},
    );
    final service = TerminalService(config, openPrinter: (queueConfig) => _Spy(queueConfig.printerName, printed));

    service.start();
    for (var i = 0; i < 100 && reports.length < 2; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    await service.stop();

    expect(printed, containsAll(['ELGIN caixa: PertoERP #1', 'EPSON cozinha: PertoERP #2']));
    expect(printed.where((line) => line.contains('#3')), isEmpty, reason: 'a fila do bar ainda não tem impressora');
    expect(queried, isNot(contains('bar')));
    expect(reports, containsAll([1, 2]));
    expect(service.status.queues, ['caixa', 'cozinha', 'bar']);
    expect(service.status.queuesWithoutPrinter, ['bar']);
    expect(service.status.health, Health.degraded);
  });

  test('guarda e lê as impressoras de cada fila', () {
    const config = TerminalConfig(
      printerName: 'ELGIN caixa',
      extraPrinters: {
        'cozinha': PrinterSettings(kind: PrinterKind.network, address: '192.168.0.50', columns: 32, cut: false, copies: 2),
      },
    );

    final reloaded = TerminalConfig.fromJson(jsonDecode(jsonEncode(config.toJson())) as Map<String, dynamic>);
    final kitchen = reloaded.extraPrinters['cozinha']!;

    expect(kitchen.kind, PrinterKind.network);
    expect(kitchen.address, '192.168.0.50');
    expect(kitchen.columns, 32);
    expect(kitchen.cut, isFalse);
    expect(kitchen.copies, 2);
    expect(reloaded.forQueue('cozinha', mainQueue: 'caixa')!.printerAddress, '192.168.0.50');
    expect(reloaded.forQueue('caixa', mainQueue: 'caixa')!.printerName, 'ELGIN caixa');
    expect(reloaded.forQueue('bar', mainQueue: 'caixa'), isNull);
  });

  test('descobre o canal de cada fila, mesmo em servidor que não manda a lista de canais', () {
    final me = Me(name: 'PC', printerName: 'caixa', channel: 'private-company.7.printer.caixa', queues: ['caixa', 'cozinha']);

    expect(me.channelFor('caixa'), 'private-company.7.printer.caixa');
    expect(me.channelFor('cozinha'), 'private-company.7.printer.cozinha');

    final withChannels = Me(name: 'PC', printerName: 'caixa', channel: 'x', queues: ['caixa', 'bar'], channels: {'bar': 'private-company.7.printer.bar'});
    expect(withChannels.channelFor('bar'), 'private-company.7.printer.bar');
  });

  test('servidor antigo (sem queues) continua com a fila principal só', () {
    final me = Me(name: 'PC', printerName: 'caixa', channel: 'private-company.7.printer.caixa');

    expect(me.queues, ['caixa']);
  });
}
