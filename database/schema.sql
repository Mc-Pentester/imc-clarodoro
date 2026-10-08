-- ============================================================
-- IMC-CLARODORO
-- PostgreSQL schema V1.1
-- ============================================================
--
-- Généré par :
--     ENV-15-SCHEMA-V1.1-GENERATION
--
-- Date de génération :
--     2026-10-01 13:00:00
--
-- IMPORTANT :
--     Ce fichier est un artefact SQL.
--     ENV-15 NE L'EXÉCUTE PAS.
--
-- Base cible prévue :
--     imc_clarodoro
--
-- Décisions de référence :
--     ENV-10-D, ENV-12, ENV-13
--
-- Convention :
--     snake_case
--     UUID
--     FK restrictives par défaut
--     statuts VARCHAR + CHECK
--
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

    max_points NUMERIC(8,2) NOT NULL DEFAULT 100,

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
        ),

    CONSTRAINT subjects_max_points_check
        CHECK (max_points > 0)
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
-- USER / TEACHER SCOPE
-- ============================================================

-- Un utilisateur enseignant peut être rattaché à un ou plusieurs
-- enregistrements teachers. Cette relation est la source de vérité
-- du périmètre serveur ; elle ne doit jamais être fournie par le client.
CREATE TABLE user_teachers (
    user_id UUID PRIMARY KEY,
    teacher_id UUID NOT NULL,

    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    CONSTRAINT user_teachers_user_fk
        FOREIGN KEY (user_id)
        REFERENCES users(id)
        ON DELETE RESTRICT,

    CONSTRAINT user_teachers_teacher_fk
        FOREIGN KEY (teacher_id)
        REFERENCES teachers(id)
        ON DELETE RESTRICT
);

CREATE INDEX idx_user_teachers_teacher
    ON user_teachers(teacher_id);

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

    -- F-02-A: staged server-authoritative profile fields not yet normalized.
    profile_data JSONB NOT NULL DEFAULT '{}'::jsonb,

    status VARCHAR(30) NOT NULL DEFAULT 'ACTIVE',

    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    CONSTRAINT students_matricule_unique
        UNIQUE (matricule),

    CONSTRAINT students_profile_data_object_check
        CHECK (jsonb_typeof(profile_data) = 'object'),

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

-- Un seul enrollment ACTIVE par étudiant et année scolaire.
CREATE UNIQUE INDEX enrollments_one_active_per_student_year
    ON enrollments (
        student_id,
        school_year_id
    )
    WHERE status = 'ACTIVE';

-- ============================================================
-- GRADES
-- ============================================================

-- Source de vérité pour l'étudiant : enrollment_id → enrollments.student_id
-- grades.student_id supprimé pour éviter l'incohérence potentielle
-- grades.coefficient supprimé : utiliser subjects.coefficient comme référence

CREATE TABLE grades (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    enrollment_id UUID NOT NULL,
    subject_id UUID NOT NULL,

    grade NUMERIC(8,2) NOT NULL,

    grade_date DATE NOT NULL DEFAULT CURRENT_DATE,

    assessment_number SMALLINT NOT NULL DEFAULT 1,

    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    CONSTRAINT grades_grade_check
        CHECK (grade >= 0),

    CONSTRAINT grades_assessment_number_check
        CHECK (assessment_number BETWEEN 1 AND 3),

    CONSTRAINT grades_enrollment_fk
        FOREIGN KEY (enrollment_id)
        REFERENCES enrollments(id)
        ON DELETE RESTRICT,

    CONSTRAINT grades_subject_fk
        FOREIGN KEY (subject_id)
        REFERENCES subjects(id)
        ON DELETE RESTRICT
);

CREATE UNIQUE INDEX grades_enrollment_subject_assessment_unique
    ON grades(enrollment_id, subject_id, assessment_number);

-- ============================================================
-- ATTENDANCE
-- ============================================================

-- Source de vérité : enrollment_id
-- student_id et class_id supprimés pour éviter la redondance
-- L'inscription fournit l'étudiant, la classe et l'année scolaire

CREATE TABLE attendance (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    enrollment_id UUID NOT NULL,

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

    CONSTRAINT attendance_enrollment_fk
        FOREIGN KEY (enrollment_id)
        REFERENCES enrollments(id)
        ON DELETE RESTRICT,

    CONSTRAINT attendance_unique
        UNIQUE (
            enrollment_id,
            attendance_date
        )
);

-- ============================================================
-- FINANCE
-- ============================================================

-- Solde financier calculé côté application :
-- invoice.amount - SUM(payments.amount)
-- Protection contre le dépassement de solde par transaction PHP avec verrouillage

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
        CHECK (amount > 0),

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

CREATE INDEX idx_grades_enrollment
    ON grades(enrollment_id);

CREATE INDEX idx_grades_subject
    ON grades(subject_id);

CREATE INDEX idx_attendance_enrollment_date
    ON attendance(enrollment_id, attendance_date);

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
-- TRANSACTION CONTROL
-- ============================================================
--
-- NOTE :
-- Les instructions BEGIN et COMMIT SQL réelles ont été supprimées par ENV-16.
-- Ce fichier DDL est prêt pour exécution manuelle ou via outil approprié.
-- ENV-16 NE L'EXÉCUTE PAS.
--
