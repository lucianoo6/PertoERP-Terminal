import 'package:flutter/material.dart';

import '../src/service.dart';

/// Tokens do PertoERP (resources/css/filament/admin/theme.css), para o terminal parecer o mesmo sistema.
class PertoColors extends ThemeExtension<PertoColors> {
  const PertoColors({
    required this.canvas,
    required this.panel,
    required this.field,
    required this.track,
    required this.line,
    required this.lineStrong,
    required this.ink,
    required this.muted,
    required this.green,
    required this.greenHover,
    required this.greenSoft,
  });

  static const light = PertoColors(
    canvas: Color(0xFFEEEEE9),
    panel: Color(0xFFFFFFFF),
    field: Color(0xFFF6F6F2),
    track: Color(0xFFE6E6E0),
    line: Color(0xFFE6E6E0),
    lineStrong: Color(0xFFD6D6CE),
    ink: Color(0xFF16160F),
    muted: Color(0xFF6F6F66),
    green: Color(0xFF4F8A16),
    greenHover: Color(0xFF447A12),
    greenSoft: Color(0xFFEEF6DF),
  );

  static const dark = PertoColors(
    canvas: Color(0xFF131311),
    panel: Color(0xFF1C1C19),
    field: Color(0xFF24241F),
    track: Color(0xFF2A2A25),
    line: Color(0xFF2F2F29),
    lineStrong: Color(0xFF3A3A33),
    ink: Color(0xFFF2F2EC),
    muted: Color(0xFFA3A399),
    green: Color(0xFF7BC142),
    greenHover: Color(0xFF8FD457),
    greenSoft: Color(0x297BC142),
  );

  final Color canvas, panel, field, track, line, lineStrong, ink, muted, green, greenHover, greenSoft;

  static PertoColors of(BuildContext context) => Theme.of(context).extension<PertoColors>()!;

  @override
  PertoColors copyWith() => this;

  @override
  PertoColors lerp(PertoColors? other, double t) => t < 0.5 || other == null ? this : other;
}

ThemeData buildTheme(Brightness brightness) {
  final dark = brightness == Brightness.dark;
  final c = dark ? PertoColors.dark : PertoColors.light;
  final radius = BorderRadius.circular(10);

  final scheme = ColorScheme.fromSeed(seedColor: PertoColors.light.green, brightness: brightness).copyWith(
    primary: c.green,
    onPrimary: dark ? const Color(0xFF0A0A09) : Colors.white,
    surface: c.panel,
    onSurface: c.ink,
    onSurfaceVariant: c.muted,
    outline: c.lineStrong,
    outlineVariant: c.line,
    secondaryContainer: c.greenSoft,
    onSecondaryContainer: dark ? c.green : c.greenHover,
  );

  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: scheme,
    extensions: [c],
    scaffoldBackgroundColor: c.canvas,
    fontFamily: 'Segoe UI',
    dividerColor: c.line,
    cardTheme: CardThemeData(
      elevation: 0,
      margin: EdgeInsets.zero,
      color: c.panel,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: BorderSide(color: c.line)),
    ),
    inputDecorationTheme: InputDecorationTheme(
      isDense: true,
      filled: true,
      fillColor: c.field,
      labelStyle: TextStyle(color: c.muted),
      helperStyle: TextStyle(color: c.muted),
      border: OutlineInputBorder(borderRadius: radius, borderSide: BorderSide(color: c.lineStrong)),
      enabledBorder: OutlineInputBorder(borderRadius: radius, borderSide: BorderSide(color: c.lineStrong)),
      focusedBorder: OutlineInputBorder(borderRadius: radius, borderSide: BorderSide(color: c.green, width: 1.5)),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(0, 44),
        backgroundColor: c.green,
        foregroundColor: scheme.onPrimary,
        shape: RoundedRectangleBorder(borderRadius: radius),
        textStyle: const TextStyle(fontWeight: FontWeight.w600),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(0, 40),
        foregroundColor: c.ink,
        backgroundColor: c.panel,
        side: BorderSide(color: c.lineStrong),
        shape: RoundedRectangleBorder(borderRadius: radius),
      ),
    ),
    textButtonTheme: TextButtonThemeData(style: TextButton.styleFrom(foregroundColor: c.ink)),
    iconButtonTheme: IconButtonThemeData(style: IconButton.styleFrom(foregroundColor: c.muted)),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: ButtonStyle(
        shape: WidgetStatePropertyAll(RoundedRectangleBorder(borderRadius: radius)),
        side: WidgetStatePropertyAll(BorderSide(color: c.lineStrong)),
        backgroundColor: WidgetStateProperty.resolveWith((states) => states.contains(WidgetState.selected) ? c.greenSoft : c.panel),
        foregroundColor: WidgetStateProperty.resolveWith((states) => states.contains(WidgetState.selected) ? (dark ? c.green : c.greenHover) : c.ink),
      ),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith((states) => states.contains(WidgetState.selected) ? Colors.white : c.muted),
      trackColor: WidgetStateProperty.resolveWith((states) => states.contains(WidgetState.selected) ? c.green : c.track),
      trackOutlineColor: WidgetStateProperty.resolveWith((states) => states.contains(WidgetState.selected) ? c.green : c.lineStrong),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: dark ? c.field : c.ink,
      contentTextStyle: TextStyle(color: dark ? c.ink : Colors.white),
      shape: RoundedRectangleBorder(borderRadius: radius),
    ),
  );
}

/// Frase curta da situação, para a tela, a dica e o menu da bandeja.
String statusTitle(TerminalStatus status) => switch (status.health) {
      Health.setup => 'Falta configurar',
      Health.ok => 'Pronto para imprimir',
      Health.degraded => 'Imprimindo (tempo real reconectando)',
      Health.error => status.connected ? 'Com problema na impressão' : 'Sem conexão com o PertoERP',
    };

Color statusColor(BuildContext context, Health health) => switch (health) {
      Health.ok => PertoColors.of(context).green,
      Health.degraded => const Color(0xFFD97706),
      Health.error => const Color(0xFFDC2626),
      Health.setup => PertoColors.of(context).muted,
    };
