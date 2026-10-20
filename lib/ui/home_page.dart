import 'dart:io';

import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import '../src/config.dart';
import '../src/escpos.dart';
import '../src/printer.dart';
import '../src/service.dart';
import '../src/win_native.dart' as win;
import 'theme.dart';

/// Tela única: situação do terminal em cima, configuração embaixo.
class HomePage extends StatefulWidget {
  const HomePage({super.key, required this.service, required this.version});

  final TerminalService service;
  final String version;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  static const _autostartName = 'PertoTerminalFlutter';

  late TerminalConfig _draft;
  late final TextEditingController _server;
  late final TextEditingController _token;
  late final TextEditingController _address;
  late final TextEditingController _path;

  List<String> _printers = [];
  bool _tokenVisible = false;
  bool _busy = false;
  bool _autostart = false;
  String? _checkMessage;
  bool _checkOk = false;

  TerminalService get service => widget.service;

  @override
  void initState() {
    super.initState();
    _draft = service.config;
    _server = TextEditingController(text: _draft.serverUrl.isEmpty ? 'https://pertoerp.com.br' : _draft.serverUrl);
    _token = TextEditingController(text: _draft.token);
    _address = TextEditingController(text: _draft.printerAddress);
    _path = TextEditingController(text: _draft.printerPath);
    _loadPrinters();
    _autostart = Platform.isWindows && win.autostartCommand(_autostartName) != null;
  }

  @override
  void dispose() {
    _server.dispose();
    _token.dispose();
    _address.dispose();
    _path.dispose();
    super.dispose();
  }

  void _loadPrinters() {
    setState(() {
      _printers = TicketPrinter.installed();
      if (_draft.printerName.isEmpty && _printers.length == 1) {
        _draft = _draft.copyWith(printerName: _printers.first);
      }
    });
  }

  TerminalConfig get _current => _draft.copyWith(
        serverUrl: _server.text,
        token: _token.text,
        printerAddress: _address.text,
        printerPath: _path.text,
      );

  Future<void> _run(Future<void> Function() action) async {
    setState(() => _busy = true);
    try {
      await action();
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  void _toast(String message, {bool error = false}) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(message),
        backgroundColor: error ? const Color(0xFFB91C1C) : null,
        behavior: SnackBarBehavior.floating,
      ));

  Future<void> _check() => _run(() async {
        try {
          final me = await TerminalService.check(_current);
          setState(() {
            _checkOk = true;
            _checkMessage = 'Conectado como "${me.name}" · fila "${me.printerName}"${me.realtime == null ? ' · sem tempo real' : ''}';
          });
        } catch (error) {
          setState(() {
            _checkOk = false;
            _checkMessage = '$error';
          });
        }
      });

  Future<void> _testPrint() => _run(() async {
        try {
          await service.testPrint(_current);
          _toast('Página de teste enviada. Confira acentos, largura e QR Code.');
        } catch (error) {
          _toast('$error', error: true);
        }
      });

  Future<void> _save() => _run(() async {
        final config = _current.normalized();
        if (config.serverUrl.isEmpty || config.token.isEmpty) {
          _toast('Informe o endereço do PertoERP e o token do terminal.', error: true);
          return;
        }
        if (!config.printerReady) {
          _toast('Escolha a impressora.', error: true);
          return;
        }

        await service.apply(config);
        _draft = config;
        _toast('Configuração salva. O terminal já está conectando.');
      });

  void _setAutostart(bool enabled) {
    try {
      win.setAutostart(_autostartName, enabled ? '"${Platform.resolvedExecutable}" --hidden' : null);
      setState(() => _autostart = enabled);
    } catch (error) {
      _toast('Não foi possível alterar: $error', error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                children: [
                  ListenableBuilder(listenable: service, builder: (context, _) => _StatusCard(status: service.status, version: widget.version, onKick: service.kick)),
                  const SizedBox(height: 12),
                  _connectionCard(),
                  const SizedBox(height: 12),
                  _printerCard(),
                  const SizedBox(height: 12),
                  _advancedCard(),
                ],
              ),
            ),
            _bottomBar(),
          ],
        ),
      ),
    );
  }

  Widget _connectionCard() => _Section(
        icon: Icons.cloud_outlined,
        title: 'Conexão com o PertoERP',
        subtitle: 'O token aparece ao cadastrar o terminal em Configurações › Terminais de impressão.',
        children: [
          TextField(
            controller: _server,
            decoration: const InputDecoration(labelText: 'Endereço do PertoERP', hintText: 'https://pertoerp.com.br'),
            keyboardType: TextInputType.url,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _token,
            obscureText: !_tokenVisible,
            decoration: InputDecoration(
              labelText: 'Token do terminal',
              suffixIcon: IconButton(
                tooltip: _tokenVisible ? 'Esconder' : 'Mostrar',
                icon: Icon(_tokenVisible ? Icons.visibility_off_outlined : Icons.visibility_outlined),
                onPressed: () => setState(() => _tokenVisible = !_tokenVisible),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              OutlinedButton.icon(onPressed: _busy ? null : _check, icon: const Icon(Icons.wifi_tethering, size: 18), label: const Text('Testar conexão')),
              const SizedBox(width: 12),
              if (_checkMessage != null)
                Expanded(
                  child: Row(
                    children: [
                      Icon(_checkOk ? Icons.check_circle : Icons.error_outline, size: 18, color: _checkOk ? brandGreen : const Color(0xFFDC2626)),
                      const SizedBox(width: 6),
                      Expanded(child: Text(_checkMessage!, style: Theme.of(context).textTheme.bodySmall, maxLines: 3, overflow: TextOverflow.ellipsis)),
                    ],
                  ),
                ),
            ],
          ),
        ],
      );

  Widget _printerCard() {
    final theme = Theme.of(context);

    return _Section(
      icon: Icons.print_outlined,
      title: 'Impressora térmica',
      children: [
        SegmentedButton<PrinterKind>(
          showSelectedIcon: false,
          segments: const [
            ButtonSegment(value: PrinterKind.windows, label: Text('USB'), icon: Icon(Icons.usb, size: 18)),
            ButtonSegment(value: PrinterKind.network, label: Text('Rede (IP)'), icon: Icon(Icons.lan_outlined, size: 18)),
            ButtonSegment(value: PrinterKind.file, label: Text('Porta'), icon: Icon(Icons.cable, size: 18)),
          ],
          selected: {_draft.printerKind},
          onSelectionChanged: (selection) => setState(() => _draft = _draft.copyWith(printerKind: selection.first)),
        ),
        const SizedBox(height: 12),
        switch (_draft.printerKind) {
          PrinterKind.windows => Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    initialValue: _printers.contains(_draft.printerName) ? _draft.printerName : null,
                    isExpanded: true,
                    decoration: InputDecoration(
                      labelText: 'Impressora instalada no Windows',
                      helperText: _printers.isEmpty ? 'Nenhuma impressora instalada. Instale o driver da térmica e clique em atualizar.' : null,
                    ),
                    items: [for (final name in _printers) DropdownMenuItem(value: name, child: Text(name, overflow: TextOverflow.ellipsis))],
                    onChanged: (name) => setState(() => _draft = _draft.copyWith(printerName: name ?? '')),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.outlined(tooltip: 'Atualizar lista', onPressed: _loadPrinters, icon: const Icon(Icons.refresh)),
              ],
            ),
          PrinterKind.network => TextField(
              controller: _address,
              decoration: const InputDecoration(labelText: 'IP da impressora', hintText: '192.168.0.50 (porta 9100)'),
            ),
          PrinterKind.file => TextField(
              controller: _path,
              decoration: const InputDecoration(labelText: 'Porta ou arquivo', hintText: r'Ex.: COM3, LPT1 ou \\computador\termica'),
            ),
        },
        const SizedBox(height: 16),
        Text('Largura da bobina', style: theme.textTheme.labelLarge),
        const SizedBox(height: 6),
        SegmentedButton<int>(
          showSelectedIcon: false,
          segments: const [
            ButtonSegment(value: 48, label: Text('80 mm')),
            ButtonSegment(value: 32, label: Text('58 mm')),
          ],
          selected: {_draft.columns == 32 ? 32 : 48},
          onSelectionChanged: (selection) => setState(() => _draft = _draft.copyWith(columns: selection.first)),
        ),
        const SizedBox(height: 16),
        DropdownButtonFormField<String>(
          initialValue: EscPos.codePages.contains(_draft.codePage) ? _draft.codePage : 'cp850',
          decoration: const InputDecoration(labelText: 'Tabela de acentos', helperText: 'Se os acentos saírem errados na página de teste, troque aqui.'),
          items: const [
            DropdownMenuItem(value: 'cp850', child: Text('CP850 (Elgin, Epson, Bematech - padrão)')),
            DropdownMenuItem(value: 'cp860', child: Text('CP860 (português)')),
            DropdownMenuItem(value: 'wpc1252', child: Text('Windows-1252')),
            DropdownMenuItem(value: 'ascii', child: Text('Sem acentos')),
          ],
          onChanged: (page) => setState(() => _draft = _draft.copyWith(codePage: page)),
        ),
        const SizedBox(height: 8),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Cortar o papel no fim'),
          value: _draft.cut,
          onChanged: (value) => setState(() => _draft = _draft.copyWith(cut: value)),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Abrir a gaveta em venda no dinheiro'),
          subtitle: const Text('Gaveta ligada na impressora (RJ11).'),
          value: _draft.openDrawer,
          onChanged: (value) => setState(() => _draft = _draft.copyWith(openDrawer: value)),
        ),
        Row(
          children: [
            const Expanded(child: Text('Vias de cada cupom')),
            IconButton.outlined(
              onPressed: _draft.copies > 1 ? () => setState(() => _draft = _draft.copyWith(copies: _draft.copies - 1)) : null,
              icon: const Icon(Icons.remove, size: 18),
            ),
            SizedBox(width: 40, child: Text('${_draft.copies}', textAlign: TextAlign.center, style: theme.textTheme.titleMedium)),
            IconButton.outlined(
              onPressed: _draft.copies < 5 ? () => setState(() => _draft = _draft.copyWith(copies: _draft.copies + 1)) : null,
              icon: const Icon(Icons.add, size: 18),
            ),
          ],
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: _busy ? null : _testPrint,
          icon: const Icon(Icons.receipt_long_outlined, size: 18),
          label: const Text('Imprimir página de teste'),
        ),
      ],
    );
  }

  Widget _advancedCard() => Card(
        child: Theme(
          data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
          child: ExpansionTile(
            leading: const Icon(Icons.tune),
            title: const Text('Mais opções'),
            childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            children: [
              if (Platform.isWindows)
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Abrir junto com o Windows'),
                  subtitle: const Text('Fica na bandeja, sem abrir esta janela.'),
                  value: _autostart,
                  onChanged: _setAutostart,
                ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Aceitar certificado de teste'),
                subtitle: const Text('Só para servidor local (.test). Deixe desligado no dia a dia.'),
                value: _draft.insecureTls,
                onChanged: (value) => setState(() => _draft = _draft.copyWith(insecureTls: value)),
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Pasta de configuração e log'),
                subtitle: SelectableText(TerminalConfig.directory.path),
                trailing: IconButton(
                  tooltip: 'Abrir pasta',
                  icon: const Icon(Icons.folder_open_outlined),
                  onPressed: () {
                    TerminalConfig.directory.createSync(recursive: true);
                    Process.run('explorer', [TerminalConfig.directory.path]);
                  },
                ),
              ),
            ],
          ),
        ),
      );

  Widget _bottomBar() => Container(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        decoration: BoxDecoration(
          color: Theme.of(context).cardTheme.color,
          border: Border(top: BorderSide(color: Theme.of(context).dividerColor.withValues(alpha: 0.2))),
        ),
        child: Row(
          children: [
            TextButton(onPressed: () => windowManager.close(), child: const Text('Esconder na bandeja')),
            const Spacer(),
            FilledButton.icon(
              onPressed: _busy ? null : _save,
              icon: _busy ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Icons.check),
              label: const Text('Salvar e conectar'),
            ),
          ],
        ),
      );
}

class _StatusCard extends StatelessWidget {
  const _StatusCard({required this.status, required this.version, required this.onKick});

  final TerminalStatus status;
  final String version;
  final VoidCallback onKick;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = statusColor(status.health);
    final lastPrint = status.lastPrintAt;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(color: color.withValues(alpha: 0.12), shape: BoxShape.circle),
                  child: Icon(switch (status.health) {
                    Health.ok => Icons.print,
                    Health.degraded => Icons.sync,
                    Health.error => Icons.error_outline,
                    Health.setup => Icons.settings_outlined,
                  }, color: color),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(statusTitle(status), style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
                      Text(
                        [
                          if (status.device.isNotEmpty) status.device,
                          if (status.printerName.isNotEmpty) 'fila ${status.printerName}',
                          'Perto Terminal $version',
                        ].join(' · '),
                        style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
                if (status.configured) IconButton(tooltip: 'Buscar impressões agora', onPressed: onKick, icon: const Icon(Icons.refresh)),
              ],
            ),
            if (status.configured) ...[
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _Pill(icon: Icons.cloud_done_outlined, label: status.connected ? 'Servidor conectado' : 'Sem servidor', on: status.connected),
                  _Pill(icon: Icons.bolt, label: status.realtime ? 'Tempo real' : 'Consultando a cada poucos segundos', on: status.realtime),
                  _Pill(
                    icon: Icons.receipt_outlined,
                    label: status.printed == 0
                        ? 'Nenhum cupom ainda'
                        : '${status.printed} impresso(s)${lastPrint != null ? ' · último às ${lastPrint.hour.toString().padLeft(2, '0')}:${lastPrint.minute.toString().padLeft(2, '0')}' : ''}',
                    on: status.printed > 0,
                  ),
                ],
              ),
            ],
            if (status.lastError.isNotEmpty) ...[
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: const Color(0xFFDC2626).withValues(alpha: 0.08), borderRadius: BorderRadius.circular(8)),
                child: SelectableText(status.lastError, style: theme.textTheme.bodySmall?.copyWith(color: const Color(0xFFB91C1C))),
              ),
            ],
            if (!status.configured) ...[
              const SizedBox(height: 8),
              Text('Preencha a conexão e a impressora abaixo e clique em "Salvar e conectar".', style: theme.textTheme.bodySmall),
            ],
          ],
        ),
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.icon, required this.label, required this.on});

  final IconData icon;
  final String label;
  final bool on;

  @override
  Widget build(BuildContext context) {
    final color = on ? brandGreen : Theme.of(context).colorScheme.onSurfaceVariant;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(99)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 5),
          Text(label, style: Theme.of(context).textTheme.labelSmall?.copyWith(color: color)),
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.icon, required this.title, this.subtitle, required this.children});

  final IconData icon;
  final String title;
  final String? subtitle;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(icon, size: 20, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Text(title, style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
              ],
            ),
            if (subtitle != null) ...[
              const SizedBox(height: 4),
              Text(subtitle!, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
            ],
            const SizedBox(height: 14),
            ...children,
          ],
        ),
      ),
    );
  }
}
