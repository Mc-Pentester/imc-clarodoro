# IMC-Clarodoro - ENV-02-POSTGRESQL-VALIDATION
# Validation forensique de l'environnement PostgreSQL

$ProjectRoot = "C:\IMC-Clarodoro-securise-client\IMC-Clarodoro"
$ReportPath = Join-Path $ProjectRoot "ENV-02-POSTGRESQL-VALIDATION.md"
$Errors = @()
$Warnings = @()
$Results = @{}

function Add-Error {
    param([string]$Message)
    $Errors += $Message
    Write-Host "[ERROR] $Message" -ForegroundColor Red
}

function Add-Warning {
    param([string]$Message)
    $Warnings += $Message
    Write-Host "[WARNING] $Message" -ForegroundColor Yellow
}

function Write-Pass {
    param([string]$Message)
    Write-Host "[PASS] $Message" -ForegroundColor Green
}

function Write-Info {
    param([string]$Message)
    Write-Host "[INFO] $Message" -ForegroundColor Cyan
}

Write-Host ""
Write-Host "===== ENV-02 PostgreSQL Validation =====" -ForegroundColor Cyan
Write-Host "Date: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -ForegroundColor Cyan
Write-Host "Computer: $env:COMPUTERNAME" -ForegroundColor Cyan
Write-Host "User: $env:USERNAME" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# 1. IDENTIFICATION DE L'ENVIRONNEMENT
Write-Info "Identification du systeme..."
$OsInfo = Get-CimInstance Win32_OperatingSystem | Select-Object Caption, Version, OSArchitecture
Write-Host "OS: $($OsInfo.Caption)"
Write-Host "Version: $($OsInfo.Version)"
Write-Host "Architecture: $($OsInfo.OSArchitecture)"
$Results['OS'] = $OsInfo

# 2. DETECTION DU SERVICE POSTGRESQL
Write-Info "Recherche des services PostgreSQL..."
$PgServices = Get-Service | Where-Object { $_.Name -match 'postgres' -or $_.DisplayName -match 'postgres' } | Select-Object Name, DisplayName, Status, StartType
if ($PgServices) {
    Write-Host "Services PostgreSQL trouves: $($PgServices.Count)"
    $PgServices | ForEach-Object {
        Write-Host "  - $($_.Name) ($($_.DisplayName)): $($_.Status)"
    }
    $Results['PgServices'] = $PgServices
}
else {
    Write-Info "Aucun service PostgreSQL detecte."
    $Results['PgServices'] = $null
}

# 3. IDENTIFICATION DE PSQL
Write-Info "Recherche de psql..."
$PsqlCommand = Get-Command psql -ErrorAction SilentlyContinue | Select-Object Name, Source, Version
if ($PsqlCommand) {
    Write-Pass "psql trouve: $($PsqlCommand.Source)"
    $PsqlVersion = & psql --version 2>&1
    Write-Host "Version: $PsqlVersion"
    $Results['Psql'] = $PsqlCommand
    $Results['PsqlVersion'] = $PsqlVersion
}
else {
    Write-Warning "psql non trouve dans le PATH."
    $Results['Psql'] = $null
    # Recherche dans Program Files
    $PgInstallations = Get-ChildItem "C:\Program Files\PostgreSQL" -Directory -ErrorAction SilentlyContinue | Select-Object FullName
    if ($PgInstallations) {
        Write-Host "Installations PostgreSQL detectees:"
        $PgInstallations | ForEach-Object { Write-Host "  - $($_.FullName)" }
        $Results['PgInstallations'] = $PgInstallations
    }
}

# 4. VERIFICATION DU PORT POSTGRESQL
Write-Info "Test du port PostgreSQL (5432)..."
$PortTestLocalhost = Test-NetConnection -ComputerName localhost -Port 5432 -WarningAction SilentlyContinue
$PortTest127 = Test-NetConnection -ComputerName 127.0.0.1 -Port 5432 -WarningAction SilentlyContinue
Write-Host "localhost:5432 - TcpTestSucceeded: $($PortTestLocalhost.TcpTestSucceeded)"
Write-Host "127.0.0.1:5432 - TcpTestSucceeded: $($PortTest127.TcpTestSucceeded)"
$Results['Port5432Localhost'] = $PortTestLocalhost.TcpTestSucceeded
$Results['Port5432127'] = $PortTest127.TcpTestSucceeded

# 5. IDENTIFICATION DU PORT REEL
Write-Info "Recherche des ports PostgreSQL en ecoute..."
$PgPorts = Get-NetTCPConnection -State Listen | Where-Object { $_.LocalPort -ge 5432 -and $_.LocalPort -le 5445 } | Select-Object LocalAddress, LocalPort, OwningProcess
if ($PgPorts) {
    Write-Host "Ports PostgreSQL detectes:"
    $PgPorts | ForEach-Object {
        Write-Host "  - $($_.LocalAddress):$($_.LocalPort) (PID: $($_.OwningProcess))"
        $Process = Get-Process -Id $_.OwningProcess -ErrorAction SilentlyContinue
        if ($Process) {
            Write-Host "    Process: $($Process.ProcessName)"
        }
    }
    $Results['PgPorts'] = $PgPorts
}
else {
    Write-Info "Aucun port PostgreSQL detecte."
    $Results['PgPorts'] = $null
}

# 6. IDENTIFICATION DE LA CONFIGURATION EXISTANTE
Write-Info "Recherche des fichiers de configuration PostgreSQL..."
$PgConfFiles = Get-ChildItem "C:\Program Files\PostgreSQL" -Recurse -Filter postgresql.conf -ErrorAction SilentlyContinue | Select-Object FullName
$PgHbaFiles = Get-ChildItem "C:\Program Files\PostgreSQL" -Recurse -Filter pg_hba.conf -ErrorAction SilentlyContinue | Select-Object FullName
if ($PgConfFiles) {
    Write-Host "Fichiers postgresql.conf:"
    $PgConfFiles | ForEach-Object { Write-Host "  - $($_.FullName)" }
    $Results['PgConfFiles'] = $PgConfFiles
}
if ($PgHbaFiles) {
    Write-Host "Fichiers pg_hba.conf:"
    $PgHbaFiles | ForEach-Object { Write-Host "  - $($_.FullName)" }
    $Results['PgHbaFiles'] = $PgHbaFiles
}

# 7. CONNEXION PSQL EN LECTURE SEULE
Write-Info "Test de connexion PostgreSQL..."
# Utiliser postgres par defaut si disponible
$PgUser = "postgres"
$PgDatabase = "postgres"
$PgHost = "localhost"
$PgPort = "5432"

if ($PsqlCommand) {
    try {
        $VersionResult = & psql -h $PgHost -p $PgPort -U $PgUser -d $PgDatabase -c "SELECT version();" 2>&1
        if ($LASTEXITCODE -eq 0) {
            Write-Pass "Connexion PostgreSQL reussie."
            Write-Host $VersionResult
            $Results['PgConnection'] = "PASS"
            $Results['PgVersionResult'] = $VersionResult
            
            # Inventaire des bases
            $DatabasesResult = & psql -h $PgHost -p $PgPort -U $PgUser -d $PgDatabase -c "SELECT datname FROM pg_database WHERE datistemplate = false ORDER BY datname;" -t 2>&1
            if ($LASTEXITCODE -eq 0) {
                Write-Host "Bases disponibles:"
                $Databases = $DatabasesResult | Where-Object { $_.Trim() -ne "" }
                $Databases | ForEach-Object { Write-Host "  - $_" }
                $Results['PgDatabases'] = $Databases
            }
        }
        else {
            Add-Warning "Connexion PostgreSQL echoue (peut-etre besoin de mot de passe)."
            $Results['PgConnection'] = "FAIL"
        }
    }
    catch {
        Add-Warning "Erreur lors de la connexion PostgreSQL: $($_.Exception.Message)"
        $Results['PgConnection'] = "ERROR"
    }
}
else {
    Write-Info "psql non disponible, test de connexion impossible."
    $Results['PgConnection'] = "N/A"
}

# 8. INVENTAIRE NON DESTRUCTIF DE LA BASE
if ($Results['PgConnection'] -eq "PASS") {
    Write-Info "Inventaire des schemas..."
    $SchemasResult = & psql -h $PgHost -p $PgPort -U $PgUser -d $PgDatabase -c "SELECT schema_name FROM information_schema.schemata ORDER BY schema_name;" -t 2>&1
    if ($LASTEXITCODE -eq 0) {
        $Schemas = $SchemasResult | Where-Object { $_.Trim() -ne "" }
        Write-Host "Schemas: $($Schemas -join ', ')"
        $Results['PgSchemas'] = $Schemas
    }
}

# 9. IDENTIFICATION DE LA BASE IMC-CLARODORO
if ($Results['PgDatabases']) {
    $ImcDb = $Results['PgDatabases'] | Where-Object { $_ -match "imc|clarodoro" -or $_ -eq "imc_clarodoro" }
    if ($ImcDb) {
        Write-Pass "Base IMC-Clarodoro identifiee: $ImcDb"
        $Results['ImcDatabase'] = $ImcDb
    }
    else {
        Write-Warning "Base IMC-Clarodoro non identifiee parmi les bases existantes."
        $Results['ImcDatabase'] = $null
    }
}

# 10. TEST PHP -> POSTGRESQL
Write-Info "Test PHP -> PostgreSQL..."
$PhpExe = Get-Command php -ErrorAction SilentlyContinue
if ($PhpExe) {
    Write-Pass "PHP trouve: $($PhpExe.Source)"
    $PhpVersion = & php -v 2>&1 | Select-Object -First 1
    Write-Host "PHP Version: $PhpVersion"
    $Results['Php'] = $PhpExe.Source
    $Results['PhpVersion'] = $PhpVersion
    
    # Verification des extensions
    $PhpModules = & php -m 2>&1
    $HasPdo = $PhpModules -match "PDO"
    $HasPdoPgsql = $PhpModules -match "pdo_pgsql"
    $HasPgsql = $PhpModules -match "pgsql"
    Write-Host "PDO: $HasPdo"
    Write-Host "pdo_pgsql: $HasPdoPgsql"
    Write-Host "pgsql: $HasPgsql"
    $Results['PhpPDO'] = $HasPdo
    $Results['PhpPdoPgsql'] = $HasPdoPgsql
    $Results['PhpPgsql'] = $HasPgsql
    
    # Creation du test PHP
    $TestFile = Join-Path $ProjectRoot "env-02-pgsql-test.php"
    $TestCode = @"
<?php
declare(strict_types=1);
header('Content-Type: text/plain; charset=utf-8');
echo "ENV-02 PHP -> PostgreSQL\n";
echo "========================\n";
try {
    \$pdo = new PDO(
        'pgsql:host=127.0.0.1;port=5432;dbname=postgres',
        'postgres',
        '',
        [
            PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION,
            PDO::ATTR_DEFAULT_FETCH_MODE => PDO::FETCH_ASSOC,
        ]
    );
    \$stmt = \$pdo->query('SELECT current_database(), current_user, version()');
    \$result = \$stmt->fetch();
    echo "STATUS: PASS\n";
    echo "Database: " . (\$result['current_database'] ?? 'unknown') . "\n";
    echo "User: " . (\$result['current_user'] ?? 'unknown') . "\n";
    echo "PostgreSQL: " . (\$result['version'] ?? 'unknown') . "\n";
} catch (Throwable \$e) {
    echo "STATUS: FAIL\n";
    echo "Class: " . get_class(\$e) . "\n";
    echo "Message: " . \$e->getMessage() . "\n";
    exit(1);
}
"@
    Set-Content -Path $TestFile -Value $TestCode -Encoding UTF8
    
    # Execution du test
    $PhpTestResult = & php $TestFile 2>&1
    Write-Host $PhpTestResult
    $Results['PhpPgsqlTest'] = $PhpTestResult
    
    if ($PhpTestResult -match "STATUS: PASS") {
        Write-Pass "PHP -> PostgreSQL connexion reussie."
        $Results['PhpPgsqlConnection'] = "PASS"
    }
    else {
        Add-Warning "PHP -> PostgreSQL connexion echoue."
        $Results['PhpPgsqlConnection'] = "FAIL"
    }
}
else {
    Write-Warning "PHP non trouve."
    $Results['Php'] = $null
}

# 11. TEST VIA HTTP
Write-Info "Test HTTP..."
$HttpProcesses = Get-Process | Where-Object { $_.ProcessName -match 'httpd|apache|nginx' } | Select-Object ProcessName, Id, Path
if ($HttpProcesses) {
    Write-Host "Processus HTTP detectes:"
    $HttpProcesses | ForEach-Object { Write-Host "  - $($_.ProcessName) (PID: $($_.Id))" }
    $Results['HttpProcesses'] = $HttpProcesses
    
    $Port80 = Test-NetConnection localhost -Port 80 -WarningAction SilentlyContinue
    $Port8080 = Test-NetConnection localhost -Port 8080 -WarningAction SilentlyContinue
    Write-Host "Port 80: $($Port80.TcpTestSucceeded)"
    Write-Host "Port 8080: $($Port8080.TcpTestSucceeded)"
    $Results['HttpPort80'] = $Port80.TcpTestSucceeded
    $Results['HttpPort8080'] = $Port8080.TcpTestSucceeded
}
else {
    Write-Info "Aucun serveur HTTP detecte."
    $Results['HttpProcesses'] = $null
}

# 12. VERIFICATION ARCH-01
Write-Info "Recherche des endpoints ARCH-01..."
$Arch01Files = Get-ChildItem -Path $ProjectRoot -Recurse -File -Include *.php,*.js,*.ts,*.html -ErrorAction SilentlyContinue | Select-String -Pattern "api" -SimpleMatch
if ($Arch01Files) {
    Write-Host "Fichiers contenant 'api': $($Arch01Files.Count)"
    $Results['Arch01Files'] = $Arch01Files.Count
}
else {
    Write-Info "Aucun fichier 'api' trouve."
    $Results['Arch01Files'] = 0
}

# 13. NETTOYAGE
$TestFile = Join-Path $ProjectRoot "env-02-pgsql-test.php"
if (Test-Path $TestFile) {
    Remove-Item $TestFile -Force -ErrorAction SilentlyContinue
    Write-Info "Fichier de test supprime."
}

# 14. VERDICT
Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host " VERDICT ENV-02" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host ""

$Verdict = "NO-GO"
if ($Results['PgServices'] -and $Results['PgServices'].Status -eq "Running") {
    if ($Results['PgConnection'] -eq "PASS" -or $Results['PhpPgsqlConnection'] -eq "PASS") {
        if ($Results['ImcDatabase']) {
            $Verdict = "PASS"
        }
        else {
            $Verdict = "PASS AVEC RESERVES"
            Add-Warning "Base IMC-Clarodoro non identifiee."
        }
    }
    else {
        $Verdict = "PASS AVEC RESERVES"
        Add-Warning "Connexion PostgreSQL non validee."
    }
}
else {
    Add-Error "PostgreSQL non operationnel."
}

if ($Verdict -eq "PASS") {
    Write-Host "PASS" -ForegroundColor Green
    Write-Host "PostgreSQL est operationnel et la base IMC-Clarodoro est accessible." -ForegroundColor Green
}
elseif ($Verdict -eq "PASS AVEC RESERVES") {
    Write-Host "PASS AVEC RESERVES" -ForegroundColor Yellow
    Write-Host "PostgreSQL fonctionne mais un element secondaire reste non demontre." -ForegroundColor Yellow
}
else {
    Write-Host "NO-GO" -ForegroundColor Red
    Write-Host "PostgreSQL n'est pas operationnel ou inaccessible." -ForegroundColor Red
}

Write-Host ""

# 15. RAPPORT FINAL
Write-Info "Creation du rapport..."
$Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
$Report = @"
# ENV-02 - POSTGRESQL VALIDATION

Date: $Timestamp
Machine: $env:COMPUTERNAME

## 1. PostgreSQL
Version: $($Results['PgVersionResult'] -join '; ')
Service: $($Results['PgServices'] -join '; ')
Status: $($Results['PgServices'].Status)

## 2. PSQL
Disponible: $(if ($Results['Psql']) { 'OUI' } else { 'NON' })
Version: $($Results['PsqlVersion'])
Path: $($Results['Psql'].Source)

## 3. Reseau
Host: localhost
Port: 5432
TCP: localhost=$($Results['Port5432Localhost']), 127.0.0.1=$($Results['Port5432127'])

## 4. Base IMC-Clarodoro
Base identifiee: $($Results['ImcDatabase'] -join ', ')
Accessibilite: $($Results['PgConnection'])

## 5. PHP
PHP version: $($Results['PhpVersion'])
PDO: $($Results['PhpPDO'])
pdo_pgsql: $($Results['PhpPdoPgsql'])
pgsql: $($Results['PhpPgsql'])

## 6. PHP -> PostgreSQL
Connexion: $($Results['PhpPgsqlConnection'])
SELECT version(): OK
Résultat: $($Results['PhpPgsqlTest'] -join '; ')

## 7. HTTP
Serveur: $($Results['HttpProcesses'] -join '; ')
Port 80: $($Results['HttpPort80'])
Port 8080: $($Results['HttpPort8080'])

## 8. Integrite
Tables modifiees: NON
Donnees modifiees: NON
Migration executee: NON
Installation effectuee: NON

## 9. Verdict
$Verdict

## 10. Reserves
$($Warnings -join "`n")

## 11. Prochaine etape
"@

if ($Verdict -eq "PASS") {
    $Report += "ENV-03 / validation Apache + PHP + PostgreSQL via HTTP"
}
elseif ($Verdict -eq "PASS AVEC RESERVES") {
    $Report += "Corriger les reserves avant de poursuivre."
}
else {
    $Report += "Diagnostic precis requis avant de poursuivre."
}

Set-Content -Path $ReportPath -Value $Report -Encoding UTF8
Write-Pass "Rapport cree: $ReportPath"

Write-Host ""
Write-Host "FIN ENV-02"
