# WhatsApp — destinataires multiples et consentements

## Règles de routage

L'API serveur est seule autorisée à déterminer les destinataires. Le navigateur ne transmet jamais une liste de numéros à envoyer.

- **Élève mineur** : envoyer uniquement aux parents/responsables reliés par `student_parents` et disposant chacun d'un consentement actif pour la finalité. Tous les responsables admissibles sont ciblés; `is_primary` ne remplace jamais un consentement.
- **Élève majeur, message personnel** : envoyer uniquement à l'élève, sur le numéro explicitement consenti et enregistré dans `whatsapp_recipient_consents`.
- **Élève majeur, message concernant aussi les parents** : envoyer à l'élève et à tous ses parents/responsables reliés qui ont un consentement actif, chacun sur son propre numéro.
- **Date de naissance absente** : traiter par prudence comme mineur pour le routage.
- **Personnel / enseignants** : envoi direct uniquement si leur consentement individuel est actif pour la finalité.
- Les finalités sont distinctes : `ATTENDANCE`, `RESULTS_AVAILABLE`, `PAYMENT_REMINDER`, `GENERAL`.

La majorité est calculée côté PostgreSQL à 18 ans selon l'article 16.2 de la Constitution haïtienne. La date de naissance est évaluée par rapport à `CURRENT_DATE` de la base.

## Consentement

La migration additive `20261115150000_whatsapp_multi_recipient_consents.sql` crée :

- `whatsapp_recipient_consents` : consentement par personne, numéro et finalité;
- `whatsapp_recipient_consent_audit` : historique append-only;
- `whatsapp_recipient_message_log` : statut d'envoi individuel et clé idempotente par destinataire.

Les consentements parentaux existants de `whatsapp_consents` sont copiés vers la nouvelle table. L'ancienne table et son audit ne sont pas supprimés. Les deux API de consentement parentales synchronisent les deux modèles afin de maintenir la compatibilité.

Un numéro présent dans le dossier scolaire n'est pas une preuve de consentement. L'interface demande un numéro WhatsApp E.164, une source obligatoire pour activer le consentement, et une référence de preuve facultative.

## API

- `GET /api/whatsapp/recipient-search.php?recipient_type=...&q=...` — recherche de personnes.
- `GET|POST /api/whatsapp/recipient-consents.php` — consultation et gestion des consentements.
- `POST /api/whatsapp/send-multi.php` — calcul serveur des destinataires et envoi individuel par Meta.
- `GET /api/whatsapp/send.php` — état de configuration Meta existant.

Le service revérifie et verrouille chaque consentement juste avant l'appel Meta. Chaque destinataire obtient une ligne d'audit indépendante et une clé idempotente. Un résultat accepté par Meta ne garantit pas la livraison. Les erreurs réseau dont l'issue est incertaine ne sont pas réessayées automatiquement.

## Permissions

- `whatsapp.message.send` : initier un envoi.
- `whatsapp.recipient.read` : rechercher les personnes; accordé aux rôles qui avaient déjà `whatsapp.message.send`.
- `whatsapp.recipient.manage` : enregistrer/retirer les consentements; non accordé automatiquement aux autres rôles.
- `whatsapp.message.audit` : permission réservée à une future interface de consultation des journaux.

Le rôle PDG reçoit les nouvelles permissions. Les autres rôles doivent recevoir explicitement `whatsapp.recipient.manage` via l'administration RBAC s'ils doivent gérer les consentements.

## Migration et déploiement

Cette migration est additive et n'est pas exécutée automatiquement. Elle doit être appliquée par le processus approuvé après sauvegarde et vérification de l'historique `schema_migrations`. Aucune donnée ne doit être supprimée.

Aucun envoi réel ne doit être activé avant validation de la configuration Meta, des modèles approuvés et des tests d'intégration.
