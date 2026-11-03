param(
    [Parameter(Mandatory = $true)][string]$AppRoot
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$AppRoot = [System.IO.Path]::GetFullPath($AppRoot)
$programDataRoot = Join-Path $env:ProgramData 'IMC-Clarodaro'
$logRoot = Join-Path $programDataRoot 'logs'
if (Test-Path -LiteralPath $logRoot -PathType Container) {
    try { Start-Transcript -Path (Join-Path $logRoot 'uninstall-services.log') -Append | Out-Null } catch {}
}
$dataDirectory = Join-Path $programDataRoot 'PostgreSQL\data'
$serviceName = 'IMC-Clarodaro-PostgreSQL'
$taskName = 'IMC-Clarodaro-PHP-Server'
$expectedPgCtl = Join-Path $env:ProgramData 'IMC-Clarodaro\runtime\postgresql\bin\pg_ctl.exe'
$expectedLauncher = Join-Path $AppRoot 'installer\Start-Clarodaro-Server.ps1'

trap {
    Write-Host ('ERREUR : ' + $_.Exception.Message) -ForegroundColor Red
    try { Stop-Transcript | Out-Null } catch {}
    exit 1
}

if (-not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    throw 'La désinstallation des services nécessite les droits administrateur.'
}

$task = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
if ($task) {
    $taskAction = ($task.Actions | ForEach-Object { $_.Execute + ' ' + $_.Arguments }) -join ' '
    if ($taskAction -notlike "*$expectedLauncher*" -or [string]$task.Principal.UserId -notmatch "LOCAL SERVICE|S-1-5-19") {
        throw "La tâche $taskName ne correspond pas à cette installation. Elle est conservée."
    }
    Stop-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
    $taskStopDeadline = (Get-Date).AddSeconds(30)
    do {
        $currentTask = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
        $listener = Get-NetTCPConnection -State Listen -LocalPort 8080 -ErrorAction SilentlyContinue | Select-Object -First 1
        if (-not $listener -and (-not $currentTask -or [string]$currentTask.State -ne 'Running')) { break }
        Start-Sleep -Seconds 1
    } while ((Get-Date) -lt $taskStopDeadline)
    if (Get-NetTCPConnection -State Listen -LocalPort 8080 -ErrorAction SilentlyContinue | Select-Object -First 1) {
        throw 'Le serveur PHP n’a pas libéré le port 8080. Désinstallation interrompue pour éviter un processus orphelin.'
    }
    Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction Stop
}

$service = Get-CimInstance Win32_Service -Filter "Name='$serviceName'" -ErrorAction SilentlyContinue
if ($service) {
    $serviceCommand = [string]$service.PathName
    $legacyPgCtl = Join-Path $AppRoot 'runtime\postgresql\bin\pg_ctl.exe'
    $knownRuntime = ($serviceCommand -like "*$expectedPgCtl*" -or $serviceCommand -like "*$legacyPgCtl*")
    if (-not $knownRuntime -or $serviceCommand -notlike "*$dataDirectory*" -or [string]$service.StartName -notmatch "NETWORK SERVICE|S-1-5-20") {
        throw "Le service $serviceName ne correspond pas à cette installation. Il est conservé."
    }
    if ((Get-Service -Name $serviceName).Status -ne 'Stopped') {
        Stop-Service -Name $serviceName -Force
        (Get-Service -Name $serviceName).WaitForStatus('Stopped', [TimeSpan]::FromSeconds(45))
    }
    & sc.exe delete $serviceName | Out-Null
    $deleteExitCode = $LASTEXITCODE
    # 1072 = ERROR_SERVICE_MARKED_FOR_DELETE; accept only this documented pending state.
    if ($deleteExitCode -ne 0 -and $deleteExitCode -ne 1072) {
        throw "Impossible de désenregistrer le service $serviceName (sc.exe exit code $deleteExitCode)."
    }
    $deleteDeadline = (Get-Date).AddSeconds(60)
    while ((Get-CimInstance Win32_Service -Filter "Name='$serviceName'" -ErrorAction SilentlyContinue) -and (Get-Date) -lt $deleteDeadline) {
        Start-Sleep -Seconds 1
    }
    if (Get-CimInstance Win32_Service -Filter "Name='$serviceName'" -ErrorAction SilentlyContinue) {
        throw "Le service $serviceName reste en attente de suppression. Les fichiers ne doivent pas être retirés."
    }
}

$firewallRule = Get-NetFirewallRule -DisplayName 'IMC-Clarodaro HTTP LAN' -ErrorAction SilentlyContinue
if ($firewallRule) {
    $firewallRule | Remove-NetFirewallRule
}

Write-Host 'Services et tâche Clarodaro retirés. Les données PostgreSQL, la configuration, les sauvegardes et les journaux ProgramData sont conservés.'
try { Stop-Transcript | Out-Null } catch {}
