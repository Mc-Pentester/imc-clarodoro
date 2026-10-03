#requires -Version 5.1

<#
ENV-11 — SCHEMA SQL V1 GENERATION

Projet :
    IMC-Clarodoro

Objectif :
    Generer le premier schema.sql PostgreSQL V1 a partir de la
    baseline de decisions ENV-10-D.

IMPORTANT :
    Cette intervention est GENERATIVE mais NON EXECUTIVE.

    Elle :
      - genere database/schema.sql
      - genere un rapport de tracabilite
      - documente les hypotheses
      - documente les points a valider

    Elle NE :
      - se connecte pas a PostgreSQL
      - ne cree pas la base imc_clarodoro
      - n'execute aucun SQL
      - ne cree aucune table reelle
      - ne cree aucune migration
      - ne modifie aucune donnee
      - ne modifie aucun code PHP/JS/HTML
      - n'installe aucun package
      - ne modifie aucun service Windows

Sorties :
    database/schema.sql
    audit/ENV-11-SCHEMA-V1-GENERATION-REPORT.md
    audit/ENV-11-SCHEMA-V1-GENERATION-REPORT-FINAL.md
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$ProjectRoot = "C:\IMC-Clarodoro-securise-client\IMC-Clarodoro"
$AuditDir = Join-Path $ProjectRoot 'audit'
$DatabaseDir = Join-Path $ProjectRoot 'database'

New-Item -ItemType Directory -Path $AuditDir -Force | Out-Null
New-Item -ItemType Directory -Path $DatabaseDir -Force | Out-Null

$BaselinePath = Join-Path $AuditDir 'ENV-10-D-FORENSIC-DATA-MODEL-V1-DECISION-VALIDATION-REPORT-FINAL.md'
$DecisionReportPath = Join-Path $AuditDir 'ENV-10-D-FORENSIC-DATA-MODEL-V1-DECISION-VALIDATION-REPORT-FINAL.md'

$SchemaPath = Join-Path $DatabaseDir 'schema.sql'
$ReportPath = Join-Path $AuditDir 'ENV-11-SCHEMA-V1-GENERATION-REPORT.md'
$FinalReportPath = Join-Path $AuditDir 'ENV-11-SCHEMA-V1-GENERATION-REPORT-FINAL.md'

$timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'

if (-not (Test-Path -LiteralPath $BaselinePath)) {
    throw "Baseline ENV-10-D introuvable : $BaselinePath"
}

if (-not (Test-Path -LiteralPath $DecisionReportPath)) {
    throw "Rapport ENV-10-D introuvable : $DecisionReportPath"
}

# ------------------------------------------------------------
# IMPORTANT :
# Ne jamais ecraser silencieusement un schema.sql existant.
# ------------------------------------------------------------

if (Test-Path -LiteralPath $SchemaPath) {
    $existingContent = Get-Content -LiteralPath $SchemaPath -Raw

    if ($existingContent.Trim().Length -gt 0) {
        throw @"
database/schema.sql existe deja et contient du contenu.

ENV-11 refuse volontairement de l'ecraser automatiquement.

Fichier :
$SchemaPath

Aucune modification n'a ete effectuee.

Si le fichier existant est uniquement le placeholder actuellement
audite, il devra etre remplace explicitement apres verification.
"@
    }
}

# ------------------------------------------------------------
# Schema PostgreSQL V1
# ------------------------------------------------------------

$schema = @'
-- ============================================================
-- IMC-CLARODORO
-- PostgreSQL schema V1
-- ============================================================
--
-- Genere par :
--     ENV-11-SCHEMA-V1-GENERATION
--
-- Date de generation :
--     __GENERATION_DATE__
--
-- IMPORTANT :
--     Ce fichier est un artefact SQL.
--     ENV-11 NE L'EXECUTE PAS.
--
-- Base cible prevue :
--     imc_clarodoro
--
-- Decisions de reference :
--     ENV-10-D
--
-- Convention :
--     snake_case
--     UUID
--     FK restrictives par defaut
--     statuts VARCHAR + CHECK
--
-- ============================================================

BEGIN;

-- ============================================================
-- EXTENSIONS
-- ============================================================

CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- ============================================================
-- SECURITY / RBAC
-- ============================================================

CREATE TABLE roles (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name VARCHAR(100) NOT NULL,
    description TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    CONSTRAINT roles_name_unique
        UNIQUE (name),

    CONSTRAINT roles_name_not_blank
        CHECK (length(trim(name)) > 0)
);

CREATE TABLE permissions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name VARCHAR(150) NOT NULL,
    description TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    CONSTRAINT permissions_name_unique
        UNIQUE (name),

    CONSTRAINT permissions_name_not_blank
        CHECK (length(trim(name)) > 0)
);

CREATE TABLE role_permissions (
    role_id UUID NOT NULL,
    permission_id UUID NOT NULL,

    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    PRIMARY KEY (role_id, permission_id),

    CONSTRAINT role_permissions_role_fk
        FOREIGN KEY (role_id)
        REFERENCES roles(id)
        ON DELETE RESTRICT,

    CONSTRAINT role_permissions_permission_fk
        FOREIGN KEY (permission_id)
        REFERENCES permissions(id)
        ON DELETE RESTRICT
);

CREATE TABLE users (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    username VARCHAR(100) NOT NULL,
    email VARCHAR(255),
    password_hash TEXT NOT NULL,

    role_id UUID NOT NULL,

    status VARCHAR(30) NOT NULL DEFAULT 'ACTIVE',

    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    CONSTRAINT users_username_unique
        UNIQUE (username),

    CONSTRAINT users_email_unique
        UNIQUE (email),

    CONSTRAINT users_username_not_blank
        CHECK (length(trim(username)) > 0),

    CONSTRAINT users_status_check
        CHECK (
            status IN (
                'ACTIVE',
                'INACTIVE',
                'SUSPENDED'
            )
        ),

    CONSTRAINT users_role_fk
        FOREIGN KEY (role_id)
        REFERENCES roles(id)
        ON DELETE RESTRICT
);

-- ============================================================
-- ACADEMIC REFERENCE
-- ============================================================

CREATE TABLE levels (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    code VARCHAR(50) NOT NULL,
    name VARCHAR(150) NOT NULL,
    description TEXT,

    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    CONSTRAINT levels_code_unique
        UNIQUE (code),

    CONSTRAINT levels_name_not_blank
        CHECK (length(trim(name)) > 0)
);

CREATE TABLE school_years (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    label VARCHAR(50) NOT NULL,

    start_date DATE NOT NULL,
    end_date DATE NOT NULL,

    status VARCHAR(30) NOT NULL DEFAULT 'ACTIVE',

    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    CONSTRAINT school_years_label_unique
        UNIQUE (label),

    CONSTRAINT school_years_dates_check
        CHECK (end_date > start_date),

    CONSTRAINT school_years_status_check
        CHECK (
            status IN (
                'PLANNED',
                'ACTIVE',
                'CLOSED',
                'ARCHIVED'
            )
        )
);

CREATE TABLE subjects (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    code VARCHAR(50) NOT NULL,
    name VARCHAR(150) NOT NULL,
    description TEXT,

    coefficient NUMERIC(8,2),

    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    CONSTRAINT subjects_code_unique
        UNIQUE (code),

    CONSTRAINT subjects_name_not_blank
        CHECK (length(trim(name)) > 0),

    CONSTRAINT subjects_coefficient_check
        CHECK (
            coefficient IS NULL
            OR coefficient > 0
        )
);

CREATE TABLE teachers (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    first_name VARCHAR(150) NOT NULL,
    last_name VARCHAR(150) NOT NULL,

    email VARCHAR(255),
    phone VARCHAR(50),

    status VARCHAR(30) NOT NULL DEFAULT 'ACTIVE',

    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    CONSTRAINT teachers_status_check
        CHECK (
            status IN (
                'ACTIVE',
                'INACTIVE',
                'ARCHIVED'
            )
        )
);

CREATE TABLE staff (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    first_name VARCHAR(150) NOT NULL,
    last_name VARCHAR(150) NOT NULL,

    function_name VARCHAR(150),

    phone VARCHAR(50),
    email VARCHAR(255),

    status VARCHAR(30) NOT NULL DEFAULT 'ACTIVE',

    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    CONSTRAINT staff_status_check
        CHECK (
            status IN (
                'ACTIVE',
                'INACTIVE',
                'ARCHIVED'
            )
        )
);

CREATE TABLE classes (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    code VARCHAR(50) NOT NULL,
    name VARCHAR(150) NOT NULL,

    level_id UUID,

    status VARCHAR(30) NOT NULL DEFAULT 'ACTIVE',

    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    CONSTRAINT classes_code_unique
        UNIQUE (code),

    CONSTRAINT classes_name_not_blank
        CHECK (length(trim(name)) > 0),

    CONSTRAINT classes_status_check
        CHECK (
            status IN (
                'ACTIVE',
                'INACTIVE',
                'ARCHIVED'
            )
        ),

    CONSTRAINT classes_level_fk
        FOREIGN KEY (level_id)
        REFERENCES levels(id)
        ON DELETE RESTRICT
);

-- ============================================================
-- TEACHER / CLASS / SUBJECT ASSIGNMENTS
-- ============================================================

CREATE TABLE teacher_class_subjects (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    teacher_id UUID NOT NULL,
    class_id UUID NOT NULL,
    subject_id UUID NOT NULL,

    status VARCHAR(30) NOT NULL DEFAULT 'ACTIVE',

    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    CONSTRAINT teacher_class_subjects_unique
        UNIQUE (
            teacher_id,
            class_id,
            subject_id
        ),

    CONSTRAINT teacher_class_subjects_status_check
        CHECK (
            status IN (
                'ACTIVE',
                'INACTIVE',
                'ARCHIVED'
            )
        ),

    CONSTRAINT teacher_class_subjects_teacher_fk
        FOREIGN KEY (teacher_id)
        REFERENCES teachers(id)
        ON DELETE RESTRICT,

    CONSTRAINT teacher_class_subjects_class_fk
        FOREIGN KEY (class_id)
        REFERENCES classes(id)
        ON DELETE RESTRICT,

    CONSTRAINT teacher_class_subjects_subject_fk
        FOREIGN KEY (subject_id)
        REFERENCES subjects(id)
        ON DELETE RESTRICT
);

-- ============================================================
-- STUDENTS / PARENTS
-- ============================================================

CREATE TABLE students (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    matricule VARCHAR(100) NOT NULL,

    last_name VARCHAR(150) NOT NULL,
    first_name VARCHAR(150) NOT NULL,

    date_of_birth DATE,
    sex VARCHAR(20),

    address TEXT,
    phone VARCHAR(50),

    status VARCHAR(30) NOT NULL DEFAULT 'ACTIVE',

    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    CONSTRAINT students_matricule_unique
        UNIQUE (matricule),

    CONSTRAINT students_status_check
        CHECK (
            status IN (
                'ACTIVE',
                'INACTIVE',
                'ARCHIVED'
            )
        ),

    CONSTRAINT students_sex_check
        CHECK (
            sex IS NULL
            OR sex IN (
                'M',
                'F',
                'OTHER',
                'UNSPECIFIED'
            )
        )
);

CREATE TABLE parents (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    last_name VARCHAR(150) NOT NULL,
    first_name VARCHAR(150) NOT NULL,

    phone VARCHAR(50),
    email VARCHAR(255),
    address TEXT,

    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE student_parents (
    student_id UUID NOT NULL,
    parent_id UUID NOT NULL,

    relationship_type VARCHAR(50),
    is_primary BOOLEAN NOT NULL DEFAULT FALSE,

    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    PRIMARY KEY (student_id, parent_id),

    CONSTRAINT student_parents_student_fk
        FOREIGN KEY (student_id)
        REFERENCES students(id)
        ON DELETE RESTRICT,

    CONSTRAINT student_parents_parent_fk
        FOREIGN KEY (parent_id)
        REFERENCES parents(id)
        ON DELETE RESTRICT
);

-- ============================================================
-- ENROLLMENTS
-- ============================================================

CREATE TABLE enrollments (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    student_id UUID NOT NULL,
    class_id UUID NOT NULL,
    school_year_id UUID NOT NULL,

    status VARCHAR(30) NOT NULL DEFAULT 'ACTIVE',

    enrollment_date DATE NOT NULL DEFAULT CURRENT_DATE,

    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    CONSTRAINT enrollments_status_check
        CHECK (
            status IN (
                'PENDING',
                'ACTIVE',
                'CANCELLED',
                'COMPLETED',
                'ARCHIVED'
            )
        ),

    CONSTRAINT enrollments_student_fk
        FOREIGN KEY (student_id)
        REFERENCES students(id)
        ON DELETE RESTRICT,

    CONSTRAINT enrollments_class_fk
        FOREIGN KEY (class_id)
        REFERENCES classes(id)
        ON DELETE RESTRICT,

    CONSTRAINT enrollments_school_year_fk
        FOREIGN KEY (school_year_id)
        REFERENCES school_years(id)
        ON DELETE RESTRICT
);

-- Un seul enrollment ACTIVE par etudiant et annee scolaire.
CREATE UNIQUE INDEX enrollments_one_active_per_student_year
    ON enrollments (
        student_id,
        school_year_id
    )
    WHERE status = 'ACTIVE';

-- ============================================================
-- GRADES
-- ============================================================

CREATE TABLE grades (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    student_id UUID NOT NULL,
    subject_id UUID NOT NULL,
    enrollment_id UUID NOT NULL,

    grade NUMERIC(8,2) NOT NULL,
    coefficient NUMERIC(8,2),

    grade_date DATE NOT NULL DEFAULT CURRENT_DATE,

    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    CONSTRAINT grades_grade_check
        CHECK (grade >= 0),

    CONSTRAINT grades_coefficient_check
        CHECK (
            coefficient IS NULL
            OR coefficient > 0
        ),

    CONSTRAINT grades_student_fk
        FOREIGN KEY (student_id)
        REFERENCES students(id)
        ON DELETE RESTRICT,

    CONSTRAINT grades_subject_fk
        FOREIGN KEY (subject_id)
        REFERENCES subjects(id)
        ON DELETE RESTRICT,

    CONSTRAINT grades_enrollment_fk
        FOREIGN KEY (enrollment_id)
        REFERENCES enrollments(id)
        ON DELETE RESTRICT
);

-- ============================================================
-- ATTENDANCE
-- ============================================================

CREATE TABLE attendance (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    student_id UUID NOT NULL,
    class_id UUID NOT NULL,

    attendance_date DATE NOT NULL,

    status VARCHAR(30) NOT NULL,

    comment TEXT,

    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    CONSTRAINT attendance_status_check
        CHECK (
            status IN (
                'PRESENT',
                'ABSENT',
                'LATE',
                'EXCUSED'
            )
        ),

    CONSTRAINT attendance_student_fk
        FOREIGN KEY (student_id)
        REFERENCES students(id)
        ON DELETE RESTRICT,

    CONSTRAINT attendance_class_fk
        FOREIGN KEY (class_id)
        REFERENCES classes(id)
        ON DELETE RESTRICT,

    CONSTRAINT attendance_unique
        UNIQUE (
            student_id,
            class_id,
            attendance_date
        )
);

-- ============================================================
-- FINANCE
-- ============================================================

CREATE TABLE invoices (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    student_id UUID NOT NULL,

    amount NUMERIC(12,2) NOT NULL,
    status VARCHAR(30) NOT NULL DEFAULT 'OPEN',

    invoice_date DATE NOT NULL DEFAULT CURRENT_DATE,

    description TEXT,

    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    CONSTRAINT invoices_amount_check
        CHECK (amount >= 0),

    CONSTRAINT invoices_status_check
        CHECK (
            status IN (
                'DRAFT',
                'OPEN',
                'PARTIALLY_PAID',
                'PAID',
                'CANCELLED',
                'ARCHIVED'
            )
        ),

    CONSTRAINT invoices_student_fk
        FOREIGN KEY (student_id)
        REFERENCES students(id)
        ON DELETE RESTRICT
);

CREATE TABLE payments (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    invoice_id UUID NOT NULL,

    amount NUMERIC(12,2) NOT NULL,

    payment_date DATE NOT NULL DEFAULT CURRENT_DATE,

    method VARCHAR(50) NOT NULL,

    reference VARCHAR(150),

    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    CONSTRAINT payments_amount_check
        CHECK (amount > 0),

    CONSTRAINT payments_method_check
        CHECK (
            length(trim(method)) > 0
        ),

    CONSTRAINT payments_invoice_fk
        FOREIGN KEY (invoice_id)
        REFERENCES invoices(id)
        ON DELETE RESTRICT
);

-- ============================================================
-- INDEXES
-- ============================================================

CREATE INDEX idx_students_status
    ON students(status);

CREATE INDEX idx_students_last_name
    ON students(last_name);

CREATE INDEX idx_enrollments_student
    ON enrollments(student_id);

CREATE INDEX idx_enrollments_class
    ON enrollments(class_id);

CREATE INDEX idx_enrollments_school_year
    ON enrollments(school_year_id);

CREATE INDEX idx_grades_student
    ON grades(student_id);

CREATE INDEX idx_grades_subject
    ON grades(subject_id);

CREATE INDEX idx_grades_enrollment
    ON grades(enrollment_id);

CREATE INDEX idx_attendance_student_date
    ON attendance(student_id, attendance_date);

CREATE INDEX idx_invoices_student
    ON invoices(student_id);

CREATE INDEX idx_payments_invoice
    ON payments(invoice_id);

CREATE INDEX idx_teacher_class_subjects_class
    ON teacher_class_subjects(class_id);

CREATE INDEX idx_teacher_class_subjects_teacher
    ON teacher_class_subjects(teacher_id);

CREATE INDEX idx_teacher_class_subjects_subject
    ON teacher_class_subjects(subject_id);

-- ============================================================
-- COMMIT
-- ============================================================
--
-- NOTE :
-- Ce COMMIT appartient au script SQL genere.
-- ENV-11 NE L'EXECUTE PAS.
--
COMMIT;
'@

$schema = $schema.Replace('__GENERATION_DATE__', $timestamp)

# ------------------------------------------------------------
# Ecriture
# ------------------------------------------------------------

Set-Content `
    -LiteralPath $SchemaPath `
    -Value $schema `
    -Encoding UTF8

# ------------------------------------------------------------
# Controles statiques
# ------------------------------------------------------------

$createTableCount = ([regex]::Matches($schema, '(?im)^\s*CREATE\s+TABLE\s+')).Count
$createIndexCount = ([regex]::Matches($schema, '(?im)^\s*CREATE\s+(?:UNIQUE\s+)?INDEX\s+')).Count
$foreignKeyCount = ([regex]::Matches($schema, '(?im)^\s*FOREIGN\s+KEY\s*\(')).Count
$checkCount = ([regex]::Matches($schema, '(?im)^\s*CONSTRAINT\s+.*_check\s*$')).Count
$uniqueConstraintCount = ([regex]::Matches($schema, '(?im)^\s*CONSTRAINT\s+.*_unique\s*$')).Count

$tableNames = @(
    'roles'
    'permissions'
    'role_permissions'
    'users'
    'levels'
    'school_years'
    'subjects'
    'teachers'
    'staff'
    'classes'
    'teacher_class_subjects'
    'students'
    'parents'
    'student_parents'
    'enrollments'
    'grades'
    'attendance'
    'invoices'
    'payments'
)

$missingTables = @()

foreach ($table in $tableNames) {
    if ($schema -notmatch "(?im)CREATE\s+TABLE\s+$([regex]::Escape($table))\s*\(") {
        $missingTables += $table
    }
}

$report = @"
# ENV-11 — SCHEMA V1 GENERATION REPORT

Date : $timestamp

Projet : C:\IMC-Clarodoro-securise-client\IMC-Clarodoro

## Statut

**SCHEMA-V1-GENERATED / NOT-EXECUTED**

Le premier schema PostgreSQL V1 a ete genere a partir de la baseline
ENV-10-D.

## Securite d'execution

ENV-11 n'a effectue aucune connexion PostgreSQL.

Aucun SQL n'a ete execute.

Aucune base de donnees n'a ete creee.

Aucune table reelle n'a ete creee.

Aucune donnee n'a ete modifiee.

Aucune migration n'a ete creee.

Aucun service Windows n'a ete modifie.

## Fichier genere

database/schema.sql

## Controles statiques

| Controle | Resultat |
|---|---:|
| CREATE TABLE | $createTableCount |
| CREATE INDEX | $createIndexCount |
| FOREIGN KEY | $foreignKeyCount |
| CHECK detectes | $checkCount |
| UNIQUE detectes | $uniqueConstraintCount |
| Tables attendues | $($tableNames.Count) |
| Tables manquantes | $($missingTables.Count) |

## Tables V1

$($tableNames | ForEach-Object { "- $_" } | Out-String)

## Architecture

### Securite

users
→ roles
→ role_permissions
→ permissions

### Academique

students
→ enrollments
→ classes
→ levels

enrollments
→ school_years

students
→ grades
→ subjects

### Enseignants

teachers
→ teacher_class_subjects
← classes
← subjects

### Parents

students
→ student_parents
← parents

### Presence

students
→ attendance
← classes

### Finance

students
→ invoices
→ payments

## Points volontairement NON inclus

Les elements suivants ne sont pas presents comme tables V1 :

- sections
- holidays

Ils restent soumis a validation fonctionnelle.

## Points necessitant encore une validation fonctionnelle

### D04 / D08 — Affectations enseignants

La table teacher_class_subjects est generee comme association explicite.

Il faudra verifier que cette granularite correspond exactement au fonctionnement attendu.

### D14 — Notes / coefficients

subjects.coefficient est present comme coefficient de matiere.

grades.coefficient est egalement present pour permettre un coefficient explicite au niveau de la note lorsque le modele fonctionnel l'exige.

Cette duplication potentielle devra etre resolue avant la mise en production du schema.

### D15 — Moyennes

Aucune moyenne n'est stockee comme donnee primaire.

Les moyennes devront etre calculees a partir des notes et coefficients.

### D16 — Presence / absence

La table attendance remplace conceptuellement la separation attendance / absences.

Les regles fonctionnelles devront confirmer que les statuts :

- PRESENT
- ABSENT
- LATE
- EXCUSED

couvrent reellement le besoin.

### D19 — Solde financier

Aucune colonne balance n'est stockee dans invoices.

Le solde est destine a etre calcule a partir de :

invoice.amount - SUM(payments.amount)

La strategie d'implementation applicative devra etre definie avant l'utilisation reelle.

### D20 — Methodes de paiement

Aucune liste metier definitive n'est imposee dans le SQL.

Le champ est controle comme valeur textuelle non vide.

La liste exacte des moyens de paiement doit etre validee avant durcissement.

## Point critique — integrite financiere

Le schema garantit :

- montant facture >= 0
- montant paiement > 0
- paiement rattache a une facture existante
- suppression restrictive des factures referencees

Mais le schema V1 ne garantit pas encore au niveau PostgreSQL que :

SUM(payments.amount) <= invoices.amount

Cette regle devra etre traitee dans une intervention dediee d'integrite financiere.

## Point critique — coherence student/enrollment/grade

La FK grades.enrollment_id garantit l'existence de l'inscription.

La FK grades.student_id garantit l'existence de l'eleve.

Mais le SQL V1 ne garantit pas encore que :

grades.student_id = enrollments.student_id

Cette coherence inter-colonnes devra etre traitee avant production.

## Point critique — attendance

La table empeche deux enregistrements identiques pour :

student + class + date

Mais elle ne garantit pas encore que l'eleve etait effectivement inscrit dans cette classe a cette date.

Cette regle appartient a l'integrite metier et devra etre traitee separement.

## Validation syntaxique

ENV-11 n'execute volontairement pas psql.

La validation effectuee ici est donc statique.

Une validation PostgreSQL reelle sera une etape distincte.

## Verdict

**ENV-11 — SCHEMA V1 GENERATED / NOT EXECUTED**

Le fichier SQL existe.

La base PostgreSQL reste inchangee.

La prochaine etape recommandee est :

**ENV-12 — FORENSIC SQL SCHEMA REVIEW**

Cette etape devra auditer le schema.sql genere avant toute creation de base.
"@

Set-Content `
    -LiteralPath $ReportPath `
    -Value $report `
    -Encoding UTF8

Set-Content `
    -LiteralPath $FinalReportPath `
    -Value $report `
    -Encoding UTF8

Write-Host ''
Write-Host '================================================='
Write-Host ' ENV-11 — SCHEMA V1 GENERATION'
Write-Host '================================================='
Write-Host ''
Write-Host "Schema : $SchemaPath"
Write-Host "Tables : $createTableCount"
Write-Host "Indexes : $createIndexCount"
Write-Host "Foreign Keys : $foreignKeyCount"
Write-Host "Checks : $checkCount"
Write-Host ''
Write-Host 'Fichiers generes :'
Write-Host " - $SchemaPath"
Write-Host " - $ReportPath"
Write-Host " - $FinalReportPath"
Write-Host ''
Write-Host 'AUCUNE connexion PostgreSQL.'
Write-Host 'AUCUN SQL execute.'
Write-Host 'AUCUNE base creee.'
Write-Host 'AUCUNE table reelle creee.'
Write-Host ''
Write-Host 'STATUT : SCHEMA-V1-GENERATED / NOT-EXECUTED'
Write-Host ''
