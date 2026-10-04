# P0-A.2 — RUNTIME RBAC VALIDATION
# Validation HTTP de l'authentification et RBAC

Set-Location 'C:\imc-clarodoro'

# ------------------------------------------------------------
# Configuration PostgreSQL
# ------------------------------------------------------------

$env:DB_HOST = '127.0.0.1'
$env:DB_PORT = '5432'
$env:DB_NAME = 'imc_clarodoro'
$env:DB_USER = 'postgres'

# ------------------------------------------------------------
# Vérification des variables d'environnement
# ------------------------------------------------------------

if (-not $env:DB_PASSWORD) {
    Write-Error "DB_PASSWORD doit être défini dans la session PowerShell."
    exit 1
}

if (-not $env:PDG_PASSWORD) {
    Write-Error "PDG_PASSWORD doit être défini dans la session PowerShell."
    exit 1
}

# ------------------------------------------------------------
# Variables de test
# ------------------------------------------------------------

$baseUrl = 'http://127.0.0.1:8090'
$results = @{}

# ------------------------------------------------------------
# Test 1: GET /api/auth/permission-test.php SANS session
# ------------------------------------------------------------

Write-Host 'Test 1: 401 permission-test sans session...' -ForegroundColor Yellow

try {
    $response = Invoke-WebRequest `
        -Uri "$baseUrl/api/auth/permission-test.php" `
        -UseBasicParsing `
        -ErrorAction Stop

    $results['401_permission-test_sans_session'] = 'FAIL'
    Write-Host 'FAIL: Devrait retourner 401' -ForegroundColor Red
}
catch {
    if ($_.Exception.Response.StatusCode.value__ -eq 401) {
        $results['401_permission-test_sans_session'] = 'PASS'
        Write-Host 'PASS' -ForegroundColor Green
    }
    else {
        $results['401_permission-test_sans_session'] = 'FAIL'
        Write-Host "FAIL: Statut inattendu $($_.Exception.Response.StatusCode.value__)" -ForegroundColor Red
    }
}

# ------------------------------------------------------------
# Test 2: GET /api/auth/me.php SANS session
# ------------------------------------------------------------

Write-Host 'Test 2: 401 me sans session...' -ForegroundColor Yellow

try {
    $response = Invoke-WebRequest `
        -Uri "$baseUrl/api/auth/me.php" `
        -UseBasicParsing `
        -ErrorAction Stop

    $results['401_me_sans_session'] = 'FAIL'
    Write-Host 'FAIL: Devrait retourner 401' -ForegroundColor Red
}
catch {
    if ($_.Exception.Response.StatusCode.value__ -eq 401) {
        $results['401_me_sans_session'] = 'PASS'
        Write-Host 'PASS' -ForegroundColor Green
    }
    else {
        $results['401_me_sans_session'] = 'FAIL'
        Write-Host "FAIL: Statut inattendu $($_.Exception.Response.StatusCode.value__)" -ForegroundColor Red
    }
}

# ------------------------------------------------------------
# Test 3: POST /api/auth/login.php
# ------------------------------------------------------------

Write-Host 'Test 3: LOGIN PDG...' -ForegroundColor Yellow

$loginBody = @{
    username = 'pdg'
    password = $env:PDG_PASSWORD
} | ConvertTo-Json

$session = New-Object Microsoft.PowerShell.Commands.WebRequestSession

try {
    $login = Invoke-RestMethod `
        -Uri "$baseUrl/api/auth/login.php" `
        -Method POST `
        -ContentType 'application/json' `
        -Body $loginBody `
        -WebSession $session `
        -ErrorAction Stop

    if ($login.success -and $login.user.username -eq 'pdg') {
        $results['LOGIN_PDG'] = 'PASS'
        Write-Host "PASS: $($login.user.username)" -ForegroundColor Green
    }
    else {
        $results['LOGIN_PDG'] = 'FAIL'
        Write-Host 'FAIL: Login échoué' -ForegroundColor Red
    }
}
catch {
    $results['LOGIN_PDG'] = 'FAIL'
    Write-Host "FAIL: $($_.Exception.Message)" -ForegroundColor Red
}

# ------------------------------------------------------------
# Test 4: GET /api/auth/me.php avec session
# ------------------------------------------------------------

Write-Host 'Test 4: ME authentifié...' -ForegroundColor Yellow

try {
    $me = Invoke-RestMethod `
        -Uri "$baseUrl/api/auth/me.php" `
        -Method GET `
        -WebSession $session `
        -ErrorAction Stop

    if ($me.success -and $me.user.username -eq 'pdg' -and $me.user.role -eq 'PDG') {
        $results['ME_authentifie'] = 'PASS'
        Write-Host "PASS: $($me.user.username) / $($me.user.role)" -ForegroundColor Green
    }
    else {
        $results['ME_authentifie'] = 'FAIL'
        Write-Host 'FAIL: Données incorrectes' -ForegroundColor Red
    }
}
catch {
    $results['ME_authentifie'] = 'FAIL'
    Write-Host "FAIL: $($_.Exception.Message)" -ForegroundColor Red
}

# ------------------------------------------------------------
# Test 5: GET /api/auth/permission-test.php avec session PDG
# ------------------------------------------------------------

Write-Host 'Test 5: RBAC eleves.read...' -ForegroundColor Yellow

try {
    $permission = Invoke-RestMethod `
        -Uri "$baseUrl/api/auth/permission-test.php" `
        -Method GET `
        -WebSession $session `
        -ErrorAction Stop

    if ($permission.success -and $permission.permission -eq 'eleves.read') {
        $results['RBAC_eleves_read'] = 'PASS'
        Write-Host 'PASS: PDG autorisé pour eleves.read' -ForegroundColor Green
    }
    else {
        $results['RBAC_eleves_read'] = 'FAIL'
        Write-Host 'FAIL: Permission incorrecte' -ForegroundColor Red
    }
}
catch {
    $results['RBAC_eleves_read'] = 'FAIL'
    Write-Host "FAIL: $($_.Exception.Message)" -ForegroundColor Red
}

# ------------------------------------------------------------
# Test 6: POST /api/auth/logout.php
# ------------------------------------------------------------

Write-Host 'Test 6: LOGOUT...' -ForegroundColor Yellow

try {
    $logout = Invoke-RestMethod `
        -Uri "$baseUrl/api/auth/logout.php" `
        -Method POST `
        -WebSession $session `
        -ErrorAction Stop

    if ($logout.success) {
        $results['LOGOUT'] = 'PASS'
        Write-Host 'PASS' -ForegroundColor Green
    }
    else {
        $results['LOGOUT'] = 'FAIL'
        Write-Host 'FAIL: Logout échoué' -ForegroundColor Red
    }
}
catch {
    $results['LOGOUT'] = 'FAIL'
    Write-Host "FAIL: $($_.Exception.Message)" -ForegroundColor Red
}

# ------------------------------------------------------------
# Test 7: GET /api/auth/me.php après logout
# ------------------------------------------------------------

Write-Host 'Test 7: ME après logout...' -ForegroundColor Yellow

try {
    $response = Invoke-RestMethod `
        -Uri "$baseUrl/api/auth/me.php" `
        -Method GET `
        -WebSession $session `
        -ErrorAction Stop

    $results['ME_apres_logout'] = 'FAIL'
    Write-Host 'FAIL: Devrait retourner 401' -ForegroundColor Red
}
catch {
    if ($_.Exception.Response.StatusCode.value__ -eq 401) {
        $results['ME_apres_logout'] = 'PASS'
        Write-Host 'PASS' -ForegroundColor Green
    }
    else {
        $results['ME_apres_logout'] = 'FAIL'
        Write-Host "FAIL: Statut inattendu $($_.Exception.Response.StatusCode.value__)" -ForegroundColor Red
    }
}

# ------------------------------------------------------------
# Nettoyage
# ------------------------------------------------------------

Remove-Item Env:DB_PASSWORD -ErrorAction SilentlyContinue
Remove-Item Env:PDG_PASSWORD -ErrorAction SilentlyContinue

# ------------------------------------------------------------
# Affichage du résumé
# ------------------------------------------------------------

Write-Host ''
Write-Host '==============================================' -ForegroundColor Cyan
Write-Host ' P0-A.2 — RUNTIME RBAC VALIDATION' -ForegroundColor Cyan
Write-Host '==============================================' -ForegroundColor Cyan
Write-Host ''

Write-Host "401 permission-test sans session : $($results['401_permission-test_sans_session'])" -ForegroundColor White
Write-Host "401 me sans session              : $($results['401_me_sans_session'])" -ForegroundColor White
Write-Host "LOGIN PDG                        : $($results['LOGIN_PDG'])" -ForegroundColor White
Write-Host "ME authentifié                   : $($results['ME_authentifie'])" -ForegroundColor White
Write-Host "RBAC eleves.read                 : $($results['RBAC_eleves_read'])" -ForegroundColor White
Write-Host "LOGOUT                           : $($results['LOGOUT'])" -ForegroundColor White
Write-Host "ME après logout                  : $($results['ME_apres_logout'])" -ForegroundColor White

Write-Host ''

$allPassed = $results.Values -eq 'PASS' -notcontains $false

if ($allPassed) {
    Write-Host 'RESULT : PASS' -ForegroundColor Green
    exit 0
}
else {
    Write-Host 'RESULT : FAIL' -ForegroundColor Red
    exit 1
}
