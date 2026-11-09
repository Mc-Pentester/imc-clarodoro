#define MyAppName "IMC-Clarodaro"
#define MyAppVersion "1.1.0"
#define MyAppPublisher "Jean Rony Agéna"
#define MyAppURL "https://github.com/Mc-Pentester/imc-clarodoro"

[Setup]
AppId={{B1F31B8E-2D19-4F27-AF6D-9D5E6F4C1A20}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher={#MyAppPublisher}
AppPublisherURL={#MyAppURL}
LicenseFile=..\LICENSE-CLARODARO.txt
DefaultDirName={autopf}\IMC-Clarodoro
DisableProgramGroupPage=yes
PrivilegesRequired=admin
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
OutputDir=..\dist
OutputBaseFilename=IMC-Clarodoro-Setup-{#MyAppVersion}
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
Name: "{app}"
Name: "{app}\logs"
Name: "{app}\backups"
Name: "{app}\uploads"
Name: "{app}\storage"
Name: "{app}\installer"

[Files]
; Deploy application sources but never overwrite environment files, backups, logs or local runtime data.
Source: "..\*"; DestDir: "{app}"; Excludes: ".git\*,.github\*,.env,.env.*,backups\*,logs\*,tmp\*,cache\*,node_modules\*,vendor\*,dist\*,audit\*,docs\*,installer\payload\*,installer\*.iss,installer\*.ps1"; Flags: ignoreversion recursesubdirs createallsubdirs
; Bundled, checksum-verified PHP runtime (NTS x64) and PostgreSQL server binaries.
Source: "payload\php\*"; DestDir: "{app}\runtime\php"; Flags: ignoreversion recursesubdirs createallsubdirs
; Stage PostgreSQL inside the install directory; Configure-Windows-Services.ps1 copies and verifies it in ProgramData before service registration.\nSource: "payload\postgresql\*"; DestDir: "{app}\installer\postgresql-runtime"; Flags: ignoreversion recursesubdirs createallsubdirs
Source: "payload\runtime-manifest.json"; DestDir: "{app}\runtime"; Flags: ignoreversion
Source: "payload\vc_redist.x64.exe"; DestDir: "{app}\runtime"; Flags: ignoreversion
Source: "Start-Clarodaro-Server.ps1"; DestDir: "{app}\installer"; Flags: ignoreversion
Source: "Configure-Windows-Services.ps1"; DestDir: "{app}\installer"; Flags: ignoreversion
Source: "Remove-Windows-Services.ps1"; DestDir: "{app}\installer"; Flags: ignoreversion
Source: "Prepare-Upgrade.ps1"; DestDir: "{app}\installer"; Flags: ignoreversion; AfterInstall: ConfigureAfterFiles
; The upgrade guard must come from this installer, not from the older installed version.
Source: "Prepare-Upgrade.ps1"; Flags: dontcopy
; Keep persistent configuration and user data during upgrades and uninstall.
; Bundling binaries does not authorize initialization, migration, restore or replacement of any existing PostgreSQL data directory.

[Icons]
Name: "{autoprograms}\IMC-Clarodoro"; Filename: "{sys}\cmd.exe"; Parameters: "/c start """" ""http://localhost:18080/"""; WorkingDir: "{app}"; IconFilename: "{sys}\shell32.dll"; IconIndex: 14
Name: "{autodesktop}\IMC-Clarodoro"; Filename: "{sys}\cmd.exe"; Parameters: "/c start """" ""http://localhost:18080/"""; WorkingDir: "{app}"; IconFilename: "{sys}\shell32.dll"; IconIndex: 14; Tasks: desktopicon

[Code]

var
  PurgeClarodaroData: Boolean;

function CmdLineParamExists(const Value: string): Boolean;
var
  I: Integer;
begin
  Result := False;
  for I := 1 to ParamCount do
    if CompareText(ParamStr(I), Value) = 0 then
    begin
      Result := True;
      Exit;
    end;
end;

function InitializeUninstall(): Boolean;
begin
  Result := True;
  PurgeClarodaroData := False;
  if CmdLineParamExists('/PURGEDATA') then
    PurgeClarodaroData := True
  else if not UninstallSilent then
  begin
    if MsgBox(
      'Souhaitez-vous supprimer aussi les données locales de Clarodaro ?' + #13#10 + #13#10 +
      'OUI : supprimer définitivement la base PostgreSQL, le compte PDG, les comptes utilisateurs, les paramètres, les sauvegardes, les exports, le stockage, les fichiers téléversés, les secrets et les journaux.' + #13#10 + #13#10 +
      'NON : conserver toutes ces données pour une éventuelle réinstallation. C''est le choix recommandé.',
      mbConfirmation, MB_YESNO or MB_DEFBUTTON2) = IDYES then
    begin
      if MsgBox(
        'CONFIRMATION FINALE : toutes les données de cet établissement seront supprimées sans possibilité de récupération par Clarodaro.' + #13#10 + #13#10 +
        'Assurez-vous de disposer d''une sauvegarde externe si nécessaire. Confirmer la suppression définitive ?',
        mbCriticalError, MB_YESNO or MB_DEFBUTTON2) = IDYES then
        PurgeClarodaroData := True;
    end;
  end;
end;

procedure ConfigureAfterFiles;
var
  ResultCode: Integer;
  Parameters: String;
  PowerShellPath: String;
begin
  if not Exec(
    ExpandConstant('{app}\runtime\vc_redist.x64.exe'),
    '/install /quiet /norestart',
    '',
    SW_HIDE,
    ewWaitUntilTerminated,
    ResultCode
  ) then
    RaiseException('Impossible de lancer le redistribuable Microsoft Visual C++.');

  if (ResultCode <> 0) and (ResultCode <> 1638) and (ResultCode <> 3010) then
    RaiseException('Installation du runtime Microsoft Visual C++ échouée. Code : ' + IntToStr(ResultCode));

  PowerShellPath := ExpandConstant('{sys}\WindowsPowerShell\v1.0\powershell.exe');
  Parameters := '-NoProfile -ExecutionPolicy Bypass -File "' +
    ExpandConstant('{app}\installer\Configure-Windows-Services.ps1') +
    '" -AppRoot "' + ExpandConstant('{app}') + '"';

  if not Exec(
    PowerShellPath,
    Parameters,
    ExpandConstant('{app}'),
    SW_HIDE,
    ewWaitUntilTerminated,
    ResultCode
  ) then
    RaiseException('Impossible de lancer la configuration des services Windows.');

  if ResultCode <> 0 then
    RaiseException(
      'La configuration des services Clarodaro a échoué. Consultez le journal : ' +
      ExpandConstant('{commonappdata}\IMC-Clarodaro\logs\installer-services.log')
    );

end;

procedure CurStepChanged(CurStep: TSetupStep);
var
  ResultCode: Integer;
  Parameters: String;
  PowerShellPath: String;
begin
  if CurStep = ssInstall then
  begin
    if DirExists(ExpandConstant('{app}')) then
    begin
      ExtractTemporaryFile('Prepare-Upgrade.ps1');
      Parameters := '-NoProfile -ExecutionPolicy Bypass -File "' +
        ExpandConstant('{tmp}\Prepare-Upgrade.ps1') +
        '" -AppRoot "' + ExpandConstant('{app}') + '"';
      if not Exec(
        ExpandConstant('{sys}\WindowsPowerShell\v1.0\powershell.exe'),
        Parameters,
        ExpandConstant('{app}'),
        SW_HIDE,
        ewWaitUntilTerminated,
        ResultCode
      ) then
        RaiseException('Impossible de préparer l arret des services avant la mise à jour.');
      if ResultCode <> 0 then
        RaiseException('Arrêt sécurisé des services impossible. Mise à jour annulée avant remplacement des fichiers. Consultez le journal : ' + ExpandConstant('{commonappdata}\\IMC-Clarodaro\\logs\\upgrade-preparation.log'));
    end;
  end;

end;

procedure CurUninstallStepChanged(CurUninstallStep: TUninstallStep);
var
  ResultCode: Integer;
  Parameters: String;
begin
  if CurUninstallStep = usUninstall then
  begin
    Parameters := '-NoProfile -ExecutionPolicy Bypass -File "' +
      ExpandConstant('{app}\installer\Remove-Windows-Services.ps1') +
      '" -AppRoot "' + ExpandConstant('{app}') + '"';
    if PurgeClarodaroData then
      Parameters := Parameters + ' -PurgeData';
    if not Exec(
      ExpandConstant('{sys}\WindowsPowerShell\v1.0\powershell.exe'),
      Parameters,
      ExpandConstant('{app}'),
      SW_HIDE,
      ewWaitUntilTerminated,
      ResultCode
    ) then
      RaiseException('Impossible de lancer le nettoyage des services Clarodaro.');
    if ResultCode <> 0 then
      RaiseException('Le nettoyage des services Clarodaro a échoué. Les données ProgramData sont conservées.');
  end;
end;

[Run]
Filename: "{sys}\cmd.exe"; Parameters: "/c start """" ""http://localhost:18080/"""; Description: "Ouvrir IMC-Clarodaro"; Flags: postinstall nowait skipifsilent

[UninstallDelete]
; Intentionally empty: uninstall must not delete .env, backups, logs or database data.
