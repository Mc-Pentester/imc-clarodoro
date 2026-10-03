# ENV-17 — Création DB + exécution contrôlée du schéma
# Projet : IMC-Clarodoro
# Cible : PostgreSQL local 127.0.0.1:5432 / imc_clarodoro
#
# SÉCURITÉ :
# - Ne supprime aucune base.
# - Ne fait aucun DROP/TRUNCATE/DELETE/UPDATE.
# - Ne démarre pas le service Windows PostgreSQL.
# - Crée imc_clarodoro uniquement si elle n'existe pas.
# - Exécute database/schema.sql avec ON_ERROR_STOP uniquement lors d'une création.
# - Avec -VerifyExisting, ne rejoue jamais schema.sql et vérifie uniquement la DB existante.
# - Vérifie ensuite les invariants du schéma.

[CmdletBinding()]
param(
    [string]$ProjectRoot = '',
    [string]$PgBin = 'C:\Program Files\PostgreSQL\18\bin',
    [string]$PgHost = '127.0.0.1',
    [int]$Port = 5432,
    [string]$AdminUser = 'postgres',
    [string]$Database = 'imc_clarodoro',
    [switch]$VerifyExisting
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
$exists = [string]((& $psql @common -d postgres -Atqc "SELECT 1 FROM pg_database WHERE datname = '$Database';") -join "").Trim()
if ($LASTEXITCODE -ne 0) { throw "Impossible de vérifier l'existence de $Database." }

$createdDatabase = $false

if ($exists -eq '1') {
    Write-Host "Base $Database déjà présente." -ForegroundColor DarkYellow
    if (-not $VerifyExisting) {
        throw "La base $Database existe déjà. Par sécurité, aucun DDL n'est exécuté. Relance avec -VerifyExisting pour vérifier la base existante sans rejouer database/schema.sql."
    }
    Write-Host "Mode -VerifyExisting : schema.sql ne sera PAS exécuté." -ForegroundColor Cyan
} else {
    if ($VerifyExisting) {
        throw "Mode -VerifyExisting demandé, mais la base $Database n'existe pas. Crée d'abord la base avec une exécution normale d'ENV-17."
    }
    Write-Host "Création contrôlée de $Database..." -ForegroundColor Green
    & $psql @common -d postgres -v ON_ERROR_STOP=1 -c "CREATE DATABASE $Database WITH OWNER = $AdminUser ENCODING = 'UTF8' TEMPLATE = template0;"
    if ($LASTEXITCODE -ne 0) { throw "Échec CREATE DATABASE." }
    $createdDatabase = $true
}

Write-Host "[3/6] Contrôle du mode d'exécution..." -ForegroundColor Yellow
$tableCountBefore = [int]((& $psql @common -d $Database -Atqc "SELECT count(*) FROM pg_catalog.pg_tables WHERE schemaname = 'public';").Trim())

if ($VerifyExisting) {
    Write-Host "Base existante : $tableCountBefore table(s) publiques détectées. Vérification seule." -ForegroundColor Green
} else {
    if ($tableCountBefore -gt 0) {
        throw "La base $Database contient déjà $tableCountBefore table(s) publiques. Arrêt préventif : aucun DDL n'est exécuté."
    }

    Write-Host "[4/6] Exécution database/schema.sql..." -ForegroundColor Yellow
    & $psql @common -d $Database -v ON_ERROR_STOP=1 -f $schema
    if ($LASTEXITCODE -ne 0) { throw "Échec de l'exécution de database/schema.sql." }
}

Write-Host "[5/6] Vérification des invariants..." -ForegroundColor Yellow
$tableCount = [int]((& $psql @common -d $Database -Atqc "SELECT count(*) FROM pg_catalog.pg_tables WHERE schemaname = 'public';").Trim())
$fkCount = [int]((& $psql @common -d $Database -Atqc "SELECT count(*) FROM pg_constraint con JOIN pg_namespace n ON n.oid=con.connamespace WHERE n.nspname='public' AND con.contype = 'f';").Trim())
$uniqueCount = [int]((& $psql @common -d $Database -Atqc "SELECT count(*) FROM pg_constraint con JOIN pg_namespace n ON n.oid=con.connamespace WHERE n.nspname='public' AND con.contype = 'u';").Trim())
$primaryCount = [int]((& $psql @common -d $Database -Atqc "SELECT count(*) FROM pg_constraint con JOIN pg_namespace n ON n.oid=con.connamespace WHERE n.nspname='public' AND con.contype = 'p';").Trim())
$checkCount = [int]((& $psql @common -d $Database -Atqc "SELECT count(*) FROM pg_constraint con JOIN pg_namespace n ON n.oid=con.connamespace WHERE n.nspname='public' AND con.contype = 'c';").Trim())
# Indexes applicatifs : les 13 CREATE INDEX ordinaires du schéma.
# L'index partiel UNIQUE d'enrollments est vérifié séparément.
$indexCount = [int]((& $psql @common -d $Database -Atqc "SELECT count(*) FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace LEFT JOIN pg_constraint con ON con.conindid=c.oid WHERE n.nspname='public' AND c.relkind='i' AND con.oid IS NULL AND c.relname <> 'enrollments_one_active_per_student_year';").Trim())
$partialUniqueIndexCount = [int]((& $psql @common -d $Database -Atqc "SELECT count(*) FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname='public' AND c.relkind='i' AND c.relname='enrollments_one_active_per_student_year';").Trim())
$cascadeCount = [int]((& $psql @common -d $Database -Atqc "SELECT count(*) FROM pg_constraint con JOIN pg_namespace n ON n.oid=con.connamespace WHERE n.nspname='public' AND con.contype='f' AND con.confdeltype='c';").Trim())
$triggerCount = [int]((& $psql @common -d $Database -Atqc "SELECT count(*) FROM pg_trigger t JOIN pg_class c ON c.oid=t.tgrelid JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname='public' AND NOT t.tgisinternal;").Trim())

$gradeColumns = (& $psql @common -d $Database -Atqc "SELECT string_agg(column_name, ',' ORDER BY ordinal_position) FROM information_schema.columns WHERE table_schema='public' AND table_name='grades';").Trim()
$attendanceColumns = (& $psql @common -d $Database -Atqc "SELECT string_agg(column_name, ',' ORDER BY ordinal_position) FROM information_schema.columns WHERE table_schema='public' AND table_name='attendance';").Trim()
$userColumns = (& $psql @common -d $Database -Atqc "SELECT string_agg(column_name, ',' ORDER BY ordinal_position) FROM information_schema.columns WHERE table_schema='public' AND table_name='users';").Trim()

$checks = @(
    @{ Name='tables'; Actual=$tableCount; Expected=19 },
    @{ Name='foreign keys'; Actual=$fkCount; Expected=17 },
    @{ Name='UNIQUE constraints'; Actual=$uniqueCount; Expected=11 },
    @{ Name='PRIMARY KEY constraints'; Actual=$primaryCount; Expected=19 },
    @{ Name='check constraints'; Actual=$checkCount; Expected=23 },
    @{ Name='indexes hors contraintes'; Actual=$indexCount; Expected=13 },
    @{ Name='partial unique index'; Actual=$partialUniqueIndexCount; Expected=1 },
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

Mode : $(if ($VerifyExisting) { 'VerifyExisting — vérification non destructive de la base existante' } else { 'Création contrôlée + exécution du schéma' })

## Vérifications

| Contrôle | Attendu | Réel |
|---|---:|---:|
| Tables publiques | 19 | $tableCount |
| Foreign Keys | 17 | $fkCount |
| UNIQUE | 11 | $uniqueCount |
| PRIMARY KEY | 19 | $primaryCount |
| CHECK | 23 | $checkCount |
| Indexes hors contraintes | 13 | $indexCount |
| Index UNIQUE partiel enrollment | 1 | $partialUniqueIndexCount |
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

$(if ($VerifyExisting) { 'Aucun — mode VerifyExisting : le schéma existant n’a pas été rejoué.' } else { 'database/schema.sql' })

## Verdict

**ENV-17-PASS**
"@ | Set-Content -LiteralPath $report -Encoding UTF8

Write-Host ""
Write-Host "ENV-17 PASS." -ForegroundColor Green
Write-Host "Rapport : $report" -ForegroundColor Green
