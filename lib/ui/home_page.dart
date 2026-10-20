import 'dart:io';

import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import '../src/config.dart';
import '../src/escpos.dart';
import '../src/printer.dart';
import '../src/service.dart';
import '../main.dart' show installUpdate;
import '../src/updates.dart';
import '../src/autostart.dart';
import 'theme.dart';

/// Tela única: situação do terminal em cima, configuração embaixo.
class HomePage extends StatefulWidget {
  const HomePage({super.key, required this.service, required this.updates, required this.version});

  final TerminalService service;
  final UpdateChecker updates;
  final String version;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
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
  String? _updateMessage;

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
    _autostart = Autostart.supported && Autostart.enabled;
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
        appearance: service.config.appearance,
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

  Future<void> _checkUpdates() => _run(() async {
        final update = await widget.updates.check();
        setState(() => _updateMessage = update == null
            ? 'Você já está na versão mais nova (${widget.version}).'
            : 'Saiu a versão ${update.version}: veja o aviso no topo da janela.');
      });

  void _setAutostart(bool enabled) {
    try {
      Autostart.set(enabled);
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
                  _BrandHeader(version: widget.version),
                  const SizedBox(height: 14),
                  ListenableBuilder(
                    listenable: widget.updates,
                    builder: (context, _) => widget.updates.available == null
                        ? const SizedBox.shrink()
                        : Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: _UpdateBanner(
                              update: widget.updates.available!,
                              current: widget.version,
                              updates: widget.updates,
                              onInstall: () => installUpdate(service, widget.updates, widget.updates.available!),
                            ),
                          ),
                  ),
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
                      Icon(_checkOk ? Icons.check_circle : Icons.error_outline, size: 18, color: _checkOk ? PertoColors.of(context).green : const Color(0xFFDC2626)),
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
                      labelText: Platform.isWindows ? 'Impressora instalada no Windows' : 'Impressora instalada (CUPS)',
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
              decoration: InputDecoration(labelText: 'Porta ou arquivo', hintText: Platform.isWindows ? r'Ex.: COM3, LPT1 ou \\computador\termica' : 'Ex.: /dev/usb/lp0'),
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
              Align(alignment: Alignment.centerLeft, child: Text('Aparência', style: Theme.of(context).textTheme.labelLarge)),
              const SizedBox(height: 6),
              SizedBox(
                width: double.infinity,
                child: SegmentedButton<Appearance>(
                  showSelectedIcon: false,
                  segments: const [
                    ButtonSegment(value: Appearance.light, label: Text('Claro'), icon: Icon(Icons.light_mode_outlined, size: 18)),
                    ButtonSegment(value: Appearance.dark, label: Text('Escuro'), icon: Icon(Icons.dark_mode_outlined, size: 18)),
                    ButtonSegment(value: Appearance.system, label: Text('Igual ao Windows'), icon: Icon(Icons.desktop_windows_outlined, size: 18)),
                  ],
                  selected: {service.config.appearance},
                  onSelectionChanged: (selection) => service.setAppearance(selection.first),
                ),
              ),
              const SizedBox(height: 8),
              if (Autostart.supported)
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(Platform.isWindows ? 'Abrir junto com o Windows' : 'Abrir junto com o sistema'),
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
              if (widget.updates.enabled)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Atualizações'),
                  subtitle: Text(_updateMessage ?? 'Versão ${widget.version}. O terminal confere sozinho se saiu versão nova.'),
                  trailing: OutlinedButton(onPressed: _busy ? null : _checkUpdates, child: const Text('Procurar agora')),
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
                    Process.run(Platform.isWindows ? 'explorer' : 'xdg-open', [TerminalConfig.directory.path]);
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
            Tooltip(
              message: 'O terminal continua imprimindo pelo ícone ao lado do relógio.',
              child: OutlinedButton.icon(
                onPressed: () => windowManager.close(),
                icon: const Icon(Icons.keyboard_arrow_down, size: 18),
                label: const Text('Esconder na bandeja'),
              ),
            ),
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
    final color = statusColor(context, status.health);
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
            if (status.configured) ...[
              const SizedBox(height: 12),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.info_outline, size: 16, color: PertoColors.of(context).muted),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Pode fechar ou minimizar esta janela: o terminal continua imprimindo pelo ícone verde ao lado do relógio. '
                      'Se ele não aparecer, clique na setinha ^ da barra de tarefas.',
                      style: theme.textTheme.bodySmall?.copyWith(color: PertoColors.of(context).muted),
                    ),
                  ),
                ],
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
    final color = on ? PertoColors.of(context).green : PertoColors.of(context).muted;

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

class _BrandHeader extends StatelessWidget {
  const _BrandHeader({required this.version});

  final String version;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = PertoColors.of(context);

    return Row(
      children: [
        ClipRRect(borderRadius: BorderRadius.circular(9), child: Image.asset('assets/brand/icon.png', width: 36, height: 36)),
        const SizedBox(width: 10),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Perto Terminal', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700, color: colors.ink)),
            Text('Impressão do PertoERP · versão $version', style: theme.textTheme.bodySmall?.copyWith(color: colors.muted)),
          ],
        ),
      ],
    );
  }
}

class _UpdateBanner extends StatelessWidget {
  const _UpdateBanner({required this.update, required this.current, required this.updates, required this.onInstall});

  final AvailableUpdate update;
  final String current;
  final UpdateChecker updates;
  final VoidCallback onInstall;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = PertoColors.of(context);
    final notes = update.notes
        .split('\n')
        .map((line) => line.replaceFirst(RegExp(r'^[#*\-\s]+'), '').trim())
        .where((line) => line.isNotEmpty && !line.startsWith('Full Changelog') && !line.startsWith("What's Changed"))
        .take(3)
        .toList();

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colors.greenSoft,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: colors.green.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.system_update_alt, color: colors.green),
              const SizedBox(width: 8),
              Expanded(
                child: Text('Nova versão ${update.version} disponível', style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700, color: colors.ink)),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
              update.canInstall
                  ? 'Você está na $current. Clique em "Atualizar agora": o terminal fecha, atualiza e volta sozinho em poucos segundos, com a mesma configuração.'
                  : 'Você está na $current. Baixe a versão nova e siga o passo a passo do site: a configuração continua a mesma.',
              style: theme.textTheme.bodySmall?.copyWith(color: colors.muted)),
          if (notes.isNotEmpty) ...[
            const SizedBox(height: 8),
            for (final note in notes)
              Padding(
                padding: const EdgeInsets.only(bottom: 2),
                child: Text('• $note', style: theme.textTheme.bodySmall?.copyWith(color: colors.ink), maxLines: 2, overflow: TextOverflow.ellipsis),
              ),
          ],
          if (updates.installError != null) ...[
            const SizedBox(height: 8),
            Text(updates.installError!, style: theme.textTheme.bodySmall?.copyWith(color: const Color(0xFFB91C1C))),
          ],
          const SizedBox(height: 10),
          if (updates.installing)
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                LinearProgressIndicator(value: updates.installProgress, color: colors.green, backgroundColor: colors.track, minHeight: 6, borderRadius: BorderRadius.circular(3)),
                const SizedBox(height: 6),
                Text(
                  (updates.installProgress ?? 0) >= 1 ? 'Instalando… o terminal volta sozinho em instantes.' : 'Baixando a versão ${update.version}… ${((updates.installProgress ?? 0) * 100).round()}%',
                  style: theme.textTheme.bodySmall?.copyWith(color: colors.muted),
                ),
              ],
            )
          else
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (update.canInstall)
                  FilledButton.icon(onPressed: onInstall, icon: const Icon(Icons.system_update_alt, size: 18), label: const Text('Atualizar agora'))
                else
                  FilledButton.icon(
                    onPressed: () => openInBrowser(update.downloadUrl ?? update.pageUrl),
                    icon: const Icon(Icons.download, size: 18),
                    label: const Text('Baixar agora'),
                  ),
                OutlinedButton(onPressed: () => openInBrowser(update.pageUrl), child: Text(update.canInstall ? 'Ver novidades' : 'Como instalar')),
              ],
            ),
        ],
      ),
    );
  }
}
