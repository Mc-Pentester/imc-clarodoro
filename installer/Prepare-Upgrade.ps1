param(
    [Parameter(Mandatory = $true)][string]$AppRoot,
    [int]$HttpPort = 18080
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$AppRoot = [System.IO.Path]::GetFullPath($AppRoot)
$serviceName = 'IMC-Clarodaro-PostgreSQL'
$taskName = 'IMC-Clarodaro-PHP-Server'
$dataDirectory = Join-Path $env:ProgramData 'IMC-Clarodaro\PostgreSQL\data'
$logRoot = Join-Path $env:ProgramData 'IMC-Clarodaro\logs'
$logFile = Join-Path $logRoot 'upgrade-preparation.log'
$expectedPgCtl = Join-Path $env:ProgramData 'IMC-Clarodaro\runtime\postgresql\bin\pg_ctl.exe'
$expectedLauncher = Join-Path $AppRoot 'installer\Start-Clarodaro-Server.ps1'

function Write-UpgradeLog([string]$Message) {
    $line = '{0} {1}{2}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff'), $Message, [Environment]::NewLine
    try {
        New-Item -ItemType Directory -Path $logRoot -Force | Out-Null
        [System.IO.File]::AppendAllText($logFile, $line, ([System.Text.UTF8Encoding]::new($false)))
    } catch {
        [Console]::Error.WriteLine($line)
    }
}
trap {
    Write-UpgradeLog ('ERREUR : ' + $_.Exception.Message)
    Write-UpgradeLog ('DÉTAIL : ' + ($_ | Out-String))
    Write-Host ('ERREUR : ' + $_.Exception.Message) -ForegroundColor Red
    Write-Host ('Journal : ' + $logFile) -ForegroundColor Yellow
    exit 1
}

Write-UpgradeLog '=== Début de la préparation de mise à jour ==='
Write-UpgradeLog ('AppRoot=' + $AppRoot + '; HttpPort=' + $HttpPort)
Write-UpgradeLog ('Identité=' + [Security.Principal.WindowsIdentity]::GetCurrent().Name)

if (-not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    throw 'La préparation de mise à jour nécessite les droits administrateur.'
}

$task = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
if ($task) {
    Write-UpgradeLog ('Tâche trouvée : état=' + [string]$task.State + '; utilisateur=' + [string]$task.Principal.UserId)
    $taskAction = ($task.Actions | ForEach-Object { $_.Execute + ' ' + $_.Arguments }) -join ' '
    if ($taskAction -notlike "*$expectedLauncher*" -or [string]$task.Principal.UserId -notmatch "LOCAL SERVICE|S-1-5-19") {
        throw "La tâche $taskName ne correspond pas à cette installation. Aucun arrêt effectué."
    }
    Write-UpgradeLog ('Action de la tâche : ' + $taskAction)
    Stop-ScheduledTask -TaskName $taskName -ErrorAction Stop
    Write-UpgradeLog 'Demande Stop-ScheduledTask acceptée.'
    $expectedPhp = [System.IO.Path]::GetFullPath((Join-Path $AppRoot 'runtime\\php\\php.exe'))
    $deadline = (Get-Date).AddSeconds(45)
    do {
        $listener = Get-NetTCPConnection -State Listen -LocalPort $HttpPort -ErrorAction SilentlyContinue |
            Select-Object -First 1
        if (-not $listener) { Write-UpgradeLog 'Aucun écouteur sur le port HTTP ; arrêt PHP confirmé.'; break }

        $listenerProcess = Get-CimInstance Win32_Process -Filter "ProcessId=$($listener.OwningProcess)" -ErrorAction SilentlyContinue
        if (-not $listenerProcess -or -not $listenerProcess.ExecutablePath) {
            throw "Impossible d'identifier le processus qui écoute sur le port HTTP $HttpPort (PID $($listener.OwningProcess)). Aucun fichier ne sera remplacé."
        }
        Write-UpgradeLog ('Écouteur HTTP : PID=' + $listener.OwningProcess + '; exécutable=' + $listenerProcess.ExecutablePath)
        $actualExecutable = [System.IO.Path]::GetFullPath([string]$listenerProcess.ExecutablePath)
        if (-not [string]::Equals($actualExecutable, $expectedPhp, [StringComparison]::OrdinalIgnoreCase)) {
            throw "Le port HTTP $HttpPort est occupé par un autre programme : $actualExecutable. Aucun processus tiers ne sera arrêté."
        }
        Start-Sleep -Seconds 1
    } while ((Get-Date) -lt $deadline)

    $listener = Get-NetTCPConnection -State Listen -LocalPort $HttpPort -ErrorAction SilentlyContinue |
        Select-Object -First 1
    if ($listener) {
        Write-UpgradeLog ('Échec arrêt HTTP : PID=' + $listener.OwningProcess)
        throw "Le serveur PHP Clarodaro (PID $($listener.OwningProcess)) ne s'est pas arrêté sur le port $HttpPort. Mise à jour interrompue avant remplacement des fichiers."
    }
}

$service = Get-CimInstance Win32_Service -Filter "Name='$serviceName'" -ErrorAction SilentlyContinue
if ($service) {
    Write-UpgradeLog ('Service trouvé : état=' + $service.State + '; compte=' + $service.StartName + '; commande=' + $service.PathName)
    $serviceCommand = [string]$service.PathName
    $legacyPgCtl = Join-Path $AppRoot 'runtime\postgresql\bin\pg_ctl.exe'
    $knownRuntime = ($serviceCommand -like "*$expectedPgCtl*" -or $serviceCommand -like "*$legacyPgCtl*")
    if (-not $knownRuntime -or $serviceCommand -notlike "*$dataDirectory*" -or [string]$service.StartName -notmatch "NETWORK SERVICE|S-1-5-20") {
        throw "Le service $serviceName ne correspond pas à cette installation. Aucun arrêt effectué."
    }
    if ((Get-Service -Name $serviceName).Status -ne 'Stopped') {
        Write-UpgradeLog 'Demande arrêt du service PostgreSQL.'
        Stop-Service -Name $serviceName -Force
        (Get-Service -Name $serviceName).WaitForStatus('Stopped', [TimeSpan]::FromSeconds(60))
    }
}

Write-UpgradeLog 'Services Clarodaro arrêtés proprement avant remplacement des fichiers. Données ProgramData intactes.'
Write-Host 'Services Clarodaro arrêtés proprement avant remplacement des fichiers. Les données ProgramData restent intactes.'
Write-Host ('Journal : ' + $logFile)
