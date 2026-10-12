param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('Backup', 'Restore')]
    [string]$Mode,
    [string]$BackupDirectory = (Join-Path $PSScriptRoot '..\backups'),
    [string]$BackupFile,
    [string]$TargetDatabase,
    [switch]$ConfirmRestore
)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
function Get-RequiredEnvironmentVariable {
    param([Parameter(Mandatory = $true)][string]$Name)
    $value = [Environment]::GetEnvironmentVariable($Name)
    if ([string]::IsNullOrWhiteSpace($value)) { throw "Variable d'environnement manquante : $Name. N'ajoutez aucun secret au dépôt." }
    return $value
}
function Get-PostgresTool {
    param([Parameter(Mandatory = $true)][string]$Name)
    $command = Get-Command $Name -ErrorAction SilentlyContinue
    if (-not $command) { throw "$Name est introuvable dans PATH. Ajoutez le dossier bin de PostgreSQL au PATH." }
    return $command.Source
}
$hostName = if ($env:DB_HOST) { $env:DB_HOST } else { 'localhost' }
$port = if ($env:DB_PORT) { $env:DB_PORT } else { '5432' }
$user = Get-RequiredEnvironmentVariable -Name 'DB_USER'
$sourceDatabase = Get-RequiredEnvironmentVariable -Name 'DB_NAME'
$password = Get-RequiredEnvironmentVariable -Name 'DB_PASSWORD'
if ($port -notmatch '^\d{1,5}$' -or [int]$port -lt 1 -or [int]$port -gt 65535) { throw 'DB_PORT doit être un port TCP valide.' }
if ($sourceDatabase -notmatch '^[A-Za-z0-9_]+$') { throw 'DB_NAME doit contenir uniquement lettres, chiffres et caractères soulignés.' }
$pgDump = Get-PostgresTool -Name 'pg_dump'
$pgRestore = Get-PostgresTool -Name 'pg_restore'
$psql = Get-PostgresTool -Name 'psql'
$previousPgPassword = $env:PGPASSWORD
$env:PGPASSWORD = $password
try {
    if ($Mode -eq 'Backup') {
        $resolvedDirectory = [System.IO.Path]::GetFullPath($BackupDirectory)
        New-Item -ItemType Directory -Path $resolvedDirectory -Force | Out-Null
        $timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
        $BackupFile = Join-Path $resolvedDirectory "imc_clarodoro_$($timestamp).backup"
        if (Test-Path -LiteralPath $BackupFile) { throw "Le fichier existe déjà : $BackupFile" }
        Write-Host "Sauvegarde PostgreSQL de '$sourceDatabase' vers un fichier local..."
        $dumpArgs = @('--host', $hostName, '--port', $port, '--username', $user, '--dbname', $sourceDatabase, '--format', 'custom', '--no-owner', '--no-acl', '--file', $BackupFile)
        & $pgDump @dumpArgs
        if ($LASTEXITCODE -ne 0) {
            Remove-Item -LiteralPath $BackupFile -Force -ErrorAction SilentlyContinue
            throw "pg_dump a échoué (code $LASTEXITCODE)."
        }
        if (-not (Test-Path -LiteralPath $BackupFile) -or (Get-Item -LiteralPath $BackupFile).Length -le 0) { throw 'La sauvegarde est absente ou vide.' }
        $hash = (Get-FileHash -LiteralPath $BackupFile -Algorithm SHA256).Hash
        $manifest = [ordered]@{
            format = 'PostgreSQL custom dump'
            database = $sourceDatabase
            host = $hostName
            port = [int]$port
            createdAtUtc = [DateTime]::UtcNow.ToString('o')
            file = [IO.Path]::GetFileName($BackupFile)
            sizeBytes = (Get-Item -LiteralPath $BackupFile).Length
            sha256 = $hash
            restorePolicy = 'Restore only into a new, separate database; never overwrite the source database.'
        }
        $manifestPath = "$BackupFile.manifest.json"
        $manifest | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $manifestPath -Encoding utf8
        Write-Host '[OK] Sauvegarde créée.'
        Write-Host "Fichier : $BackupFile"
        Write-Host "Manifeste SHA-256 : $manifestPath"
        Write-Host "SHA-256 : $hash"
        Write-Host 'Conservez les deux fichiers sur un support séparé et protégé.'
    } else {
        if (-not $ConfirmRestore) { throw 'Restauration bloquée. Relancez avec -ConfirmRestore après avoir vérifié la cible.' }
        if ([string]::IsNullOrWhiteSpace($BackupFile) -or -not (Test-Path -LiteralPath $BackupFile -PathType Leaf)) { throw 'Indiquez -BackupFile avec un fichier de sauvegarde existant.' }
        if ([string]::IsNullOrWhiteSpace($TargetDatabase) -or $TargetDatabase -notmatch '^[A-Za-z][A-Za-z0-9_]{0,62}$') { throw 'TargetDatabase doit commencer par une lettre et contenir lettres, chiffres et _ (63 caractères max).' }
        if ($TargetDatabase -eq $sourceDatabase) { throw 'REFUS : la cible est la base source DB_NAME. Choisissez une nouvelle base de test.' }
        $resolvedBackup = (Resolve-Path -LiteralPath $BackupFile).Path
        $manifestPath = "$resolvedBackup.manifest.json"
        if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) { throw "Manifeste absent : $manifestPath. Restauration refusée." }
        $manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
        $actualHash = (Get-FileHash -LiteralPath $resolvedBackup -Algorithm SHA256).Hash
        if ($manifest.sha256 -ne $actualHash) { throw 'ÉCHEC INTÉGRITÉ : le SHA-256 ne correspond pas au manifeste.' }
        if ($manifest.database -and $manifest.database -ne $sourceDatabase) { Write-Warning "Le manifeste indique '$($manifest.database)' mais DB_NAME vaut '$sourceDatabase'. Vérifiez vos paramètres." }
        $existsArgs = @('--host', $hostName, '--port', $port, '--username', $user, '--dbname', 'postgres', '--no-psqlrc', '--tuples-only', '--no-align', '--command', "SELECT 1 FROM pg_database WHERE datname = '$TargetDatabase';")
        $existsOutput = & $psql @existsArgs
        if ($LASTEXITCODE -ne 0) { throw "Impossible de vérifier la base cible (code $LASTEXITCODE)." }
        if (($existsOutput | Out-String).Trim() -eq '1') { throw "La base cible '$TargetDatabase' existe déjà. Aucune base existante ne sera écrasée." }
        Write-Warning "Création d'une nouvelle base '$TargetDatabase'. La source '$sourceDatabase' ne sera pas modifiée."
        $quote = [char]34
        $createSql = 'CREATE DATABASE ' + $quote + $TargetDatabase + $quote + ';'
        $createArgs = @('--host', $hostName, '--port', $port, '--username', $user, '--dbname', 'postgres', '--no-psqlrc', '--command', $createSql)
        & $psql @createArgs
        if ($LASTEXITCODE -ne 0) { throw "Création de la base cible échouée (code $LASTEXITCODE)." }
        $restoreArgs = @('--host', $hostName, '--port', $port, '--username', $user, '--dbname', $TargetDatabase, '--no-owner', '--no-acl', '--exit-on-error', $resolvedBackup)
        & $pgRestore @restoreArgs
        if ($LASTEXITCODE -ne 0) { throw "pg_restore a échoué (code $LASTEXITCODE). La base cible peut être partielle; la source n'a pas été modifiée. Inspectez la cible." }
        Write-Host '[OK] Restauration terminée dans une base séparée.'
        Write-Host "Base restaurée : $TargetDatabase"
        Write-Host "La base source n'a pas été modifiée. Vérifiez les données avant toute bascule."
    }
} finally {
    if ($null -eq $previousPgPassword) { Remove-Item Env:PGPASSWORD -ErrorAction SilentlyContinue }
    else { $env:PGPASSWORD = $previousPgPassword }
}
