# ENV-15 — SCHEMA V1.1 GENERATION REPORT

Date : 2026-10-01 13:00:00

Projet : C:\IMC-Clarodoro-securise-client\IMC-Clarodoro

## Verdict

**SCHEMA-V1.1-GENERATED / NOT-EXECUTED**

## Fichier

database/schema.sql

## Modifications principales

### B01 — Intégrité financière

- invoices.amount : CHECK modifié de >= 0 à > 0 (montant strictement positif)
- payments.amount : CHECK > 0 déjà présent (inchangé)
- Aucune contrainte SQL pour SUM(payments.amount) <= invoices.amount
- Responsabilité : transaction PHP avec verrouillage de facture
- Solde calculé côté application : invoice.amount - SUM(payments.amount)

### B02 — Grades / Enrollment

- grades.student_id : SUPPRIMÉ
- grades.enrollment_id : conservé comme source de vérité pour l'étudiant
- grades.coefficient : SUPPRIMÉ (utiliser subjects.coefficient)
- La source de vérité devient : enrollment_id → enrollments.student_id

### B03 — Attendance / Enrollment

- attendance.student_id : SUPPRIMÉ
- attendance.class_id : SUPPRIMÉ
- attendance.enrollment_id : AJOUTÉ comme FK vers enrollments
- L'inscription fournit l'étudiant, la classe et l'année scolaire
- Unicité modifiée : UNIQUE(enrollment_id, attendance_date)

### B04 — Coefficients

- subjects.coefficient : conservé comme coefficient académique de référence
- grades.coefficient : SUPPRIMÉ (sans preuve fonctionnelle de coefficient variable par note)

### B05 — Statuts

- Statuts conservés tels que définis dans V1 (pas de nouveaux statuts ajoutés)
- Chaque table conserve ses propres CHECK adaptées à son domaine

### B06 — updated_at

- updated_at conservé sur toutes les tables où il était présent
- Aucun trigger PostgreSQL créé
- Responsabilité : PHP/application layer

## Tables

1. roles
2. permissions
3. role_permissions
4. users
5. levels
6. school_years
7. subjects
8. teachers
9. staff
10. classes
11. teacher_class_subjects
12. students
13. parents
14. student_parents
15. enrollments
16. grades
17. attendance
18. invoices
19. payments

Total : 19 tables

## Contraintes

### PK (Primary Key)

- 19 tables avec id UUID PRIMARY KEY DEFAULT gen_random_uuid()

### FK (Foreign Key)

- role_permissions : 2 FK (role_id, permission_id)
- users : 1 FK (role_id)
- classes : 1 FK (level_id)
- teacher_class_subjects : 3 FK (teacher_id, class_id, subject_id)
- student_parents : 2 FK (student_id, parent_id)
- enrollments : 3 FK (student_id, class_id, school_year_id)
- grades : 2 FK (enrollment_id, subject_id)
- attendance : 1 FK (enrollment_id)
- invoices : 1 FK (student_id)
- payments : 1 FK (invoice_id)

Total FK : 17

### UNIQUE

- roles_name_unique
- permissions_name_unique
- role_permissions PK (role_id, permission_id)
- users_username_unique
- users_email_unique
- levels_code_unique
- school_years_label_unique
- subjects_code_unique
- classes_code_unique
- teacher_class_subjects_unique (teacher_id, class_id, subject_id)
- students_matricule_unique
- student_parents PK (student_id, parent_id)
- enrollments_one_active_per_student_year (index unique partiel)
- attendance_unique (enrollment_id, attendance_date)

Total UNIQUE : 14

### CHECK

- roles_name_not_blank
- permissions_name_not_blank
- users_username_not_blank
- users_status_check
- levels_name_not_blank
- school_years_dates_check
- school_years_status_check
- subjects_name_not_blank
- subjects_coefficient_check
- teachers_status_check
- staff_status_check
- classes_name_not_blank
- classes_status_check
- teacher_class_subjects_status_check
- students_status_check
- students_sex_check
- enrollments_status_check
- grades_grade_check
- attendance_status_check
- invoices_amount_check
- invoices_status_check
- payments_amount_check
- payments_method_check

Total CHECK : 23

### INDEX

- idx_students_status
- idx_students_last_name
- idx_enrollments_student
- idx_enrollments_class
- idx_enrollments_school_year
- idx_grades_enrollment
- idx_grades_subject
- idx_attendance_enrollment_date
- idx_invoices_student
- idx_payments_invoice
- idx_teacher_class_subjects_class
- idx_teacher_class_subjects_teacher
- idx_teacher_class_subjects_subject

Total INDEX : 13

## Contrôles de sécurité

- Aucun SQL exécuté
- Aucune DB créée
- Aucune migration créée
- Aucun code applicatif modifié
- Aucune dépendance installée
- Aucun service modifié

## Contrôles négatifs

- DROP = 0
- TRUNCATE = 0
- DELETE = 0
- INSERT = 0
- UPDATE = 0
- ON DELETE CASCADE = 0
- CREATE TRIGGER métier = 0

## Contrôles spécifiques V1.1

1. grades.student_id : ABSENT (conforme à B02)
2. grades.enrollment_id : PRÉSENT (conforme à B02)
3. grades.coefficient : ABSENT (conforme à B04)
4. attendance.student_id : ABSENT (conforme à B03)
5. attendance.class_id : ABSENT (conforme à B03)
6. attendance.enrollment_id : PRÉSENT (conforme à B03)
7. updated_at : PRÉSENT sur les tables applicatives (conforme à B06)
8. CREATE TRIGGER : 0 (conforme à B06)
9. ON DELETE CASCADE : 0 (conforme aux conventions)
10. password_hash : PRÉSENT, password : ABSENT (conforme aux conventions de sécurité)
11. invoices.amount CHECK : > 0 (conforme à B01)
12. payments.amount CHECK : > 0 (conforme à B01)
13. role_permissions PK : (role_id, permission_id) - unicité conforme
14. student_parents PK : (student_id, parent_id) - unicité conforme
15. teacher_class_subjects UNIQUE : (teacher_id, class_id, subject_id) - unicité conforme
16. enrollments index unique partiel : (student_id, school_year_id) WHERE status = 'ACTIVE' - conforme
17. grades CHECK : grade >= 0 - conforme
18. attendance UNIQUE : (enrollment_id, attendance_date) - conforme

## Points restant à valider avant création DB

Aucun point structurel bloquant ne reste ouvert dans le schéma V1.1.

Les points suivants nécessitent une validation applicative avant création de la base :

1. **B01** : Implémenter la transaction PHP avec verrouillage de facture pour protéger contre le dépassement de solde
2. **B03** : Vérifier temporellement que l'inscription était active à la date d'attendance (règle applicative)

Ces points sont documentés dans le schéma par des commentaires SQL et relèvent de la logique applicative, pas de la structure du schéma.

## Verdict final

**ENV-15 TERMINÉ**

Le schéma PostgreSQL V1.1 a été généré en appliquant les corrections identifiées par ENV-12 et ENV-13.

**Schema V1.1 généré**
**SQL NON EXÉCUTÉ**
**DB NON CRÉÉE**
**Code NON MODIFIÉ**

Rapport : audit/ENV-15-SCHEMA-V1.1-GENERATION-REPORT.md
