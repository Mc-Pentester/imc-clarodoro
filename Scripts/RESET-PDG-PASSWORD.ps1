# Réinitialisation sécurisée du mot de passe PDG pour Clarodaro.
# Peut être lancé depuis n'importe quel répertoire, y compris System32.
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$scriptDirectory = Split-Path -Parent $MyInvocation.MyCommand.Path
$appRoot = [System.IO.Path]::GetFullPath((Join-Path $scriptDirectory '..'))
$phpScript = Join-Path $scriptDirectory 'RESET-PDG-PASSWORD.php'
$bundledPhp = Join-Path $appRoot 'runtime\php\php.exe'

if (-not (Test-Path -LiteralPath $phpScript -PathType Leaf)) {
    throw "Script PHP introuvable : $phpScript"
}

if (Test-Path -LiteralPath $bundledPhp -PathType Leaf) {
    $php = $bundledPhp
}
else {
    $phpCommand = Get-Command 'php.exe' -ErrorAction SilentlyContinue
    if (-not $phpCommand) {
        $phpCommand = Get-Command 'php' -ErrorAction SilentlyContinue
    }
    if (-not $phpCommand) {
        throw "PHP est introuvable. Runtime embarqué attendu : $bundledPhp"
    }
    $php = $phpCommand.Source
}

$protectedEnvironment = Join-Path $env:ProgramData 'IMC-Clarodaro\config\.env'
$legacyEnvironment = Join-Path $appRoot '.env'
$environmentFile = if (Test-Path -LiteralPath $protectedEnvironment -PathType Leaf) {
    $protectedEnvironment
}
elseif (Test-Path -LiteralPath $legacyEnvironment -PathType Leaf) {
    $legacyEnvironment
}
else {
    $null
}

$securePassword = Read-Host 'Nouveau mot de passe PDG (12 caractères minimum)' -AsSecureString
$bstr = [IntPtr]::Zero
$previousPassword = [Environment]::GetEnvironmentVariable('IMC_PDG_NEW_PASSWORD', 'Process')
$previousEnvironmentFile = [Environment]::GetEnvironmentVariable('IMC_CLARODARO_ENV_FILE', 'Process')

try {
    $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($securePassword)
    $passwordText = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr)
    if ([string]::IsNullOrEmpty($passwordText) -or $passwordText.Length -lt 12) {
        throw 'Le mot de passe doit contenir au moins 12 caractères.'
    }

    $env:IMC_PDG_NEW_PASSWORD = $passwordText
    if ($environmentFile) {
        $env:IMC_CLARODARO_ENV_FILE = $environmentFile
    }

    Push-Location $appRoot
    try {
        & $php $phpScript
        $exitCode = $LASTEXITCODE
    }
    finally {
        Pop-Location
    }

    if ($exitCode -ne 0) {
        throw "La réinitialisation a échoué (code PHP $exitCode). Le compte et les données n'ont pas été volontairement réinitialisés."
    }
}
finally {
    [Environment]::SetEnvironmentVariable('IMC_PDG_NEW_PASSWORD', $previousPassword, 'Process')
    [Environment]::SetEnvironmentVariable('IMC_CLARODARO_ENV_FILE', $previousEnvironmentFile, 'Process')
    if ($bstr -ne [IntPtr]::Zero) {
        [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
    }
    if ($null -ne $securePassword) {
        $securePassword.Dispose()
    }
    if (Get-Variable -Name passwordText -Scope Local -ErrorAction SilentlyContinue) {
        Remove-Variable -Name passwordText -Scope Local -Force -ErrorAction SilentlyContinue
    }
}
