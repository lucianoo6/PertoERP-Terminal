import 'dart:io';

/// Preenchida pelo build do GitHub a partir da tag (ex.: v1.3.0 → 1.3.0).
const appVersion = String.fromEnvironment('APP_VERSION', defaultValue: 'dev');

/// Enviado ao PertoERP em toda requisição: é por ele que o servidor sabe o que este terminal sabe imprimir.
String get userAgent => 'PertoTerminal/$appVersion (${Platform.operatingSystem})';
