#requires -Version 5.1
<#
================================================================================
IMC-CLARODORO
ENV-06 ? SCHEMA FORENSIC AUDIT
================================================================================

OBJECTIF
--------
Identifier de maniere forensic la veritable source du schema PostgreSQL
avant toute creation de la base imc_clarodoro.

IMPORTANT
---------
- Lecture seule uniquement.
- Aucune creation de base.
- Aucune creation/modification de table.
- Aucun CREATE / INSERT / UPDATE / DELETE / DROP.
- Aucun ALTER.
- Aucun lancement/arret de PostgreSQL.
- Aucun changement de fichier applicatif.
- Aucun changement Apache.
- Aucun mot de passe affiche.
- Aucun secret affiche.
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = "Continue"

$ProjectRoot = "C:\IMC-Clarodoro-securise-client\IMC-Clarodoro"
$AuditDir    = Join-Path $ProjectRoot "audit"
$Report       = Join-Path $AuditDir "ENV-06-SCHEMA-FORENSIC-AUDIT-REPORT.md"
$FinalReport  = Join-Path $AuditDir "ENV-06-SCHEMA-FORENSIC-AUDIT-REPORT-FINAL.md"
$PhpExe = "C:\PHP\8.2\php.exe"
$PsqlCandidates = @(
    "C:\Program Files\PostgreSQL\18\bin\psql.exe",
    "C:\Program Files\PostgreSQL\17\bin\psql.exe",
    "C:\Program Files\PostgreSQL\16\bin\psql.exe"
)

New-Item -ItemType Directory -Force -Path $AuditDir | Out-Null
$StartedAt = Get-Date
$Lines = New-Object System.Collections.Generic.List[string]

function Add-Line {
    param([string]$Text = "")
    $Lines.Add($Text)
}

function Add-Section {
    param([string]$Title)
    Add-Line ""
    Add-Line "## $Title"
    Add-Line ""
}

function Mask-Secrets {
    param([string]$Text)
    if ([string]::IsNullOrEmpty($Text)) {
        return $Text
    }
    $Result = $Text
    $Result = $Result -replace '(?i)(DB_PASSWORD\s*=\s*).+', '$1[REDACTED]'
    $Result = $Result -replace '(?i)(PASSWORD\s*=\s*).+', '$1[REDACTED]'
    $Result = $Result -replace '(?i)(password.*?[:=].*)', '$1[REDACTED]'
    $Result = $Result -replace '(?i)(PGPASSWORD\s*=\s*).+', '$1[REDACTED]'
    $Result = $Result -replace '(?i)(DATABASE_URL\s*=\s*).+', '$1[REDACTED]'
    return $Result
}

function Add-FileInfo {
    param([System.IO.FileInfo]$File)
    $dateStr = $File.LastWriteTime.ToString("yyyy-MM-dd HH:mm:ss")
    Add-Line "- $($File.FullName)"
    Add-Line "  - Taille : $($File.Length) octets"
    Add-Line "  - Modification : $dateStr"
}

Add-Line "# ENV-06 ? SCHEMA FORENSIC AUDIT"
Add-Line ""
Add-Line "**Projet :** $ProjectRoot"
$dateStr = $StartedAt.ToString("yyyy-MM-dd HH:mm:ss")
Add-Line "**Date :** $dateStr"
Add-Line "**Mode :** READ-ONLY"
Add-Line ""
Add-Line "> Cette intervention ne modifie ni le code, ni PostgreSQL, ni la structure"
Add-Line "> de la base de donnees."
Add-Line ""

Add-Section "1. Verification du projet"

if (-not (Test-Path $ProjectRoot)) {
    Add-Line "### BLOCKED"
    Add-Line ""
    Add-Line "Le dossier projet n'existe pas :"
    Add-Line ""
    Add-Line "    $ProjectRoot"
}
else {
    Add-Line "### PASS"
    Add-Line ""
    Add-Line "Projet trouve :"
    Add-Line ""
    Add-Line "    $ProjectRoot"
}

Add-Section "2. Inventaire des repertoires lies a la base"

$ImportantDirs = @("database", "migrations", "migration", "sql", "install", "setup", "scripts", "config", "api", "docs")

foreach ($DirName in $ImportantDirs) {
    $Full = Join-Path $ProjectRoot $DirName
    if (Test-Path $Full -PathType Container) {
        Add-Line "- **$DirName/** : PRESENT"
        $Files = @(Get-ChildItem -Path $Full -Recurse -File -ErrorAction SilentlyContinue | Where-Object { $_.FullName -notmatch '\\node_modules\\' -and $_.FullName -notmatch '\\vendor\\' })
        Add-Line "  - fichiers detectes : $($Files.Count)"
    }
    else {
        Add-Line "- **$DirName/** : ABSENT"
    }
}

Add-Section "3. Analyse de database/schema.sql"

$SchemaPath = Join-Path $ProjectRoot "database\schema.sql"

if (-not (Test-Path $SchemaPath)) {
    Add-Line "### ABSENT"
    Add-Line ""
    Add-Line "`database/schema.sql` n'existe pas."
}
else {
    Add-Line "### PRESENT"
    Add-Line ""
    $SchemaFile = Get-Item $SchemaPath
    Add-FileInfo $SchemaFile
    try {
        $SchemaContent = Get-Content -Raw -LiteralPath $SchemaPath -ErrorAction Stop
        $SchemaLength = $SchemaContent.Length
    }
    catch {
        Add-Line ""
        Add-Line "### BLOCKED"
        Add-Line ""
        Add-Line "Impossible de lire `database/schema.sql`."
        $SchemaContent = ""
        $SchemaLength = 0
    }
    Add-Line ""
    Add-Line "- Taille texte : $SchemaLength caracteres"
    $CreateTableCount = ([regex]::Matches($SchemaContent, '(?im)\bCREATE\s+TABLE\b')).Count
    $AlterTableCount = ([regex]::Matches($SchemaContent, '(?im)\bALTER\s+TABLE\b')).Count
    $CreateIndexCount = ([regex]::Matches($SchemaContent, '(?im)\bCREATE\s+INDEX\b')).Count
    $CreateIndexCount = $CreateIndexCount + ([regex]::Matches($SchemaContent, '(?im)\bCREATE\s+UNIQUE\s+INDEX\b')).Count
    $CreateEnumCount = ([regex]::Matches($SchemaContent, '(?im)\bCREATE\s+TYPE\b')).Count
    $InsertCount = ([regex]::Matches($SchemaContent, '(?im)\bINSERT\s+INTO\b')).Count
    Add-Line ""
    Add-Line "### Analyse SQL"
    Add-Line ""
    Add-Line "- `CREATE TABLE` : **$CreateTableCount**"
    Add-Line "- `ALTER TABLE` : **$AlterTableCount**"
    Add-Line "- `CREATE INDEX` : **$CreateIndexCount**"
    Add-Line "- `CREATE TYPE` : **$CreateEnumCount**"
    Add-Line "- `INSERT INTO` : **$InsertCount**"
    if ($CreateTableCount -eq 0) {
        Add-Line ""
        Add-Line "### WARNING"
        Add-Line ""
        Add-Line "Aucune instruction `CREATE TABLE` detectee."
        Add-Line "Le fichier peut etre un placeholder ou ne pas constituer le schema reel."
    }
    else {
        Add-Line ""
        Add-Line "### PASS"
        Add-Line ""
        Add-Line "Le fichier contient des definitions de tables."
    }
    $PlaceholderPatterns = @("placeholder", "future architecture", "future.*postgresql", "TODO", "to be implemented", "a venir", "future schema")
    $PlaceholderDetected = $false
    foreach ($Pattern in $PlaceholderPatterns) {
        if ($SchemaContent -match "(?i)$Pattern") {
            $PlaceholderDetected = $true
            break
        }
    }
    if ($PlaceholderDetected) {
        Add-Line ""
        Add-Line "### WARNING ? PLACEHOLDER POSSIBLE"
        Add-Line ""
        Add-Line "Le contenu contient des marqueurs indiquant potentiellement"
        Add-Line "que ce fichier n'est pas le schema definitif."
    }
}

Add-Section "4. Inventaire de tous les fichiers SQL"

$SqlFiles = @(Get-ChildItem -Path $ProjectRoot -Recurse -File -Filter "*.sql" -ErrorAction SilentlyContinue | Where-Object { $_.FullName -notmatch '\\node_modules\\' -and $_.FullName -notmatch '\\vendor\\' -and $_.FullName -notmatch '\\audit\\' })

if ($SqlFiles.Count -eq 0) {
    Add-Line "### WARNING"
    Add-Line ""
    Add-Line "Aucun fichier `.sql` exploitable detecte."
}
else {
    Add-Line "### $($SqlFiles.Count) fichier(s) SQL detecte(s)"
    Add-Line ""
    foreach ($File in $SqlFiles) {
        Add-FileInfo $File
    }
}

Add-Section "5. Recherche des definitions CREATE TABLE"

$CreateTableMatches = @()
foreach ($File in $SqlFiles) {
    try {
        $Content = Get-Content -Raw -LiteralPath $File.FullName -ErrorAction Stop
        if ($Content -match '(?im)\bCREATE\s+TABLE\b') {
            $CreateTableMatches += $File
        }
    }
    catch {
        Add-Line ""
        Add-Line "### BLOCKED"
        Add-Line ""
        Add-Line "Impossible de lire : $($File.FullName)"
    }
}

if ($CreateTableMatches.Count -eq 0) {
    Add-Line "### WARNING"
    Add-Line ""
    Add-Line "Aucun fichier SQL contenant `CREATE TABLE` n'a ete trouve."
}
else {
    Add-Line "### PASS"
    Add-Line ""
    Add-Line "Fichiers contenant `CREATE TABLE` :"
    Add-Line ""
    foreach ($File in $CreateTableMatches) {
        Add-Line "- $($File.FullName)"
    }
}

Add-Section "6. Recherche de migrations"

$MigrationCandidates = @(Get-ChildItem -Path $ProjectRoot -Recurse -File -ErrorAction SilentlyContinue | Where-Object { $_.FullName -notmatch '\\node_modules\\' -and $_.FullName -notmatch '\\vendor\\' -and $_.FullName -notmatch '\\audit\\' -and ($_.DirectoryName -match '(?i)\\migrations?$' -or $_.Name -match '(?i)migration' -or $_.Name -match '(?i)database.*(init|install|setup)' -or $_.Name -match '(?i)(init|install|setup).*database') })
$MigrationCandidates = @($MigrationCandidates | Sort-Object FullName -Unique)

if ($MigrationCandidates.Count -eq 0) {
    Add-Line "### WARNING"
    Add-Line ""
    Add-Line "Aucun fichier ressemblant a une migration n'a ete trouve."
}
else {
    Add-Line "### Fichiers candidats"
    Add-Line ""
    foreach ($File in $MigrationCandidates) {
        Add-FileInfo $File
    }
}

Add-Section "7. Recherche de DDL PostgreSQL dans les fichiers PHP"

$PhpFiles = @(Get-ChildItem -Path $ProjectRoot -Recurse -File -Filter "*.php" -ErrorAction SilentlyContinue | Where-Object { $_.FullName -notmatch '\\vendor\\' -and $_.FullName -notmatch '\\node_modules\\' -and $_.FullName -notmatch '\\audit\\' })
Add-Line "Fichiers PHP inspectables : **$($PhpFiles.Count)**"

$DdlMatches = New-Object System.Collections.Generic.List[string]
$DdlPatterns = @('\bCREATE\s+TABLE\b', '\bALTER\s+TABLE\b', '\bDROP\s+TABLE\b', '\bCREATE\s+DATABASE\b', '\bCREATE\s+SCHEMA\b', '\bCREATE\s+INDEX\b', '\bCREATE\s+TYPE\b', '\bTRUNCATE\b')

foreach ($File in $PhpFiles) {
    try {
        $Content = Get-Content -Raw -LiteralPath $File.FullName -ErrorAction Stop
        foreach ($Pattern in $DdlPatterns) {
            if ($Content -match "(?im)$Pattern") {
                $DdlMatches.Add("$($File.FullName) -> $Pattern")
                break
            }
        }
    }
    catch {
        Add-Line ""
        Add-Line "### BLOCKED"
        Add-Line ""
        Add-Line "Impossible de lire : $($File.FullName)"
    }
}

if ($DdlMatches.Count -eq 0) {
    Add-Line ""
    Add-Line "### INFO"
    Add-Line ""
    Add-Line "Aucun DDL PostgreSQL evident detecte dans les fichiers PHP."
}
else {
    Add-Line ""
    Add-Line "### ATTENTION"
    Add-Line ""
    Add-Line "Des instructions ressemblant a du DDL ont ete detectees :"
    Add-Line ""
    foreach ($Match in $DdlMatches) {
        Add-Line "- $Match"
    }
}

Add-Section "8. Recherche de references a imc_clarodoro"

$DatabaseReferences = New-Object System.Collections.Generic.List[string]
$SearchExtensions = @("*.php", "*.sql", "*.md", "*.txt", "*.env", "*.example", "*.ini", "*.conf", "*.json", "*.yml", "*.yaml")

foreach ($Extension in $SearchExtensions) {
    $Files = @(Get-ChildItem -Path $ProjectRoot -Recurse -File -Filter $Extension -ErrorAction SilentlyContinue | Where-Object { $_.FullName -notmatch '\\vendor\\' -and $_.FullName -notmatch '\\node_modules\\' -and $_.FullName -notmatch '\\audit\\' })
    foreach ($File in $Files) {
        try {
            $Content = Get-Content -Raw -LiteralPath $File.FullName -ErrorAction Stop
            if ($Content -match '(?i)imc[_-]clarodoro') {
                $DatabaseReferences.Add($File.FullName)
            }
        }
        catch {
            Add-Line ""
            Add-Line "### BLOCKED"
            Add-Line ""
            Add-Line "Impossible de lire : $($File.FullName)"
        }
    }
}

$DatabaseReferences = @($DatabaseReferences | Sort-Object -Unique)

if ($DatabaseReferences.Count -eq 0) {
    Add-Line "### WARNING"
    Add-Line ""
    Add-Line "Aucune reference explicite a `imc_clarodoro` trouvee."
}
else {
    Add-Line "### PASS"
    Add-Line ""
    Add-Line "References detectees dans :"
    Add-Line ""
    foreach ($Ref in $DatabaseReferences) {
        Add-Line "- $Ref"
    }
}

Add-Section "9. Analyse de config/database.php"

$DatabaseConfig = Join-Path $ProjectRoot "config\database.php"

if (-not (Test-Path $DatabaseConfig)) {
    Add-Line "### WARNING"
    Add-Line ""
    Add-Line "`config/database.php` absent."
}
else {
    Add-Line "### PRESENT"
    Add-Line ""
    Add-FileInfo (Get-Item $DatabaseConfig)
    try {
        $ConfigContent = Get-Content -Raw -LiteralPath $DatabaseConfig -ErrorAction Stop
    }
    catch {
        Add-Line ""
        Add-Line "### BLOCKED"
        Add-Line ""
        Add-Line "Impossible de lire `config/database.php`."
        $ConfigContent = ""
    }
    $ExpectedVars = @("DB_HOST", "DB_PORT", "DB_NAME", "DB_USER", "DB_PASSWORD")
    foreach ($Var in $ExpectedVars) {
        if ($ConfigContent -match [regex]::Escape($Var)) {
            Add-Line "- $Var : reference detectee"
        }
        else {
            Add-Line "- $Var : non detectee"
        }
    }
    if ($ConfigContent -match '(?i)pgsql:') {
        Add-Line ""
        Add-Line "PDO PostgreSQL : **detecte**"
    }
    else {
        Add-Line ""
        Add-Line "PDO PostgreSQL : **non detecte explicitement**"
    }
}

Add-Section "10. Configuration environnement"

$EnvPath = Join-Path $ProjectRoot ".env"
$EnvExamplePath = Join-Path $ProjectRoot ".env.example"

if (Test-Path $EnvPath) {
    Add-Line "- `.env` : PRESENT"
    try {
        $EnvContent = Get-Content -Raw -LiteralPath $EnvPath -ErrorAction Stop
        $EnvLines = $EnvContent -split "`r?`n"
        foreach ($Line in $EnvLines) {
            if ($Line -match '^\s*(DB_HOST|DB_PORT|DB_NAME|DB_USER|DB_PASSWORD)\s*=') {
                $Name = ($Line -split '=',2)[0].Trim()
                if ($Name -eq "DB_PASSWORD") {
                    Add-Line "  - DB_PASSWORD : PRESENT [VALEUR MASQUEE]"
                }
                else {
                    Add-Line "  - $Name : PRESENT"
                }
            }
        }
    }
    catch {
        Add-Line ""
        Add-Line "### BLOCKED"
        Add-Line ""
        Add-Line "Impossible de lire `.env`."
    }
}
else {
    Add-Line "- `.env` : ABSENT"
}

if (Test-Path $EnvExamplePath) {
    Add-Line "- `.env.example` : PRESENT"
}
else {
    Add-Line "- `.env.example` : ABSENT"
}

Add-Section "11. Documentation d'installation PostgreSQL"

$DocCandidates = @(Get-ChildItem -Path $ProjectRoot -Recurse -File -ErrorAction SilentlyContinue | Where-Object { $_.FullName -notmatch '\\vendor\\' -and $_.FullName -notmatch '\\node_modules\\' -and $_.FullName -notmatch '\\audit\\' -and ($_.Name -match '(?i)^README' -or $_.Name -match '(?i)install' -or $_.Name -match '(?i)setup' -or $_.Name -match '(?i)database' -or $_.Name -match '(?i)postgres') })
$DocCandidates = @($DocCandidates | Sort-Object FullName -Unique)

if ($DocCandidates.Count -eq 0) {
    Add-Line "### INFO"
    Add-Line ""
    Add-Line "Aucun document evident d'installation DB trouve."
}
else {
    Add-Line "Documents candidats :"
    Add-Line ""
    foreach ($File in $DocCandidates) {
        Add-Line "- $($File.FullName)"
    }
}

Add-Section "12. Recherche de noms de tables PostgreSQL dans le code"

# Pattern corrig? par cc14dc6 : utiliser \w+ au lieu de [a-zA-Z_][a-zA-Z0-9_]*
$TablePatterns = @('FROM\s+(\w+)', 'JOIN\s+(\w+)', 'INSERT\s+INTO\s+(\w+)', 'UPDATE\s+(\w+)', 'DELETE\s+FROM\s+(\w+)')
$DetectedTables = New-Object System.Collections.Generic.HashSet[string]

foreach ($File in $PhpFiles) {
    try {
        $Content = Get-Content -Raw -LiteralPath $File.FullName -ErrorAction Stop
        foreach ($Pattern in $TablePatterns) {
            $Matches = [regex]::Matches($Content, "(?im)$Pattern")
            foreach ($Match in $Matches) {
                if ($Match.Groups.Count -gt 1) {
                    $Candidate = $Match.Groups[1].Value
                    if ($Candidate -notmatch '^(SELECT|WHERE|SET|VALUES|RETURNING)$') {
                        [void]$DetectedTables.Add($Candidate)
                    }
                }
            }
        }
    }
    catch {
        Add-Line ""
        Add-Line "### BLOCKED"
        Add-Line ""
        Add-Line "Impossible de lire : $($File.FullName)"
    }
}

if ($DetectedTables.Count -eq 0) {
    Add-Line "Aucun nom de table SQL identifiable automatiquement."
}
else {
    Add-Line "Tables/noms SQL candidats detectes :"
    Add-Line ""
    foreach ($Table in ($DetectedTables | Sort-Object)) {
        Add-Line "- $Table"
    }
}

Add-Section "13. Verification PostgreSQL"

$Psql = $null
foreach ($Candidate in $PsqlCandidates) {
    if (Test-Path $Candidate) {
        $Psql = $Candidate
        break
    }
}

if ($null -eq $Psql) {
    $Command = Get-Command psql.exe -ErrorAction SilentlyContinue
    if ($null -ne $Command) {
        $Psql = $Command.Source
    }
}

if ($null -eq $Psql) {
    Add-Line "### WARNING"
    Add-Line ""
    Add-Line "`psql.exe` non trouve."
}
else {
    Add-Line "### PASS"
    Add-Line ""
    Add-Line "`psql.exe` : $Psql"
    $VersionOutput = & $Psql --version 2>&1
    Add-Line ""
    Add-Line "Version :"
    Add-Line ""
    Add-Line '```text'
    Add-Line (Mask-Secrets ($VersionOutput -join "`n"))
    Add-Line '```'
}

Add-Section "14. PostgreSQL ? port TCP 5432"

$Tcp = Test-NetConnection -ComputerName "127.0.0.1" -Port 5432 -WarningAction SilentlyContinue -ErrorAction SilentlyContinue
if ($Tcp -and $Tcp.TcpTestSucceeded) {
    Add-Line "### PASS"
    Add-Line ""
    Add-Line "TCP 127.0.0.1:5432 accessible."
}
else {
    Add-Line "### WARNING"
    Add-Line ""
    Add-Line "TCP 127.0.0.1:5432 inaccessible."
}

Add-Section "15. Processus PostgreSQL"

$PostgresProcesses = Get-Process postgres -ErrorAction SilentlyContinue
if ($PostgresProcesses) {
    Add-Line "### PASS"
    Add-Line ""
    Add-Line "Processus PostgreSQL detectes : **$($PostgresProcesses.Count)**"
    Add-Line ""
    foreach ($Process in $PostgresProcesses) {
        Add-Line "- PID $($Process.Id)"
    }
}
else {
    Add-Line "### WARNING"
    Add-Line ""
    Add-Line "Aucun processus `postgres` detecte."
}

Add-Section "16. Verification READ-ONLY de la base imc_clarodoro"

if ($null -eq $Psql) {
    Add-Line "### NOT EXECUTED"
    Add-Line ""
    Add-Line "Impossible d'interroger PostgreSQL sans `psql.exe`."
}
else {
    $env:PGHOST = "127.0.0.1"
    $env:PGPORT = "5432"
    $env:PGUSER = "postgres"
    $DbCheck = & $Psql -h 127.0.0.1 -p 5432 -U postgres -d postgres -tAc "SELECT datname FROM pg_database WHERE datname = 'imc_clarodoro';" 2>&1
    $DbCheckText = ($DbCheck -join "`n").Trim()
    if ($DbCheckText -eq "imc_clarodoro") {
        Add-Line "### PRESENT"
        Add-Line ""
        Add-Line "La base `imc_clarodoro` existe."
    }
    elseif ($DbCheckText -match '(?i)password' -or $DbCheckText -match '(?i)authentication' -or $DbCheckText -match '(?i)no password') {
        Add-Line "### NOT VERIFIED"
        Add-Line ""
        Add-Line "PostgreSQL demande une authentification non disponible"
        Add-Line "dans ce script read-only."
    }
    elseif ([string]::IsNullOrWhiteSpace($DbCheckText)) {
        Add-Line "### ABSENT"
        Add-Line ""
        Add-Line "Aucune ligne retournee : `imc_clarodoro` n'existe pas."
    }
    else {
        Add-Line "### WARNING"
        Add-Line ""
        Add-Line "Reponse PostgreSQL non standard :"
        Add-Line ""
        Add-Line '```text'
        Add-Line (Mask-Secrets $DbCheckText)
        Add-Line '```'
    }
}

Remove-Item Env:PGHOST -ErrorAction SilentlyContinue
Remove-Item Env:PGPORT -ErrorAction SilentlyContinue
Remove-Item Env:PGUSER -ErrorAction SilentlyContinue

Add-Section "17. Evaluation forensic"

$SchemaUsable = $false
$SchemaSources = 0

if ($CreateTableMatches.Count -gt 0) {
    $SchemaSources++
    $SchemaUsable = $true
}

if ($DdlMatches.Count -gt 0) {
    $SchemaSources++
}

if ($MigrationCandidates.Count -gt 0) {
    $SchemaSources++
}

Add-Line "Nombre de sources potentielles de schema : **$SchemaSources**"
Add-Line ""

if ($CreateTableMatches.Count -gt 0) {
    Add-Line "### SCENARIO A ? SCHEMA POTENTIELLEMENT EXPLOITABLE"
    Add-Line ""
    Add-Line "Des definitions `CREATE TABLE` ont ete retrouvees."
    Add-Line "Une analyse plus detaillee du modele doit etre faite avant"
    Add-Line "toute initialisation PostgreSQL."
}

if ($MigrationCandidates.Count -gt 0) {
    Add-Line "### SCENARIO B ? MIGRATIONS A ANALYSER"
    Add-Line ""
    Add-Line "Des fichiers candidats aux migrations existent."
    Add-Line "Ils doivent etre analyses avant toute creation/initialisation."
}

$SchemaNotFound = ($CreateTableMatches.Count -eq 0) -and ($MigrationCandidates.Count -eq 0)
if ($SchemaNotFound) {
    Add-Line "### SCENARIO C ? SCHEMA NON RETROUVE"
    Add-Line ""
    Add-Line "Aucune source evidente de schema PostgreSQL complet n'a ete retrouvee."
    Add-Line ""
    Add-Line "Il ne faut PAS creer des tables arbitrairement."
    Add-Line "Le modele devra etre reconstruit a partir du code applicatif"
    Add-Line "et des besoins fonctionnels documentes."
}

Add-Section "18. Decision ENV-06"

Add-Line "| Condition | Decision |"
Add-Line "|---|---|"

if ($CreateTableMatches.Count -gt 0) {
    Add-Line "| CREATE TABLE trouve | **CONTINUER VERS ANALYSE DU SCHEMA** |"
}
else {
    Add-Line "| CREATE TABLE absent | **NE PAS INITIALISER LA DB** |"
}

if ($MigrationCandidates.Count -gt 0) {
    Add-Line "| Migrations detectees | **ANALYSER LES MIGRATIONS** |"
}
else {
    Add-Line "| Migrations absentes | **VERIFIER LE MODELE DANS LE CODE** |"
}

if ($DdlMatches.Count -gt 0) {
    Add-Line "| DDL dans PHP | **AUDITER AVANT EXECUTION** |"
}
else {
    Add-Line "| DDL PHP absent | **PAS DE MIGRATION AUTOMATIQUE IDENTIFIEE** |"
}

Add-Line ""
Add-Line "### Regle absolue"
Add-Line ""
Add-Line "Aucune creation de `imc_clarodoro` ne doit etre effectuee"
Add-Line "sur la base de suppositions."

Add-Section "19. Resume d'execution"

$FinishedAt = Get-Date
$Duration = $FinishedAt - $StartedAt
$startStr = $StartedAt.ToString("yyyy-MM-dd HH:mm:ss")
$endStr = $FinishedAt.ToString("yyyy-MM-dd HH:mm:ss")
$durationStr = $Duration.TotalSeconds.ToString("0.00")

Add-Line "- Debut : $startStr"
Add-Line "- Fin : $endStr"
Add-Line "- Duree : $durationStr secondes"
Add-Line ""
Add-Line "**ENV-06 est termine en mode READ-ONLY.**"

$ReportContent = $Lines -join "`r`n"

Set-Content -LiteralPath $Report -Value $ReportContent -Encoding UTF8
Set-Content -LiteralPath $FinalReport -Value $ReportContent -Encoding UTF8

Write-Host ""
Write-Host "============================================================"
Write-Host " ENV-06 ? SCHEMA FORENSIC AUDIT"
Write-Host "============================================================"
Write-Host ""
Write-Host "Projet : $ProjectRoot"
Write-Host ""
Write-Host "Rapport :"
Write-Host "  $FinalReport"
Write-Host ""
Write-Host "MODE : READ-ONLY"
Write-Host ""
Write-Host "Aucune base n'a ete creee."
Write-Host "Aucune table n'a ete creee."
Write-Host "Aucune donnee n'a ete modifiee."
Write-Host ""
Write-Host "============================================================"
