param(
    [Parameter(Mandatory = $true)][string]$AppRoot,
    [Parameter(Mandatory = $true)][string]$EnvironmentFile,
    [Parameter(Mandatory = $true)][string]$PgBin,
    [string]$BackupDirectory = ''
)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$AppRoot = [IO.Path]::GetFullPath($AppRoot)
$EnvironmentFile = [IO.Path]::GetFullPath($EnvironmentFile)
$PgBin = [IO.Path]::GetFullPath($PgBin)
if ([string]::IsNullOrWhiteSpace($BackupDirectory)) {
    $BackupDirectory = Join-Path $AppRoot 'backups'
}
$BackupDirectory = [IO.Path]::GetFullPath($BackupDirectory)
$restoreScript = Join-Path $PSScriptRoot 'DB-BACKUP-RESTORE.ps1'

foreach ($required in @($EnvironmentFile, "$PgBin\pg_dump.exe", "$PgBin\pg_restore.exe", "$PgBin\psql.exe", $restoreScript)) {
    if (-not (Test-Path -LiteralPath $required -PathType Leaf)) {
        throw "Composant requis pour la sauvegarde introuvable : $required"
    }
}

# Charger les paramètres de connexion depuis le fichier protégé généré par
# l'installateur. Aucun mot de passe n'est placé dans la ligne de commande,
# dans le Planificateur Windows ou dans un fichier temporaire.
$config = @{}
foreach ($line in Get-Content -LiteralPath $EnvironmentFile) {
    $trimmed = ([string]$line).Trim()
    if (-not $trimmed -or $trimmed.StartsWith('#')) { continue }
    $separator = $trimmed.IndexOf('=')
    if ($separator -le 0) { continue }
    $key = $trimmed.Substring(0, $separator).Trim()
    $value = $trimmed.Substring($separator + 1).Trim()
    if ($value.Length -ge 2 -and (($value.StartsWith('"') -and $value.EndsWith('"')) -or ($value.StartsWith("'") -and $value.EndsWith("'")))) {
        $value = $value.Substring(1, $value.Length - 2)
    }
    $config[$key] = $value
}
foreach ($key in @('DB_NAME', 'DB_USER', 'DB_PASSWORD')) {
    if (-not $config.ContainsKey($key) -or [string]::IsNullOrWhiteSpace([string]$config[$key])) {
        throw "Paramètre $key absent du fichier de configuration protégé."
    }
}
$env:DB_HOST = if ($config.ContainsKey('DB_HOST') -and $config['DB_HOST']) { [string]$config['DB_HOST'] } else { '127.0.0.1' }
$env:DB_PORT = if ($config.ContainsKey('DB_PORT') -and $config['DB_PORT']) { [string]$config['DB_PORT'] } else { '55432' }
$env:DB_NAME = [string]$config['DB_NAME']
$env:DB_USER = [string]$config['DB_USER']
$env:DB_PASSWORD = [string]$config['DB_PASSWORD']
$env:Path = "$PgBin;$([Environment]::GetEnvironmentVariable('Path', 'Machine'))"

New-Item -ItemType Directory -Path $BackupDirectory -Force | Out-Null
& $restoreScript -Mode Backup -BackupDirectory $BackupDirectory
if ($LASTEXITCODE -ne 0) {
    throw "Le script PostgreSQL de sauvegarde a échoué (code $LASTEXITCODE)."
}
