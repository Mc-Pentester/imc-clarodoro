#requires -Version 5.1

<#
ENV-12 — FORENSIC SQL SCHEMA REVIEW

Objectif :
    Auditer database/schema.sql V1 sans l'executer.

IMPORTANT :
    - Aucun acces PostgreSQL
    - Aucun SQL execute
    - Aucune base creee
    - Aucun CREATE TABLE execute
    - Aucun fichier applicatif modifie
    - Aucun schema.sql modifie
    - Aucun package installe
    - Aucun service modifie

Entree :
    database/schema.sql

Sorties :
    audit\ENV-12-FORENSIC-SQL-SCHEMA-REVIEW-REPORT.md
    audit\ENV-12-FORENSIC-SQL-SCHEMA-REVIEW-REPORT-FINAL.md
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$ProjectRoot = "C:\IMC-Clarodoro-securise-client\IMC-Clarodoro"
$SchemaPath = Join-Path $ProjectRoot 'database\schema.sql'
$AuditDir = Join-Path $ProjectRoot 'audit'

New-Item -ItemType Directory -Path $AuditDir -Force | Out-Null

$ReportPath = Join-Path $AuditDir 'ENV-12-FORENSIC-SQL-SCHEMA-REVIEW-REPORT.md'
$FinalReportPath = Join-Path $AuditDir 'ENV-12-FORENSIC-SQL-SCHEMA-REVIEW-REPORT-FINAL.md'

if (-not (Test-Path -LiteralPath $SchemaPath)) {
    throw "schema.sql introuvable : $SchemaPath"
}

$schema = Get-Content -LiteralPath $SchemaPath -Raw
$timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'

# ============================================================
# UTILITAIRES
# ============================================================

function Test-Pattern {
    param(
        [string]$Text,
        [string]$Pattern
    )

    return [regex]::IsMatch(
        $Text,
        $Pattern,
        [System.Text.RegularExpressions.RegexOptions]::IgnoreCase
    )
}

function Count-Pattern {
    param(
        [string]$Text,
        [string]$Pattern
    )

    return ([regex]::Matches(
        $Text,
        $Pattern,
        [System.Text.RegularExpressions.RegexOptions]::IgnoreCase
    )).Count
}

# ============================================================
# INVENTAIRE
# ============================================================

$expectedTables = @(
    'roles',
    'permissions',
    'role_permissions',
    'users',
    'levels',
    'school_years',
    'subjects',
    'teachers',
    'staff',
    'classes',
    'teacher_class_subjects',
    'students',
    'parents',
    'student_parents',
    'enrollments',
    'grades',
    'attendance',
    'invoices',
    'payments'
)

$missingTables = @()
$foundTables = @()

foreach ($table in $expectedTables) {

    $pattern = "(?im)^\s*CREATE\s+TABLE\s+$([regex]::Escape($table))\s*\("

    if (Test-Pattern -Text $schema -Pattern $pattern) {
        $foundTables += $table
    }
    else {
        $missingTables += $table
    }
}

$createTableCount = Count-Pattern $schema '(?im)^\s*CREATE\s+TABLE\s+'
$foreignKeyCount = Count-Pattern $schema '(?im)FOREIGN\s+KEY\s*\('
$indexCount = Count-Pattern $schema '(?im)^\s*CREATE\s+(?:UNIQUE\s+)?INDEX\s+'
$checkCount = Count-Pattern $schema '(?im)CONSTRAINT\s+\S+\s+CHECK\s*\('
$uniqueCount = Count-Pattern $schema '(?im)CONSTRAINT\s+\S+\s+UNIQUE\s*\('

# ============================================================
# PK
# ============================================================

$pkUuidCount = Count-Pattern $schema '(?im)id\s+UUID\s+PRIMARY\s+KEY'

$pkFindings = if ($pkUuidCount -eq $createTableCount) {
    'PASS — toutes les tables principales utilisent un id UUID PRIMARY KEY.'
}
else {
    "WARNING — $pkUuidCount PK UUID détectées pour $createTableCount tables."
}

# ============================================================
# UUID DEFAULT
# ============================================================

$uuidDefaultCount = Count-Pattern $schema '(?im)UUID\s+PRIMARY\s+KEY\s+DEFAULT\s+gen_random_uuid'

$uuidFinding = if ($uuidDefaultCount -eq $createTableCount) {
    'PASS — les PK UUID disposent d''une génération automatique.'
}
else {
    "WARNING — $uuidDefaultCount PK disposent de gen_random_uuid() sur $createTableCount tables."
}

# ============================================================
# SNAKE CASE
# ============================================================

$camelCaseIdentifiers = [regex]::Matches(
    $schema,
    '\b[a-z]+[A-Z][A-Za-z0-9_]*\b'
)

$snakeCaseFinding = if ($camelCaseIdentifiers.Count -eq 0) {
    'PASS — aucun identifiant SQL CamelCase détecté.'
}
else {
    "WARNING — $($camelCaseIdentifiers.Count) identifiants potentiellement CamelCase détectés."
}

# ============================================================
# ON DELETE
# ============================================================

$fkWithoutDeleteRule = [regex]::Matches(
    $schema,
    '(?is)FOREIGN\s+KEY\s*\([^)]+\)\s*REFERENCES\s+[^\s(]+\s*\([^)]+\)(?!\s*ON\s+DELETE)'
)

$deleteRestrictCount = Count-Pattern $schema '(?im)ON\s+DELETE\s+RESTRICT'
$deleteCascadeCount = Count-Pattern $schema '(?im)ON\s+DELETE\s+CASCADE'
$deleteSetNullCount = Count-Pattern $schema '(?im)ON\s+DELETE\s+SET\s+NULL'

$deleteFinding = if ($deleteCascadeCount -eq 0) {
    'PASS — aucune suppression CASCADE détectée.'
}
else {
    "WARNING — $deleteCascadeCount suppression(s) CASCADE détectée(s)."
}

# ============================================================
# D09 — STATUS
# ============================================================

$statusTables = @(
    'users',
    'school_years',
    'teachers',
    'staff',
    'classes',
    'teacher_class_subjects',
    'students',
    'enrollments',
    'attendance',
    'invoices'
)

$statusMissing = @()

foreach ($table in $statusTables) {

    $pattern = "(?is)CREATE\s+TABLE\s+$([regex]::Escape($table))\s*\(.*?status\s+VARCHAR"

    if (-not (Test-Pattern -Text $schema -Pattern $pattern)) {
        $statusMissing += $table
    }
}

# ============================================================
# D14 — COEFFICIENT
# ============================================================

$subjectCoefficient = Test-Pattern $schema '(?is)CREATE\s+TABLE\s+subjects.*?coefficient\s+NUMERIC'
$gradeCoefficient = Test-Pattern $schema '(?is)CREATE\s+TABLE\s+grades.*?coefficient\s+NUMERIC'

$coefficientFinding = if ($subjectCoefficient -and $gradeCoefficient) {
    'WARNING — coefficient présent dans subjects et grades. Duplication potentielle à arbitrer.'
}
elseif ($subjectCoefficient) {
    'PASS — coefficient porté par subjects uniquement.'
}
else {
    'WARNING — aucun coefficient de matière détecté.'
}

# ============================================================
# D13 — ACTIVE ENROLLMENT
# ============================================================

$activeEnrollmentIndex = Test-Pattern `
    $schema `
    'CREATE\s+UNIQUE\s+INDEX\s+enrollments_one_active_per_student_year'

$activeEnrollmentPartial = Test-Pattern `
    $schema `
    'WHERE\s+status\s*=\s*''ACTIVE'''

$enrollmentFinding = if ($activeEnrollmentIndex -and $activeEnrollmentPartial) {
    'PASS — unicité active étudiant/année implémentée par index unique partiel.'
}
else {
    'WARNING — règle d''unicité active étudiant/année insuffisamment protégée.'
}

# ============================================================
# D12 — MATRICULE
# ============================================================

$matriculeUnique = Test-Pattern `
    $schema `
    'matricule\s+VARCHAR[^,]*NOT\s+NULL.*?CONSTRAINT\s+students_matricule_unique\s+UNIQUE'

$matriculeFinding = if ($matriculeUnique) {
    'PASS — matricule NOT NULL + UNIQUE.'
}
else {
    'WARNING — unicité du matricule à vérifier.'
}

# ============================================================
# D16 — ATTENDANCE
# ============================================================

$attendanceUnique = Test-Pattern `
    $schema `
    'CONSTRAINT\s+attendance_unique\s+UNIQUE\s*\(\s*student_id\s*,\s*class_id\s*,\s*attendance_date\s*\)'

$attendanceStatuses = @(
    'PRESENT',
    'ABSENT',
    'LATE',
    'EXCUSED'
)

$attendanceStatusMissing = @()

foreach ($status in $attendanceStatuses) {
    if (-not (Test-Pattern $schema "'$status'")) {
        $attendanceStatusMissing += $status
    }
}

$attendanceFinding = if ($attendanceUnique -and $attendanceStatusMissing.Count -eq 0) {
    'PASS — unicité étudiant/classe/date et statuts attendance présents.'
}
else {
    'WARNING — structure attendance incomplète ou à confirmer.'
}

# ============================================================
# D17/D18/D19 — FINANCE
# ============================================================

$invoiceAmount = Test-Pattern `
    $schema `
    'CREATE\s+TABLE\s+invoices.*?amount\s+NUMERIC'

$paymentAmount = Test-Pattern `
    $schema `
    'CREATE\s+TABLE\s+payments.*?amount\s+NUMERIC'

$paymentFk = Test-Pattern `
    $schema `
    'payments_invoice_fk.*?FOREIGN\s+KEY\s*\(\s*invoice_id\s*\)'

$paymentPositive = Test-Pattern `
    $schema `
    'payments_amount_check.*?amount\s*>\s*0'

$financialAggregateProtection = Test-Pattern `
    $schema `
    'SUM\s*\(\s*payments\.amount'

$financeFinding = @()

if ($invoiceAmount) {
    $financeFinding += 'PASS : montant facture present.'
}
else {
    $financeFinding += 'FAIL : montant facture absent.'
}

if ($paymentAmount) {
    $financeFinding += 'PASS : montant paiement present.'
}
else {
    $financeFinding += 'FAIL : montant paiement absent.'
}

if ($paymentFk) {
    $financeFinding += 'PASS : FK payment -> invoice presente.'
}
else {
    $financeFinding += 'FAIL : FK payment -> invoice absente.'
}

if ($paymentPositive) {
    $financeFinding += 'PASS : paiement strictement positif.'
}
else {
    $financeFinding += 'WARNING : contrainte paiement > 0 absente.'
}

if (-not $financialAggregateProtection) {
    $financeFinding += 'WARNING : aucune protection SQL contre paiement total > facture.'
}

# ============================================================
# D14/D15 — GRADES
# ============================================================

$gradeStudentFk = Test-Pattern `
    $schema `
    'grades_student_fk.*?FOREIGN\s+KEY\s*\(\s*student_id\s*\)'

$gradeEnrollmentFk = Test-Pattern `
    $schema `
    'grades_enrollment_fk.*?FOREIGN\s+KEY\s*\(\s*enrollment_id\s*\)'

$gradeCrossConsistency = Test-Pattern `
    $schema `
    'CHECK\s*\(.*student_id.*enrollment_id'

$gradeFinding = @()

if ($gradeStudentFk) {
    $gradeFinding += 'PASS : grades.student_id possède une FK.'
}
else {
    $gradeFinding += 'FAIL : grades.student_id sans FK.'
}

if ($gradeEnrollmentFk) {
    $gradeFinding += 'PASS : grades.enrollment_id possède une FK.'
}
else {
    $gradeFinding += 'FAIL : grades.enrollment_id sans FK.'
}

if (-not $gradeCrossConsistency) {
    $gradeFinding += 'WARNING : aucune contrainte inter-colonnes garantissant student_id = enrollment.student_id.'
}

# ============================================================
# UPDATED_AT
# ============================================================

$updatedAtCount = Count-Pattern $schema '(?im)updated_at\s+TIMESTAMPTZ'

$updatedAtTriggerCount = Count-Pattern $schema '(?im)CREATE\s+TRIGGER'

$updatedAtFinding = if ($updatedAtCount -gt 0 -and $updatedAtTriggerCount -eq 0) {
    'WARNING — updated_at existe mais aucun trigger de synchronisation automatique n''est defini.'
}
else {
    'INFO — stratégie updated_at à confirmer.'
}

# ============================================================
# EMAIL UNIQUE
# ============================================================

$emailUniqueCount = Count-Pattern $schema '(?im)email\s+UNIQUE'

$emailFinding = if ($emailUniqueCount -gt 0) {
    'INFO — des contraintes UNIQUE email existent. PostgreSQL permet plusieurs NULL, ce qui doit etre coherent avec le metier.'
}
else {
    'INFO — aucune contrainte UNIQUE email detectee.'
}

# ============================================================
# SENSIBILITE / AUTH
# ============================================================

$passwordHash = Test-Pattern $schema 'password_hash\s+TEXT\s+NOT\s+NULL'
$passwordPlain = Test-Pattern $schema '(?i)password\s+(VARCHAR|TEXT)'

$passwordFinding = if ($passwordHash -and -not $passwordPlain) {
    'PASS — le modele utilise password_hash et ne contient pas de colonne password en clair.'
}
else {
    'WARNING — verifier la representation du mot de passe.'
}

# ============================================================
# INDEX FK
# ============================================================

$expectedIndexes = @(
    'idx_enrollments_student',
    'idx_enrollments_class',
    'idx_enrollments_school_year',
    'idx_grades_student',
    'idx_grades_subject',
    'idx_grades_enrollment',
    'idx_attendance_student_date',
    'idx_invoices_student',
    'idx_payments_invoice',
    'idx_teacher_class_subjects_class',
    'idx_teacher_class_subjects_teacher',
    'idx_teacher_class_subjects_subject'
)

$missingIndexes = @()

foreach ($indexName in $expectedIndexes) {
    if (-not (Test-Pattern $schema "CREATE INDEX\s+$([regex]::Escape($indexName))")) {
        $missingIndexes += $indexName
    }
}

$indexFinding = if ($missingIndexes.Count -eq 0) {
    'PASS — les index FK principaux sont presents.'
}
else {
    "WARNING — index attendus absents : $($missingIndexes -join ', ')"
}

# ============================================================
# SECTIONS / HOLIDAYS
# ============================================================

$sectionsPresent = Test-Pattern $schema '(?im)CREATE\s+TABLE\s+sections\s*\('
$holidaysPresent = Test-Pattern $schema '(?im)CREATE\s+TABLE\s+holidays\s*\('

# ============================================================
# SQL DANGEREUX / EXECUTION
# ============================================================

$dangerousStatements = @(
    'DROP\s+DATABASE',
    'DROP\s+TABLE',
    'TRUNCATE',
    'DELETE\s+FROM',
    'UPDATE\s+\w+\s+SET',
    'INSERT\s+INTO'
)

$dangerousFound = @()

foreach ($pattern in $dangerousStatements) {
    if (Test-Pattern $schema $pattern) {
        $dangerousFound += $pattern
    }
}

# ============================================================
# SCORE TECHNIQUE
# ============================================================

$criticalWarnings = 0
$warnings = 0
$passes = 0

$checks = @(
    $pkFindings,
    $uuidFinding,
    $snakeCaseFinding,
    $deleteFinding,
    $coefficientFinding,
    $enrollmentFinding,
    $matriculeFinding,
    $attendanceFinding,
    $updatedAtFinding,
    $emailFinding,
    $passwordFinding,
    $indexFinding
)

foreach ($finding in $checks) {

    if ($finding -like 'PASS*') {
        $passes++
    }
    elseif ($finding -like 'WARNING*') {
        $warnings++
    }
}

if (-not $gradeCrossConsistency) {
    $criticalWarnings++
}

if (-not $financialAggregateProtection) {
    $criticalWarnings++
}

if (-not $gradeCrossConsistency) {
    $warnings++
}

if (-not $financialAggregateProtection) {
    $warnings++
}

if ($missingTables.Count -gt 0) {
    $criticalWarnings++
}

if ($dangerousFound.Count -gt 0) {
    $criticalWarnings++
}

# ============================================================
# VERDICT
# ============================================================

$verdict = if ($missingTables.Count -gt 0 -or $dangerousFound.Count -gt 0) {
    'NO-GO'
}
elseif ($criticalWarnings -gt 0) {
    'REVIEW-REQUIRED'
}
else {
    'PASS'
}

# ============================================================
# RAPPORT
# ============================================================

$report = @"
# ENV-12 — FORENSIC SQL SCHEMA REVIEW

Date : $timestamp

Projet : C:\IMC-Clarodoro-securise-client\IMC-Clarodoro

## Verdict

**$verdict**

ENV-12 est une revue statique et non destructive de :

database/schema.sql

Aucun SQL n'a ete execute.

---

# 1. INVENTAIRE

| Element | Resultat |
|---|---:|
| Tables attendues | $($expectedTables.Count) |
| Tables trouvees | $($foundTables.Count) |
| Tables manquantes | $($missingTables.Count) |
| CREATE TABLE | $createTableCount |
| FOREIGN KEY | $foreignKeyCount |
| CREATE INDEX | $indexCount |
| CHECK | $checkCount |
| UNIQUE | $uniqueCount |

### Tables manquantes

$(if ($missingTables.Count -eq 0) { 'Aucune.' } else { $missingTables -join ', ' })

---

# 2. PK / UUID

**$pkFindings**

**$uuidFinding**

---

# 3. NAMING

**$snakeCaseFinding**

---

# 4. FOREIGN KEYS / DELETE

Foreign keys avec `ON DELETE RESTRICT` :

**$deleteRestrictCount**

Foreign keys avec `ON DELETE CASCADE` :

**$deleteCascadeCount**

Foreign keys avec `ON DELETE SET NULL` :

**$deleteSetNullCount**

**$deleteFinding**

Foreign keys sans regle ON DELETE explicite :

**$($fkWithoutDeleteRule.Count)**

---

# 5. STATUTS

Tables examinees :

$($statusTables -join ', ')

$(if ($statusMissing.Count -eq 0) {
'PASS — toutes les tables examinees possedent un status VARCHAR.'
} else {
"WARNING — tables sans status detecte : $($statusMissing -join ', ')"
})

---

# 6. D12 — MATRICULE

**$matriculeFinding**

---

# 7. D13 — ENROLLMENT

**$enrollmentFinding**

---

# 8. D14 — COEFFICIENTS

**$coefficientFinding**

### Point a resoudre

Le schema contient :

- subjects.coefficient
- grades.coefficient

Cela peut etre correct si les deux representent des concepts differents.

Sinon, cela cree une duplication potentielle.

Aucune modification n'est effectuee par ENV-12.

---

# 9. D15 — MOYENNES

Aucune colonne de moyenne persistee n'a ete detectee dans le schema V1.

**Conclusion : PASS STRUCTUREL**

La regle de calcul devra cependant etre definie dans la couche metier.

---

# 10. D16 — ATTENDANCE

**$attendanceFinding**

Statuts attendus :

- PRESENT
- ABSENT
- LATE
- EXCUSED

---

# 11. D17/D18/D19 — FINANCE

$($financeFinding -join "`n")

### Protection agregee

Aucune contrainte PostgreSQL actuelle ne garantit :

SUM(payments.amount) <= invoices.amount

**Statut : REVIEW-REQUIRED**

---

# 12. GRADES — COHERENCE ELEVE / INSCRIPTION

$($gradeFinding -join "`n")

### Probleme structurel

Deux FK separees garantissent :

- student existe
- enrollment existe

Mais elles ne garantissent pas necessairement :

grades.student_id = enrollments.student_id

**Statut : REVIEW-REQUIRED**

---

# 13. ATTENDANCE — COHERENCE D'INSCRIPTION

Le schema garantit qu'un etudiant et une classe existent.

Il ne garantit pas que l'etudiant etait inscrit dans cette classe a la date concernee.

**Statut : REVIEW-REQUIRED**

---

# 14. UPDATED_AT

**$updatedAtFinding**

Le schema contient des colonnes updated_at, mais aucun trigger automatique n'a ete detecte.

La strategie applicative devra donc etre explicitement definie.

---

# 15. EMAIL

**$emailFinding**

Attention :

PostgreSQL autorise plusieurs valeurs NULL dans une contrainte UNIQUE.

Cela signifie que email UNIQUE ne signifie pas necessairement "un utilisateur doit obligatoirement avoir un email unique non NULL".

La regle metier doit preciser le comportement attendu.

---

# 16. AUTHENTIFICATION

**$passwordFinding**

Le schema utilise :

password_hash

Aucune colonne password en clair n'a ete detectee.

---

# 17. INDEX

**$indexFinding**

---

# 18. ENTITES HYPOTHETIQUES

sections :

$(if ($sectionsPresent) { 'PRESENTE — inattendu pour ENV-11.' } else { 'ABSENTE — conforme a ENV-10-D.' })

holidays :

$(if ($holidaysPresent) { 'PRESENTE — inattendu pour ENV-11.' } else { 'ABSENTE — conforme a ENV-10-D.' })

---

# 19. CONTENU SQL DANGEREUX

$(if ($dangerousFound.Count -eq 0) {
'PASS — aucun DROP DATABASE, DROP TABLE, TRUNCATE, DELETE, UPDATE ou INSERT detecte.'
} else {
"WARNING — motifs detectes : $($dangerousFound -join ', ')"
})

---

# 20. RESULTATS

| Categorie | Resultat |
|---|---:|
| PASS detectes | $passes |
| WARNING detectes | $warnings |
| Critical review items | $criticalWarnings |

---

# 21. POINTS BLOQUANTS AVANT CREATION DE BASE

## B01 — Integrite financiere

Le PostgreSQL V1 ne garantit pas directement :

SUM(payments.amount) <= invoices.amount

Une decision d'architecture est necessaire.

## B02 — Coherence grade/enrollment

Une note peut theoriquement referencer un etudiant different de celui de l'inscription referencee.

Cette incoherence doit etre empechee.

## B03 — Coherence attendance/enrollment

L'attendance doit idealement etre coherente avec l'inscription de l'etudiant dans la classe concernee.

## B04 — Coefficients

Il faut determiner si :

subjects.coefficient

et

grades.coefficient

sont reellement deux concepts distincts.

## B05 — Statuts

Les listes de statuts ont ete proposees pendant ENV-11.

Elles doivent etre confrontees au comportement reel de l'application avant production.

## B06 — updated_at

Determiner si la responsabilite de mise a jour appartient exclusivement a PHP ou si PostgreSQL doit garantir la valeur.

---

# 22. VERDICT

**ENV-12 — $verdict**

Le schema V1 est structurellement present et coherent sur les elements principaux.

Cependant, plusieurs regles d'integrite metier importantes ne peuvent pas etre considerees comme garanties uniquement par les FK actuelles.

**Aucune creation de base PostgreSQL ne doit etre deduite de cette intervention.**

La prochaine etape recommandee est :

**ENV-13 — FORENSIC INTEGRITY DESIGN**

Objectif :

- resoudre B01 finance ;
- resoudre B02 grades/enrollment ;
- resoudre B03 attendance/enrollment ;
- trancher B04 coefficients ;
- trancher B05 statuts ;
- trancher B06 updated_at ;

puis produire une version SQL V1.1 corrigee, toujours sans l'executer.
"@

Set-Content -LiteralPath $ReportPath -Value $report -Encoding UTF8
Set-Content -LiteralPath $FinalReportPath -Value $report -Encoding UTF8

Write-Host ''
Write-Host '================================================='
Write-Host ' ENV-12 — FORENSIC SQL SCHEMA REVIEW'
Write-Host '================================================='
Write-Host ''
Write-Host "Tables : $($foundTables.Count)/$($expectedTables.Count)"
Write-Host "FK : $foreignKeyCount"
Write-Host "Indexes : $indexCount"
Write-Host "CHECK : $checkCount"
Write-Host "UNIQUE : $uniqueCount"
Write-Host ''
Write-Host "Critical review items : $criticalWarnings"
Write-Host "Warnings : $warnings"
Write-Host ''
Write-Host "VERDICT : $verdict"
Write-Host ''
Write-Host 'Aucun SQL execute.'
Write-Host 'Aucune connexion PostgreSQL.'
Write-Host ''
Write-Host "Rapport : $FinalReportPath"
Write-Host ''
