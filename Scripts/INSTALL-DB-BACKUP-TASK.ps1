param(
    [Parameter(Mandatory = $true)][string]$AppRoot,
    [Parameter(Mandatory = $true)][string]$EnvironmentFile,
    [string]$BackupDirectory = '',
    [string]$PgBin = '',
    [string]$ScheduleTime = '02:30',
    [string]$TaskName = 'IMC-Clarodaro PostgreSQL Backup',
    [string]$CopyTaskName = 'IMC-Clarodaro Backup Copy to USB'
)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$AppRoot = [IO.Path]::GetFullPath($AppRoot)
$EnvironmentFile = [IO.Path]::GetFullPath($EnvironmentFile)
if (-not (Test-Path -LiteralPath $EnvironmentFile -PathType Leaf)) {
    throw "Configuration protégée introuvable : $EnvironmentFile"
}
if ([string]::IsNullOrWhiteSpace($BackupDirectory)) {
    $BackupDirectory = Join-Path $AppRoot 'backups'
}
if ([string]::IsNullOrWhiteSpace($PgBin)) {
    $PgBin = Join-Path $env:ProgramData 'IMC-Clarodaro\runtime\postgresql\bin'
}
$PgBin = [IO.Path]::GetFullPath($PgBin)
$backupFullPath = [IO.Path]::GetFullPath($BackupDirectory)
$runner = Join-Path $PSScriptRoot 'RUN-DB-BACKUP.ps1'
$copyScript = Join-Path $PSScriptRoot 'COPY-DB-BACKUPS-TO-EXTERNAL.ps1'

foreach ($required in @("$PgBin\pg_dump.exe", "$PgBin\pg_restore.exe", "$PgBin\psql.exe", (Join-Path $PSScriptRoot 'DB-BACKUP-RESTORE.ps1'), $runner, $copyScript)) {
    if (-not (Test-Path -LiteralPath $required -PathType Leaf)) {
        throw "Fichier requis pour la sauvegarde absent : $required"
    }
}
if ($ScheduleTime -notmatch '^([01]\d|2[0-3]):[0-5]\d$') {
    throw 'ScheduleTime doit être au format HH:mm.'
}

New-Item -ItemType Directory -Path $backupFullPath -Force | Out-Null
# Le dossier de sauvegarde est accessible en modification uniquement au service PHP
# (LOCAL SERVICE), aux administrateurs et à SYSTEM.
& icacls.exe $backupFullPath /grant '*S-1-5-19:(OI)(CI)M' '*S-1-5-18:(OI)(CI)F' '*S-1-5-32-544:(OI)(CI)F' /T /C | Out-Null
if ($LASTEXITCODE -ne 0) { throw "Impossible de configurer les droits du dossier de sauvegarde : $backupFullPath" }

$identity = 'NT AUTHORITY\LOCAL SERVICE'
$principal = New-ScheduledTaskPrincipal -UserId $identity -LogonType ServiceAccount -RunLevel Limited
$settings = New-ScheduledTaskSettingsSet -StartWhenAvailable -ExecutionTimeLimit (New-TimeSpan -Hours 1) -MultipleInstances IgnoreNew
$arguments = "-NoProfile -NonInteractive -ExecutionPolicy Bypass -File `"$runner`" -AppRoot `"$AppRoot`" -EnvironmentFile `"$EnvironmentFile`" -PgBin `"$PgBin`" -BackupDirectory `"$backupFullPath`""
$action = New-ScheduledTaskAction -Execute 'PowerShell.exe' -Argument $arguments -WorkingDirectory $AppRoot
$trigger = New-ScheduledTaskTrigger -Daily -At ([datetime]::ParseExact($ScheduleTime, 'HH:mm', $null))
Register-ScheduledTask -TaskName $TaskName -Action $action -Trigger $trigger -Principal $principal -Settings $settings -Force | Out-Null

$copyArguments = "-NoProfile -NonInteractive -ExecutionPolicy Bypass -File `"$copyScript`" -SourceDirectory `"$backupFullPath`""
$copyAction = New-ScheduledTaskAction -Execute 'PowerShell.exe' -Argument $copyArguments -WorkingDirectory $AppRoot
$copyTrigger = New-ScheduledTaskTrigger -Once -At (Get-Date).AddMinutes(5) -RepetitionInterval (New-TimeSpan -Hours 6) -RepetitionDuration (New-TimeSpan -Days 3650)
$copySettings = New-ScheduledTaskSettingsSet -StartWhenAvailable -ExecutionTimeLimit (New-TimeSpan -Minutes 30) -MultipleInstances IgnoreNew
Register-ScheduledTask -TaskName $CopyTaskName -Action $copyAction -Trigger $copyTrigger -Principal $principal -Settings $copySettings -Force | Out-Null

# Vérifie que les tâches sont réellement enregistrées sous le compte de service attendu.
foreach ($name in @($TaskName, $CopyTaskName)) {
    $registered = Get-ScheduledTask -TaskName $name -ErrorAction Stop
    if ([string]$registered.Principal.UserId -notmatch 'LOCAL SERVICE|S-1-5-19') {
        throw "La tâche $name n'est pas enregistrée sous LOCAL SERVICE."
    }
}
Write-Host '[OK] Planification des sauvegardes installée.'
Write-Host "Sauvegarde quotidienne : $ScheduleTime"
Write-Host "Dossier : $backupFullPath"
Write-Host "Compte : $identity"
Write-Host "Copie externe : toutes les 6 heures vers le support portant l'étiquette IMC_BACKUPS"
