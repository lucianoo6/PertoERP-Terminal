import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:perto_terminal/src/config.dart';
import 'package:perto_terminal/src/printer.dart';
import 'package:perto_terminal/src/service.dart';
import 'package:perto_terminal/src/ticket.dart';

class _FakePrinter implements TicketPrinter {
  final printed = <Uint8List>[];
  Object? failWith;

  @override
  Future<void> print(String document, Uint8List data) async {
    if (failWith != null) {
      throw failWith!;
    }
    printed.add(data);
  }
}

/// PertoERP de mentira: /me, a fila e o registro de status.
class _FakeServer {
  late HttpServer server;
  final reports = <Map<String, dynamic>>[];
  final jobs = <Map<String, dynamic>>[];
  String? lastAuthorization;
  int status = 200;

  String get url => 'http://${server.address.host}:${server.port}';

  Future<void> start() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      lastAuthorization = request.headers.value(HttpHeaders.authorizationHeader);
      final body = await utf8.decoder.bind(request).join();
      request.response.headers.contentType = ContentType.json;

      if (status != 200) {
        request.response.statusCode = status;
      } else if (request.uri.path == '/api/v1/terminal/me') {
        request.response.write(jsonEncode({'id': 1, 'name': 'Caixa 1', 'printer_name': 'caixa', 'channel': '', 'realtime': null}));
      } else if (request.uri.path == '/api/v1/terminal/jobs') {
        request.response.write(jsonEncode({'data': jobs}));
      } else if (request.uri.path.endsWith('/status')) {
        final report = (jsonDecode(body) as Map<String, dynamic>)..['id'] = int.parse(request.uri.pathSegments[4]);
        reports.add(report);
        jobs.removeWhere((job) => job['id'] == report['id'] && report['status'] == 'printed');
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
  late _FakeServer api;
  late _FakePrinter printer;
  late TerminalService service;

  setUp(() async {
    api = _FakeServer();
    await api.start();
    printer = _FakePrinter();
    service = TerminalService(
      TerminalConfig(serverUrl: api.url, token: 'secret', printerName: 'Elgin i9', pollSeconds: 2),
      openPrinter: (_) => printer,
    );
  });

  tearDown(() async {
    await service.stop();
    await api.server.close(force: true);
  });

  test('busca a fila, imprime e confirma cada cupom uma vez só', () async {
    api.jobs.add({'id': 7, 'printer_name': 'caixa', 'status': 'pending', 'payload': jsonEncode({'header': {'store_name': 'Loja'}, 'items': [], 'totals': {'total': 10}})});

    service.start();
    await _eventually(() => api.reports.isNotEmpty);

    expect(api.lastAuthorization, 'Bearer secret');
    expect(printer.printed, hasLength(1));
    expect(api.reports.single, {'status': 'printed', 'id': 7});
    expect(service.status.device, 'Caixa 1');
    expect(service.status.printed, 1);
    expect(service.status.health, Health.degraded); // sem Reverb informado: imprime por consulta
  });

  test('avisa o PertoERP quando a impressora falha', () async {
    printer.failWith = Exception('impressora sem papel');
    api.jobs.add({'id': 9, 'payload': {'items': []}});

    service.start();
    await _eventually(() => api.reports.isNotEmpty);

    expect(api.reports.first['status'], 'failed');
    expect(api.reports.first['error_message'], contains('sem papel'));
    expect(service.status.lastError, contains('Impressão'));
    expect(service.status.health, Health.error);
  });

  test('token recusado aparece como problema de autorização', () async {
    api.status = 401;

    service.start();
    await _eventually(() => service.status.lastError.isNotEmpty);

    expect(service.status.lastError, contains('não autorizado'));
    expect(service.status.connected, isFalse);
  });

  test('página de teste respeita as vias e só abre a gaveta na primeira', () async {
    await service.testPrint(TerminalConfig(serverUrl: api.url, token: 't', printerName: 'x', copies: 2, openDrawer: true));

    expect(printer.printed, hasLength(2));
    final drawer = [0x1b, 0x70, 0, 25, 250];
    bool hasDrawer(Uint8List bytes) => String.fromCharCodes(bytes).contains(String.fromCharCodes(drawer));
    expect(hasDrawer(printer.printed[0]), isTrue);
    expect(hasDrawer(printer.printed[1]), isFalse);
    expect(printer.printed[1], renderTicket(samplePayload(), const RenderOptions(columns: 48, codePage: 'cp850', cut: true)));
  });
}
