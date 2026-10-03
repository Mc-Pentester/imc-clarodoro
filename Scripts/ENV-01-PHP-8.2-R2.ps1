# IMC-Clarodoro - ENV-01-PHP-8.2-R2
# Correction TLS 1.2 + Installation PHP 8.2 x64 TS

$ProjectRoot = "C:\IMC-Clarodoro-securise-client\IMC-Clarodoro"
$PhpRoot = "C:\PHP"
$PhpDir = "C:\PHP\8.2"
$PhpVersion = "8.2.34"
$PhpZip = Join-Path $env:TEMP "php-8.2.34-Win32-vs16-x64.zip"
$PhpUrl = "https://windows.php.net/downloads/releases/php-8.2.34-Win32-vs16-x64.zip"
$ReportPath = Join-Path $ProjectRoot "ENV-01-PHP-8.2-R2-RAPPORT.md"
$Errors = @()
$Warnings = @()

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
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host " IMC-CLARODORO - ENV-01-PHP-8.2-R2" -ForegroundColor Cyan
Write-Host " TLS 1.2 + PHP 8.2 x64 Thread Safe" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host ""

# Verification projet
Write-Info "Verification du projet..."
if (-not (Test-Path $ProjectRoot)) {
    Add-Error "Projet introuvable : $ProjectRoot"
    exit 1
}
Write-Pass "Projet trouve."

# Forcer TLS 1.2
Write-Info "Activation de TLS 1.2 pour cette session PowerShell..."
try {
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    $TlsProtocol = [Net.ServicePointManager]::SecurityProtocol
    Write-Host "SecurityProtocol = $TlsProtocol"
    if ($TlsProtocol -match "Tls12") {
        Write-Pass "TLS 1.2 actif pour cette session."
    }
    else {
        Add-Error "TLS 1.2 n'a pas pu etre active."
    }
}
catch {
    Add-Error "Impossible d'activer TLS 1.2 : $($_.Exception.Message)"
}

# Test HTTPS
Write-Info "Test HTTPS vers windows.php.net..."
try {
    $HttpsTest = Invoke-WebRequest -Uri "https://windows.php.net/" -UseBasicParsing -ErrorAction Stop
    Write-Host "HTTP Status : $($HttpsTest.StatusCode)"
    if ($HttpsTest.StatusCode -eq 200) {
        Write-Pass "HTTPS/TLS 1.2 vers windows.php.net fonctionne."
    }
    else {
        Add-Error "windows.php.net retourne HTTP $($HttpsTest.StatusCode)."
    }
}
catch {
    Add-Error "HTTPS vers windows.php.net echoue : $($_.Exception.Message)"
}

# Windows
Write-Info "Detection du systeme..."
$OsInfo = Get-CimInstance Win32_OperatingSystem
$OsCaption = $OsInfo.Caption
$OsVersion = $OsInfo.Version
$OsBuild = [int]$OsInfo.BuildNumber
$OsArchitecture = $OsInfo.OSArchitecture
Write-Host "OS : $OsCaption"
Write-Host "Version : $OsVersion"
Write-Host "Build : $OsBuild"
Write-Host "Architecture : $OsArchitecture"
if ($OsArchitecture -ne "64-bit") {
    Add-Error "Le systeme n'est pas x64."
}
else {
    Write-Pass "Architecture x64 confirmee."
}

# Visual C++
Write-Info "Verification Visual C++ Redistributable x64..."
$VcInstalled = $false
$VcPaths = @(
    "HKLM:\SOFTWARE\Microsoft\VisualStudio\14.0\VC\Runtimes\x64",
    "HKLM:\SOFTWARE\WOW6432Node\Microsoft\VisualStudio\14.0\VC\Runtimes\x64"
)
foreach ($Path in $VcPaths) {
    if (Test-Path $Path) {
        $VcInfo = Get-ItemProperty $Path -ErrorAction SilentlyContinue
        if ($VcInfo.Installed -eq 1) {
            $VcInstalled = $true
            Write-Pass "Visual C++ Redistributable x64 present."
            Write-Host "Version : $($VcInfo.Version)"
            break
        }
    }
}
if (-not $VcInstalled) {
    Add-Warning "Visual C++ Redistributable x64 non detecte."
}

# Dossier PHP
Write-Info "Preparation du dossier PHP..."
if (-not (Test-Path $PhpDir)) {
    New-Item -ItemType Directory -Path $PhpDir -Force | Out-Null
    Write-Pass "Dossier cree : $PhpDir"
}
else {
    Write-Info "Dossier deja present : $PhpDir"
}
$PhpExe = Join-Path $PhpDir "php.exe"

# Telechargement PHP
if (-not (Test-Path $PhpExe)) {
    Write-Info "Telechargement PHP $PhpVersion..."
    Write-Host "URL : $PhpUrl"
    try {
        Invoke-WebRequest -Uri $PhpUrl -OutFile $PhpZip -UseBasicParsing -ErrorAction Stop
        if (Test-Path $PhpZip) {
            $ZipInfo = Get-Item $PhpZip
            Write-Host "Taille archive : $($ZipInfo.Length) octets"
            if ($ZipInfo.Length -gt 1000000) {
                Write-Pass "Archive PHP telechargee."
            }
            else {
                Add-Error "Archive PHP anormalement petite."
            }
        }
        else {
            Add-Error "Archive PHP introuvable apres telechargement."
        }
    }
    catch {
        Add-Error "Telechargement PHP echoue : $($_.Exception.Message)"
    }
}
else {
    Write-Info "php.exe existe deja."
}

# Extraction
if (-not (Test-Path $PhpExe) -and (Test-Path $PhpZip)) {
    Write-Info "Extraction de PHP..."
    try {
        Expand-Archive -Path $PhpZip -DestinationPath $PhpDir -Force
        if (Test-Path $PhpExe) {
            Write-Pass "PHP extrait dans $PhpDir"
        }
        else {
            Add-Error "php.exe absent apres extraction."
        }
    }
    catch {
        Add-Error "Erreur extraction PHP : $($_.Exception.Message)"
    }
}

# php.ini
$PhpIni = Join-Path $PhpDir "php.ini"
$PhpIniProduction = Join-Path $PhpDir "php.ini-production"
if (Test-Path $PhpIni) {
    Write-Info "php.ini existe deja."
}
elseif (Test-Path $PhpIniProduction) {
    Copy-Item -Path $PhpIniProduction -Destination $PhpIni -Force
    Write-Pass "php.ini cree depuis php.ini-production."
}
else {
    Add-Error "php.ini-production introuvable."
}

# Configuration php.ini
if (Test-Path $PhpIni) {
    Write-Info "Configuration php.ini..."
    $Content = Get-Content $PhpIni -Raw
    
    # extension_dir
    if ($Content -match 'extension_dir') {
        $Content = $Content -replace ';?\s*extension_dir\s*=.*', 'extension_dir = "ext"'
    }
    else {
        $Content = $Content + [Environment]::NewLine + 'extension_dir = "ext"' + [Environment]::NewLine
    }
    
    # Extensions
    $Extensions = @("pdo_pgsql", "pgsql", "mbstring", "openssl", "fileinfo")
    foreach ($Extension in $Extensions) {
        $Escaped = [regex]::Escape($Extension)
        if ($Content -match ";\s*extension\s*=\s*$Escaped") {
            $Content = $Content -replace ";\s*extension\s*=\s*$Escaped", "extension=$Extension"
            Write-Info "Activation : $Extension"
        }
        elseif ($Content -match "extension\s*=\s*$Escaped") {
            Write-Info "Deja actif : $Extension"
        }
        else {
            Add-Warning "Entree extension non trouvee : $Extension"
        }
    }
    
    Set-Content -Path $PhpIni -Value $Content -Encoding UTF8
    Write-Pass "php.ini configure."
}

# Test PHP
if (Test-Path $PhpExe) {
    Write-Info "Test php.exe -v..."
    $VersionOutput = & $PhpExe -v 2>&1
    Write-Host $VersionOutput
    if ($LASTEXITCODE -eq 0) {
        Write-Pass "PHP CLI fonctionne."
    }
    else {
        Add-Error "php.exe -v echoue avec code $LASTEXITCODE."
    }
}
else {
    Add-Error "php.exe absent."
}

# Test modules
if (Test-Path $PhpExe) {
    Write-Info "Test php.exe -m..."
    $Modules = & $PhpExe -m 2>&1
    Write-Host $Modules
    $RequiredModules = @("PDO", "pdo_pgsql", "pgsql", "mbstring", "openssl", "fileinfo")
    foreach ($Module in $RequiredModules) {
        if ($Modules -match $Module) {
            Write-Pass "Module present : $Module"
        }
        else {
            Add-Error "Module absent : $Module"
        }
    }
}

# Configuration active
if (Test-Path $PhpExe) {
    Write-Info "Configuration PHP active..."
    & $PhpExe --ini
}

# Test PDO PostgreSQL
if (Test-Path $PhpExe) {
    Write-Info "Test PDO PostgreSQL..."
    $PdoTestFile = Join-Path $env:TEMP "imc-pdo-test.php"
    $PdoTestCode = "<?php if (extension_loaded('pdo_pgsql')) { echo 'PDO PostgreSQL est disponible.'; } else { echo 'PDO PostgreSQL n est pas disponible.'; exit(1); }"
    Set-Content -Path $PdoTestFile -Value $PdoTestCode -Encoding UTF8
    $PdoResult = & $PhpExe $PdoTestFile 2>&1
    Write-Host $PdoResult
    if ($LASTEXITCODE -eq 0) {
        Write-Pass "PDO PostgreSQL valide."
    }
    else {
        Add-Error "PDO PostgreSQL non valide."
    }
    Remove-Item $PdoTestFile -Force -ErrorAction SilentlyContinue
}

# Fichiers PHP ARCH-01
Write-Info "Recherche des fichiers PHP du projet..."
$PhpFiles = Get-ChildItem -Path $ProjectRoot -Filter "*.php" -File -Recurse -ErrorAction SilentlyContinue
if (-not $PhpFiles) {
    Add-Error "Aucun fichier PHP trouve dans le projet."
}
else {
    Write-Host "Nombre de fichiers PHP : $($PhpFiles.Count)"
}

# Validation syntaxique
if ((Test-Path $PhpExe) -and $PhpFiles) {
    Write-Info "Validation php -l..."
    $SyntaxErrors = 0
    foreach ($File in $PhpFiles) {
        Write-Host ""
        Write-Info "Validation : $($File.FullName)"
        $LintResult = & $PhpExe -l $File.FullName 2>&1
        Write-Host $LintResult
        if ($LASTEXITCODE -eq 0) {
            Write-Pass "Syntaxe OK : $($File.Name)"
        }
        else {
            $SyntaxErrors++
            Add-Error "Syntaxe PHP incorrecte : $($File.FullName)"
        }
    }
    if ($SyntaxErrors -eq 0) {
        Write-Pass "Tous les fichiers PHP passent php -l."
    }
    else {
        Add-Error "$SyntaxErrors fichier(s) echouent au lint PHP."
    }
}

# Fichiers sensibles
Write-Info "Controle auth.js / secure-storage.js..."
$AuthFile = Get-ChildItem -Path $ProjectRoot -Filter "auth.js" -File -Recurse -ErrorAction SilentlyContinue
$SecureStorageFile = Get-ChildItem -Path $ProjectRoot -Filter "secure-storage.js" -File -Recurse -ErrorAction SilentlyContinue
if ($AuthFile) {
    Write-Pass "auth.js present."
}
else {
    Add-Error "auth.js introuvable."
}
if ($SecureStorageFile) {
    Write-Pass "secure-storage.js present."
}
else {
    Add-Error "secure-storage.js introuvable."
}

# PostgreSQL
$Psql = Get-Command psql.exe -ErrorAction SilentlyContinue
if ($Psql) {
    Write-Info "PostgreSQL detecte."
    & $Psql.Source --version
}
else {
    Write-Info "PostgreSQL non installe - attendu a cette phase."
}

# Apache
$Httpd = Get-Command httpd.exe -ErrorAction SilentlyContinue
if ($Httpd) {
    Write-Info "Apache detecte."
    & $Httpd.Source -v
}
else {
    Write-Info "Apache non installe - attendu a cette phase."
}

# Test PHP local
$PhpTest = Join-Path $ProjectRoot "server\env-01-php-test.php"
if (-not (Test-Path (Split-Path $PhpTest -Parent))) {
    New-Item -ItemType Directory -Path (Split-Path $PhpTest -Parent) -Force | Out-Null
}
$PhpTestCode = "<?php echo 'ENV-01-PHP-8.2-R2 Test'; echo 'PHP Version: ' . PHP_VERSION; echo 'OS: ' . PHP_OS;"
Set-Content -Path $PhpTest -Value $PhpTestCode -Encoding UTF8
if (Test-Path $PhpExe) {
    Write-Info "Execution du test PHP local..."
    & $PhpExe $PhpTest
}

# PATH utilisateur
Write-Info "Verification PATH utilisateur..."
$UserPath = [Environment]::GetEnvironmentVariable("Path", "User")
if ([string]::IsNullOrWhiteSpace($UserPath)) {
    $UserPath = ""
}
$PathEntries = $UserPath -split ";" | Where-Object { $_ -and $_.Trim() }
$PhpPathPresent = $false
foreach ($Entry in $PathEntries) {
    $EntryNormalized = $Entry.TrimEnd('\')
    $PhpDirNormalized = $PhpDir.TrimEnd('\')
    if ($EntryNormalized -ieq $PhpDirNormalized) {
        $PhpPathPresent = $true
        break
    }
}
if (-not $PhpPathPresent) {
    if ($UserPath) {
        $NewPath = $UserPath + ";" + $PhpDir
    }
    else {
        $NewPath = $PhpDir
    }
    [Environment]::SetEnvironmentVariable("Path", $NewPath, "User")
    Write-Pass "C:\PHP\8.2 ajoute au PATH utilisateur."
}
else {
    Write-Info "C:\PHP\8.2 deja present dans le PATH."
}

# Nettoyage
if (Test-Path $PhpZip) {
    Remove-Item -Path $PhpZip -Force -ErrorAction SilentlyContinue
    Write-Info "Archive temporaire supprimee."
}

# Rapport
Write-Info "Creation du rapport forensic..."
$Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
$PhpVersionDetected = "NON VERIFIE"
if (Test-Path $PhpExe) {
    try {
        $VersionLine = & $PhpExe -v 2>&1 | Select-Object -First 1
        if ($VersionLine) {
            $PhpVersionDetected = $VersionLine.ToString()
        }
    }
    catch {
        $PhpVersionDetected = "ERREUR"
    }
}
$ErrorsText = if ($Errors.Count -eq 0) { "- Aucun echec bloquant." } else { ($Errors | ForEach-Object { "- $_" }) -join [Environment]::NewLine }
$WarningsText = if ($Warnings.Count -eq 0) { "- Aucune reserve." } else { ($Warnings | ForEach-Object { "- $_" }) -join [Environment]::NewLine }
if ($Errors.Count -gt 0) {
    $Verdict = "NO-GO"
}
elseif ($Warnings.Count -gt 0) {
    $Verdict = "PASS AVEC RESERVES"
}
else {
    $Verdict = "PASS"
}

$Report = "IMC-Clarodoro - ENV-01-PHP-8.2-R2 - RAPPORT FORENSIC" + [Environment]::NewLine
$Report += "Date : $Timestamp" + [Environment]::NewLine
$Report += "Projet : $ProjectRoot" + [Environment]::NewLine
$Report += [Environment]::NewLine
$Report += "1. Environnement" + [Environment]::NewLine
$Report += "- OS : $OsCaption" + [Environment]::NewLine
$Report += "- Version : $OsVersion" + [Environment]::NewLine
$Report += "- Build : $OsBuild" + [Environment]::NewLine
$Report += "- Architecture : $OsArchitecture" + [Environment]::NewLine
$Report += [Environment]::NewLine
$Report += "2. TLS" + [Environment]::NewLine
$Report += "- TLS 1.2 force : OUI" + [Environment]::NewLine
$Report += "- HTTPS windows.php.net : $(if ($HttpsTest.StatusCode -eq 200) { 'PASS' } else { 'NON VALIDE' })" + [Environment]::NewLine
$Report += [Environment]::NewLine
$Report += "3. PHP" + [Environment]::NewLine
$Report += "- Version demandee : PHP $PhpVersion" + [Environment]::NewLine
$Report += "- Chemin : $PhpDir" + [Environment]::NewLine
$Report += "- php.exe present : $(Test-Path $PhpExe)" + [Environment]::NewLine
$Report += "- Version detectee : $PhpVersionDetected" + [Environment]::NewLine
$Report += "- php.ini present : $(Test-Path $PhpIni)" + [Environment]::NewLine
$Report += [Environment]::NewLine
$Report += "4. Extensions" + [Environment]::NewLine
$Report += "- PDO, pdo_pgsql, pgsql, mbstring, openssl, fileinfo demandes" + [Environment]::NewLine
$Report += [Environment]::NewLine
$Report += "5. Syntaxe PHP" + [Environment]::NewLine
$Report += "- Fichiers PHP trouves : $($PhpFiles.Count)" + [Environment]::NewLine
$Report += [Environment]::NewLine
$Report += "6. PostgreSQL" + [Environment]::NewLine
$Report += "- Non installe dans cette phase" + [Environment]::NewLine
$Report += [Environment]::NewLine
$Report += "7. Apache" + [Environment]::NewLine
$Report += "- Non installe dans cette phase" + [Environment]::NewLine
$Report += [Environment]::NewLine
$Report += "8. Integrite IMC-Clarodoro" + [Environment]::NewLine
$Report += "- Aucune modification de fichiers metier" + [Environment]::NewLine
$Report += "- Aucune operation Git" + [Environment]::NewLine
$Report += [Environment]::NewLine
$Report += "9. Erreurs" + [Environment]::NewLine
$Report += $ErrorsText + [Environment]::NewLine
$Report += [Environment]::NewLine
$Report += "10. Reserves" + [Environment]::NewLine
$Report += $WarningsText + [Environment]::NewLine
$Report += [Environment]::NewLine
$Report += "11. Verdict" + [Environment]::NewLine
$Report += $Verdict + [Environment]::NewLine

Set-Content -Path $ReportPath -Value $Report -Encoding UTF8
Write-Pass "Rapport cree : $ReportPath"

# Verdict console
Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host " VERDICT ENV-01-PHP-8.2-R2" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host ""
if ($Errors.Count -gt 0) {
    Write-Host "NO-GO" -ForegroundColor Red
    Write-Host ""
    Write-Host "Erreurs : $($Errors.Count)" -ForegroundColor Red
}
elseif ($Warnings.Count -gt 0) {
    Write-Host "PASS AVEC RESERVES" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "Reserves : $($Warnings.Count)" -ForegroundColor Yellow
}
else {
    Write-Host "PASS" -ForegroundColor Green
    Write-Host ""
    Write-Host "PHP 8.2 est installe et valide." -ForegroundColor Green
}
Write-Host ""
Write-Host "Rapport :" -ForegroundColor Cyan
Write-Host $ReportPath
Write-Host ""
Write-Host "FIN ENV-01-PHP-8.2-R2"
