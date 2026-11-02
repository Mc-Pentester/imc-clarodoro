param(
    [Parameter(Mandatory = $true)][string]$AppRoot,
    [string]$EnvironmentFile = '',
    [int]$HttpPort = 8080
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$AppRoot = [System.IO.Path]::GetFullPath($AppRoot)
$php = Join-Path $AppRoot 'runtime\php\php.exe'
$router = Join-Path $AppRoot 'router.php'
$logRoot = Join-Path $env:ProgramData 'IMC-Clarodaro\logs'
$logFile = Join-Path $logRoot 'php-server.log'

if (-not (Test-Path -LiteralPath $php -PathType Leaf)) {
    throw "Runtime PHP introuvable : $php"
}
if (-not (Test-Path -LiteralPath $router -PathType Leaf)) {
    throw "Routeur PHP introuvable : $router"
}

New-Item -ItemType Directory -Path $logRoot -Force | Out-Null
if ($EnvironmentFile -and (Test-Path -LiteralPath $EnvironmentFile -PathType Leaf)) {
    $env:IMC_CLARODARO_ENV_FILE = [System.IO.Path]::GetFullPath($EnvironmentFile)
}
Set-Location -LiteralPath $AppRoot

# The scheduled task remains alive for the lifetime of PHP's built-in server.
& $php -S "0.0.0.0:$HttpPort" router.php *>> $logFile
exit $LASTEXITCODE
