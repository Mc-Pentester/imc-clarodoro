param(
    [Parameter(Mandatory = $true)][string]$AppRoot
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$AppRoot = [System.IO.Path]::GetFullPath($AppRoot)
$programDataRoot = Join-Path $env:ProgramData 'IMC-Clarodaro'
$dataDirectory = Join-Path $programDataRoot 'PostgreSQL\data'
$serviceName = 'IMC-Clarodaro-PostgreSQL'
$taskName = 'IMC-Clarodaro-PHP-Server'
$expectedPgCtl = Join-Path $AppRoot 'runtime\postgresql\bin\pg_ctl.exe'
$expectedLauncher = Join-Path $AppRoot 'installer\Start-Clarodaro-Server.ps1'

trap {
    Write-Host ('ERREUR : ' + $_.Exception.Message) -ForegroundColor Red
    exit 1
}

if (-not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    throw 'La désinstallation des services nécessite les droits administrateur.'
}

$task = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
if ($task) {
    $taskAction = ($task.Actions | ForEach-Object { $_.Execute + ' ' + $_.Arguments }) -join ' '
    if ($taskAction -notlike "*$expectedLauncher*" -or [string]$task.Principal.UserId -notmatch "LOCAL SERVICE") {
        throw "La tâche $taskName ne correspond pas à cette installation. Elle est conservée."
    }
    Stop-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
    $taskStopDeadline = (Get-Date).AddSeconds(20)
    while ((Get-NetTCPConnection -State Listen -LocalPort 8080 -ErrorAction SilentlyContinue | Select-Object -First 1) -and (Get-Date) -lt $taskStopDeadline) {
        Start-Sleep -Seconds 1
    }
    if (Get-NetTCPConnection -State Listen -LocalPort 8080 -ErrorAction SilentlyContinue | Select-Object -First 1) {
        throw 'Le serveur PHP na pas libéré le port 8080. Désinstallation interrompue pour éviter un processus orphelin.'
    }
    Unregister-ScheduledTask -TaskName $taskName -Confirm:$false
}

$service = Get-CimInstance Win32_Service -Filter "Name='$serviceName'" -ErrorAction SilentlyContinue
if ($service) {
    $serviceCommand = [string]$service.PathName
    if ($serviceCommand -notlike "*$expectedPgCtl*" -or $serviceCommand -notlike "*$dataDirectory*" -or [string]$service.StartName -notmatch "NETWORK SERVICE") {
        throw "Le service $serviceName ne correspond pas à cette installation. Il est conservé."
    }
    if ((Get-Service -Name $serviceName).Status -ne 'Stopped') {
        Stop-Service -Name $serviceName -Force
        (Get-Service -Name $serviceName).WaitForStatus('Stopped', [TimeSpan]::FromSeconds(45))
    }
    & sc.exe delete $serviceName | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "Impossible de désenregistrer le service $serviceName." }
    $deleteDeadline = (Get-Date).AddSeconds(20)
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
