# WhatsApp — contrat RBAC et modèle de données proposé

## Statut

Document de conception uniquement. Ce fichier n'est pas une migration et ne doit pas être exécuté par PostgreSQL. Aucun code d'envoi, aucune modification des tables existantes et aucun envoi réel ne sont inclus.

## RBAC existant constaté

- L'API PHP expose `requirePermission(PDO $pdo, string $permissionName)` dans `config/auth.php`.
- Les permissions sont enregistrées dans `permissions` et attribuées via `role_permissions`.
- `bootstrap-auth.php` définit actuellement la matrice des rôles; le rôle `PDG` reçoit la liste complète déclarée par ce script.
- Les permissions WhatsApp ne sont pas présentes dans cette liste au commit audité. Il ne faut pas autoriser un endpoint WhatsApp en se fondant uniquement sur un contrôle côté navigateur.

## Permissions proposées

| Permission | But |
| --- | --- |
| `whatsapp.status.read` | Consulter l'état de configuration sans afficher les secrets |
| `whatsapp.consent.read` | Consulter le statut de consentement |
| `whatsapp.consent.manage` | Enregistrer ou retirer le consentement, avec trace d'audit |
| `whatsapp.message.send` | Demander un envoi manuel autorisé |
| `whatsapp.message.audit` | Consulter les journaux d'envoi et les erreurs expurgées |

Principe par défaut : ne pas ajouter automatiquement ces permissions à tous les rôles. L'attribution doit être décidée explicitement. Le contrôle serveur et la vérification CSRF restent obligatoires pour toute action modifiant des données ou demandant un envoi.

## Modèle de données à valider avant toute migration

### Consentement

Une table dédiée de consentement devrait au minimum tracer :

- un identifiant UUID ;
- le parent/contact auquel le consentement se rapporte ;
- le canal (WhatsApp) et, si nécessaire, la catégorie de notification ;
- l'état explicite (consenti, retiré) ;
- la date/heure, la source et l'utilisateur ayant enregistré l'action ;
- une preuve/référence limitée, sans stocker inutilement le contenu de conversations.

Il faut décider si le consentement s'applique par parent, par numéro, par élève-parent et/ou par catégorie. En attendant cette décision, l'envoi doit être bloqué en l'absence d'un consentement non ambigu et actif.

### Journal des messages

Un journal distinct devrait conserver :

- une clé d'idempotence unique pour empêcher les doublons ;
- le type de notification et une référence interne à l'événement métier ;
- le destinataire interne et un numéro masqué, pas le jeton ;
- le statut contrôlé (préparé, simulé, envoyé, échoué, annulé) ;
- l'identifiant du message renvoyé par Meta lorsqu'il existe ;
- les horodatages, l'utilisateur initiateur et un code d'erreur expurgé.

Ne pas enregistrer le jeton d'accès, le corps complet de résultats scolaires, les soldes ou d'autres données sensibles dans les logs techniques. Les détails sensibles doivent être minimisés et leur conservation définie.

## Conditions avant de rédiger une migration additive

1. Lire le schéma réel du dépôt pour confirmer les types et contraintes de `parents`, `students` et `student_parents`.
2. Vérifier les règles de relation parent-élève et si un parent peut avoir plusieurs numéros.
3. Définir la portée du consentement et la politique de rétention du journal.
4. Vérifier comment les migrations sont enregistrées et lancées dans ce projet.
5. Ajouter ensuite une migration additive idempotente, dans un commit distinct, pour revue seulement. Ne pas l'exécuter sur la base locale ou de production sans accord explicite.

## Critères de sécurité avant tout envoi

- Authentification serveur active, permission appropriée et CSRF sur les requêtes mutatives.
- Association parent-élève vérifiée côté serveur pour chaque notification ciblée.
- Consentement applicable et actif, numéro validé et absence de désinscription.
- Clé d'idempotence vérifiée avant de contacter Meta.
- Envoi désactivé par défaut; tests en mode simulation sans appel réseau.
- Secrets uniquement dans l'environnement serveur; réponses et logs ne révèlent jamais leurs valeurs.
- Aucun envoi automatique de résultats avant confirmation d'un événement métier fiable de publication.

## Hors périmètre

- Pas de migration SQL dans ce commit.
- Pas d'exécution de migration.
- Pas de changement de base de données.
- Pas de modification de `bootstrap-auth.php` ni des permissions actives.
- Pas d'appel à l'API Meta et aucun message WhatsApp envoyé.
