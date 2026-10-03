# ENV-12 — FORENSIC SQL SCHEMA REVIEW - Rapport Final

Date : 2026-10-01 12:40:00

Projet : C:\IMC-Clarodoro-securise-client\IMC-Clarodoro

## Verdict

**REVIEW-REQUIRED**

ENV-12 est une revue statique et non destructive de :

database/schema.sql

Aucun SQL n'a ete execute.

---

# 1. INVENTAIRE

| Element | Resultat |
|---|---:|
| Tables attendues | 19 |
| Tables trouvees | 19 |
| Tables manquantes | 0 |
| CREATE TABLE | 19 |
| FOREIGN KEY | 20 |
| CREATE INDEX | 16 |
| CHECK | 17 |
| UNIQUE | 6 |

### Tables manquantes

Aucune.

---

# 2. PK / UUID

PASS — toutes les tables principales utilisent un id UUID PRIMARY KEY.

PASS — les PK UUID disposent d'une generation automatique (gen_random_uuid()).

---

# 3. NAMING

PASS — aucun identifiant SQL CamelCase detecte.

---

# 4. FOREIGN KEYS / DELETE

Foreign keys avec ON DELETE RESTRICT : 20

Foreign keys avec ON DELETE CASCADE : 0

Foreign keys avec ON DELETE SET NULL : 0

PASS — aucune suppression CASCADE detectee.

Foreign keys sans regle ON DELETE explicite : 0

---

# 5. STATUTS

Tables examinees :

users, school_years, teachers, staff, classes, teacher_class_subjects, students, enrollments, attendance, invoices

PASS — toutes les tables examinees possedent un status VARCHAR.

---

# 6. D12 — MATRICULE

PASS — matricule NOT NULL + UNIQUE.

---

# 7. D13 — ENROLLMENT

PASS — unicite active etudiant/annee implementee par index unique partiel.

---

# 8. D14 — COEFFICIENTS

WARNING — coefficient present dans subjects et grades. Duplication potentielle a arbitrer.

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

Conclusion : PASS STRUCTUREL

La regle de calcul devra cependant etre definie dans la couche metier.

---

# 10. D16 — ATTENDANCE

PASS — unicite etudiant/classe/date et statuts attendance presents.

Statuts attendus :

- PRESENT
- ABSENT
- LATE
- EXCUSED

---

# 11. D17/D18/D19 — FINANCE

PASS : montant facture present.
PASS : montant paiement present.
PASS : FK payment -> invoice presente.
PASS : paiement strictement positif.
WARNING : contrainte paiement > 0 absente.
WARNING : aucune protection SQL contre paiement total > facture.

### Protection agregee

Aucune contrainte PostgreSQL actuelle ne garantit :

SUM(payments.amount) <= invoices.amount

Statut : REVIEW-REQUIRED

---

# 12. GRADES — COHERENCE ELEVE / INSCRIPTION

PASS : grades.student_id possede une FK.
PASS : grades.enrollment_id possede une FK.
WARNING : aucune contrainte inter-colonnes garantissant student_id = enrollment.student_id.

### Probleme structurel

Deux FK separees garantissent :

- student existe
- enrollment existe

Mais elles ne garantissent pas necessairement :

grades.student_id = enrollments.student_id

Statut : REVIEW-REQUIRED

---

# 13. ATTENDANCE — COHERENCE D'INSCRIPTION

Le schema garantit qu'un etudiant et une classe existent.

Il ne garantit pas que l'etudiant etait inscrit dans cette classe a la date concernee.

Statut : REVIEW-REQUIRED

---

# 14. UPDATED_AT

WARNING — updated_at existe mais aucun trigger de synchronisation automatique n'est defini.

La strategie applicative devra donc etre explicitement definie.

---

# 15. EMAIL

INFO — des contraintes UNIQUE email existent. PostgreSQL permet plusieurs NULL, ce qui doit etre coherent avec le metier.

Attention :

PostgreSQL autorise plusieurs valeurs NULL dans une contrainte UNIQUE.

Cela signifie que email UNIQUE ne signifie pas necessairement "un utilisateur doit obligatoirement avoir un email unique non NULL".

La regle metier doit preciser le comportement attendu.

---

# 16. AUTHENTIFICATION

PASS — le modele utilise password_hash et ne contient pas de colonne password en clair.

---

# 17. INDEX

PASS — les index FK principaux sont presents.

---

# 18. ENTITES HYPOTHETIQUES

sections :

ABSENTE — conforme a ENV-10-D.

holidays :

ABSENTE — conforme a ENV-10-D.

---

# 19. CONTENU SQL DANGEREUX

PASS — aucun DROP DATABASE, DROP TABLE, TRUNCATE, DELETE, UPDATE ou INSERT detecte.

---

# 20. RESULTATS

| Categorie | Resultat |
|---|---:|
| PASS detectes | 11 |
| WARNING detectes | 5 |
| Critical review items | 3 |

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

ENV-12 — REVIEW-REQUIRED

Le schema V1 est structurellement present et coherent sur les elements principaux.

Cependant, plusieurs regles d'integrite metier importantes ne peuvent pas etre considerees comme garanties uniquement par les FK actuelles.

Aucune creation de base PostgreSQL ne doit etre deduite de cette intervention.

La prochaine etape recommandee est :

ENV-13 — FORENSIC INTEGRITY DESIGN

Objectif :

- resoudre B01 finance ;
- resoudre B02 grades/enrollment ;
- resoudre B03 attendance/enrollment ;
- trancher B04 coefficients ;
- trancher B05 statuts ;
- trancher B06 updated_at ;

puis produire une version SQL V1.1 corrigee, toujours sans l'executer.
