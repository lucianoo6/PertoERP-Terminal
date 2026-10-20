import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:perto_terminal/src/updates.dart';

void main() {
  late HttpServer github;
  late Map<String, dynamic>? latest;
  late int status;

  setUp(() async {
    latest = null;
    status = 200;
    github = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    github.listen((request) async {
      request.response.statusCode = latest == null ? 404 : status;
      request.response.write(jsonEncode(latest ?? {'message': 'Not Found'}));
      await request.response.close();
    });
  });

  tearDown(() => github.close(force: true));

  UpdateChecker checker(String current) => UpdateChecker(currentVersion: current, apiBase: 'http://${github.address.host}:${github.port}');

  Map<String, dynamic> release(String tag) => {
        'tag_name': tag,
        'body': '## Novidades\n- Aviso quando acaba o papel\n\n**Full Changelog**: ...',
        'assets': [
          {'name': 'PertoTerminal-${tag.substring(1)}-windows-instalador.exe', 'browser_download_url': 'https://github.com/dl/setup.exe'},
          {'name': 'PertoTerminal-${tag.substring(1)}-windows-x64.zip', 'browser_download_url': 'https://github.com/dl/win.zip'},
          {'name': 'PertoTerminal-${tag.substring(1)}-linux-x64.tar.gz', 'browser_download_url': 'https://github.com/dl/linux.tar.gz'},
        ],
      };

  test('avisa quando saiu versão mais nova, com o pacote deste sistema', () async {
    latest = release('v1.1.0');
    final updates = checker('1.0.0');
    var notified = 0;
    updates.addListener(() => notified++);

    final update = await updates.check();

    expect(update?.version, '1.1.0');
    expect(update?.downloadUrl, Platform.isWindows ? 'https://github.com/dl/win.zip' : 'https://github.com/dl/linux.tar.gz');
    expect(update?.pageUrl, 'https://pertoerp.com.br/terminal');
    expect(update?.installerUrl, 'https://github.com/dl/setup.exe');
    expect(update?.canInstall, Platform.isWindows || Platform.isLinux);
    expect(notified, 1);
  });

  test('sem instalador no Release, o aviso oferece só o download', () async {
    latest = release('v1.1.0')..['assets'] = (release('v1.1.0')['assets'] as List).where((asset) => !'${asset['name']}'.contains('instalador')).toList();

    final update = await checker('1.0.0').check();

    expect(update?.installerUrl, isNull);
    expect(update?.canInstall, Platform.isLinux);
  });

  test('falha no download do instalador vira uma mensagem simples, sem fechar o terminal', () async {
    final updates = checker('1.0.0');
    final update = AvailableUpdate(version: '9.9.9', notes: '', pageUrl: '', installerUrl: 'http://${github.address.host}:${github.port}/nao-existe.exe');

    if (!Platform.isWindows) {
      return; // No Linux a atualização vai pelo script do site.
    }

    await expectLater(updates.downloadAndInstall(update), throwsA(isA<HttpException>()));
    expect(updates.installing, isFalse);
    expect(updates.installError, contains('Não deu para atualizar agora'));
  });

  test('fica quieto na versão mais nova, sem internet ou sem nenhum Release', () async {
    latest = release('v1.0.0');
    expect(await checker('1.0.0').check(), isNull);

    latest = null;
    expect(await checker('1.0.0').check(), isNull);

    final offline = checker('1.0.0');
    await github.close(force: true);
    expect(await offline.check(), isNull);
  });

  test('compara versões pelo número, não pelo texto', () {
    expect(UpdateChecker.isNewer('1.10.0', '1.9.3'), isTrue);
    expect(UpdateChecker.isNewer('2.0', '1.99.99'), isTrue);
    expect(UpdateChecker.isNewer('1.0.0', '1.0.0'), isFalse);
    expect(UpdateChecker.isNewer('1.0.1', '1.1.0'), isFalse);
    expect(UpdateChecker.isNewer('lixo', '1.0.0'), isFalse);
  });

  test('build de desenvolvimento não procura atualização', () {
    expect(checker('dev').enabled, isFalse);
    expect(checker('0.0.0-abc1234').enabled, isFalse);
    expect(checker('1.0.0').enabled, isTrue);
  });
}
