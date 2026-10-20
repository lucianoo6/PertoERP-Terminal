// Ligações FFI diretas com o Windows (winspool, crypt32, advapi32, kernel32): só o que o terminal usa.
// ignore_for_file: non_constant_identifier_names, constant_identifier_names

import 'dart:ffi';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

final _winspool = DynamicLibrary.open('winspool.drv');
final _kernel32 = DynamicLibrary.open('kernel32.dll');
final _crypt32 = DynamicLibrary.open('crypt32.dll');
final _advapi32 = DynamicLibrary.open('advapi32.dll');

final class _DocInfo1 extends Struct {
  external Pointer<Utf16> pDocName;
  external Pointer<Utf16> pOutputFile;
  external Pointer<Utf16> pDatatype;
}

final class _PrinterInfo4 extends Struct {
  external Pointer<Utf16> pPrinterName;
  external Pointer<Utf16> pServerName;
  @Uint32()
  external int attributes;
}

final class _DataBlob extends Struct {
  @Uint32()
  external int cbData;
  external Pointer<Uint8> pbData;
}

final _openPrinter = _winspool.lookupFunction<Int32 Function(Pointer<Utf16>, Pointer<IntPtr>, Pointer<Void>), int Function(Pointer<Utf16>, Pointer<IntPtr>, Pointer<Void>)>('OpenPrinterW');
final _closePrinter = _winspool.lookupFunction<Int32 Function(IntPtr), int Function(int)>('ClosePrinter');
final _startDocPrinter = _winspool.lookupFunction<Uint32 Function(IntPtr, Uint32, Pointer<_DocInfo1>), int Function(int, int, Pointer<_DocInfo1>)>('StartDocPrinterW');
final _startPagePrinter = _winspool.lookupFunction<Int32 Function(IntPtr), int Function(int)>('StartPagePrinter');
final _writePrinter = _winspool.lookupFunction<Int32 Function(IntPtr, Pointer<Uint8>, Uint32, Pointer<Uint32>), int Function(int, Pointer<Uint8>, int, Pointer<Uint32>)>('WritePrinter');
final _endPagePrinter = _winspool.lookupFunction<Int32 Function(IntPtr), int Function(int)>('EndPagePrinter');
final _endDocPrinter = _winspool.lookupFunction<Int32 Function(IntPtr), int Function(int)>('EndDocPrinter');
final _enumPrinters = _winspool.lookupFunction<
    Int32 Function(Uint32, Pointer<Utf16>, Uint32, Pointer<Uint8>, Uint32, Pointer<Uint32>, Pointer<Uint32>),
    int Function(int, Pointer<Utf16>, int, Pointer<Uint8>, int, Pointer<Uint32>, Pointer<Uint32>)>('EnumPrintersW');

final _getLastError = _kernel32.lookupFunction<Uint32 Function(), int Function()>('GetLastError');
final _formatMessage = _kernel32.lookupFunction<
    Uint32 Function(Uint32, Pointer<Void>, Uint32, Uint32, Pointer<Utf16>, Uint32, Pointer<Void>),
    int Function(int, Pointer<Void>, int, int, Pointer<Utf16>, int, Pointer<Void>)>('FormatMessageW');
final _localFree = _kernel32.lookupFunction<IntPtr Function(Pointer<Void>), int Function(Pointer<Void>)>('LocalFree');

final _cryptProtect = _crypt32.lookupFunction<
    Int32 Function(Pointer<_DataBlob>, Pointer<Utf16>, Pointer<_DataBlob>, Pointer<Void>, Pointer<Void>, Uint32, Pointer<_DataBlob>),
    int Function(Pointer<_DataBlob>, Pointer<Utf16>, Pointer<_DataBlob>, Pointer<Void>, Pointer<Void>, int, Pointer<_DataBlob>)>('CryptProtectData');
final _cryptUnprotect = _crypt32.lookupFunction<
    Int32 Function(Pointer<_DataBlob>, Pointer<Pointer<Utf16>>, Pointer<_DataBlob>, Pointer<Void>, Pointer<Void>, Uint32, Pointer<_DataBlob>),
    int Function(Pointer<_DataBlob>, Pointer<Pointer<Utf16>>, Pointer<_DataBlob>, Pointer<Void>, Pointer<Void>, int, Pointer<_DataBlob>)>('CryptUnprotectData');

final _regSetKeyValue = _advapi32.lookupFunction<
    Int32 Function(IntPtr, Pointer<Utf16>, Pointer<Utf16>, Uint32, Pointer<Void>, Uint32),
    int Function(int, Pointer<Utf16>, Pointer<Utf16>, int, Pointer<Void>, int)>('RegSetKeyValueW');
final _regDeleteKeyValue = _advapi32.lookupFunction<Int32 Function(IntPtr, Pointer<Utf16>, Pointer<Utf16>), int Function(int, Pointer<Utf16>, Pointer<Utf16>)>('RegDeleteKeyValueW');
final _regGetValue = _advapi32.lookupFunction<
    Int32 Function(IntPtr, Pointer<Utf16>, Pointer<Utf16>, Uint32, Pointer<Uint32>, Pointer<Void>, Pointer<Uint32>),
    int Function(int, Pointer<Utf16>, Pointer<Utf16>, int, Pointer<Uint32>, Pointer<Void>, Pointer<Uint32>)>('RegGetValueW');

/// HKEY_CURRENT_USER é (HKEY)(LONG)0x80000001: com sinal estendido em 64 bits.
const _hkeyCurrentUser = -0x7fffffff;
const _runKey = r'Software\Microsoft\Windows\CurrentVersion\Run';

class WindowsError implements Exception {
  WindowsError(this.code) : message = _systemMessage(code);

  final int code;
  final String message;

  @override
  String toString() => message.isEmpty ? 'erro $code do Windows' : '$message (erro $code)';

  static String _systemMessage(int code) => using((arena) {
        final buffer = arena<Uint16>(512).cast<Utf16>();
        final length = _formatMessage(0x1000 | 0x200, nullptr, code, 0, buffer, 512, nullptr);

        return length == 0 ? '' : buffer.toDartString(length: length).trim();
      });
}

/// Impressoras instaladas (locais e compartilhadas).
List<String> installedPrinters() => using((arena) {
      final needed = arena<Uint32>();
      final returned = arena<Uint32>();
      const flags = 0x2 | 0x4; // PRINTER_ENUM_LOCAL | PRINTER_ENUM_CONNECTIONS

      _enumPrinters(flags, nullptr, 4, nullptr, 0, needed, returned);
      if (needed.value == 0) {
        return <String>[];
      }

      final buffer = arena<Uint8>(needed.value);
      if (_enumPrinters(flags, nullptr, 4, buffer, needed.value, needed, returned) == 0) {
        return <String>[];
      }

      final infos = buffer.cast<_PrinterInfo4>();

      return [for (var i = 0; i < returned.value; i++) infos[i].pPrinterName.toDartString()];
    });

/// Manda os bytes ESC/POS em modo RAW pela fila do Windows (driver do fabricante ou "Generic / Text Only").
///
/// Não consulta o driver antes (GetPrinterDriver nível 8): drivers de térmica como o da Elgin i9 recusam
/// essa consulta com "Os dados são inválidos". Tenta RAW e depois as alternativas, como a versão em Go.
void printRaw(String printerName, String document, Uint8List data) => using((arena) {
      final handle = arena<IntPtr>();

      if (_openPrinter(printerName.toNativeUtf16(allocator: arena), handle, nullptr) == 0) {
        throw PrinterException('impressora "$printerName" não encontrada no Windows: ${WindowsError(_getLastError())}');
      }

      try {
        final failures = <String>[];
        var started = false;

        for (final datatype in ['RAW', 'XPS_PASS', 'RAW [FF appended]']) {
          final info = arena<_DocInfo1>()
            ..ref.pDocName = document.toNativeUtf16(allocator: arena)
            ..ref.pOutputFile = nullptr
            ..ref.pDatatype = datatype.toNativeUtf16(allocator: arena);

          if (_startDocPrinter(handle.value, 1, info) != 0) {
            started = true;
            break;
          }
          failures.add('$datatype: ${WindowsError(_getLastError())}');
        }

        if (!started) {
          throw PrinterException('a impressora "$printerName" não aceitou dados diretos (${failures.join('; ')}). '
              'Em Impressoras do Windows › Propriedades da impressora › Avançado › Processador de impressão, escolha "winprint" e o tipo padrão "RAW"; '
              'ou instale a mesma porta USB com o driver "Generic / Text Only" e escolha essa impressora no Perto Terminal');
        }

        try {
          if (_startPagePrinter(handle.value) == 0) {
            throw PrinterException('a impressora não iniciou a página: ${WindowsError(_getLastError())}');
          }

          final bytes = arena<Uint8>(data.length)..asTypedList(data.length).setAll(0, data);
          final written = arena<Uint32>();
          final ok = _writePrinter(handle.value, bytes, data.length, written) != 0;
          final error = ok ? 0 : _getLastError();
          _endPagePrinter(handle.value);

          if (!ok) {
            throw PrinterException('falha ao enviar para a impressora: ${WindowsError(error)}');
          }
          if (written.value != data.length) {
            throw PrinterException('a impressora recebeu só ${written.value} de ${data.length} bytes');
          }
        } finally {
          _endDocPrinter(handle.value);
        }
      } finally {
        _closePrinter(handle.value);
      }
    });

class PrinterException implements Exception {
  PrinterException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Cifra com o DPAPI da conta do Windows: só este usuário, neste computador, consegue ler.
Uint8List protect(Uint8List data) => using((arena) {
      final input = _blob(arena, data);
      final output = arena<_DataBlob>();

      if (_cryptProtect(input, 'PertoTerminal'.toNativeUtf16(allocator: arena), nullptr, nullptr, nullptr, 0x1, output) == 0) {
        throw WindowsError(_getLastError());
      }

      return _take(output);
    });

Uint8List unprotect(Uint8List data) => using((arena) {
      final input = _blob(arena, data);
      final output = arena<_DataBlob>();

      if (_cryptUnprotect(input, nullptr, nullptr, nullptr, nullptr, 0x1, output) == 0) {
        throw WindowsError(_getLastError());
      }

      return _take(output);
    });

Pointer<_DataBlob> _blob(Arena arena, Uint8List data) {
  final bytes = arena<Uint8>(data.isEmpty ? 1 : data.length)..asTypedList(data.length).setAll(0, data);

  return arena<_DataBlob>()
    ..ref.cbData = data.length
    ..ref.pbData = bytes;
}

Uint8List _take(Pointer<_DataBlob> blob) {
  final result = Uint8List.fromList(blob.ref.pbData.asTypedList(blob.ref.cbData));
  _localFree(blob.ref.pbData.cast());

  return result;
}

/// Inicia junto com o Windows (chave Run do usuário).
void setAutostart(String name, String? command) => using((arena) {
      final subkey = _runKey.toNativeUtf16(allocator: arena);
      final value = name.toNativeUtf16(allocator: arena);

      if (command == null) {
        _regDeleteKeyValue(_hkeyCurrentUser, subkey, value);

        return;
      }

      final data = command.toNativeUtf16(allocator: arena);
      final status = _regSetKeyValue(_hkeyCurrentUser, subkey, value, 1, data.cast(), (command.length + 1) * 2);
      if (status != 0) {
        throw WindowsError(status);
      }
    });

String? autostartCommand(String name) => using((arena) {
      final subkey = _runKey.toNativeUtf16(allocator: arena);
      final value = name.toNativeUtf16(allocator: arena);
      final size = arena<Uint32>()..value = 2048;
      final buffer = arena<Uint16>(1024);

      final status = _regGetValue(_hkeyCurrentUser, subkey, value, 0x2, nullptr, buffer.cast(), size);

      return status == 0 ? buffer.cast<Utf16>().toDartString() : null;
    });
