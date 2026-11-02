#define MyAppName "IMC-Clarodaro"
#define MyAppVersion "1.1.0"
#define MyAppPublisher "IMC-Clarodaro"
#define MyAppURL "https://github.com/Mc-Pentester/imc-clarodoro"

[Setup]
AppId={{B1F31B8E-2D19-4F27-AF6D-9D5E6F4C1A20}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher={#MyAppPublisher}
AppPublisherURL={#MyAppURL}
DefaultDirName={autopf}\IMC-Clarodaro
DisableProgramGroupPage=yes
PrivilegesRequired=admin
ArchitecturesInstallIn64BitMode=x64
OutputDir=..\dist
OutputBaseFilename=IMC-Clarodaro-Setup-{#MyAppVersion}
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
Uninstallable=yes
; The installer updates managed application files only. Persistent data is excluded below.

[Languages]
Name: "french"; MessagesFile: "compiler:Languages\French.isl"

[Tasks]
Name: "desktopicon"; Description: "Créer un raccourci sur le Bureau"; GroupDescription: "Raccourcis :"; Flags: unchecked

[Dirs]
Name: "{app}"; Permissions: users-modify
Name: "{app}\logs"; Flags: uninsneveruninstall
Name: "{app}\backups"; Flags: uninsneveruninstall
Name: "{app}\installer"

[Files]
; Deploy application sources but never overwrite environment files, backups, logs or local runtime data.
Source: "..\*"; DestDir: "{app}"; Excludes: ".git\*,.github\*,.env,.env.*,backups\*,logs\*,tmp\*,cache\*,node_modules\*,vendor\*,dist\*,audit\*,docs\*,installer\payload\*,installer\*.iss,installer\*.ps1"; Flags: ignoreversion recursesubdirs createallsubdirs
; Bundled, checksum-verified PHP runtime (NTS x64) and PostgreSQL server binaries.
Source: "payload\php\*"; DestDir: "{app}\runtime\php"; Flags: ignoreversion recursesubdirs createallsubdirs
Source: "payload\postgresql\*"; DestDir: "{app}\runtime\postgresql"; Flags: ignoreversion recursesubdirs createallsubdirs
Source: "payload\runtime-manifest.json"; DestDir: "{app}\runtime"; Flags: ignoreversion
Source: "payload\vc_redist.x64.exe"; DestDir: "{app}\runtime"; Flags: ignoreversion
Source: "Start-Clarodaro-Server.ps1"; DestDir: "{app}\installer"; Flags: ignoreversion
Source: "Configure-Windows-Services.ps1"; DestDir: "{app}\installer"; Flags: ignoreversion
; Keep persistent configuration and user data during upgrades and uninstall.
; Bundling binaries does not authorize initialization, migration, restore or replacement of any existing PostgreSQL data directory.

[Icons]
Name: "{autoprograms}\IMC-Clarodaro"; Filename: "{sys}\cmd.exe"; Parameters: "/c start """" ""http://localhost:8080/"""; WorkingDir: "{app}"; IconFilename: "{sys}\shell32.dll"; IconIndex: 14
Name: "{autodesktop}\IMC-Clarodaro"; Filename: "{sys}\cmd.exe"; Parameters: "/c start """" ""http://localhost:8080/"""; WorkingDir: "{app}"; IconFilename: "{sys}\shell32.dll"; IconIndex: 14; Tasks: desktopicon

[Run]
Filename: "{app}\runtime\vc_redist.x64.exe"; Parameters: "/install /quiet /norestart"; StatusMsg: "Installation du runtime Microsoft Visual C++..."; Flags: waituntilterminated runhidden
Filename: "{sys}\WindowsPowerShell\v1.0\powershell.exe"; Parameters: "-NoProfile -ExecutionPolicy Bypass -File ""{app}\installer\Configure-Windows-Services.ps1"" -AppRoot ""{app}"""; StatusMsg: "Configuration sécurisée des services PostgreSQL et PHP..."; Flags: runhidden waituntilterminated
Filename: "{sys}\cmd.exe"; Parameters: "/c start """" ""http://localhost:8080/"""; Description: "Ouvrir IMC-Clarodaro"; Flags: postinstall nowait skipifsilent

[UninstallDelete]
; Intentionally empty: uninstall must not delete .env, backups, logs or database data.
