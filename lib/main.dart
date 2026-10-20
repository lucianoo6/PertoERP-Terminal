import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';
import 'package:windows_single_instance/windows_single_instance.dart';

import 'src/config.dart';
import 'src/service.dart';
import 'src/updates.dart';
import 'ui/home_page.dart';
import 'ui/theme.dart';

/// Preenchida pelo build do GitHub a partir da tag (ex.: v1.2.0 → 1.2.0).
const appVersion = String.fromEnvironment('APP_VERSION', defaultValue: 'dev');

/// Perto Terminal (Flutter): fica na bandeja e imprime na térmica os cupons e DANFEs NFC-e enviados pelo PertoERP.
Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();

  // Já aberto: a segunda tentativa só traz a janela da primeira para a frente.
  await WindowsSingleInstance.ensureSingleInstance(args, 'perto_terminal_flutter', onSecondWindow: (_) => _showWindow());

  await windowManager.ensureInitialized();

  final service = TerminalService(TerminalConfig.load())..start();
  final updates = UpdateChecker(currentVersion: appVersion)..start();
  TerminalService.log('Perto Terminal (Flutter) $appVersion iniciado');

  final startHidden = args.contains('--hidden') || service.config.configured;

  await windowManager.waitUntilReadyToShow(
    const WindowOptions(
      title: 'Perto Terminal',
      size: Size(520, 760),
      minimumSize: Size(440, 560),
      center: true,
    ),
    () async {
      await windowManager.setPreventClose(true);
      if (!startHidden) {
        await _showWindow();
      }
    },
  );

  runApp(PertoTerminalApp(service: service, updates: updates));
}

/// Some da barra de tarefas e fica só o ícone ao lado do relógio.
Future<void> hideToTray() async {
  await windowManager.hide();
  await windowManager.setSkipTaskbar(true);
}

Future<void> _showWindow() async {
  if (await windowManager.isMinimized()) {
    await windowManager.restore();
  }
  await windowManager.setSkipTaskbar(false);
  await windowManager.show();
  await windowManager.focus();
}

class PertoTerminalApp extends StatefulWidget {
  const PertoTerminalApp({super.key, required this.service, required this.updates});

  final TerminalService service;
  final UpdateChecker updates;

  @override
  State<PertoTerminalApp> createState() => _PertoTerminalAppState();
}

class _PertoTerminalAppState extends State<PertoTerminalApp> with TrayListener, WindowListener {
  Health? _trayHealth;
  String _trayTooltip = '';
  String _menuSignature = '';
  final _messenger = GlobalKey<ScaffoldMessengerState>();

  TerminalService get service => widget.service;

  UpdateChecker get updates => widget.updates;

  @override
  void initState() {
    super.initState();
    trayManager.addListener(this);
    windowManager.addListener(this);
    service.addListener(_syncTray);
    updates.addListener(_syncTray);
    _syncTray();
  }

  @override
  void dispose() {
    service.removeListener(_syncTray);
    updates.removeListener(_syncTray);
    trayManager.removeListener(this);
    windowManager.removeListener(this);
    super.dispose();
  }

  Future<void> _syncTray() async {
    final status = service.status;
    final title = statusTitle(status);
    final update = updates.available;

    if (status.health != _trayHealth) {
      _trayHealth = status.health;
      // O Windows usa .ico; a bandeja do Linux (AppIndicator) usa PNG.
      await trayManager.setIcon('assets/tray/${status.health.name}.${Platform.isWindows ? 'ico' : 'png'}');
    }
    if ('$title${update?.version}' != _trayTooltip) {
      _trayTooltip = '$title${update?.version}';
      await trayManager.setToolTip('Perto Terminal · $title${update == null ? '' : ' · nova versão ${update.version}'}');
    }

    final signature = '$title|${status.configured}|${service.config.printerReady}|${update?.version}';
    if (signature == _menuSignature) {
      return;
    }
    _menuSignature = signature;

    await trayManager.setContextMenu(Menu(items: [
      MenuItem(key: 'status', label: title, disabled: true),
      if (update != null) MenuItem(key: 'update', label: 'Baixar a versão nova (${update.version})'),
      MenuItem.separator(),
      MenuItem(key: 'open', label: 'Abrir Perto Terminal'),
      MenuItem(key: 'kick', label: 'Buscar impressões agora', disabled: !status.configured),
      MenuItem(key: 'test', label: 'Imprimir página de teste', disabled: !service.config.printerReady),
      MenuItem.separator(),
      MenuItem(key: 'quit', label: 'Sair'),
    ]));
  }

  @override
  void onTrayIconMouseDown() => _showWindow();

  @override
  void onTrayIconRightMouseDown() => trayManager.popUpContextMenu();

  @override
  Future<void> onTrayMenuItemClick(MenuItem menuItem) async {
    switch (menuItem.key) {
      case 'open':
        await _showWindow();
      case 'kick':
        service.kick();
      case 'update':
        final update = updates.available;
        if (update != null) {
          await openInBrowser(update.downloadUrl ?? update.pageUrl);
        }
      case 'test':
        try {
          await service.testPrint(service.config);
        } catch (error) {
          await _showWindow();
          _messenger.currentState?.showSnackBar(SnackBar(content: Text('Página de teste: $error')));
        }
      case 'quit':
        await service.stop();
        await trayManager.destroy();
        await windowManager.setPreventClose(false);
        exit(0);
    }
  }

  /// Fechar ou minimizar a janela só esconde: o terminal continua imprimindo pela bandeja.
  @override
  Future<void> onWindowClose() => hideToTray();

  @override
  Future<void> onWindowMinimize() => hideToTray();

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: service,
      builder: (context, _) => MaterialApp(
        title: 'Perto Terminal',
        debugShowCheckedModeBanner: false,
        scaffoldMessengerKey: _messenger,
        theme: buildTheme(Brightness.light),
        darkTheme: buildTheme(Brightness.dark),
        themeMode: switch (service.config.appearance) {
          Appearance.light => ThemeMode.light,
          Appearance.dark => ThemeMode.dark,
          Appearance.system => ThemeMode.system,
        },
        home: HomePage(service: service, updates: updates, version: appVersion),
      ),
    );
  }
}
