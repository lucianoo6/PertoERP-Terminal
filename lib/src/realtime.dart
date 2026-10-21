import 'dart:async';
import 'dart:convert';
import 'dart:io';

typedef Authorizer = Future<String> Function(String socketId, String channel);

/// Conexão com o Reverb (protocolo Pusher 7) para saber na hora que chegou impressão.
/// Reconecta sozinha, com espera crescente, até [stop].
class RealtimeClient {
  RealtimeClient({
    required this.uri,
    required this.channel,
    required this.authorize,
    required this.onEvent,
    required this.onState,
    this.insecureTls = false,
  });

  final Uri uri;
  final String channel;
  final Authorizer authorize;
  final void Function(String event) onEvent;
  final void Function(bool connected, Object? error) onState;
  final bool insecureTls;

  bool _running = false;
  WebSocket? _socket;
  Completer<void>? _wake;

  void start() {
    if (_running) {
      return;
    }
    _running = true;
    unawaited(_loop());
  }

  Future<void> stop() async {
    _running = false;
    _wake?.complete();
    await _socket?.close(WebSocketStatus.normalClosure);
  }

  Future<void> _loop() async {
    var backoff = const Duration(seconds: 1);

    while (_running) {
      final started = DateTime.now();
      Object? error;

      try {
        await _session();
      } catch (e) {
        error = e;
      }
      if (!_running) {
        return;
      }

      onState(false, error);

      if (DateTime.now().difference(started) > const Duration(minutes: 1)) {
        backoff = const Duration(seconds: 1);
      }

      _wake = Completer<void>();
      await Future.any([Future<void>.delayed(backoff), _wake!.future]);
      backoff = backoff * 2 > const Duration(seconds: 30) ? const Duration(seconds: 30) : backoff * 2;
    }
  }

  Future<void> _session() async {
    final client = HttpClient();
    if (insecureTls) {
      client.badCertificateCallback = (_, _, _) => true;
    }

    final WebSocket socket;
    try {
      socket = await WebSocket.connect(uri.toString(), customClient: client).timeout(const Duration(seconds: 15));
    } catch (error) {
      throw RealtimeException('tempo real indisponível em ${uri.scheme}://${uri.host}:${uri.port}: $error');
    }
    _socket = socket;

    final messages = StreamIterator(socket.map((data) => _decode(data)));
    Timer? idle;

    try {
      if (!await messages.moveNext().timeout(const Duration(seconds: 20))) {
        throw RealtimeException('o Reverb fechou a conexão');
      }

      final hello = messages.current;
      if (hello['event'] != 'pusher:connection_established') {
        throw RealtimeException('resposta inesperada do Reverb: ${hello['event']}');
      }

      final established = _unwrap(hello['data']);
      final socketId = '${established['socket_id']}';
      var activity = Duration(seconds: (established['activity_timeout'] as num?)?.toInt() ?? 30);
      if (activity <= Duration.zero || activity > const Duration(minutes: 2)) {
        activity = const Duration(seconds: 30);
      }

      final auth = await authorize(socketId, channel);
      socket.add(jsonEncode({
        'event': 'pusher:subscribe',
        'data': {'auth': auth, 'channel': channel},
      }));

      var waitingPong = false;
      Object? failure;

      void armIdle(Duration after) {
        idle?.cancel();
        idle = Timer(after, () {
          if (waitingPong) {
            failure = RealtimeException('o Reverb parou de responder');
            socket.close(WebSocketStatus.goingAway);

            return;
          }
          socket.add(jsonEncode({'event': 'pusher:ping', 'data': {}}));
          waitingPong = true;
          armIdle(const Duration(seconds: 30));
        });
      }

      armIdle(activity);

      while (await messages.moveNext()) {
        final message = messages.current;
        waitingPong = false;
        armIdle(activity);

        switch (message['event']) {
          case 'pusher_internal:subscription_succeeded':
            onState(true, null);
          case 'pusher:ping':
            socket.add(jsonEncode({'event': 'pusher:pong', 'data': {}}));
          case 'pusher:pong':
            break;
          case 'pusher:error':
            throw RealtimeException('Reverb recusou: ${jsonEncode(message['data'])}');
          default:
            if (message['channel'] == channel) {
              onEvent('${message['event']}');
            }
        }
      }

      if (failure != null) {
        throw failure!;
      }
      if (_running) {
        throw RealtimeException('conexão de tempo real caiu');
      }
    } finally {
      idle?.cancel();
      await messages.cancel();
      await socket.close();
      client.close(force: true);
      _socket = null;
    }
  }

  Map<String, dynamic> _decode(Object? data) {
    try {
      final decoded = jsonDecode('$data');

      return decoded is Map ? decoded.cast<String, dynamic>() : {};
    } on FormatException {
      return {};
    }
  }

  /// No protocolo Pusher o campo data costuma vir como texto contendo JSON.
  Map<String, dynamic> _unwrap(Object? data) {
    if (data is String) {
      try {
        final decoded = jsonDecode(data);

        return decoded is Map ? decoded.cast<String, dynamic>() : {};
      } on FormatException {
        return {};
      }
    }

    return data is Map ? data.cast<String, dynamic>() : {};
  }
}

class RealtimeException implements Exception {
  RealtimeException(this.message);

  final String message;

  @override
  String toString() => message;
}
