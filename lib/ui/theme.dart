import 'package:flutter/material.dart';

import '../src/service.dart';

/// Verde do PertoERP.
const brandGreen = Color(0xFF4F8A16);

ThemeData buildTheme(Brightness brightness) {
  final scheme = ColorScheme.fromSeed(seedColor: brandGreen, brightness: brightness, primary: brightness == Brightness.light ? brandGreen : null);
  final dark = brightness == Brightness.dark;

  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: dark ? const Color(0xFF111110) : const Color(0xFFF6F6F2),
    fontFamily: 'Segoe UI',
    cardTheme: CardThemeData(
      elevation: 0,
      margin: EdgeInsets.zero,
      color: dark ? const Color(0xFF1C1C19) : Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: dark ? const Color(0xFF2A2A25) : const Color(0xFFE6E6E0)),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
      isDense: true,
      filled: true,
      fillColor: dark ? const Color(0xFF16160F) : const Color(0xFFFBFBF8),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(0, 44),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(0, 40),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: SegmentedButton.styleFrom(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
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

Color statusColor(Health health) => switch (health) {
      Health.ok => brandGreen,
      Health.degraded => const Color(0xFFD97706),
      Health.error => const Color(0xFFDC2626),
      Health.setup => const Color(0xFF9CA3AF),
    };
