$ErrorActionPreference = "Continue"

# CONFIGURATION
$ProjectRoot = "C:\IMC-Clarodoro-securise-client\IMC-Clarodoro"
$TargetDocumentRoot = $ProjectRoot.Replace("\","/")
$BaseUrl = "http://localhost:8080"
$ReportDir = Join-Path $ProjectRoot "audit"
$ReportFile = Join-Path $ReportDir "ENV-04-APACHE-DOCUMENTROOT-CORRECTION-REPORT.md"
$ReportFinalFile = Join-Path $ReportDir "ENV-04-APACHE-DOCUMENTROOT-CORRECTION-REPORT-FINAL.md"
$BackupDir = Join-Path $ProjectRoot "audit\apache-backups"
$Timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$Results = New-Object System.Collections.Generic.List[object]

New-Item -ItemType Directory -Force -Path $ReportDir | Out-Null
New-Item -ItemType Directory -Force -Path $BackupDir | Out-Null

# FONCTION RESULTAT
function Add-Result {
    param(
        [string]$ID,
        [ValidateSet("PASS","WARNING","BLOCKED")]
        [string]$Status,
        [string]$Component,
        [string]$Details
    )

    $Results.Add(
        [PSCustomObject]@{
            ID        = $ID
            Status    = $Status
            Component = $Component
            Details   = $Details
        }
    )

    switch ($Status) {
        "PASS" {
            Write-Host "[PASS] $ID - $Component - $Details" -ForegroundColor Green
        }
        "WARNING" {
            Write-Host "[WARN] $ID - $Component - $Details" -ForegroundColor Yellow
        }
        "BLOCKED" {
            Write-Host "[BLOCKED] $ID - $Component - $Details" -ForegroundColor Red
        }
    }
}

# FONCTION EXTRACTION CHEMIN CONFIGURATION
function Get-ConfigPathFromProcess {
    param([object]$Process)

    try {
        $CommandLine = Get-CimInstance Win32_Process -Filter "ProcessId = $($Process.Id)" -ErrorAction Stop | Select-Object -ExpandProperty CommandLine

        if ([string]::IsNullOrWhiteSpace($CommandLine)) {
            return $null
        }

        if ($CommandLine -match '(?i)(?:^|\s)-f\s+"([^"]+)"') {
            return $Matches[1]
        }

        if ($CommandLine -match '(?i)(?:^|\s)-f\s+([^\s]+)') {
            return $Matches[1]
        }
    }
    catch {
    }

    return $null
}

# FONCTION DETECTION HTTPD
function Find-HttpdExecutable {
    $Candidates = @()

    $Processes = Get-Process -Name "httpd" -ErrorAction SilentlyContinue

    foreach ($Process in $Processes) {
        try {
            $Path = $Process.Path
            if ($Path) {
                $Candidates += $Path
            }
        }
        catch {
        }
    }

    $Candidates += @(
        "C:\Apache24\bin\httpd.exe",
        "C:\xampp\apache\bin\httpd.exe",
        "C:\wamp64\bin\apache\apache2.4.*\bin\httpd.exe",
        "C:\Program Files\Apache Software Foundation\Apache2.4\bin\httpd.exe"
    )

    try {
        $Command = Get-Command httpd.exe -ErrorAction SilentlyContinue
        if ($Command) {
            $Candidates += $Command.Source
        }
    }
    catch {
    }

    foreach ($Candidate in ($Candidates | Select-Object -Unique)) {
        if (Test-Path $Candidate) {
            return $Candidate
        }
        try {
            $Resolved = Get-ChildItem -Path $Candidate -File -ErrorAction SilentlyContinue
            if ($Resolved) {
                return $Resolved[0].FullName
            }
        }
        catch {
        }
    }

    return $null
}

# FONCTION DETECTION CONFIGURATION
function Find-ApacheConfig {
    param([string]$HttpdExe)

    $Processes = Get-Process -Name "httpd" -ErrorAction SilentlyContinue

    foreach ($Process in $Processes) {
        $Config = Get-ConfigPathFromProcess $Process
        if ($Config -and (Test-Path $Config)) {
            return $Config
        }
    }

    try {
        $Output = & $HttpdExe -V 2>&1
        foreach ($Line in $Output) {
            if ($Line -match 'SERVER_CONFIG_FILE="([^"]+)"') {
                $ConfigFileName = $Matches[1]
                $HttpdDir = Split-Path $HttpdExe -Parent
                $ApacheRoot = Split-Path $HttpdDir -Parent
                $Candidate = Join-Path $ApacheRoot $ConfigFileName
                if (Test-Path $Candidate) {
                    return $Candidate
                }
            }
        }
    }
    catch {
    }

    $Fallbacks = @(
        (Join-Path (Split-Path (Split-Path $HttpdExe -Parent) -Parent) "conf\httpd.conf"),
        "C:\Apache24\conf\httpd.conf",
        "C:\xampp\apache\conf\httpd.conf"
    )

    foreach ($Candidate in $Fallbacks) {
        if (Test-Path $Candidate) {
            return $Candidate
        }
    }

    return $null
}

# FONCTION TEST HTTP
function Test-Endpoint {
    param([string]$ID, [string]$Path)

    $Url = "$BaseUrl$Path"

    try {
        $Timer = [System.Diagnostics.Stopwatch]::StartNew()
        $Response = Invoke-WebRequest -Uri $Url -Method GET -UseBasicParsing -TimeoutSec 15 -ErrorAction Stop
        $Timer.Stop()

        $StatusCode = [int]$Response.StatusCode
        $Elapsed = $Timer.ElapsedMilliseconds

        if ($StatusCode -ge 200 -and $StatusCode -lt 300) {
            Add-Result "$ID-HTTP" "PASS" $Path "HTTP $StatusCode en ${Elapsed}ms"
        }
        elseif ($StatusCode -ge 300 -and $StatusCode -lt 500) {
            Add-Result "$ID-HTTP" "WARNING" $Path "HTTP $StatusCode en ${Elapsed}ms"
        }
        else {
            Add-Result "$ID-HTTP" "BLOCKED" $Path "HTTP $StatusCode en ${Elapsed}ms"
        }

        return [PSCustomObject]@{
            Path       = $Path
            StatusCode = $StatusCode
            ElapsedMs  = $Elapsed
            Body       = $Response.Content
        }
    }
    catch {
        $StatusCode = $null
        try {
            if ($_.Exception.Response) {
                $StatusCode = [int]$_.Exception.Response.StatusCode
            }
        }
        catch {
        }

        if ($null -ne $StatusCode) {
            Add-Result "$ID-HTTP" "WARNING" $Path "HTTP $StatusCode : $($_.Exception.Message)"
        }
        else {
            Add-Result "$ID-HTTP" "BLOCKED" $Path "Acces impossible : $($_.Exception.Message)"
        }

        return [PSCustomObject]@{
            Path       = $Path
            StatusCode = $StatusCode
            ElapsedMs  = $null
            Body       = ""
        }
    }
}

# DEBUT
$StartTime = Get-Date
Write-Host ""
Write-Host "============================================================"
Write-Host " ENV-04 - APACHE DOCUMENTROOT CORRECTION"
Write-Host "============================================================"
Write-Host ""
Write-Host "Projet cible : $ProjectRoot"
Write-Host "DocumentRoot : $TargetDocumentRoot"
Write-Host "URL : $BaseUrl"
Write-Host ""

# 01 - PROJET
if (Test-Path $ProjectRoot) {
    Add-Result "ENV-04-01" "PASS" "Projet" "Repertoire projet trouve"
}
else {
    Add-Result "ENV-04-01" "BLOCKED" "Projet" "Repertoire projet introuvable"
    exit
}

# 02 - APACHE
$ApacheProcesses = Get-Process -Name "httpd" -ErrorAction SilentlyContinue
if ($ApacheProcesses) {
    Add-Result "ENV-04-02" "PASS" "Apache" "$($ApacheProcesses.Count) processus httpd detecte(s)"
}
else {
    Add-Result "ENV-04-02" "WARNING" "Apache" "Aucun processus httpd detecte"
}

# 03 - HTTPD.EXE
$HttpdExe = Find-HttpdExecutable
if ($HttpdExe) {
    Add-Result "ENV-04-03" "PASS" "httpd.exe" "Executable : $HttpdExe"
}
else {
    Add-Result "ENV-04-03" "BLOCKED" "httpd.exe" "Executable Apache introuvable"
    exit
}

# 04 - VERSION APACHE
try {
    $VersionOutput = & $HttpdExe -v 2>&1
    $VersionLine = ($VersionOutput | Where-Object { $_ -match "Server version" } | Select-Object -First 1)
    if ($VersionLine) {
        Add-Result "ENV-04-04" "PASS" "Version Apache" $VersionLine
    }
    else {
        Add-Result "ENV-04-04" "WARNING" "Version Apache" "Version non determinee"
    }
}
catch {
    Add-Result "ENV-04-04" "WARNING" "Version Apache" $_.Exception.Message
}

# 05 - CONFIGURATION ACTIVE
$HttpdConfig = Find-ApacheConfig $HttpdExe
if ($HttpdConfig) {
    Add-Result "ENV-04-05" "PASS" "httpd.conf" "Configuration detectee : $HttpdConfig"
}
else {
    Add-Result "ENV-04-05" "BLOCKED" "httpd.conf" "Impossible de determiner le fichier httpd.conf"
    exit
}

# 06 - LECTURE CONFIG
try {
    $ConfigContent = Get-Content -Path $HttpdConfig -Raw -ErrorAction Stop
    Add-Result "ENV-04-06" "PASS" "Lecture httpd.conf" "Configuration lisible"
}
catch {
    Add-Result "ENV-04-06" "BLOCKED" "Lecture httpd.conf" $_.Exception.Message
    exit
}

# 07 - DOCUMENTROOT ACTUEL
$DocumentRootMatches = [regex]::Matches($ConfigContent, '(?im)^\sDocumentRoot\s+"?([^"\r\n]+)"?\s$')
if ($DocumentRootMatches.Count -gt 0) {
    $CurrentDocumentRoot = $DocumentRootMatches[0].Groups[1].Value.Trim()
    Add-Result "ENV-04-07" "PASS" "DocumentRoot actuel" $CurrentDocumentRoot
}
else {
    $CurrentDocumentRoot = $null
    Add-Result "ENV-04-07" "WARNING" "DocumentRoot actuel" "Aucun DocumentRoot actif trouve dans httpd.conf"
}

# 08 - VERIFICATION BLOC DIRECTORY
$DirectoryPattern = '(?is)<Directory\s+"?' + [regex]::Escape($TargetDocumentRoot) + '"?\s*>.*?'
$DirectoryMatch = [regex]::Match($ConfigContent, $DirectoryPattern)
if ($DirectoryMatch.Success) {
    Add-Result "ENV-04-08" "PASS" "Bloc Directory" "Bloc <Directory> deja present pour le projet"
}
else {
    Add-Result "ENV-04-08" "WARNING" "Bloc Directory" "Bloc <Directory> absent pour le projet"
}

# 09 - VERIFICATION CONFIG AVANT MODIFICATION
try {
    $SyntaxBefore = & $HttpdExe -t -f $HttpdConfig 2>&1
    $SyntaxBeforeText = $SyntaxBefore -join "`n"
    if ($LASTEXITCODE -eq 0) {
        Add-Result "ENV-04-09" "PASS" "Syntaxe Apache avant correction" $SyntaxBeforeText.Trim()
    }
    else {
        Add-Result "ENV-04-09" "BLOCKED" "Syntaxe Apache avant correction" $SyntaxBeforeText.Trim()
        exit
    }
}
catch {
    Add-Result "ENV-04-09" "BLOCKED" "Syntaxe Apache avant correction" $_.Exception.Message
    exit
}

# 10 - SAUVEGARDE
$BackupFile = Join-Path $BackupDir "httpd.conf.$Timestamp.bak"
try {
    Copy-Item -Path $HttpdConfig -Destination $BackupFile -Force -ErrorAction Stop
    Add-Result "ENV-04-10" "PASS" "Sauvegarde Apache" "Sauvegarde creee : $BackupFile"
}
catch {
    Add-Result "ENV-04-10" "BLOCKED" "Sauvegarde Apache" "Impossible de sauvegarder httpd.conf : $($_.Exception.Message)"
    exit
}

# 11 - PREPARATION NOUVELLE CONFIGURATION
$NewConfigContent = $ConfigContent

# DocumentRoot
$NewDocumentRootLine = 'DocumentRoot "' + $TargetDocumentRoot + '"'
if ($DocumentRootMatches.Count -gt 0) {
    $NewConfigContent = [regex]::Replace($NewConfigContent, '(?im)^\s*DocumentRoot\s+"?[^"\r\n]+"?\s*$', $NewDocumentRootLine, 1)
}
else {
    if ($NewConfigContent -match '(?im)^\s*ServerRoot\s+') {
        $NewConfigContent = [regex]::Replace($NewConfigContent, '(?im)^(\s*ServerRoot[^\r\n]*\r?\n)', "`$1$NewDocumentRootLine`r`n", 1)
    }
    else {
        $NewConfigContent = $NewDocumentRootLine + "`r`n" + $NewConfigContent
    }
}

# Bloc Directory
$DirectoryBlock = @"
<Directory "$TargetDocumentRoot">
Options Indexes FollowSymLinks
AllowOverride All
Require all granted

"@
$DirectoryPattern2 = '(?is)<Directory\s+"?' + [regex]::Escape($TargetDocumentRoot) + '"?\s*>.*?'
if ([regex]::IsMatch($NewConfigContent, $DirectoryPattern2)) {
    $NewConfigContent = [regex]::Replace($NewConfigContent, $DirectoryPattern2, $DirectoryBlock, 1)
}
else {
    $NewConfigContent = $NewConfigContent.TrimEnd() + "`r`n`r`n" + "# ENV-04 IMC-Clarodoro DocumentRoot" + "`r`n" + $DirectoryBlock + "`r`n"
}

# 12 - ECRITURE CONFIGURATION
try {
    Set-Content -Path $HttpdConfig -Value $NewConfigContent -Encoding UTF8 -ErrorAction Stop
    Add-Result "ENV-04-11" "PASS" "Modification httpd.conf" "DocumentRoot configure vers $TargetDocumentRoot"
}
catch {
    Add-Result "ENV-04-11" "BLOCKED" "Modification httpd.conf" $_.Exception.Message
    exit
}

# 13 - SYNTAXE APACHE APRES MODIFICATION
try {
    $SyntaxAfter = & $HttpdExe -t -f $HttpdConfig 2>&1
    $SyntaxAfterText = $SyntaxAfter -join "`n"
    if ($LASTEXITCODE -eq 0) {
        Add-Result "ENV-04-12" "PASS" "Syntaxe Apache apres correction" $SyntaxAfterText.Trim()
    }
    else {
        Add-Result "ENV-04-12" "BLOCKED" "Syntaxe Apache apres correction" $SyntaxAfterText.Trim()
        # RESTAURATION IMMEDIATE
        try {
            Copy-Item -Path $BackupFile -Destination $HttpdConfig -Force
            Add-Result "ENV-04-12-ROLLBACK" "PASS" "Rollback Apache" "Configuration restauree depuis la sauvegarde"
        }
        catch {
            Add-Result "ENV-04-12-ROLLBACK" "BLOCKED" "Rollback Apache" "Echec restauration : $($_.Exception.Message)"
        }
        exit
    }
}
catch {
    Add-Result "ENV-04-12" "BLOCKED" "Syntaxe Apache apres correction" $_.Exception.Message
    exit
}

# 14 - REDÉMARRAGE APACHE (AUTOMATIQUE)
Write-Host ""
Write-Host "Redemarrage automatique d'Apache..."
Write-Host ""

$ApacheServices = Get-Service | Where-Object { $_.Name -match 'apache|httpd' -or $_.DisplayName -match 'apache|httpd' }
$Restarted = $false

if ($ApacheServices) {
    foreach ($Service in $ApacheServices) {
        try {
            Restart-Service -Name $Service.Name -Force -ErrorAction Stop
            Start-Sleep -Seconds 3
            Add-Result "ENV-04-13" "PASS" "Redemarrage Apache" "Service $($Service.Name) redemarre"
            $Restarted = $true
            break
        }
        catch {
            continue
        }
    }
}

if (-not $Restarted) {
    try {
        $RestartOutput = & $HttpdExe -k restart -f $HttpdConfig 2>&1
        if ($LASTEXITCODE -eq 0) {
            Add-Result "ENV-04-13" "PASS" "Redemarrage Apache" "httpd -k restart execute avec succes"
            $Restarted = $true
        }
        else {
            Add-Result "ENV-04-13" "BLOCKED" "Redemarrage Apache" ($RestartOutput -join " ")
        }
    }
    catch {
        Add-Result "ENV-04-13" "BLOCKED" "Redemarrage Apache" $_.Exception.Message
    }
}

Start-Sleep -Seconds 3

# Vérification processus
$ApacheAfter = Get-Process -Name "httpd" -ErrorAction SilentlyContinue
if ($ApacheAfter) {
    Add-Result "ENV-04-14" "PASS" "Apache apres redemarrage" "$($ApacheAfter.Count) processus httpd actifs"
}
else {
    Add-Result "ENV-04-14" "BLOCKED" "Apache apres redemarrage" "Aucun processus httpd actif apres redemarrage"
}

# 15 - PORT 8080 APRÈS CORRECTION
$Port8080 = Get-NetTCPConnection -LocalPort 8080 -State Listen -ErrorAction SilentlyContinue
if ($Port8080) {
    Add-Result "ENV-04-15" "PASS" "Port 8080" "Port 8080 en ecoute apres correction"
}
else {
    Add-Result "ENV-04-15" "BLOCKED" "Port 8080" "Port 8080 non disponible apres correction"
}

# 16 - TEST ENDPOINTS ARCH-01 APRÈS CORRECTION
Write-Host ""
Write-Host "============================================================"
Write-Host " VALIDATION HTTP APRÈS CORRECTION"
Write-Host "============================================================"
Write-Host ""

$HttpResults = @()
$HttpResults += Test-Endpoint "ARCH-01-A" "/api/health.php"
$HttpResults += Test-Endpoint "ARCH-01-B" "/api/index.php"
$HttpResults += Test-Endpoint "ARCH-01-C" "/api/health-db.php"

# 17 - VÉRIFICATION DOCUMENTROOT RÉEL
try {
    $RootResponse = Invoke-WebRequest -Uri "$BaseUrl/" -Method GET -UseBasicParsing -TimeoutSec 10 -ErrorAction Stop
    if ($RootResponse.StatusCode -eq 200) {
        Add-Result "ENV-04-16" "PASS" "HTTP racine" "GET / -> HTTP 200"
    }
    else {
        Add-Result "ENV-04-16" "WARNING" "HTTP racine" "GET / -> HTTP $($RootResponse.StatusCode)"
    }
}
catch {
    Add-Result "ENV-04-16" "WARNING" "HTTP racine" "Impossible de verifier / : $($_.Exception.Message)"
}

# 18 - VALIDATION PHYSIQUE DES ENDPOINTS
$RequiredFiles = @("api\health.php", "api\index.php", "api\health-db.php")
foreach ($RelativeFile in $RequiredFiles) {
    $PhysicalPath = Join-Path $ProjectRoot $RelativeFile
    if (Test-Path $PhysicalPath) {
        Add-Result "ENV-04-FILE-$($RelativeFile.Replace('\','-'))" "PASS" "Fichier API" "$RelativeFile present"
    }
    else {
        Add-Result "ENV-04-FILE-$($RelativeFile.Replace('\','-'))" "BLOCKED" "Fichier API" "$RelativeFile absent"
    }
}

# 19 - VÉRIFICATION AUCUNE MODIFICATION POSTGRESQL
Add-Result "ENV-04-17" "PASS" "PostgreSQL" "Aucune operation PostgreSQL executee par ENV-04"

# 20 - RAPPORT
$EndTime = Get-Date
$Duration = $EndTime - $StartTime
$PassCount = ($Results | Where-Object { $_.Status -eq "PASS" }).Count
$WarningCount = ($Results | Where-Object { $_.Status -eq "WARNING" }).Count
$BlockedCount = ($Results | Where-Object { $_.Status -eq "BLOCKED" }).Count

if ($BlockedCount -gt 0) {
    $GlobalStatus = "BLOCKED"
}
elseif ($WarningCount -gt 0) {
    $GlobalStatus = "PASS WITH WARNINGS"
}
else {
    $GlobalStatus = "PASS"
}

# RAPPORT MARKDOWN
$ResultLines = foreach ($Result in $Results) {
    $SafeDetails = $Result.Details -replace "\|","/" -replace "`r"," " -replace "`n"," "
    "| $($Result.ID) | $($Result.Status) | $($Result.Component) | $SafeDetails |"
}

$HttpEvidenceLines = foreach ($Item in $HttpResults) {
    $Preview = ""
    if ($Item.Body) {
        $Preview = $Item.Body.Trim()
        if ($Preview.Length -gt 300) {
            $Preview = $Preview.Substring(0,300) + "..."
        }
        $Preview = $Preview -replace '(?i)(password|passwd|pwd)\s*[:=]\s*["'']?[^"'',\s}]+', '$1=[REDACTED]'
        $Preview = $Preview.Replace("|","/").Replace("`r"," ").Replace("`n"," ")
    }
    "| $($Item.Path) | $($Item.StatusCode) | $($Item.ElapsedMs) | $Preview |"
}

$Report = @"
ENV-04 — APACHE DOCUMENTROOT CORRECTION
Rapport automatise
Projet : $ProjectRoot
DocumentRoot cible : $TargetDocumentRoot
URL : $BaseUrl
Date debut : $StartTime
Date fin : $EndTime
Duree : $($Duration.TotalSeconds.ToString("0.00")) secondes

1. VERDICT
$GlobalStatus

2. STATISTIQUES
| Statut | Nombre |
|--------|--------|
| PASS | $PassCount |
| WARNING | $WarningCount |
| BLOCKED | $BlockedCount |

3. CONFIGURATION APACHE
httpd.exe: $HttpdExe
httpd.conf: $HttpdConfig
DocumentRoot cible: $TargetDocumentRoot
Sauvegarde: $BackupFile

4. RESULTATS
| ID | Statut | Composant | Detail |
|----|--------|-----------|--------|
$($ResultLines -join "`r`n")

5. TESTS HTTP APRÈS CORRECTION
| Endpoint | HTTP | Temps ms | Reponse |
|----------|-----|---------|--------|
$($HttpEvidenceLines -join "`r`n")

6. GARANTIE DE NON-DESTRUCTIVITE
ENV-04 n'a cree aucune base, aucune table, ni modifie aucune donnee PostgreSQL.
La seule configuration modifiee est httpd.conf, apres sauvegarde et validation syntaxique.

7. RAPPORTS
Rapport automatique: $ReportFile
Rapport final: $ReportFinalFile
Sauvegarde Apache: $BackupFile
"@

Set-Content -Path $ReportFile -Value $Report -Encoding UTF8

# RAPPORT FINAL
$FinalReport = @"
ENV-04-APACHE-DOCUMENTROOT-CORRECTION — RAPPORT FINAL
IMC-Clarodoro
Date : $EndTime

VERDICT
$GlobalStatus

Statistiques
- PASS : $PassCount
- WARNING : $WarningCount
- BLOCKED : $BlockedCount

Configuration Apache
httpd.exe: $HttpdExe
httpd.conf: $HttpdConfig
DocumentRoot cible: $TargetDocumentRoot
Sauvegarde: $BackupFile

Resultats
$($ResultLines -join "`r`n")

Endpoints
$($HttpEvidenceLines -join "`r`n")

Integrite
Aucune modification PostgreSQL effectuee.
Aucune base imc_clarodoro creee.
Une sauvegarde Apache a ete cree avant modification.
La syntaxe Apache a ete controlee avant application.

Conclusion
ENV-04 avait pour objectif de corriger le DocumentRoot Apache.
Le verdict ci-dessus correspond uniquement aux controles reellement executes.

Fichiers
Rapport automatique: $ReportFile
Rapport final: $ReportFinalFile
Sauvegarde Apache: $BackupFile
"@

Set-Content -Path $ReportFinalFile -Value $FinalReport -Encoding UTF8

Write-Host ""
Write-Host "============================================================"
Write-Host " ENV-04 TERMINÉ"
Write-Host "============================================================"
Write-Host ""
Write-Host "VERDICT : $GlobalStatus"
Write-Host ""
Write-Host "PASS : $PassCount" -ForegroundColor Green
Write-Host "WARNING : $WarningCount" -ForegroundColor Yellow
Write-Host "BLOCKED : $BlockedCount" -ForegroundColor Red
Write-Host ""
Write-Host "httpd.exe : $HttpdExe"
Write-Host "httpd.conf : $HttpdConfig"
Write-Host "Backup : $BackupFile"
Write-Host ""
Write-Host "Rapport : $ReportFile"
Write-Host ""
Write-Host "PostgreSQL : aucune modification effectuee."
Write-Host ""
Write-Host "============================================================"
Write-Host " FIN DU SCRIPT"
Write-Host "============================================================"
