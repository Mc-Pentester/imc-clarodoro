Set-Location 'C:\imc-clarodoro'

Write-Host ''
Write-Host '==============================================' -ForegroundColor Cyan
Write-Host ' P0-A.2 — RUNTIME RBAC VALIDATION' -ForegroundColor Cyan
Write-Host '==============================================' -ForegroundColor Cyan
Write-Host ''

# ------------------------------------------------------------
# 1. PostgreSQL environment
# ------------------------------------------------------------

$env:DB_HOST = '127.0.0.1'
$env:DB_PORT = '5432'
$env:DB_NAME = 'imc_clarodoro'
$env:DB_USER = 'postgres'

if (-not $env:DB_PASSWORD) {
    Write-Error "DB_PASSWORD doit être défini dans la session PowerShell."
    exit 1
}

if (-not $env:PDG_PASSWORD) {
    Write-Error "PDG_PASSWORD doit être défini dans la session PowerShell."
    exit 1
}

# ------------------------------------------------------------
# 2. Vérifier PostgreSQL
# ------------------------------------------------------------

Write-Host ''
Write-Host '[1/6] Vérification PostgreSQL...' -ForegroundColor Yellow

& "C:\Program Files\PostgreSQL\18\bin\psql.exe" `
    -h 127.0.0.1 `
    -p 5432 `
    -U postgres `
    -d imc_clarodoro `
    -c "SELECT current_database(), current_user;" 2>&1 | Out-Null

if ($LASTEXITCODE -ne 0) {
    throw 'Connexion PostgreSQL échouée.'
}

Write-Host 'PASS — PostgreSQL accessible.' -ForegroundColor Green

# ------------------------------------------------------------
# 3. Vérifier serveur PHP
# ------------------------------------------------------------

Write-Host ''
Write-Host '[2/6] Vérification serveur PHP...' -ForegroundColor Yellow

try {
    $health = Invoke-WebRequest `
        -Uri 'http://127.0.0.1:8090/api/health.php' `
        -UseBasicParsing `
        -ErrorAction Stop

    Write-Host "PASS — HTTP $($health.StatusCode)" -ForegroundColor Green
}
catch {
    throw 'Serveur PHP non accessible sur http://127.0.0.1:8090'
}

# ------------------------------------------------------------
# 4. Test 401 sans session
# ------------------------------------------------------------

Write-Host ''
Write-Host '[3/6] Test 401 sans session...' -ForegroundColor Yellow

try {
    Invoke-WebRequest `
        -Uri 'http://127.0.0.1:8090/api/auth/permission-test.php' `
        -WebSession (
            New-Object Microsoft.PowerShell.Commands.WebRequestSession
        ) `
        -UseBasicParsing `
        -ErrorAction Stop | Out-Null

    throw 'ERREUR : permission-test a accepté une requête non authentifiée.'
}
catch {
    if ($_.Exception.Response.StatusCode.value__ -ne 401) {
        throw "ERREUR : statut inattendu pour requête non authentifiée."
    }
}

Write-Host 'PASS — permission-test retourne 401 sans session.' -ForegroundColor Green

# ------------------------------------------------------------
# 5. LOGIN PDG
# ------------------------------------------------------------

Write-Host ''
Write-Host '[4/6] Login PDG...' -ForegroundColor Yellow

$loginBody = @{
    username = 'pdg'
    password = $env:PDG_PASSWORD
} | ConvertTo-Json

$session = New-Object Microsoft.PowerShell.Commands.WebRequestSession

try {
    $login = Invoke-RestMethod `
        -Uri 'http://127.0.0.1:8090/api/auth/login.php' `
        -Method POST `
        -ContentType 'application/json' `
        -Body $loginBody `
        -WebSession $session
}
catch {
    throw 'Login PDG échoué.'
}

if (-not $login.success) {
    throw 'Login PDG : réponse success=false.'
}

Write-Host "PASS — Login PDG : $($login.user.username)" -ForegroundColor Green

# ------------------------------------------------------------
# 6. ME + permission-test + logout
# ------------------------------------------------------------

Write-Host ''
Write-Host '[5/6] Vérification session + RBAC...' -ForegroundColor Yellow

$me = Invoke-RestMethod `
    -Uri 'http://127.0.0.1:8090/api/auth/me.php' `
    -Method GET `
    -WebSession $session

if (-not $me.success) {
    throw 'ME échoué après login.'
}

Write-Host "PASS — ME : $($me.user.username) / $($me.user.role)" -ForegroundColor Green

$permission = Invoke-RestMethod `
    -Uri 'http://127.0.0.1:8090/api/auth/permission-test.php' `
    -Method GET `
    -WebSession $session

if (-not $permission.success) {
    throw 'permission-test échoué avec PDG.'
}

if ($permission.permission -ne 'eleves.read') {
    throw 'La permission testée n''est pas eleves.read.'
}

Write-Host 'PASS — PDG autorisé pour eleves.read.' -ForegroundColor Green

# ------------------------------------------------------------
# LOGOUT
# ------------------------------------------------------------

$logout = Invoke-RestMethod `
    -Uri 'http://127.0.0.1:8090/api/auth/logout.php' `
    -Method POST `
    -WebSession $session

if (-not $logout.success) {
    throw 'Logout échoué.'
}

Write-Host 'PASS — Logout.' -ForegroundColor Green

# ------------------------------------------------------------
# POST-LOGOUT 401
# ------------------------------------------------------------

try {
    Invoke-RestMethod `
        -Uri 'http://127.0.0.1:8090/api/auth/me.php' `
        -Method GET `
        -WebSession $session `
        -ErrorAction Stop

    throw 'ERREUR : ME reste accessible après logout.'
}
catch {
    if ($_.Exception.Response.StatusCode.value__ -ne 401) {
        throw 'ERREUR : ME ne retourne pas 401 après logout.'
    }
}

Write-Host 'PASS — ME retourne 401 après logout.' -ForegroundColor Green

Write-Host ''
Write-Host '[6/6] Nettoyage environnement...' -ForegroundColor Yellow

Remove-Item Env:DB_PASSWORD -ErrorAction SilentlyContinue
Remove-Item Env:PDG_PASSWORD -ErrorAction SilentlyContinue

Write-Host 'PASS — Mots de passe retirés de la session PowerShell.' -ForegroundColor Green

Write-Host ''
Write-Host '==============================================' -ForegroundColor Cyan
Write-Host ' P0-A.2 RUNTIME VALIDATION — PASS' -ForegroundColor Green
Write-Host '==============================================' -ForegroundColor Cyan
Write-Host ''
Write-Host 'Validé :' -ForegroundColor Green
Write-Host '  401 sans authentification'
Write-Host '  Login PDG'
Write-Host '  ME authentifié'
Write-Host '  RBAC eleves.read'
Write-Host '  Logout'
Write-Host '  401 après logout'
Write-Host ''
Write-Host 'Le seul test encore manquant est le 403 avec un rôle' -ForegroundColor Yellow
Write-Host 'ne possédant pas la permission eleves.create.' -ForegroundColor Yellow
Write-Host ''
