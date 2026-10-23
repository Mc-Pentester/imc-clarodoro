# Audit des relations élèves–parents pour WhatsApp

## Portée et limite

Audit statique du dépôt GitHub, branche `main`, sur le schéma déclaré dans `database/schema.sql` au commit audité `c039195c45d8c8c77e6b5ca273d04852e72dff8d`.

Ce n'est pas une inspection de la base PostgreSQL réellement installée. Aucune connexion à la base n'a été ouverte et aucune requête de données n'a été exécutée.

## Relations confirmées dans le schéma du dépôt

### `students`

- Clé primaire : `id UUID`.
- Identité : `matricule`, `last_name`, `first_name`.
- Téléphone : `phone VARCHAR(50)`, mais il s'agit du téléphone de l'élève, pas nécessairement du parent.
- Statut : `status` avec valeurs `ACTIVE`, `INACTIVE`, `ARCHIVED`.

### `parents`

- Clé primaire : `id UUID`.
- Identité : `last_name`, `first_name`.
- Contact : `phone VARCHAR(50)`, nullable, `email VARCHAR(255)`, nullable.
- Pas de champ de consentement WhatsApp dans le schéma actuel.

### `student_parents`

- Table d'association entre élèves et parents/responsables.
- Colonnes : `student_id UUID NOT NULL`, `parent_id UUID NOT NULL`, `relationship_type VARCHAR(50)` nullable, `is_primary BOOLEAN NOT NULL DEFAULT FALSE`.
- Clé primaire composite : `(student_id, parent_id)`.
- Clé étrangère `student_id → students(id)`, `ON DELETE RESTRICT`.
- Clé étrangère `parent_id → parents(id)`, `ON DELETE RESTRICT`.

Le modèle autorise donc plusieurs parents pour un élève et un parent lié à plusieurs élèves. Le champ `is_primary` n'identifie pas à lui seul une personne autorisée à recevoir toutes les catégories de messages et ne constitue pas un consentement.

## Conséquences pour WhatsApp

1. Pour chaque envoi, retrouver le parent via `student_parents` et vérifier côté serveur la liaison avec l'élève concerné. Ne jamais accepter le `parent_id` ou le numéro cible uniquement parce que le navigateur le fournit.
2. Le champ `parents.phone` est nullable et le schéma ne garantit ni format E.164 ni validité WhatsApp. Valider le numéro avant tout envoi; si absent/invalide, bloquer.
3. Aucun consentement ni désinscription WhatsApp n'est représenté dans ces trois tables. En attendant un modèle de consentement approuvé, ne pas envoyer de messages.
4. `student_parents` n'a pas de statut ou de dates de validité. Le schéma seul ne permet pas de représenter explicitement une relation passée/retirée. Vérifier les règles métier existantes avant de décider si une évolution additive est nécessaire.
5. Ne pas utiliser `students.phone` comme substitut automatique au numéro du parent.
6. Pour les rappels de paiement, vérifier aussi l'autorisation métier et la relation de la facture/paiement à l'élève; ne pas envoyer de montant sur la seule base d'une association parent–élève.
7. Pour les résultats scolaires, vérifier l'événement fiable de publication et la permission de partager le résultat avant de générer une notification.

## Vérifications non encore démontrées

- La structure ci-dessus est celle du fichier de schéma versionné, pas une preuve que la base PostgreSQL réelle possède exactement ces contraintes.
- L'existence, la qualité et la fraîcheur des données parents/numéros dans la base réelle ne sont pas établies.
- L'API et l'interface actuelles ne démontrent pas encore un flux complet d'administration du consentement WhatsApp.
- Aucune règle existante n'a été confirmée pour déterminer automatiquement le destinataire par catégorie de notification.

## Décision recommandée

Le schéma fournit une base relationnelle exploitable (`students → student_parents → parents`), mais il ne suffit pas pour un envoi conforme et sûr. Étape suivante : comparer ce schéma au catalogue PostgreSQL réel en lecture seule, puis proposer le modèle de consentement et de journal dans une migration additive séparée. Ne pas exécuter cette migration ni envoyer de messages sans validation explicite.
