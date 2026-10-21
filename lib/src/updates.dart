import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

/// Versão nova publicada nos Releases do GitHub.
class AvailableUpdate {
  AvailableUpdate({required this.version, required this.notes, required this.pageUrl, this.downloadUrl, this.installerUrl});

  final String version;
  final String notes;

  /// Página de downloads do PertoERP (com o passo a passo de instalação).
  final String pageUrl;

  /// Pacote deste sistema (Windows ou Linux), quando o Release tiver.
  final String? downloadUrl;

  /// Instalador do Windows: permite atualizar com um clique, sem o lojista baixar nada.
  final String? installerUrl;

  /// Windows: pelo instalador do Release. Linux: pelo script de instalação do site, que também atualiza.
  bool get canInstall => Platform.isWindows ? installerUrl != null : Platform.isLinux;
}

/// Confere de tempos em tempos se saiu versão nova do Perto Terminal. Nunca instala nada sozinho:
/// só avisa na janela e na bandeja, e o lojista baixa quando quiser.
class UpdateChecker extends ChangeNotifier {
  UpdateChecker({
    required this.currentVersion,
    this.repository = 'lucianoo6/PertoERP-Terminal',
    this.apiBase = 'https://api.github.com',
    this.downloadsPage = 'https://pertoerp.com.br/terminal',
    this.interval = const Duration(hours: 6),
  });

  final String currentVersion;
  final String repository;
  final String apiBase;
  final String downloadsPage;
  final Duration interval;

  AvailableUpdate? _available;
  DateTime? _checkedAt;
  Timer? _timer;
  double? _installProgress;
  String? _installError;

  AvailableUpdate? get available => _available;

  /// Progresso do download do instalador (0 a 1), enquanto "Atualizar agora" roda.
  double? get installProgress => _installProgress;

  String? get installError => _installError;

  bool get installing => _installProgress != null;

  DateTime? get checkedAt => _checkedAt;

  /// Builds de desenvolvimento ("dev" ou 0.0.0-abc1234) não procuram atualização.
  bool get enabled => parseVersion(currentVersion) != null && !currentVersion.startsWith('0.0.0');

  void start({Duration firstCheckAfter = const Duration(seconds: 20)}) {
    if (!enabled) {
      return;
    }

    _timer?.cancel();
    _timer = Timer(firstCheckAfter, () {
      unawaited(check());
      _timer = Timer.periodic(interval, (_) => unawaited(check()));
    });
  }

  void stop() => _timer?.cancel();

  /// Consulta o último Release (o GitHub já ignora rascunhos e versões de teste).
  Future<AvailableUpdate?> check() async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 10);

    try {
      final request = await client.getUrl(Uri.parse('$apiBase/repos/$repository/releases/latest'));
      request.headers
        ..set(HttpHeaders.acceptHeader, 'application/vnd.github+json')
        ..set(HttpHeaders.userAgentHeader, 'PertoTerminal/$currentVersion (${Platform.operatingSystem})');

      final response = await request.close().timeout(const Duration(seconds: 15));
      final body = await response.transform(utf8.decoder).join();
      _checkedAt = DateTime.now();

      if (response.statusCode != 200) {
        return _available;
      }

      final release = jsonDecode(body) as Map<String, dynamic>;
      final version = '${release['tag_name'] ?? ''}'.replaceFirst(RegExp('^[vV]'), '');

      if (!isNewer(version, currentVersion)) {
        _set(null);

        return null;
      }

      final platform = Platform.isWindows ? 'windows' : 'linux';
      final assets = (release['assets'] as List? ?? []).cast<Map<String, dynamic>>();
      String? url(bool Function(String name) matches) =>
          assets.where((asset) => matches('${asset['name']}'.toLowerCase())).map((asset) => '${asset['browser_download_url']}').firstOrNull;

      _set(AvailableUpdate(
        version: version,
        notes: '${release['body'] ?? ''}'.trim(),
        pageUrl: downloadsPage,
        downloadUrl: url((name) => name.contains(platform) && !name.contains('instalador')),
        installerUrl: url((name) => name.contains('windows') && name.contains('instalador') && name.endsWith('.exe')),
      ));
    } catch (_) {
      // Sem internet ou GitHub fora: tenta de novo no próximo intervalo, sem incomodar.
    } finally {
      client.close(force: true);
    }

    return _available;
  }

  /// Baixa o instalador da versão nova e roda em silêncio: ele fecha este terminal, troca os arquivos
  /// e abre o novo já na bandeja. Quem chama deve encerrar o app logo depois.
  Future<void> downloadAndInstall(AvailableUpdate update) async {
    if (!update.canInstall || installing) {
      return;
    }

    _installError = null;
    _installProgress = 0;
    notifyListeners();

    if (Platform.isLinux) {
      // O script baixa a última versão, fecha este terminal, troca os arquivos e abre o novo.
      await Process.start('bash', ['-c', 'curl -fsSL "${update.pageUrl}/instalar.sh" | bash'], mode: ProcessStartMode.detached);
      _installProgress = 1;
      notifyListeners();

      return;
    }

    final installer = update.installerUrl!;

    final client = HttpClient()..connectionTimeout = const Duration(seconds: 15);
    final file = File('${Directory.systemTemp.path}${Platform.pathSeparator}PertoTerminal-${update.version}-instalador.exe');

    try {
      final response = await (await client.getUrl(Uri.parse(installer))).close();
      if (response.statusCode != 200) {
        throw HttpException('o download respondeu ${response.statusCode}');
      }

      final total = response.contentLength;
      var received = 0;
      final sink = file.openWrite();
      await for (final chunk in response) {
        sink.add(chunk);
        received += chunk.length;
        if (total > 0) {
          _installProgress = received / total;
          notifyListeners();
        }
      }
      await sink.close();

      if (total > 0 && received != total) {
        throw const HttpException('o download veio incompleto');
      }

      await Process.start(file.path, ['/VERYSILENT', '/SUPPRESSMSGBOXES', '/NORESTART'], mode: ProcessStartMode.detached);
      _installProgress = 1;
      notifyListeners();
    } catch (error) {
      _installProgress = null;
      _installError = 'Não deu para atualizar agora ($error). Tente de novo ou baixe pelo site.';
      notifyListeners();
      rethrow;
    } finally {
      client.close(force: true);
    }
  }

  void _set(AvailableUpdate? update) {
    if (update?.version == _available?.version) {
      return;
    }
    _available = update;
    notifyListeners();
  }

  /// "1.2.3" → [1, 2, 3]; aceita "1.2" e ignora sufixos como "-beta".
  static List<int>? parseVersion(String version) {
    final match = RegExp(r'^(\d+)\.(\d+)(?:\.(\d+))?').firstMatch(version.trim());
    if (match == null) {
      return null;
    }

    return [int.parse(match[1]!), int.parse(match[2]!), int.parse(match[3] ?? '0')];
  }

  static bool isNewer(String candidate, String current) {
    final a = parseVersion(candidate);
    final b = parseVersion(current);
    if (a == null || b == null) {
      return false;
    }

    for (var i = 0; i < 3; i++) {
      if (a[i] != b[i]) {
        return a[i] > b[i];
      }
    }

    return false;
  }
}

/// Abre um endereço no navegador padrão.
Future<void> openInBrowser(String url) => Platform.isWindows
    ? Process.run('rundll32', ['url.dll,FileProtocolHandler', url])
    : Process.run('xdg-open', [url]);
