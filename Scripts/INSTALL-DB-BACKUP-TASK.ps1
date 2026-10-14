param(
    [string]$TaskName = 'IMC-Clarodoro PostgreSQL Backup',
    [string]$BackupDirectory = (Join-Path $PSScriptRoot '..\backups'),
    [string]$ScheduleTime = '14:30',
    [string]$PgBin = 'C:\Program Files\PostgreSQL\18\bin'
)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

if (-not (Test-Path -LiteralPath "$PgBin\pg_dump.exe")) { throw "pg_dump introuvable dans $PgBin" }
if (-not (Test-Path -LiteralPath "$PSScriptRoot\DB-BACKUP-RESTORE.ps1")) { throw 'Script de sauvegarde introuvable.' }

$backupFullPath = [IO.Path]::GetFullPath($BackupDirectory)
New-Item -ItemType Directory -Path $backupFullPath -Force | Out-Null

# Le mot de passe n'est jamais écrit dans le script ni dans les arguments de la tâche.
# pg_dump lit le fichier pgpass de l'utilisateur qui exécute la tâche.
$pgpass = Join-Path $env:APPDATA 'postgresql\pgpass.conf'
$pgpassDir = Split-Path $pgpass -Parent
New-Item -ItemType Directory -Path $pgpassDir -Force | Out-Null

if (-not (Test-Path -LiteralPath $pgpass)) {
    $secure = Read-Host 'Mot de passe PostgreSQL pour postgres' -AsSecureString
    $password = [System.Net.NetworkCredential]::new('', $secure).Password
    $line = "localhost:5432:imc_clarodoro:postgres:$password"
    Set-Content -LiteralPath $pgpass -Value $line -Encoding ascii -NoNewline
}

# Restreint le fichier pgpass au compte courant avec l'outil Windows ACL.
# Set-Acl peut échouer sur certaines configurations Windows en demandant
# SeSecurityPrivilege. icacls modifie la DACL sans demander ce privilège.
$identity = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
& "$env:SystemRoot\System32\icacls.exe" $pgpass /inheritance:r /grant:r "$($identity):(F)" | Out-Null
if ($LASTEXITCODE -ne 0) {
    throw "Impossible de restreindre les droits de $pgpass (icacls code $LASTEXITCODE). Aucun planificateur n'a été enregistré."
}

$runner = Join-Path $PSScriptRoot 'RUN-DB-BACKUP.ps1'
$runnerContent = @"
`$ErrorActionPreference = 'Stop'
Set-Location -LiteralPath '$((Split-Path $PSScriptRoot -Parent))'
`$env:DB_HOST = 'localhost'
`$env:DB_PORT = '5432'
`$env:DB_NAME = 'imc_clarodoro'
`$env:DB_USER = 'postgres'
`$env:PGPASSFILE = '$pgpass'
`$env:Path = '$PgBin;' + [Environment]::GetEnvironmentVariable('Path','Machine')
& '$PSScriptRoot\DB-BACKUP-RESTORE.ps1' -Mode Backup
if (`$LASTEXITCODE -ne 0) { exit `$LASTEXITCODE }
"@
Set-Content -LiteralPath $runner -Value $runnerContent -Encoding utf8

$action = New-ScheduledTaskAction -Execute 'PowerShell.exe' -Argument "-NoProfile -NonInteractive -ExecutionPolicy Bypass -File `"$runner`""
$trigger = New-ScheduledTaskTrigger -Daily -At ([datetime]::ParseExact($ScheduleTime, 'HH:mm', $null))
$principal = New-ScheduledTaskPrincipal -UserId $identity -LogonType Interactive -RunLevel Limited
$settings = New-ScheduledTaskSettingsSet -StartWhenAvailable -ExecutionTimeLimit (New-TimeSpan -Hours 1) -MultipleInstances IgnoreNew
Register-ScheduledTask -TaskName $TaskName -Action $action -Trigger $trigger -Principal $principal -Settings $settings -Force | Out-Null

Write-Host '[OK] Tâche de sauvegarde quotidienne installée.'
Write-Host "Nom : $TaskName"
Write-Host "Heure : $ScheduleTime chaque jour"
Write-Host "Dossier : $backupFullPath"
Write-Host "Compte : $identity"
Write-Host "Exécutez ensuite : Get-ScheduledTask -TaskName '$TaskName' | Get-ScheduledTaskInfo"
