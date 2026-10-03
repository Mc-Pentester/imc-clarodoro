$ErrorActionPreference = "Stop"

$ProjectRoot = "C:\IMC-Clarodoro-securise-client\IMC-Clarodoro"
$PhpExe = "C:\PHP\8.2\php.exe"
$BindHost = "127.0.0.1"
$Port = 8090
$BaseUrl = "http://$BindHost`:$Port"
$AuditDir = Join-Path $ProjectRoot "audit"
$ReportFile = Join-Path $AuditDir "ENV-05-PHP-BUILTIN-ARCH-01-VALIDATION-REPORT.md"
$FinalReport = Join-Path $AuditDir "ENV-05-PHP-BUILTIN-ARCH-01-VALIDATION-REPORT-FINAL.md"

$ApiEndpoints = @("/api/health.php", "/api/index.php", "/api/health-db.php")
$ServerProcess = $null
$StartedByScript = $false
$Results = New-Object System.Collections.Generic.List[object]

New-Item -ItemType Directory -Force -Path $AuditDir | Out-Null

function Add-Result {
    param([string]$Test, [string]$Status, [string]$Details)
    $Results.Add([PSCustomObject]@{Test = $Test; Status = $Status; Details = $Details})
}

function Mask-Secrets {
    param([string]$Text)
    if ($null -eq $Text) { return "" }
    $Masked = $Text
    $Masked = $Masked -replace '(?i)(password\s*[=:]\s*)[^&\s<"]+', '$1[REDACTED]'
    $Masked = $Masked -replace '(?i)(passwd\s*[=:]\s*)[^&\s<"]+', '$1[REDACTED]'
    $Masked = $Masked -replace '(?i)(secret\s*[=:]\s*)[^&\s<"]+', '$1[REDACTED]'
    $Masked = $Masked -replace '(?i)(token\s*[=:]\s*)[^&\s<"]+', '$1[REDACTED]'
    return $Masked
}

function Test-TcpPort {
    param([string]$TargetHost, [int]$Port)
    try {
        $Client = New-Object System.Net.Sockets.TcpClient
        $Async = $Client.BeginConnect($TargetHost, $Port, $null, $null)
        $Success = $Async.AsyncWaitHandle.WaitOne(500)
        if ($Success -and $Client.Connected) {
            $Client.Close()
            return $true
        }
        $Client.Close()
        return $false
    }
    catch { return $false }
}

function Invoke-Endpoint {
    param([string]$Endpoint)
    $Url = "$BaseUrl$Endpoint"
    $Started = Get-Date
    try {
        $Response = Invoke-WebRequest -Uri $Url -UseBasicParsing -TimeoutSec 15 -ErrorAction Stop
        $Elapsed = ((Get-Date) - $Started).TotalMilliseconds
        $Body = [string]$Response.Content
        if ($Body.Length -gt 5000) { $Body = $Body.Substring(0,5000) + "`n...[TRUNCATED]" }
        $Body = Mask-Secrets $Body
        return [PSCustomObject]@{Endpoint = $Endpoint; Url = $Url; HttpStatus = [int]$Response.StatusCode; ContentType = [string]$Response.Headers["Content-Type"]; Body = $Body; DurationMs = [math]::Round($Elapsed,2); Error = $null}
    }
    catch {
        $Elapsed = ((Get-Date) - $Started).TotalMilliseconds
        $StatusCode = $null
        $ResponseBody = ""
        if ($_.Exception.Response) {
            try { $StatusCode = [int]$_.Exception.Response.StatusCode } catch {}
            try {
                $Stream = $_.Exception.Response.GetResponseStream()
                if ($Stream) {
                    $Reader = New-Object System.IO.StreamReader($Stream)
                    $ResponseBody = $Reader.ReadToEnd()
                    $Reader.Dispose()
                    $Stream.Dispose()
                }
            } catch {}
        }
        $ResponseBody = Mask-Secrets $ResponseBody
        if ($ResponseBody.Length -gt 5000) { $ResponseBody = $ResponseBody.Substring(0,5000) + "`n...[TRUNCATED]" }
        return [PSCustomObject]@{Endpoint = $Endpoint; Url = $Url; HttpStatus = $StatusCode; ContentType = ""; Body = $ResponseBody; DurationMs = [math]::Round($Elapsed,2); Error = $_.Exception.Message}
    }
}

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host " ENV-05 - PHP BUILT-IN SERVER - ARCH-01 VALIDATION" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Project: $ProjectRoot"
Write-Host "PHP: $PhpExe"
Write-Host "URL: $BaseUrl"
Write-Host ""

if (Test-Path $ProjectRoot -PathType Container) {
    Add-Result "Project IMC-Clarodoro present" "PASS" $ProjectRoot
}
else {
    Add-Result "Project IMC-Clarodoro present" "BLOCKED" "Directory not found: $ProjectRoot"
    throw "Project not found."
}

if (Test-Path $PhpExe -PathType Leaf) {
    try {
        $PhpVersion = & $PhpExe -v 2>&1 | Select-Object -First 1
        Add-Result "PHP CLI available" "PASS" ([string]$PhpVersion)
    }
    catch {
        Add-Result "PHP CLI available" "BLOCKED" "PHP exists but cannot be executed: $($_.Exception.Message)"
        throw
    }
}
else {
    Add-Result "PHP CLI available" "BLOCKED" "Executable not found: $PhpExe"
    throw "PHP not found."
}

foreach ($Endpoint in $ApiEndpoints) {
    $RelativePath = $Endpoint.TrimStart("/") -replace "/", "\"
    $FilePath = Join-Path $ProjectRoot $RelativePath
    if (Test-Path $FilePath -PathType Leaf) {
        Add-Result "File $Endpoint" "PASS" $FilePath
    }
    else {
        Add-Result "File $Endpoint" "BLOCKED" "File not found: $FilePath"
    }
}

if (Test-TcpPort -TargetHost $BindHost -Port $Port) {
    Add-Result "Port TCP $Port available" "BLOCKED" "Port $Port is already in use."
    throw "Port $Port already in use."
}
else {
    Add-Result "Port TCP $Port available" "PASS" "Port $Port is free."
}

Write-Host ""
Write-Host "Starting PHP built-in server..." -ForegroundColor Yellow

$PhpArguments = @("-S", "$BindHost`:$Port")

try {
    $ServerProcess = Start-Process -FilePath $PhpExe -ArgumentList $PhpArguments -WorkingDirectory $ProjectRoot -PassThru -WindowStyle Hidden -RedirectStandardOutput (Join-Path $AuditDir "ENV-05-php-server.stdout.log") -RedirectStandardError (Join-Path $AuditDir "ENV-05-php-server.stderr.log")
    $StartedByScript = $true
    Add-Result "Start PHP Built-in Server" "PASS" "PID=$($ServerProcess.Id), listening on $BaseUrl"
}
catch {
    Add-Result "Start PHP Built-in Server" "BLOCKED" $_.Exception.Message
    throw
}

$ServerReady = $false
for ($i = 1; $i -le 30; $i++) {
    Start-Sleep -Milliseconds 500
    if (Test-TcpPort -TargetHost $BindHost -Port $Port) {
        $ServerReady = $true
        break
    }
    if ($ServerProcess.HasExited) { break }
}

if ($ServerReady) {
    Add-Result "PHP server accessible" "PASS" "$BaseUrl responds at TCP level."
}
else {
    $StdOutPath = Join-Path $AuditDir "ENV-05-php-server.stdout.log"
    $StdErrPath = Join-Path $AuditDir "ENV-05-php-server.stderr.log"
    $Diagnostics = @()
    if (Test-Path $StdOutPath) { $Diagnostics += Get-Content $StdOutPath -Raw }
    if (Test-Path $StdErrPath) { $Diagnostics += Get-Content $StdErrPath -Raw }
    $DiagnosticsText = Mask-Secrets (($Diagnostics -join "`n"))
    Add-Result "PHP server accessible" "BLOCKED" "PHP server did not become accessible.`n$DiagnosticsText"
    throw "PHP server inaccessible."
}

Write-Host ""
Write-Host "Validating HTTP endpoints..." -ForegroundColor Yellow
Write-Host ""

$HttpResults = New-Object System.Collections.Generic.List[object]

foreach ($Endpoint in $ApiEndpoints) {
    Write-Host "  -> $Endpoint"
    $Result = Invoke-Endpoint -Endpoint $Endpoint
    $HttpResults.Add($Result)
    if ($null -eq $Result.HttpStatus) {
        Add-Result "HTTP $Endpoint" "BLOCKED" "No HTTP response. Error: $($Result.Error)"
    }
    elseif ($Result.HttpStatus -ge 200 -and $Result.HttpStatus -lt 300) {
        Add-Result "HTTP $Endpoint" "PASS" "HTTP $($Result.HttpStatus), Content-Type=$($Result.ContentType), ${($Result.DurationMs)}ms"
    }
    elseif ($Result.HttpStatus -ge 400 -and $Result.HttpStatus -lt 500) {
        Add-Result "HTTP $Endpoint" "WARNING" "HTTP $($Result.HttpStatus), Content-Type=$($Result.ContentType), ${($Result.DurationMs)}ms"
    }
    elseif ($Result.HttpStatus -ge 500) {
        Add-Result "HTTP $Endpoint" "WARNING" "HTTP $($Result.HttpStatus), Content-Type=$($Result.ContentType), ${($Result.DurationMs)}ms"
    }
    else {
        Add-Result "HTTP $Endpoint" "WARNING" "HTTP $($Result.HttpStatus), Content-Type=$($Result.ContentType), ${($Result.DurationMs)}ms"
    }
}

foreach ($Result in $HttpResults) {
    $Combined = "$($Result.Body) $($Result.Error)"
    $PhpErrorDetected = $Combined -match "(?i)Fatal error" -or $Combined -match "(?i)Parse error" -or $Combined -match "(?i)Warning:" -or $Combined -match "(?i)Notice:" -or $Combined -match "(?i)Uncaught"
    if ($PhpErrorDetected) {
        Add-Result "PHP errors visible $($Result.Endpoint)" "WARNING" "PHP error signature present in response."
    }
    else {
        Add-Result "PHP errors visible $($Result.Endpoint)" "PASS" "No obvious PHP error signature detected."
    }
}

$SecretPatterns = @("(?i)DB_PASSWORD\s*=", "(?i)password\s*[:=]\s*[^<\s]+", "(?i)postgres://[^<\s]+", "(?i)postgresql://[^<\s]+", "(?i)-----BEGIN .* PRIVATE KEY-----")

foreach ($Result in $HttpResults) {
    $FoundSecret = $false
    foreach ($Pattern in $SecretPatterns) {
        if ($Result.Body -match $Pattern) {
            $FoundSecret = $true
            break
        }
    }
    if ($FoundSecret) {
        Add-Result "Secret exposure $($Result.Endpoint)" "WARNING" "Potentially sensitive pattern detected in HTTP response."
    }
    else {
        Add-Result "Secret exposure $($Result.Endpoint)" "PASS" "No obvious secret pattern detected."
    }
}

Add-Result "PostgreSQL modified by ENV-05" "PASS" "No PostgreSQL command executed by this intervention."
Add-Result "Apache modified by ENV-05" "PASS" "No Apache configuration modified by this intervention."

Write-Host ""
Write-Host "Stopping PHP server started by ENV-05..." -ForegroundColor Yellow

if ($StartedByScript -and $null -ne $ServerProcess) {
    try {
        if (-not $ServerProcess.HasExited) {
            Stop-Process -Id $ServerProcess.Id -Force -ErrorAction Stop
            Add-Result "Stop PHP server ENV-05" "PASS" "PID $($ServerProcess.Id) stopped."
        }
        else {
            Add-Result "Stop PHP server ENV-05" "PASS" "Process PID $($ServerProcess.Id) was already terminated."
        }
    }
    catch {
        Add-Result "Stop PHP server ENV-05" "WARNING" "Could not automatically stop PID $($ServerProcess.Id): $($_.Exception.Message)"
    }
}

Start-Sleep -Milliseconds 500

if (Test-TcpPort -TargetHost $BindHost -Port $Port) {
    Add-Result "Port $Port freed after ENV-05" "WARNING" "Port $Port still responds after stopping process started by ENV-05."
}
else {
    Add-Result "Port $Port freed after ENV-05" "PASS" "Port $Port is free."
}

$PassCount = @($Results | Where-Object Status -eq "PASS").Count
$WarningCount = @($Results | Where-Object Status -eq "WARNING").Count
$BlockedCount = @($Results | Where-Object Status -eq "BLOCKED").Count

if ($BlockedCount -gt 0) {
    $Verdict = "NO-GO"
}
elseif ($WarningCount -gt 0) {
    $Verdict = "PASS WITH WARNINGS"
}
else {
    $Verdict = "PASS"
}

$ReportContent = @"
# ENV-05 - PHP BUILT-IN SERVER - ARCH-01 VALIDATION

## Summary
HTTP validation of IMC-Clarodoro application with PHP built-in server.

## Verdict
$Verdict

## Environment
- Project: $ProjectRoot
- PHP: $PhpExe
- Validation URL: $BaseUrl
- Apache: not modified
- PostgreSQL: not modified
- Database: no creation/modification

## Statistics
- PASS: $PassCount
- WARNING: $WarningCount
- BLOCKED: $BlockedCount

## Results
| Test | Status | Details |
|---|---|---|
"@

foreach ($Item in $Results) {
    $SafeDetails = ($Item.Details -replace "`r?`n", "<br>") -replace "\|", "\|"
    $ReportContent += "`n| $($Item.Test) | $($Item.Status) | $SafeDetails |"
}

$ReportContent += "`n`n## HTTP Responses`n`n"

foreach ($Result in $HttpResults) {
    $ReportContent += "### $($Result.Endpoint)`n`n"
    $ReportContent += "- URL: $($Result.Url)`n"
    $ReportContent += "- HTTP: $($Result.HttpStatus)`n"
    $ReportContent += "- Content-Type: $($Result.ContentType)`n"
    $ReportContent += "- Time: $($Result.DurationMs) ms`n`n"
    $ReportContent += "```text`n$($Result.Body)`n````n`n"
}

$ReportContent += "## Conclusion`n`n"

if ($Verdict -eq "PASS") {
    $ReportContent += "PHP built-in server successfully validated HTTP exposure of ARCH-01 endpoints without depending on Apache.`n`n"
}
elseif ($Verdict -eq "PASS WITH WARNINGS") {
    $ReportContent += "Application is accessible via PHP built-in server, but some endpoints have warnings requiring further analysis.`n`n"
}
else {
    $ReportContent += "ARCH-01 validation via PHP built-in server is not conclusive. Detailed results must be analyzed before any environment modification.`n`n"
}

$ReportContent += "## Security / Non-destructiveness`n`n"
$ReportContent += "- No Apache modification.`n"
$ReportContent += "- No PostgreSQL modification.`n"
$ReportContent += "- No database creation.`n"
$ReportContent += "- No schema changes.`n"
$ReportContent += "- No application file changes.`n"
$ReportContent += "- No package installation.`n"
$ReportContent += "- No external PHP process stopped.`n"

Set-Content -Path $ReportFile -Value $ReportContent -Encoding UTF8
Set-Content -Path $FinalReport -Value $ReportContent -Encoding UTF8

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host " ENV-05 COMPLETE" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Verdict: $Verdict" -ForegroundColor Yellow
Write-Host "PASS: $PassCount"
Write-Host "WARNING: $WarningCount"
Write-Host "BLOCKED: $BlockedCount"
Write-Host ""
Write-Host "Report: $FinalReport"
Write-Host ""

if ($Verdict -eq "NO-GO") { exit 2 }
elseif ($Verdict -eq "PASS WITH WARNINGS") { exit 1 }
else { exit 0 }
