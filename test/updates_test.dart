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
    expect(notified, 1);
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
