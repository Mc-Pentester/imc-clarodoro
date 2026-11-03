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
$locationPushed = $false

function Write-LauncherLog([string]$Message) {
    $line = '{0} {1}{2}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff'), $Message, [Environment]::NewLine
    try {
        [System.IO.File]::AppendAllText($logFile, $line, (New-Object System.Text.UTF8Encoding($false)))
    }
    catch {
        [Console]::Error.WriteLine($line)
        throw
    }
}

try {
    New-Item -ItemType Directory -Path $logRoot -Force | Out-Null
    Write-LauncherLog 'Démarrage du lanceur PHP Clarodaro.'
    Write-LauncherLog ("Identité : " + [Security.Principal.WindowsIdentity]::GetCurrent().Name)
    Write-LauncherLog ("Application : " + $AppRoot)
    Write-LauncherLog ("PHP : " + $php)
    Write-LauncherLog ("Routeur : " + $router)
    Write-LauncherLog ("Port HTTP : " + $HttpPort)

    if (-not (Test-Path -LiteralPath $php -PathType Leaf)) {
        throw "Runtime PHP introuvable : $php"
    }
    if (-not (Test-Path -LiteralPath $router -PathType Leaf)) {
        throw "Routeur PHP introuvable : $router"
    }

    if ($EnvironmentFile) {
        if (-not (Test-Path -LiteralPath $EnvironmentFile -PathType Leaf)) {
            throw "Configuration ProgramData introuvable : $EnvironmentFile"
        }
        $env:IMC_CLARODARO_ENV_FILE = [System.IO.Path]::GetFullPath($EnvironmentFile)
        Write-LauncherLog ("Configuration protégée sélectionnée : " + $env:IMC_CLARODARO_ENV_FILE)
    }

    Set-Location -LiteralPath $AppRoot
    $locationPushed = $true

    Write-LauncherLog 'Vérification du runtime PHP.'
    $versionOutput = @(& $php -v 2>&1)
    $versionExitCode = $LASTEXITCODE
    foreach ($line in $versionOutput) { Write-LauncherLog ([string]$line) }
    if ($versionExitCode -ne 0) {
        throw "PHP ne peut pas être exécuté (code $versionExitCode)."
    }

    Write-LauncherLog 'Lancement du serveur PHP intégré sur toutes les interfaces LAN.'
    & $php -S ("0.0.0.0:{0}" -f $HttpPort) -t $AppRoot $router 2>&1 |
        ForEach-Object { Write-LauncherLog ([string]$_) }
    $phpExitCode = $LASTEXITCODE
    Write-LauncherLog ("Le processus PHP s'est terminé avec le code " + $phpExitCode + '.')
    exit $phpExitCode
}
catch {
    try {
        Write-LauncherLog ("ERREUR FATALE : " + $_.Exception.Message)
        Write-LauncherLog ("Détail : " + ($_ | Out-String))
    }
    catch {
        [Console]::Error.WriteLine("Échec du lanceur PHP : " + $_.Exception.Message)
    }
    exit 1
}
finally {
    if ($locationPushed) {
        Pop-Location
    }
}
