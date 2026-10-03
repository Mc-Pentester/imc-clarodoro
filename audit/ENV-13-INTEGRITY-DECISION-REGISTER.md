# ENV-13 â€” INTEGRITY DECISION REGISTER

Date : 2026-10-01 15:22:14

Statut global :

**FORENSIC ANALYSIS / HUMAN VALIDATION REQUIRED**

ENV-13 ne considere aucune proposition ci-dessous comme une decision
humaine definitive.

---

# B01 â€” Integrite financiere

## Constat

Le schema garantit l'existence de la facture et du paiement.

Il garantit egalement que le paiement est strictement positif.

Il ne garantit cependant pas :

SUM(payments.amount) <= invoices.amount

## Preuve code

Nombre d'elements financiers detectes :

80

Elements concernant explicitement une limite paiement/facture :

0

## Proposition technique

La regle metier doit etre appliquee dans une transaction atomique lors
de l'enregistrement du paiement :

1. verrouiller la facture ;
2. recalculer le montant deja paye ;
3. calculer le solde ;
4. refuser si le nouveau paiement depasse le solde ;
5. enregistrer le paiement ;
6. mettre a jour le statut de facture si necessaire ;
7. commit.

La contrainte ne doit pas reposer uniquement sur le client.

## Decision

**PROPOSED â€” transaction applicative + verrouillage de facture**

Validation humaine requise.

---

# B02 â€” CohÃ©rence grades / enrollment

## Constat

Le schema possede :

- grades.student_id â†’ students.id
- grades.enrollment_id â†’ enrollments.id

Mais cela ne garantit pas que l'inscription appartient au meme etudiant.

## Proposition technique

La relation note â†’ inscription doit devenir la relation de reference
pour determiner l'etudiant.

Deux solutions sont possibles :

### Option A â€” supprimer grades.student_id

La note reference uniquement enrollment_id.

L'etudiant est determine par l'inscription.

### Option B â€” conserver student_id + FK composite

Conserver les deux colonnes mais ajouter une contrainte permettant de
garantir la coherence.

## Proposition V1

**Option A est proposee**, car elle evite une duplication de la meme
relation et supprime une source potentielle d'incoherence.

Validation humaine requise.

---

# B03 â€” CohÃ©rence attendance / enrollment

## Constat

attendance contient :

- student_id
- class_id
- attendance_date

Mais aucune relation vers enrollment.

## Proposition technique

La presence doit etre rattachee a une inscription valide plutot qu'a
un simple etudiant + classe.

Proposition :

attendance.enrollment_id

avec FK vers enrollments.

L'inscription devient la source permettant de determiner :

- etudiant ;
- classe ;
- annee scolaire.

## Proposition V1

**Ajouter enrollment_id a attendance.**

Une contrainte metier devra ensuite verifier que l'enregistrement
correspond a une inscription active/valide a la date concernee.

Validation humaine requise.

---

# B04 â€” Coefficients

## Constat

Le schema contient :

- subjects.coefficient
- grades.coefficient

## Risque

Deux coefficients peuvent diverger sans regle explicite.

## Proposition

Le coefficient structurel de la matiere appartient a subjects.

Un coefficient specifique a une evaluation ne doit etre conserve dans
grades que si l'application permet reellement de modifier le
coefficient pour chaque evaluation.

## Proposition V1

**Ne pas conserver grades.coefficient sans preuve fonctionnelle.**

La valeur par defaut doit provenir de la configuration academique
appropriee.

Validation humaine requise.

---

# B05 â€” Statuts

## Constat

ENV-11 a propose plusieurs listes de statuts.

ENV-13 confronte ces statuts avec les occurrences detectees dans le code.

## Regle

Aucun statut SQL ne doit etre ajoute uniquement parce qu'il semble
raisonnable.

Chaque statut doit etre justifie par :

- le code ;
- une regle fonctionnelle ;
- ou une decision humaine.

## Proposition V1

Conserver uniquement les statuts demontrÃ©s ou explicitement valides.

Validation humaine requise.

---

# B06 â€” updated_at

## Constat

Les tables possedent updated_at.

Aucun trigger PostgreSQL n'a ete detecte.

## Options

### Option A

PHP est responsable de mettre a jour updated_at.

### Option B

PostgreSQL impose automatiquement la valeur via trigger.

## Proposition V1

**Option A â€” responsabilite applicative**, tant que l'application
centralise correctement toutes les modifications.

Cette option evite d'introduire une logique PostgreSQL non necessaire
avant validation de l'architecture applicative.

Validation humaine requise.

---

# MATRICE DE DECISION

| ID | Sujet | Proposition | Statut |
|---|---|---|---|
| B01 | Paiements | transaction + verrouillage facture | PROPOSED |
| B02 | Grades | enrollment comme source de l'etudiant | PROPOSED |
| B03 | Attendance | reference vers enrollment | PROPOSED |
| B04 | Coefficients | coefficient de grade uniquement si fonctionnellement necessaire | PROPOSED |
| B05 | Statuts | uniquement statuts demontrÃ©s/validÃ©s | PROPOSED |
| B06 | updated_at | responsabilite PHP | PROPOSED |

---

# INTERDICTION DE PASSAGE AUTOMATIQUE

ENV-13 ne valide aucune de ces propositions automatiquement.

La prochaine etape est :

**ENV-14 â€” HUMAN INTEGRITY DECISION VALIDATION**

Apres validation humaine, le schema V1.1 pourra etre genere.
