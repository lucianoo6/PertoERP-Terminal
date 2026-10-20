import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

/// Versão nova publicada nos Releases do GitHub.
class AvailableUpdate {
  AvailableUpdate({required this.version, required this.notes, required this.pageUrl, this.downloadUrl});

  final String version;
  final String notes;

  /// Página de downloads do PertoERP (com o passo a passo de instalação).
  final String pageUrl;

  /// Pacote deste sistema (Windows ou Linux), quando o Release tiver.
  final String? downloadUrl;
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

  AvailableUpdate? get available => _available;

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
        ..set(HttpHeaders.userAgentHeader, 'PertoTerminal/$currentVersion');

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
      final asset = (release['assets'] as List? ?? [])
          .cast<Map<String, dynamic>>()
          .where((asset) => '${asset['name']}'.toLowerCase().contains(platform))
          .firstOrNull;

      _set(AvailableUpdate(
        version: version,
        notes: '${release['body'] ?? ''}'.trim(),
        pageUrl: downloadsPage,
        downloadUrl: asset == null ? null : '${asset['browser_download_url']}',
      ));
    } catch (_) {
      // Sem internet ou GitHub fora: tenta de novo no próximo intervalo, sem incomodar.
    } finally {
      client.close(force: true);
    }

    return _available;
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
