# P0-A.3-A — STUDENTS READ API SECURITY TEST
# Tests the new students API with RBAC

Set-Location 'C:\imc-clarodoro'

# ------------------------------------------------------------
# Configuration
# ------------------------------------------------------------

$baseUrl = 'http://127.0.0.1:8090'
$results = @{}

if (-not $env:PDG_PASSWORD) {
    Write-Error "PDG_PASSWORD doit être défini dans la session PowerShell."
    exit 1
}

# ------------------------------------------------------------
# Test 1: GET without session
# ------------------------------------------------------------

Write-Host 'Test 1: GET /api/students/index.php sans session...' -ForegroundColor Yellow

try {
    $response = Invoke-WebRequest `
        -Uri "$baseUrl/api/students/index.php" `
        -UseBasicParsing `
        -ErrorAction Stop

    $results['get_sans_session'] = 'FAIL'
    Write-Host 'FAIL: Devrait retourner 401' -ForegroundColor Red
}
catch {
    if ($_.Exception.Response.StatusCode.value__ -eq 401) {
        $results['get_sans_session'] = 'PASS'
        Write-Host 'PASS: HTTP 401 retourné' -ForegroundColor Green
    }
    else {
        $results['get_sans_session'] = 'FAIL'
        Write-Host "FAIL: Statut inattendu $($_.Exception.Response.StatusCode.value__)" -ForegroundColor Red
    }
}

# ------------------------------------------------------------
# Test 2: LOGIN PDG
# ------------------------------------------------------------

Write-Host 'Test 2: LOGIN PDG...' -ForegroundColor Yellow

# Create JSON body in temporary file to ensure proper encoding
$tempJson = Join-Path $env:TEMP "imc-login-body.json"
$jsonContent = @{
    username = 'pdg'
    password = $env:PDG_PASSWORD
} | ConvertTo-Json -Compress

[System.IO.File]::WriteAllText(
    $tempJson,
    $jsonContent,
    (New-Object System.Text.UTF8Encoding($false))
)

$session = New-Object Microsoft.PowerShell.Commands.WebRequestSession

try {
    $login = Invoke-RestMethod `
        -Uri "$baseUrl/api/auth/login.php" `
        -Method POST `
        -ContentType 'application/json' `
        -InFile $tempJson `
        -WebSession $session `
        -ErrorAction Stop

    if ($login.success -and $login.user.username -eq 'pdg') {
        $results['login_pdg'] = 'PASS'
        Write-Host "PASS: $($login.user.username)" -ForegroundColor Green
    }
    else {
        $results['login_pdg'] = 'FAIL'
        Write-Host 'FAIL: Login échoué' -ForegroundColor Red
        $session = $null
    }
}
catch {
    $results['login_pdg'] = 'FAIL'
    Write-Host "FAIL: $($_.Exception.Message)" -ForegroundColor Red
    $session = $null
}
finally {
    Remove-Item $tempJson -Force -ErrorAction SilentlyContinue
}

# ------------------------------------------------------------
# Test 3: GET with PDG session
# ------------------------------------------------------------

if ($session) {
    Write-Host 'Test 3: GET /api/students/index.php avec session PDG...' -ForegroundColor Yellow

    try {
        $data = Invoke-RestMethod `
            -Uri "$baseUrl/api/students/index.php" `
            -WebSession $session `
            -ErrorAction Stop

        # Verify success=true, students present, count present
        # Accept students=[] and count=0 (no data is not an error)
        if ($data.success -eq $true -and $data.PSObject.Properties.Name -contains 'students' -and $data.PSObject.Properties.Name -contains 'count') {
            $results['get_avec_session'] = 'PASS'
            Write-Host "PASS: success=true, count=$($data.count)" -ForegroundColor Green
        }
        else {
            $results['get_avec_session'] = 'FAIL'
            Write-Host 'FAIL: Données incorrectes' -ForegroundColor Red
        }
    }
    catch {
        $results['get_avec_session'] = 'FAIL'
        Write-Host "FAIL: $($_.Exception.Message)" -ForegroundColor Red
    }
}
else {
    $results['get_avec_session'] = 'FAIL'
    Write-Host 'SKIP: Session non disponible' -ForegroundColor Yellow
}

# ------------------------------------------------------------
# Test 4: GET with ?role=Autre (should still work)
# ------------------------------------------------------------

if ($session) {
    Write-Host 'Test 4: GET avec ?role=Autre...' -ForegroundColor Yellow

    try {
        $data = Invoke-RestMethod `
            -Uri "$baseUrl/api/students/index.php?role=Autre" `
            -WebSession $session `
            -ErrorAction Stop

        if ($data.success) {
            $results['query_role_bypass'] = 'PASS'
            Write-Host 'PASS: Query param ignored, still authorized' -ForegroundColor Green
        }
        else {
            $results['query_role_bypass'] = 'FAIL'
            Write-Host 'FAIL: Query param affected authorization' -ForegroundColor Red
        }
    }
    catch {
        $results['query_role_bypass'] = 'FAIL'
        Write-Host "FAIL: $($_.Exception.Message)" -ForegroundColor Red
    }
}
else {
    $results['query_role_bypass'] = 'FAIL'
    Write-Host 'SKIP: Session non disponible' -ForegroundColor Yellow
}

# ------------------------------------------------------------
# Test 5: GET with X-Role header (should still work)
# ------------------------------------------------------------

if ($session) {
    Write-Host 'Test 5: GET avec X-Role header...' -ForegroundColor Yellow

    try {
        $data = Invoke-RestMethod `
            -Uri "$baseUrl/api/students/index.php" `
            -WebSession $session `
            -Headers @{'X-Role' = 'Autre'} `
            -ErrorAction Stop

        if ($data.success) {
            $results['header_x_role_bypass'] = 'PASS'
            Write-Host 'PASS: Header ignored, still authorized' -ForegroundColor Green
        }
        else {
            $results['header_x_role_bypass'] = 'FAIL'
            Write-Host 'FAIL: Header affected authorization' -ForegroundColor Red
        }
    }
    catch {
        $results['header_x_role_bypass'] = 'FAIL'
        Write-Host "FAIL: $($_.Exception.Message)" -ForegroundColor Red
    }
}
else {
    $results['header_x_role_bypass'] = 'FAIL'
    Write-Host 'SKIP: Session non disponible' -ForegroundColor Yellow
}

# ------------------------------------------------------------
# Test 6: GET with X-Permission header (should still work)
# ------------------------------------------------------------

if ($session) {
    Write-Host 'Test 6: GET avec X-Permission header...' -ForegroundColor Yellow

    try {
        $data = Invoke-RestMethod `
            -Uri "$baseUrl/api/students/index.php" `
            -WebSession $session `
            -Headers @{'X-Permission' = 'false'} `
            -ErrorAction Stop

        if ($data.success) {
            $results['header_x_permission_bypass'] = 'PASS'
            Write-Host 'PASS: Header ignored, still authorized' -ForegroundColor Green
        }
        else {
            $results['header_x_permission_bypass'] = 'FAIL'
            Write-Host 'FAIL: Header affected authorization' -ForegroundColor Red
        }
    }
    catch {
        $results['header_x_permission_bypass'] = 'FAIL'
        Write-Host "FAIL: $($_.Exception.Message)" -ForegroundColor Red
    }
}
else {
    $results['header_x_permission_bypass'] = 'FAIL'
    Write-Host 'SKIP: Session non disponible' -ForegroundColor Yellow
}

# ------------------------------------------------------------
# Test 7: PUT (should return 405)
# NOTE: POST is handled by P0-A.3-B (creation endpoint)
# ------------------------------------------------------------

if ($session) {
    Write-Host 'Test 7: PUT /api/students/index.php...' -ForegroundColor Yellow

    try {
        $response = Invoke-WebRequest `
            -Uri "$baseUrl/api/students/index.php" `
            -Method PUT `
            -WebSession $session `
            -UseBasicParsing `
            -ErrorAction Stop

        $results['put_405'] = 'FAIL'
        Write-Host 'FAIL: Devrait retourner 405' -ForegroundColor Red
    }
    catch {
        if ($_.Exception.Response.StatusCode.value__ -eq 405) {
            $results['put_405'] = 'PASS'
            Write-Host 'PASS: HTTP 405 retourné' -ForegroundColor Green
        }
        else {
            $results['put_405'] = 'FAIL'
            Write-Host "FAIL: Statut inattendu $($_.Exception.Response.StatusCode.value__)" -ForegroundColor Red
        }
    }
}
else {
    $results['put_405'] = 'FAIL'
    Write-Host 'SKIP: Session non disponible' -ForegroundColor Yellow
}

# ------------------------------------------------------------
# Test 8: DELETE (should return 405)
# ------------------------------------------------------------

if ($session) {
    Write-Host 'Test 8: DELETE /api/students/index.php...' -ForegroundColor Yellow

    try {
        $response = Invoke-WebRequest `
            -Uri "$baseUrl/api/students/index.php" `
            -Method DELETE `
            -WebSession $session `
            -UseBasicParsing `
            -ErrorAction Stop

        $results['delete_405'] = 'FAIL'
        Write-Host 'FAIL: Devrait retourner 405' -ForegroundColor Red
    }
    catch {
        if ($_.Exception.Response.StatusCode.value__ -eq 405) {
            $results['delete_405'] = 'PASS'
            Write-Host 'PASS: HTTP 405 retourné' -ForegroundColor Green
        }
        else {
            $results['delete_405'] = 'FAIL'
            Write-Host "FAIL: Statut inattendu $($_.Exception.Response.StatusCode.value__)" -ForegroundColor Red
        }
    }
}
else {
    $results['delete_405'] = 'FAIL'
    Write-Host 'SKIP: Session non disponible' -ForegroundColor Yellow
}

# ------------------------------------------------------------
# Test 9: LOGOUT
# ------------------------------------------------------------

if ($session) {
    Write-Host 'Test 9: LOGOUT...' -ForegroundColor Yellow

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
# Test 10: GET after logout
# ------------------------------------------------------------

if ($session) {
    Write-Host 'Test 10: GET après logout...' -ForegroundColor Yellow

    try {
        $response = Invoke-RestMethod `
            -Uri "$baseUrl/api/students/index.php" `
            -WebSession $session `
            -ErrorAction Stop

        $results['get_apres_logout'] = 'FAIL'
        Write-Host 'FAIL: Devrait retourner 401' -ForegroundColor Red
    }
    catch {
        if ($_.Exception.Response.StatusCode.value__ -eq 401) {
            $results['get_apres_logout'] = 'PASS'
            Write-Host 'PASS: HTTP 401 retourné' -ForegroundColor Green
        }
        else {
            $results['get_apres_logout'] = 'FAIL'
            Write-Host "FAIL: Statut inattendu $($_.Exception.Response.StatusCode.value__)" -ForegroundColor Red
        }
    }
}
else {
    $results['get_apres_logout'] = 'FAIL'
    Write-Host 'SKIP: Session non disponible' -ForegroundColor Yellow
}

# ------------------------------------------------------------
# Nettoyage
# ------------------------------------------------------------

Remove-Item Env:PDG_PASSWORD -ErrorAction SilentlyContinue

# ------------------------------------------------------------
# Affichage du résumé
# ------------------------------------------------------------

Write-Host ''
Write-Host '==============================================' -ForegroundColor Cyan
Write-Host ' P0-A.3-A — STUDENTS READ API TEST' -ForegroundColor Cyan
Write-Host '==============================================' -ForegroundColor Cyan
Write-Host ''

Write-Host "GET sans session              : $($results['get_sans_session'])" -ForegroundColor White
Write-Host "LOGIN PDG                     : $($results['login_pdg'])" -ForegroundColor White
Write-Host "GET avec session PDG         : $($results['get_avec_session'])" -ForegroundColor White
Write-Host "Query ?role=Autre ignored     : $($results['query_role_bypass'])" -ForegroundColor White
Write-Host "Header X-Role ignored        : $($results['header_x_role_bypass'])" -ForegroundColor White
Write-Host "Header X-Permission ignored  : $($results['header_x_permission_bypass'])" -ForegroundColor White
Write-Host "PUT 405                      : $($results['put_405'])" -ForegroundColor White
Write-Host "DELETE 405                   : $($results['delete_405'])" -ForegroundColor White
Write-Host "LOGOUT                       : $($results['logout'])" -ForegroundColor White
Write-Host "GET après logout             : $($results['get_apres_logout'])" -ForegroundColor White

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
