param(
    [Parameter(Mandatory = $true)][string]$AppRoot
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$AppRoot = [System.IO.Path]::GetFullPath($AppRoot)
$programDataRoot = Join-Path $env:ProgramData 'IMC-Clarodaro'
$logRoot = Join-Path $programDataRoot 'logs'
$logFile = Join-Path $logRoot 'uninstall-services.log'
$dataDirectory = Join-Path $programDataRoot 'PostgreSQL\data'
$serviceName = 'IMC-Clarodaro-PostgreSQL'
$taskName = 'IMC-Clarodaro-PHP-Server'
$expectedPgCtl = Join-Path $env:ProgramData 'IMC-Clarodaro\runtime\postgresql\bin\pg_ctl.exe'
$expectedLauncher = Join-Path $AppRoot 'installer\Start-Clarodaro-Server.ps1'

function Write-RemovalLog([string]$Message) {
    $line = '{0} {1}{2}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff'), $Message, [Environment]::NewLine
    try {
        New-Item -ItemType Directory -Path $logRoot -Force | Out-Null
        [System.IO.File]::AppendAllText($logFile, $line, ([System.Text.UTF8Encoding]::new($false)))
    }
    catch {
        [Console]::Error.WriteLine($line)
        throw
    }
}

try {
    Write-RemovalLog 'Début du retrait des ressources Windows Clarodaro.'
    Write-RemovalLog ("Application : " + $AppRoot)
    Write-RemovalLog ("Identité : " + [Security.Principal.WindowsIdentity]::GetCurrent().Name)

    if (-not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        throw 'La désinstallation des services nécessite les droits administrateur.'
    }

    $task = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
    if ($task) {
        $taskAction = ($task.Actions | ForEach-Object { $_.Execute + ' ' + $_.Arguments }) -join ' '
        if ($taskAction -notlike "*$expectedLauncher*" -or [string]$task.Principal.UserId -notmatch 'LOCAL SERVICE|S-1-5-19') {
            throw "La tâche $taskName ne correspond pas à cette installation. Elle est conservée."
        }

        if ([string]$task.State -eq 'Running') {
            Write-RemovalLog 'Arrêt de la tâche PHP Clarodaro.'
            Stop-ScheduledTask -TaskName $taskName -ErrorAction Stop
        }
        else {
            Write-RemovalLog ("La tâche PHP est déjà à l'état " + [string]$task.State + ' ; aucun arrêt forcé nécessaire.')
        }
        $taskStopDeadline = (Get-Date).AddSeconds(45)
        do {
            $currentTask = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
            $listener = Get-NetTCPConnection -State Listen -LocalPort 8080 -ErrorAction SilentlyContinue |
                Select-Object -First 1
            if (-not $listener -and (-not $currentTask -or [string]$currentTask.State -ne 'Running')) { break }
            Start-Sleep -Seconds 1
        } while ((Get-Date) -lt $taskStopDeadline)

        $listener = Get-NetTCPConnection -State Listen -LocalPort 8080 -ErrorAction SilentlyContinue |
            Select-Object -First 1
        if ($listener) {
            throw "Le port 8080 reste occupé (PID $($listener.OwningProcess)). La tâche n'est pas supprimée."
        }

        $currentTask = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
        if ($currentTask -and [string]$currentTask.State -eq 'Running') {
            throw 'La tâche PHP est toujours active ; désinstallation interrompue.'
        }

        Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction Stop
        Write-RemovalLog 'Tâche planifiée PHP supprimée.'
    }
    else {
        Write-RemovalLog 'Aucune tâche PHP Clarodaro à supprimer.'
    }

    $service = Get-CimInstance Win32_Service -Filter "Name='$serviceName'" -ErrorAction SilentlyContinue
    if ($service) {
        $serviceCommand = [string]$service.PathName
        $serviceAccount = [string]$service.StartName
        $legacyPgCtl = Join-Path $AppRoot 'runtime\postgresql\bin\pg_ctl.exe'
        $knownRuntime = ($serviceCommand -like "*$expectedPgCtl*" -or $serviceCommand -like "*$legacyPgCtl*")
        if (-not $knownRuntime -or $serviceCommand -notlike "*$dataDirectory*" -or $serviceAccount -notmatch 'NETWORK SERVICE|S-1-5-20') {
            throw "Le service $serviceName ne correspond pas à cette installation. Il est conservé."
        }

        Write-RemovalLog ("Service identifié : état=" + $service.State + "; compte=" + $serviceAccount + '; commande=' + $serviceCommand)
        $service = $null

        $serviceStatus = Get-Service -Name $serviceName -ErrorAction Stop
        if ($serviceStatus.Status -ne 'Stopped') {
            Write-RemovalLog 'Arrêt du service PostgreSQL Clarodaro.'
            Stop-Service -Name $serviceName -Force -ErrorAction Stop
            $serviceStatus = Get-Service -Name $serviceName -ErrorAction Stop
            $serviceStatus.WaitForStatus('Stopped', [TimeSpan]::FromSeconds(60))
        }

        $serviceStatus = Get-Service -Name $serviceName -ErrorAction Stop
        if ($serviceStatus.Status -ne 'Stopped') {
            throw "Le service PostgreSQL n'est pas arrêté ; aucune suppression demandée."
        }

        Write-RemovalLog 'Demande de suppression du service PostgreSQL Clarodaro.'
        $scOutput = @(& sc.exe delete $serviceName 2>&1)
        $deleteExitCode = $LASTEXITCODE
        foreach ($line in $scOutput) { Write-RemovalLog ("sc.exe : " + [string]$line) }

        # 1072 = ERROR_SERVICE_MARKED_FOR_DELETE. Both 0 and 1072 mean the SCM
        # accepted deletion. The service record can remain visible until this
        # process releases its SCM handles, so do not block uninstall on WMI polling.
        if ($deleteExitCode -ne 0 -and $deleteExitCode -ne 1072) {
            throw "Impossible de désenregistrer le service $serviceName (sc.exe exit code $deleteExitCode)."
        }
        Write-RemovalLog ("Suppression du service acceptée par Windows (code " + $deleteExitCode + ').')
    }
    else {
        Write-RemovalLog 'Aucun service PostgreSQL Clarodaro à supprimer.'
    }

    $firewallRule = Get-NetFirewallRule -DisplayName 'IMC-Clarodaro HTTP LAN' -ErrorAction SilentlyContinue
    if ($firewallRule) {
        $firewallRule | Remove-NetFirewallRule -ErrorAction Stop
        Write-RemovalLog 'Règle pare-feu HTTP LAN supprimée.'
    }
    else {
        Write-RemovalLog 'Aucune règle pare-feu HTTP LAN à supprimer.'
    }

    Write-RemovalLog 'Nettoyage terminé. PostgreSQL data, configuration, secrets, sauvegardes, fichiers téléversés et journaux ProgramData sont conservés.'
    exit 0
}
catch {
    try {
        Write-RemovalLog ("ERREUR : " + $_.Exception.Message)
        Write-RemovalLog ("Détail : " + ($_ | Out-String))
    }
    catch {
        [Console]::Error.WriteLine("Échec du nettoyage Clarodaro : " + $_.Exception.Message)
    }
    exit 1
}
