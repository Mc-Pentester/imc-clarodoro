param(
    [Parameter(Mandatory = $true)][string]$AppRoot,
    [int]$PostgreSqlPort = 55432,
    [int]$HttpPort = 8080
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$script:TranscriptStarted = $false
trap {
    Write-Host ('ERREUR : ' + $_.Exception.Message) -ForegroundColor Red
    if ($script:TranscriptStarted) { try { Stop-Transcript | Out-Null } catch {} }
    exit 1
}

function Write-Step([string]$Message) {
    Write-Host "[Clarodaro] $Message"
}

function Set-PrivateAcl([string]$Path) {
    $inheritance = if (Test-Path -LiteralPath $Path -PathType Container) { '(OI)(CI)F' } else { 'F' }
    & icacls.exe $Path /inheritance:r /grant:r "*S-1-5-18:$inheritance" "*S-1-5-32-544:$inheritance" | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "Impossible de protéger les permissions : $Path" }
}

function Test-PortAvailable([int]$Port) {
    $listener = Get-NetTCPConnection -State Listen -LocalPort $Port -ErrorAction SilentlyContinue |
        Select-Object -First 1
    return ($null -eq $listener)
}

$AppRoot = [System.IO.Path]::GetFullPath($AppRoot)
$programDataRoot = Join-Path $env:ProgramData 'IMC-Clarodaro'
$configRoot = Join-Path $programDataRoot 'config'
$dataRoot = Join-Path $programDataRoot 'PostgreSQL'
$dataDirectory = Join-Path $dataRoot 'data'
$logRoot = Join-Path $programDataRoot 'logs'
$environmentFile = Join-Path $configRoot '.env'
$adminSecretFile = Join-Path $configRoot 'postgres-admin.secret'
$provisioningMarker = Join-Path $configRoot 'initial-provisioning-incomplete.marker'
$serviceName = 'IMC-Clarodaro-PostgreSQL'
$taskName = 'IMC-Clarodaro-PHP-Server'
$pgBin = Join-Path $AppRoot 'runtime\postgresql\bin'
$pgCtl = Join-Path $pgBin 'pg_ctl.exe'
$initdb = Join-Path $pgBin 'initdb.exe'
$psql = Join-Path $pgBin 'psql.exe'
$pgIsReady = Join-Path $pgBin 'pg_isready.exe'
$php = Join-Path $AppRoot 'runtime\php\php.exe'

if (-not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    throw 'Cette configuration doit être exécutée en administrateur.'
}
foreach ($required in @($pgCtl, $initdb, $psql, $pgIsReady, $php)) {
    if (-not (Test-Path -LiteralPath $required -PathType Leaf)) {
        throw "Runtime requis absent : $required"
    }
}
if ($PostgreSqlPort -lt 1024 -or $PostgreSqlPort -gt 65535 -or $HttpPort -lt 1024 -or $HttpPort -gt 65535) {
    throw 'Port invalide.'
}

New-Item -ItemType Directory -Path $configRoot, $dataRoot, $logRoot -Force | Out-Null
Set-PrivateAcl $logRoot
Start-Transcript -Path (Join-Path $logRoot 'installer-services.log') -Append | Out-Null
$script:TranscriptStarted = $true
Set-PrivateAcl $configRoot
if (Test-Path -LiteralPath $provisioningMarker) {
    throw 'Une initialisation précédente est incomplète. Le serveur ne sera pas démarré automatiquement ; consulter le journal et réparer la base manuellement.'
}

$legacyEnvironmentFile = Join-Path $AppRoot '.env'
$hasProtectedConfig = Test-Path -LiteralPath $environmentFile -PathType Leaf
$hasLegacyConfig = Test-Path -LiteralPath $legacyEnvironmentFile -PathType Leaf
$service = Get-CimInstance Win32_Service -Filter "Name='$serviceName'" -ErrorAction SilentlyContinue

if ($service) {
    $serviceCommand = [string]$service.PathName
    if ($serviceCommand -notlike "*$pgCtl*" -or $serviceCommand -notlike "*$dataDirectory*") {
        throw "Le service $serviceName existe mais ne correspond pas à l'instance Clarodaro attendue. Aucun changement effectué."
    }
}

if (-not $hasProtectedConfig -and -not $hasLegacyConfig) {
    if (Test-Path -LiteralPath $dataDirectory) {
        $existingItems = @(Get-ChildItem -LiteralPath $dataDirectory -Force -ErrorAction Stop)
        if ($existingItems.Count -gt 0) {
            throw "Le répertoire PostgreSQL contient déjà des données mais aucune configuration Clarodaro n'existe. Initialisation refusée : $dataDirectory"
        }
    }

    if (-not $service -and -not (Test-PortAvailable $PostgreSqlPort)) {
        throw "Le port PostgreSQL $PostgreSqlPort est déjà utilisé. Aucun service tiers ne sera modifié."
    }

    if ($service -and -not (Test-Path -LiteralPath $adminSecretFile -PathType Leaf)) {
        throw 'Un service PostgreSQL Clarodaro existe mais le secret administrateur de son cluster est absent. Initialisation refusée.'
    }
    if (-not (Test-Path -LiteralPath $adminSecretFile -PathType Leaf)) {
        Write-Step 'Première installation : initialisation dun nouveau cluster PostgreSQL dédié.'
        $pgAdminBytes = New-Object byte[] 48
        $appPasswordBytes = New-Object byte[] 48
        $rng = [Security.Cryptography.RandomNumberGenerator]::Create()
        $rng.GetBytes($pgAdminBytes)
        $rng.GetBytes($appPasswordBytes)
        $pgAdminPassword = [Convert]::ToBase64String($pgAdminBytes)
        $appPassword = [Convert]::ToBase64String($appPasswordBytes)
        $rng.Dispose()
        $passwordFile = Join-Path $configRoot 'postgres-init-password.tmp'
        [System.IO.File]::WriteAllText($passwordFile, $pgAdminPassword, [System.Text.UTF8Encoding]::new($false))
        Set-PrivateAcl $passwordFile

        try {
            if (-not (Test-Path -LiteralPath $dataDirectory)) {
                New-Item -ItemType Directory -Path $dataDirectory -Force | Out-Null
            }
            & $initdb -D $dataDirectory -U postgres --encoding=UTF8 --auth-local=trust --auth-host=scram-sha-256 --pwfile=$passwordFile
            if ($LASTEXITCODE -ne 0) { throw "initdb a échoué (code $LASTEXITCODE)." }

            Add-Content -LiteralPath (Join-Path $dataDirectory 'postgresql.conf') -Value @(
                '',
                '# IMC-Clarodaro managed settings',
                "listen_addresses = '127.0.0.1'",
                "port = $PostgreSqlPort",
                "password_encryption = 'scram-sha-256'"
            ) -Encoding ascii

            & icacls.exe $dataDirectory /inheritance:r /grant:r '*S-1-5-18:(OI)(CI)F' '*S-1-5-32-544:(OI)(CI)F' /T /C | Out-Null
            if ($LASTEXITCODE -ne 0) { throw 'Impossible de protéger les permissions du cluster PostgreSQL.' }

            & $pgCtl register -N $serviceName -D $dataDirectory -S auto
            if ($LASTEXITCODE -ne 0) { throw "Enregistrement du service PostgreSQL échoué (code $LASTEXITCODE)." }
            $service = Get-CimInstance Win32_Service -Filter "Name='$serviceName'" -ErrorAction Stop
            if ([string]$service.PathName -notlike "*$pgCtl*" -or [string]$service.PathName -notlike "*$dataDirectory*") {
                throw 'Le service PostgreSQL créé ne correspond pas au runtime et au répertoire attendus.'
            }
            Start-Service -Name $serviceName
            $deadline = (Get-Date).AddSeconds(60)
            do {
                Start-Sleep -Seconds 2
                & $pgIsReady -h 127.0.0.1 -p $PostgreSqlPort
                $ready = ($LASTEXITCODE -eq 0)
            } while (-not $ready -and (Get-Date) -lt $deadline)
            if (-not $ready) { throw 'PostgreSQL ne répond pas après 60 secondes.' }

            $env:PGPASSWORD = $pgAdminPassword
            $databaseSetupFile = Join-Path $configRoot 'create-application-database.sql'
            $databaseSetupSql = "CREATE ROLE imc_clarodaro_app LOGIN PASSWORD '$appPassword';" + [Environment]::NewLine + "CREATE DATABASE imc_clarodoro OWNER imc_clarodaro_app ENCODING 'UTF8';" + [Environment]::NewLine
            [System.IO.File]::WriteAllText($databaseSetupFile, $databaseSetupSql, [System.Text.UTF8Encoding]::new($false))
            Set-PrivateAcl $databaseSetupFile
            try {
                & $psql -h 127.0.0.1 -p $PostgreSqlPort -U postgres -d postgres -v ON_ERROR_STOP=1 -f $databaseSetupFile
                if ($LASTEXITCODE -ne 0) { throw 'Création du rôle ou de la base applicative PostgreSQL échouée.' }
            }
            finally {
                Remove-Item -LiteralPath $databaseSetupFile -Force -ErrorAction SilentlyContinue
            }

            [System.IO.File]::WriteAllText($adminSecretFile, $pgAdminPassword, [System.Text.UTF8Encoding]::new($false))
            Set-PrivateAcl $adminSecretFile
            $envContents = @(
                'DB_HOST=127.0.0.1',
                "DB_PORT=$PostgreSqlPort",
                'DB_NAME=imc_clarodoro',
                'DB_USER=imc_clarodoro_app',
                "DB_PASSWORD=$appPassword"
            ) -join "`r`n"
            [System.IO.File]::WriteAllText($environmentFile, $envContents + "`r`n", [System.Text.UTF8Encoding]::new($false))
            Set-PrivateAcl $environmentFile
        }
        finally {
            Remove-Item -LiteralPath $passwordFile -Force -ErrorAction SilentlyContinue
            Remove-Item Env:\PGPASSWORD -ErrorAction SilentlyContinue
        }

        Write-Step 'Base vierge créée. Vérification et application des migrations officielles sur cette nouvelle base uniquement.'
        [System.IO.File]::WriteAllText($provisioningMarker, 'Initial migration not yet confirmed.', [System.Text.UTF8Encoding]::new($false))
        Set-PrivateAcl $provisioningMarker
        $env:IMC_CLARODARO_ENV_FILE = $environmentFile
        Push-Location $AppRoot
        try {
            & $php 'database\migrate.php' '--status'
            if ($LASTEXITCODE -ne 0) { throw 'La vérification des migrations a échoué. Aucune migration ne sera forcée.' }
            & $php 'database\migrate.php' '--apply'
            if ($LASTEXITCODE -ne 0) { throw 'Les migrations initiales ont échoué. Les données et le cluster sont conservés pour diagnostic.' }
        }
        finally {
            Pop-Location
            Remove-Item Env:\IMC_CLARODARO_ENV_FILE -ErrorAction SilentlyContinue
        }
    }
    else {
        throw "Une installation PostgreSQL semble déjà initialisée mais la configuration applicative est absente. Intervention manuelle requise ; aucune réinitialisation n'est autorisée."
    }
}
elseif ($service) {
    Write-Step 'Instance PostgreSQL Clarodaro existante détectée ; aucune initialisation ni migration ne sera exécutée.'
    if ((Get-Service -Name $serviceName).Status -ne 'Running') {
        Start-Service -Name $serviceName
    }
}
else {
    Write-Step 'Configuration de base existante détectée. PostgreSQL externe ou historique conservé ; aucune instance ni base ne sera créée.'
}

# Do not overwrite a legacy root .env. The PHP launcher selects ProgramData only
# when that protected configuration was created by this installer.
$taskEnvironmentFile = if (Test-Path -LiteralPath $environmentFile -PathType Leaf) { $environmentFile } else { '' }
$task = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
$launcher = Join-Path $AppRoot 'installer\Start-Clarodaro-Server.ps1'
if ($task) {
    $existingAction = ($task.Actions | ForEach-Object { $_.Execute + ' ' + $_.Arguments }) -join ' '
    if ($existingAction -notlike "*$launcher*") {
        throw "La tâche planifiée $taskName existe déjà mais n'appartient pas à Clarodaro. Aucun remplacement effectué."
    }
    Stop-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
    $stopDeadline = (Get-Date).AddSeconds(20)
    while (-not (Test-PortAvailable $HttpPort) -and (Get-Date) -lt $stopDeadline) { Start-Sleep -Seconds 1 }
    if (-not (Test-PortAvailable $HttpPort)) {
        throw "L'ancien serveur Clarodaro n'a pas libéré le port $HttpPort. Aucun nouveau serveur n'a été lancé."
    }
}

if (-not (Test-PortAvailable $HttpPort) -and -not $task) {
    throw "Le port HTTP $HttpPort est déjà utilisé. La tâche PHP n'a pas été créée."
}

$powershell = Join-Path $PSHOME 'powershell.exe'
$arguments = '-NoProfile -NonInteractive -ExecutionPolicy Bypass -File "' + $launcher + '" -AppRoot "' + $AppRoot + '"'
if ($taskEnvironmentFile) { $arguments += ' -EnvironmentFile "' + $taskEnvironmentFile + '"' }
$arguments += " -HttpPort $HttpPort"

$action = New-ScheduledTaskAction -Execute $powershell -Argument $arguments -WorkingDirectory $AppRoot
$trigger = New-ScheduledTaskTrigger -AtStartup
$principal = New-ScheduledTaskPrincipal -UserId 'SYSTEM' -LogonType ServiceAccount -RunLevel Highest
$settings = New-ScheduledTaskSettingsSet -StartWhenAvailable -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -RestartCount 3 -RestartInterval (New-TimeSpan -Minutes 1)
Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Principal $principal -Settings $settings -Force | Out-Null
Start-ScheduledTask -TaskName $taskName
$httpDeadline = (Get-Date).AddSeconds(20)
while ((Test-PortAvailable $HttpPort) -and (Get-Date) -lt $httpDeadline) { Start-Sleep -Seconds 1 }
if (Test-PortAvailable $HttpPort) {
    throw "Le serveur PHP n'a pas démarré sur le port $HttpPort. Consulter le journal PHP dans ProgramData."
}

try {
    if (-not (Get-NetFirewallRule -DisplayName 'IMC-Clarodaro HTTP LAN' -ErrorAction SilentlyContinue)) {
        New-NetFirewallRule -DisplayName 'IMC-Clarodaro HTTP LAN' -Direction Inbound -Action Allow -Protocol TCP -LocalPort $HttpPort -Profile Private | Out-Null
    }
}
catch {
    Write-Warning "Règle pare-feu non créée automatiquement : $($_.Exception.Message)"
}

Write-Step "Serveur PHP planifié au démarrage sur le port $HttpPort."
Write-Step "Données persistantes : $programDataRoot"
Write-Step 'Aucun compte PDG na été créé ou réinitialisé. Effectuer le bootstrap PDG séparément avec le script CLI prévu à cet effet.'
Stop-Transcript | Out-Null
$script:TranscriptStarted = $false
