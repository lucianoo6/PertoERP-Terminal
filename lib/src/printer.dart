import 'dart:io';
import 'dart:typed_data';

import 'config.dart';
import 'win_native.dart' as win;

/// Envia os bytes ESC/POS: impressora instalada no Windows (RAW), de rede (porta 9100) ou dispositivo/arquivo.
abstract class TicketPrinter {
  Future<void> print(String document, Uint8List data);

  static TicketPrinter open(TerminalConfig config) => switch (config.printerKind) {
        PrinterKind.windows when config.printerName.isEmpty => throw win.PrinterException('escolha a impressora nas configurações'),
        PrinterKind.windows => _Spooler(config.printerName),
        PrinterKind.network when config.printerAddress.isEmpty => throw win.PrinterException('informe o IP da impressora de rede'),
        PrinterKind.network => _Network(config.printerAddress),
        PrinterKind.file when config.printerPath.isEmpty => throw win.PrinterException('informe o caminho do dispositivo'),
        PrinterKind.file => _Device(config.printerPath),
      };

  /// Impressoras instaladas no Windows.
  static List<String> installed() => Platform.isWindows ? win.installedPrinters() : const [];
}

class _Spooler implements TicketPrinter {
  _Spooler(this.name);

  final String name;

  @override
  Future<void> print(String document, Uint8List data) async => win.printRaw(name, document, data);
}

class _Network implements TicketPrinter {
  _Network(String address) : address = address.contains(':') ? address : '$address:9100';

  final String address;

  @override
  Future<void> print(String document, Uint8List data) async {
    final separator = address.lastIndexOf(':');
    final host = address.substring(0, separator);
    final port = int.tryParse(address.substring(separator + 1)) ?? 9100;

    final Socket socket;
    try {
      socket = await Socket.connect(host, port, timeout: const Duration(seconds: 5));
    } on SocketException catch (error) {
      throw win.PrinterException('impressora de rede $address não respondeu: ${error.message}');
    }

    try {
      socket.add(data);
      await socket.flush().timeout(const Duration(seconds: 20));
    } finally {
      await socket.close();
    }
  }
}

class _Device implements TicketPrinter {
  _Device(this.path);

  final String path;

  @override
  Future<void> print(String document, Uint8List data) => File(path).writeAsBytes(data, mode: FileMode.append, flush: true);
}
