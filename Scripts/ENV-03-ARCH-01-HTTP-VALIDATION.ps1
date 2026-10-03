$ErrorActionPreference = "Continue"

# CONFIGURATION
$ProjectRoot = "C:\IMC-Clarodoro-securise-client\IMC-Clarodoro"
$BaseUrl = "http://localhost:8080"
$ReportDir = Join-Path $ProjectRoot "audit"
$ReportFile = Join-Path $ReportDir "ENV-03-ARCH-01-HTTP-VALIDATION-REPORT.md"
$ReportFinalFile = Join-Path $ReportDir "ENV-03-ARCH-01-HTTP-VALIDATION-REPORT-FINAL.md"

# Endpoints officiels ARCH-01
$Endpoints = @(
    @{
        ID = "ARCH-01-A"
        Name = "API Health"
        Path = "/api/health.php"
        File = "api\health.php"
    },
    @{
        ID = "ARCH-01-B"
        Name = "API Index"
        Path = "/api/index.php"
        File = "api\index.php"
    },
    @{
        ID = "ARCH-01-C"
        Name = "API Database Health"
        Path = "/api/health-db.php"
        File = "api\health-db.php"
    }
)

$Results = New-Object System.Collections.Generic.List[object]

# PREPARATION
New-Item -ItemType Directory -Force -Path $ReportDir | Out-Null
$StartTime = Get-Date

Write-Host ""
Write-Host "============================================================"
Write-Host " ENV-03 - ARCH-01 HTTP VALIDATION"
Write-Host " IMC-Clarodoro"
Write-Host "============================================================"
Write-Host ""
Write-Host "Projet : $ProjectRoot"
Write-Host "URL : $BaseUrl"
Write-Host ""

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

# FONCTION NORMALISATION REPONSE
function Get-SafeResponsePreview {
    param([string]$Body)

    if ([string]::IsNullOrWhiteSpace($Body)) {
        return "[EMPTY]"
    }

    $Preview = $Body.Trim()

    if ($Preview.Length -gt 500) {
        $Preview = $Preview.Substring(0,500) + "..."
    }

    # Eviter de publier des secrets evidents
    $Preview = $Preview -replace '(?i)(password|passwd|pwd)\s*[:=]\s*["'']?[^"'',\s}]+', '$1=[REDACTED]'
    $Preview = $Preview -replace '(?i)(token|secret|api[_-]?key)\s*[:=]\s*["'']?[^"'',\s}]+', '$1=[REDACTED]'

    return $Preview.Replace("`r"," ").Replace("`n"," ")
}

# FONCTION DETECTION ERREURS PHP
function Test-PhpErrorExposure {
    param([string]$Body)

    if ([string]::IsNullOrWhiteSpace($Body)) {
        return @()
    }

    $Patterns = @(
        "Fatal error",
        "Parse error",
        "Warning:",
        "Notice:",
        "Uncaught Error",
        "Uncaught Exception",
        "Stack trace:",
        "PDOException",
        "mysqli_sql_exception",
        "Call to undefined function",
        "Call to undefined method",
        "Undefined variable"
    )

    $Matches = New-Object System.Collections.Generic.List[string]

    foreach ($Pattern in $Patterns) {
        if ($Body -match [regex]::Escape($Pattern)) {
            $Matches.Add($Pattern)
        }
    }

    return $Matches
}

# FONCTION DETECTION SECRETS
function Test-SecretExposure {
    param([string]$Body)

    if ([string]::IsNullOrWhiteSpace($Body)) {
        return @()
    }

    $Patterns = @(
        "DB_PASSWORD",
        "DATABASE_PASSWORD",
        "password\s*=",
        "passwd\s*=",
        "api[_-]?key\s*=",
        "secret[_-]?key\s*=",
        "Authorization:\s*Bearer",
        "BEGIN PRIVATE KEY"
    )

    $Matches = New-Object System.Collections.Generic.List[string]

    foreach ($Pattern in $Patterns) {
        if ($Body -match $Pattern) {
            $Matches.Add($Pattern)
        }
    }

    return $Matches
}

# 01 - PROJET
if (Test-Path $ProjectRoot) {
    Add-Result "ENV-03-01" "PASS" "Projet" "Repertoire projet trouve : $ProjectRoot"
}
else {
    Add-Result "ENV-03-01" "BLOCKED" "Projet" "Repertoire projet introuvable : $ProjectRoot"
}

# 02 - APACHE / HTTPD
$ApacheProcesses = Get-Process -Name "httpd" -ErrorAction SilentlyContinue
if ($ApacheProcesses) {
    Add-Result "ENV-03-02" "PASS" "Apache" "$($ApacheProcesses.Count) processus httpd detecte(s)"
}
else {
    Add-Result "ENV-03-02" "WARNING" "Apache" "Aucun processus httpd detecte"
}

# 03 - PORT 8080
$Port8080 = Get-NetTCPConnection -LocalPort 8080 -State Listen -ErrorAction SilentlyContinue
if ($Port8080) {
    $Owners = @()
    foreach ($Connection in $Port8080) {
        $PidValue = $Connection.OwningProcess
        try {
            $Process = Get-Process -Id $PidValue -ErrorAction Stop
            $Owners += "$($Process.ProcessName) PID=$PidValue"
        }
        catch {
            $Owners += "PID=$PidValue"
        }
    }
    Add-Result "ENV-03-03" "PASS" "HTTP 8080" "Port 8080 en ecoute : $($Owners -join ', ')"
}
else {
    Add-Result "ENV-03-03" "BLOCKED" "HTTP 8080" "Aucun processus en ecoute sur le port 8080"
}

# 04 - TEST RACINE HTTP
$RootUrl = "$BaseUrl/"
$RootHttpStatus = $null
$RootResponseBody = $null
$RootElapsedMs = $null

try {
    $RootTimer = [System.Diagnostics.Stopwatch]::StartNew()
    $RootResponse = Invoke-WebRequest -Uri $RootUrl -Method GET -UseBasicParsing -TimeoutSec 10 -ErrorAction Stop
    $RootTimer.Stop()

    $RootHttpStatus = [int]$RootResponse.StatusCode
    $RootResponseBody = $RootResponse.Content
    $RootElapsedMs = $RootTimer.ElapsedMilliseconds

    if ($RootHttpStatus -ge 200 -and $RootHttpStatus -lt 400) {
        Add-Result "ENV-03-04" "PASS" "HTTP racine" "GET / -> HTTP $RootHttpStatus en ${RootElapsedMs}ms"
    }
    else {
        Add-Result "ENV-03-04" "WARNING" "HTTP racine" "GET / -> HTTP $RootHttpStatus en ${RootElapsedMs}ms"
    }
}
catch {
    $RootTimer.Stop()
    Add-Result "ENV-03-04" "BLOCKED" "HTTP racine" "Impossible d'acceder a $RootUrl : $($_.Exception.Message)"
}

# 05 - ENDPOINTS ARCH-01
$EndpointEvidence = New-Object System.Collections.Generic.List[object]

foreach ($Endpoint in $Endpoints) {
    Write-Host ""
    Write-Host "------------------------------------------------------------"
    Write-Host "$($Endpoint.ID) - $($Endpoint.Name)"
    Write-Host "------------------------------------------------------------"

    $EndpointUrl = "$BaseUrl$($Endpoint.Path)"
    $PhysicalFile = Join-Path $ProjectRoot $Endpoint.File

    # FICHIER PHYSIQUE
    if (Test-Path $PhysicalFile) {
        $FileInfo = Get-Item $PhysicalFile
        Add-Result "$($Endpoint.ID)-FILE" "PASS" "$($Endpoint.Name) - fichier" "Fichier present : $($Endpoint.File) ($($FileInfo.Length) octets)"
    }
    else {
        Add-Result "$($Endpoint.ID)-FILE" "BLOCKED" "$($Endpoint.Name) - fichier" "Fichier absent : $PhysicalFile"
    }

    # HTTP
    $HttpStatus = $null
    $ContentType = ""
    $Body = ""
    $ElapsedMs = $null
    $Headers = @{}

    try {
        $Timer = [System.Diagnostics.Stopwatch]::StartNew()
        $Response = Invoke-WebRequest -Uri $EndpointUrl -Method GET -UseBasicParsing -TimeoutSec 15 -ErrorAction Stop
        $Timer.Stop()

        $HttpStatus = [int]$Response.StatusCode
        $ContentType = [string]$Response.Headers["Content-Type"]
        $Body = [string]$Response.Content
        $ElapsedMs = $Timer.ElapsedMilliseconds
        $Headers = $Response.Headers

        $Preview = Get-SafeResponsePreview $Body

        $EndpointEvidence.Add(
            [PSCustomObject]@{
                ID          = $Endpoint.ID
                Name        = $Endpoint.Name
                Path        = $Endpoint.Path
                URL         = $EndpointUrl
                HTTPStatus  = $HttpStatus
                ContentType = $ContentType
                ElapsedMs   = $ElapsedMs
                BodyLength  = $Body.Length
                Preview     = $Preview
            }
        )

        # HTTP STATUS
        if ($HttpStatus -ge 200 -and $HttpStatus -lt 300) {
            Add-Result "$($Endpoint.ID)-HTTP" "PASS" "$($Endpoint.Name) - HTTP" "HTTP $HttpStatus en ${ElapsedMs}ms"
        }
        elseif ($HttpStatus -ge 300 -and $HttpStatus -lt 400) {
            Add-Result "$($Endpoint.ID)-HTTP" "WARNING" "$($Endpoint.Name) - HTTP" "HTTP $HttpStatus (redirection) en ${ElapsedMs}ms"
        }
        elseif ($HttpStatus -ge 400 -and $HttpStatus -lt 500) {
            Add-Result "$($Endpoint.ID)-HTTP" "WARNING" "$($Endpoint.Name) - HTTP" "HTTP $HttpStatus (erreur client) en ${ElapsedMs}ms"
        }
        else {
            Add-Result "$($Endpoint.ID)-HTTP" "BLOCKED" "$($Endpoint.Name) - HTTP" "HTTP $HttpStatus (erreur serveur) en ${ElapsedMs}ms"
        }

        # CONTENT TYPE
        if ([string]::IsNullOrWhiteSpace($ContentType)) {
            Add-Result "$($Endpoint.ID)-CONTENT" "WARNING" "$($Endpoint.Name) - Content-Type" "Content-Type absent"
        }
        else {
            Add-Result "$($Endpoint.ID)-CONTENT" "PASS" "$($Endpoint.Name) - Content-Type" $ContentType
        }

        # ERREURS PHP
        $PhpErrors = Test-PhpErrorExposure $Body
        if ($PhpErrors.Count -eq 0) {
            Add-Result "$($Endpoint.ID)-PHP" "PASS" "$($Endpoint.Name) - erreurs PHP" "Aucune erreur PHP evidente detectee dans la reponse"
        }
        else {
            Add-Result "$($Endpoint.ID)-PHP" "WARNING" "$($Endpoint.Name) - erreurs PHP" "Motifs detectes : $($PhpErrors -join ', ')"
        }

        # SECRETS
        $Secrets = Test-SecretExposure $Body
        if ($Secrets.Count -eq 0) {
            Add-Result "$($Endpoint.ID)-SECRET" "PASS" "$($Endpoint.Name) - secrets" "Aucun motif evident de secret detecte"
        }
        else {
            Add-Result "$($Endpoint.ID)-SECRET" "WARNING" "$($Endpoint.Name) - secrets" "Motifs potentiellement sensibles detectes : $($Secrets -join ', ')"
        }

        # PERFORMANCE
        if ($ElapsedMs -le 2000) {
            Add-Result "$($Endpoint.ID)-TIME" "PASS" "$($Endpoint.Name) - temps" "${ElapsedMs}ms"
        }
        else {
            Add-Result "$($Endpoint.ID)-TIME" "WARNING" "$($Endpoint.Name) - temps" "${ElapsedMs}ms"
        }

        # APERCU REPONSE
        Add-Result "$($Endpoint.ID)-BODY" "PASS" "$($Endpoint.Name) - reponse" (Get-SafeResponsePreview $Body)
    }
    catch {
        $ExceptionMessage = $_.Exception.Message
        $StatusFromException = $null

        try {
            if ($_.Exception.Response) {
                $StatusFromException = [int]$_.Exception.Response.StatusCode
            }
        }
        catch {
            $StatusFromException = $null
        }

        if ($null -ne $StatusFromException) {
            Add-Result "$($Endpoint.ID)-HTTP" "WARNING" "$($Endpoint.Name) - HTTP" "HTTP $StatusFromException : $ExceptionMessage"
        }
        else {
            Add-Result "$($Endpoint.ID)-HTTP" "BLOCKED" "$($Endpoint.Name) - HTTP" "Endpoint inaccessible : $ExceptionMessage"
        }

        $EndpointEvidence.Add(
            [PSCustomObject]@{
                ID          = $Endpoint.ID
                Name        = $Endpoint.Name
                Path        = $Endpoint.Path
                URL         = $EndpointUrl
                HTTPStatus  = $StatusFromException
                ContentType = ""
                ElapsedMs   = $null
                BodyLength  = 0
                Preview     = "[REQUEST FAILED]"
            }
        )
    }
}

# 06 - VERIFICATION API INDEX / ROUTING
$IndexEndpoint = $EndpointEvidence | Where-Object { $_.ID -eq "ARCH-01-B" }
if ($IndexEndpoint) {
    if ($IndexEndpoint.HTTPStatus -ge 200 -and $IndexEndpoint.HTTPStatus -lt 300) {
        Add-Result "ARCH-01-ROUTING" "PASS" "Routage API" "/api/index.php accessible"
    }
    else {
        Add-Result "ARCH-01-ROUTING" "WARNING" "Routage API" "/api/index.php repond HTTP $($IndexEndpoint.HTTPStatus)"
    }
}
else {
    Add-Result "ARCH-01-ROUTING" "BLOCKED" "Routage API" "Aucune preuve de /api/index.php"
}

# 07 - VERIFICATION HEALTH DB
$HealthDbEndpoint = $EndpointEvidence | Where-Object { $_.ID -eq "ARCH-01-C" }
if ($HealthDbEndpoint) {
    if ($HealthDbEndpoint.HTTPStatus -ge 200 -and $HealthDbEndpoint.HTTPStatus -lt 300) {
        Add-Result "ARCH-01-DB-HTTP" "PASS" "Health DB HTTP" "/api/health-db.php repond HTTP $($HealthDbEndpoint.HTTPStatus)"
    }
    elseif ($HealthDbEndpoint.HTTPStatus -ge 500) {
        Add-Result "ARCH-01-DB-HTTP" "WARNING" "Health DB HTTP" "/api/health-db.php est expose mais renvoie HTTP $($HealthDbEndpoint.HTTPStatus). Cela doit etre analyse separement de la disponibilite HTTP."
    }
    else {
        Add-Result "ARCH-01-DB-HTTP" "WARNING" "Health DB HTTP" "/api/health-db.php repond HTTP $($HealthDbEndpoint.HTTPStatus)"
    }
}
else {
    Add-Result "ARCH-01-DB-HTTP" "BLOCKED" "Health DB HTTP" "Aucune preuve de /api/health-db.php"
}

# 08 - TEST HTTP HEAD / OPTIONS
try {
    $OptionsResponse = Invoke-WebRequest -Uri "$BaseUrl/api/health.php" -Method HEAD -UseBasicParsing -TimeoutSec 10 -ErrorAction Stop
    Add-Result "ARCH-01-HEAD" "PASS" "HTTP HEAD" "/api/health.php accepte HEAD avec HTTP $($OptionsResponse.StatusCode)"
}
catch {
    Add-Result "ARCH-01-HEAD" "WARNING" "HTTP HEAD" "HEAD non supporte ou non expose : $($_.Exception.Message)"
}

# 09 - SECURITE BASIQUE DES REPONSES
$AllBodies = @()
foreach ($Evidence in $EndpointEvidence) {
    if ($Evidence.Preview -and $Evidence.Preview -ne "[REQUEST FAILED]") {
        $AllBodies += $Evidence.Preview
    }
}

$CombinedPreview = $AllBodies -join "`n"
$GlobalSecretPatterns = @("DB_PASSWORD", "DATABASE_PASSWORD", "BEGIN PRIVATE KEY")
$GlobalSecrets = @()

foreach ($Pattern in $GlobalSecretPatterns) {
    if ($CombinedPreview -match $Pattern) {
        $GlobalSecrets += $Pattern
    }
}

if ($GlobalSecrets.Count -eq 0) {
    Add-Result "ARCH-01-SECURITY" "PASS" "Exposition secrets" "Aucun secret evident trouve dans les apercus HTTP"
}
else {
    Add-Result "ARCH-01-SECURITY" "WARNING" "Exposition secrets" "Motifs detectes : $($GlobalSecrets -join ', ')"
}

# 10 - RAPPORT
$EndTime = Get-Date
$Duration = $EndTime - $StartTime
$PassCount = ($Results | Where-Object { $_.Status -eq "PASS" }).Count
$WarningCount = ($Results | Where-Object { $_.Status -eq "WARNING" }).Count
$BlockedCount = ($Results | Where-Object { $_.Status -eq "BLOCKED" }).Count

# VERDICT
if ($BlockedCount -gt 0) {
    $GlobalStatus = "BLOCKED"
}
elseif ($WarningCount -gt 0) {
    $GlobalStatus = "PASS WITH WARNINGS"
}
else {
    $GlobalStatus = "PASS"
}

# LIGNES RESULTATS
$ResultLines = foreach ($Result in $Results) {
    $SafeDetails = $Result.Details -replace "\|","/" -replace "`r"," " -replace "`n"," "
    "| $($Result.ID) | $($Result.Status) | $($Result.Component) | $SafeDetails |"
}

# ENDPOINT EVIDENCE
$EndpointLines = foreach ($Evidence in $EndpointEvidence) {
    $SafePreview = $Evidence.Preview -replace "\|","/" -replace "`r"," " -replace "`n"," "
    "| $($Evidence.ID) | $($Evidence.Path) | $($Evidence.HTTPStatus) | $($Evidence.ContentType) | $($Evidence.ElapsedMs) | $($Evidence.BodyLength) | $SafePreview |"
}

# RAPPORT MARKDOWN
$Report = @"
ENV-03 — ARCH-01 HTTP VALIDATION
Rapport automatise
Projet : $ProjectRoot
Base URL : $BaseUrl
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

3. OBJECTIF
Validation de l'exposition HTTP de l'application IMC-Clarodoro
via Apache sur le port 8080.
Endpoints ARCH-01 :
- `/api/health.php`
- `/api/index.php`
- `/api/health-db.php`

4. GARANTIE DE NON-DESTRUCTIVITE
Cette intervention n'a effectue aucune operation destructive.
Elle n'a :
- cree aucune base PostgreSQL ;
- cree aucune table ;
- modifie aucune donnee ;
- supprime aucune donnee ;
- execute aucun INSERT ;
- execute aucun UPDATE ;
- execute aucun DELETE ;
- execute aucun POST metier ;
- demarre aucun service ;
- arrete aucun service ;
- modifie aucun fichier PHP ;
- modifie aucune configuration Apache.

Les requetes HTTP effectuees sont exclusivement des requetes de diagnostic.

5. RESULTATS DETAILLES
| ID | Statut | Composant | Detail |
|----|--------|-----------|--------|
$($ResultLines -join "`r`n")

6. PREUVES HTTP DES ENDPOINTS
| Endpoint | URL | HTTP | Content-Type | Temps ms | Taille | Apercu |
|----------|-----|-----|--------------|---------|-------|--------|
$($EndpointLines -join "`r`n")

7. INTERPRETATION
**PASS**
Le controle correspondant a ete demontre par le diagnostic.

**WARNING**
Le controle fonctionne partiellement ou presente un element necessitant une analyse complementaire.
Un WARNING ne signifie pas automatiquement que l'application est defaillante.

**BLOCKED**
Le controle n'a pas pu etre realise ou l'acces HTTP requis est indisponible.

8. IMPORTANT — HEALTH DB
La disponibilite HTTP de `/api/health-db.php` ne prouve pas necessairement que la connexion PHP -> PostgreSQL fonctionne.
Elle prouve seulement que l'endpoint est accessible si son code repond.
La connexion PostgreSQL doit etre consideree comme une preuve distincte.

9. PROCHAINE DECISION
Apres analyse de ce rapport, l'etape suivante pourra etre determinee parmi :
- correction HTTP/Apache ;
- correction du chargement de configuration DB ;
- validation PHP -> PostgreSQL ;
- preparation controlee de `imc_clarodoro` ;
- analyse du schema SQL existant ;
- validation ARCH-01 finale.

Aucune de ces operations n'a ete executee automatiquement par ce diagnostic.

10. SECURITE
Les reponses HTTP ont ete inspectees a la recherche de motifs evidents :
- mot de passe ;
- token ;
- secret ;
- cle API ;
- cle privee ;
- erreurs PHP ;
- traces d'exception.

Les valeurs potentiellement sensibles sont masquees dans les apercus du rapport lorsqu'elles sont detectees.

11. FICHIERS DE RAPPORT
Rapport automatique : $ReportFile
Rapport final : $ReportFinalFile
"@

Set-Content -Path $ReportFile -Value $Report -Encoding UTF8

# RAPPORT FINAL
$FinalReport = @"
ENV-03-ARCH-01 — RAPPORT FINAL
IMC-Clarodoro
Date : $EndTime

VERDICT
$GlobalStatus

Comptage
- PASS : $PassCount
- WARNING : $WarningCount
- BLOCKED : $BlockedCount

Objectif
Valider l'acces HTTP de l'application IMC-Clarodoro
via Apache sur : $BaseUrl

Endpoints :
- `/api/health.php`
- `/api/index.php`
- `/api/health-db.php`

Resultats
$($ResultLines -join "`r`n")

Preuves HTTP
$($EndpointLines -join "`r`n")

Integrite
Aucune base, table ou donnee PostgreSQL n'a ete modifiee.
Aucun fichier applicatif n'a ete modifie.
Aucun service n'a ete demarre ou arrete.
Aucun POST metier n'a ete execute.

Conclusion
Le verdict $GlobalStatus correspond exclusivement aux controles HTTP effectues pendant cette intervention.
La validation HTTP ne constitue pas a elle seule une preuve de connexion PHP -> PostgreSQL.
La base `imc_clarodoro` ne doit pas etre cree automatiquement par cette intervention.
La prochaine etape doit etre determinee a partir des resultats reels observes ci-dessus.

Rapport detaille
$ReportFile
"@

Set-Content -Path $ReportFinalFile -Value $FinalReport -Encoding UTF8

Write-Host ""
Write-Host "============================================================"
Write-Host " ENV-03 - DIAGNOSTIC TERMINE"
Write-Host "============================================================"
Write-Host ""
Write-Host "VERDICT : $GlobalStatus"
Write-Host ""
Write-Host "PASS : $PassCount" -ForegroundColor Green
Write-Host "WARNING : $WarningCount" -ForegroundColor Yellow
Write-Host "BLOCKED : $BlockedCount" -ForegroundColor Red
Write-Host ""
Write-Host "Rapport automatique :"
Write-Host $ReportFile
Write-Host ""
Write-Host "Rapport final :"
Write-Host $ReportFinalFile
Write-Host ""
Write-Host "Aucune modification applicative ou PostgreSQL n'a ete effectuee."
Write-Host ""
Write-Host "============================================================"
Write-Host " FIN DU SCRIPT"
Write-Host "============================================================"
