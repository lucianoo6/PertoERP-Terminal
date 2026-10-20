import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'config.dart';
import 'win_native.dart' as win;

/// Envia os bytes ESC/POS: impressora instalada no sistema (RAW no Windows, CUPS no Linux),
/// de rede (porta 9100) ou dispositivo/arquivo.
abstract class TicketPrinter {
  Future<void> print(String document, Uint8List data);

  static TicketPrinter open(TerminalConfig config) => switch (config.printerKind) {
        PrinterKind.windows when config.printerName.isEmpty => throw win.PrinterException('escolha a impressora nas configurações'),
        PrinterKind.windows => Platform.isWindows ? _Spooler(config.printerName) : _Cups(config.printerName),
        PrinterKind.network when config.printerAddress.isEmpty => throw win.PrinterException('informe o IP da impressora de rede'),
        PrinterKind.network => _Network(config.printerAddress),
        PrinterKind.file when config.printerPath.isEmpty => throw win.PrinterException('informe o caminho do dispositivo'),
        PrinterKind.file => _Device(config.printerPath),
      };

  /// Impressoras instaladas no sistema.
  static List<String> installed() {
    if (Platform.isWindows) {
      return win.installedPrinters();
    }

    try {
      final result = Process.runSync('lpstat', ['-e']);

      return result.exitCode == 0 ? LineSplitter.split('${result.stdout}').map((line) => line.trim()).where((line) => line.isNotEmpty).toList() : const [];
    } on ProcessException {
      return const [];
    }
  }
}

class _Spooler implements TicketPrinter {
  _Spooler(this.name);

  final String name;

  @override
  Future<void> print(String document, Uint8List data) async => win.printRaw(name, document, data);
}

/// Linux/macOS: manda pelo CUPS em modo bruto (sem o filtro do driver mexer nos comandos ESC/POS).
class _Cups implements TicketPrinter {
  _Cups(this.name);

  final String name;

  @override
  Future<void> print(String document, Uint8List data) async {
    final Process process;
    try {
      process = await Process.start('lp', ['-d', name, '-o', 'raw', '-t', document]);
    } on ProcessException {
      throw win.PrinterException('o CUPS não está instalado (comando "lp" não encontrado)');
    }

    process.stdin.add(data);
    await process.stdin.close();

    final errors = await process.stderr.transform(utf8.decoder).join();
    if (await process.exitCode != 0) {
      throw win.PrinterException('o CUPS recusou a impressão em "$name": ${errors.trim()}');
    }
  }
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
