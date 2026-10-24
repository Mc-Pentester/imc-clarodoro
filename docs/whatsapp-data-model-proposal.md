# Modèle de données WhatsApp — proposition statique

## Statut

Proposition additive pour la branche `feature/whatsapp-foundation`. Elle n'est pas une migration exécutable et n'a pas été appliquée à PostgreSQL. Le schéma déployé doit être confirmé avant toute migration.

## Principes

- Réutiliser `parents`, `students` et `student_parents` comme sources de vérité pour l'identité et le lien familial.
- Ne pas traiter `student_parents.is_primary` comme un consentement.
- Ne pas déduire le numéro WhatsApp du téléphone de l'élève.
- Stocker les consentements, événements, messages et tentatives séparément.
- Ne jamais envoyer directement depuis une requête CRUD métier.
- Tout envoi est désactivé tant que consentement, autorisation et événement fiable ne sont pas vérifiés.

## 1. `whatsapp_consents` — consentement par parent, numéro et catégorie

Champs proposés :
- `id UUID PRIMARY KEY`
- `parent_id UUID NOT NULL REFERENCES parents(id)`
- `phone_e164 VARCHAR(20) NOT NULL` — numéro normalisé et validé
- `purpose VARCHAR(40) NOT NULL` — `ATTENDANCE`, `RESULTS_AVAILABLE`, `PAYMENT_REMINDER`, `GENERAL`
- `status VARCHAR(20) NOT NULL` — `PENDING`, `OPTED_IN`, `OPTED_OUT`
- `consent_source VARCHAR(40) NOT NULL` — ex. formulaire signé, interface administrative, mot-clé entrant
- `consented_at TIMESTAMPTZ NULL`
- `withdrawn_at TIMESTAMPTZ NULL`
- `recorded_by_user_id UUID NULL` — référence à la table utilisateur réelle après vérification du nom et de la clé
- `evidence_reference TEXT NULL` — référence à une preuve, pas nécessairement la copie d'un document sensible
- `created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()`
- `updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()`

Règles :
- Pas d'envoi si aucun consentement explicite actif ne correspond au parent, au numéro et à la catégorie.
- Un retrait doit bloquer immédiatement les envois futurs.
- Garder l'historique des changements ; ne pas réactiver un consentement retiré sans nouvelle preuve.
- Le consentement à une catégorie ne vaut pas automatiquement pour toutes les autres.

## 2. `whatsapp_message_events` — événement métier à notifier

Champs proposés :
- `id UUID PRIMARY KEY`
- `event_type VARCHAR(40) NOT NULL` — `ATTENDANCE_CONFIRMED`, `RESULTS_PUBLISHED`, `PAYMENT_REMINDER_ELIGIBLE`
- `student_id UUID NOT NULL REFERENCES students(id)`
- `source_entity_type VARCHAR(40) NOT NULL`
- `source_entity_id UUID NOT NULL` — identifiant de l'enregistrement métier source
- `source_version VARCHAR(100) NULL` — version ou marqueur de changement si disponible
- `occurred_at TIMESTAMPTZ NOT NULL`
- `eligible_at TIMESTAMPTZ NULL`
- `status VARCHAR(20) NOT NULL` — `PENDING`, `READY`, `CANCELLED`, `PROCESSED`
- `idempotency_key VARCHAR(200) NOT NULL UNIQUE`
- `created_by_user_id UUID NULL`
- `created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()`

Important : cette table ne remplace pas les tables métier. Elle conserve une intention de notification rattachée à un fait source. Les événements `RESULTS_PUBLISHED` ne doivent être créés que par un vrai flux de publication, qui reste à concevoir/identifier.

## 3. `whatsapp_outbox` — message préparé et file d'envoi

Champs proposés :
- `id UUID PRIMARY KEY`
- `event_id UUID NOT NULL REFERENCES whatsapp_message_events(id)`
- `parent_id UUID NOT NULL REFERENCES parents(id)`
- `consent_id UUID NOT NULL REFERENCES whatsapp_consents(id)`
- `phone_e164 VARCHAR(20) NOT NULL` — instantané du numéro ciblé lors de la préparation
- `template_name VARCHAR(100) NOT NULL`
- `template_language VARCHAR(20) NOT NULL`
- `payload JSONB NOT NULL` — variables du modèle, sans contenu sensible inutile
- `status VARCHAR(20) NOT NULL` — `PENDING`, `SENDING`, `SENT`, `FAILED`, `CANCELLED`
- `idempotency_key VARCHAR(200) NOT NULL UNIQUE`
- `attempt_count INTEGER NOT NULL DEFAULT 0`
- `next_attempt_at TIMESTAMPTZ NULL`
- `provider_message_id VARCHAR(200) NULL`
- `last_error_code VARCHAR(100) NULL` — code seulement, sans jeton ni données personnelles
- `created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()`
- `updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()`
- `sent_at TIMESTAMPTZ NULL`

Règles :
- La file doit être créée dans la même transaction que l'événement éligible lorsque c'est possible.
- Juste avant l'appel Meta, revérifier le consentement, la relation parent-élève, l'autorisation, l'état de l'événement et le numéro.
- Utiliser une contrainte unique pour éviter les doublons, y compris lors de reprises après erreur.
- Ne pas réessayer automatiquement les erreurs permanentes ou les refus de consentement.
- Une réponse réseau incertaine ne doit pas provoquer aveuglément un second envoi.

## 4. `whatsapp_message_logs` — journal d'audit append-only

Champs proposés :
- `id UUID PRIMARY KEY`
- `outbox_id UUID NULL REFERENCES whatsapp_outbox(id)`
- `actor_user_id UUID NULL`
- `action VARCHAR(40) NOT NULL` — ex. `QUEUED`, `SEND_ATTEMPT`, `SENT`, `FAILED`, `CANCELLED`, `OPT_OUT`
- `result_code VARCHAR(100) NULL`
- `metadata JSONB NOT NULL DEFAULT '{}'::jsonb` — liste blanche de métadonnées non sensibles
- `created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()`

Ne pas stocker les jetons Meta, en-têtes HTTP, corps complets contenant des informations scolaires ou financières, ni le contenu complet des conversations dans ce journal. Restreindre la lecture à une permission dédiée.

## 5. `whatsapp_webhook_events` — événements entrants de Meta

Table facultative pour la désinscription entrante et les statuts de livraison :
- `id UUID PRIMARY KEY`
- `provider_event_id VARCHAR(200) NOT NULL UNIQUE` si un identifiant stable est disponible
- `event_type VARCHAR(40) NOT NULL`
- `phone_e164 VARCHAR(20) NULL`
- `provider_message_id VARCHAR(200) NULL`
- `received_at TIMESTAMPTZ NOT NULL DEFAULT NOW()`
- `processed_at TIMESTAMPTZ NULL`
- `processing_status VARCHAR(20) NOT NULL DEFAULT 'PENDING'`
- `safe_metadata JSONB NOT NULL DEFAULT '{}'::jsonb`

Valider la signature du webhook selon la documentation Meta. Dédupliquer les événements. Traiter les mots-clés de retrait sans dépendre d'une intervention manuelle. Ne pas conserver le corps brut si ce n'est pas nécessaire.

## 6. Relations

- `parents 1—N whatsapp_consents`
- `students 1—N whatsapp_message_events`
- `whatsapp_message_events 1—N whatsapp_outbox`
- `parents 1—N whatsapp_outbox`
- `whatsapp_consents 1—N whatsapp_outbox`
- `whatsapp_outbox 1—N whatsapp_message_logs`

Une notification peut cibler un parent et un élève précis. Le lien autorisant cet envoi doit être vérifié via `student_parents` au moment de l'envoi, car la relation peut changer après la création de la file.

## 7. Permissions RBAC proposées

- `whatsapp.status.read` — lire l'état de la configuration, sans révéler les secrets.
- `whatsapp.consent.read` — consulter l'état du consentement.
- `whatsapp.consent.manage` — enregistrer ou retirer un consentement avec traçabilité.
- `whatsapp.message.send` — autoriser l'initiation d'un envoi ; ne dispense pas des vérifications automatiques.
- `whatsapp.message.audit` — consulter les journaux et résultats.
- `whatsapp.template.manage` — gérer la liste de modèles autorisés, si nécessaire.

Ne pas attribuer ces permissions automatiquement à tous les rôles. Les rôles et tables RBAC réels doivent être inspectés avant de définir les affectations.

## 8. Index et contraintes à prévoir

- Index `(parent_id, purpose, status)` sur les consentements.
- Index sur `(status, eligible_at)` pour la file de traitement.
- Index sur `(event_type, status, occurred_at)` pour les événements.
- Unicité de `idempotency_key` pour les événements et les éléments de file.
- Unicité de l'identifiant fournisseur lorsqu'il est fourni.
- CHECK constraints pour les valeurs permises de `purpose`, `status` et `event_type`.
- Clés étrangères en `ON DELETE RESTRICT` ou conservation logique pour préserver l'audit ; la stratégie finale doit respecter les règles de conservation de l'école.

## 9. Décisions à confirmer avant migration

1. Consentement : est-il enregistré par parent + numéro + catégorie (recommandé), ou doit-il être distinct pour chaque relation parent-élève ?
2. Événements d'absence : qui confirme l'absence et à quel moment ?
3. Résultats : existe-t-il déjà un état de publication officiel ailleurs dans l'application ?
4. Paiements : fréquence, heures autorisées, délai de grâce et nombre maximal de rappels.
5. Conservation : durée de conservation des journaux et des preuves de consentement.
6. Comptes utilisateurs : nom exact de la table et type de clé à utiliser pour `recorded_by_user_id` et `actor_user_id`.
7. Schéma PostgreSQL réel : confirmer tables, schémas et contraintes avant d'écrire une migration.

## 10. Étapes d'implémentation sûres

1. Valider ces décisions et le schéma réel.
2. Écrire une migration additive versionnée, sans modifier les tables existantes au-delà des ajouts approuvés.
3. Ajouter les tests de contraintes, consentement retiré, lien parent-élève supprimé, événement annulé, doublons, erreur fournisseur et reprise.
4. Construire d'abord un mode simulation qui ne fait aucun appel réseau.
5. Activer les envois uniquement après autorisation explicite, validation des modèles Meta et tests d'intégration.

**Non exécuté :** aucune migration, aucune requête à la base, aucun envoi de message.
