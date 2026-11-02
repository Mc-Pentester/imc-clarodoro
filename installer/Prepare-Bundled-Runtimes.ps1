param(
    [string]$RepositoryRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$payloadRoot = Join-Path $PSScriptRoot 'payload'
$tempRoot = Join-Path $env:RUNNER_TEMP 'clarodaro-runtime'
$phpZip = Join-Path $tempRoot 'php-8.4.27-nts-x64.zip'
$postgresZip = Join-Path $tempRoot 'postgresql-18.6-5-windows-x64-binaries.zip'
$phpExtract = Join-Path $tempRoot 'php-extracted'
$postgresExtract = Join-Path $tempRoot 'postgres-extracted'

$phpUrl = 'https://downloads.php.net/~windows/releases/archives/php-8.4.27-1-nts-Win32-vs17-x64.zip'
$phpSha256 = 'dbae154a0a89791f36c3d48e68bae797878333e7d6cb5721e74617de59b63ab7'
$postgresUrl = 'https://get.enterprisedb.com/postgresql/postgresql-18.6-5-windows-x64-binaries.zip'
$postgresSha256 = 'e2246ba91d22345bc3d017586c09ede52d9df180b1eeb480f050445f1cad84e2'

if (Test-Path -LiteralPath $tempRoot) {
    Remove-Item -LiteralPath $tempRoot -Recurse -Force
}
if (Test-Path -LiteralPath $payloadRoot) {
    Remove-Item -LiteralPath $payloadRoot -Recurse -Force
}

New-Item -ItemType Directory -Path $tempRoot, $phpExtract, $postgresExtract,
    (Join-Path $payloadRoot 'php'), (Join-Path $payloadRoot 'postgresql') -Force | Out-Null

Write-Host 'Téléchargement du runtime PHP officiel...'
Invoke-WebRequest -Uri $phpUrl -OutFile $phpZip
$actualPhpHash = (Get-FileHash -LiteralPath $phpZip -Algorithm SHA256).Hash.ToLowerInvariant()
if ($actualPhpHash -ne $phpSha256) {
    throw "SHA-256 PHP invalide. Attendu=$phpSha256 Obtenu=$actualPhpHash"
}

Write-Host 'Téléchargement des binaires PostgreSQL EDB...'
Invoke-WebRequest -Uri $postgresUrl -OutFile $postgresZip
$actualPostgresHash = (Get-FileHash -LiteralPath $postgresZip -Algorithm SHA256).Hash.ToLowerInvariant()
if ($actualPostgresHash -ne $postgresSha256) {
    throw "SHA-256 PostgreSQL invalide. Attendu=$postgresSha256 Obtenu=$actualPostgresHash"
}

Expand-Archive -LiteralPath $phpZip -DestinationPath $phpExtract -Force
Expand-Archive -LiteralPath $postgresZip -DestinationPath $postgresExtract -Force

$phpExe = Get-ChildItem -LiteralPath $phpExtract -Filter 'php.exe' -File -Recurse |
    Select-Object -First 1
if (-not $phpExe) {
    throw 'php.exe absent de l’archive PHP officielle.'
}
Get-ChildItem -LiteralPath $phpExe.Directory.FullName -Force | Copy-Item -Destination (Join-Path $payloadRoot 'php') -Recurse -Force

$postgresExe = Get-ChildItem -LiteralPath $postgresExtract -Filter 'postgres.exe' -File -Recurse |
    Select-Object -First 1
if (-not $postgresExe) {
    throw 'postgres.exe absent de l’archive EDB.'
}
$postgresBin = $postgresExe.Directory.FullName
$postgresRoot = Split-Path -Parent $postgresBin
foreach ($directory in @('bin', 'lib', 'share')) {
    $sourceDirectory = Join-Path $postgresRoot $directory
    if (-not (Test-Path -LiteralPath $sourceDirectory -PathType Container)) {
        throw "Répertoire PostgreSQL requis absent : $sourceDirectory"
    }
    Copy-Item -LiteralPath $sourceDirectory -Destination (Join-Path $payloadRoot 'postgresql') -Recurse -Force
}

$phpPayload = Join-Path $payloadRoot 'php'
$phpIniProduction = Join-Path $phpPayload 'php.ini-production'
$phpIni = Join-Path $phpPayload 'php.ini'
if (-not (Test-Path -LiteralPath $phpIniProduction)) {
    throw 'php.ini-production absent du runtime PHP.'
}
Copy-Item -LiteralPath $phpIniProduction -Destination $phpIni -Force
$iniText = Get-Content -LiteralPath $phpIni -Raw
$iniText = $iniText -replace '(?m)^;?\s*extension_dir\s*=\s*"ext"\s*$', 'extension_dir = "ext"'
foreach ($extension in @('curl', 'fileinfo', 'mbstring', 'openssl', 'pdo_pgsql', 'pgsql', 'zip')) {
    $iniText = [regex]::Replace(
        $iniText,
        "(?m)^;\s*extension\s*=\s*$([regex]::Escape($extension))\s*$",
        "extension=$extension"
    )
}
Set-Content -LiteralPath $phpIni -Value $iniText -Encoding ascii

foreach ($extension in @('php_pdo_pgsql.dll', 'php_pgsql.dll')) {
    if (-not (Test-Path -LiteralPath (Join-Path $phpPayload "ext\$extension"))) {
        throw "Extension PHP PostgreSQL manquante : $extension"
    }
}

$phpVersion = (& (Join-Path $phpPayload 'php.exe') -v 2>&1 | Select-Object -First 1)
if ($LASTEXITCODE -ne 0) {
    throw "Le runtime PHP ne démarre pas : $phpVersion"
}
$phpModules = & (Join-Path $phpPayload 'php.exe') -m 2>&1
if ($LASTEXITCODE -ne 0 -or $phpModules -notcontains 'PDO' -or $phpModules -notcontains 'pdo_pgsql' -or $phpModules -notcontains 'pgsql') {
    throw 'PHP ne charge pas correctement PDO, pdo_pgsql et pgsql.'
}

$postgresVersion = (& (Join-Path $payloadRoot 'postgresql\bin\postgres.exe') --version 2>&1)
if ($LASTEXITCODE -ne 0) {
    throw "Le binaire PostgreSQL ne démarre pas : $postgresVersion"
}
& (Join-Path $payloadRoot 'postgresql\bin\pg_ctl.exe') --version
if ($LASTEXITCODE -ne 0) {
    throw 'pg_ctl.exe ne démarre pas.'
}

$manifest = [ordered]@{
    product = 'IMC-Clarodoro'
    architecture = 'windows-x64'
    php = [ordered]@{
        version = '8.4.27'
        package = 'php-8.4.27-1-nts-Win32-vs17-x64.zip'
        source = $phpUrl
        sha256 = $phpSha256
        modules = @('PDO', 'pdo_pgsql', 'pgsql', 'curl', 'fileinfo', 'mbstring', 'openssl', 'zip')
    }
    postgresql = [ordered]@{
        version = '18.6'
        package = 'postgresql-18.6-5-windows-x64-binaries.zip'
        source = $postgresUrl
        sha256 = $postgresSha256
    }
    note = 'Binaries bundled and checksum-verified at build time. Data directory and Windows service provisioning are handled separately; never initialize or replace an existing cluster during upgrade.'
}
$manifest | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $payloadRoot 'runtime-manifest.json') -Encoding utf8

Write-Host "PHP embarqué : $phpVersion"
Write-Host "PostgreSQL embarqué : $postgresVersion"
Write-Host "Payload prêt : $payloadRoot"
