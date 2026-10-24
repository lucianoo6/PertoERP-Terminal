import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'version.dart' as version;

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
  Me({
    required this.name,
    required this.printerName,
    required this.channel,
    this.realtime,
    List<String>? queues,
    Map<String, String>? channels,
    this.stations = const [],
  })  : queues = queues == null || queues.isEmpty ? [printerName] : queues,
        channels = channels ?? {};

  /// Setores da loja para escolher ao lado de cada impressora. Servidores antigos não mandam (lista vazia).
  final List<Station> stations;

  final String name;

  /// Fila principal deste terminal.
  final String printerName;
  final String channel;
  final RealtimeInfo? realtime;

  /// Todas as filas deste computador (a principal primeiro), ex.: [caixa, cozinha, bar].
  final List<String> queues;

  /// Canal de tempo real de cada fila. Servidores antigos não mandam: o nome segue o da fila principal.
  final Map<String, String> channels;

  String channelFor(String queue) {
    final known = channels[queue];
    if (known != null && known.isNotEmpty) {
      return known;
    }
    if (queue == printerName || !channel.endsWith('.printer.$printerName')) {
      return channel;
    }

    return '${channel.substring(0, channel.length - printerName.length)}$queue';
  }
}

/// Setor de impressão da loja (Caixa, Cozinha, Bar…), cadastrado no PertoERP.
class Station {
  const Station({required this.queue, required this.name});

  final String queue;
  final String name;
}

class Job {
  Job({required this.id, required this.payload});

  final int id;
  final Map<String, dynamic> payload;
}

/// Resultado do pareamento: o token do terminal e como ele está cadastrado no PertoERP.
class Pairing {
  Pairing({required this.token, required this.name, required this.printerName});

  final String token;
  final String name;
  final String printerName;
}

/// Fala com o PertoERP: /api/v1/terminal (fila de impressão) e /api/broadcasting/auth (canal privado).
class ApiClient {
  ApiClient(String baseUrl, this.token, {bool insecureTls = false})
      : base = baseUrl.replaceFirst(RegExp(r'/+$'), ''),
        http = HttpClient()
          ..connectionTimeout = const Duration(seconds: 15)
          ..userAgent = version.userAgent {
    if (insecureTls) {
      http.badCertificateCallback = (_, _, _) => true;
    }
  }

  final String base;
  final String token;
  final HttpClient http;

  /// Troca o código de 6 dígitos mostrado no painel pelo token deste terminal (não precisa de token antes).
  static Future<Pairing> pair(String baseUrl, String code, {bool insecureTls = false}) async {
    final client = ApiClient(baseUrl, '', insecureTls: insecureTls);

    try {
      final json = await client._request('POST', '/api/v1/terminal/pair', body: jsonEncode({'code': code}), contentType: 'application/json') as Map<String, dynamic>;

      return Pairing(token: '${json['token']}', name: '${json['name'] ?? ''}', printerName: '${json['printer_name'] ?? ''}');
    } finally {
      client.close();
    }
  }

  Future<Me> me() async => _me(await _request('GET', '/api/v1/terminal/me') as Map<String, dynamic>);

  /// Avisa o PertoERP quais setores este computador imprime (o principal primeiro) e devolve o cadastro atualizado.
  Future<Me> updateQueues(List<String> queues) async => _me(await _request(
        'POST',
        '/api/v1/terminal/queues',
        body: jsonEncode({'queues': queues}),
        contentType: 'application/json',
      ) as Map<String, dynamic>);

  Me _me(Map<String, dynamic> json) {
    final realtime = json['realtime'];

    return Me(
      name: '${json['name'] ?? ''}',
      printerName: '${json['printer_name'] ?? ''}',
      channel: '${json['channel'] ?? ''}',
      queues: (json['queues'] as List? ?? []).map((queue) => '$queue').where((queue) => queue.isNotEmpty).toList(),
      channels: json['channels'] is Map ? (json['channels'] as Map).map((key, value) => MapEntry('$key', '$value')) : null,
      stations: [
        for (final station in (json['stations'] as List? ?? const []))
          if (station is Map && '${station['queue'] ?? ''}'.isNotEmpty) Station(queue: '${station['queue']}', name: '${station['name'] ?? station['queue']}'),
      ],
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

  /// Trabalhos pendentes de uma fila (sem fila: a principal do terminal).
  Future<List<Job>> pendingJobs({String? queue}) async {
    final path = queue == null || queue.isEmpty ? '/api/v1/terminal/jobs' : '/api/v1/terminal/jobs?printer=${Uri.encodeQueryComponent(queue)}';
    final json = await _request('GET', path) as Map<String, dynamic>;

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
    final uri = Uri.tryParse('$base$path');

    // O token nunca vai por conexão sem criptografia (exceto no próprio computador ou em .test, para desenvolvimento).
    if (uri == null || (uri.scheme != 'https' && !(uri.host == 'localhost' || uri.host == '127.0.0.1' || uri.host.endsWith('.test')))) {
      throw ApiException('endereço inseguro: o PertoERP só é acessado por https');
    }

    try {
      final request = await http.openUrl(method, uri);
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');
      if (token.isNotEmpty) {
        request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
      }
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
    if (response.statusCode == 429) {
      throw ApiException('muitas tentativas seguidas. Espere 1 minuto e tente de novo');
    }
    if (response.statusCode == 422) {
      throw ApiException(_message(text) ?? 'dados recusados pelo PertoERP');
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

  String? _message(String text) {
    try {
      final json = jsonDecode(text);

      return json is Map && json['message'] is String ? json['message'] as String : null;
    } on FormatException {
      return null;
    }
  }

  String _snippet(String text) {
    final trimmed = text.trim();

    return trimmed.length > 200 ? '${trimmed.substring(0, 200)}…' : trimmed;
  }
}
