# ENV-18 — PostgreSQL Integrity Forensic Validation
[CmdletBinding()]
param(
  [string]$Host = "localhost",
  [int]$Port = 5432,
  [string]$Database = "imc_clarodoro",
  [string]$Username = "postgres",
  [string]$PsqlPath = "psql"
)

$ErrorActionPreference = "Stop"
$reportDir = Join-Path (Split-Path -Parent $PSScriptRoot) "audit"
$reportPath = Join-Path $reportDir "ENV-18-POSTGRESQL-INTEGRITY-FORENSIC-REPORT.md"
New-Item -ItemType Directory -Force -Path $reportDir | Out-Null

function Invoke-PsqlScalar {
  param([Parameter(Mandatory=$true)][string]$Sql)

  $out = & $PsqlPath -X -h $Host -p $Port -U $Username -d $Database -tA -c $Sql 2>&1
  if ($LASTEXITCODE -ne 0) {
    throw "psql failed: $($out -join ([Environment]::NewLine))"
  }
  return ($out -join ([Environment]::NewLine)).Trim()
}

function Add-Check {
  param(
    [string]$Name,
    [int]$Expected,
    [int]$Actual,
    [ref]$Failures
  )

  $ok = $Expected -eq $Actual
  if ($ok) {
    $result = "PASS"
  } else {
    $result = "FAIL"
    $Failures.Value++
  }

  return [pscustomobject]@{
    Check = $Name
    Expected = $Expected
    Actual = $Actual
    Result = $result
  }
}

Write-Host "ENV-18 — PostgreSQL Integrity Forensic Validation"
Write-Host "READ-ONLY : aucune écriture SQL."
$failures = 0
$results = @()

$version = Invoke-PsqlScalar -Sql "SELECT version();"

$checks = @(
  @("public tables",19,"SELECT count(*) FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace WHERE c.relkind='r' AND n.nspname='public';"),
  @("UNIQUE constraints",11,"SELECT count(*) FROM pg_constraint con JOIN pg_namespace n ON n.oid=con.connamespace WHERE n.nspname='public' AND con.contype='u';"),
  @("PRIMARY KEY constraints",19,"SELECT count(*) FROM pg_constraint con JOIN pg_namespace n ON n.oid=con.connamespace WHERE n.nspname='public' AND con.contype='p';"),
  @("CHECK constraints",23,"SELECT count(*) FROM pg_constraint con JOIN pg_namespace n ON n.oid=con.connamespace WHERE n.nspname='public' AND con.contype='c';"),
  @("FOREIGN KEY constraints",17,"SELECT count(*) FROM pg_constraint con JOIN pg_namespace n ON n.oid=con.connamespace WHERE n.nspname='public' AND con.contype='f';"),
  @("ordinary application indexes",13,"SELECT count(*) FROM pg_class i JOIN pg_namespace n ON n.oid=i.relnamespace WHERE i.relkind='i' AND n.nspname='public' AND NOT EXISTS (SELECT 1 FROM pg_constraint c WHERE c.conindid=i.oid) AND i.relname <> 'enrollments_one_active_per_student_year';"),
  @("partial unique enrollment index",1,"SELECT count(*) FROM pg_class i JOIN pg_namespace n ON n.oid=i.relnamespace WHERE n.nspname='public' AND i.relkind='i' AND i.relname='enrollments_one_active_per_student_year';"),
  @("ON DELETE CASCADE FKs",0,"SELECT count(*) FROM pg_constraint con JOIN pg_namespace n ON n.oid=con.connamespace WHERE n.nspname='public' AND con.contype='f' AND con.confdeltype='c';"),
  @("application triggers",0,"SELECT count(*) FROM pg_trigger t JOIN pg_class c ON c.oid=t.tgrelid JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname='public' AND NOT t.tgisinternal;")
)

foreach ($c in $checks) {
  $actual = [int](Invoke-PsqlScalar -Sql $c[2])
  $results += Add-Check -Name $c[0] -Expected ([int]$c[1]) -Actual $actual -Failures ([ref]$failures)
}

$columnSql = "SELECT table_name||'.'||column_name FROM information_schema.columns WHERE table_schema='public' AND ((table_name='users' AND column_name IN ('password_hash','password')) OR (table_name='grades' AND column_name IN ('enrollment_id','student_id','coefficient')) OR (table_name='attendance' AND column_name IN ('enrollment_id','student_id','class_id'))) ORDER BY 1;"
$columnOut = & $PsqlPath -X -h $Host -p $Port -U $Username -d $Database -tA -c $columnSql 2>&1
if ($LASTEXITCODE -ne 0) {
  throw "psql failed during column check: $($columnOut -join ([Environment]::NewLine))"
}

$columnSet = @{}
foreach ($row in $columnOut) {
  if ($row.Trim()) {
    $columnSet[$row.Trim()] = $true
  }
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

foreach ($e in $columnExpectations) {
  $actual = $columnSet.ContainsKey($e[0])
  $ok = $actual -eq [bool]$e[1]

  if ($ok) {
    $result = "PASS"
  } else {
    $result = "FAIL"
    $failures++
  }

  if ([bool]$e[1]) {
    $expectedText = "PRESENT"
  } else {
    $expectedText = "ABSENT"
  }

  if ($actual) {
    $actualText = "PRESENT"
  } else {
    $actualText = "ABSENT"
  }

  $results += [pscustomobject]@{
    Check = $e[0]
    Expected = $expectedText
    Actual = $actualText
    Result = $result
  }
}

$report = @(
  "# ENV-18 — PostgreSQL Integrity Forensic Validation",
  "",
  "Date : $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')",
  "",
  "## Mode",
  "",
  "**READ-ONLY** — uniquement des requêtes SELECT/catalogue PostgreSQL.",
  "",
  "## PostgreSQL",
  "",
  $version,
  "",
  "## Résultats",
  "",
  "| Contrôle | Attendu | Réel | Résultat |",
  "|---|---:|---:|---|"
)

foreach ($r in $results) {
  $report += "| $($r.Check) | $($r.Expected) | $($r.Actual) | $($r.Result) |"
}

if ($failures -eq 0) {
  $verdict = "**ENV-18 PASS**"
} else {
  $verdict = "**ENV-18 FAIL** — $failures contrôle(s) en échec."
}

$report += @(
  "",
  "## Verdict",
  "",
  $verdict,
  "",
  "## Sécurité d'exécution",
  "",
  "- DB ciblée : $Database",
  "- INSERT/UPDATE/DELETE : NON",
  "- CREATE/ALTER/DROP : NON",
  "- TRUNCATE : NON",
  "- Base recréée : NON"
)

Set-Content -LiteralPath $reportPath -Value ($report -join ([Environment]::NewLine)) -Encoding UTF8

Write-Host ""
if ($failures -eq 0) {
  Write-Host "ENV-18 PASS"
} else {
  Write-Host "ENV-18 FAIL"
  exit 1
}
Write-Host "Rapport : $reportPath"
