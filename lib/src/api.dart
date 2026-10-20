import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// Token inválido, revogado ou terminal desativado no painel.
class UnauthorizedException implements Exception {
  @override
  String toString() => 'terminal não autorizado: confira o token ou se ele está ativo no PertoERP';
}

class ApiException implements Exception {
  ApiException(this.message);

  final String message;

  @override
  String toString() => message;
}

class RealtimeInfo {
  RealtimeInfo({required this.key, required this.host, required this.port, required this.scheme});

  final String key;
  final String host;
  final int port;
  final String scheme;

  /// Endereço do WebSocket do Reverb (protocolo Pusher 7).
  Uri get uri => Uri.parse('${scheme == 'http' ? 'ws' : 'wss'}://$host:$port/app/${Uri.encodeComponent(key)}'
      '?protocol=7&client=perto-terminal-flutter&version=1.0&flash=false');
}

class Me {
  Me({required this.name, required this.printerName, required this.channel, this.realtime});

  final String name;
  final String printerName;
  final String channel;
  final RealtimeInfo? realtime;
}

class Job {
  Job({required this.id, required this.payload});

  final int id;
  final Map<String, dynamic> payload;
}

/// Fala com o PertoERP: /api/v1/terminal (fila de impressão) e /api/broadcasting/auth (canal privado).
class ApiClient {
  ApiClient(String baseUrl, this.token, {bool insecureTls = false})
      : base = baseUrl.replaceFirst(RegExp(r'/+$'), ''),
        http = HttpClient()
          ..connectionTimeout = const Duration(seconds: 15)
          ..userAgent = 'PertoTerminal-Flutter' {
    if (insecureTls) {
      http.badCertificateCallback = (_, _, _) => true;
    }
  }

  final String base;
  final String token;
  final HttpClient http;

  Future<Me> me() async {
    final json = await _request('GET', '/api/v1/terminal/me') as Map<String, dynamic>;
    final realtime = json['realtime'];

    return Me(
      name: '${json['name'] ?? ''}',
      printerName: '${json['printer_name'] ?? ''}',
      channel: '${json['channel'] ?? ''}',
      realtime: realtime is Map && '${realtime['key'] ?? ''}'.isNotEmpty
          ? RealtimeInfo(
              key: '${realtime['key']}',
              host: '${realtime['host']}',
              port: (realtime['port'] as num?)?.toInt() ?? 443,
              scheme: '${realtime['scheme'] ?? 'https'}',
            )
          : null,
    );
  }

  Future<List<Job>> pendingJobs() async {
    final json = await _request('GET', '/api/v1/terminal/jobs') as Map<String, dynamic>;

    return [
      for (final job in (json['data'] as List? ?? []).cast<Map<String, dynamic>>())
        Job(id: (job['id'] as num).toInt(), payload: _payload(job['payload'])),
    ];
  }

  /// Confirma a impressão ou registra a falha com a mensagem para o painel.
  Future<void> report(int jobId, {required bool printed, String message = ''}) => _request(
        'POST',
        '/api/v1/terminal/jobs/$jobId/status',
        body: jsonEncode(printed
            ? {'status': 'printed'}
            : {'status': 'failed', 'error_message': message.length > 1000 ? message.substring(0, 1000) : message}),
        contentType: 'application/json',
      );

  /// Assina a inscrição no canal privado do Reverb.
  Future<String> authorizeChannel(String socketId, String channel) async {
    final json = await _request(
      'POST',
      '/api/broadcasting/auth',
      body: Uri(queryParameters: {'socket_id': socketId, 'channel_name': channel}).query,
      contentType: 'application/x-www-form-urlencoded',
    ) as Map<String, dynamic>;

    final auth = '${json['auth'] ?? ''}';
    if (auth.isEmpty) {
      throw ApiException('autorização do canal veio vazia');
    }

    return auth;
  }

  void close() => http.close(force: true);

  /// Aceita o cupom como objeto ou gravado como texto JSON.
  Map<String, dynamic> _payload(Object? raw) {
    if (raw is String) {
      final decoded = jsonDecode(raw);

      return decoded is Map ? decoded.cast<String, dynamic>() : {};
    }

    return raw is Map ? raw.cast<String, dynamic>() : {};
  }

  Future<Object?> _request(String method, String path, {String? body, String? contentType}) async {
    final HttpClientResponse response;
    final String text;

    try {
      final request = await http.openUrl(method, Uri.parse('$base$path'));
      request.headers
        ..set(HttpHeaders.authorizationHeader, 'Bearer $token')
        ..set(HttpHeaders.acceptHeader, 'application/json');
      if (contentType != null) {
        request.headers.set(HttpHeaders.contentTypeHeader, contentType);
      }
      if (body != null) {
        request.write(body);
      }

      response = await request.close().timeout(const Duration(seconds: 20));
      text = await response.transform(utf8.decoder).join().timeout(const Duration(seconds: 20));
    } on TimeoutException {
      throw ApiException('sem conexão com o servidor: tempo esgotado');
    } on SocketException catch (error) {
      throw ApiException('sem conexão com o servidor: ${error.message}');
    } on HandshakeException catch (error) {
      throw ApiException('certificado do servidor recusado: ${error.message}');
    } on FormatException {
      throw ApiException('endereço do PertoERP inválido');
    }

    if (response.statusCode == 401 || response.statusCode == 403) {
      throw UnauthorizedException();
    }
    if (response.statusCode >= 300) {
      throw ApiException('servidor respondeu ${response.statusCode}: ${_snippet(text)}');
    }
    if (text.trim().isEmpty) {
      return null;
    }

    try {
      return jsonDecode(text);
    } on FormatException {
      throw ApiException('resposta inesperada do servidor (é o endereço do PertoERP?): ${_snippet(text)}');
    }
  }

  String _snippet(String text) {
    final trimmed = text.trim();

    return trimmed.length > 200 ? '${trimmed.substring(0, 200)}…' : trimmed;
  }
}
