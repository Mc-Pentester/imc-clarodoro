# ENV-17 — Création DB + exécution contrôlée du schéma
# Projet : IMC-Clarodoro
# Cible : PostgreSQL local 127.0.0.1:5432 / imc_clarodoro
#
# SÉCURITÉ :
# - Ne supprime aucune base.
# - Ne fait aucun DROP/TRUNCATE/DELETE/UPDATE.
# - Ne démarre pas le service Windows PostgreSQL.
# - Crée imc_clarodoro uniquement si elle n'existe pas.
# - Exécute database/schema.sql avec ON_ERROR_STOP.
# - Vérifie ensuite les invariants du schéma.

[CmdletBinding()]
param(
    [string]$ProjectRoot = '',
    [string]$PgBin = 'C:\Program Files\PostgreSQL\18\bin',
    [string]$PgHost = '127.0.0.1',
    [int]$Port = 5432,
    [string]$AdminUser = 'postgres',
    [string]$Database = 'imc_clarodoro'
)

$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($ProjectRoot)) {
    $ProjectRoot = Split-Path -Parent $PSScriptRoot
}


$psql = Join-Path $PgBin 'psql.exe'
$schema = Join-Path $ProjectRoot 'database\schema.sql'
$report = Join-Path $ProjectRoot 'audit\ENV-17-DB-CREATION-SCHEMA-EXECUTION-REPORT.md'

if (-not (Test-Path -LiteralPath $psql)) { throw "psql.exe introuvable : $psql" }
if (-not (Test-Path -LiteralPath $schema)) { throw "Schema introuvable : $schema" }

Write-Host "=== ENV-17 IMC-CLARODORO ===" -ForegroundColor Cyan
Write-Host "PostgreSQL : $PgHost / port $Port"
Write-Host "Base cible : $Database"
Write-Host ""

if (-not $env:PGPASSWORD) {
    $secure = Read-Host "Mot de passe PostgreSQL pour $AdminUser" -AsSecureString
    $ptr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
    try { $env:PGPASSWORD = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($ptr) }
    finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($ptr) }
}

$common = @('-h', $PgHost, '-p', $Port.ToString(), '-U', $AdminUser)

Write-Host "[1/6] Pré-check PostgreSQL..." -ForegroundColor Yellow
& $psql @common -d postgres -v ON_ERROR_STOP=1 -Atqc 'SELECT version();'
if ($LASTEXITCODE -ne 0) { throw "Connexion PostgreSQL impossible." }

Write-Host "[2/6] Vérification de la base cible..." -ForegroundColor Yellow
$exists = (& $psql @common -d postgres -Atqc "SELECT 1 FROM pg_database WHERE datname = '$Database';").Trim()
if ($LASTEXITCODE -ne 0) { throw "Impossible de vérifier l'existence de $Database." }

if ($exists -eq '1') {
    Write-Host "Base $Database déjà présente : aucune création." -ForegroundColor DarkYellow
} else {
    Write-Host "Création contrôlée de $Database..." -ForegroundColor Green
    & $psql @common -d postgres -v ON_ERROR_STOP=1 -c "CREATE DATABASE $Database WITH OWNER = $AdminUser ENCODING = 'UTF8' TEMPLATE = template0;"
    if ($LASTEXITCODE -ne 0) { throw "Échec CREATE DATABASE." }
}

Write-Host "[3/6] Vérification que le schéma n'est pas déjà installé..." -ForegroundColor Yellow
$tableCountBefore = (& $psql @common -d $Database -Atqc "SELECT count(*) FROM pg_catalog.pg_tables WHERE schemaname = 'public';").Trim()
if ([int]$tableCountBefore -gt 0) {
    throw "La base $Database contient déjà $tableCountBefore table(s) publiques. Arrêt préventif : aucun DDL n'est exécuté."
}

Write-Host "[4/6] Exécution database/schema.sql..." -ForegroundColor Yellow
& $psql @common -d $Database -v ON_ERROR_STOP=1 -f $schema
if ($LASTEXITCODE -ne 0) { throw "Échec de l'exécution de database/schema.sql." }

Write-Host "[5/6] Vérification des invariants..." -ForegroundColor Yellow
$tableCount = [int]((& $psql @common -d $Database -Atqc "SELECT count(*) FROM pg_catalog.pg_tables WHERE schemaname = 'public';").Trim())
$fkCount = [int]((& $psql @common -d $Database -Atqc "SELECT count(*) FROM pg_constraint WHERE contype = 'f';").Trim())
$uniqueCount = [int]((& $psql @common -d $Database -Atqc "SELECT count(*) FROM pg_constraint WHERE contype = 'u' OR contype = 'p';").Trim())
$checkCount = [int]((& $psql @common -d $Database -Atqc "SELECT count(*) FROM pg_constraint WHERE contype = 'c';").Trim())
$indexCount = [int]((& $psql @common -d $Database -Atqc "SELECT count(*) FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname='public' AND c.relkind='i' AND c.relname NOT LIKE '%_pkey';").Trim())
$cascadeCount = [int]((& $psql @common -d $Database -Atqc "SELECT count(*) FROM pg_constraint WHERE contype='f' AND confdeltype='c';").Trim())
$triggerCount = [int]((& $psql @common -d $Database -Atqc "SELECT count(*) FROM pg_trigger t JOIN pg_class c ON c.oid=t.tgrelid JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname='public' AND NOT t.tgisinternal;").Trim())

$gradeColumns = (& $psql @common -d $Database -Atqc "SELECT string_agg(column_name, ',' ORDER BY ordinal_position) FROM information_schema.columns WHERE table_schema='public' AND table_name='grades';").Trim()
$attendanceColumns = (& $psql @common -d $Database -Atqc "SELECT string_agg(column_name, ',' ORDER BY ordinal_position) FROM information_schema.columns WHERE table_schema='public' AND table_name='attendance';").Trim()
$userColumns = (& $psql @common -d $Database -Atqc "SELECT string_agg(column_name, ',' ORDER BY ordinal_position) FROM information_schema.columns WHERE table_schema='public' AND table_name='users';").Trim()

$checks = @(
    @{ Name='tables'; Actual=$tableCount; Expected=19 },
    @{ Name='foreign keys'; Actual=$fkCount; Expected=17 },
    @{ Name='unique/primary constraints'; Actual=$uniqueCount; Expected=14 },
    @{ Name='check constraints'; Actual=$checkCount; Expected=23 },
    @{ Name='indexes hors PK'; Actual=$indexCount; Expected=13 },
    @{ Name='CASCADE FK'; Actual=$cascadeCount; Expected=0 },
    @{ Name='triggers applicatifs'; Actual=$triggerCount; Expected=0 }
)

$failed = @($checks | Where-Object { $_.Actual -ne $_.Expected })
if ($failed.Count -gt 0) {
    $failed | Format-Table | Out-String | Write-Host
    throw "Une ou plusieurs vérifications ENV-17 ont échoué."
}

if ($gradeColumns -notmatch 'enrollment_id' -or $gradeColumns -match 'student_id' -or $gradeColumns -match 'coefficient') {
    throw "Structure grades inattendue : $gradeColumns"
}
if ($attendanceColumns -notmatch 'enrollment_id' -or $attendanceColumns -match 'student_id' -or $attendanceColumns -match 'class_id') {
    throw "Structure attendance inattendue : $attendanceColumns"
}

Write-Host "[6/6] Génération du rapport..." -ForegroundColor Yellow
$now = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'

@"
# ENV-17 — DB CREATION + SCHEMA EXECUTION REPORT

Date d'exécution : $now

Projet : $ProjectRoot
PostgreSQL : 18.x
Host : $PgHost
Port : $Port
Base : $Database

## Résultat

ENV-17 : PASS

## Vérifications

| Contrôle | Attendu | Réel |
|---|---:|---:|
| Tables publiques | 19 | $tableCount |
| Foreign Keys | 17 | $fkCount |
| UNIQUE/PK | 14 | $uniqueCount |
| CHECK | 23 | $checkCount |
| Index hors PK | 13 | $indexCount |
| FK CASCADE | 0 | $cascadeCount |
| Triggers applicatifs | 0 | $triggerCount |

## Grades

$gradeColumns

## Attendance

$attendanceColumns

## Users

$userColumns

## Sécurité

- DROP DATABASE : NON
- DROP TABLE : NON
- TRUNCATE : NON
- DELETE : NON
- UPDATE : NON
- Autres bases modifiées : NON
- Le service Windows PostgreSQL n'a pas été démarré par ce script.

## Schéma exécuté

database/schema.sql

## Verdict

**ENV-17-PASS**
"@ | Set-Content -LiteralPath $report -Encoding UTF8

Write-Host ""
Write-Host "ENV-17 PASS." -ForegroundColor Green
Write-Host "Rapport : $report" -ForegroundColor Green
