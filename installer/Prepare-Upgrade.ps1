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
    $expectedPhp = [System.IO.Path]::GetFullPath((Join-Path $AppRoot 'runtime\php\php.exe'))
    $expectedRouter = [System.IO.Path]::GetFullPath((Join-Path $AppRoot 'router.php'))
    $deadline = (Get-Date).AddSeconds(45)
    $graceDeadline = (Get-Date).AddSeconds(5)
    $forcedStopAttempted = $false

    do {
        $listener = Get-NetTCPConnection -State Listen -LocalPort $HttpPort -ErrorAction SilentlyContinue |
            Select-Object -First 1
        if (-not $listener) {
            Write-UpgradeLog 'Aucun écouteur sur le port HTTP ; arrêt PHP confirmé.'
            break
        }

        $listenerPid = [int]$listener.OwningProcess
        $listenerProcess = Get-CimInstance Win32_Process -Filter "ProcessId=$listenerPid" -ErrorAction SilentlyContinue
        if (-not $listenerProcess) {
            throw "Impossible d'identifier le processus qui écoute sur le port HTTP $HttpPort (PID $listenerPid). Aucun fichier ne sera remplacé."
        }

        $executablePath = [string]$listenerProcess.ExecutablePath
        if ([string]::IsNullOrWhiteSpace($executablePath)) {
            # CIM can omit ExecutablePath even for an accessible process. Get-Process
            # provides a second read path; never infer identity from the PID alone.
            $processInfo = Get-Process -Id $listenerPid -ErrorAction SilentlyContinue
            if ($processInfo) { $executablePath = [string]$processInfo.Path }
        }
        $commandLine = [string]$listenerProcess.CommandLine
        if ([string]::IsNullOrWhiteSpace($executablePath) -or [string]::IsNullOrWhiteSpace($commandLine)) {
            throw "Impossible de confirmer l'identité complète du processus HTTP (PID $listenerPid). Aucun fichier ne sera remplacé."
        }

        $actualExecutable = [System.IO.Path]::GetFullPath($executablePath)
        $isExpectedExecutable = [string]::Equals($actualExecutable, $expectedPhp, [StringComparison]::OrdinalIgnoreCase)
        $hasExpectedRouter = $commandLine.IndexOf($expectedRouter, [StringComparison]::OrdinalIgnoreCase) -ge 0
        $hasExpectedAppRoot = $commandLine.IndexOf($AppRoot, [StringComparison]::OrdinalIgnoreCase) -ge 0
        $hasExpectedPort = $commandLine -match ('(?i)(?:^|\s)-S\s+["'']?0\.0\.0\.0:' + $HttpPort + '["'']?(?:\s|$)')

        Write-UpgradeLog ('Écouteur HTTP : PID=' + $listenerPid + '; exécutable=' + $actualExecutable + '; commande=' + $commandLine)
        if (-not $isExpectedExecutable -or -not $hasExpectedRouter -or -not $hasExpectedAppRoot -or -not $hasExpectedPort) {
            throw "Le port HTTP $HttpPort est occupé par un processus qui ne peut pas être authentifié comme le serveur Clarodaro attendu (PID $listenerPid). Aucun processus tiers ne sera arrêté."
        }

        if (-not $forcedStopAttempted -and (Get-Date) -ge $graceDeadline) {
            # Re-read the listener and process immediately before termination to
            # prevent killing a recycled PID or a process that took over the port.
            $currentListener = Get-NetTCPConnection -State Listen -LocalPort $HttpPort -ErrorAction SilentlyContinue |
                Select-Object -First 1
            if ($currentListener -and [int]$currentListener.OwningProcess -eq $listenerPid) {
                $currentProcess = Get-CimInstance Win32_Process -Filter "ProcessId=$listenerPid" -ErrorAction SilentlyContinue
                $currentPath = if ($currentProcess) { [string]$currentProcess.ExecutablePath } else { '' }
                if ([string]::IsNullOrWhiteSpace($currentPath)) {
                    $currentProcessInfo = Get-Process -Id $listenerPid -ErrorAction SilentlyContinue
                    if ($currentProcessInfo) { $currentPath = [string]$currentProcessInfo.Path }
                }
                $currentCommand = if ($currentProcess) { [string]$currentProcess.CommandLine } else { '' }
                $currentExecutableMatches = $false
                if (-not [string]::IsNullOrWhiteSpace($currentPath)) {
                    $currentExecutableMatches = [string]::Equals([System.IO.Path]::GetFullPath($currentPath), $expectedPhp, [StringComparison]::OrdinalIgnoreCase)
                }
                $currentIdentityMatches = $currentExecutableMatches -and
                    $currentCommand.IndexOf($expectedRouter, [StringComparison]::OrdinalIgnoreCase) -ge 0 -and
                    $currentCommand.IndexOf($AppRoot, [StringComparison]::OrdinalIgnoreCase) -ge 0 -and
                    ($currentCommand -match ('(?i)(?:^|\s)-S\s+["'']?0\.0\.0\.0:' + $HttpPort + '["'']?(?:\s|$)'))
                if (-not $currentIdentityMatches) {
                    throw "L'identité du processus HTTP (PID $listenerPid) a changé avant son arrêt. Aucun processus ne sera arrêté."
                }

                Write-UpgradeLog ("Arrêt forcé du processus PHP Clarodaro authentifié : PID=$listenerPid.")
                try {
                    Stop-Process -Id $listenerPid -Force -ErrorAction Stop
                    Wait-Process -Id $listenerPid -Timeout 15 -ErrorAction SilentlyContinue
                    Write-UpgradeLog ("Commande d'arrêt envoyée au processus PHP PID=$listenerPid.")
                } catch {
                    throw "Impossible d'arrêter le processus PHP Clarodaro authentifié (PID $listenerPid). Vérifiez les droits administrateur. Détail : $($_.Exception.Message)"
                }
                $forcedStopAttempted = $true
            }
        }

        Start-Sleep -Seconds 1
    } while ((Get-Date) -lt $deadline)

    $listener = Get-NetTCPConnection -State Listen -LocalPort $HttpPort -ErrorAction SilentlyContinue |
        Select-Object -First 1
    if ($listener) {
        Write-UpgradeLog ('Échec arrêt HTTP : PID=' + $listener.OwningProcess)
        throw "Le serveur PHP Clarodaro (PID $($listener.OwningProcess)) écoute toujours sur le port $HttpPort. Mise à jour interrompue avant remplacement des fichiers."
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
