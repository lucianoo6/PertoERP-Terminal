import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:perto_terminal/src/escpos.dart';
import 'package:perto_terminal/src/ticket.dart';

/// Os gabaritos em test/fixtures foram gerados pelo Perto Terminal em Go:
/// as duas versões precisam mandar exatamente os mesmos bytes para a impressora.
void main() {
  final receipt = Payload.fromJson(jsonDecode(File('test/fixtures/receipt.json').readAsStringSync()) as Map<String, dynamic>);

  void expectSameBytes(String fixture, List<int> actual) {
    final expected = File('test/fixtures/$fixture').readAsBytesSync();

    if (actual.length != expected.length || !List.generate(expected.length, (i) => expected[i] == actual[i]).every((same) => same)) {
      final firstDifference = List.generate(expected.length < actual.length ? expected.length : actual.length, (i) => i)
          .firstWhere((i) => expected[i] != actual[i], orElse: () => -1);
      fail('$fixture difere da versão em Go (esperado ${expected.length} bytes, veio ${actual.length}; primeira diferença no byte $firstDifference)');
    }
  }

  test('DANFE de teste igual ao Go em 80 mm, cp850, com gaveta', () {
    expectSameBytes('sample_48_cp850.bin', renderTicket(samplePayload(), const RenderOptions(columns: 48, codePage: 'cp850', cut: true, openDrawer: true)));
  });

  test('DANFE de teste igual ao Go em 58 mm, Windows-1252', () {
    expectSameBytes('sample_32_wpc1252.bin', renderTicket(samplePayload(), const RenderOptions(columns: 32, codePage: 'wpc1252', cut: true)));
  });

  test('comprovante sem nota igual ao Go (quebra de linha, desconto, dois pagamentos, observação)', () {
    expectSameBytes('receipt_32_cp860.bin', renderTicket(receipt, const RenderOptions(columns: 32, codePage: 'cp860', cut: false, openDrawer: true)));
    expectSameBytes('receipt_48_ascii.bin', renderTicket(receipt, const RenderOptions(columns: 48, codePage: 'ascii', cut: true)));
  });

  test('formata valores e quantidades no padrão brasileiro', () {
    expect(money(1234567.891), '1.234.567,89');
    expect(money(-3.5), '-3,50');
    expect(quantity(1.255), '1,255');
    expect(quantity(2), '2');
    expect(EscPos.transliterate('Ação “ok” — fim…'), 'Acao "ok" - fim...');
  });
}
