# ENV-11 — SCHEMA V1 GENERATION REPORT

Date : 2026-10-01 12:35:00

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
| CREATE TABLE | 19 |
| CREATE INDEX | 16 |
| FOREIGN KEY | 20 |
| CHECK detectes | 17 |
| UNIQUE detectes | 6 |
| Tables attendues | 19 |
| Tables manquantes | 0 |

## Tables V1

- roles
- permissions
- role_permissions
- users
- levels
- school_years
- subjects
- teachers
- staff
- classes
- teacher_class_subjects
- students
- parents
- student_parents
- enrollments
- grades
- attendance
- invoices
- payments

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

**ENV-11 — SCHEMA V1 GENERATED / NOT-EXECUTED**

Le fichier SQL existe.

La base PostgreSQL reste inchangee.

La prochaine etape recommandee est :

**ENV-12 — FORENSIC SQL SCHEMA REVIEW**

Cette etape devra auditer le schema.sql genere avant toute creation de base.
