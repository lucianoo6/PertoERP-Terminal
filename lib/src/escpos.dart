import 'dart:convert';
import 'dart:typed_data';

import 'code_pages.dart';

/// Comandos das impressoras térmicas (Epson, Elgin, Bematech, Daruma, Tanca, Knup…).
class EscPos {
  EscPos(String codePage) : _page = codePageTables.containsKey(codePage) || codePage == 'ascii' ? codePage : 'cp850' {
    _raw([_esc, 0x40]);
    if (_page != 'ascii') {
      _raw([_esc, 0x74, codePageIds[_page]!]);
    }
  }

  static const _esc = 0x1b;
  static const _gs = 0x1d;

  /// Tabelas aceitas, para a tela de configuração.
  static const codePages = ['cp850', 'cp860', 'wpc1252', 'ascii'];

  final String _page;
  final BytesBuilder _buffer = BytesBuilder(copy: false);

  EscPos _raw(List<int> bytes) {
    _buffer.add(bytes);
    return this;
  }

  EscPos align(EscAlign value) => _raw([_esc, 0x61, value.index]);

  EscPos bold(bool on) => _raw([_esc, 0x45, on ? 1 : 0]);

  /// Fonte B (menor), boa para rodapés.
  EscPos condensed(bool on) => _raw([_esc, 0x4d, on ? 1 : 0]);

  EscPos text(String value) {
    _buffer.add(_encode(value));
    return this;
  }

  EscPos line(String value) => text(value)._raw([0x0a]);

  EscPos feed(int lines) => _raw([_esc, 0x64, lines.clamp(0, 255)]);

  /// Avança o papel e faz o corte parcial.
  EscPos cut() => _raw([_gs, 0x56, 66, 3]);

  /// Pulso da gaveta de dinheiro (pino 2).
  EscPos openDrawer() => _raw([_esc, 0x70, 0, 25, 250]);

  /// QR Code nativo da impressora (GS ( k): nítido e sem enviar imagem.
  EscPos qrCode(String data, int moduleSize) {
    final payload = _ascii(data);
    final store = payload.length + 3;

    _raw([_gs, 0x28, 0x6b, 4, 0, 49, 65, 50, 0]); // modelo 2
    _raw([_gs, 0x28, 0x6b, 3, 0, 49, 67, moduleSize.clamp(1, 16)]); // tamanho do módulo
    _raw([_gs, 0x28, 0x6b, 3, 0, 49, 69, 49]); // correção de erro M
    _raw([_gs, 0x28, 0x6b, store % 256, store ~/ 256, 49, 80, 48]);
    _buffer.add(payload);

    return _raw([_gs, 0x28, 0x6b, 3, 0, 49, 81, 48]); // imprime
  }

  Uint8List bytes() => _buffer.toBytes();

  List<int> _ascii(String value) => utf8.encode(value);

  List<int> _encode(String value) {
    final table = codePageTables[_page];
    final out = <int>[];

    for (final rune in value.runes) {
      if (rune == 0x0a || (rune >= 0x20 && rune < 0x7f)) {
        out.add(rune);
        continue;
      }
      final mapped = table?[rune];
      if (mapped != null) {
        out.add(mapped);
        continue;
      }
      out.addAll(transliterate(String.fromCharCode(rune)).codeUnits);
    }

    return out;
  }

  static const Map<String, String> _fallback = {
    'á': 'a', 'à': 'a', 'â': 'a', 'ã': 'a', 'ä': 'a', 'Á': 'A', 'À': 'A', 'Â': 'A', 'Ã': 'A', 'Ä': 'A',
    'é': 'e', 'è': 'e', 'ê': 'e', 'ë': 'e', 'É': 'E', 'È': 'E', 'Ê': 'E', 'Ë': 'E',
    'í': 'i', 'ì': 'i', 'î': 'i', 'ï': 'i', 'Í': 'I', 'Ì': 'I', 'Î': 'I', 'Ï': 'I',
    'ó': 'o', 'ò': 'o', 'ô': 'o', 'õ': 'o', 'ö': 'o', 'Ó': 'O', 'Ò': 'O', 'Ô': 'O', 'Õ': 'O', 'Ö': 'O',
    'ú': 'u', 'ù': 'u', 'û': 'u', 'ü': 'u', 'Ú': 'U', 'Ù': 'U', 'Û': 'U', 'Ü': 'U',
    'ç': 'c', 'Ç': 'C', 'ñ': 'n', 'Ñ': 'N', 'º': 'o', 'ª': 'a', '°': 'o',
    '·': '-', '–': '-', '—': '-', '“': '"', '”': '"', '‘': "'", '’': "'", '…': '...', '€': 'EUR',
  };

  /// Troca o que a tabela da impressora não tem por letras sem acento.
  static String transliterate(String value) {
    final buffer = StringBuffer();

    for (final rune in value.runes) {
      final char = String.fromCharCode(rune);
      final replaced = _fallback[char] ?? char;

      for (final r in replaced.runes) {
        buffer.write(r == 0x0a || (r >= 0x20 && r < 0x7f) ? String.fromCharCode(r) : '?');
      }
    }

    return buffer.toString();
  }
}

enum EscAlign { left, center, right }
