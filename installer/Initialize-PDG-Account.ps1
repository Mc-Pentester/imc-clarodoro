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
    try { return [Runtime.InteropServices.Marshal]::PtrToStringBSTR($pointer) }
    finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($pointer) }
}

function Show-PdgCredentialDialog {
    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing
    [System.Windows.Forms.Application]::EnableVisualStyles()

    $form = New-Object System.Windows.Forms.Form
    $form.Text = 'Configuration initiale - Clarodaro'
    $form.StartPosition = 'CenterScreen'
    $form.Size = New-Object System.Drawing.Size(490, 330)
    $form.FormBorderStyle = 'FixedDialog'
    $form.MaximizeBox = $false
    $form.MinimizeBox = $false
    $form.TopMost = $true

    $intro = New-Object System.Windows.Forms.Label
    $intro.Text = 'Créez le compte administrateur principal (PDG) de votre établissement.'
    $intro.Location = New-Object System.Drawing.Point(20, 18)
    $intro.Size = New-Object System.Drawing.Size(440, 42)
    $form.Controls.Add($intro)

    $userLabel = New-Object System.Windows.Forms.Label
    $userLabel.Text = 'Identifiant'
    $userLabel.Location = New-Object System.Drawing.Point(22, 75)
    $userLabel.Size = New-Object System.Drawing.Size(130, 22)
    $form.Controls.Add($userLabel)

    $userValue = New-Object System.Windows.Forms.TextBox
    $userValue.Text = 'pdg'
    $userValue.ReadOnly = $true
    $userValue.Location = New-Object System.Drawing.Point(170, 72)
    $userValue.Size = New-Object System.Drawing.Size(270, 24)
    $form.Controls.Add($userValue)

    $passwordLabel = New-Object System.Windows.Forms.Label
    $passwordLabel.Text = 'Mot de passe (12 caractères min.)'
    $passwordLabel.Location = New-Object System.Drawing.Point(22, 117)
    $passwordLabel.Size = New-Object System.Drawing.Size(145, 38)
    $form.Controls.Add($passwordLabel)

    $password = New-Object System.Windows.Forms.TextBox
    $password.UseSystemPasswordChar = $true
    $password.Location = New-Object System.Drawing.Point(170, 117)
    $password.Size = New-Object System.Drawing.Size(270, 24)
    $form.Controls.Add($password)

    $confirmLabel = New-Object System.Windows.Forms.Label
    $confirmLabel.Text = 'Confirmer'
    $confirmLabel.Location = New-Object System.Drawing.Point(22, 163)
    $confirmLabel.Size = New-Object System.Drawing.Size(130, 22)
    $form.Controls.Add($confirmLabel)

    $confirm = New-Object System.Windows.Forms.TextBox
    $confirm.UseSystemPasswordChar = $true
    $confirm.Location = New-Object System.Drawing.Point(170, 160)
    $confirm.Size = New-Object System.Drawing.Size(270, 24)
    $form.Controls.Add($confirm)

    $hint = New-Object System.Windows.Forms.Label
    $hint.Text = 'Utilisez au moins 12 caractères ASCII imprimables.'
    $hint.Location = New-Object System.Drawing.Point(170, 190)
    $hint.Size = New-Object System.Drawing.Size(270, 34)
    $hint.ForeColor = [System.Drawing.Color]::DimGray
    $form.Controls.Add($hint)

    $ok = New-Object System.Windows.Forms.Button
    $ok.Text = 'Créer le compte PDG'
    $ok.Location = New-Object System.Drawing.Point(245, 235)
    $ok.Size = New-Object System.Drawing.Size(195, 32)
    $ok.DialogResult = [System.Windows.Forms.DialogResult]::OK
    $form.Controls.Add($ok)
    $form.AcceptButton = $ok

    $cancel = New-Object System.Windows.Forms.Button
    $cancel.Text = 'Annuler'
    $cancel.Location = New-Object System.Drawing.Point(145, 235)
    $cancel.Size = New-Object System.Drawing.Size(90, 32)
    $cancel.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
    $form.Controls.Add($cancel)
    $form.CancelButton = $cancel

    try {
        while ($true) {
            $result = $form.ShowDialog()
            if ($result -ne [System.Windows.Forms.DialogResult]::OK) {
                return $null
            }
            if ($password.Text.Length -lt 12 -or $password.Text -notmatch '^[\x20-\x7E]+$') {
                [System.Windows.Forms.MessageBox]::Show(
                    'Le mot de passe doit contenir au moins 12 caractères ASCII imprimables.',
                    'Mot de passe invalide',
                    [System.Windows.Forms.MessageBoxButtons]::OK,
                    [System.Windows.Forms.MessageBoxIcon]::Warning
                ) | Out-Null
                continue
            }
            if ($password.Text -cne $confirm.Text) {
                [System.Windows.Forms.MessageBox]::Show(
                    'Les deux mots de passe ne correspondent pas.',
                    'Confirmation incorrecte',
                    [System.Windows.Forms.MessageBoxButtons]::OK,
                    [System.Windows.Forms.MessageBoxIcon]::Warning
                ) | Out-Null
                continue
            }
            return $password.Text
        }
    }
    finally {
        $password.Clear()
        $confirm.Clear()
        $form.Dispose()
    }
}

if (-not (Test-Path -LiteralPath $php -PathType Leaf) -or -not (Test-Path -LiteralPath $bootstrap -PathType Leaf)) {
    throw 'Runtime PHP ou script bootstrap-auth.php introuvable.'
}
if (Test-Path -LiteralPath $programDataConfig -PathType Leaf) {
    $env:IMC_CLARODARO_ENV_FILE = $programDataConfig
}
elseif (-not (Test-Path -LiteralPath $legacyConfig -PathType Leaf)) {
    throw 'Aucun fichier .env applicatif valide n''a été trouvé.'
}

$checkCode = 'require "config/database.php"; $pdo = getDatabaseConnection(); $stmt = $pdo->query("SELECT 1 FROM users u LEFT JOIN roles r ON r.id = u.role_id WHERE LOWER(u.username) = ''pdg'' OR r.name = ''PDG'' LIMIT 1"); exit($stmt->fetchColumn() !== false ? 0 : 2);'
Push-Location $AppRoot
try {
    & $php -r $checkCode
    $checkExitCode = $LASTEXITCODE
    if ($checkExitCode -eq 0) {
        Write-Host 'Un compte PDG existe déjà. Identifiants, rôle et permissions conservés.'
        exit 0
    }
    if ($checkExitCode -ne 2) {
        throw 'Impossible de vérifier de façon fiable si un compte PDG existe. Initialisation annulée.'
    }

    # Un secret d'environnement n'est accepté que pour un déploiement automatisé explicite (CI).
    # En installation interactive, l'utilisateur saisit lui-même son mot de passe dans la fenêtre sécurisée.
    $first = [string]$env:IMC_BOOTSTRAP_PASSWORD
    if ([string]::IsNullOrWhiteSpace($first)) {
        $first = Show-PdgCredentialDialog
        if ($null -eq $first) {
            throw 'Création du compte PDG annulée. L''installation ne peut pas être finalisée sans ce compte.'
        }
    }
    if ($first.Length -lt 12 -or $first -notmatch '^[\x20-\x7E]+$') {
        throw 'Le mot de passe PDG doit contenir au moins 12 caractères ASCII imprimables.'
    }

    $env:IMC_BOOTSTRAP_PASSWORD = $first
    try {
        & $php $bootstrap
        if ($LASTEXITCODE -ne 0) {
            throw 'La création du compte PDG a échoué. Aucun compte existant ne doit être modifié.'
        }
        Write-Host 'Compte PDG initial créé avec succès.'
    }
    finally {
        Remove-Item Env:\IMC_BOOTSTRAP_PASSWORD -ErrorAction SilentlyContinue
        $first = $null
    }
}
finally {
    Pop-Location
    Remove-Item Env:\IMC_CLARODARO_ENV_FILE -ErrorAction SilentlyContinue
}