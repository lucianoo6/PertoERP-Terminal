import 'dart:io';

/// Preenchida pelo build do GitHub a partir da tag (ex.: v1.3.1 → 1.3.1).
const appVersion = String.fromEnvironment('APP_VERSION', defaultValue: 'dev');

/// Endereço do PertoERP. Na versão publicada é fixo: ninguém consegue apontar o terminal (e o token) para outro lugar.
const officialServer = String.fromEnvironment('SERVER_URL', defaultValue: 'https://pertoerp.com.br');

/// Build de desenvolvimento (flutter run, sem tag): permite outro endereço (ex.: https://pertoerp.test).
const isDevBuild = appVersion == 'dev';

/// Enviado ao PertoERP em toda requisição: é por ele que o servidor sabe o que este terminal sabe imprimir.
String get userAgent => 'PertoTerminal/$appVersion (${Platform.operatingSystem})';
