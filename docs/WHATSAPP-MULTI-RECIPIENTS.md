# WhatsApp — destinataires multiples et consentements

## Règles de routage

L'API serveur est seule autorisée à déterminer les destinataires. Le navigateur ne transmet jamais une liste de numéros à envoyer.

- **Élève mineur** : envoyer uniquement aux parents/responsables reliés par `student_parents` et disposant chacun d'un consentement actif pour la finalité. Tous les responsables admissibles sont ciblés; `is_primary` ne remplace jamais un consentement.
- **Élève majeur, message personnel** : envoyer uniquement à l'élève, sur le numéro explicitement consenti et enregistré dans `whatsapp_recipient_consents`.
- **Élève majeur, message concernant aussi les parents** : envoyer à l'élève et à tous ses parents/responsables reliés qui ont un consentement actif, chacun sur son propre numéro.
- **Date de naissance absente** : traiter par prudence comme mineur pour le routage.
- **Personnel / enseignants** : envoi direct uniquement si leur consentement individuel est actif pour la finalité.
- Les finalités sont distinctes : `ATTENDANCE`, `RESULTS_AVAILABLE`, `PAYMENT_REMINDER`, `GENERAL`.

La majorité est calculée côté PostgreSQL à 18 ans selon l'article 16.2 de la Constitution haïtienne. La date de naissance est évaluée selon le calendrier local `America/Port-au-Prince`, indépendamment du fuseau horaire du serveur.

## Consentement

La migration additive `20261115150000_whatsapp_multi_recipient_consents.sql` crée :

- `whatsapp_recipient_consents` : consentement par personne, numéro et finalité;
- `whatsapp_recipient_consent_audit` : historique append-only;
- `whatsapp_recipient_message_log` : statut d'envoi individuel et clé idempotente par destinataire;
- `whatsapp_webhook_events` : accusés Meta dédupliqués et empreinte du corps reçu, sans conservation du corps brut.

Les consentements parentaux existants de `whatsapp_consents` sont copiés vers la nouvelle table. L'ancienne table et son audit ne sont pas supprimés. Les deux API de consentement parentales synchronisent les deux modèles afin de maintenir la compatibilité.

Un numéro présent dans le dossier scolaire n'est pas une preuve de consentement. L'interface demande un numéro WhatsApp E.164, une source obligatoire pour activer le consentement, et une référence de preuve facultative.

## API

- `GET /api/whatsapp/recipient-search.php?recipient_type=...&q=...` — recherche de personnes.
- `GET|POST /api/whatsapp/recipient-consents.php` — consultation et gestion des consentements.
- `POST /api/whatsapp/send-multi.php` — calcul serveur des destinataires et envoi individuel par Meta.
- `GET /api/whatsapp/recipient-message-history.php` — historique des 100 derniers envois, protégé par `whatsapp.message.audit`.
- `GET|POST /api/whatsapp/webhook.php` — vérification du webhook Meta et traitement des statuts `sent`, `delivered`, `read`, `failed`.
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

## Sécurité transactionnelle des envois

Chaque destinataire est réservé dans une transaction PostgreSQL courte : Clarodaro verrouille et revérifie le consentement, crée la ligne idempotente `PROCESSING`, puis valide la transaction **avant** d'appeler Meta. La réponse du fournisseur est enregistrée dans une seconde transaction courte. Aucun verrou de consentement ni transaction PostgreSQL ne reste ouvert pendant l'appel HTTP.

Une révocation effectuée après la réservation n'annule pas un appel Meta déjà en cours. Elle est immédiatement enregistrée et empêche les réservations suivantes. Si la connexion expire ou si le processus s'arrête après la réservation, la clé idempotente reste consommée : vérifiez l'historique avant toute nouvelle tentative. Un statut `PROCESSING` ou `FAILED / NETWORK_UNCERTAIN` ne doit pas être interprété comme une preuve que Meta n'a pas reçu le message.

## Compatibilité des preuves de consentement

Le modèle générique reprend les champs de preuve du modèle parent historique : méthode (`PAPER` ou `DIGITAL_EMAIL`), référence de preuve, courriel vérifié et version du texte de consentement. Les API historiques, la confirmation parentale par e-mail et l'API multi-destinataires synchronisent les deux modèles dans la même transaction. Une révocation conserve la date initiale de consentement et ses éléments de preuve; l'audit est append-only et identifie séparément les actions du personnel et celles du parent.
