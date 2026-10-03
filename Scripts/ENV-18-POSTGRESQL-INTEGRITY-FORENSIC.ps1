# ENV-18 - PostgreSQL Integrity Forensic Validation
[CmdletBinding()]
param(
  [ValidateNotNullOrEmpty()]
  [string]$DbHost = "localhost",
  [ValidateRange(1,65535)]
  [int]$Port = 5432,
  [ValidateNotNullOrEmpty()]
  [string]$Database = "imc_clarodoro",
  [ValidateNotNullOrEmpty()]
  [string]$Username = "postgres",
  [ValidateNotNullOrEmpty()]
  [string]$PsqlPath = "psql"
)

$ErrorActionPreference = "Stop"
$projectRoot = Split-Path -Parent $PSScriptRoot
$reportDir = Join-Path $projectRoot "audit"
$reportPath = Join-Path $reportDir "ENV-18-POSTGRESQL-INTEGRITY-FORENSIC-REPORT.md"
New-Item -ItemType Directory -Force -Path $reportDir | Out-Null

function Invoke-PsqlScalar {
  param([Parameter(Mandatory=$true)][string]$Sql)
  $output = & $PsqlPath -X -v ON_ERROR_STOP=1 -h $DbHost -p $Port -U $Username -d $Database -tA -c $Sql 2>&1
  if ($LASTEXITCODE -ne 0) {
    throw "psql failed: $($output -join ([Environment]::NewLine))"
  }
  return ($output -join ([Environment]::NewLine)).Trim()
}

function Add-Check {
  param(
    [Parameter(Mandatory=$true)][string]$Name,
    [Parameter(Mandatory=$true)][string]$Expected,
    [Parameter(Mandatory=$true)][string]$Actual,
    [Parameter(Mandatory=$true)][ref]$Failures,
    [string]$Details = ""
  )
  if ($Expected -eq $Actual) {
    $result = "PASS"
  } else {
    $result = "FAIL"
    $Failures.Value++
  }
  [pscustomobject]@{
    Check = $Name
    Expected = $Expected
    Actual = $Actual
    Result = $result
    Details = $Details
  }
}

function Add-BooleanCheck {
  param(
    [Parameter(Mandatory=$true)][string]$Name,
    [Parameter(Mandatory=$true)][bool]$Expected,
    [Parameter(Mandatory=$true)][bool]$Actual,
    [Parameter(Mandatory=$true)][ref]$Failures
  )
  $expectedText = if ($Expected) { "PRESENT" } else { "ABSENT" }
  $actualText = if ($Actual) { "PRESENT" } else { "ABSENT" }
  if ($Expected -eq $Actual) {
    $result = "PASS"
  } else {
    $result = "FAIL"
    $Failures.Value++
  }
  [pscustomobject]@{
    Check = $Name
    Expected = $expectedText
    Actual = $actualText
    Result = $result
    Details = ""
  }
}

Write-Host "ENV-18 - PostgreSQL Integrity Forensic Validation"
Write-Host "READ-ONLY: catalogue and SELECT queries only."

$failures = 0
$results = @()
$version = Invoke-PsqlScalar -Sql 'SELECT version();'
Write-Host ("PostgreSQL : {0}" -f $version)

$expectedTables = @(
  "roles","permissions","role_permissions","users","levels","school_years",
  "subjects","teachers","staff","classes","teacher_class_subjects","students",
  "parents","student_parents","enrollments","grades","attendance","invoices","payments"
)

$tableSql = "SELECT tablename FROM pg_tables WHERE schemaname='public' ORDER BY tablename;"
$actualTables = @(Invoke-PsqlScalar -Sql $tableSql).Split([Environment]::NewLine, [StringSplitOptions]::RemoveEmptyEntries)
$missingTables = @($expectedTables | Where-Object { $_ -notin $actualTables })
$extraTables = @($actualTables | Where-Object { $_ -notin $expectedTables })
$results += Add-Check -Name "public tables exact set" -Expected ($expectedTables.Count.ToString()) -Actual ($actualTables.Count.ToString()) -Failures ([ref]$failures) -Details ("missing={0}; extra={1}" -f ($missingTables -join ","), ($extraTables -join ","))

$countChecks = @(
  @("UNIQUE constraints","11","SELECT count(*) FROM pg_constraint con JOIN pg_namespace n ON n.oid=con.connamespace WHERE n.nspname='public' AND con.contype='u';"),
  @("PRIMARY KEY constraints","19","SELECT count(*) FROM pg_constraint con JOIN pg_namespace n ON n.oid=con.connamespace WHERE n.nspname='public' AND con.contype='p';"),
  @("CHECK constraints","23","SELECT count(*) FROM pg_constraint con JOIN pg_namespace n ON n.oid=con.connamespace WHERE n.nspname='public' AND con.contype='c';"),
  @("FOREIGN KEY constraints","17","SELECT count(*) FROM pg_constraint con JOIN pg_namespace n ON n.oid=con.connamespace WHERE n.nspname='public' AND con.contype='f';"),
  @("application triggers","0","SELECT count(*) FROM pg_trigger t JOIN pg_class c ON c.oid=t.tgrelid JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname='public' AND NOT t.tgisinternal;")
)
foreach ($c in $countChecks) {
  $actual = Invoke-PsqlScalar -Sql $c[2]
  $results += Add-Check -Name $c[0] -Expected $c[1] -Actual $actual -Failures ([ref]$failures)
}

$fkRestrict = Invoke-PsqlScalar -Sql "SELECT count(*) FROM pg_constraint con JOIN pg_namespace n ON n.oid=con.connamespace WHERE n.nspname='public' AND con.contype='f' AND con.confdeltype='r';"
$fkCascade = Invoke-PsqlScalar -Sql "SELECT count(*) FROM pg_constraint con JOIN pg_namespace n ON n.oid=con.connamespace WHERE n.nspname='public' AND con.contype='f' AND con.confdeltype='c';"
$fkOther = Invoke-PsqlScalar -Sql "SELECT count(*) FROM pg_constraint con JOIN pg_namespace n ON n.oid=con.connamespace WHERE n.nspname='public' AND con.contype='f' AND con.confdeltype NOT IN ('r','c');"
$results += Add-Check -Name "FOREIGN KEY ON DELETE RESTRICT" -Expected "17" -Actual $fkRestrict -Failures ([ref]$failures)
$results += Add-Check -Name "FOREIGN KEY ON DELETE CASCADE" -Expected "0" -Actual $fkCascade -Failures ([ref]$failures)
$results += Add-Check -Name "FOREIGN KEY other delete actions" -Expected "0" -Actual $fkOther -Failures ([ref]$failures)

$ordinaryIndexSql = "SELECT count(*) FROM pg_class i JOIN pg_namespace n ON n.oid=i.relnamespace WHERE i.relkind='i' AND n.nspname='public' AND NOT EXISTS (SELECT 1 FROM pg_constraint c WHERE c.conindid=i.oid) AND i.relname <> 'enrollments_one_active_per_student_year';"
$ordinaryIndexes = Invoke-PsqlScalar -Sql $ordinaryIndexSql
$results += Add-Check -Name "ordinary application indexes" -Expected "13" -Actual $ordinaryIndexes -Failures ([ref]$failures)

$partialIndexSql = "SELECT count(*) FROM pg_class i JOIN pg_namespace n ON n.oid=i.relnamespace JOIN pg_index ix ON ix.indexrelid=i.oid WHERE n.nspname='public' AND i.relname='enrollments_one_active_per_student_year' AND i.relkind='i' AND ix.indisunique AND ix.indpred IS NOT NULL;"
$partialIndex = Invoke-PsqlScalar -Sql $partialIndexSql
$results += Add-Check -Name "partial unique enrollment index" -Expected "1" -Actual $partialIndex -Failures ([ref]$failures)

$columnSql = "SELECT table_name||'.'||column_name FROM information_schema.columns WHERE table_schema='public' AND ((table_name='users' AND column_name IN ('password_hash','password')) OR (table_name='grades' AND column_name IN ('enrollment_id','student_id','coefficient')) OR (table_name='attendance' AND column_name IN ('enrollment_id','student_id','class_id'))) ORDER BY 1;"
$columnOutput = & $PsqlPath -X -v ON_ERROR_STOP=1 -h $DbHost -p $Port -U $Username -d $Database -tA -c $columnSql 2>&1
if ($LASTEXITCODE -ne 0) {
  throw "psql failed during column check: $($columnOutput -join ([Environment]::NewLine))"
}
$columnSet = @{}
foreach ($row in $columnOutput) {
  $value = $row.ToString().Trim()
  if ($value) { $columnSet[$value] = $true }
}

$columnExpectations = @(
  @("users.password_hash",$true),
  @("users.password",$false),
  @("grades.enrollment_id",$true),
  @("grades.student_id",$false),
  @("grades.coefficient",$false),
  @("attendance.enrollment_id",$true),
  @("attendance.student_id",$false),
  @("attendance.class_id",$false)
)
foreach ($expectation in $columnExpectations) {
  $actual = $columnSet.ContainsKey($expectation[0])
  $results += Add-BooleanCheck -Name $expectation[0] -Expected ([bool]$expectation[1]) -Actual $actual -Failures ([ref]$failures)
}

$pgcrypto = Invoke-PsqlScalar -Sql "SELECT count(*) FROM pg_extension WHERE extname='pgcrypto';"
$results += Add-Check -Name "pgcrypto extension" -Expected "1" -Actual $pgcrypto -Failures ([ref]$failures)

$report = @()
$report += "# ENV-18 - PostgreSQL Integrity Forensic Validation"
$report += ""
$report += ("Date : {0}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"))
$report += ""
$report += "## Mode"
$report += ""
$report += "READ-ONLY - SELECT and PostgreSQL catalogue queries only."
$report += ""
$report += "## PostgreSQL"
$report += ""
$report += $version
$report += ""
$report += "## Results"
$report += ""
$report += "| Check | Expected | Actual | Result |"
$report += "|---|---|---|---|"
foreach ($r in $results) {
  $report += ("| {0} | {1} | {2} | {3} |" -f $r.Check, $r.Expected, $r.Actual, $r.Result)
  if ($r.Details) {
    $report += ("| Detail | | | {0} |" -f $r.Details)
  }
}
if ($failures -eq 0) {
  $verdict = "ENV-18 PASS"
} else {
  $verdict = ("ENV-18 FAIL - {0} check(s) failed." -f $failures)
}
$report += ""
$report += "## Verdict"
$report += ""
$report += $verdict
$report += ""
$report += "## Execution Safety"
$report += ""
$report += ("- Database : {0}" -f $Database)
$report += "- INSERT/UPDATE/DELETE : NO"
$report += "- CREATE/ALTER/DROP : NO"
$report += "- TRUNCATE : NO"
$report += "- Database recreated : NO"

Set-Content -LiteralPath $reportPath -Value ($report -join ([Environment]::NewLine)) -Encoding UTF8

Write-Host ""
Write-Host ("Checks executed : {0}" -f $results.Count)
if ($failures -eq 0) {
  Write-Host "ENV-18 PASS"
} else {
  Write-Host ("ENV-18 FAIL - {0} check(s) failed." -f $failures)
  exit 1
}
Write-Host ("Report : {0}" -f $reportPath)
