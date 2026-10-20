import 'dart:io';

import 'win_native.dart' as win;

/// Abrir junto com o sistema, já escondido na bandeja.
class Autostart {
  static const _name = 'PertoTerminalFlutter';

  static String get _command => '"${Platform.resolvedExecutable}" --hidden';

  static File get _desktopFile => File('${Platform.environment['HOME'] ?? '.'}/.config/autostart/perto-terminal.desktop');

  static bool get supported => Platform.isWindows || Platform.isLinux;

  static bool get enabled {
    if (Platform.isWindows) {
      return win.autostartCommand(_name) != null;
    }

    return Platform.isLinux && _desktopFile.existsSync();
  }

  static void set(bool enabled) {
    if (Platform.isWindows) {
      win.setAutostart(_name, enabled ? _command : null);

      return;
    }

    if (!Platform.isLinux) {
      return;
    }

    if (!enabled) {
      if (_desktopFile.existsSync()) {
        _desktopFile.deleteSync();
      }

      return;
    }

    _desktopFile.parent.createSync(recursive: true);
    _desktopFile.writeAsStringSync('''
[Desktop Entry]
Type=Application
Name=Perto Terminal
Comment=Impressão do PertoERP
Exec=$_command
Terminal=false
X-GNOME-Autostart-enabled=true
''');
  }
}
