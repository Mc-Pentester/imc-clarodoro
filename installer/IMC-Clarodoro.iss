#define MyAppName "IMC-Clarodaro"
#define MyAppVersion "1.0.0"
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

[Files]
; Deploy application sources but never overwrite environment files, backups, logs or local runtime data.
Source: "..\*"; DestDir: "{app}"; Excludes: ".git\*,.github\*,.env,.env.*,backups\*,logs\*,tmp\*,cache\*,node_modules\*,vendor\*,dist\*,audit\*,docs\*"; Flags: ignoreversion recursesubdirs createallsubdirs
; Keep persistent configuration and user data during upgrades and uninstall.
; No database creation, schema execution, migration, restore or PostgreSQL service operation is performed.

[Icons]
Name: "{autoprograms}\IMC-Clarodaro"; Filename: "{sys}\cmd.exe"; Parameters: "/c start """" ""http://localhost:8080/"""; WorkingDir: "{app}"; IconFilename: "{sys}\shell32.dll"; IconIndex: 14
Name: "{autodesktop}\IMC-Clarodaro"; Filename: "{sys}\cmd.exe"; Parameters: "/c start """" ""http://localhost:8080/"""; WorkingDir: "{app}"; IconFilename: "{sys}\shell32.dll"; IconIndex: 14; Tasks: desktopicon

[Run]
Filename: "{sys}\cmd.exe"; Parameters: "/c start """" ""http://localhost:8080/"""; Description: "Ouvrir IMC-Clarodaro"; Flags: postinstall nowait skipifsilent

[UninstallDelete]
; Intentionally empty: uninstall must not delete .env, backups, logs or database data.
