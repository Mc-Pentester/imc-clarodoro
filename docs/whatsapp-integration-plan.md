# Intégration WhatsApp — audit et plan de mise en œuvre

## Statut

Phase préparatoire uniquement. Ce document ne configure pas l'API, n'envoie aucun message et ne modifie pas la base PostgreSQL.

## Périmètre fonctionnel envisagé

- Envoi manuel de communications autorisées par le personnel.
- Notifications ciblées concernant les résultats/bulletins, les absences et retards, les rappels de paiement et les annonces générales.
- Déploiement progressif, avec activation désactivée tant que la configuration et les contrôles ne sont pas validés.

## Constats de l'audit du dépôt

- Le dépôt contient des API PHP pour la présence, les finances et les résultats.
- Le schéma contient les tables `students`, `parents` et `student_parents`; il reste à vérifier la qualité des associations et des numéros de téléphone dans l'environnement réel.
- L'audit du code n'a pas identifié de mécanisme dédié de consentement WhatsApp, de désinscription ou de journal d'envoi.
- Aucun déclencheur fiable de publication des résultats n'a été confirmé. Il ne faut donc pas envoyer automatiquement un résultat sur la seule base de son existence.
- Le dépôt seul ne permet pas de confirmer les données réelles de PostgreSQL ni l'état du compte Meta.

## Garde-fous obligatoires avant tout envoi

1. Respecter l'authentification, les permissions RBAC et la protection CSRF déjà en place.
2. Vérifier l'association élève-parent dans les données autorisées et valider le numéro destinataire.
3. Enregistrer le consentement explicite, sa date/source et le statut de désinscription; bloquer l'envoi en l'absence de consentement applicable.
4. Ne jamais exposer le jeton Meta au navigateur, au dépôt ou aux journaux.
5. Prévenir les doublons par une clé d'idempotence et un journal d'envoi; traiter les erreurs et les reprises sans renvoyer aveuglément.
6. Utiliser les modèles approuvés lorsque la politique WhatsApp l'exige, notamment hors de la fenêtre de service de 24 heures.
7. Minimiser les données sensibles dans les messages et ne pas diffuser les résultats scolaires ou les soldes à un destinataire non vérifié.
8. Garder l'envoi désactivé par défaut jusqu'à la validation de la configuration et des tests.

## Plan proposé

### Étape 1 — contrat et configuration (sans envoi)

- Définir une configuration serveur qui lit les variables d'environnement sans afficher leurs valeurs.
- Ajouter un contrôle de disponibilité qui ne contacte pas l'API d'envoi et ne révèle aucun secret.
- Définir les permissions RBAC nécessaires et vérifier la manière dont les permissions sont déclarées dans le projet.
- Documenter les prérequis Meta : compte WhatsApp Business, numéro/Phone Number ID, jeton avec permissions nécessaires et modèles approuvés.

Variables envisagées : `WHATSAPP_ACCESS_TOKEN`, `WHATSAPP_PHONE_NUMBER_ID`, `WHATSAPP_API_VERSION`, `WHATSAPP_WEBHOOK_VERIFY_TOKEN`. Elles ne doivent pas être ajoutées avec des valeurs réelles au dépôt.

### Étape 2 — consentement et traçabilité

- Concevoir une migration SQL additive, séparée, à examiner avant exécution.
- Définir les états de consentement/désinscription et un journal d'envoi avec identifiant externe, statut, horodatage et clé anti-doublon.
- Vérifier les liens élève-parent et la règle métier autorisant chaque catégorie de notification.

### Étape 3 — envoi contrôlé

- Ajouter un endpoint protégé, d'abord en mode simulation sans appel externe.
- Tester RBAC, CSRF, validation des destinataires, consentement, anti-doublon, erreurs et journalisation.
- Activer les envois réels uniquement après validation manuelle et configuration Meta.

### Étape 4 — automatisation progressive

- Ajouter une file de tâches et des déclencheurs seulement après identification des événements métier fiables.
- Démarrer par un type de notification à faible risque; vérifier les résultats avant d'élargir.

## Hors périmètre de cette phase

- Aucune migration exécutée.
- Aucune modification des tables existantes.
- Aucun envoi WhatsApp réel.
- Aucun secret ajouté au dépôt.
- Aucun changement de configuration de production.
