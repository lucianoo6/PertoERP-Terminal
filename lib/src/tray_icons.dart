import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'config.dart';
import 'service.dart';

/// Ícones da bandeja desenhados na hora (círculo na cor da situação com um cupom branco), igual à versão em Go.
class TrayIcons {
  static const _colors = {
    Health.ok: [0x4a, 0x8a, 0x1c],
    Health.degraded: [0xd9, 0x77, 0x06],
    Health.error: [0xdc, 0x26, 0x26],
    Health.setup: [0x9c, 0xa3, 0xaf],
  };

  static final Map<Health, String> _paths = {};

  /// Caminho do .ico da situação (o tray_manager do Windows só aceita arquivo).
  static String path(Health health) => _paths.putIfAbsent(health, () {
        final directory = Directory('${TerminalConfig.directory.path}\\icons')..createSync(recursive: true);
        final file = File('${directory.path}\\${health.name}.ico')..writeAsBytesSync(ico(health));

        return file.path;
      });

  static Uint8List ico(Health health) {
    const size = 32;
    final fill = _colors[health]!;
    final pixels = List.generate(size, (_) => List<List<int>?>.filled(size, null));
    const c = (size - 1) / 2;

    for (var y = 0; y < size; y++) {
      for (var x = 0; x < size; x++) {
        if (math.sqrt(math.pow(x - c, 2) + math.pow(y - c, 2)) <= c) {
          pixels[y][x] = fill;
        }
        // Cupom: retângulo branco com "dentes" embaixo.
        if (x >= 10 && x <= 21 && y >= 7 && y <= 23 && (y < 23 || (x - 10) % 3 != 2)) {
          pixels[y][x] = const [0xff, 0xff, 0xff];
        }
      }
    }
    for (final y in [11, 14, 17]) {
      for (var x = 12; x <= 19; x++) {
        pixels[y][x] = fill;
      }
    }

    // ICO com DIB 32 bits (BGRA, de baixo para cima) + máscara AND.
    const maskRow = 4; // 32 pixels = 4 bytes, já alinhado em 32 bits
    const imageSize = 40 + size * size * 4 + size * maskRow;
    final data = ByteData(6 + 16 + imageSize);
    var offset = 0;

    void u8(int value) => data.setUint8(offset++, value);
    void u16(int value) {
      data.setUint16(offset, value, Endian.little);
      offset += 2;
    }

    void u32(int value) {
      data.setUint32(offset, value, Endian.little);
      offset += 4;
    }

    u16(0);
    u16(1);
    u16(1);
    u8(size);
    u8(size);
    u8(0);
    u8(0);
    u16(1);
    u16(32);
    u32(imageSize);
    u32(22);

    u32(40);
    u32(size);
    u32(size * 2);
    u16(1);
    u16(32);
    for (var i = 0; i < 6; i++) {
      u32(0);
    }

    for (var y = size - 1; y >= 0; y--) {
      for (var x = 0; x < size; x++) {
        final pixel = pixels[y][x];
        u8(pixel?[2] ?? 0);
        u8(pixel?[1] ?? 0);
        u8(pixel?[0] ?? 0);
        u8(pixel == null ? 0 : 0xff);
      }
    }
    for (var i = 0; i < size * maskRow; i++) {
      u8(0);
    }

    return data.buffer.asUint8List();
  }
}
