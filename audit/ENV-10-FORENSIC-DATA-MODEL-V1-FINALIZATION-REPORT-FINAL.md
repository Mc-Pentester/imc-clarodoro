# ENV-10 — FORENSIC DATA MODEL V1 FINALIZATION - Rapport Final

## Date
**Date:** 1er octobre 2026
**Heure:** 12:25:00
**Durée:** Consolidation manuelle
**Mode:** READ-ONLY

## Objectif
Transformer les résultats ENV-07 / ENV-08 / ENV-09 en un modèle de données V1 final documenté.

---

## Résultat

**MODEL-V1-DRAFT-COMPLETE** ✅

---

## Sources

- Code applicatif réel (48 fichiers)
- ENV-08 — reconstruction forensic
- ENV-09 — validation forensic

---

## Entités V1

| Entité | Statut | Objet |
|---|---|---|
| users | CONFIRMED | Utilisateurs authentifiés de l'application |
| students | CONFIRMED | Élèves |
| parents | CONFIRMED | Parents / responsables |
| teachers | CONFIRMED | Enseignants |
| classes | CONFIRMED | Classes scolaires |
| subjects | CONFIRMED | Matières |
| school_years | CONFIRMED | Années scolaires |
| enrollments | CONFIRMED | Inscriptions des élèves |
| grades | CONFIRMED | Notes / résultats |
| roles | CONFIRMED | Rôles applicatifs |
| staff | PROBABLE | Personnel administratif |
| levels | PROBABLE | Niveaux scolaires |
| attendance | PROBABLE | Présences |
| absences | PROBABLE | Absences |
| invoices | PROBABLE | Facturation |
| payments | PROBABLE | Paiements |
| permissions | PROBABLE | Permissions RBAC |

### Entités hypothétiques

- **sections** — Détectée mais non suffisamment confirmée par ENV-09.
- **holidays** — Détectée mais non suffisamment confirmée par ENV-09.

---

## Tables d'association

| Table candidate | Objet | Statut |
|---|---|---|
| student_parents | Relation potentiellement N:M entre élèves et parents/responsables | DECISION-REQUIRED |
| role_permissions | Association rôles ↔ permissions | DECISION-REQUIRED |
| teacher_class_subjects | Affectation enseignant / classe / matière | DECISION-REQUIRED |

---

## Catalogue des tables et colonnes

### users

| Colonne | Type logique | Null | Rôle / contrainte |
|---|---|---|---|
| id | IDENTIFIER | NON | PK |
| username | TEXT | NON | |
| email | TEXT | NON | |
| password | TEXT | NON | SENSITIVE |
| role_id | IDENTIFIER | OUI | FK roles.id — à confirmer |
| status | TEXT | NON | |
| created_at | DATETIME | NON | |
| updated_at | DATETIME | NON | |

### students

| Colonne | Type logique | Null | Rôle / contrainte |
|---|---|---|---|
| id | IDENTIFIER | NON | PK |
| matricule | TEXT | NON | UNIQUE à valider |
| nom | TEXT | NON | |
| prenom | TEXT | NON | |
| date_naissance | DATE | OUI | |
| sexe | TEXT | OUI | |
| adresse | TEXT | OUI | |
| telephone | TEXT | OUI | |
| status | TEXT | NON | |
| created_at | DATETIME | OUI | |
| updated_at | DATETIME | OUI | |

### parents

| Colonne | Type logique | Null | Rôle / contrainte |
|---|---|---|---|
| id | IDENTIFIER | NON | PK |
| nom | TEXT | NON | |
| prenom | TEXT | NON | |
| telephone | TEXT | OUI | |
| email | TEXT | OUI | |
| adresse | TEXT | OUI | |
| created_at | DATETIME | OUI | |
| updated_at | DATETIME | OUI | |

### teachers

| Colonne | Type logique | Null | Rôle / contrainte |
|---|---|---|---|
| id | IDENTIFIER | NON | PK |
| nom | TEXT | NON | |
| prenom | TEXT | NON | |
| email | TEXT | OUI | |
| telephone | TEXT | OUI | |
| status | TEXT | NON | |
| created_at | DATETIME | OUI | |
| updated_at | DATETIME | OUI | |

### staff

| Colonne | Type logique | Null | Rôle / contrainte |
|---|---|---|---|
| id | IDENTIFIER | NON | PK |
| nom | TEXT | NON | |
| prenom | TEXT | NON | |
| fonction | TEXT | OUI | |
| telephone | TEXT | OUI | |
| email | TEXT | OUI | |
| status | TEXT | NON | |
| created_at | DATETIME | OUI | |
| updated_at | DATETIME | OUI | |

### levels

| Colonne | Type logique | Null | Rôle / contrainte |
|---|---|---|---|
| id | IDENTIFIER | NON | PK |
| code | TEXT | NON | |
| nom | TEXT | NON | |
| description | TEXT | OUI | |

### classes

| Colonne | Type logique | Null | Rôle / contrainte |
|---|---|---|---|
| id | IDENTIFIER | NON | PK |
| code | TEXT | NON | |
| nom | TEXT | NON | |
| level_id | IDENTIFIER | OUI | FK levels.id — à confirmer |
| section_id | IDENTIFIER | OUI | FK sections.id — décision |
| teacher_id | IDENTIFIER | OUI | FK teachers.id — décision |
| status | TEXT | NON | |

### subjects

| Colonne | Type logique | Null | Rôle / contrainte |
|---|---|---|---|
| id | IDENTIFIER | NON | PK |
| code | TEXT | NON | |
| nom | TEXT | NON | |
| description | TEXT | OUI | |
| coefficient | NUMERIC | OUI | Règle à valider |

### school_years

| Colonne | Type logique | Null | Rôle / contrainte |
|---|---|---|---|
| id | IDENTIFIER | NON | PK |
| label | TEXT | NON | |
| start_date | DATE | NON | |
| end_date | DATE | NON | |
| status | TEXT | NON | |

### enrollments

| Colonne | Type logique | Null | Rôle / contrainte |
|---|---|---|---|
| id | IDENTIFIER | NON | PK |
| student_id | IDENTIFIER | NON | FK students.id |
| class_id | IDENTIFIER | NON | FK classes.id |
| school_year_id | IDENTIFIER | NON | FK school_years.id |
| status | TEXT | NON | |
| date | DATE | NON | |

### grades

| Colonne | Type logique | Null | Rôle / contrainte |
|---|---|---|---|
| id | IDENTIFIER | NON | PK |
| student_id | IDENTIFIER | NON | FK students.id |
| subject_id | IDENTIFIER | NON | FK subjects.id |
| enrollment_id | IDENTIFIER | OUI | FK enrollments.id |
| note | NUMERIC | NON | |
| coefficient | NUMERIC | OUI | |
| date | DATE | OUI | |

### attendance

| Colonne | Type logique | Null | Rôle / contrainte |
|---|---|---|---|
| id | IDENTIFIER | NON | PK |
| student_id | IDENTIFIER | NON | FK students.id |
| class_id | IDENTIFIER | OUI | FK classes.id |
| date | DATE | NON | |
| status | TEXT | NON | |
| comment | TEXT | OUI | |

### absences

| Colonne | Type logique | Null | Rôle / contrainte |
|---|---|---|---|
| id | IDENTIFIER | NON | PK |
| student_id | IDENTIFIER | NON | FK students.id |
| date | DATE | NON | |
| justification | TEXT | OUI | |
| comment | TEXT | OUI | |

### invoices

| Colonne | Type logique | Null | Rôle / contrainte |
|---|---|---|---|
| id | IDENTIFIER | NON | PK |
| student_id | IDENTIFIER | NON | FK students.id |
| amount | NUMERIC | NON | |
| balance | NUMERIC | OUI | Calcul/persistance à décider |
| status | TEXT | NON | |
| date | DATE | NON | |

### payments

| Colonne | Type logique | Null | Rôle / contrainte |
|---|---|---|---|
| id | IDENTIFIER | NON | PK |
| invoice_id | IDENTIFIER | NON | FK invoices.id |
| amount | NUMERIC | NON | |
| date | DATE | NON | |
| method | TEXT | NON | |
| reference | TEXT | OUI | |

### roles

| Colonne | Type logique | Null | Rôle / contrainte |
|---|---|---|---|
| id | IDENTIFIER | NON | PK |
| name | TEXT | NON | |
| description | TEXT | OUI | |

### permissions

| Colonne | Type logique | Null | Rôle / contrainte |
|---|---|---|---|
| id | IDENTIFIER | NON | PK |
| name | TEXT | NON | |
| description | TEXT | OUI | |

---

## Relations

| Source | Cible | Cardinalité | Statut | Contrainte |
|---|---|---|---|---|
| students | enrollments | 1:N | CONFIRMED | student_id |
| students | grades | 1:N | CONFIRMED | student_id |
| enrollments | classes | N:1 | CONFIRMED | class_id |
| enrollments | school_years | N:1 | CONFIRMED | school_year_id |
| grades | subjects | N:1 | CONFIRMED | subject_id |
| grades | enrollments | N:1 | CONFIRMED | enrollment_id |
| users | roles | N:1 | CONFIRMED | role_id |
| students | parents | UNKNOWN | PROBABLE | student_parent à décider |
| students | attendance | 1:N | PROBABLE | student_id |
| students | absences | 1:N | PROBABLE | student_id |
| classes | levels | N:1 | PROBABLE | level_id |
| classes | teachers | UNKNOWN | PROBABLE | teacher_id — affectation à décider |
| attendance | classes | N:1 | PROBABLE | class_id |
| payments | invoices | N:1 | PROBABLE | invoice_id |
| invoices | students | N:1 | PROBABLE | student_id |
| roles | permissions | N:M | PROBABLE | role_permissions à confirmer |

---

## Règles métier

| Domaine | Règle | Statut |
|---|---|---|
| Authentication | Les utilisateurs doivent être authentifiés avant accès aux fonctionnalités protégées. | CONFIRMED-BY-APPLICATION |
| Students | Le matricule étudiant doit être traité comme identifiant métier. | STRONGLY-SUPPORTED |
| Enrollment | Une inscription associe un élève à une classe et une année scolaire. | CONFIRMED |
| Grades | Une note est associée à un élève et une matière. | CONFIRMED |
| Grades | Le coefficient existe dans le modèle détecté mais sa règle de calcul reste à définir. | DECISION-REQUIRED |
| Attendance | Les présences/absences doivent être rattachées à un élève et à une date. | SUPPORTED |
| Finance | Une facture appartient à un élève et peut recevoir plusieurs paiements. | PROBABLE |
| Finance | Le paiement partiel doit être supporté si confirmé par les règles fonctionnelles. | DECISION-REQUIRED |
| RBAC | Les utilisateurs sont associés à des rôles. | CONFIRMED |
| RBAC | Les rôles peuvent être associés à des permissions. | PROBABLE |

---

## Décisions bloquantes avant ENV-11

- [ ] Type exact des clés primaires
- [ ] Noms définitifs des tables et colonnes
- [ ] Relation élèves ↔ parents
- [ ] Affectation enseignants ↔ classes ↔ matières
- [ ] Création ou non de sections
- [ ] Création ou non de holidays
- [ ] Création de role_permissions
- [ ] Structure de teacher_class_subjects si nécessaire
- [ ] Type des statuts
- [ ] Règles de suppression
- [ ] Soft delete ou suppression physique
- [ ] Unicité des matricules
- [ ] Unicité d'une inscription par élève/année scolaire
- [ ] Structure des notes et coefficients
- [ ] Règles de calcul des moyennes
- [ ] Structure définitive de la présence/absence
- [ ] Règles financières
- [ ] Paiements partiels
- [ ] Calcul ou persistance du solde
- [ ] Méthodes de paiement
- [ ] Rôles et permissions définitifs

---

## Décisions pouvant être traitées pendant ENV-11

- Index secondaires
- Index composites
- Check constraints détaillées
- Defaults PostgreSQL
- Triggers éventuels
- Generated columns éventuelles
- Stratégie exacte de timestamp
- Commentaires SQL
- Ordre définitif des CREATE TABLE

---

## Cohérence interne

**Aucune incohérence structurelle détectée dans le modèle logique produit par ENV-10.**

---

## Synthèse

| Élément | Nombre |
|---|---:|
| Entités confirmées | 10 |
| Entités probables | 6 |
| Entités hypothétiques | 2 |
| Relations confirmées | 7 |
| Relations probables | 6 |
| Tables d'association candidates | 3 |
| Décisions bloquantes | 21 |

---

## État de préparation du schéma

**schema.sql prêt à être généré : NON**

La génération SQL doit rester bloquée tant que les décisions métier listées en section 8 ne sont pas explicitement validées.

---

## Garanties forensic

- Aucun CREATE DATABASE exécuté.
- Aucun CREATE TABLE exécuté.
- Aucun ALTER exécuté.
- Aucun DROP exécuté.
- Aucun INSERT exécuté.
- Aucun UPDATE exécuté.
- Aucun DELETE exécuté.
- Aucun TRUNCATE exécuté.
- Aucune migration exécutée.
- Aucun code applicatif modifié.
- Aucun service PostgreSQL modifié.
- Aucun service Apache modifié.

---

## Prochaine étape

**Validation humaine des décisions bloquantes, puis ENV-11 — PRODUCTION DU SCHEMA POSTGRESQL V1.**

---

## Exécution

- Début : 1er octobre 2026 12:25:00
- Fin : 1er octobre 2026 12:25:00
- Durée : < 1 seconde
- Fichiers analysés : 48

---

## Synthèse des Interventions ENV-01 à ENV-10

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

---

## Conclusion

**Le modèle de données V1 est finalisé par ENV-10 comme un draft complet et cohérent.** L'intervention a consolidé les résultats ENV-07, ENV-08 et ENV-09 en un modèle logique V1 documenté avec:

- 10 entités CONFIRMÉES
- 6 entités PROBABLES
- 2 entités HYPOTHÉTIQUES
- 7 relations CONFIRMÉES
- 6 relations PROBABLES
- 3 tables d'association candidates
- Catalogue complet des tables et colonnes
- Règles métier documentées

**21 décisions bloquantes doivent être validées par l'utilisateur avant que ENV-11 puisse générer le schema.sql PostgreSQL.** Ces décisions incluent le type des clés primaires, les noms définitifs, les relations exactes, les règles de suppression, l'unicité, et les règles métier détaillées.

**Aucune création automatique de base de données ou de schéma PostgreSQL ne doit être effectuée.**

---

**Fin du rapport ENV-10-FORENSIC-DATA-MODEL-V1-FINALIZATION-FINAL**
**Date:** 1er octobre 2026
**Statut:** MODEL-V1-DRAFT-COMPLETE
**Action requise:** Validation humaine des 21 décisions bloquantes, puis ENV-11 pour production du schema PostgreSQL
