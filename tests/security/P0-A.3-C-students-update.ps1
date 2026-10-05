$ErrorActionPreference = 'Stop'

function LoadLocalEnv([string]$Path) {
    if (!(Test-Path -LiteralPath $Path -PathType Leaf)) { return }
    foreach ($line in (Get-Content -LiteralPath $Path -ErrorAction Stop)) {
        $trimmed = $line.Trim()
        if ([string]::IsNullOrWhiteSpace($trimmed) -or $trimmed.StartsWith('#')) { continue }
        if ($trimmed.StartsWith('export ')) { $trimmed = $trimmed.Substring(7).Trim() }
        $separator = $trimmed.IndexOf('=')
        if ($separator -lt 1) { continue }
        $name = $trimmed.Substring(0, $separator).Trim()
        $value = $trimmed.Substring($separator + 1).Trim()
        if ($name -notmatch '^[A-Za-z_][A-Za-z0-9_]*
    $v = [Environment]::GetEnvironmentVariable($Name)
    if ([string]::IsNullOrWhiteSpace($v)) { return $Default }
    return $v
}
function StatusOf($e) {
    try { if ($e.Exception.Response.StatusCode) { return [int]$e.Exception.Response.StatusCode.value__ } } catch {}
    return $null
}
function Result([string]$Key,[string]$Value,[string]$Message) {
    $script:results[$Key] = $Value
    $c = if ($Value -eq 'PASS') {'Green'} elseif ($Value -eq 'SKIP') {'Yellow'} else {'Red'}
    Write-Host "${Value}: $Message" -ForegroundColor $c
}
function Psql([string]$Sql) {
    if ([string]::IsNullOrWhiteSpace($env:DB_PASSWORD)) { throw 'DB_PASSWORD non défini pour psql' }
    $old = $env:PGPASSWORD
    $env:PGPASSWORD = $env:DB_PASSWORD
    try {
        $out = & $script:psql -h $script:dbHost -p $script:dbPort -U $script:dbUser -d $script:dbName -c $Sql 2>&1
        return [pscustomobject]@{ Code=$LASTEXITCODE; Output=$out }
    } finally {
        if ($null -eq $old) { Remove-Item Env:PGPASSWORD -ErrorAction SilentlyContinue } else { $env:PGPASSWORD=$old }
    }
}
function ExpectStatus([string]$Key,[scriptblock]$Action,[int]$Expected) {
    try { & $Action | Out-Null; Result $Key 'FAIL' "Devrait retourner HTTP $Expected" }
    catch {
        $s=StatusOf $_
        if ($s -eq $Expected) { Result $Key 'PASS' "HTTP $Expected retourné" } else { Result $Key 'FAIL' "Statut inattendu $s" }
    }
}

$baseUrl='http://127.0.0.1:8090'
$results=@{}
$testStudentId=$null
$conflictStudentId=$null
$projectRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
LoadLocalEnv (Join-Path $projectRoot '.env')

$dbHost=EnvOrDefault 'DB_HOST' '127.0.0.1'
$dbPort=EnvOrDefault 'DB_PORT' '5432'
$dbUser=EnvOrDefault 'DB_USER' 'postgres'
$dbName=EnvOrDefault 'DB_NAME' 'imc_clarodoro'
$script:dbHost=$dbHost; $script:dbPort=$dbPort; $script:dbUser=$dbUser; $script:dbName=$dbName
$script:results=$results
$script:psql='C:\Program Files\PostgreSQL\18\bin\psql.exe'

Write-Host ''
Write-Host '==============================================' -ForegroundColor Cyan
Write-Host ' P0-A.3-C — STUDENTS UPDATE API TEST' -ForegroundColor Cyan
Write-Host '==============================================' -ForegroundColor Cyan

# 1 PostgreSQL
Write-Host 'Test 1: Vérification PostgreSQL...' -ForegroundColor Yellow
if (!(Test-Path $script:psql)) { Result 'postgresql' 'FAIL' 'psql.exe introuvable' }
elseif ([string]::IsNullOrWhiteSpace($env:DB_PASSWORD)) { Result 'postgresql' 'FAIL' 'DB_PASSWORD non défini pour psql' }
else {
    try { $r=Psql 'SELECT 1;'; if ($r.Code -eq 0) { Result 'postgresql' 'PASS' 'PostgreSQL accessible' } else { Result 'postgresql' 'FAIL' "psql code $($r.Code): $($r.Output -join ' ')" } }
    catch { Result 'postgresql' 'FAIL' $_.Exception.Message }
}

# 2 Endpoint: unauthenticated 401/403 proves route exists and is protected
Write-Host 'Test 2: Vérification endpoint...' -ForegroundColor Yellow
try {
    $r=Invoke-WebRequest -Uri "$baseUrl/api/students/index.php" -Method GET -UseBasicParsing -ErrorAction Stop
    if ($r.StatusCode -in @(200,401,403)) { Result 'endpoint' 'PASS' "Endpoint présent — HTTP $($r.StatusCode)" } else { Result 'endpoint' 'FAIL' "Statut HTTP $($r.StatusCode)" }
} catch {
    $s=StatusOf $_
    if ($s -in @(401,403)) { Result 'endpoint' 'PASS' "Endpoint présent et protégé — HTTP $s" } else { Result 'endpoint' 'FAIL' "Statut inattendu $s" }
}

# 3 Login + create test student
Write-Host 'Test 3: Création étudiant de test...' -ForegroundColor Yellow
$stamp=[DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
$testMatricule="P0-A3C-$stamp"
$session=$null
try {
    if ([string]::IsNullOrWhiteSpace($env:PDG_PASSWORD)) { throw 'PDG_PASSWORD non défini' }
    $login=@{username='pdg';password=$env:PDG_PASSWORD}|ConvertTo-Json -Compress
    $lr=Invoke-RestMethod -Uri "$baseUrl/api/auth/login.php" -Method POST -ContentType 'application/json' -Body $login -SessionVariable session -ErrorAction Stop
    if (!$lr.success) { throw 'Login PDG échoué' }
    Result 'login_pdg' 'PASS' 'Login PDG'
    $data=@{matricule=$testMatricule;last_name='Test';first_name='Student';date_of_birth='2010-01-15';sex='M';address='Test address';phone='00000000';status='ACTIVE'}|ConvertTo-Json -Compress
    $cr=Invoke-RestMethod -Uri "$baseUrl/api/students/index.php" -Method POST -ContentType 'application/json' -Body $data -WebSession $session -ErrorAction Stop
    if (!$cr.success -or !$cr.student) { throw 'Création étudiant échouée' }
    $testStudentId=$cr.student.id
    Result 'create_student' 'PASS' "Student créé, ID=$testStudentId"
} catch {
    if (!$results.ContainsKey('login_pdg')) { Result 'login_pdg' 'FAIL' $_.Exception.Message }
    Result 'create_student' 'FAIL' $_.Exception.Message
}

# 4 PUT without session
Write-Host 'Test 4: PUT sans session...' -ForegroundColor Yellow
ExpectStatus 'put_sans_session' { Invoke-RestMethod -Uri "$baseUrl/api/students/index.php?id=$testStudentId" -Method PUT -ContentType 'application/json' -Body '{}' -ErrorAction Stop } 401

# 5 Explicit re-login
Write-Host 'Test 5: Re-login PDG...' -ForegroundColor Yellow
try {
    $session=$null
    $login=@{username='pdg';password=$env:PDG_PASSWORD}|ConvertTo-Json -Compress
    $lr=Invoke-RestMethod -Uri "$baseUrl/api/auth/login.php" -Method POST -ContentType 'application/json' -Body $login -SessionVariable session -ErrorAction Stop
    if ($lr.success -and $session) { Result 'relogin_pdg' 'PASS' 'Re-login PDG' } else { Result 'relogin_pdg' 'FAIL' 'Re-login échoué';$session=$null }
} catch { Result 'relogin_pdg' 'FAIL' $_.Exception.Message;$session=$null }

# 6 PUT valid
Write-Host 'Test 6: PUT valide...' -ForegroundColor Yellow
try {
    $d=@{matricule=$testMatricule;last_name='Updated';first_name='Student';date_of_birth='2010-01-15';sex='M';address='Updated address';phone='11111111';status='ACTIVE'}|ConvertTo-Json -Compress
    $r=Invoke-RestMethod -Uri "$baseUrl/api/students/index.php?id=$testStudentId" -Method PUT -ContentType 'application/json' -Body $d -WebSession $session -ErrorAction Stop
    if ($r.success -and $r.student) { Result 'put_valide' 'PASS' 'HTTP 200, données mises à jour' } else { Result 'put_valide' 'FAIL' 'Réponse incorrecte' }
} catch { Result 'put_valide' 'FAIL' $_.Exception.Message }

# 7 verify PUT
Write-Host 'Test 7: Vérification PUT via GET...' -ForegroundColor Yellow
try {
    $r=Invoke-RestMethod -Uri "$baseUrl/api/students/index.php" -WebSession $session -ErrorAction Stop
    $s=$r.students|Where-Object {$_.id -eq $testStudentId}
    if ($s -and $s.last_name -eq 'Updated' -and $s.address -eq 'Updated address') { Result 'put_verification' 'PASS' 'Données mises à jour en base' } else { Result 'put_verification' 'FAIL' 'Données non conformes' }
} catch { Result 'put_verification' 'FAIL' $_.Exception.Message }

# 8 PATCH partial
Write-Host 'Test 8: PATCH partiel...' -ForegroundColor Yellow
try {
    $d=@{phone='99999999'}|ConvertTo-Json -Compress
    $r=Invoke-RestMethod -Uri "$baseUrl/api/students/index.php?id=$testStudentId" -Method PATCH -ContentType 'application/json' -Body $d -WebSession $session -ErrorAction Stop
    if ($r.success -and $r.student) { Result 'patch_valide' 'PASS' 'HTTP 200, PATCH partiel' } else { Result 'patch_valide' 'FAIL' 'Réponse incorrecte' }
} catch { Result 'patch_valide' 'FAIL' $_.Exception.Message }

# 9 PATCH preservation
Write-Host 'Test 9: Vérification PATCH préservation...' -ForegroundColor Yellow
try {
    $r=Invoke-RestMethod -Uri "$baseUrl/api/students/index.php" -WebSession $session -ErrorAction Stop
    $s=$r.students|Where-Object {$_.id -eq $testStudentId}
    if ($s -and $s.phone -eq '99999999' -and $s.last_name -eq 'Updated') { Result 'patch_preservation' 'PASS' 'Phone modifié, autres champs préservés' } else { Result 'patch_preservation' 'FAIL' 'Préservation échouée' }
} catch { Result 'patch_preservation' 'FAIL' $_.Exception.Message }

# 10-18 expected statuses
Write-Host 'Test 10: UUID invalide...' -ForegroundColor Yellow
ExpectStatus 'uuid_invalide' { Invoke-RestMethod -Uri "$baseUrl/api/students/index.php?id=invalid-uuid" -Method PUT -ContentType 'application/json' -Body '{}' -WebSession $session -ErrorAction Stop } 400
Write-Host 'Test 11: Étudiant inexistant...' -ForegroundColor Yellow
ExpectStatus 'student_inexistant' { Invoke-RestMethod -Uri "$baseUrl/api/students/index.php?id=00000000-0000-0000-0000-000000000000" -Method PUT -ContentType 'application/json' -Body '{"matricule":"test","last_name":"test","first_name":"test"}' -WebSession $session -ErrorAction Stop } 404
Write-Host 'Test 12: JSON invalide...' -ForegroundColor Yellow
ExpectStatus 'json_invalide' { Invoke-RestMethod -Uri "$baseUrl/api/students/index.php?id=$testStudentId" -Method PUT -ContentType 'application/json' -Body '{"invalid": json}' -WebSession $session -ErrorAction Stop } 400
Write-Host 'Test 13: PUT sans matricule...' -ForegroundColor Yellow
ExpectStatus 'put_sans_matricule' { Invoke-RestMethod -Uri "$baseUrl/api/students/index.php?id=$testStudentId" -Method PUT -ContentType 'application/json' -Body '{"last_name":"test","first_name":"test"}' -WebSession $session -ErrorAction Stop } 422
Write-Host 'Test 14: Champ inconnu...' -ForegroundColor Yellow
ExpectStatus 'champ_inconnu' { Invoke-RestMethod -Uri "$baseUrl/api/students/index.php?id=$testStudentId" -Method PATCH -ContentType 'application/json' -Body '{"unknown_field":"value"}' -WebSession $session -ErrorAction Stop } 422
Write-Host 'Test 15: id dans JSON...' -ForegroundColor Yellow
ExpectStatus 'id_in_json' { Invoke-RestMethod -Uri "$baseUrl/api/students/index.php?id=$testStudentId" -Method PATCH -ContentType 'application/json' -Body '{"id":"some-id"}' -WebSession $session -ErrorAction Stop } 422
Write-Host 'Test 16: created_at dans JSON...' -ForegroundColor Yellow
ExpectStatus 'created_at_in_json' { Invoke-RestMethod -Uri "$baseUrl/api/students/index.php?id=$testStudentId" -Method PATCH -ContentType 'application/json' -Body '{"created_at":"2020-01-01"}' -WebSession $session -ErrorAction Stop } 422
Write-Host 'Test 17: updated_at dans JSON...' -ForegroundColor Yellow
ExpectStatus 'updated_at_in_json' { Invoke-RestMethod -Uri "$baseUrl/api/students/index.php?id=$testStudentId" -Method PATCH -ContentType 'application/json' -Body '{"updated_at":"2020-01-01"}' -WebSession $session -ErrorAction Stop } 422
Write-Host 'Test 18: Status invalide...' -ForegroundColor Yellow
ExpectStatus 'status_invalide' { Invoke-RestMethod -Uri "$baseUrl/api/students/index.php?id=$testStudentId" -Method PATCH -ContentType 'application/json' -Body '{"status":"INVALID"}' -WebSession $session -ErrorAction Stop } 422

# 19 Matricule conflict — ConvertTo-Json, guaranteed targeted cleanup
Write-Host 'Test 19: Conflit matricule...' -ForegroundColor Yellow
$conflictMatricule="P0-A3C-CONFLICT-$([DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds())"
try {
    $d=@{matricule=$conflictMatricule;last_name='Conflict';first_name='Student'}|ConvertTo-Json -Compress
    $cr=Invoke-RestMethod -Uri "$baseUrl/api/students/index.php" -Method POST -ContentType 'application/json' -Body $d -WebSession $session -ErrorAction Stop
    if (!$cr.success -or !$cr.student) { throw 'Création conflit échouée' }
    $conflictStudentId=$cr.student.id
    $patch=@{matricule=$conflictMatricule}|ConvertTo-Json -Compress
    try {
        Invoke-RestMethod -Uri "$baseUrl/api/students/index.php?id=$testStudentId" -Method PATCH -ContentType 'application/json' -Body $patch -WebSession $session -ErrorAction Stop | Out-Null
        Result 'conflit_matricule' 'FAIL' 'Devrait retourner HTTP 409'
    } catch {
        $s=StatusOf $_
        if ($s -eq 409) {
            $body = ''
            try {
                $resp = $_.Exception.Response
                if ($resp) {
                    $reader = New-Object System.IO.StreamReader($resp.GetResponseStream())
                    $body = $reader.ReadToEnd()
                    $reader.Dispose()
                }
            } catch {}
            if ($body -match 'Matricule déjà utilisé') { Result 'conflit_matricule' 'PASS' 'HTTP 409 + message de conflit confirmé' }
            else { Result 'conflit_matricule' 'FAIL' "HTTP 409 mais body inattendu: $body" }
        } else { Result 'conflit_matricule' 'FAIL' "Statut inattendu $s" }
    }
} catch { Result 'conflit_matricule' 'FAIL' $_.Exception.Message }
finally {
    if ($conflictStudentId) {
        try {
            $r=Psql "DELETE FROM students WHERE id = '$conflictStudentId';"
            if ($r.Code -ne 0) { Write-Host "AVERTISSEMENT cleanup conflit: $($r.Output -join ' ')" -ForegroundColor Yellow }
        } catch { Write-Host "AVERTISSEMENT cleanup conflit: $($_.Exception.Message)" -ForegroundColor Yellow }
        $conflictStudentId=$null
    }
}

# 20 JSON spoof
Write-Host 'Test 20: Spoof JSON role/permission...' -ForegroundColor Yellow
ExpectStatus 'spoof_json' { Invoke-RestMethod -Uri "$baseUrl/api/students/index.php?id=$testStudentId" -Method PATCH -ContentType 'application/json' -Body '{"role":"PDG","permission":"eleves.update","phone":"12345"}' -WebSession $session -ErrorAction Stop } 422

# 21 X-Role
Write-Host 'Test 21: X-Role header...' -ForegroundColor Yellow
try {
    $r=Invoke-RestMethod -Uri "$baseUrl/api/students/index.php?id=$testStudentId" -Method PATCH -ContentType 'application/json' -Body '{"phone":"54321"}' -Headers @{'X-Role'='Autre'} -WebSession $session -ErrorAction Stop
    if ($r.success) { Result 'x_role_header' 'PASS' 'X-Role ignoré' } else { Result 'x_role_header' 'FAIL' 'Réponse incorrecte' }
} catch { Result 'x_role_header' 'FAIL' $_.Exception.Message }

# 22 X-Permission
Write-Host 'Test 22: X-Permission header...' -ForegroundColor Yellow
try {
    $r=Invoke-RestMethod -Uri "$baseUrl/api/students/index.php?id=$testStudentId" -Method PATCH -ContentType 'application/json' -Body '{"phone":"54321"}' -Headers @{'X-Permission'='false'} -WebSession $session -ErrorAction Stop
    if ($r.success) { Result 'x_permission_header' 'PASS' 'X-Permission ignoré' } else { Result 'x_permission_header' 'FAIL' 'Réponse incorrecte' }
} catch { Result 'x_permission_header' 'FAIL' $_.Exception.Message }

# 23 logout
Write-Host 'Test 23: LOGOUT...' -ForegroundColor Yellow
try {
    $r=Invoke-RestMethod -Uri "$baseUrl/api/auth/logout.php" -Method POST -WebSession $session -ErrorAction Stop
    if ($r.success) { Result 'logout' 'PASS' 'Logout réussi' } else { Result 'logout' 'FAIL' 'Logout échoué' }
} catch { Result 'logout' 'FAIL' $_.Exception.Message }

# 24-25 after logout
Write-Host 'Test 24: PUT après logout...' -ForegroundColor Yellow
ExpectStatus 'put_apres_logout' { Invoke-RestMethod -Uri "$baseUrl/api/students/index.php?id=$testStudentId" -Method PUT -ContentType 'application/json' -Body '{"matricule":"test","last_name":"test","first_name":"test"}' -WebSession $session -ErrorAction Stop } 401
Write-Host 'Test 25: PATCH après logout...' -ForegroundColor Yellow
ExpectStatus 'patch_apres_logout' { Invoke-RestMethod -Uri "$baseUrl/api/students/index.php?id=$testStudentId" -Method PATCH -ContentType 'application/json' -Body '{"phone":"12345"}' -WebSession $session -ErrorAction Stop } 401

# 26 targeted cleanup
Write-Host 'Test 26: Nettoyage étudiant de test...' -ForegroundColor Yellow
if ($testStudentId) {
    try {
        $r=Psql "DELETE FROM students WHERE id = '$testStudentId';"
        if ($r.Code -eq 0) { Result 'cleanup' 'PASS' 'Étudiant de test supprimé' } else { Result 'cleanup' 'FAIL' "DELETE échoué: $($r.Output -join ' ')" }
    } catch { Result 'cleanup' 'FAIL' $_.Exception.Message }
} else { Result 'cleanup' 'FAIL' 'Aucun étudiant de test à nettoyer' }

Remove-Item Env:PDG_PASSWORD -ErrorAction SilentlyContinue

Write-Host ''
Write-Host '==============================================' -ForegroundColor Cyan
Write-Host ' RÉSUMÉ P0-A.3-C' -ForegroundColor Cyan
Write-Host '==============================================' -ForegroundColor Cyan
$labels=@(
 @('PostgreSQL accessible','postgresql'),@('Endpoint accessible','endpoint'),@('LOGIN PDG','login_pdg'),
 @('Création étudiant','create_student'),@('PUT sans session','put_sans_session'),@('Re-login PDG','relogin_pdg'),
 @('PUT valide','put_valide'),@('Vérification PUT','put_verification'),@('PATCH valide','patch_valide'),
 @('Préservation PATCH','patch_preservation'),@('UUID invalide','uuid_invalide'),@('Étudiant inexistant','student_inexistant'),
 @('JSON invalide','json_invalide'),@('PUT sans matricule','put_sans_matricule'),@('Champ inconnu','champ_inconnu'),
 @('id dans JSON','id_in_json'),@('created_at dans JSON','created_at_in_json'),@('updated_at dans JSON','updated_at_in_json'),
 @('Status invalide','status_invalide'),@('Conflit matricule','conflit_matricule'),@('Spoof JSON role/permission','spoof_json'),
 @('X-Role header','x_role_header'),@('X-Permission header','x_permission_header'),@('LOGOUT','logout'),
 @('PUT après logout','put_apres_logout'),@('PATCH après logout','patch_apres_logout'),@('CLEANUP','cleanup')
)
foreach($x in $labels){$v=if($results.ContainsKey($x[1])){$results[$x[1]]}else{'FAIL'};Write-Host ("{0,-34}: {1}" -f $x[0],$v)}
$failed=$results.Values|Where-Object {$_ -eq 'FAIL'}
Write-Host ''
if($failed){Write-Host 'RESULT : FAIL' -ForegroundColor Red;exit 1}
Write-Host 'RESULT : PASS' -ForegroundColor Green
exit 0
) { continue }
        if ($null -ne [Environment]::GetEnvironmentVariable($name, 'Process')) { continue }
        if ($value.Length -ge 2 -and (($value.StartsWith('"') -and $value.EndsWith('"')) -or ($value.StartsWith("'") -and $value.EndsWith("'")))) { $value = $value.Substring(1, $value.Length - 2) }
        [Environment]::SetEnvironmentVariable($name, $value, 'Process')
    }
}
function EnvOrDefault([string]$Name,[string]$Default) {
    $v = [Environment]::GetEnvironmentVariable($Name)
    if ([string]::IsNullOrWhiteSpace($v)) { return $Default }
    return $v
}
function StatusOf($e) {
    try { if ($e.Exception.Response.StatusCode) { return [int]$e.Exception.Response.StatusCode.value__ } } catch {}
    return $null
}
function Result([string]$Key,[string]$Value,[string]$Message) {
    $script:results[$Key] = $Value
    $c = if ($Value -eq 'PASS') {'Green'} elseif ($Value -eq 'SKIP') {'Yellow'} else {'Red'}
    Write-Host "${Value}: $Message" -ForegroundColor $c
}
function Psql([string]$Sql) {
    if ([string]::IsNullOrWhiteSpace($env:DB_PASSWORD)) { throw 'DB_PASSWORD non défini pour psql' }
    $old = $env:PGPASSWORD
    $env:PGPASSWORD = $env:DB_PASSWORD
    try {
        $out = & $script:psql -h $script:dbHost -p $script:dbPort -U $script:dbUser -d $script:dbName -c $Sql 2>&1
        return [pscustomobject]@{ Code=$LASTEXITCODE; Output=$out }
    } finally {
        if ($null -eq $old) { Remove-Item Env:PGPASSWORD -ErrorAction SilentlyContinue } else { $env:PGPASSWORD=$old }
    }
}
function ExpectStatus([string]$Key,[scriptblock]$Action,[int]$Expected) {
    try { & $Action | Out-Null; Result $Key 'FAIL' "Devrait retourner HTTP $Expected" }
    catch {
        $s=StatusOf $_
        if ($s -eq $Expected) { Result $Key 'PASS' "HTTP $Expected retourné" } else { Result $Key 'FAIL' "Statut inattendu $s" }
    }
}

$baseUrl='http://127.0.0.1:8090'
$results=@{}
$testStudentId=$null
$conflictStudentId=$null
$dbHost=EnvOrDefault 'DB_HOST' '127.0.0.1'
$dbPort=EnvOrDefault 'DB_PORT' '5432'
$dbUser=EnvOrDefault 'DB_USER' 'postgres'
$dbName=EnvOrDefault 'DB_NAME' 'imc_clarodoro'
$script:dbHost=$dbHost; $script:dbPort=$dbPort; $script:dbUser=$dbUser; $script:dbName=$dbName
$script:results=$results
$script:psql='C:\Program Files\PostgreSQL\18\bin\psql.exe'

Write-Host ''
Write-Host '==============================================' -ForegroundColor Cyan
Write-Host ' P0-A.3-C — STUDENTS UPDATE API TEST' -ForegroundColor Cyan
Write-Host '==============================================' -ForegroundColor Cyan

# 1 PostgreSQL
Write-Host 'Test 1: Vérification PostgreSQL...' -ForegroundColor Yellow
if (!(Test-Path $script:psql)) { Result 'postgresql' 'FAIL' 'psql.exe introuvable' }
elseif ([string]::IsNullOrWhiteSpace($env:DB_PASSWORD)) { Result 'postgresql' 'FAIL' 'DB_PASSWORD non défini pour psql' }
else {
    try { $r=Psql 'SELECT 1;'; if ($r.Code -eq 0) { Result 'postgresql' 'PASS' 'PostgreSQL accessible' } else { Result 'postgresql' 'FAIL' "psql code $($r.Code): $($r.Output -join ' ')" } }
    catch { Result 'postgresql' 'FAIL' $_.Exception.Message }
}

# 2 Endpoint: unauthenticated 401/403 proves route exists and is protected
Write-Host 'Test 2: Vérification endpoint...' -ForegroundColor Yellow
try {
    $r=Invoke-WebRequest -Uri "$baseUrl/api/students/index.php" -Method GET -UseBasicParsing -ErrorAction Stop
    if ($r.StatusCode -in @(200,401,403)) { Result 'endpoint' 'PASS' "Endpoint présent — HTTP $($r.StatusCode)" } else { Result 'endpoint' 'FAIL' "Statut HTTP $($r.StatusCode)" }
} catch {
    $s=StatusOf $_
    if ($s -in @(401,403)) { Result 'endpoint' 'PASS' "Endpoint présent et protégé — HTTP $s" } else { Result 'endpoint' 'FAIL' "Statut inattendu $s" }
}

# 3 Login + create test student
Write-Host 'Test 3: Création étudiant de test...' -ForegroundColor Yellow
$stamp=[DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
$testMatricule="P0-A3C-$stamp"
$session=$null
try {
    if ([string]::IsNullOrWhiteSpace($env:PDG_PASSWORD)) { throw 'PDG_PASSWORD non défini' }
    $login=@{username='pdg';password=$env:PDG_PASSWORD}|ConvertTo-Json -Compress
    $lr=Invoke-RestMethod -Uri "$baseUrl/api/auth/login.php" -Method POST -ContentType 'application/json' -Body $login -SessionVariable session -ErrorAction Stop
    if (!$lr.success) { throw 'Login PDG échoué' }
    Result 'login_pdg' 'PASS' 'Login PDG'
    $data=@{matricule=$testMatricule;last_name='Test';first_name='Student';date_of_birth='2010-01-15';sex='M';address='Test address';phone='00000000';status='ACTIVE'}|ConvertTo-Json -Compress
    $cr=Invoke-RestMethod -Uri "$baseUrl/api/students/index.php" -Method POST -ContentType 'application/json' -Body $data -WebSession $session -ErrorAction Stop
    if (!$cr.success -or !$cr.student) { throw 'Création étudiant échouée' }
    $testStudentId=$cr.student.id
    Result 'create_student' 'PASS' "Student créé, ID=$testStudentId"
} catch {
    if (!$results.ContainsKey('login_pdg')) { Result 'login_pdg' 'FAIL' $_.Exception.Message }
    Result 'create_student' 'FAIL' $_.Exception.Message
}

# 4 PUT without session
Write-Host 'Test 4: PUT sans session...' -ForegroundColor Yellow
ExpectStatus 'put_sans_session' { Invoke-RestMethod -Uri "$baseUrl/api/students/index.php?id=$testStudentId" -Method PUT -ContentType 'application/json' -Body '{}' -ErrorAction Stop } 401

# 5 Explicit re-login
Write-Host 'Test 5: Re-login PDG...' -ForegroundColor Yellow
try {
    $session=$null
    $login=@{username='pdg';password=$env:PDG_PASSWORD}|ConvertTo-Json -Compress
    $lr=Invoke-RestMethod -Uri "$baseUrl/api/auth/login.php" -Method POST -ContentType 'application/json' -Body $login -SessionVariable session -ErrorAction Stop
    if ($lr.success -and $session) { Result 'relogin_pdg' 'PASS' 'Re-login PDG' } else { Result 'relogin_pdg' 'FAIL' 'Re-login échoué';$session=$null }
} catch { Result 'relogin_pdg' 'FAIL' $_.Exception.Message;$session=$null }

# 6 PUT valid
Write-Host 'Test 6: PUT valide...' -ForegroundColor Yellow
try {
    $d=@{matricule=$testMatricule;last_name='Updated';first_name='Student';date_of_birth='2010-01-15';sex='M';address='Updated address';phone='11111111';status='ACTIVE'}|ConvertTo-Json -Compress
    $r=Invoke-RestMethod -Uri "$baseUrl/api/students/index.php?id=$testStudentId" -Method PUT -ContentType 'application/json' -Body $d -WebSession $session -ErrorAction Stop
    if ($r.success -and $r.student) { Result 'put_valide' 'PASS' 'HTTP 200, données mises à jour' } else { Result 'put_valide' 'FAIL' 'Réponse incorrecte' }
} catch { Result 'put_valide' 'FAIL' $_.Exception.Message }

# 7 verify PUT
Write-Host 'Test 7: Vérification PUT via GET...' -ForegroundColor Yellow
try {
    $r=Invoke-RestMethod -Uri "$baseUrl/api/students/index.php" -WebSession $session -ErrorAction Stop
    $s=$r.students|Where-Object {$_.id -eq $testStudentId}
    if ($s -and $s.last_name -eq 'Updated' -and $s.address -eq 'Updated address') { Result 'put_verification' 'PASS' 'Données mises à jour en base' } else { Result 'put_verification' 'FAIL' 'Données non conformes' }
} catch { Result 'put_verification' 'FAIL' $_.Exception.Message }

# 8 PATCH partial
Write-Host 'Test 8: PATCH partiel...' -ForegroundColor Yellow
try {
    $d=@{phone='99999999'}|ConvertTo-Json -Compress
    $r=Invoke-RestMethod -Uri "$baseUrl/api/students/index.php?id=$testStudentId" -Method PATCH -ContentType 'application/json' -Body $d -WebSession $session -ErrorAction Stop
    if ($r.success -and $r.student) { Result 'patch_valide' 'PASS' 'HTTP 200, PATCH partiel' } else { Result 'patch_valide' 'FAIL' 'Réponse incorrecte' }
} catch { Result 'patch_valide' 'FAIL' $_.Exception.Message }

# 9 PATCH preservation
Write-Host 'Test 9: Vérification PATCH préservation...' -ForegroundColor Yellow
try {
    $r=Invoke-RestMethod -Uri "$baseUrl/api/students/index.php" -WebSession $session -ErrorAction Stop
    $s=$r.students|Where-Object {$_.id -eq $testStudentId}
    if ($s -and $s.phone -eq '99999999' -and $s.last_name -eq 'Updated') { Result 'patch_preservation' 'PASS' 'Phone modifié, autres champs préservés' } else { Result 'patch_preservation' 'FAIL' 'Préservation échouée' }
} catch { Result 'patch_preservation' 'FAIL' $_.Exception.Message }

# 10-18 expected statuses
Write-Host 'Test 10: UUID invalide...' -ForegroundColor Yellow
ExpectStatus 'uuid_invalide' { Invoke-RestMethod -Uri "$baseUrl/api/students/index.php?id=invalid-uuid" -Method PUT -ContentType 'application/json' -Body '{}' -WebSession $session -ErrorAction Stop } 400
Write-Host 'Test 11: Étudiant inexistant...' -ForegroundColor Yellow
ExpectStatus 'student_inexistant' { Invoke-RestMethod -Uri "$baseUrl/api/students/index.php?id=00000000-0000-0000-0000-000000000000" -Method PUT -ContentType 'application/json' -Body '{"matricule":"test","last_name":"test","first_name":"test"}' -WebSession $session -ErrorAction Stop } 404
Write-Host 'Test 12: JSON invalide...' -ForegroundColor Yellow
ExpectStatus 'json_invalide' { Invoke-RestMethod -Uri "$baseUrl/api/students/index.php?id=$testStudentId" -Method PUT -ContentType 'application/json' -Body '{"invalid": json}' -WebSession $session -ErrorAction Stop } 400
Write-Host 'Test 13: PUT sans matricule...' -ForegroundColor Yellow
ExpectStatus 'put_sans_matricule' { Invoke-RestMethod -Uri "$baseUrl/api/students/index.php?id=$testStudentId" -Method PUT -ContentType 'application/json' -Body '{"last_name":"test","first_name":"test"}' -WebSession $session -ErrorAction Stop } 422
Write-Host 'Test 14: Champ inconnu...' -ForegroundColor Yellow
ExpectStatus 'champ_inconnu' { Invoke-RestMethod -Uri "$baseUrl/api/students/index.php?id=$testStudentId" -Method PATCH -ContentType 'application/json' -Body '{"unknown_field":"value"}' -WebSession $session -ErrorAction Stop } 422
Write-Host 'Test 15: id dans JSON...' -ForegroundColor Yellow
ExpectStatus 'id_in_json' { Invoke-RestMethod -Uri "$baseUrl/api/students/index.php?id=$testStudentId" -Method PATCH -ContentType 'application/json' -Body '{"id":"some-id"}' -WebSession $session -ErrorAction Stop } 422
Write-Host 'Test 16: created_at dans JSON...' -ForegroundColor Yellow
ExpectStatus 'created_at_in_json' { Invoke-RestMethod -Uri "$baseUrl/api/students/index.php?id=$testStudentId" -Method PATCH -ContentType 'application/json' -Body '{"created_at":"2020-01-01"}' -WebSession $session -ErrorAction Stop } 422
Write-Host 'Test 17: updated_at dans JSON...' -ForegroundColor Yellow
ExpectStatus 'updated_at_in_json' { Invoke-RestMethod -Uri "$baseUrl/api/students/index.php?id=$testStudentId" -Method PATCH -ContentType 'application/json' -Body '{"updated_at":"2020-01-01"}' -WebSession $session -ErrorAction Stop } 422
Write-Host 'Test 18: Status invalide...' -ForegroundColor Yellow
ExpectStatus 'status_invalide' { Invoke-RestMethod -Uri "$baseUrl/api/students/index.php?id=$testStudentId" -Method PATCH -ContentType 'application/json' -Body '{"status":"INVALID"}' -WebSession $session -ErrorAction Stop } 422

# 19 Matricule conflict — ConvertTo-Json, guaranteed targeted cleanup
Write-Host 'Test 19: Conflit matricule...' -ForegroundColor Yellow
$conflictMatricule="P0-A3C-CONFLICT-$([DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds())"
try {
    $d=@{matricule=$conflictMatricule;last_name='Conflict';first_name='Student'}|ConvertTo-Json -Compress
    $cr=Invoke-RestMethod -Uri "$baseUrl/api/students/index.php" -Method POST -ContentType 'application/json' -Body $d -WebSession $session -ErrorAction Stop
    if (!$cr.success -or !$cr.student) { throw 'Création conflit échouée' }
    $conflictStudentId=$cr.student.id
    $patch=@{matricule=$conflictMatricule}|ConvertTo-Json -Compress
    try {
        Invoke-RestMethod -Uri "$baseUrl/api/students/index.php?id=$testStudentId" -Method PATCH -ContentType 'application/json' -Body $patch -WebSession $session -ErrorAction Stop | Out-Null
        Result 'conflit_matricule' 'FAIL' 'Devrait retourner HTTP 409'
    } catch {
        $s=StatusOf $_
        if ($s -eq 409) {
            $body = ''
            try {
                $resp = $_.Exception.Response
                if ($resp) {
                    $reader = New-Object System.IO.StreamReader($resp.GetResponseStream())
                    $body = $reader.ReadToEnd()
                    $reader.Dispose()
                }
            } catch {}
            if ($body -match 'Matricule déjà utilisé') { Result 'conflit_matricule' 'PASS' 'HTTP 409 + message de conflit confirmé' }
            else { Result 'conflit_matricule' 'FAIL' "HTTP 409 mais body inattendu: $body" }
        } else { Result 'conflit_matricule' 'FAIL' "Statut inattendu $s" }
    }
} catch { Result 'conflit_matricule' 'FAIL' $_.Exception.Message }
finally {
    if ($conflictStudentId) {
        try {
            $r=Psql "DELETE FROM students WHERE id = '$conflictStudentId';"
            if ($r.Code -ne 0) { Write-Host "AVERTISSEMENT cleanup conflit: $($r.Output -join ' ')" -ForegroundColor Yellow }
        } catch { Write-Host "AVERTISSEMENT cleanup conflit: $($_.Exception.Message)" -ForegroundColor Yellow }
        $conflictStudentId=$null
    }
}

# 20 JSON spoof
Write-Host 'Test 20: Spoof JSON role/permission...' -ForegroundColor Yellow
ExpectStatus 'spoof_json' { Invoke-RestMethod -Uri "$baseUrl/api/students/index.php?id=$testStudentId" -Method PATCH -ContentType 'application/json' -Body '{"role":"PDG","permission":"eleves.update","phone":"12345"}' -WebSession $session -ErrorAction Stop } 422

# 21 X-Role
Write-Host 'Test 21: X-Role header...' -ForegroundColor Yellow
try {
    $r=Invoke-RestMethod -Uri "$baseUrl/api/students/index.php?id=$testStudentId" -Method PATCH -ContentType 'application/json' -Body '{"phone":"54321"}' -Headers @{'X-Role'='Autre'} -WebSession $session -ErrorAction Stop
    if ($r.success) { Result 'x_role_header' 'PASS' 'X-Role ignoré' } else { Result 'x_role_header' 'FAIL' 'Réponse incorrecte' }
} catch { Result 'x_role_header' 'FAIL' $_.Exception.Message }

# 22 X-Permission
Write-Host 'Test 22: X-Permission header...' -ForegroundColor Yellow
try {
    $r=Invoke-RestMethod -Uri "$baseUrl/api/students/index.php?id=$testStudentId" -Method PATCH -ContentType 'application/json' -Body '{"phone":"54321"}' -Headers @{'X-Permission'='false'} -WebSession $session -ErrorAction Stop
    if ($r.success) { Result 'x_permission_header' 'PASS' 'X-Permission ignoré' } else { Result 'x_permission_header' 'FAIL' 'Réponse incorrecte' }
} catch { Result 'x_permission_header' 'FAIL' $_.Exception.Message }

# 23 logout
Write-Host 'Test 23: LOGOUT...' -ForegroundColor Yellow
try {
    $r=Invoke-RestMethod -Uri "$baseUrl/api/auth/logout.php" -Method POST -WebSession $session -ErrorAction Stop
    if ($r.success) { Result 'logout' 'PASS' 'Logout réussi' } else { Result 'logout' 'FAIL' 'Logout échoué' }
} catch { Result 'logout' 'FAIL' $_.Exception.Message }

# 24-25 after logout
Write-Host 'Test 24: PUT après logout...' -ForegroundColor Yellow
ExpectStatus 'put_apres_logout' { Invoke-RestMethod -Uri "$baseUrl/api/students/index.php?id=$testStudentId" -Method PUT -ContentType 'application/json' -Body '{"matricule":"test","last_name":"test","first_name":"test"}' -WebSession $session -ErrorAction Stop } 401
Write-Host 'Test 25: PATCH après logout...' -ForegroundColor Yellow
ExpectStatus 'patch_apres_logout' { Invoke-RestMethod -Uri "$baseUrl/api/students/index.php?id=$testStudentId" -Method PATCH -ContentType 'application/json' -Body '{"phone":"12345"}' -WebSession $session -ErrorAction Stop } 401

# 26 targeted cleanup
Write-Host 'Test 26: Nettoyage étudiant de test...' -ForegroundColor Yellow
if ($testStudentId) {
    try {
        $r=Psql "DELETE FROM students WHERE id = '$testStudentId';"
        if ($r.Code -eq 0) { Result 'cleanup' 'PASS' 'Étudiant de test supprimé' } else { Result 'cleanup' 'FAIL' "DELETE échoué: $($r.Output -join ' ')" }
    } catch { Result 'cleanup' 'FAIL' $_.Exception.Message }
} else { Result 'cleanup' 'FAIL' 'Aucun étudiant de test à nettoyer' }

Remove-Item Env:PDG_PASSWORD -ErrorAction SilentlyContinue

Write-Host ''
Write-Host '==============================================' -ForegroundColor Cyan
Write-Host ' RÉSUMÉ P0-A.3-C' -ForegroundColor Cyan
Write-Host '==============================================' -ForegroundColor Cyan
$labels=@(
 @('PostgreSQL accessible','postgresql'),@('Endpoint accessible','endpoint'),@('LOGIN PDG','login_pdg'),
 @('Création étudiant','create_student'),@('PUT sans session','put_sans_session'),@('Re-login PDG','relogin_pdg'),
 @('PUT valide','put_valide'),@('Vérification PUT','put_verification'),@('PATCH valide','patch_valide'),
 @('Préservation PATCH','patch_preservation'),@('UUID invalide','uuid_invalide'),@('Étudiant inexistant','student_inexistant'),
 @('JSON invalide','json_invalide'),@('PUT sans matricule','put_sans_matricule'),@('Champ inconnu','champ_inconnu'),
 @('id dans JSON','id_in_json'),@('created_at dans JSON','created_at_in_json'),@('updated_at dans JSON','updated_at_in_json'),
 @('Status invalide','status_invalide'),@('Conflit matricule','conflit_matricule'),@('Spoof JSON role/permission','spoof_json'),
 @('X-Role header','x_role_header'),@('X-Permission header','x_permission_header'),@('LOGOUT','logout'),
 @('PUT après logout','put_apres_logout'),@('PATCH après logout','patch_apres_logout'),@('CLEANUP','cleanup')
)
foreach($x in $labels){$v=if($results.ContainsKey($x[1])){$results[$x[1]]}else{'FAIL'};Write-Host ("{0,-34}: {1}" -f $x[0],$v)}
$failed=$results.Values|Where-Object {$_ -eq 'FAIL'}
Write-Host ''
if($failed){Write-Host 'RESULT : FAIL' -ForegroundColor Red;exit 1}
Write-Host 'RESULT : PASS' -ForegroundColor Green
exit 0
