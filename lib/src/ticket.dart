import 'dart:typed_data';

import 'escpos.dart';

/// JSON da fila de impressão (contrato v2 do PertoERP).
class Payload {
  Payload({
    this.version = 2,
    this.documentType = '',
    this.header = const Header(),
    this.customer = const Customer(),
    this.items = const [],
    this.totals = const Totals(),
    this.payments = const [],
    this.fiscal,
    this.footer = const Footer(),
    this.lines = const [],
  });

  factory Payload.fromJson(Map<String, dynamic> json) => Payload(
        version: _int(json['version']),
        documentType: _str(json['document_type']),
        header: Header.fromJson(_map(json['header'])),
        customer: Customer.fromJson(_map(json['customer'])),
        items: _list(json['items']).map((item) => Item.fromJson(_map(item))).toList(),
        totals: Totals.fromJson(_map(json['totals'])),
        payments: _list(json['payments']).map((payment) => Payment.fromJson(_map(payment))).toList(),
        fiscal: json['fiscal'] is Map ? Fiscal.fromJson(_map(json['fiscal'])) : null,
        footer: Footer.fromJson(_map(json['footer'])),
        lines: _list(json['lines']).map((line) => ReportLine.fromJson(_map(line))).toList(),
      );

  final int version;
  final String documentType;
  final Header header;
  final Customer customer;
  final List<Item> items;
  final Totals totals;
  final List<Payment> payments;
  final Fiscal? fiscal;
  final Footer footer;

  /// Linhas livres de um relatório (fechamento de caixa e outros), quando document_type é "report".
  final List<ReportLine> lines;

  bool get isReport => documentType == 'report';

  /// Só imprime como DANFE NFC-e quando há nota e o conteúdo do QR Code.
  bool get isDanfe => fiscal != null && fiscal!.key.isNotEmpty;
}

/// Uma linha de relatório: texto à esquerda, valor à direita (opcional) e um estilo.
class ReportLine {
  const ReportLine({this.text = '', this.right = '', this.bold = false, this.align = 'left', this.style = ''});

  factory ReportLine.fromJson(Map<String, dynamic> json) => ReportLine(
        text: _str(json['text']),
        right: _str(json['right']),
        bold: json['bold'] == true,
        align: _str(json['align']).isEmpty ? 'left' : _str(json['align']),
        style: _str(json['style']),
      );

  final String text, right, align;
  final bool bold;

  /// rule (traço), space (linha em branco), signature (linha para assinar), small (fonte menor) ou vazio.
  final String style;
}

class Header {
  const Header({
    this.storeName = '',
    this.legalName = '',
    this.document = '',
    this.stateRegistration = '',
    this.address = '',
    this.phone = '',
    this.orderNumber = '',
    this.dateTime = '',
    this.title = '',
  });

  factory Header.fromJson(Map<String, dynamic> json) => Header(
        storeName: _str(json['store_name']),
        legalName: _str(json['legal_name']),
        document: _str(json['document']),
        stateRegistration: _str(json['state_registration']),
        address: _str(json['address']),
        phone: _str(json['phone']),
        orderNumber: _str(json['order_number']),
        dateTime: _str(json['date_time']),
        title: _str(json['title']),
      );

  final String storeName, legalName, document, stateRegistration, address, phone, orderNumber, dateTime, title;
}

class Customer {
  const Customer({this.name = '', this.document = '', this.phone = ''});

  factory Customer.fromJson(Map<String, dynamic> json) =>
      Customer(name: _str(json['name']), document: _str(json['document']), phone: _str(json['phone']));

  final String name, document, phone;
}

class Item {
  const Item({
    this.number = 0,
    this.code = '',
    this.name = '',
    this.quantity = 0,
    this.unit = '',
    this.unitPrice = 0,
    this.totalPrice = 0,
    this.notes = '',
  });

  factory Item.fromJson(Map<String, dynamic> json) => Item(
        number: _int(json['number']),
        code: _str(json['code']),
        name: _str(json['name']),
        quantity: _num(json['quantity']),
        unit: _str(json['unit']),
        unitPrice: _num(json['unit_price']),
        totalPrice: _num(json['total_price']),
        notes: _str(json['notes']),
      );

  final int number;
  final String code, name, unit, notes;
  final double quantity, unitPrice, totalPrice;
}

class Totals {
  const Totals({this.itemsCount = 0, this.subtotal = 0, this.discount = 0, this.change = 0, this.total = 0});

  factory Totals.fromJson(Map<String, dynamic> json) => Totals(
        itemsCount: _int(json['items_count']),
        subtotal: _num(json['subtotal']),
        discount: _num(json['discount']),
        change: _num(json['change']),
        total: _num(json['total']),
      );

  final int itemsCount;
  final double subtotal, discount, change, total;
}

class Payment {
  const Payment({this.method = '', this.amount = 0});

  factory Payment.fromJson(Map<String, dynamic> json) => Payment(method: _str(json['method']), amount: _num(json['amount']));

  final String method;
  final double amount;
}

class Fiscal {
  const Fiscal({
    this.model = '',
    this.number = '',
    this.series = '',
    this.key = '',
    this.keyFormatted = '',
    this.protocol = '',
    this.authorizedAt = '',
    this.environment = 0,
    this.contingency = false,
    this.qrCode = '',
    this.consultaUrl = '',
    this.consumer = '',
    this.messages = const [],
  });

  factory Fiscal.fromJson(Map<String, dynamic> json) => Fiscal(
        model: _str(json['model']),
        number: _str(json['number']),
        series: _str(json['series']),
        key: _str(json['key']),
        keyFormatted: _str(json['key_formatted']),
        protocol: _str(json['protocol']),
        authorizedAt: _str(json['authorized_at']),
        environment: _int(json['environment']),
        contingency: json['contingency'] == true,
        qrCode: _str(json['qr_code']),
        consultaUrl: _str(json['consulta_url']),
        consumer: _str(json['consumer']),
        messages: _list(json['messages']).map(_str).toList(),
      );

  final String model, number, series, key, keyFormatted, protocol, authorizedAt, qrCode, consultaUrl, consumer;
  final int environment;
  final bool contingency;
  final List<String> messages;
}

class Footer {
  const Footer({this.message = '', this.systemInfo = ''});

  factory Footer.fromJson(Map<String, dynamic> json) => Footer(message: _str(json['message']), systemInfo: _str(json['system_info']));

  final String message, systemInfo;
}

/// Opções de impressão vindas da configuração.
class RenderOptions {
  const RenderOptions({this.columns = 48, this.codePage = 'cp850', this.cut = true, this.openDrawer = false});

  final int columns;
  final String codePage;
  final bool cut;
  final bool openDrawer;
}

/// Monta o DANFE NFC-e (venda com nota) ou o comprovante sem valor fiscal, igual ao terminal em Go.
Uint8List renderTicket(Payload p, RenderOptions options) => _Layout(EscPos(options.codePage), options.columns <= 0 ? 48 : options.columns).render(p, options);

class _Layout {
  _Layout(this.w, this.cols);

  final EscPos w;
  final int cols;

  Uint8List render(Payload p, RenderOptions options) {
    if (p.isReport) {
      return report(p, options);
    }

    if (options.openDrawer && p.payments.any((payment) => payment.method.toUpperCase().contains('DINHEIRO'))) {
      w.openDrawer();
    }

    header(p);

    if (p.isDanfe) {
      center(true, ['Documento Auxiliar da Nota Fiscal', 'de Consumidor Eletrônica']);
    } else {
      final title = p.header.title.isEmpty ? 'COMPROVANTE DE VENDA - NÃO É DOCUMENTO FISCAL' : p.header.title;
      center(true, wrap(title, cols));
    }
    rule();

    items(p);
    totals(p);

    if (p.isDanfe) {
      fiscal(p);
    } else {
      receiptFooter(p);
    }

    footer(p);

    w.feed(4);
    if (options.cut) {
      w.cut();
    }

    return w.bytes();
  }

  /// Relatório (ex.: fechamento de caixa): cabeçalho da loja, título, data e as linhas livres.
  Uint8List report(Payload p, RenderOptions options) {
    header(p);
    center(true, wrap(p.header.title.isEmpty ? 'RELATÓRIO' : p.header.title, cols));
    if (p.header.dateTime.isNotEmpty) {
      center(false, ['Emitido em ${p.header.dateTime}']);
    }
    rule();

    for (final line in p.lines) {
      switch (line.style) {
        case 'rule':
          rule();
        case 'space':
          w.feed(1);
        case 'signature':
          w.feed(3);
          center(false, ['_' * (cols * 2 ~/ 3), if (line.text.isNotEmpty) line.text]);
        default:
          w.align(line.align == 'center' ? EscAlign.center : EscAlign.left).bold(line.bold);
          if (line.style == 'small') {
            w.condensed(true);
          }
          if (line.right.isNotEmpty) {
            w.line(columns(line.text, line.right, cols));
          } else {
            for (final part in wrap(line.text, cols)) {
              w.line(part);
            }
          }
          if (line.style == 'small') {
            w.condensed(false);
          }
          w.bold(false).align(EscAlign.left);
      }
    }

    footer(p);
    w.feed(4);
    if (options.cut) {
      w.cut();
    }

    return w.bytes();
  }

  void header(Payload p) {
    final h = p.header;

    w.align(EscAlign.center).bold(true);
    for (final line in wrap(h.storeName, cols)) {
      w.line(line);
    }
    w.bold(false);

    if (h.legalName.isNotEmpty && h.legalName.toLowerCase() != h.storeName.toLowerCase()) {
      center(false, wrap(h.legalName, cols));
    }

    final docs = [h.document, h.stateRegistration].where((value) => value.trim().isNotEmpty).join('  ').trim();
    if (docs.isNotEmpty) {
      center(false, wrap(docs, cols));
    }
    if (h.address.isNotEmpty) {
      center(false, wrap(h.address, cols));
    }
    if (h.phone.isNotEmpty) {
      center(false, [h.phone]);
    }
    rule();
  }

  void items(Payload p) {
    w.align(EscAlign.left).bold(true);
    w.line(truncate('#   CÓDIGO  DESCRIÇÃO', cols));
    w.line(columns('QTD UN x VL UNIT', 'VL TOTAL', cols));
    w.bold(false);

    for (var i = 0; i < p.items.length; i++) {
      final item = p.items[i];
      final number = item.number == 0 ? i + 1 : item.number;
      final unit = item.unit.isEmpty ? 'UN' : item.unit;

      final prefix = '${number.toString().padLeft(3, '0')} ${item.code} ';
      final lines = wrap(prefix + item.name, cols);
      for (var j = 0; j < lines.length; j++) {
        w.line(truncate(j > 0 ? '    ${lines[j]}' : lines[j], cols));
      }
      if (item.notes.isNotEmpty) {
        for (final line in wrap('Obs.: ${item.notes}', cols - 4)) {
          w.line('    $line');
        }
      }

      w.line(columns('    ${quantity(item.quantity)} $unit x ${money(item.unitPrice)}', money(item.totalPrice), cols));
    }
    rule();
  }

  void totals(Payload p) {
    final t = p.totals;
    final count = t.itemsCount == 0 ? p.items.length : t.itemsCount;
    final subtotal = t.subtotal == 0 ? t.total + t.discount : t.subtotal;

    w.align(EscAlign.left);
    w.line(columns('Qtde. total de itens', '$count', cols));
    w.line(columns('Valor total R\$', money(subtotal), cols));
    if (t.discount > 0.004) {
      w.line(columns('Desconto R\$', '-${money(t.discount)}', cols));
    }
    w.bold(true).line(columns('Valor a Pagar R\$', money(t.total), cols)).bold(false);

    if (p.payments.isNotEmpty) {
      w.line(columns('FORMA DE PAGAMENTO', 'VALOR PAGO R\$', cols));
      for (final payment in p.payments) {
        w.line(columns(payment.method, money(payment.amount), cols));
      }
    }
    if (t.change > 0.004) {
      w.line(columns('Troco R\$', money(t.change), cols));
    }
    rule();
  }

  void fiscal(Payload p) {
    final f = p.fiscal!;

    for (final message in f.messages) {
      center(true, wrap(message, cols));
    }
    if (f.messages.isNotEmpty) {
      rule();
    }

    center(true, ['Consulte pela Chave de Acesso em']);
    if (f.consultaUrl.isNotEmpty) {
      center(false, wrap(f.consultaUrl, cols));
    }
    center(false, wrap(f.keyFormatted.isEmpty ? groups(f.key, 4) : f.keyFormatted, cols));
    rule();

    final consumer = f.consumer.isEmpty ? 'CONSUMIDOR NÃO IDENTIFICADO' : f.consumer;
    center(true, wrap(consumer, cols));
    final name = p.customer.name;
    if (name.isNotEmpty && name.toLowerCase() != 'consumidor final' && f.consumer.isNotEmpty && !f.consumer.contains('NÃO IDENTIFICADO')) {
      center(false, wrap(name, cols));
    }
    rule();

    center(true, ['NFC-e nº ${padded(f.number, 9)} Série ${padded(f.series, 3)}']);
    center(false, [p.header.dateTime]);
    if (f.protocol.isNotEmpty) {
      center(false, ['Protocolo de autorização: ${f.protocol}']);
      if (f.authorizedAt.isNotEmpty) {
        center(false, ['Data de autorização: ${f.authorizedAt}']);
      }
    }

    if (f.qrCode.isNotEmpty) {
      w.align(EscAlign.center).feed(1).qrCode(f.qrCode, cols < 40 ? 4 : 5).feed(1);
    }
  }

  void receiptFooter(Payload p) {
    if (p.customer.name.isNotEmpty) {
      center(false, wrap('Cliente: ${p.customer.name}', cols));
    }
    final when = '${p.header.orderNumber}  ${p.header.dateTime}'.trim();
    if (when.isNotEmpty) {
      center(false, wrap(when, cols));
    }
    center(true, ['NÃO É DOCUMENTO FISCAL']);
  }

  void footer(Payload p) {
    if (p.footer.message.isNotEmpty) {
      w.feed(1);
      for (final part in p.footer.message.split('\n')) {
        center(false, wrap(part, cols));
      }
    }
    if (p.footer.systemInfo.isNotEmpty) {
      w.align(EscAlign.center).condensed(true).line(p.footer.systemInfo).condensed(false);
    }
  }

  void center(bool bold, List<String> lines) {
    w.align(EscAlign.center).bold(bold);
    for (final line in lines) {
      for (final part in wrap(line, cols)) {
        w.line(part);
      }
    }
    w.bold(false).align(EscAlign.left);
  }

  void rule() => w.align(EscAlign.left).line('-' * cols);
}

/// Formato brasileiro: 1.234,56.
String money(double value) {
  final negative = value < 0;
  final cents = (value.abs() * 100).round();
  final whole = (cents ~/ 100).toString();

  final buffer = StringBuffer();
  for (var i = 0; i < whole.length; i++) {
    if (i > 0 && (whole.length - i) % 3 == 0) {
      buffer.write('.');
    }
    buffer.write(whole[i]);
  }

  final out = '$buffer,${(cents % 100).toString().padLeft(2, '0')}';

  return negative ? '-$out' : out;
}

String quantity(double value) {
  if (value == value.truncateToDouble()) {
    return value.toInt().toString();
  }

  var text = value.toStringAsFixed(3);
  text = text.replaceFirst(RegExp(r'0+$'), '');
  text = text.replaceFirst(RegExp(r'\.$'), '');

  return text.replaceAll('.', ',');
}

/// Número com zeros à esquerda (ex.: 000000007), se for numérico.
String padded(String value, int width) {
  if (int.tryParse(value) == null || value.length >= width) {
    return value;
  }

  return value.padLeft(width, '0');
}

/// Um texto à esquerda e outro à direita na mesma linha.
String columns(String left, String right, int width) {
  var space = width - runeLength(left) - runeLength(right);
  if (space < 1) {
    left = truncate(left, (width - runeLength(right) - 1).clamp(0, width));
    space = width - runeLength(left) - runeLength(right);
  }

  return left + ' ' * (space < 1 ? 1 : space) + right;
}

/// Quebra por palavras; palavras maiores que a linha (URLs) são cortadas.
List<String> wrap(String text, int width) {
  text = text.trim();
  if (text.isEmpty) {
    return [];
  }

  final lines = <String>[];
  var current = '';

  for (var word in text.split(RegExp(r'\s+'))) {
    while (runeLength(word) > width) {
      if (current.isNotEmpty) {
        lines.add(current);
        current = '';
      }
      lines.add(truncate(word, width));
      word = String.fromCharCodes(word.runes.skip(width));
    }

    if (current.isEmpty) {
      current = word;
    } else if (runeLength(current) + 1 + runeLength(word) <= width) {
      current += ' $word';
    } else {
      lines.add(current);
      current = word;
    }
  }
  if (current.isNotEmpty) {
    lines.add(current);
  }

  return lines;
}

String truncate(String value, int width) {
  final runes = value.runes.toList();

  return runes.length <= width ? value : String.fromCharCodes(runes.take(width));
}

int runeLength(String value) => value.runes.length;

String groups(String value, int size) {
  final parts = <String>[];
  while (value.length > size) {
    parts.add(value.substring(0, size));
    value = value.substring(size);
  }
  parts.add(value);

  return parts.join(' ');
}

/// Página de teste: um DANFE NFC-e de homologação com acentos e QR Code.
Payload samplePayload() => Payload(
      version: 2,
      documentType: 'danfe_nfce',
      header: const Header(
        storeName: 'PÁGINA DE TESTE - PERTO TERMINAL',
        legalName: 'Loja Exemplo Ltda',
        document: 'CNPJ: 00.000.000/0001-00',
        stateRegistration: 'IE: 000000000',
        address: 'Rua da Conceição, 123, Centro, São João',
        dateTime: '01/01/2026 12:00:00',
      ),
      items: const [
        Item(number: 1, code: '1', name: 'Açúcar cristal 1kg', quantity: 2, unit: 'UN', unitPrice: 5.49, totalPrice: 10.98),
        Item(number: 2, code: '2', name: 'Pão francês', quantity: 0.35, unit: 'KG', unitPrice: 18.9, totalPrice: 6.62),
      ],
      totals: const Totals(itemsCount: 2, subtotal: 17.6, total: 17.6, change: 2.4),
      payments: const [Payment(method: 'DINHEIRO', amount: 20)],
      fiscal: const Fiscal(
        model: '65',
        number: '1',
        series: '1',
        key: '00000000000000000000000000000000000000000000',
        keyFormatted: '0000 0000 0000 0000 0000 0000 0000 0000 0000 0000 0000',
        protocol: '000000000000000',
        authorizedAt: '01/01/2026 12:00:01',
        environment: 2,
        qrCode: 'https://www.sefaz.gov.br/nfce/qrcode?p=teste',
        consultaUrl: 'www.sefaz.gov.br/nfce/consulta',
        consumer: 'CONSUMIDOR NÃO IDENTIFICADO',
        messages: ['PÁGINA DE TESTE - SEM VALOR FISCAL', 'Acentos: á é í ó ú â ê ô ã õ ç'],
      ),
      footer: const Footer(message: 'Se os acentos e o QR Code saíram certos,\nestá tudo pronto.', systemInfo: 'Perto Terminal'),
    );

String _str(Object? value) => value == null ? '' : (value is String ? value : value.toString());

int _int(Object? value) => value is num ? value.toInt() : int.tryParse('$value') ?? 0;

double _num(Object? value) => value is num ? value.toDouble() : double.tryParse('$value') ?? 0;

Map<String, dynamic> _map(Object? value) => value is Map ? value.cast<String, dynamic>() : const {};

List<Object?> _list(Object? value) => value is List ? value : const [];
