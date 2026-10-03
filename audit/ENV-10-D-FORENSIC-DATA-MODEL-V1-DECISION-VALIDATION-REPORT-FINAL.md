# ENV-10-D — FORENSIC DATA MODEL V1 DECISION VALIDATION - Rapport Final

## Date
**Date:** 1er octobre 2026
**Heure:** 12:30:00
**Durée:** Consolidation manuelle
**Mode:** READ-ONLY

## Objectif
Transformer les 21 décisions bloquantes ENV-10 en un registre architectural V1 explicite.

---

## Résultat

**DECISION-REGISTER-CREATED** ✅

---

## Sécurité de l'intervention

- Mode : READ-ONLY
- Base PostgreSQL créée : NON
- Tables PostgreSQL créées : NON
- Migration exécutée : NON
- Code applicatif modifié : NON
- Services système modifiés : NON

---

## État du schema.sql actuel

- Fichier : `database/schema.sql`
- CREATE TABLE détectés : 0

**Le schema.sql reste un placeholder.**

---

## Registre des Décisions

| ID | Domaine | Décision | Statut |
|---|---|---|---|
| D01 | IDENTIFIANTS | Type exact des clés primaires | HUMAN-DECISION |
| D02 | NAMING | Noms définitifs des tables et colonnes | PROPOSED |
| D03 | STUDENTS-PARENTS | Relation élèves ↔ parents | HUMAN-DECISION |
| D04 | PEDAGOGIE | Affectation enseignants/classes/matières | HUMAN-DECISION |
| D05 | STRUCTURE | Création de sections | HUMAN-DECISION |
| D06 | CALENDRIER | Création de holidays | HUMAN-DECISION |
| D07 | RBAC | Association rôles ↔ permissions | HUMAN-DECISION |
| D08 | PEDAGOGIE | Structure teacher_class_subjects | HUMAN-DECISION |
| D09 | STATUTS | Type des statuts | HUMAN-DECISION |
| D10 | INTEGRITE | Règles de suppression | HUMAN-DECISION |
| D11 | HISTORIQUE | Soft delete | HUMAN-DECISION |
| D12 | STUDENTS | Unicité des matricules | HUMAN-DECISION |
| D13 | ENROLLMENTS | Unicité d'inscription élève/année | HUMAN-DECISION |
| D14 | GRADES | Structure notes/coefficient | HUMAN-DECISION |
| D15 | GRADES | Calcul des moyennes | HUMAN-DECISION |
| D16 | ATTENDANCE | Présence / absence | HUMAN-DECISION |
| D17 | FINANCE | Structure financière | HUMAN-DECISION |
| D18 | FINANCE | Paiements partiels | HUMAN-DECISION |
| D19 | FINANCE | Calcul/persistance du solde | HUMAN-DECISION |
| D20 | FINANCE | Méthodes de paiement | HUMAN-DECISION |
| D21 | RBAC | Rôles et permissions définitifs | HUMAN-DECISION |

---

## Détail des Décisions

### D01 — Type exact des clés primaires

**Domaine :** IDENTIFIANTS

**Options :** UUID / BIGINT / INTEGER

**Preuve disponible :** Le code détecte des identifiants mais ne démontre pas un type PostgreSQL définitif.

**Proposition technique :** UUID si l'application doit rester facilement distribuable/importable; sinon BIGINT.

**Statut :** HUMAN-DECISION

---

### D02 — Noms définitifs des tables et colonnes

**Domaine :** NAMING

**Options :** snake_case / noms historiques

**Preuve disponible :** Le modèle forensic utilise déjà principalement des noms snake_case.

**Proposition technique :** Conserver snake_case pour PostgreSQL.

**Statut :** PROPOSED

---

### D03 — Relation élèves ↔ parents

**Domaine :** STUDENTS-PARENTS

**Options :** 1:N / N:M

**Preuve disponible :** students et parents sont confirmés; cardinalité non démontrée.

**Proposition technique :** N:M avec student_parents si plusieurs responsables par élève sont autorisés.

**Statut :** HUMAN-DECISION

---

### D04 — Affectation enseignants/classes/matières

**Domaine :** PEDAGOGIE

**Options :** teacher_id dans classes / table d'affectation

**Preuve disponible :** classes, teachers et subjects sont détectés.

**Proposition technique :** Table d'affectation si un enseignant peut gérer plusieurs classes/matières.

**Statut :** HUMAN-DECISION

---

### D05 — Création de sections

**Domaine :** STRUCTURE

**Options :** Créer / ne pas créer

**Preuve disponible :** sections seulement hypothétique.

**Proposition technique :** Ne pas créer sans preuve fonctionnelle.

**Statut :** HUMAN-DECISION

---

### D06 — Création de holidays

**Domaine :** CALENDRIER

**Options :** Créer / ne pas créer

**Preuve disponible :** holidays seulement hypothétique.

**Proposition technique :** Ne pas créer sans preuve fonctionnelle.

**Statut :** HUMAN-DECISION

---

### D07 — Association rôles ↔ permissions

**Domaine :** RBAC

**Options :** N:M / autre

**Preuve disponible :** roles et permissions sont détectés.

**Proposition technique :** role_permissions en N:M.

**Statut :** HUMAN-DECISION

---

### D08 — Structure teacher_class_subjects

**Domaine :** PEDAGOGIE

**Options :** Créer / ne pas créer

**Preuve disponible :** La combinaison enseignant/classe/matière est suggérée mais non complètement démontrée.

**Proposition technique :** Créer uniquement si les affectations multiples sont réellement supportées.

**Statut :** HUMAN-DECISION

---

### D09 — Type des statuts

**Domaine :** STATUTS

**Options :** ENUM / VARCHAR + CHECK

**Preuve disponible :** Plusieurs valeurs de statut sont détectées.

**Proposition technique :** VARCHAR + CHECK ou tables de référence si les valeurs doivent évoluer.

**Statut :** HUMAN-DECISION

---

### D10 — Règles de suppression

**Domaine :** INTEGRITE

**Options :** CASCADE / RESTRICT / SET NULL

**Preuve disponible :** Les dépendances existent mais aucune stratégie globale n'est démontrée.

**Proposition technique :** RESTRICT par défaut sur données métier/historiques.

**Statut :** HUMAN-DECISION

---

### D11 — Soft delete

**Domaine :** HISTORIQUE

**Options :** Oui / Non

**Preuve disponible :** Le modèle contient plusieurs données historiques.

**Proposition technique :** Privilégier l'archivage/statut pour données métier plutôt que DELETE physique.

**Statut :** HUMAN-DECISION

---

### D12 — Unicité des matricules

**Domaine :** STUDENTS

**Options :** UNIQUE global / UNIQUE contextualisé

**Preuve disponible :** matricule détecté comme identifiant métier.

**Proposition technique :** UNIQUE, sous réserve de confirmer s'il est global ou lié à l'établissement.

**Statut :** HUMAN-DECISION

---

### D13 — Unicité d'inscription élève/année

**Domaine :** ENROLLMENTS

**Options :** Unique / plusieurs inscriptions

**Preuve disponible :** enrollment associe student, class et school_year.

**Proposition technique :** Une inscription active par élève et année scolaire.

**Statut :** HUMAN-DECISION

---

### D14 — Structure notes/coefficient

**Domaine :** GRADES

**Options :** coefficient matière / coefficient évaluation / les deux

**Preuve disponible :** note et coefficient détectés.

**Proposition technique :** Ne pas figer avant clarification du système de notation.

**Statut :** HUMAN-DECISION

---

### D15 — Calcul des moyennes

**Domaine :** GRADES

**Options :** calcul dynamique / valeur persistée

**Preuve disponible :** Les résultats sont présents mais aucune règle SQL définitive n'est démontrée.

**Proposition technique :** Calculer depuis les notes sources plutôt que persister une valeur dérivée.

**Statut :** HUMAN-DECISION

---

### D16 — Présence / absence

**Domaine :** ATTENDANCE

**Options :** attendance unique / attendance + absences

**Preuve disponible :** Deux concepts sont détectés.

**Proposition technique :** Éviter la duplication; privilégier une source unique si les statuts couvrent les cas nécessaires.

**Statut :** HUMAN-DECISION

---

### D17 — Structure financière

**Domaine :** FINANCE

**Options :** invoice/payment / autre

**Preuve disponible :** invoices et payments sont fortement supportés.

**Proposition technique :** Conserver invoice → payments.

**Statut :** HUMAN-DECISION

---

### D18 — Paiements partiels

**Domaine :** FINANCE

**Options :** Oui / Non

**Preuve disponible :** payments multiples potentiels détectés.

**Proposition technique :** Autoriser plusieurs paiements par facture si le besoin métier est confirmé.

**Statut :** HUMAN-DECISION

---

### D19 — Calcul/persistance du solde

**Domaine :** FINANCE

**Options :** calculé / stocké

**Preuve disponible :** balance apparait dans le modèle.

**Proposition technique :** Éviter une duplication du solde si celui-ci peut être calculé de façon fiable.

**Statut :** HUMAN-DECISION

---

### D20 — Méthodes de paiement

**Domaine :** FINANCE

**Options :** VARCHAR / ENUM / table

**Preuve disponible :** method et reference sont détectés.

**Proposition technique :** VARCHAR + validation contrôlée pour permettre l'évolution.

**Statut :** HUMAN-DECISION

---

### D21 — Rôles et permissions définitifs

**Domaine :** RBAC

**Options :** rôles/permissions actuels du code

**Preuve disponible :** roles et permissions détectés par ENV-08/09.

**Proposition technique :** Définir explicitement les rôles et permissions avant création des contraintes SQL.

**Statut :** HUMAN-DECISION

---

## Architecture V1 Proposée

### Noyau académique

```
students
    │
    ├── enrollments → classes → levels
    │                   │
    │                   └── school_years
    │
    └── grades → subjects
```

### Noyau financier

```
students
    │
    └── invoices
           │
           └── payments
```

### Noyau sécurité

```
users
   │
   └── roles
          │
          └── role_permissions → permissions
```

### Relations potentiellement N:M

- students ↔ parents
- roles ↔ permissions
- teachers ↔ classes ↔ subjects

---

## Points volontairement non figés

- sections
- holidays
- structure exacte des affectations enseignants
- cardinalité élèves/parents
- modèle exact des notes
- stratégie attendance/absences
- stratégie de suppression
- type des statuts

---

## Préparation ENV-11

ENV-11 pourra générer le schema.sql uniquement après validation humaine du registre D01-D21.

La validation humaine doit conserver les identifiants D01 à D21 afin que chaque choix soit traçable jusqu'au SQL.

---

## Anomalies

Aucune anomalie bloquante détectée.

---

## Warnings

Aucun warning.

---

## Conclusion

**ENV-10-D COMPLETE — DECISION REGISTER READY FOR HUMAN VALIDATION**

Le modèle logique peut maintenant être validé décision par décision avant toute production SQL.

---

## Synthèse des Interventions ENV-01 à ENV-10-D

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
| ENV-09 | PASS ✅ | Validation réussie, modèle cohérent avec le code |
| ENV-10 | PASS ✅ | Modèle V1 finalisé, prêt pour validation humaine |
| ENV-10-D | PASS ✅ | Registre de décisions créé, prêt pour validation humaine |

---

## Documentation Complète

Rapport détaillé: <ref_file file="C:\IMC-Clarodoro-securise-client\IMC-Clarodoro\audit\ENV-10-D-FORENSIC-DATA-MODEL-V1-DECISION-VALIDATION-REPORT-FINAL.md" />

Registre de décisions: <ref_file file="C:\IMC-Clarodoro-securise-client\IMC-Clarodoro\audit\ENV-10-D-V1-DECISION-REGISTER.md" />

---

**ENV-10-D a transformé les 21 décisions bloquantes ENV-10 en un registre architectural V1 explicite.** Chaque décision est documentée avec son domaine, ses options, les preuves disponibles dans le code, une proposition technique, et un statut de validation requise. Le schema.sql actuel reste un placeholder (0 CREATE TABLE). Aucune base de données ou table n'a été créée. ENV-11 pourra générer le schema.sql uniquement après validation humaine du registre D01-D21.

---

**Fin du rapport ENV-10-D-FORENSIC-DATA-MODEL-V1-DECISION-VALIDATION-FINAL**
**Date:** 1er octobre 2026
**Statut:** DECISION-REGISTER-CREATED
**Action requise:** Validation humaine des 21 décisions D01-D21, puis ENV-11 pour production du schema PostgreSQL
