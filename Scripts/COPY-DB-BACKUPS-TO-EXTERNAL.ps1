[CmdletBinding()]
param(
    [string]$SourceDirectory = (Join-Path $PSScriptRoot '..\backups'),
    [string]$DestinationDirectory = '',
    [string]$VolumeLabel = 'IMC_BACKUPS'
)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$logPath = Join-Path ([IO.Path]::GetFullPath($SourceDirectory)) 'external-copy.log'
function Write-BackupLog([string]$Message) {
    $line = '{0} {1}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Message
    Add-Content -LiteralPath $logPath -Value $line -Encoding utf8
    Write-Host $line
}

try {
    $source = [IO.Path]::GetFullPath($SourceDirectory)
    if (-not (Test-Path -LiteralPath $source -PathType Container)) {
        throw "Dossier source introuvable : $source"
    }
    # Résout le support par son étiquette, pas par une lettre fixe (F:, E:, etc.).
    # Une lettre peut changer d'un ordinateur à l'autre ou après reconnexion USB.
    if ([string]::IsNullOrWhiteSpace($DestinationDirectory)) {
        $volumes = @(Get-Volume -FileSystemLabel $VolumeLabel -ErrorAction SilentlyContinue |
            Where-Object { $_.DriveLetter -and $_.DriveType -eq 'Removable' })
        if ($volumes.Count -ne 1) {
            throw "Support USB attendu introuvable ou ambigu. Connectez un seul support amovible portant l'étiquette '$VolumeLabel'."
        }
        $DestinationDirectory = "$($volumes[0].DriveLetter):\IMC-Clarodoro-Backups"
    }

    $destinationFullPath = [IO.Path]::GetFullPath($DestinationDirectory)
    $driveRoot = [IO.Path]::GetPathRoot($destinationFullPath)
    if ([string]::IsNullOrWhiteSpace($driveRoot) -or $driveRoot -eq [IO.Path]::GetPathRoot($source)) {
        throw 'La destination doit être sur un support distinct du dossier source.'
    }
    if (-not (Test-Path -LiteralPath $driveRoot -PathType Container)) {
        throw "Support externe indisponible : $driveRoot"
    }
    New-Item -ItemType Directory -Path $destinationFullPath -Force | Out-Null

    $backups = @(Get-ChildItem -LiteralPath $source -Filter '*.backup' -File | Sort-Object Name)
    if ($backups.Count -eq 0) {
        Write-BackupLog 'Aucun fichier .backup à copier.'
        exit 0
    }

    $copied = 0
    foreach ($backup in $backups) {
        $manifestPath = "$($backup.FullName).manifest.json"
        if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) {
            Write-BackupLog "IGNORÉ (manifeste absent) : $($backup.Name)"
            continue
        }

        $manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
        $sourceHash = (Get-FileHash -LiteralPath $backup.FullName -Algorithm SHA256).Hash
        if ([string]$manifest.sha256 -ne $sourceHash -or [long]$manifest.sizeBytes -ne $backup.Length) {
            throw "Intégrité source invalide : $($backup.Name). Copie refusée."
        }

        $destinationBackup = Join-Path $destinationFullPath $backup.Name
        $destinationManifest = "$destinationBackup.manifest.json"

        if (Test-Path -LiteralPath $destinationBackup -PathType Leaf) {
            $existingHash = (Get-FileHash -LiteralPath $destinationBackup -Algorithm SHA256).Hash
            if ($existingHash -ne $sourceHash) {
                throw "Le fichier de destination existe avec un hash différent : $destinationBackup. Aucun écrasement effectué."
            }
        } else {
            Copy-Item -LiteralPath $backup.FullName -Destination $destinationBackup
        }

        if (Test-Path -LiteralPath $destinationManifest -PathType Leaf) {
            $existingManifest = Get-Content -LiteralPath $destinationManifest -Raw | ConvertFrom-Json
            if ([string]$existingManifest.sha256 -ne $sourceHash) {
                throw "Manifeste de destination incompatible : $destinationManifest. Aucun écrasement effectué."
            }
        } else {
            Copy-Item -LiteralPath $manifestPath -Destination $destinationManifest
        }

        $destinationHash = (Get-FileHash -LiteralPath $destinationBackup -Algorithm SHA256).Hash
        $verifiedManifest = Get-Content -LiteralPath $destinationManifest -Raw | ConvertFrom-Json
        if ($destinationHash -ne $sourceHash -or [string]$verifiedManifest.sha256 -ne $destinationHash) {
            throw "Vérification après copie échouée : $($backup.Name)"
        }
        $copied++
    }

    Write-BackupLog "SUCCÈS : $copied paire(s) backup/manifeste vérifiée(s) sur $destinationFullPath."
} catch {
    try { Write-BackupLog "ÉCHEC : $($_.Exception.Message)" } catch {}
    exit 1
}
