import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:perto_terminal/src/api.dart';
import 'package:perto_terminal/src/config.dart';
import 'package:perto_terminal/src/version.dart';

void main() {
  late HttpServer server;
  late int status;
  late Map<String, dynamic> body;
  Map<String, dynamic>? received;
  String? authorization;

  setUp(() async {
    status = 200;
    body = {'token': '7|abc', 'name': 'Caixa 1', 'printer_name': 'caixa'};
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      authorization = request.headers.value(HttpHeaders.authorizationHeader);
      received = jsonDecode(await utf8.decoder.bind(request).join()) as Map<String, dynamic>;
      request.response
        ..statusCode = status
        ..headers.contentType = ContentType.json
        ..write(jsonEncode(body));
      await request.response.close();
    });
  });

  tearDown(() async {
    TerminalConfig.allowCustomServer = isDevBuild;
    await server.close(force: true);
  });

  String url() => 'http://${server.address.host}:${server.port}';

  test('troca o código pelo token, sem mandar token nenhum antes', () async {
    final pairing = await ApiClient.pair(url(), '482913');

    expect(received, {'code': '482913'});
    expect(authorization, isNull);
    expect(pairing.token, '7|abc');
    expect(pairing.name, 'Caixa 1');
    expect(pairing.printerName, 'caixa');
  });

  test('mostra a mensagem do PertoERP quando o código está errado ou vencido', () async {
    status = 422;
    body = {'message': 'Código inválido ou vencido. Gere um novo no PertoERP.'};

    await expectLater(ApiClient.pair(url(), '000000'), throwsA(predicate((e) => '$e' == 'Código inválido ou vencido. Gere um novo no PertoERP.')));
  });

  test('avisa para esperar quando passou do limite de tentativas', () async {
    status = 429;
    body = {'message': 'Too Many Attempts.'};

    await expectLater(ApiClient.pair(url(), '000000'), throwsA(predicate((e) => '$e'.contains('Espere 1 minuto'))));
  });

  test('na versão publicada o endereço é sempre o oficial e sem certificado de teste', () {
    TerminalConfig.allowCustomServer = false;

    final config = const TerminalConfig(serverUrl: 'https://golpe.example.com', insecureTls: true, token: 't').normalized();

    expect(config.serverUrl, officialServer);
    expect(config.insecureTls, isFalse);
    expect(const TerminalConfig().normalized().serverUrl, 'https://pertoerp.com.br');
  });

  test('nunca manda o token por http para outro computador', () async {
    final client = ApiClient('http://pertoerp.com.br', 'segredo');

    await expectLater(client.me(), throwsA(predicate((e) => '$e'.contains('só é acessado por https'))));
    client.close();
  });
}
