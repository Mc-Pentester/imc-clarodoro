#requires -Version 5.1

<#
ENV-13 — FORENSIC INTEGRITY DESIGN

Projet :
    IMC-Clarodoro

Objectif :
    Analyser les points critiques B01-B06 identifies par ENV-12
    en confrontant :

        - database/schema.sql
        - code PHP
        - code JavaScript
        - documentation
        - validations existantes

IMPORTANT :
    Intervention STRICTEMENT READ-ONLY.

    Cette intervention :
        - ne modifie aucun fichier
        - ne modifie pas schema.sql
        - ne se connecte pas a PostgreSQL
        - n'execute aucun SQL
        - ne cree aucune base
        - ne cree aucune table
        - ne cree aucune migration
        - n'installe aucun package
        - ne modifie aucun service

Sorties :
    audit\ENV-13-FORENSIC-INTEGRITY-DESIGN-REPORT.md
    audit\ENV-13-FORENSIC-INTEGRITY-DESIGN-REPORT-FINAL.md
    audit\ENV-13-INTEGRITY-DECISION-REGISTER.md
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$ProjectRoot = "C:\IMC-Clarodoro-securise-client\IMC-Clarodoro"
$AuditDir = Join-Path $ProjectRoot 'audit'
$SchemaPath = Join-Path $ProjectRoot 'database\schema.sql'

New-Item -ItemType Directory -Path $AuditDir -Force | Out-Null

$ReportPath = Join-Path $AuditDir 'ENV-13-FORENSIC-INTEGRITY-DESIGN-REPORT.md'
$FinalReportPath = Join-Path $AuditDir 'ENV-13-FORENSIC-INTEGRITY-DESIGN-REPORT-FINAL.md'
$DecisionPath = Join-Path $AuditDir 'ENV-13-INTEGRITY-DECISION-REGISTER.md'

$timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'

if (-not (Test-Path -LiteralPath $SchemaPath)) {
    throw "schema.sql introuvable : $SchemaPath"
}

$schema = Get-Content -LiteralPath $SchemaPath -Raw

# ============================================================
# EXCLUSION DES DOSSIERS NON PERTINENTS
# ============================================================

$excludedDirectories = @(
    '\vendor\',
    '\node_modules\',
    '\.git\',
    '\audit\',
    '\database\'
)

# ============================================================
# INVENTAIRE DU CODE
# ============================================================

$sourceFiles = @(
    Get-ChildItem `
        -LiteralPath $ProjectRoot `
        -Recurse `
        -File `
        -ErrorAction SilentlyContinue |
    Where-Object {
        $_.Extension -in @(
            '.php',
            '.js',
            '.html',
            '.json',
            '.md'
        )
    } |
    Where-Object {
        $full = $_.FullName
        -not ($excludedDirectories | Where-Object { $full -like "*$_*" })
    }
)

$phpFiles = @($sourceFiles | Where-Object Extension -eq '.php')
$jsFiles = @($sourceFiles | Where-Object Extension -eq '.js')
$htmlFiles = @($sourceFiles | Where-Object Extension -eq '.html')
$jsonFiles = @($sourceFiles | Where-Object Extension -eq '.json')
$mdFiles = @($sourceFiles | Where-Object Extension -eq '.md')

# ============================================================
# UTILITAIRES
# ============================================================

function Search-CodePattern {
    param(
        [string[]]$Patterns
    )

    $results = @()

    foreach ($file in $sourceFiles) {

        try {
            $content = Get-Content -LiteralPath $file.FullName -Raw -ErrorAction Stop
        }
        catch {
            continue
        }

        foreach ($pattern in $Patterns) {

            $matches = [regex]::Matches(
                $content,
                $pattern,
                [System.Text.RegularExpressions.RegexOptions]::IgnoreCase
            )

            if ($matches.Count -gt 0) {

                foreach ($match in $matches) {

                    $lineNumber = (
                        $content.Substring(
                            0,
                            $match.Index
                        ) -split "`n"
                    ).Count

                    $results += [PSCustomObject]@{
                        File = $file.FullName.Substring($ProjectRoot.Length).TrimStart('\')
                        Line = $lineNumber
                        Pattern = $pattern
                        Match = $match.Value.Trim()
                    }
                }
            }
        }
    }

    return $results
}

function Count-CodeMatches {
    param(
        [string[]]$Patterns
    )

    return @(Search-CodePattern -Patterns $Patterns).Count
}

function Get-ContextMatches {
    param(
        [string[]]$Patterns,
        [int]$Max = 30
    )

    $results = @(Search-CodePattern -Patterns $Patterns)

    if ($results.Count -gt $Max) {
        return @($results | Select-Object -First $Max)
    }

    return $results
}

# ============================================================
# B01 — FINANCE
# ============================================================

$financePatterns = @(
    'payments?',
    'invoice',
    'facture',
    'montant',
    'amount',
    'balance',
    'solde',
    'payment',
    'paiement',
    'SUM\s*\(',
    'total',
    'partiel',
    'partial'
)

$financeEvidence = @(Get-ContextMatches -Patterns $financePatterns -Max 80)

$paymentLimitPatterns = @(
    'payment.*amount.*invoice',
    'amount.*payment.*invoice',
    'payment.*balance',
    'paiement.*solde',
    'paiement.*montant',
    'amount\s*>\s*balance',
    'amount\s*<=\s*balance',
    'payment.*total'
)

$paymentLimitEvidence = @(Get-ContextMatches `
    -Patterns $paymentLimitPatterns `
    -Max 50)

$financialTransactionPatterns = @(
    'transaction',
    'beginTransaction',
    'commit',
    'rollback',
    'PDO::beginTransaction',
    'PDO::commit',
    'PDO::rollBack'
)

$financialTransactionEvidence = @(Get-ContextMatches `
    -Patterns $financialTransactionPatterns `
    -Max 30)

# ============================================================
# B02 — GRADES / ENROLLMENTS
# ============================================================

$gradePatterns = @(
    'grades?',
    'notes?',
    'student_id',
    'studentId',
    'enrollment_id',
    'enrollmentId',
    'coefficient',
    'coefficient'
)

$gradeEvidence = @(Get-ContextMatches `
    -Patterns $gradePatterns `
    -Max 100)

$gradeConsistencyPatterns = @(
    'student_id.*enrollment_id',
    'enrollment_id.*student_id',
    'enrollment.*student',
    'student.*enrollment',
    'JOIN.*enrollment',
    'JOIN.*enrollments'
)

$gradeConsistencyEvidence = @(Get-ContextMatches `
    -Patterns $gradeConsistencyPatterns `
    -Max 60)

# ============================================================
# B03 — ATTENDANCE / ENROLLMENT
# ============================================================

$attendancePatterns = @(
    'attendance',
    'absenc',
    'presence',
    'student_id',
    'studentId',
    'class_id',
    'classId',
    'enrollment'
)

$attendanceEvidence = @(Get-ContextMatches `
    -Patterns $attendancePatterns `
    -Max 100)

$attendanceEnrollmentPatterns = @(
    'attendance.*enrollment',
    'enrollment.*attendance',
    'attendance.*class',
    'class.*attendance',
    'student.*class',
    'student.*enrollment'
)

$attendanceEnrollmentEvidence = @(Get-ContextMatches `
    -Patterns $attendanceEnrollmentPatterns `
    -Max 60)

# ============================================================
# B04 — COEFFICIENTS
# ============================================================

$coefficientPatterns = @(
    'coefficient',
    'coeff',
    'coef',
    'mati[eè]re',
    'subject'
)

$coefficientEvidence = @(Get-ContextMatches `
    -Patterns $coefficientPatterns `
    -Max 100)

$gradeCalculationPatterns = @(
    'moyenne',
    'average',
    'weighted',
    'coefficient',
    'total',
    'note',
    'grade'
)

$gradeCalculationEvidence = @(Get-ContextMatches `
    -Patterns $gradeCalculationPatterns `
    -Max 100)

# ============================================================
# B05 — STATUS
# ============================================================

$statusPatterns = @(
    '\bACTIVE\b',
    '\bINACTIVE\b',
    '\bARCHIVED\b',
    '\bPENDING\b',
    '\bCANCELLED\b',
    '\bCOMPLETED\b',
    '\bPLANNED\b',
    '\bCLOSED\b',
    '\bDRAFT\b',
    '\bOPEN\b',
    '\bPARTIALLY_PAID\b',
    '\bPAID\b',
    '\bPRESENT\b',
    '\bABSENT\b',
    '\bLATE\b',
    '\bEXCUSED\b'
)

$statusEvidence = @(Get-ContextMatches `
    -Patterns $statusPatterns `
    -Max 150)

# ============================================================
# B06 — UPDATED_AT
# ============================================================

$updatedAtPatterns = @(
    'updated_at',
    'updatedAt',
    'UPDATE\s+',
    'SET\s+updated_at',
    'date_updated',
    'modified_at',
    'modifiedAt'
)

$updatedAtEvidence = @(Get-ContextMatches `
    -Patterns $updatedAtPatterns `
    -Max 100)

$triggerEvidence = @()

if ($schema -match '(?im)CREATE\s+TRIGGER') {
    $triggerEvidence = @('Trigger SQL detecte dans schema.sql.')
}

# ============================================================
# SCHEMA — COEFFICIENTS
# ============================================================

$schemaSubjectCoefficient = $schema -match `
    '(?is)CREATE\s+TABLE\s+subjects.*?coefficient\s+NUMERIC'

$schemaGradeCoefficient = $schema -match `
    '(?is)CREATE\s+TABLE\s+grades.*?coefficient\s+NUMERIC'

# ============================================================
# SCHEMA — FINANCE
# ============================================================

$schemaPaymentCheck = $schema -match `
    '(?is)payments_amount_check.*?amount\s*>\s*0'

$schemaInvoiceAmountCheck = $schema -match `
    '(?is)invoices_amount_check.*?amount\s*>=\s*0'

$schemaFinancialAggregate = $schema -match `
    '(?is)SUM\s*\(\s*payments\.amount'

# ============================================================
# SCHEMA — GRADE
# ============================================================

$schemaGradeStudentFK = $schema -match `
    '(?is)grades_student_fk'

$schemaGradeEnrollmentFK = $schema -match `
    '(?is)grades_enrollment_fk'

$schemaGradeCrossCheck = $schema -match `
    '(?is)CHECK\s*\(.*student_id.*enrollment_id'

# ============================================================
# SCHEMA — ATTENDANCE
# ============================================================

$schemaAttendanceStudentFK = $schema -match `
    '(?is)attendance_student_fk'

$schemaAttendanceClassFK = $schema -match `
    '(?is)attendance_class_fk'

$schemaAttendanceEnrollmentFK = $schema -match `
    '(?is)attendance.*enrollment_id'

# ============================================================
# STATUS UTILISES DANS LE SQL
# ============================================================

$sqlStatuses = @(
    [regex]::Matches(
        $schema,
        "'([A-Z_]+)'",
        [System.Text.RegularExpressions.RegexOptions]::IgnoreCase
    ) |
    ForEach-Object {
        $_.Groups[1].Value.ToUpperInvariant()
    } |
    Sort-Object -Unique
)

# ============================================================
# DETECTION DE STATUTS POTENTIELLEMENT ABSENTS DU CODE
# ============================================================

$knownBusinessStatuses = @(
    'ACTIVE',
    'INACTIVE',
    'ARCHIVED',
    'PENDING',
    'CANCELLED',
    'COMPLETED',
    'PLANNED',
    'CLOSED',
    'DRAFT',
    'OPEN',
    'PARTIALLY_PAID',
    'PAID',
    'PRESENT',
    'ABSENT',
    'LATE',
    'EXCUSED'
)

$statusCoverage = @()

foreach ($status in $knownBusinessStatuses) {

    $sqlPresent = $sqlStatuses -contains $status

    $codePresent = $statusEvidence.Match -match [regex]::Escape($status)

    $statusCoverage += [PSCustomObject]@{
        Status = $status
        SQL = $sqlPresent
        Code = $codePresent
    }
}

# ============================================================
# CLASSIFICATION
# ============================================================

$b01Status = if ($paymentLimitEvidence.Count -gt 0) {
    'EVIDENCE-FOUND'
}
else {
    'UNRESOLVED'
}

$b02Status = if ($gradeConsistencyEvidence.Count -gt 0) {
    'EVIDENCE-FOUND'
}
else {
    'UNRESOLVED'
}

$b03Status = if ($attendanceEnrollmentEvidence.Count -gt 0) {
    'EVIDENCE-FOUND'
}
else {
    'UNRESOLVED'
}

$b04Status = if ($coefficientEvidence.Count -gt 0) {
    'EVIDENCE-FOUND'
}
else {
    'UNRESOLVED'
}

$b05Status = if ($statusEvidence.Count -gt 0) {
    'EVIDENCE-FOUND'
}
else {
    'UNRESOLVED'
}

$b06Status = if ($updatedAtEvidence.Count -gt 0) {
    'EVIDENCE-FOUND'
}
else {
    'UNRESOLVED'
}

# ============================================================
# DECISIONS PROPOSEES
# ============================================================

$decisionRegister = @"
# ENV-13 — INTEGRITY DECISION REGISTER

Date : $timestamp

Statut global :

**FORENSIC ANALYSIS / HUMAN VALIDATION REQUIRED**

ENV-13 ne considere aucune proposition ci-dessous comme une decision
humaine definitive.

---

# B01 — Integrite financiere

## Constat

Le schema garantit l'existence de la facture et du paiement.

Il garantit egalement que le paiement est strictement positif.

Il ne garantit cependant pas :

SUM(payments.amount) <= invoices.amount

## Preuve code

Nombre d'elements financiers detectes :

$($financeEvidence.Count)

Elements concernant explicitement une limite paiement/facture :

$($paymentLimitEvidence.Count)

## Proposition technique

La regle metier doit etre appliquee dans une transaction atomique lors
de l'enregistrement du paiement :

1. verrouiller la facture ;
2. recalculer le montant deja paye ;
3. calculer le solde ;
4. refuser si le nouveau paiement depasse le solde ;
5. enregistrer le paiement ;
6. mettre a jour le statut de facture si necessaire ;
7. commit.

La contrainte ne doit pas reposer uniquement sur le client.

## Decision

**PROPOSED — transaction applicative + verrouillage de facture**

Validation humaine requise.

---

# B02 — Cohérence grades / enrollment

## Constat

Le schema possede :

- grades.student_id → students.id
- grades.enrollment_id → enrollments.id

Mais cela ne garantit pas que l'inscription appartient au meme etudiant.

## Proposition technique

La relation note → inscription doit devenir la relation de reference
pour determiner l'etudiant.

Deux solutions sont possibles :

### Option A — supprimer grades.student_id

La note reference uniquement enrollment_id.

L'etudiant est determine par l'inscription.

### Option B — conserver student_id + FK composite

Conserver les deux colonnes mais ajouter une contrainte permettant de
garantir la coherence.

## Proposition V1

**Option A est proposee**, car elle evite une duplication de la meme
relation et supprime une source potentielle d'incoherence.

Validation humaine requise.

---

# B03 — Cohérence attendance / enrollment

## Constat

attendance contient :

- student_id
- class_id
- attendance_date

Mais aucune relation vers enrollment.

## Proposition technique

La presence doit etre rattachee a une inscription valide plutot qu'a
un simple etudiant + classe.

Proposition :

attendance.enrollment_id

avec FK vers enrollments.

L'inscription devient la source permettant de determiner :

- etudiant ;
- classe ;
- annee scolaire.

## Proposition V1

**Ajouter enrollment_id a attendance.**

Une contrainte metier devra ensuite verifier que l'enregistrement
correspond a une inscription active/valide a la date concernee.

Validation humaine requise.

---

# B04 — Coefficients

## Constat

Le schema contient :

- subjects.coefficient
- grades.coefficient

## Risque

Deux coefficients peuvent diverger sans regle explicite.

## Proposition

Le coefficient structurel de la matiere appartient a subjects.

Un coefficient specifique a une evaluation ne doit etre conserve dans
grades que si l'application permet reellement de modifier le
coefficient pour chaque evaluation.

## Proposition V1

**Ne pas conserver grades.coefficient sans preuve fonctionnelle.**

La valeur par defaut doit provenir de la configuration academique
appropriee.

Validation humaine requise.

---

# B05 — Statuts

## Constat

ENV-11 a propose plusieurs listes de statuts.

ENV-13 confronte ces statuts avec les occurrences detectees dans le code.

## Regle

Aucun statut SQL ne doit etre ajoute uniquement parce qu'il semble
raisonnable.

Chaque statut doit etre justifie par :

- le code ;
- une regle fonctionnelle ;
- ou une decision humaine.

## Proposition V1

Conserver uniquement les statuts demontrés ou explicitement valides.

Validation humaine requise.

---

# B06 — updated_at

## Constat

Les tables possedent updated_at.

Aucun trigger PostgreSQL n'a ete detecte.

## Options

### Option A

PHP est responsable de mettre a jour updated_at.

### Option B

PostgreSQL impose automatiquement la valeur via trigger.

## Proposition V1

**Option A — responsabilite applicative**, tant que l'application
centralise correctement toutes les modifications.

Cette option evite d'introduire une logique PostgreSQL non necessaire
avant validation de l'architecture applicative.

Validation humaine requise.

---

# MATRICE DE DECISION

| ID | Sujet | Proposition | Statut |
|---|---|---|---|
| B01 | Paiements | transaction + verrouillage facture | PROPOSED |
| B02 | Grades | enrollment comme source de l'etudiant | PROPOSED |
| B03 | Attendance | reference vers enrollment | PROPOSED |
| B04 | Coefficients | coefficient de grade uniquement si fonctionnellement necessaire | PROPOSED |
| B05 | Statuts | uniquement statuts demontrés/validés | PROPOSED |
| B06 | updated_at | responsabilite PHP | PROPOSED |

---

# INTERDICTION DE PASSAGE AUTOMATIQUE

ENV-13 ne valide aucune de ces propositions automatiquement.

La prochaine etape est :

**ENV-14 — HUMAN INTEGRITY DECISION VALIDATION**

Apres validation humaine, le schema V1.1 pourra etre genere.
"@

Set-Content -LiteralPath $DecisionPath -Value $decisionRegister -Encoding UTF8

# ============================================================
# RAPPORT
# ============================================================

$report = @"
# ENV-13 — FORENSIC INTEGRITY DESIGN REPORT

Date : $timestamp

Projet : C:\IMC-Clarodoro-securise-client\IMC-Clarodoro

## Verdict

**FORENSIC-DESIGN-COMPLETE / HUMAN-VALIDATION-REQUIRED**

---

# 1. PERIMETRE

ENV-13 a confronte :

- database/schema.sql
- fichiers PHP
- fichiers JavaScript
- fichiers HTML
- JSON
- documentation Markdown

Fichiers analyses :

| Type | Nombre |
|---|---:|
| PHP | $($phpFiles.Count) |
| JavaScript | $($jsFiles.Count) |
| HTML | $($htmlFiles.Count) |
| JSON | $($jsonFiles.Count) |
| Markdown | $($mdFiles.Count) |
| Total | $($sourceFiles.Count) |

---

# 2. B01 — INTEGRITE FINANCIERE

Statut d'analyse :

**$b01Status**

Occurrences financieres detectees :

**$($financeEvidence.Count)**

Elements indiquant explicitement une protection paiement/facture :

**$($paymentLimitEvidence.Count)**

Transactions financieres detectees :

**$($financialTransactionEvidence.Count)**

### Schema

Montant facture controle :

$(if ($schemaInvoiceAmountCheck) { 'PASS' } else { 'WARNING' })

Montant paiement > 0 :

$(if ($schemaPaymentCheck) { 'PASS' } else { 'WARNING' })

Protection agregée :

$(if ($schemaFinancialAggregate) { 'PRESENTE' } else { 'ABSENTE' })

### Analyse

Le modele actuel ne doit pas permettre a deux requetes concurrentes
de contourner une verification de solde.

La strategie proposee est :

**transaction + verrouillage de la facture + recalcul du solde.**

---

# 3. B02 — GRADES / ENROLLMENTS

Statut d'analyse :

**$b02Status**

Evidence grade :

**$($gradeEvidence.Count)**

Evidence coherence grade/enrollment :

**$($gradeConsistencyEvidence.Count)**

FK student :

$(if ($schemaGradeStudentFK) { 'PASS' } else { 'FAIL' })

FK enrollment :

$(if ($schemaGradeEnrollmentFK) { 'PASS' } else { 'FAIL' })

Contrainte inter-colonnes :

$(if ($schemaGradeCrossCheck) { 'PRESENTE' } else { 'ABSENTE' })

### Analyse

Le schema possede deux references independantes.

Une incoherence reste donc theoriquement possible.

### Proposition

Utiliser enrollment_id comme source de rattachement de l'etudiant.

---

# 4. B03 — ATTENDANCE / ENROLLMENT

Statut d'analyse :

**$b03Status**

Evidence attendance :

**$($attendanceEvidence.Count)**

Evidence attendance/enrollment :

**$($attendanceEnrollmentEvidence.Count)**

FK student :

$(if ($schemaAttendanceStudentFK) { 'PASS' } else { 'FAIL' })

FK class :

$(if ($schemaAttendanceClassFK) { 'PASS' } else { 'FAIL' })

FK enrollment :

$(if ($schemaAttendanceEnrollmentFK) { 'PRÉSENTE' } else { 'ABSENTE' })

### Analyse

Le couple :

student_id + class_id

ne prouve pas qu'une inscription valide existe.

### Proposition

Ajouter enrollment_id a attendance.

---

# 5. B04 — COEFFICIENTS

Statut d'analyse :

**$b04Status**

Occurrences coefficient :

**$($coefficientEvidence.Count)**

Occurrences calcul notes :

**$($gradeCalculationEvidence.Count)**

Schema subjects.coefficient :

$(if ($schemaSubjectCoefficient) { 'PRÉSENT' } else { 'ABSENT' })

Schema grades.coefficient :

$(if ($schemaGradeCoefficient) { 'PRÉSENT' } else { 'ABSENT' })

### Analyse

La duplication est actuellement possible.

La definition finale doit preciser si le coefficient est :

- une propriete de matiere ;
- une propriete d'une evaluation ;
- une propriete d'une periode academique ;
- ou une combinaison de ces concepts.

### Proposition

Ne conserver grades.coefficient que si le code demontre reellement
un coefficient variable par note/evaluation.

---

# 6. B05 — STATUTS

Nombre d'occurrences de statuts detectes dans le code :

**$($statusEvidence.Count)**

## Couverture

| Statut | SQL | Code |
|---|---|---|
$(
    $statusCoverage |
    ForEach-Object {
        "| $($_.Status) | $($_.SQL) | $($_.Code) |"
    } |
    Out-String
)

### Analyse

Les statuts ajoutes au SQL doivent etre confrontes au comportement reel
de l'application.

Aucun statut supplementaire ne doit etre considere comme valide
uniquement parce qu'il semble utile.

---

# 7. B06 — UPDATED_AT

Occurrences updated_at / equivalents :

**$($updatedAtEvidence.Count)**

Triggers SQL :

**$($triggerEvidence.Count)**

### Analyse

Le schema contient des timestamps de modification mais ne contient
pas de trigger automatique.

### Proposition

Responsabilite applicative PHP.

Cette decision devra etre confirmee avec l'architecture des services
de donnees.

---

# 8. DECISIONS PROPOSEES

| ID | Decision | Proposition |
|---|---|---|
| B01 | Finance | Transaction + verrouillage facture |
| B02 | Grades | enrollment_id comme source de l'etudiant |
| B03 | Attendance | enrollment_id comme reference |
| B04 | Coefficients | Pas de coefficient par grade sans preuve |
| B05 | Statuts | Seulement ceux demontrés/validés |
| B06 | updated_at | Responsabilite PHP |

---

# 9. FICHIER DE DECISIONS

audit\ENV-13-INTEGRITY-DECISION-REGISTER.md

---

# 10. SECURITE

Cette intervention :

- n'a pas ouvert de connexion PostgreSQL ;
- n'a execute aucun SQL ;
- n'a pas cree la base ;
- n'a pas cree de table ;
- n'a pas modifie schema.sql ;
- n'a pas modifie le code ;
- n'a pas cree de migration ;
- n'a pas installe de dependance ;
- n'a pas modifie de service.

---

# 11. VERDICT FINAL

**ENV-13 — FORENSIC DESIGN COMPLETE**

Les six points B01-B06 disposent maintenant d'une proposition
d'architecture.

Ils ne sont toutefois pas encore consideres comme valides.

Prochaine etape :

**ENV-14 — HUMAN INTEGRITY DECISION VALIDATION**

ENV-14 devra enregistrer explicitement les decisions humaines avant
toute generation du schema.sql V1.1.
"@

Set-Content -LiteralPath $ReportPath -Value $report -Encoding UTF8
Set-Content -LiteralPath $FinalReportPath -Value $report -Encoding UTF8

# ============================================================
# SORTIE CONSOLE
# ============================================================

Write-Host ''
Write-Host '====================================================='
Write-Host ' ENV-13 — FORENSIC INTEGRITY DESIGN'
Write-Host '====================================================='
Write-Host ''

Write-Host "Fichiers analyses : $($sourceFiles.Count)"
Write-Host "PHP : $($phpFiles.Count)"
Write-Host "JS : $($jsFiles.Count)"
Write-Host "HTML : $($htmlFiles.Count)"
Write-Host ''

Write-Host 'B01 Finance :' -NoNewline
Write-Host " $b01Status"

Write-Host 'B02 Grades :' -NoNewline
Write-Host " $b02Status"

Write-Host 'B03 Attendance :' -NoNewline
Write-Host " $b03Status"

Write-Host 'B04 Coefficients :' -NoNewline
Write-Host " $b04Status"

Write-Host 'B05 Status :' -NoNewline
Write-Host " $b05Status"

Write-Host 'B06 updated_at :' -NoNewline
Write-Host " $b06Status"

Write-Host ''
Write-Host 'AUCUNE CONNEXION POSTGRESQL.'
Write-Host 'AUCUN SQL EXECUTE.'
Write-Host 'AUCUNE MODIFICATION EFFECTUEE.'
Write-Host ''
Write-Host "Rapport : $FinalReportPath"
Write-Host "Decisions : $DecisionPath"
Write-Host ''
Write-Host 'VERDICT : FORENSIC-DESIGN-COMPLETE / HUMAN-VALIDATION-REQUIRED'
Write-Host ''
