# P0-A.3-B — STUDENTS CREATE API SECURITY TEST
# Tests the POST endpoint for students with RBAC

Set-Location 'C:\imc-clarodoro'

# ------------------------------------------------------------
# Helper function for environment variables (PowerShell 5.1 compatible)
# ------------------------------------------------------------

function Get-EnvOrDefault {
    param(
        [string]$Name,
        [string]$Default
    )

    $value = [Environment]::GetEnvironmentVariable($Name)

    if ([string]::IsNullOrWhiteSpace($value)) {
        return $Default
    }

    return $value
}

# ------------------------------------------------------------
# Configuration
# ------------------------------------------------------------

$baseUrl = 'http://127.0.0.1:8090'
$results = @{}
$testStudentId = $null
$testStudentData = $null

if (-not $env:PDG_PASSWORD) {
    Write-Error "PDG_PASSWORD doit être défini dans la session PowerShell."
    exit 1
}

# Generate unique matricule
$timestamp = Get-Date -Format "yyyyMMddHHmmss"
$testMatricule = "P0-A3B-$timestamp"

# ------------------------------------------------------------
# Test 1: POST without session
# ------------------------------------------------------------

Write-Host 'Test 1: POST /api/students/index.php sans session...' -ForegroundColor Yellow

try {
    $response = Invoke-WebRequest `
        -Uri "$baseUrl/api/students/index.php" `
        -Method POST `
        -UseBasicParsing `
        -ErrorAction Stop

    $results['post_sans_session'] = 'FAIL'
    Write-Host 'FAIL: Devrait retourner 401' -ForegroundColor Red
}
catch {
    if ($_.Exception.Response.StatusCode.value__ -eq 401) {
        $results['post_sans_session'] = 'PASS'
        Write-Host 'PASS: HTTP 401 retourné' -ForegroundColor Green
    }
    else {
        $results['post_sans_session'] = 'FAIL'
        Write-Host "FAIL: Statut inattendu $($_.Exception.Response.StatusCode.value__)" -ForegroundColor Red
    }
}

# ------------------------------------------------------------
# Test 2: LOGIN PDG
# ------------------------------------------------------------

Write-Host 'Test 2: LOGIN PDG...' -ForegroundColor Yellow

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
# Test 3: POST with valid JSON
# ------------------------------------------------------------

if ($session) {
    Write-Host 'Test 3: POST avec JSON valide...' -ForegroundColor Yellow

    $studentData = @{
        matricule = $testMatricule
        last_name = 'Test'
        first_name = 'Student'
        date_of_birth = '2010-01-15'
        sex = 'M'
        address = 'Test address'
        phone = '00000000'
        status = 'ACTIVE'
    }

    $tempPostJson = Join-Path $env:TEMP "imc-student-create.json"
    $studentJson = $studentData | ConvertTo-Json -Compress

    [System.IO.File]::WriteAllText(
        $tempPostJson,
        $studentJson,
        (New-Object System.Text.UTF8Encoding($false))
    )

    try {
        $response = Invoke-RestMethod `
            -Uri "$baseUrl/api/students/index.php" `
            -Method POST `
            -ContentType 'application/json' `
            -InFile $tempPostJson `
            -WebSession $session `
            -ErrorAction Stop

        if ($response.success -and $response.student -ne $null) {
            $testStudentId = $response.student.id
            $testStudentData = $studentData
            $results['post_valide'] = 'PASS'
            Write-Host "PASS: HTTP 201, student ID=$testStudentId" -ForegroundColor Green
        }
        else {
            $results['post_valide'] = 'FAIL'
            Write-Host 'FAIL: Réponse incorrecte' -ForegroundColor Red
        }
    }
    catch {
        $results['post_valide'] = 'FAIL'
        Write-Host "FAIL: $($_.Exception.Message)" -ForegroundColor Red
    }
    finally {
        Remove-Item $tempPostJson -Force -ErrorAction SilentlyContinue
    }
}
else {
    $results['post_valide'] = 'FAIL'
    Write-Host 'SKIP: Session non disponible' -ForegroundColor Yellow
}

# ------------------------------------------------------------
# Test 4: Verify response data
# ------------------------------------------------------------

if ($session -and $testStudentId -and $testStudentData) {
    Write-Host 'Test 4: Vérification données de réponse...' -ForegroundColor Yellow

    # Verify the data returned by Test 3 (don't recreate POST to avoid duplicate matricule error)
    try {
        $response = Invoke-RestMethod `
            -Uri "$baseUrl/api/students/index.php" `
            -WebSession $session `
            -ErrorAction Stop

        $student = $response.students | Where-Object { $_.id -eq $testStudentId }
        
        if ($student -and $student.matricule -eq $testStudentData.matricule -and
            $student.first_name -eq $testStudentData.first_name -and
            $student.last_name -eq $testStudentData.last_name -and
            $student.id -ne $null) {
            $results['verification_donnees'] = 'PASS'
            Write-Host 'PASS: Données correspondantes (vérifié via GET)' -ForegroundColor Green
        }
        else {
            $results['verification_donnees'] = 'FAIL'
            Write-Host 'FAIL: Données incorrectes ou non trouvées dans GET' -ForegroundColor Red
        }
    }
    catch {
        $results['verification_donnees'] = 'FAIL'
        Write-Host "FAIL: $($_.Exception.Message)" -ForegroundColor Red
    }
}
else {
    $results['verification_donnees'] = 'FAIL'
    Write-Host 'SKIP: Student non créé ou données non stockées' -ForegroundColor Yellow
}

# ------------------------------------------------------------
# Test 5: GET after creation
# ------------------------------------------------------------

if ($session) {
    Write-Host 'Test 5: GET après création...' -ForegroundColor Yellow

    try {
        $data = Invoke-RestMethod `
            -Uri "$baseUrl/api/students/index.php" `
            -WebSession $session `
            -ErrorAction Stop

        if ($data.success -eq $true -and $data.PSObject.Properties.Name -contains 'students' -and $data.PSObject.Properties.Name -contains 'count') {
            $results['get_apres_creation'] = 'PASS'
            Write-Host "PASS: success=true, count=$($data.count)" -ForegroundColor Green
        }
        else {
            $results['get_apres_creation'] = 'FAIL'
            Write-Host 'FAIL: Données incorrectes' -ForegroundColor Red
        }
    }
    catch {
        $results['get_apres_creation'] = 'FAIL'
        Write-Host "FAIL: $($_.Exception.Message)" -ForegroundColor Red
    }
}
else {
    $results['get_apres_creation'] = 'FAIL'
    Write-Host 'SKIP: Session non disponible' -ForegroundColor Yellow
}

# ------------------------------------------------------------
# Test 6: Verify student appears in GET
# ------------------------------------------------------------

if ($session -and $testStudentId) {
    Write-Host 'Test 6: Vérification étudiant dans GET...' -ForegroundColor Yellow

    try {
        $data = Invoke-RestMethod `
            -Uri "$baseUrl/api/students/index.php" `
            -WebSession $session `
            -ErrorAction Stop

        $found = $data.students | Where-Object { $_.id -eq $testStudentId }
        if ($found) {
            $results['student_visible'] = 'PASS'
            Write-Host 'PASS: Étudiant visible dans GET' -ForegroundColor Green
        }
        else {
            $results['student_visible'] = 'FAIL'
            Write-Host 'FAIL: Étudiant non trouvé dans GET' -ForegroundColor Red
        }
    }
    catch {
        $results['student_visible'] = 'FAIL'
        Write-Host "FAIL: $($_.Exception.Message)" -ForegroundColor Red
    }
}
else {
    $results['student_visible'] = 'FAIL'
    Write-Host 'SKIP: Student non créé' -ForegroundColor Yellow
}

# ------------------------------------------------------------
# Test 7: Invalid JSON
# ------------------------------------------------------------

if ($session) {
    Write-Host 'Test 7: JSON invalide...' -ForegroundColor Yellow

    try {
        $invalidJson = '{"invalid": json}'
        $response = Invoke-RestMethod `
            -Uri "$baseUrl/api/students/index.php" `
            -Method POST `
            -ContentType 'application/json' `
            -Body $invalidJson `
            -WebSession $session `
            -ErrorAction Stop

        $results['json_invalide'] = 'FAIL'
        Write-Host 'FAIL: Devrait retourner 400' -ForegroundColor Red
    }
    catch {
        if ($_.Exception.Response.StatusCode.value__ -eq 400) {
            $results['json_invalide'] = 'PASS'
            Write-Host 'PASS: HTTP 400 retourné' -ForegroundColor Green
        }
        else {
            $results['json_invalide'] = 'FAIL'
            Write-Host "FAIL: Statut inattendu $($_.Exception.Response.StatusCode.value__)" -ForegroundColor Red
        }
    }
}
else {
    $results['json_invalide'] = 'FAIL'
    Write-Host 'SKIP: Session non disponible' -ForegroundColor Yellow
}

# ------------------------------------------------------------
# Test 8: Missing matricule
# ------------------------------------------------------------

if ($session) {
    Write-Host 'Test 8: Matricule manquant...' -ForegroundColor Yellow

    $invalidData = @{
        last_name = 'Test'
        first_name = 'Student'
    }

    $tempInvalidJson = Join-Path $env:TEMP "imc-invalid-matricule.json"
    $invalidJson = $invalidData | ConvertTo-Json -Compress

    [System.IO.File]::WriteAllText(
        $tempInvalidJson,
        $invalidJson,
        (New-Object System.Text.UTF8Encoding($false))
    )

    try {
        $response = Invoke-RestMethod `
            -Uri "$baseUrl/api/students/index.php" `
            -Method POST `
            -ContentType 'application/json' `
            -InFile $tempInvalidJson `
            -WebSession $session `
            -ErrorAction Stop

        $results['matricule_manquant'] = 'FAIL'
        Write-Host 'FAIL: Devrait retourner 422' -ForegroundColor Red
    }
    catch {
        if ($_.Exception.Response.StatusCode.value__ -eq 422) {
            $results['matricule_manquant'] = 'PASS'
            Write-Host 'PASS: HTTP 422 retourné' -ForegroundColor Green
        }
        else {
            $results['matricule_manquant'] = 'FAIL'
            Write-Host "FAIL: Statut inattendu $($_.Exception.Response.StatusCode.value__)" -ForegroundColor Red
        }
    }
    finally {
        Remove-Item $tempInvalidJson -Force -ErrorAction SilentlyContinue
    }
}
else {
    $results['matricule_manquant'] = 'FAIL'
    Write-Host 'SKIP: Session non disponible' -ForegroundColor Yellow
}

# ------------------------------------------------------------
# Test 9: Missing last_name
# ------------------------------------------------------------

if ($session) {
    Write-Host 'Test 9: last_name manquant...' -ForegroundColor Yellow

    $invalidData = @{
        matricule = 'TEST-999'
        first_name = 'Student'
    }

    $tempInvalidJson = Join-Path $env:TEMP "imc-invalid-lastname.json"
    $invalidJson = $invalidData | ConvertTo-Json -Compress

    [System.IO.File]::WriteAllText(
        $tempInvalidJson,
        $invalidJson,
        (New-Object System.Text.UTF8Encoding($false))
    )

    try {
        $response = Invoke-RestMethod `
            -Uri "$baseUrl/api/students/index.php" `
            -Method POST `
            -ContentType 'application/json' `
            -InFile $tempInvalidJson `
            -WebSession $session `
            -ErrorAction Stop

        $results['lastname_manquant'] = 'FAIL'
        Write-Host 'FAIL: Devrait retourner 422' -ForegroundColor Red
    }
    catch {
        if ($_.Exception.Response.StatusCode.value__ -eq 422) {
            $results['lastname_manquant'] = 'PASS'
            Write-Host 'PASS: HTTP 422 retourné' -ForegroundColor Green
        }
        else {
            $results['lastname_manquant'] = 'FAIL'
            Write-Host "FAIL: Statut inattendu $($_.Exception.Response.StatusCode.value__)" -ForegroundColor Red
        }
    }
    finally {
        Remove-Item $tempInvalidJson -Force -ErrorAction SilentlyContinue
    }
}
else {
    $results['lastname_manquant'] = 'FAIL'
    Write-Host 'SKIP: Session non disponible' -ForegroundColor Yellow
}

# ------------------------------------------------------------
# Test 10: Missing first_name
# ------------------------------------------------------------

if ($session) {
    Write-Host 'Test 10: first_name manquant...' -ForegroundColor Yellow

    $invalidData = @{
        matricule = 'TEST-998'
        last_name = 'Test'
    }

    $tempInvalidJson = Join-Path $env:TEMP "imc-invalid-firstname.json"
    $invalidJson = $invalidData | ConvertTo-Json -Compress

    [System.IO.File]::WriteAllText(
        $tempInvalidJson,
        $invalidJson,
        (New-Object System.Text.UTF8Encoding($false))
    )

    try {
        $response = Invoke-RestMethod `
            -Uri "$baseUrl/api/students/index.php" `
            -Method POST `
            -ContentType 'application/json' `
            -InFile $tempInvalidJson `
            -WebSession $session `
            -ErrorAction Stop

        $results['firstname_manquant'] = 'FAIL'
        Write-Host 'FAIL: Devrait retourner 422' -ForegroundColor Red
    }
    catch {
        if ($_.Exception.Response.StatusCode.value__ -eq 422) {
            $results['firstname_manquant'] = 'PASS'
            Write-Host 'PASS: HTTP 422 retourné' -ForegroundColor Green
        }
        else {
            $results['firstname_manquant'] = 'FAIL'
            Write-Host "FAIL: Statut inattendu $($_.Exception.Response.StatusCode.value__)" -ForegroundColor Red
        }
    }
    finally {
        Remove-Item $tempInvalidJson -Force -ErrorAction SilentlyContinue
    }
}
else {
    $results['firstname_manquant'] = 'FAIL'
    Write-Host 'SKIP: Session non disponible' -ForegroundColor Yellow
}

# ------------------------------------------------------------
# Test 11: Invalid status
# ------------------------------------------------------------

if ($session) {
    Write-Host 'Test 11: Status invalide...' -ForegroundColor Yellow

    $invalidData = @{
        matricule = 'TEST-997'
        last_name = 'Test'
        first_name = 'Student'
        status = 'INVALID_STATUS'
    }

    $tempInvalidJson = Join-Path $env:TEMP "imc-invalid-status.json"
    $invalidJson = $invalidData | ConvertTo-Json -Compress

    [System.IO.File]::WriteAllText(
        $tempInvalidJson,
        $invalidJson,
        (New-Object System.Text.UTF8Encoding($false))
    )

    try {
        $response = Invoke-RestMethod `
            -Uri "$baseUrl/api/students/index.php" `
            -Method POST `
            -ContentType 'application/json' `
            -InFile $tempInvalidJson `
            -WebSession $session `
            -ErrorAction Stop

        $results['status_invalide'] = 'FAIL'
        Write-Host 'FAIL: Devrait retourner 422' -ForegroundColor Red
    }
    catch {
        if ($_.Exception.Response.StatusCode.value__ -eq 422) {
            $results['status_invalide'] = 'PASS'
            Write-Host 'PASS: HTTP 422 retourné' -ForegroundColor Green
        }
        else {
            $results['status_invalide'] = 'FAIL'
            Write-Host "FAIL: Statut inattendu $($_.Exception.Response.StatusCode.value__)" -ForegroundColor Red
        }
    }
    finally {
        Remove-Item $tempInvalidJson -Force -ErrorAction SilentlyContinue
    }
}
else {
    $results['status_invalide'] = 'FAIL'
    Write-Host 'SKIP: Session non disponible' -ForegroundColor Yellow
}

# ------------------------------------------------------------
# Test 12: Unknown field
# ------------------------------------------------------------

if ($session) {
    Write-Host 'Test 12: Champ inconnu...' -ForegroundColor Yellow

    $invalidData = @{
        matricule = 'TEST-996'
        last_name = 'Test'
        first_name = 'Student'
        unknown_field = 'value'
    }

    $tempInvalidJson = Join-Path $env:TEMP "imc-unknown-field.json"
    $invalidJson = $invalidData | ConvertTo-Json -Compress

    [System.IO.File]::WriteAllText(
        $tempInvalidJson,
        $invalidJson,
        (New-Object System.Text.UTF8Encoding($false))
    )

    try {
        $response = Invoke-RestMethod `
            -Uri "$baseUrl/api/students/index.php" `
            -Method POST `
            -ContentType 'application/json' `
            -InFile $tempInvalidJson `
            -WebSession $session `
            -ErrorAction Stop

        $results['champ_inconnu'] = 'FAIL'
        Write-Host 'FAIL: Devrait retourner 422' -ForegroundColor Red
    }
    catch {
        if ($_.Exception.Response.StatusCode.value__ -eq 422) {
            $results['champ_inconnu'] = 'PASS'
            Write-Host 'PASS: HTTP 422 retourné' -ForegroundColor Green
        }
        else {
            $results['champ_inconnu'] = 'FAIL'
            Write-Host "FAIL: Statut inattendu $($_.Exception.Response.StatusCode.value__)" -ForegroundColor Red
        }
    }
    finally {
        Remove-Item $tempInvalidJson -Force -ErrorAction SilentlyContinue
    }
}
else {
    $results['champ_inconnu'] = 'FAIL'
    Write-Host 'SKIP: Session non disponible' -ForegroundColor Yellow
}

# ------------------------------------------------------------
# Test 13: Spoof role/permission in JSON
# ------------------------------------------------------------

if ($session) {
    Write-Host 'Test 13: Spoof role/permission dans JSON...' -ForegroundColor Yellow

    $spoofData = @{
        matricule = 'TEST-995'
        last_name = 'Test'
        first_name = 'Student'
        role = 'Autre'
        permission = 'eleves.read'
    }

    $tempSpoofJson = Join-Path $env:TEMP "imc-spoof.json"
    $spoofJson = $spoofData | ConvertTo-Json -Compress

    [System.IO.File]::WriteAllText(
        $tempSpoofJson,
        $spoofJson,
        (New-Object System.Text.UTF8Encoding($false))
    )

    try {
        $response = Invoke-RestMethod `
            -Uri "$baseUrl/api/students/index.php" `
            -Method POST `
            -ContentType 'application/json' `
            -InFile $tempSpoofJson `
            -WebSession $session `
            -ErrorAction Stop

        if ($response.success) {
            $results['spoof_json'] = 'PASS'
            Write-Host 'PASS: Spoof ignoré, création autorisée' -ForegroundColor Green
        }
        else {
            $results['spoof_json'] = 'FAIL'
            Write-Host 'FAIL: Spoof affecté autorisation' -ForegroundColor Red
        }
    }
    catch {
        if ($_.Exception.Response.StatusCode.value__ -eq 422) {
            $results['spoof_json'] = 'PASS'
            Write-Host 'PASS: Champ inconnu rejeté' -ForegroundColor Green
        }
        else {
            $results['spoof_json'] = 'FAIL'
            Write-Host "FAIL: $($_.Exception.Message)" -ForegroundColor Red
        }
    }
    finally {
        Remove-Item $tempSpoofJson -Force -ErrorAction SilentlyContinue
    }
}
else {
    $results['spoof_json'] = 'FAIL'
    Write-Host 'SKIP: Session non disponible' -ForegroundColor Yellow
}

# ------------------------------------------------------------
# Test 14: X-Role header
# ------------------------------------------------------------

if ($session) {
    Write-Host 'Test 14: X-Role header...' -ForegroundColor Yellow

    $studentData = @{
        matricule = "P0-A3B-XROLE-$timestamp"
        last_name = 'Test'
        first_name = 'Student-XRole'
    }

    $tempTestJson = Join-Path $env:TEMP "imc-xrole.json"
    $testJson = $studentData | ConvertTo-Json -Compress

    [System.IO.File]::WriteAllText(
        $tempTestJson,
        $testJson,
        (New-Object System.Text.UTF8Encoding($false))
    )

    try {
        $response = Invoke-RestMethod `
            -Uri "$baseUrl/api/students/index.php" `
            -Method POST `
            -ContentType 'application/json' `
            -InFile $tempTestJson `
            -WebSession $session `
            -Headers @{'X-Role' = 'Autre'} `
            -ErrorAction Stop

        if ($response.success) {
            $results['x_role_header'] = 'PASS'
            Write-Host 'PASS: Header ignoré' -ForegroundColor Green
        }
        else {
            $results['x_role_header'] = 'FAIL'
            Write-Host 'FAIL: Header affecté autorisation' -ForegroundColor Red
        }
    }
    catch {
        $results['x_role_header'] = 'FAIL'
        Write-Host "FAIL: $($_.Exception.Message)" -ForegroundColor Red
    }
    finally {
        Remove-Item $tempTestJson -Force -ErrorAction SilentlyContinue
    }
}
else {
    $results['x_role_header'] = 'FAIL'
    Write-Host 'SKIP: Session non disponible' -ForegroundColor Yellow
}

# ------------------------------------------------------------
# Test 15: X-Permission header
# ------------------------------------------------------------

if ($session) {
    Write-Host 'Test 15: X-Permission header...' -ForegroundColor Yellow

    $studentData = @{
        matricule = "P0-A3B-XPERMISSION-$timestamp"
        last_name = 'Test'
        first_name = 'Student-XPermission'
    }

    $tempTestJson = Join-Path $env:TEMP "imc-xpermission.json"
    $testJson = $studentData | ConvertTo-Json -Compress

    [System.IO.File]::WriteAllText(
        $tempTestJson,
        $testJson,
        (New-Object System.Text.UTF8Encoding($false))
    )

    try {
        $response = Invoke-RestMethod `
            -Uri "$baseUrl/api/students/index.php" `
            -Method POST `
            -ContentType 'application/json' `
            -InFile $tempTestJson `
            -WebSession $session `
            -Headers @{'X-Permission' = 'false'} `
            -ErrorAction Stop

        if ($response.success) {
            $results['x_permission_header'] = 'PASS'
            Write-Host 'PASS: Header ignoré' -ForegroundColor Green
        }
        else {
            $results['x_permission_header'] = 'FAIL'
            Write-Host 'FAIL: Header affecté autorisation' -ForegroundColor Red
        }
    }
    catch {
        $results['x_permission_header'] = 'FAIL'
        Write-Host "FAIL: $($_.Exception.Message)" -ForegroundColor Red
    }
    finally {
        Remove-Item $tempTestJson -Force -ErrorAction SilentlyContinue
    }
}
else {
    $results['x_permission_header'] = 'FAIL'
    Write-Host 'SKIP: Session non disponible' -ForegroundColor Yellow
}

# ------------------------------------------------------------
# Test 16: LOGOUT
# ------------------------------------------------------------

if ($session) {
    Write-Host 'Test 16: LOGOUT...' -ForegroundColor Yellow

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
# Test 17: POST after logout
# ------------------------------------------------------------

if ($session) {
    Write-Host 'Test 17: POST après logout...' -ForegroundColor Yellow

    try {
        $response = Invoke-RestMethod `
            -Uri "$baseUrl/api/students/index.php" `
            -Method POST `
            -WebSession $session `
            -ErrorAction Stop

        $results['post_apres_logout'] = 'FAIL'
        Write-Host 'FAIL: Devrait retourner 401' -ForegroundColor Red
    }
    catch {
        if ($_.Exception.Response.StatusCode.value__ -eq 401) {
            $results['post_apres_logout'] = 'PASS'
            Write-Host 'PASS: HTTP 401 retourné' -ForegroundColor Green
        }
        else {
            $results['post_apres_logout'] = 'FAIL'
            Write-Host "FAIL: Statut inattendu $($_.Exception.Response.StatusCode.value__)" -ForegroundColor Red
        }
    }
}
else {
    $results['post_apres_logout'] = 'FAIL'
    Write-Host 'SKIP: Session non disponible' -ForegroundColor Yellow
}

# ------------------------------------------------------------
# Test 18: Cleanup - Delete test student
# ------------------------------------------------------------

Write-Host 'Test 18: Nettoyage étudiant de test...' -ForegroundColor Yellow

if ($testStudentId) {
    $psql = 'C:\Program Files\PostgreSQL\18\bin\psql.exe'
    $env:PGPASSWORD = $env:DB_PASSWORD

    $dbHost = Get-EnvOrDefault -Name 'DB_HOST' -Default '127.0.0.1'
    $dbPort = Get-EnvOrDefault -Name 'DB_PORT' -Default '5432'
    $dbUser = Get-EnvOrDefault -Name 'DB_USER' -Default 'postgres'
    $dbName = Get-EnvOrDefault -Name 'DB_NAME' -Default 'imc_clarodoro'

    try {
        $result = & $psql `
            -h $dbHost `
            -p $dbPort `
            -U $dbUser `
            -d $dbName `
            -c "DELETE FROM students WHERE id = '$testStudentId';" 2>&1

        if ($LASTEXITCODE -eq 0) {
            $results['cleanup'] = 'PASS'
            Write-Host 'PASS: Étudiant supprimé' -ForegroundColor Green
        }
        else {
            $results['cleanup'] = 'FAIL'
            Write-Host "CLEANUP: FAIL - $result" -ForegroundColor Red
        }
    }
    catch {
        $results['cleanup'] = 'FAIL'
        Write-Host "CLEANUP: FAIL - $($_.Exception.Message)" -ForegroundColor Red
    }
    finally {
        Remove-Item Env:PGPASSWORD -ErrorAction SilentlyContinue
    }
}
else {
    $results['cleanup'] = 'SKIP'
    Write-Host 'SKIP: Aucun étudiant à nettoyer' -ForegroundColor Yellow
}

# ------------------------------------------------------------
# Nettoyage final
# ------------------------------------------------------------

Remove-Item Env:PDG_PASSWORD -ErrorAction SilentlyContinue

# ------------------------------------------------------------
# Affichage du résumé
# ------------------------------------------------------------

Write-Host ''
Write-Host '==============================================' -ForegroundColor Cyan
Write-Host ' P0-A.3-B — STUDENTS CREATE API TEST' -ForegroundColor Cyan
Write-Host '==============================================' -ForegroundColor Cyan
Write-Host ''

$postSansSession = $results['post_sans_session']
$loginPdg = $results['login_pdg']
$postValide = $results['post_valide']
$verificationDonnees = $results['verification_donnees']
$getApresCreation = $results['get_apres_creation']
$studentVisible = $results['student_visible']
$jsonInvalide = $results['json_invalide']
$matriculeManquant = $results['matricule_manquant']
$lastnameManquant = $results['lastname_manquant']
$firstnameManquant = $results['firstname_manquant']
$statusInvalide = $results['status_invalide']
$champInconnu = $results['champ_inconnu']
$spoofJson = $results['spoof_json']
$xRoleHeader = $results['x_role_header']
$xPermissionHeader = $results['x_permission_header']
$logout = $results['logout']
$postApresLogout = $results['post_apres_logout']
$cleanup = $results['cleanup']

Write-Host "POST sans session                : $postSansSession" -ForegroundColor White
Write-Host "LOGIN PDG                         : $loginPdg" -ForegroundColor White
Write-Host "POST valide                       : $postValide" -ForegroundColor White
Write-Host "Vérification données              : $verificationDonnees" -ForegroundColor White
Write-Host "GET après création                : $getApresCreation" -ForegroundColor White
Write-Host "Étudiant visible                 : $studentVisible" -ForegroundColor White
Write-Host "JSON invalide                     : $jsonInvalide" -ForegroundColor White
Write-Host "Matricule manquant               : $matriculeManquant" -ForegroundColor White
Write-Host "last_name manquant               : $lastnameManquant" -ForegroundColor White
Write-Host "first_name manquant              : $firstnameManquant" -ForegroundColor White
Write-Host "Status invalide                   : $statusInvalide" -ForegroundColor White
Write-Host "Champ inconnu                     : $champInconnu" -ForegroundColor White
Write-Host "Spoof JSON role/permission        : $spoofJson" -ForegroundColor White
Write-Host "X-Role header                     : $xRoleHeader" -ForegroundColor White
Write-Host "X-Permission header              : $xPermissionHeader" -ForegroundColor White
Write-Host "LOGOUT                            : $logout" -ForegroundColor White
Write-Host "POST après logout                 : $postApresLogout" -ForegroundColor White
Write-Host "CLEANUP                           : $cleanup" -ForegroundColor White

Write-Host ''

$failedTests = $results.Values | Where-Object { $_ -eq 'FAIL' }
$cleanupFailed = $results['cleanup'] -eq 'FAIL'

if ($failedTests) {
    Write-Host 'RESULT : FAIL' -ForegroundColor Red
    exit 1
}
elseif ($cleanupFailed) {
    Write-Host 'RESULT : FAIL (CLEANUP FAILED)' -ForegroundColor Red
    exit 1
}
else {
    Write-Host 'RESULT : PASS' -ForegroundColor Green
    exit 0
}
