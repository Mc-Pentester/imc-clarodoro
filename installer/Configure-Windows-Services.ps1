param(
    [Parameter(Mandatory = $true)][string]$AppRoot,
    [int]$PostgreSqlPort = 55432,
    [int]$HttpPort = 18080
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

function Test-ClarodaroHttpEndpoint([int]$Port, [string]$ExpectedPhpPath) {
    $listener = Get-NetTCPConnection -State Listen -LocalPort $Port -ErrorAction SilentlyContinue |
        Select-Object -First 1
    if (-not $listener) {
        throw "Aucun processus n'écoute sur le port HTTP $Port."
    }

    $listenerProcess = Get-CimInstance Win32_Process -Filter "ProcessId=$($listener.OwningProcess)" -ErrorAction SilentlyContinue
    if (-not $listenerProcess -or -not $listenerProcess.ExecutablePath) {
        throw "Impossible d'identifier le processus qui écoute sur le port $Port."
    }
    $actualExecutable = [System.IO.Path]::GetFullPath([string]$listenerProcess.ExecutablePath)
    $expectedExecutable = [System.IO.Path]::GetFullPath($ExpectedPhpPath)
    if (-not [string]::Equals($actualExecutable, $expectedExecutable, [StringComparison]::OrdinalIgnoreCase)) {
        throw "Le port HTTP $Port est occupé par un autre programme : $actualExecutable. Clarodaro PHP attendu : $expectedExecutable"
    }

    $request = [System.Net.HttpWebRequest]::Create("http://127.0.0.1:$Port/")
    $request.Method = 'GET'
    $request.AllowAutoRedirect = $false
    $request.Timeout = 8000
    $response = $null
    try {
        $response = $request.GetResponse()
    }
    catch [System.Net.WebException] {
        $response = $_.Exception.Response
        if (-not $response) { throw "Le serveur PHP écoute mais ne répond pas en HTTP : $($_.Exception.Message)" }
    }

    try {
        $statusCode = [int]$response.StatusCode
        $reader = New-Object System.IO.StreamReader($response.GetResponseStream())
        try { $body = $reader.ReadToEnd() } finally { $reader.Dispose() }
    }
    finally {
        if ($response) { $response.Dispose() }
    }

    if ($statusCode -lt 200 -or $statusCode -ge 500) {
        throw "Le serveur PHP répond avec HTTP $statusCode au lieu d'une page Clarodaro exploitable."
    }
    if ($body -notmatch '(?i)Clarodaro|IMC-Clarodaro') {
        throw "Le port $Port répond, mais le contenu ne correspond pas à Clarodaro. Le serveur HTTP inattendu ne sera pas accepté."
    }
    if ($body -notmatch '(?i)Bienvenue sur Clarodaro|Connexion requise|Créer mon compte PDG|Configuration terminée') {
        throw "Le serveur répond avec une page Clarodaro inattendue (HTTP $statusCode)."
    }
    Write-Step "Contrôle HTTP Clarodaro réussi : port $Port, processus PHP identifié, HTTP $statusCode."
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
$postgresServiceAccount = 'NT AUTHORITY\NETWORK SERVICE'
$phpTaskAccount = 'NT AUTHORITY\LOCAL SERVICE'
$postgresRuntimeRoot = Join-Path $programDataRoot 'runtime\postgresql'
$pgBin = Join-Path $postgresRuntimeRoot 'bin'
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
$launcher = Join-Path $AppRoot 'installer\Start-Clarodaro-Server.ps1'
$task = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
if ($task) {
    $existingAction = ($task.Actions | ForEach-Object { $_.Execute + ' ' + $_.Arguments }) -join ' '
    if ($existingAction -notlike "*$launcher*" -or [string]$task.Principal.UserId -notmatch "LOCAL SERVICE|S-1-5-19") {
        throw "La tâche planifiée $taskName existe déjà mais n'appartient pas à Clarodaro. Aucun changement effectué."
    }
}
elseif (-not (Test-PortAvailable $HttpPort)) {
    throw "Le port HTTP $HttpPort est déjà utilisé. Aucun cluster PostgreSQL ne sera initialisé."
}

New-Item -ItemType Directory -Path $configRoot, $dataRoot, $logRoot -Force | Out-Null

# Configurer les ACL sur les repertoires parents AVANT de creer le cluster
# NetworkService (S-1-5-20) a besoin de droits de traversee sur tous les repertoires parents
& icacls.exe $programDataRoot /grant '*S-1-5-19:(X)' '*S-1-5-20:(X)' | Out-Null
if ($LASTEXITCODE -ne 0) { throw 'Impossible de configurer les droits de traversee ProgramData.' }

& icacls.exe $dataRoot /grant '*S-1-5-20:(X)' | Out-Null
if ($LASTEXITCODE -ne 0) { throw 'Impossible de configurer les droits de traversee sur le repertoire PostgreSQL.' }

Set-PrivateAcl $logRoot
$runtimeParent = Join-Path $programDataRoot 'runtime'
foreach ($runtimeDirectory in @($programDataRoot, $runtimeParent, $postgresRuntimeRoot)) {
    if (-not (Test-Path -LiteralPath $runtimeDirectory -PathType Container)) {
        throw "Répertoire runtime PostgreSQL absent : $runtimeDirectory"
    }
    & icacls.exe $runtimeDirectory /grant '*S-1-5-20:(X)' | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "Impossible d'accorder le droit de traversée à NetworkService : $runtimeDirectory" }
}
& icacls.exe $postgresRuntimeRoot /grant '*S-1-5-20:(OI)(CI)RX' /T /C | Out-Null
if ($LASTEXITCODE -ne 0) { throw 'Impossible de donner un accès en lecture/exécution au runtime PostgreSQL pour NetworkService.' }
& icacls.exe $logRoot /grant '*S-1-5-19:(OI)(CI)M' /T /C | Out-Null
if ($LASTEXITCODE -ne 0) { throw 'Impossible de donner accès aux journaux au compte PHP restreint.' }
Start-Transcript -Path (Join-Path $logRoot 'installer-services.log') -Append | Out-Null
$script:TranscriptStarted = $true
& icacls.exe $AppRoot /reset | Out-Null
if ($LASTEXITCODE -ne 0) { throw 'Impossible de retirer les droits d écriture hérités du dossier applicatif.' }
& icacls.exe $AppRoot /grant '*S-1-5-19:(OI)(CI)RX' '*S-1-5-20:(OI)(CI)RX' | Out-Null
if ($LASTEXITCODE -ne 0) { throw 'Impossible de donner un accès en lecture aux comptes de service.' }
foreach ($relativeDirectory in @('backups', 'logs', 'uploads', 'storage', 'tmp', 'cache', 'exports')) {
    $writablePath = Join-Path $AppRoot $relativeDirectory
    New-Item -ItemType Directory -Path $writablePath -Force | Out-Null
    & icacls.exe $writablePath /grant '*S-1-5-19:(OI)(CI)M' /T /C | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "Impossible de donner accès au répertoire applicatif : $relativeDirectory" }
}
Set-PrivateAcl $configRoot
& icacls.exe $configRoot /grant '*S-1-5-19:(X)' | Out-Null
if ($LASTEXITCODE -ne 0) { throw 'Impossible de donner accès au chemin de configuration au compte PHP.' }
if (Test-Path -LiteralPath $provisioningMarker) {
    throw 'Une initialisation précédente est incomplète. Le serveur ne sera pas démarré automatiquement ; consulter le journal et réparer la base manuellement.'
}

$legacyEnvironmentFile = Join-Path $AppRoot '.env'
$hasProtectedConfig = Test-Path -LiteralPath $environmentFile -PathType Leaf
$hasLegacyConfig = Test-Path -LiteralPath $legacyEnvironmentFile -PathType Leaf
$managedLocalDatabase = $false
if ($hasProtectedConfig) {
    $configValues = @{}
    foreach ($line in Get-Content -LiteralPath $environmentFile) {
        $separator = $line.IndexOf('=')
        if ($separator -gt 0) { $configValues[$line.Substring(0, $separator)] = $line.Substring($separator + 1) }
    }
    $managedLocalDatabase = ($configValues['DB_HOST'] -eq '127.0.0.1' -and $configValues['DB_PORT'] -eq [string]$PostgreSqlPort)
}
if ($hasLegacyConfig) {
    Set-PrivateAcl $legacyEnvironmentFile
    & icacls.exe $legacyEnvironmentFile /grant '*S-1-5-19:R' | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'Impossible de donner un accès en lecture à la configuration historique.' }
}
$service = Get-CimInstance Win32_Service -Filter "Name='$serviceName'" -ErrorAction SilentlyContinue

if ($service) {
    $serviceCommand = [string]$service.PathName
    $serviceAccountMatches = [string]$service.StartName -match "NETWORK SERVICE|S-1-5-20"
    $dataPathMatches = $serviceCommand -like "*$dataDirectory*"
    if (-not $serviceAccountMatches -or -not $dataPathMatches) {
        throw "Le service $serviceName existe mais ne correspond pas à l'instance Clarodaro attendue. Aucun changement effectué."
    }

    if ($serviceCommand -notlike "*$pgCtl*") {
        # Migrate only the previous Clarodaro-owned service executable path.
        # The ProgramData cluster and its credentials are never reinitialized.
        $legacyPgCtl = Join-Path $AppRoot 'runtime\postgresql\bin\pg_ctl.exe'
        if ($serviceCommand -notlike "*$legacyPgCtl*") {
            throw "Le service $serviceName utilise un exécutable PostgreSQL tiers ou inattendu. Aucun changement effectué."
        }
        if ((Get-Service -Name $serviceName).Status -ne 'Stopped') {
            Stop-Service -Name $serviceName -Force
            (Get-Service -Name $serviceName).WaitForStatus('Stopped', [TimeSpan]::FromSeconds(60))
        }
        & sc.exe delete $serviceName | Out-Null
        if ($LASTEXITCODE -ne 0) { throw "Impossible de remplacer l'ancien enregistrement du service $serviceName." }
        $deleteDeadline = (Get-Date).AddSeconds(20)
        do {
            Start-Sleep -Milliseconds 500
            $service = Get-CimInstance Win32_Service -Filter "Name='$serviceName'" -ErrorAction SilentlyContinue
        } while ($service -and (Get-Date) -lt $deleteDeadline)
        if ($service) { throw "L'ancien service $serviceName est toujours en cours de suppression." }
        $service = $null
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
            [System.IO.File]::WriteAllText($provisioningMarker, 'Initial schema and migration setup not yet confirmed.', [System.Text.UTF8Encoding]::new($false))
            Set-PrivateAcl $provisioningMarker
            [System.IO.File]::WriteAllText($adminSecretFile, $pgAdminPassword, [System.Text.UTF8Encoding]::new($false))
            Set-PrivateAcl $adminSecretFile
            $envContents = @(
                'DB_HOST=127.0.0.1',
                "DB_PORT=$PostgreSqlPort",
                'DB_NAME=imc_clarodoro',
                'DB_USER=imc_clarodaro_app',
                "DB_PASSWORD=$appPassword"
            ) -join "`r`n"
            [System.IO.File]::WriteAllText($environmentFile, $envContents + "`r`n", [System.Text.UTF8Encoding]::new($false))
            Set-PrivateAcl $environmentFile
            & icacls.exe $environmentFile /grant '*S-1-5-19:R' | Out-Null
            if ($LASTEXITCODE -ne 0) { throw 'Impossible de donner un accès en lecture au fichier .env du service PHP.' }
        $tempDirectory = if ($env:TEMP) { $env:TEMP } else { [System.IO.Path]::GetTempPath() }
            $passwordFile = Join-Path $tempDirectory ('clarodaro-postgres-init-' + [guid]::NewGuid().ToString('N') + '.tmp')
        [System.IO.File]::WriteAllText($passwordFile, $pgAdminPassword, [System.Text.UTF8Encoding]::new($false))

        try {
            # Configurer les ACL sur le repertoire de donnees AVANT initdb
            # initdb heritera des ACL correctes au lieu de creer avec des ACL heritees incorrectes
            & icacls.exe $dataRoot /grant '*S-1-5-20:(X)' | Out-Null
            if ($LASTEXITCODE -ne 0) { throw 'Impossible de donner acces au chemin des donnees PostgreSQL.' }

            if (-not (Test-Path -LiteralPath $dataDirectory)) {
                New-Item -ItemType Directory -Path $dataDirectory -Force | Out-Null
            }

            # initdb s'exécute sous l'identité élevée de l'installateur (souvent
            # runneradmin en CI), tandis que le cluster final appartient à NetworkService.
            # Accorder temporairement l'accès au compte courant, sans élargir les droits
            # des utilisateurs ordinaires, puis retirer cette ACE après initdb.
            $installerSid = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
            $installerAce = "*$installerSid"
            $dataRootInstallerAce = '{0}:(X)' -f $installerAce
            $dataDirectoryInstallerAce = '{0}:(OI)(CI)F' -f $installerAce

            & icacls.exe $dataRoot /grant $dataRootInstallerAce | Out-Null
            if ($LASTEXITCODE -ne 0) { throw 'Impossible de donner temporairement au programme d installation accès au chemin PostgreSQL.' }

            & icacls.exe $dataDirectory /inheritance:r /grant:r '*S-1-5-18:(OI)(CI)F' '*S-1-5-32-544:(OI)(CI)F' '*S-1-5-20:(OI)(CI)F' $dataDirectoryInstallerAce /T /C | Out-Null
            if ($LASTEXITCODE -ne 0) { throw 'Impossible de protéger les permissions du cluster PostgreSQL.' }

            # Keep both the PostgreSQL executable and its working directory on an ASCII-only path.
            # The application install directory may intentionally contain accented characters.
            Push-Location $programDataRoot
            try {
                & $initdb -D $dataDirectory -U postgres --locale=C --encoding=UTF8 --auth-local=trust --auth-host=scram-sha-256 --pwfile=$passwordFile
                if ($LASTEXITCODE -ne 0) { throw "initdb a échoué (code $LASTEXITCODE)." }
            }
            finally {
                Pop-Location
                # Le service ne doit pas dépendre du compte interactif/CI qui a installé l'app.
                & icacls.exe $dataDirectory /remove:g $installerAce /T /C | Out-Null
                if ($LASTEXITCODE -ne 0) { throw 'Impossible de retirer les droits temporaires du compte installateur sur le cluster.' }
                & icacls.exe $dataRoot /remove:g $installerAce | Out-Null
                if ($LASTEXITCODE -ne 0) { throw 'Impossible de retirer les droits temporaires du compte installateur sur le chemin PostgreSQL.' }
            }

            Add-Content -LiteralPath (Join-Path $dataDirectory 'postgresql.conf') -Value @(
                '',
                '# IMC-Clarodaro managed settings',
                "listen_addresses = '127.0.0.1'",
                "port = $PostgreSqlPort",
                "password_encryption = 'scram-sha-256'"
            ) -Encoding ascii

            & $pgCtl register -N $serviceName -D $dataDirectory -S auto -U $postgresServiceAccount
            if ($LASTEXITCODE -ne 0) { throw "Enregistrement du service PostgreSQL échoué (code $LASTEXITCODE)." }
            $service = Get-CimInstance Win32_Service -Filter "Name='$serviceName'" -ErrorAction Stop
            if ([string]$service.PathName -notlike "*$pgCtl*" -or [string]$service.PathName -notlike "*$dataDirectory*" -or [string]$service.StartName -notmatch "NETWORK SERVICE|S-1-5-20") {
                throw 'Le service PostgreSQL créé ne correspond pas au runtime et au répertoire attendus.'
            }

            Write-Step "Tentative de démarrage du service PostgreSQL..."
            $startError = $null
            try {
                Start-Service -Name $serviceName -ErrorAction Stop
                # Le SCM peut laisser le service en StartPending après Start-Service.
                # Attendre Running avant de conclure à un échec sur les machines lentes.
                (Get-Service -Name $serviceName -ErrorAction Stop).WaitForStatus(
                    'Running',
                    [TimeSpan]::FromSeconds(60)
                )
            } catch {
                $startError = $_.Exception.Message
                Write-Step "Erreur démarrage/attente PostgreSQL: $startError"
            }

            $serviceCheck = Get-Service -Name $serviceName -ErrorAction SilentlyContinue
            if ($serviceCheck.Status -ne 'Running') {
                $serviceDetails = Get-CimInstance Win32_Service -Filter "Name='$serviceName'" -ErrorAction SilentlyContinue
                Write-Step "État du service après Start-Service: $($serviceCheck.Status)"
                Write-Step "État du service CIM: $($serviceDetails.State)"
                Write-Step "ExitCode du service: $($serviceDetails.ExitCode)"

                # Récupérer les événements Windows du Service Control Manager
                $eventLog = Get-WinEvent -LogName System -FilterXPath "*[System[(EventID=7045 or EventID=7036) and TimeCreated[timediff(@SystemTime) <= 3600000]]]" -MaxEvents 20 -ErrorAction SilentlyContinue
                if ($eventLog) {
                    Write-Step "=== Événements Service Control Manager récents ==="
                    $eventLog | Where-Object { $_.Message -like "*$serviceName*" } | ForEach-Object {
                        Write-Step "ID: $($_.Id), Time: $($_.TimeCreated), Message: $($_.Message)"
                    }
                }

                # Vérifier les journaux PostgreSQL
                $pgLogDir = Join-Path $dataDirectory 'log'
                if (Test-Path -LiteralPath $pgLogDir -PathType Container) {
                    Write-Step "=== Journaux PostgreSQL ==="
                    Get-ChildItem -LiteralPath $pgLogDir -File -ErrorAction SilentlyContinue | ForEach-Object {
                        Write-Step "Fichier: $($_.FullName)"
                        Get-Content -LiteralPath $_.FullName -Tail 50 -ErrorAction SilentlyContinue | ForEach-Object { Write-Step $_ }
                    }
                }

                # Vérifier les ACL sur le répertoire de données
                Write-Step "=== ACL sur le répertoire de données ==="
                & icacls.exe $dataDirectory | Out-Host

                # Vérifier que pg_ctl.exe existe et est exécutable
                Write-Step "=== Vérification de pg_ctl.exe ==="
                Write-Step "Chemin: $pgCtl"
                Write-Step "Existe: $(Test-Path -LiteralPath $pgCtl -PathType Leaf)"
                if (Test-Path -LiteralPath $pgCtl -PathType Leaf) {
                    & $pgCtl --version
                }

                throw "Le service PostgreSQL n'a pas pu démarrer. Statut: $($serviceCheck.Status), Erreur: $startError"
            }

            $deadline = (Get-Date).AddSeconds(60)
            do {
                Start-Sleep -Seconds 2
                & $pgIsReady -h 127.0.0.1 -p $PostgreSqlPort
                $ready = ($LASTEXITCODE -eq 0)
            } while (-not $ready -and (Get-Date) -lt $deadline)
            if (-not $ready) { throw 'PostgreSQL ne répond pas après 60 secondes.' }

            # Relire le secret administrateur persistant utilisé par initdb : le compte postgres
            # est réservé au bootstrap initial, jamais aux tests de réinstallation/restauration.
            $pgAdminPassword = [System.IO.File]::ReadAllText($adminSecretFile).Trim()
            if ([string]::IsNullOrWhiteSpace($pgAdminPassword)) { throw 'Le secret administrateur PostgreSQL persistant est vide.' }
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

            $schemaFile = Join-Path $AppRoot 'database\schema.sql'
            if (-not (Test-Path -LiteralPath $schemaFile -PathType Leaf)) { throw 'Le schéma de base database/schema.sql est absent.' }
            $env:PGPASSWORD = $appPassword
            & $psql -h 127.0.0.1 -p $PostgreSqlPort -U imc_clarodaro_app -d imc_clarodoro -v ON_ERROR_STOP=1 -f $schemaFile
            if ($LASTEXITCODE -ne 0) { throw 'Création du schéma initial sur la base vierge échouée.' }
            & $psql -h 127.0.0.1 -p $PostgreSqlPort -U imc_clarodaro_app -d imc_clarodoro -v ON_ERROR_STOP=1 -c "CREATE TABLE schema_migrations (filename VARCHAR(255) PRIMARY KEY, checksum CHAR(64) NOT NULL, applied_at TIMESTAMPTZ NOT NULL DEFAULT NOW());"
            if ($LASTEXITCODE -ne 0) { throw 'Création de l historique de migrations initial échouée.' }
            Remove-Item Env:\PGPASSWORD -ErrorAction SilentlyContinue

            
        }
        finally {
            Remove-Item -LiteralPath $passwordFile -Force -ErrorAction SilentlyContinue
            Remove-Item Env:\PGPASSWORD -ErrorAction SilentlyContinue
        }

        Write-Step 'Base vierge créée. Vérification et application des migrations officielles sur cette nouvelle base uniquement.'
        $env:IMC_CLARODARO_ENV_FILE = $environmentFile
        Push-Location $AppRoot
        try {
            & $php 'database\migrate.php' '--status'
            if ($LASTEXITCODE -ne 0) { throw 'La vérification des migrations a échoué. Aucune migration ne sera forcée.' }
            & $php 'database\migrate.php' '--apply'
            if ($LASTEXITCODE -ne 0) { throw 'Les migrations initiales ont échoué. Les données et le cluster sont conservés pour diagnostic.' }
            Remove-Item -LiteralPath $provisioningMarker -Force
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
        Start-Service -Name $serviceName -ErrorAction Stop
        (Get-Service -Name $serviceName -ErrorAction Stop).WaitForStatus(
            'Running',
            [TimeSpan]::FromSeconds(60)
        )
    }
}
elseif ($hasProtectedConfig -and $managedLocalDatabase) {
    if (-not (Test-Path -LiteralPath (Join-Path $dataDirectory 'PG_VERSION') -PathType Leaf)) {
        throw 'Le cluster PostgreSQL local configuré est absent. Aucune réinitialisation automatique ne sera effectuée.'
    }
    if (-not (Test-PortAvailable $PostgreSqlPort)) {
        throw "Le port PostgreSQL $PostgreSqlPort est déjà utilisé."
    }
    Write-Step 'Réenregistrement du service PostgreSQL pour le cluster ProgramData conservé.'
    & icacls.exe $dataRoot /grant '*S-1-5-20:(X)' | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'ACL du chemin PostgreSQL impossible.' }
    # Ajouter les droits du service sans remplacer les ACL existantes du cluster conservé.
    # /grant est volontairement additif : aucune ACE préexistante n'est retirée.
    & icacls.exe $dataDirectory /grant '*S-1-5-20:(OI)(CI)F' /T /C | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'Impossible d accorder les droits au service PostgreSQL sur le cluster conservé.' }
    $postgresConfig = Join-Path $dataDirectory 'postgresql.conf'
    if (-not (Test-Path -LiteralPath $postgresConfig -PathType Leaf)) { throw 'postgresql.conf absent du cluster conservé ; aucune réparation destructive ne sera tentée.' }
    & icacls.exe $postgresConfig /grant '*S-1-5-20:F' | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'Impossible de donner au service PostgreSQL la lecture du fichier postgresql.conf.' }

    # Les ACL de traversee ont deja ete appliquees et controlees par le code retour icacls ci-dessus.
    # Eviter le controle secondaire via les objets ACL PowerShell sur les runners Windows.

    & $pgCtl register -N $serviceName -D $dataDirectory -S auto -U $postgresServiceAccount
    if ($LASTEXITCODE -ne 0) { throw "Réenregistrement PostgreSQL échoué : $LASTEXITCODE" }
    $service = Get-CimInstance Win32_Service -Filter "Name='$serviceName'" -ErrorAction Stop
    if ([string]$service.PathName -notlike "*$pgCtl*" -or [string]$service.PathName -notlike "*$dataDirectory*" -or [string]$service.StartName -notmatch "NETWORK SERVICE|S-1-5-20") {
        throw 'Le service PostgreSQL réenregistré ne correspond pas à cette installation.'
    }

    Write-Step "Tentative de démarrage du service PostgreSQL réenregistré..."
    $startError = $null
    try {
        Start-Service -Name $serviceName -ErrorAction Stop
        # Même attente explicite lors du réenregistrement d'un cluster existant.
        (Get-Service -Name $serviceName -ErrorAction Stop).WaitForStatus(
            'Running',
            [TimeSpan]::FromSeconds(60)
        )
    } catch {
        $startError = $_.Exception.Message
        Write-Step "Erreur démarrage/attente PostgreSQL: $startError"
    }

    $serviceCheck = Get-Service -Name $serviceName -ErrorAction SilentlyContinue
    if ($serviceCheck.Status -ne 'Running') {
        $serviceDetails = Get-CimInstance Win32_Service -Filter "Name='$serviceName'" -ErrorAction SilentlyContinue
        Write-Step "État du service après Start-Service: $($serviceCheck.Status)"
        Write-Step "État du service CIM: $($serviceDetails.State)"
        Write-Step "ExitCode du service: $($serviceDetails.ExitCode)"

        # Récupérer les événements Windows du Service Control Manager
        $eventLog = Get-WinEvent -LogName System -FilterXPath "*[System[(EventID=7045 or EventID=7036) and TimeCreated[timediff(@SystemTime) <= 3600000]]]" -MaxEvents 20 -ErrorAction SilentlyContinue
        if ($eventLog) {
            Write-Step "=== Événements Service Control Manager récents ==="
            $eventLog | Where-Object { $_.Message -like "*$serviceName*" } | ForEach-Object {
                Write-Step "ID: $($_.Id), Time: $($_.TimeCreated), Message: $($_.Message)"
            }
        }

        # PostgreSQL écrit souvent ses erreurs de démarrage dans le journal Application
        # lorsqu'il est exécuté comme service Windows sans logging_collector.
        Write-Step "=== Événements PostgreSQL du journal Application ==="
        $applicationEvents = Get-WinEvent -LogName Application -MaxEvents 100 -ErrorAction SilentlyContinue
        if ($applicationEvents) {
            $applicationEvents |
                Where-Object {
                    $_.ProviderName -match 'PostgreSQL|pg_ctl|postgres' -or
                    $_.Message -like "*$dataDirectory*" -or
                    $_.Message -like "*$serviceName*"
                } |
                Select-Object -First 30 |
                ForEach-Object {
                    Write-Step "Application Event ID=$($_.Id), Provider=$($_.ProviderName), Time=$($_.TimeCreated): $($_.Message)"
                }
        }

        # Vérifier les journaux PostgreSQL
        $pgLogDir = Join-Path $dataDirectory 'log'
        if (Test-Path -LiteralPath $pgLogDir -PathType Container) {
            Write-Step "=== Journaux PostgreSQL ==="
            Get-ChildItem -LiteralPath $pgLogDir -File -ErrorAction SilentlyContinue | ForEach-Object {
                Write-Step "Fichier: $($_.FullName)"
                Get-Content -LiteralPath $_.FullName -Tail 50 -ErrorAction SilentlyContinue | ForEach-Object { Write-Step $_ }
            }
        }

        # Vérifier les ACL de chaque parent, pas seulement celles du cluster.
        Write-Step "=== ACL sur les chemins PostgreSQL ==="
        foreach ($aclPath in @($programDataRoot, $dataRoot, $dataDirectory, $runtimeParent, $postgresRuntimeRoot, $pgBin)) {
            if (Test-Path -LiteralPath $aclPath) {
                Write-Step "--- $aclPath"
                & icacls.exe $aclPath | Out-Host
            }
        }

        throw "Le service PostgreSQL réenregistré n'a pas pu démarrer. Statut: $($serviceCheck.Status), Erreur: $startError"
    }

    $deadline = (Get-Date).AddSeconds(60)
    do {
        Start-Sleep -Seconds 2
        & $pgIsReady -h 127.0.0.1 -p $PostgreSqlPort
        $ready = ($LASTEXITCODE -eq 0)
    } while (-not $ready -and (Get-Date) -lt $deadline)
    if (-not $ready) { throw 'Le cluster PostgreSQL conservé ne répond pas.' }
}
else {
    Write-Step 'Configuration de base existante détectée. PostgreSQL externe ou historique conservé ; aucune instance ni base ne sera créée.'
}

# Apply only migrations that are pending in the configured database. The migration
# runner verifies checksums and refuses to replay a populated database without a
# migration baseline, so existing records are never reset or overwritten.
if ($hasProtectedConfig -or $hasLegacyConfig) {
    Write-Step 'Vérification des migrations de la base existante avant le démarrage de Clarodaro.'
    $env:IMC_CLARODARO_ENV_FILE = if ($hasProtectedConfig) { $environmentFile } else { $legacyEnvironmentFile }
    Push-Location $AppRoot
    try {
        & $php 'database\migrate.php' '--status'
        if ($LASTEXITCODE -ne 0) { throw 'La vérification des migrations de la base existante a échoué.' }
        & $php 'database\migrate.php' '--apply'
        if ($LASTEXITCODE -ne 0) {
            throw 'Application des migrations en attente impossible. Les données existantes sont conservées ; consulter le journal pour établir un baseline ou corriger la migration.'
        }
    }
    finally {
        Pop-Location
        Remove-Item Env:\IMC_CLARODARO_ENV_FILE -ErrorAction SilentlyContinue
    }
}

# Do not overwrite a legacy root .env. The PHP launcher selects ProgramData only
# when that protected configuration was created by this installer.
if ($hasProtectedConfig) {
    Set-PrivateAcl $environmentFile
    & icacls.exe $environmentFile /grant '*S-1-5-19:R' | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'Impossible de donner un accès en lecture au fichier .env du service PHP.' }
}

$taskEnvironmentFile = if (Test-Path -LiteralPath $environmentFile -PathType Leaf) { $environmentFile } else { '' }
if ($task) {
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
$principal = New-ScheduledTaskPrincipal -UserId $phpTaskAccount -LogonType ServiceAccount -RunLevel Limited
$settings = New-ScheduledTaskSettingsSet -StartWhenAvailable -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -RestartCount 3 -RestartInterval (New-TimeSpan -Minutes 1)
Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Principal $principal -Settings $settings -Force | Out-Null
Start-ScheduledTask -TaskName $taskName
$httpDeadline = (Get-Date).AddSeconds(35)
while ((Test-PortAvailable $HttpPort) -and (Get-Date) -lt $httpDeadline) { Start-Sleep -Seconds 1 }
if (Test-PortAvailable $HttpPort) {
    $taskInfo = Get-ScheduledTaskInfo -TaskName $taskName -ErrorAction SilentlyContinue
    $taskState = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
    Write-Step "Échec démarrage PHP : état tâche=$($taskState.State), LastTaskResult=$($taskInfo.LastTaskResult), LastRunTime=$($taskInfo.LastRunTime)"
    if ($taskState) {
        foreach ($taskAction in $taskState.Actions) {
            Write-Step "Action PHP : Execute=$($taskAction.Execute) ; Arguments=$($taskAction.Arguments) ; WorkingDirectory=$($taskAction.WorkingDirectory)"
        }
    }
    $taskEvents = Get-WinEvent -LogName 'Microsoft-Windows-TaskScheduler/Operational' -MaxEvents 100 -ErrorAction SilentlyContinue |
        Where-Object { $_.Message -like "*$taskName*" } | Select-Object -First 25
    foreach ($event in $taskEvents) {
        Write-Step "TaskScheduler ID=$($event.Id) $($event.TimeCreated): $($event.Message)"
    }
    $phpLog = Join-Path $logRoot 'php-server.log'
    if (Test-Path -LiteralPath $phpLog -PathType Leaf) {
        Get-Content -LiteralPath $phpLog -Tail 100 | ForEach-Object { Write-Step "PHP: $_" }
    }
    foreach ($phpOutputLog in @((Join-Path $logRoot 'php-server.stdout.log'), (Join-Path $logRoot 'php-server.stderr.log'))) {
        if (Test-Path -LiteralPath $phpOutputLog -PathType Leaf) {
            Write-Step "=== $phpOutputLog ==="
            Get-Content -LiteralPath $phpOutputLog -Tail 100 | ForEach-Object { Write-Step "PHP process: $_" }
        }
    }
    throw "Le serveur PHP n'a pas démarré sur le port $HttpPort (LastTaskResult=$($taskInfo.LastTaskResult))."
}

# Ne pas confondre un simple port TCP ouvert avec le serveur web Clarodaro.
# EDB ou un autre service peut répondre sur 8080 sans servir l'application.
Test-ClarodaroHttpEndpoint -Port $HttpPort -ExpectedPhpPath $php

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
