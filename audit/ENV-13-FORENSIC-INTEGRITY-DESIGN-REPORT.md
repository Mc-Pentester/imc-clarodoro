# ENV-13 â€” FORENSIC INTEGRITY DESIGN REPORT

Date : 2026-10-01 15:22:14

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
| JSON | 0 |
| Markdown | 16 |
| Total | 37 |

---

# 2. B01 â€” INTEGRITE FINANCIERE

Statut d'analyse :

**UNRESOLVED**

Occurrences financieres detectees :

**80**

Elements indiquant explicitement une protection paiement/facture :

**0**

Transactions financieres detectees :

**15**

### Schema

Montant facture controle :

PASS

Montant paiement > 0 :

PASS

Protection agregÃ©e :

ABSENTE

### Analyse

Le modele actuel ne doit pas permettre a deux requetes concurrentes
de contourner une verification de solde.

La strategie proposee est :

**transaction + verrouillage de la facture + recalcul du solde.**

---

# 3. B02 â€” GRADES / ENROLLMENTS

Statut d'analyse :

**UNRESOLVED**

Evidence grade :

**100**

Evidence coherence grade/enrollment :

**0**

FK student :

PASS

FK enrollment :

PASS

Contrainte inter-colonnes :

PRESENTE

### Analyse

Le schema possede deux references independantes.

Une incoherence reste donc theoriquement possible.

### Proposition

Utiliser enrollment_id comme source de rattachement de l'etudiant.

---

# 4. B03 â€” ATTENDANCE / ENROLLMENT

Statut d'analyse :

**EVIDENCE-FOUND**

Evidence attendance :

**100**

Evidence attendance/enrollment :

**4**

FK student :

PASS

FK class :

PASS

FK enrollment :

PRÃ‰SENTE

### Analyse

Le couple :

student_id + class_id

ne prouve pas qu'une inscription valide existe.

### Proposition

Ajouter enrollment_id a attendance.

---

# 5. B04 â€” COEFFICIENTS

Statut d'analyse :

**EVIDENCE-FOUND**

Occurrences coefficient :

**100**

Occurrences calcul notes :

**100**

Schema subjects.coefficient :

PRÃ‰SENT

Schema grades.coefficient :

PRÃ‰SENT

### Analyse

La duplication est actuellement possible.

La definition finale doit preciser si le coefficient est :

- une propriete de matiere ;
- une propriete d'une evaluation ;
- une propriete d'une periode academique ;
- ou une combinaison de ces concepts.

### Proposition

Ne conserver grades.coefficient que si le code demontre reellement
un coefficient variable par note/evaluation.

---

# 6. B05 â€” STATUTS

Nombre d'occurrences de statuts detectes dans le code :

**42**

## Couverture

| Statut | SQL | Code |
|---|---|---|
| ACTIVE | True | active active active active active active active Inactive Active active active active active active active active active active |
| INACTIVE | True | Inactive |
| ARCHIVED | True |  |
| PENDING | True |  |
| CANCELLED | True |  |
| COMPLETED | True |  |
| PLANNED | True |  |
| CLOSED | True |  |
| DRAFT | True |  |
| OPEN | True | open |
| PARTIALLY_PAID | True |  |
| PAID | True | paid paid paid |
| PRESENT | True | present present present present present |
| ABSENT | True | absent absent ABSENT absent Absent Absent Absent Absent Absent Absent absent Absent absent Absent absent |
| LATE | True |  |
| EXCUSED | True |  |


### Analyse

Les statuts ajoutes au SQL doivent etre confrontes au comportement reel
de l'application.

Aucun statut supplementaire ne doit etre considere comme valide
uniquement parce qu'il semble utile.

---

# 7. B06 â€” UPDATED_AT

Occurrences updated_at / equivalents :

**100**

Triggers SQL :

**0**

### Analyse

Le schema contient des timestamps de modification mais ne contient
pas de trigger automatique.

### Proposition

Responsabilite applicative PHP.

Cette decision devra etre confirmee avec l'architecture des services
de donnees.

---

# 8. DECISIONS PROPOSEES

| ID | Decision | Proposition |
|---|---|---|
| B01 | Finance | Transaction + verrouillage facture |
| B02 | Grades | enrollment_id comme source de l'etudiant |
| B03 | Attendance | enrollment_id comme reference |
| B04 | Coefficients | Pas de coefficient par grade sans preuve |
| B05 | Statuts | Seulement ceux demontrÃ©s/validÃ©s |
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

**ENV-13 â€” FORENSIC DESIGN COMPLETE**

Les six points B01-B06 disposent maintenant d'une proposition
d'architecture.

Ils ne sont toutefois pas encore consideres comme valides.

Prochaine etape :

**ENV-14 â€” HUMAN INTEGRITY DECISION VALIDATION**

ENV-14 devra enregistrer explicitement les decisions humaines avant
toute generation du schema.sql V1.1.
