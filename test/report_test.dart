import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:perto_terminal/src/ticket.dart';

/// Fechamento de caixa como o PertoERP manda (ReportPayloadBuilder::cashRegister).
const _closing = '''
{
  "version": 2,
  "document_type": "report",
  "max_columns": 48,
  "header": {"store_name": "MERCADINHO SÃO JOSÉ", "document": "CNPJ: 11.222.333/0001-81", "date_time": "21/10/2026 18:05:00", "title": "FECHAMENTO DE CAIXA"},
  "lines": [
    {"text": "Caixa #12", "right": "Ana"},
    {"style": "rule"},
    {"text": "VENDAS (3)", "bold": true},
    {"text": "Dinheiro", "right": "R\$ 30,00"},
    {"text": "Total vendido", "right": "R\$ 130,00", "bold": true},
    {"text": "  Troco para o caixa 2", "style": "small"},
    {"text": "Falta", "right": "R\$ 5,00", "bold": true},
    {"style": "signature", "text": "Assinatura do operador"}
  ],
  "footer": {"message": "", "system_info": "PertoERP · Caixa #12"}
}
''';

void main() {
  final payload = Payload.fromJson(jsonDecode(_closing) as Map<String, dynamic>);
  String printed(int columns) => latin1.decode(renderTicket(payload, RenderOptions(columns: columns, codePage: 'ascii', cut: true)));

  test('lê o relatório do PertoERP', () {
    expect(payload.isReport, isTrue);
    expect(payload.lines, hasLength(8));
    expect(payload.lines[2].bold, isTrue);
    expect(payload.lines.last.style, 'signature');
  });

  test('imprime o fechamento com valores alinhados à direita e sem bloco de venda', () {
    final text = printed(48);

    expect(text, contains('FECHAMENTO DE CAIXA'));
    expect(text, contains('Emitido em 21/10/2026 18:05:00'));
    expect(text, contains('Total vendido${' ' * (48 - 'Total vendido'.length - 'R\$ 130,00'.length)}R\$ 130,00'));
    expect(text, contains('_' * 32));
    expect(text, contains('Assinatura do operador'));
    expect(text, contains('MERCADINHO SAO JOSE')); // tabela "ascii": sem acento
    expect(text, isNot(contains('VL TOTAL')));
    expect(text, isNot(contains('Valor a Pagar')));
  });

  test('cabe na bobina de 58 mm', () {
    final text = printed(32);

    expect(text, contains('Dinheiro${' ' * (32 - 'Dinheiro'.length - 'R\$ 30,00'.length)}R\$ 30,00'));
  });

  test('cupom de venda continua igual (sem linhas de relatório)', () {
    expect(samplePayload().isReport, isFalse);
  });
}
