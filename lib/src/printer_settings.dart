import 'config.dart';

/// Uma impressora deste computador e como ela imprime (cada fila do PertoERP pode ter a sua: caixa, cozinha, bar…).
class PrinterSettings {
  const PrinterSettings({
    this.kind = PrinterKind.windows,
    this.name = '',
    this.address = '',
    this.path = '',
    this.columns = 48,
    this.codePage = 'cp850',
    this.cut = true,
    this.openDrawer = false,
    this.copies = 1,
  });

  factory PrinterSettings.fromJson(Map<String, dynamic> json) => PrinterSettings(
        kind: PrinterKind.values.firstWhere((kind) => kind.name == json['kind'], orElse: () => PrinterKind.windows),
        name: '${json['name'] ?? ''}',
        address: '${json['address'] ?? ''}',
        path: '${json['path'] ?? ''}',
        columns: (json['columns'] as num?)?.toInt() ?? 48,
        codePage: '${json['code_page'] ?? 'cp850'}',
        cut: json['cut'] as bool? ?? true,
        openDrawer: json['open_drawer'] as bool? ?? false,
        copies: (json['copies'] as num?)?.toInt() ?? 1,
      ).normalized();

  final PrinterKind kind;

  /// Nome da impressora no Windows (ou no CUPS).
  final String name;

  /// host:porta da impressora de rede (porta 9100 quando omitida).
  final String address;
  final String path;

  /// 48 para bobina de 80 mm, 32 para 58 mm.
  final int columns;
  final String codePage;
  final bool cut;

  /// Abre a gaveta quando a venda tem pagamento em dinheiro.
  final bool openDrawer;
  final int copies;

  bool get ready => switch (kind) {
        PrinterKind.windows => name.isNotEmpty,
        PrinterKind.network => address.isNotEmpty,
        PrinterKind.file => path.isNotEmpty,
      };

  PrinterSettings normalized() => copyWith(
        columns: columns < 24 || columns > 64 ? 48 : columns,
        codePage: codePage.isEmpty ? 'cp850' : codePage,
        copies: copies < 1 || copies > 5 ? 1 : copies,
      );

  PrinterSettings copyWith({
    PrinterKind? kind,
    String? name,
    String? address,
    String? path,
    int? columns,
    String? codePage,
    bool? cut,
    bool? openDrawer,
    int? copies,
  }) =>
      PrinterSettings(
        kind: kind ?? this.kind,
        name: name ?? this.name,
        address: address ?? this.address,
        path: path ?? this.path,
        columns: columns ?? this.columns,
        codePage: codePage ?? this.codePage,
        cut: cut ?? this.cut,
        openDrawer: openDrawer ?? this.openDrawer,
        copies: copies ?? this.copies,
      );

  Map<String, dynamic> toJson() => {
        'kind': kind.name,
        if (name.isNotEmpty) 'name': name,
        if (address.isNotEmpty) 'address': address,
        if (path.isNotEmpty) 'path': path,
        'columns': columns,
        'code_page': codePage,
        'cut': cut,
        'open_drawer': openDrawer,
        'copies': copies,
      };
}
