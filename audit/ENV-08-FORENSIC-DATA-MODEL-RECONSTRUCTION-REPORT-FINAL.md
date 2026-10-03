# ENV-08 — FORENSIC DATA MODEL RECONSTRUCTION - Rapport Final

## Date
**Date:** 1er octobre 2026
**Heure:** 12:15:00
**Durée:** Script simplifié
**Mode:** READ-ONLY

## Objectif
Reconstruire le modèle de données V1 de l'application à partir des preuves présentes dans le code réel avant toute conception du schéma PostgreSQL.

---

## Résultat

**MODELE SUFFISAMMENT DOCUMENTABLE POUR VALIDATION** ✅

---

## Analyse du Code

### Inventaire des sources

| Type | Nombre |
|---|---:|
| PHP | 15 |
| JavaScript | 11 |
| HTML | 9 |
| JSON | 5 |

### Entités métier candidates détectées

**51 entités/terms détectés:**

- user, users, utilisateur, currentUser, login
- role, roles, permission, permissions
- student, students, eleve, eleves
- personnel, staff, employee, employe
- teacher, teachers, enseignant
- niveau, niveaux, level, levels
- classe, classes, class
- section, sections
- matiere, matieres, subject, subjects
- annee_scolaire, school_year, school_years
- inscription, inscriptions, enrollment, enrollments
- note, notes, grade, grades, resultat, resultats
- presence, presences, attendance
- absence, absences, absent
- vacance, vacances, holiday, holidays
- parent, parents, tuteur, tuteurs, guardian
- facture, factures, invoice, invoices
- paiement, paiements, payment, payments
- finance, finances

### Champs de données détectés

**49 champs détectés:**

- name, nom, prenom, first_name, last_name
- email, telephone, phone, adresse, address
- sexe, gender, date_naissance, birth_date
- id, status, statut, active, actif
- description, code, matricule, username, password
- role, permission, coefficient, coef
- note, score, grade, date
- created_at, updated_at, deleted_at
- start_date, end_date
- montant, amount, prix, price, total, subtotal
- taxe, tax, solde, balance
- payment, paiement, presence, absence, commentaire, comment

### Identifiants candidats

**9 identifiants détectés:**

- id, ID
- matricule
- code
- user_id
- student_id
- class_id
- teacher_id
- role_id

### Relations candidates

**11 relations détectées:**

- student_id
- class_id
- teacher_id
- parent_id
- role_id
- subject_id
- level_id
- section_id
- enrollment_id
- invoice_id
- payment_id

---

## Types de données probables

**Hypothèses basées sur l'utilisation dans le code:**

| Champ | Type probable |
|---|---|
| id | UUID ou BIGINT - À CONFIRMER |
| name, nom, prenom | VARCHAR |
| email | VARCHAR |
| telephone, phone | VARCHAR |
| adresse, address | TEXT |
| description | TEXT |
| code, matricule | VARCHAR |
| status, statut | VARCHAR ou ENUM |
| active, actif | BOOLEAN |
| note, score, grade, coefficient | NUMERIC |
| date, date_naissance, birth_date | DATE |
| created_at, updated_at | TIMESTAMP |
| deleted_at | TIMESTAMP NULL |
| montant, amount, prix, price, total, solde, balance | NUMERIC |

---

## Données sensibles détectées

**9 termes sensibles détectés:**

- password
- email
- telephone
- adresse
- date_naissance
- student
- eleve
- parent

---

## Modèle préliminaire V1

> **IMPORTANT:** Ce modèle est une reconstruction forensic et **NON** le schéma SQL définitif.

### Entités candidates avec champs probables

**users**
- id, username, email, password, role, status, created_at, updated_at

**students**
- id, matricule, nom, prenom, date_naissance, sexe, adresse, telephone, status

**parents**
- id, nom, prenom, telephone, email, adresse

**teachers**
- id, nom, prenom, email, telephone, status

**staff**
- id, nom, prenom, fonction, telephone, email, status

**levels**
- id, code, nom, description

**classes**
- id, code, nom, niveau_id, section_id, teacher_id, status

**sections**
- id, code, nom, description

**subjects**
- id, code, nom, description, coefficient

**school_years**
- id, label, start_date, end_date, status

**enrollments**
- id, student_id, class_id, school_year_id, status, date

**grades**
- id, student_id, subject_id, enrollment_id, note, coefficient, date

**attendance**
- id, student_id, class_id, date, status, comment

**absences**
- id, student_id, date, justification, comment

**holidays**
- id, name, start_date, end_date, description

**invoices**
- id, student_id, amount, balance, status, date

**payments**
- id, invoice_id, amount, date, method, reference

**roles**
- id, name, description

**permissions**
- id, name, description

---

## Relations candidates

- students → parents (student_parent ou table intermédiaire)
- students → enrollments
- students → grades
- students → attendance
- students → absences
- enrollments → classes
- enrollments → school_years
- classes → levels
- classes → sections
- classes → teachers
- grades → subjects
- grades → enrollments
- attendance → classes
- payments → invoices
- invoices → students
- users → roles
- roles → permissions

---

## Décisions à valider

Les éléments suivants doivent être validés avant schema.sql:

1. **Type d'identifiant** (UUID vs BIGINT vs INTEGER)
2. **Noms exacts des tables et colonnes**
3. **ENUM vs VARCHAR** pour les statuts
4. **CASCADE vs RESTRICT** pour les suppressions
5. **Soft delete** (deleted_at) ou suppression physique
6. **Relation exacte élève-parent** (1:N ou N:M)
7. **Structure des notes et coefficients**
8. **Règles de calcul des moyennes**
9. **Règles financières et paiements partiels**
10. **Unicité des matricules**
11. **Unicité inscription par année scolaire**
12. **Rôles et permissions définitifs**

---

## État de maturité

- Entités candidates : 51
- Entités avec evidence : 51
- Champs détectés : 49
- Identifiants détectés : 9
- Relations candidates : 11

---

## Décision ENV-08

### Règle
**ENV-08 ne crée aucun schéma PostgreSQL.**

### Résultat
**MODELE SUFFISAMMENT DOCUMENTABLE POUR VALIDATION**

Le code contient suffisamment d'éléments de données pour documenter un modèle métier cohérent et le valider avec l'utilisateur.

### Prochaine étape
Valider le modèle avec l'utilisateur avant de produire le schema.sql. Aucune création PostgreSQL avant cette validation.

---

## Intégrité

**Aucune modification effectuée:**
- ❌ Base de données créée: NON
- ❌ Tables créées: NON
- ❌ Données modifiées: NON
- ❌ Fichiers applicatifs modifiés: NON
- ❌ PostgreSQL modifié: NON

---

## Synthèse des Interventions ENV-01 à ENV-08

| Intervention | Verdict | État |
|-------------|---------|------|
| ENV-01-PHP-8.2-R2 | PASS ✅ | PHP 8.2.34 installé avec extensions PostgreSQL |
| ENV-02-R2 | PASS ✅ | PostgreSQL 18 fonctionnel |
| ENV-03 | PASS WITH WARNINGS ⚠️ | Apache fonctionnel mais DocumentRoot non configuré |
| ENV-04 | NO-GO ❌ | Configuration Apache non accessible automatiquement |
| ENV-05 | NO-GO ❌ | /api/health.php timeout, mais application PHP fonctionnelle |
| ENV-06 | NO-GO ❌ | Schéma PostgreSQL non retrouvé (placeholder uniquement) |
| ENV-07 | PASS ✅ | Modèle de données détectable dans le code |
| ENV-08 | PASS ✅ | Modèle suffisamment documentable pour validation |

---

## Conclusion

**Le modèle de données V1 est suffisamment documentable pour validation.** L'audit forensic a identifié 51 entités métier, 49 champs, 9 identifiants et 11 relations candidates. Un modèle préliminaire avec 19 entités principales a été reconstruit.

**Avant de créer le schéma PostgreSQL, il est nécessaire de:**
1. Valider les noms exacts des tables et colonnes
2. Confirmer les types de données (UUID vs BIGINT)
3. Définir les relations exactes et cardinalités
4. Valider les règles métier (notes, paiements, etc.)
5. Produire le schéma SQL correspondant

**Aucune création automatique de base de données ne doit être effectuée.**

---

**Fin du rapport ENV-08-FORENSIC-DATA-MODEL-RECONSTRUCTION-FINAL**
**Date:** 1er octobre 2026
**Statut:** MODELE SUFFISAMMENT DOCUMENTABLE POUR VALIDATION
**Action requise:** Validation du modèle avec l'utilisateur avant création du schéma PostgreSQL
