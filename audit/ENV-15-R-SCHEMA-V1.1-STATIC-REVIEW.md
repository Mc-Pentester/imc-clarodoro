# ENV-15-R — FINAL STATIC SCHEMA V1.1 REVIEW

Date : 2026-10-01 13:10:00

Projet : C:\IMC-Clarodoro-securise-client\IMC-Clarodoro

Fichier inspecté : database/schema.sql

## 1. Verdict

**READY-FOR-DB-CREATION**

## 2. Comptages

| Contrôle | Attendu | Réel | Résultat |
|---|---:|---:|---|
| CREATE TABLE | 19 | 19 | PASS |
| FOREIGN KEY | 17 | 17 | PASS |
| UNIQUE | 14 | 14 | PASS |
| CHECK | 23 | 23 | PASS |
| CREATE INDEX | 13 | 13 | PASS |
| CREATE TRIGGER | 0 | 0 | PASS |
| ON DELETE CASCADE | 0 | 0 | PASS |
| ON DELETE RESTRICT | 17 | 17 | PASS |

## 3. Foreign Keys

Les 17 contraintes FOREIGN KEY (toutes ON DELETE RESTRICT) :

1. role_permissions_role_fk : role_id → roles(id) [ligne 78-81]
2. role_permissions_permission_fk : permission_id → permissions(id) [ligne 83-86]
3. users_role_fk : role_id → roles(id) [ligne 121-124]
4. classes_level_fk : level_id → levels(id) [ligne 281-284]
5. teacher_class_subjects_teacher_fk : teacher_id → teachers(id) [ligne 319-322]
6. teacher_class_subjects_class_fk : class_id → classes(id) [ligne 324-327]
7. teacher_class_subjects_subject_fk : subject_id → subjects(id) [ligne 329-332]
8. student_parents_student_fk : student_id → students(id) [ligne 407-410]
9. student_parents_parent_fk : parent_id → parents(id) [ligne 412-415]
10. enrollments_student_fk : student_id → students(id) [ligne 447-450]
11. enrollments_class_fk : class_id → classes(id) [ligne 452-455]
12. enrollments_school_year_fk : school_year_id → school_years(id) [ligne 457-460]
13. grades_enrollment_fk : enrollment_id → enrollments(id) [ligne 495-498]
14. grades_subject_fk : subject_id → subjects(id) [ligne 500-503]
15. attendance_enrollment_fk : enrollment_id → enrollments(id) [ligne 538-541]
16. invoices_student_fk : student_id → students(id) [ligne 588-591]
17. payments_invoice_fk : invoice_id → invoices(id) [ligne 618-621]

## 4. Grades

grades.enrollment_id : PRÉSENT ✓ [ligne 482]
grades.student_id : ABSENT ✓ (conforme B02)
grades.coefficient : ABSENT ✓ (conforme B04)

Définition pertinente de la table grades (lignes 479-504) :

```sql
CREATE TABLE grades (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    enrollment_id UUID NOT NULL,
    subject_id UUID NOT NULL,
    grade NUMERIC(8,2) NOT NULL,
    grade_date DATE NOT NULL DEFAULT CURRENT_DATE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT grades_grade_check CHECK (grade >= 0),
    CONSTRAINT grades_enrollment_fk FOREIGN KEY (enrollment_id) REFERENCES enrollments(id) ON DELETE RESTRICT,
    CONSTRAINT grades_subject_fk FOREIGN KEY (subject_id) REFERENCES subjects(id) ON DELETE RESTRICT
);
```

Table grades correctement structurée avec enrollment_id comme source de vérité pour l'étudiant. Références conservées vers enrollments et subjects.

## 5. Attendance

attendance.enrollment_id : PRÉSENT ✓ [ligne 517]
attendance.student_id : ABSENT ✓ (conforme B03)
attendance.class_id : ABSENT ✓ (conforme B03)
UNIQUE(enrollment_id, attendance_date) : PRÉSENT ✓ [ligne 543-547]

Définition pertinente de la table attendance (lignes 514-548) :

```sql
CREATE TABLE attendance (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    enrollment_id UUID NOT NULL,
    attendance_date DATE NOT NULL,
    status VARCHAR(30) NOT NULL,
    comment TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT attendance_status_check CHECK (status IN ('PRESENT', 'ABSENT', 'LATE', 'EXCUSED')),
    CONSTRAINT attendance_enrollment_fk FOREIGN KEY (enrollment_id) REFERENCES enrollments(id) ON DELETE RESTRICT,
    CONSTRAINT attendance_unique UNIQUE (enrollment_id, attendance_date)
);
```

Table attendance correctement structurée avec enrollment_id comme source de vérité.

## 6. Subjects

subjects.coefficient : PRÉSENT ✓ [ligne 185]
grades.coefficient : ABSENT ✓ (conforme B04)

Coefficient académique de référence correctement positionné dans subjects.

## 7. Finance

invoices.amount CHECK (amount > 0) : PRÉSENT ✓ [ligne 573-574]
payments.amount CHECK (amount > 0) : PRÉSENT ✓ [ligne 610-611]
payments.invoice_id → invoices.id : PRÉSENT ✓ [ligne 618-621]

CHECK concernés :

```sql
CONSTRAINT invoices_amount_check CHECK (amount > 0)
CONSTRAINT payments_amount_check CHECK (amount > 0)
```

Contraintes financières correctes. Protection contre le dépassement de solde par transaction PHP avec verrouillage (documentée en commentaire lignes 554-556).

## 8. Auth

users.password_hash : PRÉSENT ✓ [ligne 94]
users.password : ABSENT ✓

Authentification correcte avec password_hash, aucun mot de passe en clair.

## 9. Unicités

1. role_permissions UNIQUE(role_id, permission_id) : PRÉSENT ✓ [ligne 76 - PRIMARY KEY]
2. student_parents UNIQUE(student_id, parent_id) : PRÉSENT ✓ [ligne 405 - PRIMARY KEY]
3. teacher_class_subjects UNIQUE(teacher_id, class_id, subject_id) : PRÉSENT ✓ [ligne 303-308]
4. students matricule UNIQUE : PRÉSENT ✓ [ligne 358-359]
5. enrollments index unique partiel (student_id, school_year_id) WHERE status = 'ACTIVE' : PRÉSENT ✓ [ligne 464-469]
6. attendance UNIQUE(enrollment_id, attendance_date) : PRÉSENT ✓ [ligne 543-547]

Toutes les unicités requises sont présentes.

## 10. Status

Vérification que les statuts utilisent VARCHAR + CHECK :

CHECK de statut détectés :

- users_status_check : ACTIVE, INACTIVE, SUSPENDED [ligne 112-119]
- school_years_status_check : PLANNED, ACTIVE, CLOSED, ARCHIVED [ligne 167-175]
- teachers_status_check : ACTIVE, INACTIVE, ARCHIVED [ligne 217-224]
- staff_status_check : ACTIVE, INACTIVE, ARCHIVED [ligne 243-250]
- classes_status_check : ACTIVE, INACTIVE, ARCHIVED [ligne 272-279]
- teacher_class_subjects_status_check : ACTIVE, INACTIVE, ARCHIVED [ligne 310-317]
- students_status_check : ACTIVE, INACTIVE, ARCHIVED [ligne 361-368]
- enrollments_status_check : PENDING, ACTIVE, CANCELLED, COMPLETED, ARCHIVED [ligne 436-445]
- attendance_status_check : PRESENT, ABSENT, LATE, EXCUSED [ligne 528-536]
- invoices_status_check : DRAFT, OPEN, PARTIALLY_PAID, PAID, CANCELLED, ARCHIVED [ligne 576-586]

Tous les statuts utilisent VARCHAR + CHECK conformément aux conventions.

## 11. Updated_at

Vérification des tables avec updated_at :

Tables avec updated_at : roles, permissions, users, levels, school_years, subjects, teachers, staff, classes, teacher_class_subjects, students, parents, student_parents, enrollments, grades, attendance, invoices, payments

CREATE TRIGGER : 0 ✓

Conclusion : updated_at est géré côté PHP. Aucun trigger PostgreSQL n'est utilisé.

## 12. Opérations interdites

DROP : 0 (présent uniquement dans les commentaires lignes 672-673)
TRUNCATE : 0
DELETE : 0
INSERT : 0
UPDATE : 0

Aucune instruction SQL destructive ou opérationnelle détectée.

## 13. BEGIN / COMMIT / ROLLBACK

Occurrences détectées :

BEGIN; : ligne 30 (instruction SQL réelle)
COMMIT; : ligne 675 (instruction SQL réelle, précédée de commentaire lignes 670-674)
ROLLBACK : 0 occurrence

Analyse du COMMIT :

Lignes 670-674 :
```sql
-- ============================================================
-- COMMIT
-- ============================================================
--
-- NOTE :
-- Ce COMMIT appartient au script SQL généré.
-- ENV-15 NE L'EXÉCUTE PAS.
--
```

Ligne 675 :
```sql
COMMIT;
```

Le COMMIT est une instruction SQL réelle mais est documentée comme non exécutée par le générateur ENV-15. Le BEGIN est une instruction SQL réelle pour démarrer la transaction. Cette structure est standard pour un fichier DDL transactionnel.

## 14. Triggers / Cascades

ON DELETE CASCADE : 0 ✓
CREATE TRIGGER : 0 ✓

Aucun trigger métier, aucune suppression cascade.

## 15. Cohérence générale

Tables présentes (19) :

1. roles ✓
2. permissions ✓
3. role_permissions ✓
4. users ✓
5. levels ✓
6. school_years ✓
7. subjects ✓
8. teachers ✓
9. staff ✓
10. classes ✓
11. teacher_class_subjects ✓
12. students ✓
13. parents ✓
14. student_parents ✓
15. enrollments ✓
16. grades ✓
17. attendance ✓
18. invoices ✓
19. payments ✓

Total : 19 tables (conforme à l'attendu)

## 16. Conclusion

**READY-FOR-DB-CREATION**

ENV-15-R confirme statiquement que schema.sql V1.1 est prêt pour l'étape de création et d'exécution de la base PostgreSQL. Aucun SQL n'a été exécuté pendant cette vérification.

Tous les contrôles sont PASS :

- Structure cohérente avec 19 tables
- 17 FK toutes ON DELETE RESTRICT
- 14 contraintes d'unicité correctes
- 23 CHECK appropriées
- 13 indexes sur les FK importantes
- Aucun trigger métier
- Aucune suppression cascade
- Corrections B01-B06 appliquées conformément à ENV-12/ENV-13
- Authentification sécurisée avec password_hash
- Finance protégée par CHECK > 0
- Grades et attendance refactorisés avec enrollment_id comme source de vérité
- Coefficients unifiés dans subjects
- updated_at géré côté PHP
- BEGIN/COMMIT structure transactionnelle standard
- Aucune instruction SQL destructive ou opérationnelle
