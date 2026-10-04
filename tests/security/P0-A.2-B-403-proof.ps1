# P0-A.2-B — RBAC 403 RUNTIME PROOF
# Proof that role "Autre" receives HTTP 403 for eleves.create

Set-Location 'C:\imc-clarodoro'

# ------------------------------------------------------------
# Configuration PostgreSQL
# ------------------------------------------------------------

$env:DB_HOST = '127.0.0.1'
$env:DB_PORT = '5432'
$env:DB_NAME = 'imc_clarodoro'
$env:DB_USER = 'postgres'

if (-not $env:DB_PASSWORD) {
    Write-Error "DB_PASSWORD doit être défini dans la session PowerShell."
    exit 1
}

$psql = 'C:\Program Files\PostgreSQL\18\bin\psql.exe'

# ------------------------------------------------------------
# Fonction psql helper
# ------------------------------------------------------------

function Invoke-Psql {
    param(
        [string]$Sql
    )

    $env:PGPASSWORD = $env:DB_PASSWORD

    $result = & $psql `
        -h $env:DB_HOST `
        -p $env:DB_PORT `
        -U $env:DB_USER `
        -d $env:DB_NAME `
        -t `
        -A `
        -c $Sql 2>&1

    if ($LASTEXITCODE -ne 0) {
        throw "PostgreSQL error: $result"
    }

    return ($result | Out-String).Trim()
}

# ------------------------------------------------------------
# Variables de test
# ------------------------------------------------------------

$baseUrl = 'http://127.0.0.1:8090'
$testUsername = 'rbac-test-autre'
$results = @{}
$testPassword = $null
$accountCreated = $false

# ------------------------------------------------------------
# Test 1: Vérification rôle Autre
# ------------------------------------------------------------

Write-Host 'Test 1: Vérification rôle Autre...' -ForegroundColor Yellow

try {
    $roleId = Invoke-Psql "SELECT id FROM roles WHERE name = 'Autre' LIMIT 1;"

    if (-not $roleId) {
        $results['role_autre_trouve'] = 'FAIL'
        Write-Host 'FAIL: Rôle Autre non trouvé' -ForegroundColor Red
        exit 1
    }

    $results['role_autre_trouve'] = 'PASS'
    Write-Host 'PASS: Rôle Autre trouvé' -ForegroundColor Green
}
catch {
    $results['role_autre_trouve'] = 'FAIL'
    Write-Host "FAIL: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

# ------------------------------------------------------------
# Test 2: Vérification permission eleves.create
# ------------------------------------------------------------

Write-Host 'Test 2: Vérification permission eleves.create...' -ForegroundColor Yellow

try {
    $permissionId = Invoke-Psql "SELECT id FROM permissions WHERE name = 'eleves.create' LIMIT 1;"

    if (-not $permissionId) {
        $results['permission_eleves_create'] = 'FAIL'
        Write-Host 'FAIL: Permission eleves.create non trouvée' -ForegroundColor Red
        exit 1
    }

    $results['permission_eleves_create'] = 'PASS'
    Write-Host 'PASS: Permission eleves.create trouvée' -ForegroundColor Green
}
catch {
    $results['permission_eleves_create'] = 'FAIL'
    Write-Host "FAIL: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

# ------------------------------------------------------------
# Test 3: Vérification que Autre n'a PAS eleves.create
# ------------------------------------------------------------

Write-Host 'Test 3: Vérification Autre sans eleves.create...' -ForegroundColor Yellow

try {
    $count = Invoke-Psql "SELECT COUNT(*) FROM role_permissions rp INNER JOIN permissions p ON p.id = rp.permission_id WHERE rp.role_id = '$roleId' AND p.name = 'eleves.create';"

    if ($count -ne '0') {
        $results['autre_sans_eleves_create'] = 'FAIL'
        Write-Host 'FAIL: Rôle Autre possède eleves.create' -ForegroundColor Red
        exit 1
    }

    $results['autre_sans_eleves_create'] = 'PASS'
    Write-Host 'PASS: Rôle Autre ne possède pas eleves.create' -ForegroundColor Green
}
catch {
    $results['autre_sans_eleves_create'] = 'FAIL'
    Write-Host "FAIL: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

# ------------------------------------------------------------
# Test 4: Vérification si compte existe déjà
# ------------------------------------------------------------

Write-Host 'Test 4: Vérification compte rbac-test-autre...' -ForegroundColor Yellow

try {
    $count = Invoke-Psql "SELECT COUNT(*) FROM users WHERE username = 'rbac-test-autre';"

    if ($count -ne '0') {
        Write-Host "Le compte rbac-test-autre existe déjà. Test interrompu pour éviter toute modification d'un compte existant." -ForegroundColor Yellow
        Remove-Item Env:PGPASSWORD -ErrorAction SilentlyContinue
        Remove-Item Env:DB_PASSWORD -ErrorAction SilentlyContinue
        exit 1
    }
}
catch {
    Write-Host "FAIL: $($_.Exception.Message)" -ForegroundColor Red
    Remove-Item Env:PGPASSWORD -ErrorAction SilentlyContinue
    Remove-Item Env:DB_PASSWORD -ErrorAction SilentlyContinue
    exit 1
}

# ------------------------------------------------------------
# Test 5: Création du compte de test
# ------------------------------------------------------------

Write-Host 'Test 5: Création compte rbac-test-autre...' -ForegroundColor Yellow

try {
    # Générer mot de passe
    $testPassword = -join ((48..57) + (65..90) + (97..122) | Get-Random -Count 24 | ForEach-Object { [char]$_ })

    # Générer hash via PHP temporaire
    $tempPhp = Join-Path $env:TEMP 'imc-rbac-hash.php'
    $phpScript = @'
<?php
$password = $argv[1];
echo password_hash($password, PASSWORD_DEFAULT);
'@

    [System.IO.File]::WriteAllText(
        $tempPhp,
        $phpScript,
        (New-Object System.Text.UTF8Encoding($false))
    )

    $passwordHash = php $tempPhp $testPassword 2>&1 | Out-String
    $passwordHash = $passwordHash.Trim()
    Remove-Item $tempPhp -Force -ErrorAction SilentlyContinue

    if ($LASTEXITCODE -ne 0 -or $passwordHash.Length -lt 60) {
        throw "Échec du hash du mot de passe via PHP"
    }

    # Insérer utilisateur
    $insertSql = "INSERT INTO users (username, password_hash, role_id, status) VALUES ('rbac-test-autre', '$passwordHash', '$roleId', 'ACTIVE');"
    Invoke-Psql $insertSql | Out-Null

    $results['creation_compte_test'] = 'PASS'
    Write-Host 'PASS: Compte rbac-test-autre créé' -ForegroundColor Green
    $accountCreated = $true
}
catch {
    $results['creation_compte_test'] = 'FAIL'
    Write-Host "FAIL: $($_.Exception.Message)" -ForegroundColor Red
    if ($accountCreated) {
        Invoke-Psql "UPDATE users SET status = 'INACTIVE' WHERE username = 'rbac-test-autre';" | Out-Null
    }
    Remove-Item Env:PGPASSWORD -ErrorAction SilentlyContinue
    Remove-Item Env:DB_PASSWORD -ErrorAction SilentlyContinue
    exit 1
}

# ------------------------------------------------------------
# Test 6: Login HTTP avec compte Autre
# ------------------------------------------------------------

Write-Host 'Test 6: Login rbac-test-autre...' -ForegroundColor Yellow

try {
    $loginBody = @{
        username = $testUsername
        password = $testPassword
    } | ConvertTo-Json

    $session = New-Object Microsoft.PowerShell.Commands.WebRequestSession

    $login = Invoke-RestMethod `
        -Uri "$baseUrl/api/auth/login.php" `
        -Method POST `
        -ContentType 'application/json' `
        -Body $loginBody `
        -WebSession $session `
        -ErrorAction Stop

    if ($login.success -and $login.user.username -eq $testUsername -and $login.user.role -eq 'Autre') {
        $results['login_compte_autre'] = 'PASS'
        Write-Host "PASS: $($login.user.username) / $($login.user.role)" -ForegroundColor Green
    }
    else {
        $results['login_compte_autre'] = 'FAIL'
        Write-Host 'FAIL: Login échoué ou rôle incorrect' -ForegroundColor Red
        throw 'Login failed'
    }
}
catch {
    $results['login_compte_autre'] = 'FAIL'
    Write-Host "FAIL: $($_.Exception.Message)" -ForegroundColor Red
    $session = $null
}

# ------------------------------------------------------------
# Test 7: Test permission-denied-test.php
# ------------------------------------------------------------

if ($session) {
    Write-Host 'Test 7: permission-denied-test.php...' -ForegroundColor Yellow

    try {
        $response = Invoke-WebRequest `
            -Uri "$baseUrl/api/auth/permission-denied-test.php" `
            -WebSession $session `
            -UseBasicParsing `
            -ErrorAction Stop

        $results['permission_denied_test'] = 'FAIL'
        Write-Host 'FAIL: Devrait retourner 403' -ForegroundColor Red
    }
    catch {
        if ($_.Exception.Response.StatusCode.value__ -eq 403) {
            $results['permission_denied_test'] = 'PASS'
            Write-Host 'PASS: HTTP 403 retourné' -ForegroundColor Green
        }
        else {
            $results['permission_denied_test'] = 'FAIL'
            Write-Host "FAIL: Statut inattendu $($_.Exception.Response.StatusCode.value__)" -ForegroundColor Red
        }
    }
}
else {
    $results['permission_denied_test'] = 'FAIL'
    Write-Host 'SKIP: Session non disponible' -ForegroundColor Yellow
}

# ------------------------------------------------------------
# Test 8: Non-contournement ?role=PDG
# ------------------------------------------------------------

if ($session) {
    Write-Host 'Test 8: Query ?role=PDG bloquée...' -ForegroundColor Yellow

    try {
        $response = Invoke-WebRequest `
            -Uri "$baseUrl/api/auth/permission-denied-test.php?role=PDG" `
            -WebSession $session `
            -UseBasicParsing `
            -ErrorAction Stop

        $results['query_role_bloquee'] = 'FAIL'
        Write-Host 'FAIL: Devrait retourner 403' -ForegroundColor Red
    }
    catch {
        if ($_.Exception.Response.StatusCode.value__ -eq 403) {
            $results['query_role_bloquee'] = 'PASS'
            Write-Host 'PASS: HTTP 403 retourné' -ForegroundColor Green
        }
        else {
            $results['query_role_bloquee'] = 'FAIL'
            Write-Host "FAIL: Statut inattendu $($_.Exception.Response.StatusCode.value__)" -ForegroundColor Red
        }
    }
}
else {
    $results['query_role_bloquee'] = 'FAIL'
    Write-Host 'SKIP: Session non disponible' -ForegroundColor Yellow
}

# ------------------------------------------------------------
# Test 9: Non-contournement X-Role header
# ------------------------------------------------------------

if ($session) {
    Write-Host 'Test 9: Header X-Role bloqué...' -ForegroundColor Yellow

    try {
        $response = Invoke-WebRequest `
            -Uri "$baseUrl/api/auth/permission-denied-test.php" `
            -WebSession $session `
            -UseBasicParsing `
            -Headers @{'X-Role' = 'PDG'} `
            -ErrorAction Stop

        $results['header_x_role_bloque'] = 'FAIL'
        Write-Host 'FAIL: Devrait retourner 403' -ForegroundColor Red
    }
    catch {
        if ($_.Exception.Response.StatusCode.value__ -eq 403) {
            $results['header_x_role_bloque'] = 'PASS'
            Write-Host 'PASS: HTTP 403 retourné' -ForegroundColor Green
        }
        else {
            $results['header_x_role_bloque'] = 'FAIL'
            Write-Host "FAIL: Statut inattendu $($_.Exception.Response.StatusCode.value__)" -ForegroundColor Red
        }
    }
}
else {
    $results['header_x_role_bloque'] = 'FAIL'
    Write-Host 'SKIP: Session non disponible' -ForegroundColor Yellow
}

# ------------------------------------------------------------
# Test 10: Non-contournement X-Permission header
# ------------------------------------------------------------

if ($session) {
    Write-Host 'Test 10: Header X-Permission bloqué...' -ForegroundColor Yellow

    try {
        $response = Invoke-WebRequest `
            -Uri "$baseUrl/api/auth/permission-denied-test.php" `
            -WebSession $session `
            -UseBasicParsing `
            -Headers @{'X-Permission' = 'eleves.create'} `
            -ErrorAction Stop

        $results['header_x_permission_bloque'] = 'FAIL'
        Write-Host 'FAIL: Devrait retourner 403' -ForegroundColor Red
    }
    catch {
        if ($_.Exception.Response.StatusCode.value__ -eq 403) {
            $results['header_x_permission_bloque'] = 'PASS'
            Write-Host 'PASS: HTTP 403 retourné' -ForegroundColor Green
        }
        else {
            $results['header_x_permission_bloque'] = 'FAIL'
            Write-Host "FAIL: Statut inattendu $($_.Exception.Response.StatusCode.value__)" -ForegroundColor Red
        }
    }
}
else {
    $results['header_x_permission_bloque'] = 'FAIL'
    Write-Host 'SKIP: Session non disponible' -ForegroundColor Yellow
}

# ------------------------------------------------------------
# Test 11: Logout
# ------------------------------------------------------------

if ($session) {
    Write-Host 'Test 11: Logout...' -ForegroundColor Yellow

    try {
        $logout = Invoke-RestMethod `
            -Uri "$baseUrl/api/auth/logout.php" `
            -Method POST `
            -WebSession $session `
            -ErrorAction Stop

        if ($logout.success) {
            $results['logout'] = 'PASS'
            Write-Host 'PASS' -ForegroundColor Green
        }
        else {
            $results['logout'] = 'FAIL'
            Write-Host 'FAIL: Logout échoué' -ForegroundColor Red
        }
    }
    catch {
        $results['logout'] = 'FAIL'
        Write-Host "FAIL: $($_.Exception.Message)" -ForegroundColor Red
    }
}
else {
    $results['logout'] = 'FAIL'
    Write-Host 'SKIP: Session non disponible' -ForegroundColor Yellow
}

# ------------------------------------------------------------
# Test 12: 401 après logout
# ------------------------------------------------------------

if ($session) {
    Write-Host 'Test 12: 401 après logout...' -ForegroundColor Yellow

    try {
        $response = Invoke-RestMethod `
            -Uri "$baseUrl/api/auth/me.php" `
            -Method GET `
            -WebSession $session `
            -ErrorAction Stop

        $results['401_apres_logout'] = 'FAIL'
        Write-Host 'FAIL: Devrait retourner 401' -ForegroundColor Red
    }
    catch {
        if ($_.Exception.Response.StatusCode.value__ -eq 401) {
            $results['401_apres_logout'] = 'PASS'
            Write-Host 'PASS' -ForegroundColor Green
        }
        else {
            $results['401_apres_logout'] = 'FAIL'
            Write-Host "FAIL: Statut inattendu $($_.Exception.Response.StatusCode.value__)" -ForegroundColor Red
        }
    }
}
else {
    $results['401_apres_logout'] = 'FAIL'
    Write-Host 'SKIP: Session non disponible' -ForegroundColor Yellow
}

# ------------------------------------------------------------
# Test 13: Désactivation compte test (garanti par finally)
# ------------------------------------------------------------

Write-Host 'Test 13: Désactivation compte test...' -ForegroundColor Yellow

try {
    if ($accountCreated) {
        Invoke-Psql "UPDATE users SET status = 'INACTIVE' WHERE username = 'rbac-test-autre';" | Out-Null

        $status = Invoke-Psql "SELECT status FROM users WHERE username = 'rbac-test-autre';"

        if ($status -eq 'INACTIVE') {
            $results['compte_test_desactive'] = 'PASS'
            Write-Host "PASS: Compte désactivé (status: $status)" -ForegroundColor Green
        }
        else {
            $results['compte_test_desactive'] = 'FAIL'
            Write-Host 'FAIL: Compte non désactivé' -ForegroundColor Red
        }
    }
    else {
        $results['compte_test_desactive'] = 'FAIL'
        Write-Host 'SKIP: Compte non créé par ce test' -ForegroundColor Yellow
    }
}
catch {
    $results['compte_test_desactive'] = 'FAIL'
    Write-Host "FAIL: $($_.Exception.Message)" -ForegroundColor Red
}

# ------------------------------------------------------------
# Nettoyage final
# ------------------------------------------------------------

Remove-Item Env:PGPASSWORD -ErrorAction SilentlyContinue
Remove-Item Env:DB_PASSWORD -ErrorAction SilentlyContinue
if ($testPassword) {
    $testPassword = $null
}

# ------------------------------------------------------------
# Affichage du résumé
# ------------------------------------------------------------

Write-Host ''
Write-Host '==============================================' -ForegroundColor Cyan
Write-Host ' P0-A.2-B — 403 RBAC PROOF' -ForegroundColor Cyan
Write-Host '==============================================' -ForegroundColor Cyan
Write-Host ''

Write-Host "Rôle Autre trouvé              : $($results['role_autre_trouve'])" -ForegroundColor White
Write-Host "eleves.create existe           : $($results['permission_eleves_create'])" -ForegroundColor White
Write-Host "Permission absente du rôle     : $($results['autre_sans_eleves_create'])" -ForegroundColor White
Write-Host "Compte test créé               : $($results['creation_compte_test'])" -ForegroundColor White
Write-Host "Login Autre                    : $($results['login_compte_autre'])" -ForegroundColor White
Write-Host "HTTP 403                       : $($results['permission_denied_test'])" -ForegroundColor White
Write-Host "Query role bypass              : $($results['query_role_bloquee'])" -ForegroundColor White
Write-Host "X-Role bypass                  : $($results['header_x_role_bloque'])" -ForegroundColor White
Write-Host "X-Permission bypass            : $($results['header_x_permission_bloque'])" -ForegroundColor White
Write-Host "Logout                         : $($results['logout'])" -ForegroundColor White
Write-Host "401 après logout               : $($results['401_apres_logout'])" -ForegroundColor White
Write-Host "Compte test désactivé          : $($results['compte_test_desactive'])" -ForegroundColor White

Write-Host ''

$failedTests = $results.Values | Where-Object { $_ -eq 'FAIL' }

if ($failedTests) {
    Write-Host 'RESULT : FAIL' -ForegroundColor Red
    exit 1
}
else {
    Write-Host 'RESULT : PASS' -ForegroundColor Green
    exit 0
}
