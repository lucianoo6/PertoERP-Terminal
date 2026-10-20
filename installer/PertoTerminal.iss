; Instalador do Perto Terminal para Windows (Inno Setup 6).
; Instala na pasta do usuário, sem pedir senha de administrador. Rodar de novo atualiza, mantendo a configuração.
; Compilar: ISCC /DAppVersion=1.2.0 /DSourceDir=..\build\windows\x64\runner\Release installer\PertoTerminal.iss

#ifndef AppVersion
  #define AppVersion "0.0.0"
#endif
#ifndef SourceDir
  #define SourceDir "..\build\windows\x64\runner\Release"
#endif
#ifndef OutputDir
  #define OutputDir "..\dist"
#endif

#define AppName "Perto Terminal"
#define AppExe "PertoTerminal.exe"

[Setup]
AppId={{D7BFA335-3DDA-4CBB-B81E-2B2AD4031014}
AppName={#AppName}
AppVersion={#AppVersion}
AppVerName={#AppName} {#AppVersion}
AppPublisher=PertoERP
AppPublisherURL=https://pertoerp.com.br
AppSupportURL=https://pertoerp.com.br/terminal
AppUpdatesURL=https://pertoerp.com.br/terminal
DefaultDirName={localappdata}\Programs\PertoTerminal
DisableDirPage=yes
DisableProgramGroupPage=yes
DefaultGroupName={#AppName}
PrivilegesRequired=lowest
OutputDir={#OutputDir}
OutputBaseFilename=PertoTerminal-{#AppVersion}-windows-instalador
SetupIconFile=..\windows\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\{#AppExe}
UninstallDisplayName={#AppName}
WizardStyle=modern
Compression=lzma2/max
SolidCompression=yes
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
CloseApplications=no
RestartApplications=no
SetupLogging=yes
VersionInfoVersion={#AppVersion}
VersionInfoProductName={#AppName}
VersionInfoDescription=Instalador do {#AppName}

[Languages]
Name: "pt"; MessagesFile: "compiler:Languages\BrazilianPortuguese.isl"

[CustomMessages]
pt.DesktopIcon=Criar um atalho na área de trabalho
pt.AutoStart=Abrir o Perto Terminal junto com o Windows (recomendado)
pt.LaunchNow=Abrir o Perto Terminal agora
pt.Extras=Opções:

[Tasks]
Name: "desktopicon"; Description: "{cm:DesktopIcon}"; GroupDescription: "{cm:Extras}"
Name: "autostart"; Description: "{cm:AutoStart}"; GroupDescription: "{cm:Extras}"

[Files]
Source: "{#SourceDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{userprograms}\{#AppName}"; Filename: "{app}\{#AppExe}"
Name: "{userdesktop}\{#AppName}"; Filename: "{app}\{#AppExe}"; Tasks: desktopicon

[Registry]
; Mesmo nome que a opção "Abrir junto com o Windows" do próprio terminal usa.
Root: HKCU; Subkey: "Software\Microsoft\Windows\CurrentVersion\Run"; ValueType: string; ValueName: "PertoTerminalFlutter"; ValueData: """{app}\{#AppExe}"" --hidden"; Tasks: autostart; Flags: uninsdeletevalue

[Run]
Filename: "{app}\{#AppExe}"; Description: "{cm:LaunchNow}"; Flags: nowait postinstall skipifsilent
; Atualização pelo próprio terminal (instalador em silêncio): reabre sozinho, já na bandeja.
Filename: "{app}\{#AppExe}"; Parameters: "--hidden"; Flags: nowait; Check: WizardSilent

[UninstallRun]
Filename: "{sys}\taskkill.exe"; Parameters: "/F /IM {#AppExe}"; Flags: runhidden; RunOnceId: "StopTerminal"

[Code]
// O terminal fica na bandeja (fechar a janela só esconde): encerra antes de trocar os arquivos.
function PrepareToInstall(var NeedsRestart: Boolean): String;
var
  ResultCode: Integer;
begin
  Exec(ExpandConstant('{sys}\taskkill.exe'), '/F /IM {#AppExe}', '', SW_HIDE, ewWaitUntilTerminated, ResultCode);
  Sleep(800);
  Result := '';
end;
