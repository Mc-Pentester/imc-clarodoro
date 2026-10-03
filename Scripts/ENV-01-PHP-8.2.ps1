# IMC-Clarodoro - ENV-01-PHP-8.2
# Installation controlee PHP 8.2 x64 TS

$ProjectRoot = "C:\IMC-Clarodoro-securise-client\IMC-Clarodoro"
$PhpRoot = "C:\PHP"
$PhpVersion = "8.2.34"
$PhpDir = Join-Path $PhpRoot "8.2"
$PhpZip = Join-Path $env:TEMP "php-8.2.34-Win32-vs16-x64.zip"
$PhpUrl = "https://windows.php.net/downloads/releases/php-8.2.34-Win32-vs16-x64.zip"
$VcRedistUrl = "https://aka.ms/vc14/vc_redist.x64.exe"
$VcRedistInstaller = Join-Path $env:TEMP "vc_redist.x64.exe"
$ReportPath = Join-Path $ProjectRoot "ENV-01-PHP-8.2-RAPPORT.md"
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

Write-Host "============================================================" -ForegroundColor Cyan
Write-Host " IMC-CLARODORO - ENV-01-PHP-8.2" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan

# Verification projet
Write-Info "Verification du projet..."
if (-not (Test-Path $ProjectRoot)) {
    Add-Error "Projet introuvable: $ProjectRoot"
    exit 1
}
Write-Pass "Projet trouve: $ProjectRoot"

# Verification Windows
Write-Info "Lecture version Windows..."
$OsInfo = Get-CimInstance Win32_OperatingSystem
$OsCaption = $OsInfo.Caption
$OsVersion = $OsInfo.Version
$OsBuild = [int]$OsInfo.BuildNumber
$OsArchitecture = $OsInfo.OSArchitecture
Write-Host "OS: $OsCaption"
Write-Host "Version: $OsVersion"
Write-Host "Build: $OsBuild"
Write-Host "Architecture: $OsArchitecture"

if ($OsArchitecture -ne "64-bit") {
    Add-Error "Le systeme n'est pas x64."
    exit 1
}
Write-Pass "Windows x64 detecte."

# Verification PHP existant
Write-Info "Recherche PHP existant..."
$ExistingPhp = Get-Command php.exe -ErrorAction SilentlyContinue
if ($ExistingPhp) {
    Write-Host "PHP existant: $($ExistingPhp.Source)"
}
else {
    Write-Info "Aucun PHP global detecte."
}

# Verification Visual C++
Write-Info "Recherche Visual C++ Redistributable x64..."
$VcInstalled = $false
$VcRegistryPaths = @(
    "HKLM:\SOFTWARE\Microsoft\VisualStudio\14.0\VC\Runtimes\x64",
    "HKLM:\SOFTWARE\WOW6432Node\Microsoft\VisualStudio\14.0\VC\Runtimes\x64"
)
foreach ($RegistryPath in $VcRegistryPaths) {
    if (Test-Path $RegistryPath) {
        $VcInfo = Get-ItemProperty $RegistryPath -ErrorAction SilentlyContinue
        if ($VcInfo.Installed -eq 1) {
            $VcInstalled = $true
            Write-Pass "Visual C++ Redistributable x64 detecte."
            break
        }
    }
}

if (-not $VcInstalled) {
    Add-Warning "Visual C++ Redistributable x64 non detecte."
    Write-Host "PHP 8.2 necessite le runtime Visual C++."
    $InstallVc = Read-Host "Telecharger et installer Visual C++ Redistributable x64? (O/N)"
    if ($InstallVc -match "^[OoYy]$") {
        Write-Info "Telechargement Visual C++..."
        try {
            Invoke-WebRequest -Uri $VcRedistUrl -OutFile $VcRedistInstaller -UseBasicParsing
            if (Test-Path $VcRedistInstaller) {
                Write-Pass "Installateur telecharge."
                Write-Info "Installation en cours..."
                $VcProcess = Start-Process -FilePath $VcRedistInstaller -ArgumentList "/install /quiet /norestart" -Wait -PassThru
                if ($VcProcess.ExitCode -eq 0 -or $VcProcess.ExitCode -eq 1638) {
                    Write-Pass "Visual C++ installe."
                }
                else {
                    Add-Warning "Installation echouee. Code: $($VcProcess.ExitCode)"
                }
            }
        }
        catch {
            Add-Warning "Erreur: $($_.Exception.Message)"
        }
    }
}

# Preparation PHP
Write-Info "Preparation PHP $PhpVersion..."
if (-not (Test-Path $PhpDir)) {
    New-Item -ItemType Directory -Path $PhpDir -Force | Out-Null
    Write-Pass "Dossier cree: $PhpDir"
}

$PhpExe = Join-Path $PhpDir "php.exe"
if (-not (Test-Path $PhpExe)) {
    Write-Info "Telechargement PHP $PhpVersion..."
    try {
        Invoke-WebRequest -Uri $PhpUrl -OutFile $PhpZip -UseBasicParsing
        if (Test-Path $PhpZip) {
            Write-Pass "Archive PHP telechargee."
            Write-Info "Extraction PHP..."
            Expand-Archive -Path $PhpZip -DestinationPath $PhpDir -Force
            if (Test-Path $PhpExe) {
                Write-Pass "PHP extrait."
            }
            else {
                Add-Error "php.exe introuvable apres extraction."
            }
        }
    }
    catch {
        Add-Error "Erreur telechargement: $($_.Exception.Message)"
    }
}
else {
    Write-Info "PHP deja installe dans $PhpDir"
}

# Configuration php.ini
$PhpIni = Join-Path $PhpDir "php.ini"
$PhpIniProduction = Join-Path $PhpDir "php.ini-production"
if (-not (Test-Path $PhpIni) -and (Test-Path $PhpIniProduction)) {
    Copy-Item -Path $PhpIniProduction -Destination $PhpIni -Force
    Write-Pass "php.ini cree depuis php.ini-production."
}

if (Test-Path $PhpIni) {
    Write-Info "Configuration php.ini..."
    $PhpIniContent = Get-Content $PhpIni -Raw
    
    # Extension directory
    if ($PhpIniContent -notmatch 'extension_dir') {
        Add-Content -Path $PhpIni -Value "`r`nextension_dir = `"ext`""
    }
    
    # Recharger
    $PhpIniContent = Get-Content $PhpIni -Raw
    
    # Extensions requises
    $RequiredExtensions = @("pdo", "pdo_pgsql", "pgsql", "mbstring", "openssl", "json", "fileinfo")
    foreach ($Extension in $RequiredExtensions) {
        $Pattern = "^;extension=" + [regex]::Escape($Extension)
        if ($PhpIniContent -match $Pattern) {
            $PhpIniContent = $PhpIniContent -replace $Pattern, "extension=$Extension"
            Write-Info "Activation: $Extension"
        }
    }
    
    Set-Content -Path $PhpIni -Value $PhpIniContent -Encoding UTF8
    Write-Pass "Configuration php.ini terminee."
}

# Test PHP
if (Test-Path $PhpExe) {
    Write-Info "Test PHP..."
    try {
        $PhpVersionOutput = & $PhpExe -v 2>&1
        if ($LASTEXITCODE -eq 0) {
            Write-Pass "PHP fonctionne."
            Write-Host $PhpVersionOutput[0]
        }
        else {
            Add-Warning "PHP retourne code $LASTEXITCODE"
        }
    }
    catch {
        Add-Warning "Erreur execution PHP: $($_.Exception.Message)"
    }
    
    # Test modules
    Write-Info "Extensions PHP..."
    $PhpModules = & $PhpExe -m 2>&1
    $RequiredModules = @("PDO", "pdo_pgsql", "pgsql", "mbstring", "openssl", "fileinfo")
    foreach ($Module in $RequiredModules) {
        if ($PhpModules -match $Module) {
            Write-Pass "Module present: $Module"
        }
        else {
            Add-Warning "Module absent: $Module"
        }
    }
    
    # Test fichiers PHP ARCH-01
    Write-Info "Verification fichiers PHP ARCH-01..."
    $PhpFiles = Get-ChildItem -Path $ProjectRoot -Filter "*.php" -File -Recurse -ErrorAction SilentlyContinue
    if ($PhpFiles) {
        Write-Host "Fichiers PHP trouves: $($PhpFiles.Count)"
        $SyntaxFailures = 0
        foreach ($File in $PhpFiles) {
            $SyntaxOutput = & $PhpExe -l $File.FullName 2>&1
            if ($LASTEXITCODE -eq 0) {
                Write-Pass "Syntaxe OK: $($File.Name)"
            }
            else {
                $SyntaxFailures++
                Add-Error "Erreur syntaxe: $($File.Name)"
            }
        }
        if ($SyntaxFailures -eq 0) {
            Write-Pass "Tous les fichiers PHP passent php -l."
        }
    }
}

# Verification fichiers sensibles
Write-Info "Controle fichiers sensibles..."
$ProtectedFiles = @("auth.js", "secure-storage.js")
foreach ($ProtectedFile in $ProtectedFiles) {
    if (Test-Path (Join-Path $ProjectRoot $ProtectedFile)) {
        Write-Pass "$ProtectedFile present."
    }
    else {
        Add-Error "$ProtectedFile introuvable."
    }
}

# Verification PostgreSQL
Write-Info "Verification PostgreSQL..."
$Psql = Get-Command psql.exe -ErrorAction SilentlyContinue
if ($Psql) {
    Write-Host "psql trouve: $($Psql.Source)"
}
else {
    Write-Info "PostgreSQL non installe."
}

# Verification Apache
Write-Info "Verification Apache..."
$Httpd = Get-Command httpd.exe -ErrorAction SilentlyContinue
if ($Httpd) {
    Write-Host "Apache trouve: $($Httpd.Source)"
}
else {
    Write-Info "Apache non installe."
}

# Nettoyage
if (Test-Path $PhpZip) {
    Remove-Item -Path $PhpZip -Force -ErrorAction SilentlyContinue
}
if (Test-Path $VcRedistInstaller) {
    Remove-Item -Path $VcRedistInstaller -Force -ErrorAction SilentlyContinue
}

# Rapport
Write-Info "Generation rapport..."
$Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
$PhpInstalledVersion = "NON VERIFIE"
if (Test-Path $PhpExe) {
    try {
        $VersionLine = & $PhpExe -v 2>&1 | Select-Object -First 1
        if ($VersionLine) {
            $PhpInstalledVersion = $VersionLine.ToString()
        }
    }
    catch {
        $PhpInstalledVersion = "ERREUR"
    }
}

$Verdict = "PASS"
if ($Errors.Count -gt 0) {
    $Verdict = "NO-GO"
}
elseif ($Warnings.Count -gt 0) {
    $Verdict = "PASS AVEC RESERVES"
}

$Report = @"
IMC-Clarodoro - ENV-01-PHP-8.2 - RAPPORT
Date: $Timestamp
Projet: $ProjectRoot

1. Environnement
- OS: $OsCaption
- Version: $OsVersion
- Build: $OsBuild
- Architecture: $OsArchitecture

2. PHP
- Version demandee: PHP $PhpVersion
- Chemin cible: $PhpDir
- php.exe present: $(Test-Path $PhpExe)
- Version detectee: $PhpInstalledVersion

3. Configuration
- php.ini: $(Test-Path $PhpIni)
- PostgreSQL installe: $(if ($Psql) { "OUI" } else { "NON" })
- Apache installe: $(if ($Httpd) { "OUI" } else { "NON" })

4. Tests
- Installation PHP: $(if (Test-Path $PhpExe) { "OUI" } else { "NON" })
- Execution php.exe: $(if ($PhpInstalledVersion -notlike "NON*") { "OUI" } else { "NON" })
- php -l fichiers: OUI

5. Erreurs
$($Errors -join "`n")

6. Reserves
$($Warnings -join "`n")

7. Verdict
$Verdict

8. Note
Cette phase ne configure pas Apache ni PostgreSQL.
ARCH-02 ne doit commencer qu'apres validation complete.
"@

Set-Content -Path $ReportPath -Value $Report -Encoding UTF8
Write-Pass "Rapport cree: $ReportPath"

# Verdict final
Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host " VERDICT ENV-01-PHP-8.2" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan
if ($Errors.Count -gt 0) {
    Write-Host "NO-GO" -ForegroundColor Red
    Write-Host "Erreurs: $($Errors.Count)"
}
elseif ($Warnings.Count -gt 0) {
    Write-Host "PASS AVEC RESERVES" -ForegroundColor Yellow
    Write-Host "Reserves: $($Warnings.Count)"
}
else {
    Write-Host "PASS" -ForegroundColor Green
    Write-Host "PHP 8.2 installe et valide."
}
Write-Host ""
Write-Host "FIN ENV-01-PHP-8.2"
