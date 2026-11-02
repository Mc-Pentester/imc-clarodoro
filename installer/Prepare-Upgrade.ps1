param(
    [Parameter(Mandatory = $true)][string]$AppRoot
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$AppRoot = [System.IO.Path]::GetFullPath($AppRoot)
$serviceName = 'IMC-Clarodaro-PostgreSQL'
$taskName = 'IMC-Clarodaro-PHP-Server'
$dataDirectory = Join-Path $env:ProgramData 'IMC-Clarodaro\PostgreSQL\data'
$expectedPgCtl = Join-Path $AppRoot 'runtime\postgresql\bin\pg_ctl.exe'
$expectedLauncher = Join-Path $AppRoot 'installer\Start-Clarodaro-Server.ps1'

trap {
    Write-Host ('ERREUR : ' + $_.Exception.Message) -ForegroundColor Red
    exit 1
}

if (-not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    throw 'La préparation de mise à jour nécessite les droits administrateur.'
}

$task = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
if ($task) {
    $taskAction = ($task.Actions | ForEach-Object { $_.Execute + ' ' + $_.Arguments }) -join ' '
    if ($taskAction -notlike "*$expectedLauncher*" -or [string]$task.Principal.UserId -notmatch "LOCAL SERVICE") {
        throw "La tâche $taskName ne correspond pas à cette installation. Aucun arrêt effectué."
    }
    Stop-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
    $deadline = (Get-Date).AddSeconds(25)
    while ((Get-NetTCPConnection -State Listen -LocalPort 8080 -ErrorAction SilentlyContinue | Select-Object -First 1) -and (Get-Date) -lt $deadline) {
        Start-Sleep -Seconds 1
    }
    if (Get-NetTCPConnection -State Listen -LocalPort 8080 -ErrorAction SilentlyContinue | Select-Object -First 1) {
        throw 'Le serveur PHP ne sest pas arrêté. Mise à jour interrompue avant remplacement des fichiers.'
    }
}

$service = Get-CimInstance Win32_Service -Filter "Name='$serviceName'" -ErrorAction SilentlyContinue
if ($service) {
    $serviceCommand = [string]$service.PathName
    if ($serviceCommand -notlike "*$expectedPgCtl*" -or $serviceCommand -notlike "*$dataDirectory*" -or [string]$service.StartName -notmatch "NETWORK SERVICE") {
        throw "Le service $serviceName ne correspond pas à cette installation. Aucun arrêt effectué."
    }
    if ((Get-Service -Name $serviceName).Status -ne 'Stopped') {
        Stop-Service -Name $serviceName -Force
        (Get-Service -Name $serviceName).WaitForStatus('Stopped', [TimeSpan]::FromSeconds(60))
    }
}

Write-Host 'Services Clarodaro arrêtés proprement avant remplacement des fichiers. Les données ProgramData restent intactes.'
