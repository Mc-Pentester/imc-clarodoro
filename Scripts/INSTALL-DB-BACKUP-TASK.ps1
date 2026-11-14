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

# Exécuter une première sauvegarde sous le même compte que la tâche quotidienne.
# Cela valide réellement l'accès au fichier .env, au runtime PostgreSQL et au dossier.
$before = Get-ChildItem -LiteralPath $backupFullPath -Filter '*.backup' -File -ErrorAction SilentlyContinue |
    Measure-Object -Property LastWriteTimeUtc -Maximum
$beforeTime = if ($before.Count -gt 0) { [datetime]$before.Maximum } else { [datetime]::MinValue }
Start-ScheduledTask -TaskName $TaskName
$deadline = (Get-Date).AddMinutes(5)
$verifiedBackup = $null
do {
    Start-Sleep -Seconds 3
    $candidate = Get-ChildItem -LiteralPath $backupFullPath -Filter '*.backup' -File -ErrorAction SilentlyContinue |
        Where-Object { $_.LastWriteTimeUtc -gt $beforeTime } |
        Sort-Object LastWriteTimeUtc -Descending |
        Select-Object -First 1
    if ($candidate -and (Test-Path -LiteralPath ($candidate.FullName + '.manifest.json') -PathType Leaf)) {
        $manifest = Get-Content -LiteralPath ($candidate.FullName + '.manifest.json') -Raw | ConvertFrom-Json
        $hash = (Get-FileHash -LiteralPath $candidate.FullName -Algorithm SHA256).Hash
        if ($manifest.sha256 -eq $hash -and [long]$manifest.sizeBytes -eq [long]$candidate.Length) {
            $verifiedBackup = $candidate
            break
        }
    }
    $taskInfo = Get-ScheduledTaskInfo -TaskName $TaskName -ErrorAction SilentlyContinue
    if ($taskInfo -and $taskInfo.LastRunTime -gt (Get-Date).AddMinutes(-5) -and $taskInfo.LastTaskResult -ne 0 -and (Get-ScheduledTask -TaskName $TaskName).State -ne 'Running') {
        throw "La première sauvegarde a échoué (LastTaskResult=$($taskInfo.LastTaskResult)). Vérifiez l'accès PostgreSQL et le journal des tâches."
    }
} while ((Get-Date) -lt $deadline)

if (-not $verifiedBackup) {
    $taskInfo = Get-ScheduledTaskInfo -TaskName $TaskName -ErrorAction SilentlyContinue
    throw "La tâche est installée mais aucune sauvegarde récente avec manifeste SHA-256 valide n'a été produite en 5 minutes (LastTaskResult=$($taskInfo.LastTaskResult))."
}
Write-Host "[OK] Première sauvegarde vérifiée : $($verifiedBackup.Name)"
Write-Host '[OK] Planification des sauvegardes installée.'
Write-Host "Sauvegarde quotidienne : $ScheduleTime"
Write-Host "Dossier : $backupFullPath"
Write-Host "Compte : $identity"
Write-Host "Copie externe : toutes les 6 heures vers le support portant l'étiquette IMC_BACKUPS"
