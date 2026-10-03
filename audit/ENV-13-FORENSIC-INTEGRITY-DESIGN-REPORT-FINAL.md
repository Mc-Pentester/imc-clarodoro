# ENV-13 — FORENSIC INTEGRITY DESIGN - Rapport Final

Date : 2026-10-01 12:45:00

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
| PHP | 8 |
| JavaScript | 4 |
| HTML | 9 |
| JSON | 16 |
| Markdown | 0 |
| Total | 37 |

---

# 2. B01 — INTEGRITE FINANCIERE

Statut d'analyse :

**UNRESOLVED**

Occurrences financieres detectees :

0

Elements indiquant explicitement une protection paiement/facture :

0

Transactions financieres detectees :

0

### Schema

Montant facture controle :

PASS

Montant paiement > 0 :

PASS

Protection agregee :

ABSENTE

### Analyse

Le modele actuel ne contient aucune preuve de protection contre le depassement de solde dans le code existant.

La strategie proposee est :

**transaction + verrouillage de la facture + recalcul du solde.**

---

# 3. B02 — GRADES / ENROLLMENTS

Statut d'analyse :

**UNRESOLVED**

Evidence grade :

0

Evidence coherence grade/enrollment :

0

FK student :

PASS

FK enrollment :

PASS

Contrainte inter-colonnes :

ABSENTE

### Analyse

Le schema possede deux references independantes.

Une incoherence reste donc theoriquement possible.

### Proposition

Utiliser enrollment_id comme source de rattachement de l'etudiant.

---

# 4. B03 — ATTENDANCE / ENROLLMENT

Statut d'analyse :

**EVIDENCE-FOUND**

Evidence attendance :

0

Evidence attendance/enrollment :

0

FK student :

PASS

FK class :

PASS

FK enrollment :

ABSENTE

### Analyse

Le couple student_id + class_id ne prouve pas qu'une inscription valide existe.

Bien que l'analyse n'ait pas trouve de preuve explicite de relation attendance/enrollment dans le code, la structure du schema necessite d'etre clarifiee.

### Proposition

Ajouter enrollment_id a attendance.

---

# 5. B04 — COEFFICIENTS

Statut d'analyse :

**EVIDENCE-FOUND**

Occurrences coefficient :

Preuve detectee dans le code

Occurrences calcul notes :

Preuve detectee dans le code

Schema subjects.coefficient :

PRÉSENT

Schema grades.coefficient :

PRÉSENT

### Analyse

La duplication est actuellement possible.

La definition finale doit preciser si le coefficient est :

- une propriete de matiere ;
- une propriete d'une evaluation ;
- une propriete d'une periode academique ;
- ou une combinaison de ces concepts.

### Proposition

Ne conserver grades.coefficient que si le code demontre reellement un coefficient variable par note/evaluation.

---

# 6. B05 — STATUTS

Nombre d'occurrences de statuts detectes dans le code :

Preuve detectee

## Couverture

Les statuts proposes dans ENV-11 doivent etre confrontes au comportement reel de l'application.

Aucun statut supplementaire ne doit etre considere comme valide uniquement parce qu'il semble utile.

---

# 7. B06 — UPDATED_AT

Occurrences updated_at / equivalents :

Preuve detectee dans le code

Triggers SQL :

0

### Analyse

Le schema contient des timestamps de modification mais ne contient pas de trigger automatique.

### Proposition

Responsabilite applicative PHP.

Cette decision devra etre confirmee avec l'architecture des services de donnees.

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

Les six points B01-B06 disposent maintenant d'une proposition d'architecture.

Ils ne sont toutefois pas encore consideres comme valides.

Prochaine etape :

**ENV-14 — HUMAN INTEGRITY DECISION VALIDATION**

ENV-14 devra enregistrer explicitement les decisions humaines avant toute generation du schema.sql V1.1.
