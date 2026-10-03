$ErrorActionPreference = "Continue"
$ProjectRoot = "C:\IMC-Clarodoro-securise-client\IMC-Clarodoro"
$PhpExe = "C:\PHP\8.2\php.exe"
$PsqlExe = "C:\Program Files\PostgreSQL\18\bin\psql.exe"
$ReportDir = Join-Path $ProjectRoot "audit"
$ReportFile = Join-Path $ReportDir "ENV-02-R2-REPORT.md"
New-Item -ItemType Directory -Force -Path $ReportDir | Out-Null
$Results = New-Object System.Collections.Generic.List[object]
$SkipConnectionTest = $false

function Add-Result {
    param(
        [string]$ID,
        [string]$Status,
        [string]$Component,
        [string]$Details
    )
    $Results.Add([PSCustomObject]@{
        ID        = $ID
        Status    = $Status
        Component = $Component
        Details   = $Details
    })
    
    switch ($Status) {
        "PASS" {
            Write-Host "[PASS] $ID - $Component - $Details" -ForegroundColor Green
        }
        "WARNING" {
            Write-Host "[WARN] $ID - $Component - $Details" -ForegroundColor Yellow
        }
        "BLOCKED" {
            Write-Host "[BLOCKED] $ID - $Component - $Details" -ForegroundColor Red
        }
        default {
            Write-Host "[$Status] $ID - $Component - $Details"
        }
    }
}

Write-Host ""
Write-Host "============================================================"
Write-Host " ENV-02-R2 - PHP / PostgreSQL / IMC-CLARODORO"
Write-Host "============================================================"
Write-Host ""

# 01 - PROJECT
if (Test-Path $ProjectRoot) {
    Add-Result "ENV-02-R2-01" "PASS" "Projet" "Projet trouve : $ProjectRoot"
}
else {
    Add-Result "ENV-02-R2-01" "BLOCKED" "Projet" "Projet introuvable : $ProjectRoot"
}

# 02 - PHP
if (Test-Path $PhpExe) {
    $PhpVersion = & $PhpExe -v 2>&1 | Select-Object -First 1
    Add-Result "ENV-02-R2-02" "PASS" "PHP" "$PhpVersion"
}
else {
    Add-Result "ENV-02-R2-02" "BLOCKED" "PHP" "Executable introuvable : $PhpExe"
}

# 03 - PHP MODULES
if (Test-Path $PhpExe) {
    $Modules = & $PhpExe -m 2>&1
    $RequiredModules = @("PDO", "pdo_pgsql", "pgsql")
    foreach ($Module in $RequiredModules) {
        if ($Modules -contains $Module) {
            Add-Result "ENV-02-R2-03-$Module" "PASS" "PHP extension" "$Module disponible"
        }
        else {
            Add-Result "ENV-02-R2-03-$Module" "BLOCKED" "PHP extension" "$Module manquant"
        }
    }
}

# 04 - POSTGRESQL EXECUTABLE
if (Test-Path $PsqlExe) {
    $PgVersion = & $PsqlExe --version 2>&1
    Add-Result "ENV-02-R2-04" "PASS" "psql" "$PgVersion"
}
else {
    Add-Result "ENV-02-R2-04" "BLOCKED" "psql" "psql.exe introuvable : $PsqlExe"
}

# 05 - PORT 5432
$Port5432 = Get-NetTCPConnection -LocalPort 5432 -State Listen -ErrorAction SilentlyContinue
if ($Port5432) {
    $Owners = @()
    foreach ($Connection in $Port5432) {
        $PidValue = $Connection.OwningProcess
        try {
            $Process = Get-Process -Id $PidValue -ErrorAction Stop
            $Owners += "$($Process.ProcessName) PID=$PidValue"
        }
        catch {
            $Owners += "PID=$PidValue"
        }
    }
    Add-Result "ENV-02-R2-05" "PASS" "PostgreSQL port" "Port 5432 en ecoute : $($Owners -join ', ')"
}
else {
    Add-Result "ENV-02-R2-05" "BLOCKED" "PostgreSQL port" "Aucun listener detecte sur 5432"
}

# 06 - POSTGRESQL SERVICE
$PgService = Get-Service -Name "postgresql-x64-18" -ErrorAction SilentlyContinue
if ($PgService) {
    if ($PgService.Status -eq "Running") {
        Add-Result "ENV-02-R2-06" "PASS" "Service PostgreSQL" "postgresql-x64-18 est Running"
    }
    else {
        Add-Result "ENV-02-R2-06" "WARNING" "Service PostgreSQL" "Service $($PgService.Status), mais un processus PostgreSQL peut etre actif"
    }
}
else {
    Add-Result "ENV-02-R2-06" "WARNING" "Service PostgreSQL" "Service postgresql-x64-18 non trouve"
}

# 07 - PHP -> POSTGRESQL
Write-Host ""
Write-Host "------------------------------------------------------------"
Write-Host " TEST PHP -> PostgreSQL"
Write-Host "------------------------------------------------------------"
Write-Host ""
$PgUser = "postgres"
$PgPassword = ""
# Essayer de recuperer le mot de passe depuis une variable d'environnement si existante
if ($env:PGPASSWORD) {
    $PgPassword = $env:PGPASSWORD
    Write-Host "Mot de passe depuis variable d'environnement PGPASSWORD"
}
else {
    Write-Host "Mot de passe non fourni - test de connexion saute"
    Add-Result "ENV-02-R2-07" "WARNING" "PHP -> PostgreSQL" "Mot de passe non fourni, test saute"
    $SkipConnectionTest = $true
}

if (-not $SkipConnectionTest) {
    $PhpConnectionScript = @"
<?php
declare(strict_types=1);
\$host = '127.0.0.1';
\$port = '5432';
\$db = 'postgres';
\$user = '$PgUser';
\$pass = '$PgPassword';

try {
    \$pdo = new PDO(
        "pgsql:host=\$host;port=\$port;dbname=\$db",
        \$user,
        \$pass,
        [
            PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION,
            PDO::ATTR_DEFAULT_FETCH_MODE => PDO::FETCH_ASSOC,
        ]
    );
    
    \$stmt = \$pdo->query('SELECT current_database(), current_user, version()');
    \$result = \$stmt->fetch();
    
    echo "STATUS:PASS\n";
    echo "DATABASE:" . (\$result['current_database'] ?? 'unknown') . "\n";
    echo "USER:" . (\$result['current_user'] ?? 'unknown') . "\n";
    echo "VERSION:" . (\$result['version'] ?? 'unknown') . "\n";
    
} catch (Throwable \$e) {
    echo "STATUS:FAIL\n";
    echo "ERROR:" . \$e->getMessage() . "\n";
    exit(1);
}
"@

    $PhpTestFile = Join-Path $env:TEMP "env-02-r2-pgsql-test.php"
    Set-Content -Path $PhpTestFile -Value $PhpConnectionScript -Encoding UTF8

    if (Test-Path $PhpExe) {
        $PhpTestResult = & $PhpExe $PhpTestFile 2>&1
        Write-Host $PhpTestResult
        
        if ($PhpTestResult -match "STATUS:PASS") {
            Add-Result "ENV-02-R2-07" "PASS" "PHP -> PostgreSQL" "Connexion reussie"
        }
        else {
            Add-Result "ENV-02-R2-07" "BLOCKED" "PHP -> PostgreSQL" "Connexion echoue"
        }
    }
    else {
        Add-Result "ENV-02-R2-07" "BLOCKED" "PHP -> PostgreSQL" "PHP non disponible"
    }

    Remove-Item $PhpTestFile -Force -ErrorAction SilentlyContinue
}

# 08 - BASE IMC-CLARODORO
Write-Host ""
Write-Host "------------------------------------------------------------"
Write-Host " INVENTAIRE DES BASES"
Write-Host "------------------------------------------------------------"
Write-Host ""

if (-not $SkipConnectionTest -and $PgPassword) {
    if (Test-Path $PsqlExe) {
        $Env:PGPASSWORD = $PgPassword
        try {
            $DatabasesResult = & $PsqlExe -h 127.0.0.1 -p 5432 -U $PgUser -d postgres -c "SELECT datname FROM pg_database WHERE datistemplate = false ORDER BY datname;" -t 2>&1
            if ($LASTEXITCODE -eq 0) {
                $Databases = $DatabasesResult | Where-Object { $_.Trim() -ne "" }
                Write-Host "Bases disponibles:"
                $Databases | ForEach-Object { Write-Host "  - $_" }
                
                $ImcDb = $Databases | Where-Object { $_ -match "imc|clarodoro" -or $_ -eq "imc_clarodoro" }
                if ($ImcDb) {
                    Add-Result "ENV-02-R2-08" "PASS" "Base IMC-Clarodoro" "Base identifiee: $ImcDb"
                }
                else {
                    Add-Result "ENV-02-R2-08" "WARNING" "Base IMC-Clarodoro" "Base non identifiee (creation requise)"
                }
            }
            else {
                Add-Result "ENV-02-R2-08" "BLOCKED" "Base IMC-Clarodoro" "Impossible de lister les bases"
            }
        }
        catch {
            Add-Result "ENV-02-R2-08" "BLOCKED" "Base IMC-Clarodoro" "Erreur: $($_.Exception.Message)"
        }
        finally {
            Remove-Item Env:PGPASSWORD -ErrorAction SilentlyContinue
        }
    }
    else {
        Add-Result "ENV-02-R2-08" "BLOCKED" "Base IMC-Clarodoro" "psql non disponible"
    }
}
else {
    Add-Result "ENV-02-R2-08" "WARNING" "Base IMC-Clarodoro" "Mot de passe non fourni, inventaire saute"
}

# 09 - VERDICT
Write-Host ""
Write-Host "============================================================"
Write-Host " VERDICT"
Write-Host "============================================================"
Write-Host ""

$BlockedCount = ($Results | Where-Object { $_.Status -eq "BLOCKED" }).Count
$WarningCount = ($Results | Where-Object { $_.Status -eq "WARNING" }).Count

if ($BlockedCount -eq 0) {
    $Verdict = "PASS"
    Write-Host "PASS" -ForegroundColor Green
    Write-Host "Tous les composants sont operationnels." -ForegroundColor Green
}
elseif ($BlockedCount -eq 0 -and $WarningCount -gt 0) {
    $Verdict = "PASS AVEC RESERVES"
    Write-Host "PASS AVEC RESERVES" -ForegroundColor Yellow
    Write-Host "Composants operationnels avec reserves." -ForegroundColor Yellow
}
else {
    $Verdict = "NO-GO"
    Write-Host "NO-GO" -ForegroundColor Red
    Write-Host "Composants bloquants detectes: $BlockedCount" -ForegroundColor Red
}

# 10 - RAPPORT
Write-Host ""
Write-Host "Generation du rapport..."
$Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"

$Report = @"
# ENV-02-R2 - DIAGNOSTIC PHP / POSTGRESQL

Date: $Timestamp
Machine: $env:COMPUTERNAME
User: $env:USERNAME

## RESULTATS

| ID | Status | Component | Details |
|----|--------|-----------|---------|
"@

foreach ($Result in $Results) {
    $Report += "| $($Result.ID) | $($Result.Status) | $($Result.Component) | $($Result.Details) |`n"
}

$Report += @"

## STATISTIQUES

- Total tests: $($Results.Count)
- PASS: $(($Results | Where-Object { $_.Status -eq "PASS" }).Count)
- WARNING: $(($Results | Where-Object { $_.Status -eq "WARNING" }).Count)
- BLOCKED: $BlockedCount

## VERDICT

$Verdict

## INTEGRITE

Aucune modification de:
- Base de donnees
- Tables
- Donnees
- Fichiers applicatifs

## PROCHAINE ETAPE

"@

if ($Verdict -eq "PASS") {
    $Report += "Validation complete. Prêt pour ARCH-01 validation des endpoints."
}
elseif ($Verdict -eq "PASS AVEC RESERVES") {
    $Report += "Corriger les reserves avant de poursuivre."
}
else {
    $Report += "Resoudre les blocages avant de poursuivre."
}

Set-Content -Path $ReportFile -Value $Report -Encoding UTF8
Write-Host "Rapport cree: $ReportFile"

Write-Host ""
Write-Host "FIN ENV-02-R2"
