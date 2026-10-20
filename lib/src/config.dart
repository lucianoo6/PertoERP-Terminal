import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'win_native.dart' as win;

/// Para onde vão os bytes ESC/POS.
enum PrinterKind { windows, network, file }

class TerminalConfig {
  const TerminalConfig({
    this.serverUrl = '',
    this.token = '',
    this.printerKind = PrinterKind.windows,
    this.printerName = '',
    this.printerAddress = '',
    this.printerPath = '',
    this.columns = 48,
    this.codePage = 'cp850',
    this.cut = true,
    this.openDrawer = false,
    this.copies = 1,
    this.insecureTls = false,
    this.pollSeconds = 5,
  });

  /// Mesmo formato de arquivo da versão em Go (o token vai cifrado pelo DPAPI).
  factory TerminalConfig.fromJson(Map<String, dynamic> json) {
    final printer = json['printer'] is Map ? (json['printer'] as Map).cast<String, dynamic>() : const <String, dynamic>{};

    return TerminalConfig(
      serverUrl: '${json['server_url'] ?? ''}',
      token: _unseal('${json['token'] ?? ''}'),
      printerKind: PrinterKind.values.firstWhere((kind) => kind.name == printer['kind'], orElse: () => PrinterKind.windows),
      printerName: '${printer['name'] ?? ''}',
      printerAddress: '${printer['address'] ?? ''}',
      printerPath: '${printer['path'] ?? ''}',
      columns: (json['columns'] as num?)?.toInt() ?? 48,
      codePage: '${json['code_page'] ?? 'cp850'}',
      cut: json['cut'] as bool? ?? true,
      openDrawer: json['open_drawer'] as bool? ?? false,
      copies: (json['copies'] as num?)?.toInt() ?? 1,
      insecureTls: json['insecure_tls'] as bool? ?? false,
      pollSeconds: (json['poll_seconds'] as num?)?.toInt() ?? 5,
    ).normalized();
  }

  final String serverUrl;
  final String token;
  final PrinterKind printerKind;
  final String printerName;

  /// host:porta da impressora de rede (porta 9100 quando omitida).
  final String printerAddress;
  final String printerPath;

  /// 48 para bobina de 80 mm, 32 para 58 mm.
  final int columns;
  final String codePage;
  final bool cut;

  /// Abre a gaveta quando a venda tem pagamento em dinheiro.
  final bool openDrawer;
  final int copies;

  /// Só para testes com certificado local.
  final bool insecureTls;

  /// Intervalo de consulta quando o tempo real está fora.
  final int pollSeconds;

  bool get printerReady => switch (printerKind) {
        PrinterKind.windows => printerName.isNotEmpty,
        PrinterKind.network => printerAddress.isNotEmpty,
        PrinterKind.file => printerPath.isNotEmpty,
      };

  /// Já dá para falar com o servidor e imprimir.
  bool get configured => serverUrl.isNotEmpty && token.isNotEmpty && printerReady;

  TerminalConfig normalized() => copyWith(
        serverUrl: serverUrl.trim().replaceFirst(RegExp(r'/+$'), ''),
        token: token.trim(),
        columns: columns < 24 || columns > 64 ? 48 : columns,
        codePage: codePage.isEmpty ? 'cp850' : codePage,
        copies: copies < 1 || copies > 5 ? 1 : copies,
        pollSeconds: pollSeconds < 2 || pollSeconds > 120 ? 5 : pollSeconds,
      );

  TerminalConfig copyWith({
    String? serverUrl,
    String? token,
    PrinterKind? printerKind,
    String? printerName,
    String? printerAddress,
    String? printerPath,
    int? columns,
    String? codePage,
    bool? cut,
    bool? openDrawer,
    int? copies,
    bool? insecureTls,
    int? pollSeconds,
  }) =>
      TerminalConfig(
        serverUrl: serverUrl ?? this.serverUrl,
        token: token ?? this.token,
        printerKind: printerKind ?? this.printerKind,
        printerName: printerName ?? this.printerName,
        printerAddress: printerAddress ?? this.printerAddress,
        printerPath: printerPath ?? this.printerPath,
        columns: columns ?? this.columns,
        codePage: codePage ?? this.codePage,
        cut: cut ?? this.cut,
        openDrawer: openDrawer ?? this.openDrawer,
        copies: copies ?? this.copies,
        insecureTls: insecureTls ?? this.insecureTls,
        pollSeconds: pollSeconds ?? this.pollSeconds,
      );

  Map<String, dynamic> toJson() => {
        'server_url': serverUrl,
        if (token.isNotEmpty) 'token': _seal(token),
        'printer': {
          'kind': printerKind.name,
          if (printerName.isNotEmpty) 'name': printerName,
          if (printerAddress.isNotEmpty) 'address': printerAddress,
          if (printerPath.isNotEmpty) 'path': printerPath,
        },
        'columns': columns,
        'code_page': codePage,
        'cut': cut,
        'open_drawer': openDrawer,
        'copies': copies,
        'insecure_tls': insecureTls,
        'poll_seconds': pollSeconds,
      };

  /// Pasta própria desta versão, para poder rodar lado a lado com o Perto Terminal em Go.
  static Directory get directory => Directory('${Platform.environment['APPDATA'] ?? '.'}\\PertoTerminalFlutter');

  static File get file => File('${directory.path}\\config.json');

  static TerminalConfig load() {
    try {
      if (!file.existsSync()) {
        return const TerminalConfig();
      }

      return TerminalConfig.fromJson(jsonDecode(file.readAsStringSync()) as Map<String, dynamic>);
    } catch (_) {
      return const TerminalConfig();
    }
  }

  void save() {
    directory.createSync(recursive: true);
    final temp = File('${file.path}.tmp')..writeAsStringSync(const JsonEncoder.withIndent('  ').convert(normalized().toJson()));
    temp.renameSync(file.path);
  }

  static String _seal(String token) {
    if (!Platform.isWindows) {
      return 'plain:$token';
    }

    return 'dpapi:${base64Encode(win.protect(Uint8List.fromList(utf8.encode(token))))}';
  }

  /// Outro usuário ou computador: o token precisa ser informado de novo.
  static String _unseal(String sealed) {
    try {
      if (sealed.startsWith('dpapi:')) {
        return utf8.decode(win.unprotect(base64Decode(sealed.substring(6))));
      }
      if (sealed.startsWith('plain:')) {
        return sealed.substring(6);
      }
    } catch (_) {
      return '';
    }

    return '';
  }
}
