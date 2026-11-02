param(
    [Parameter(Mandatory = $true)][string]$AppRoot
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$AppRoot = [System.IO.Path]::GetFullPath($AppRoot)
$php = Join-Path $AppRoot 'runtime\php\php.exe'
$bootstrap = Join-Path $AppRoot 'bootstrap-auth.php'
$programDataConfig = Join-Path $env:ProgramData 'IMC-Clarodaro\config\.env'
$legacyConfig = Join-Path $AppRoot '.env'

function ConvertFrom-SecureInput([Security.SecureString]$Value) {
    $pointer = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($Value)
    try {
        return [Runtime.InteropServices.Marshal]::PtrToStringBSTR($pointer)
    }
    finally {
        [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($pointer)
    }
}

if (-not (Test-Path -LiteralPath $php -PathType Leaf) -or -not (Test-Path -LiteralPath $bootstrap -PathType Leaf)) {
    throw 'Runtime PHP ou script bootstrap-auth.php introuvable.'
}
if (Test-Path -LiteralPath $programDataConfig -PathType Leaf) {
    $env:IMC_CLARODARO_ENV_FILE = $programDataConfig
}
elseif (-not (Test-Path -LiteralPath $legacyConfig -PathType Leaf)) {
    throw 'Aucun fichier .env applicatif valide na été trouvé.'
}

$checkCode = 'require "config/database.php"; $pdo = getDatabaseConnection(); $stmt = $pdo->query("SELECT 1 FROM users u LEFT JOIN roles r ON r.id = u.role_id WHERE LOWER(u.username) = ''pdg'' OR r.name = ''PDG'' LIMIT 1"); exit($stmt->fetchColumn() !== false ? 0 : 2);'
Push-Location $AppRoot
try {
    & $php -r $checkCode
    $checkExitCode = $LASTEXITCODE
    if ($checkExitCode -eq 0) {
        Write-Host 'Un compte PDG existe déjà. Aucun utilisateur, rôle ou droit ne sera modifié.'
        return
    }
    if ($checkExitCode -ne 2) {
        throw 'Impossible de vérifier de façon fiable si un compte PDG existe. Bootstrap annulé.'
    }

    do {
        $validPassword = $false
        $firstSecure = Read-Host 'Mot de passe initial du compte PDG (12 caractères minimum, caractères ASCII)' -AsSecureString
        $secondSecure = Read-Host 'Confirmez le mot de passe PDG' -AsSecureString
        $first = ConvertFrom-SecureInput $firstSecure
        $second = ConvertFrom-SecureInput $secondSecure
        if ($first.Length -lt 12 -or $first -notmatch '^[\x20-\x7E]+$') {
            Write-Host 'Mot de passe invalide : 12 caractères ASCII imprimables minimum.' -ForegroundColor Yellow
            $validPassword = $false
        }
        elseif ($first -cne $second) {
            Write-Host 'Les deux mots de passe ne correspondent pas.' -ForegroundColor Yellow
            $matches = $false
        }
        else {
            $validPassword = $true
        }
    } until ($validPassword)

    $env:IMC_BOOTSTRAP_PASSWORD = $first
    try {
        & $php $bootstrap
        if ($LASTEXITCODE -ne 0) {
            throw 'Le bootstrap PDG a échoué. Aucun compte existant ne doit être modifié.'
        }
        Write-Host 'Compte PDG initial créé avec succès. Conservez votre mot de passe en lieu sûr.' -ForegroundColor Green
    }
    finally {
        Remove-Item Env:\IMC_BOOTSTRAP_PASSWORD -ErrorAction SilentlyContinue
        $first = $null
        $second = $null
        $firstSecure.Dispose()
        $secondSecure.Dispose()
    }
}
finally {
    Pop-Location
    Remove-Item Env:\IMC_CLARODARO_ENV_FILE -ErrorAction SilentlyContinue
}
