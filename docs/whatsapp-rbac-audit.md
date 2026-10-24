# Audit statique RBAC — préparation WhatsApp

Date : 2026-10-23
Branche : `feature/whatsapp-foundation`
Portée : lecture du code et du schéma versionné sur `main`. Aucun accès à PostgreSQL, aucune migration exécutée, aucune donnée réelle consultée.

## 1. Modèle RBAC réellement défini dans `database/schema.sql`

| Table | Rôle |
|---|---|
| `users` | Compte utilisateur, statut et **un seul** `role_id` obligatoire |
| `roles` | Catalogue des rôles, nom unique |
| `permissions` | Catalogue des permissions, nom unique |
| `role_permissions` | Association plusieurs-à-plusieurs entre rôles et permissions |

Les clés étrangères de `role_permissions` pointent vers `roles(id)` et `permissions(id)`, avec `ON DELETE RESTRICT`. La clé primaire composée `(role_id, permission_id)` empêche les doublons d'association.

Le schéma définit aussi une contrainte canonique sur les rôles dans la migration `20261006200000_normalize_rbac_role_names.sql` : `PDG`, `Directeur`, `Enseignant`, `Secrétaire`, `Surveillant`, `Autre`. La présence effective de cette contrainte sur la base déployée n'a pas été vérifiée.

## 2. Application des contrôles dans le code

### API — `config/auth.php`

- `requireAuthenticatedUser(PDO $pdo)` vérifie la session, recharge le compte dans PostgreSQL, joint `users` à `roles` et refuse les comptes dont le statut n'est pas `ACTIVE`.
- `requirePermission(PDO $pdo, string $permissionName)` vérifie l'autorisation en joignant `role_permissions` à `permissions` pour le `role_id` courant.
- Une absence d'authentification renvoie 401 ; une permission manquante renvoie 403.
- Les sessions utilisent un cookie HttpOnly, SameSite=Lax, un délai d'inactivité et une durée absolue.
- La protection CSRF existe via `requireCsrfToken()`, mais elle doit être appelée explicitement par chaque route mutative : `requirePermission()` ne l'applique pas automatiquement.

### Pages HTML — `config/page_auth.php`

`imcRequirePageAccess()` vérifie la session, le statut du compte et la permission. Un contrôle de rôle explicite (`$requiredRole`) peut aussi être demandé ; il ne doit pas remplacer le contrôle par permission.

### Tests disponibles

`tests/security/P0-A.2-rbac.php` vérifie statiquement la présence des principaux contrôles et les routes de test. Ce test statique ne prouve pas que les permissions et associations de rôles présentes dans la base réelle sont correctes.

## 3. Rôles : ce que l'audit permet — et ne permet pas — d'affirmer

La matrice `docs/P0-02-RBAC-MATRIX.md` décrit six rôles et les permissions attendues pour plusieurs modules. C'est une référence documentaire, pas une preuve de l'état des lignes de `role_permissions` en production.

**Non vérifié à ce stade :**
- les rôles, permissions et associations réellement présents dans la base déployée ;
- les éventuelles différences entre le schéma versionné, les migrations appliquées et la base courante ;
- les permissions exactes de chaque rôle dans les données actives.

Aucune affectation WhatsApp ne doit être déduite automatiquement de la matrice documentaire ni ajoutée sans décision explicite.

## 4. Compatibilité proposée pour WhatsApp

Le code actuel convient à un contrôle par permission sans créer un système d'identité parallèle. Les futures routes WhatsApp devront utiliser le mécanisme existant `requirePermission($pdo, 'nom.permission')`, revalider le statut du compte côté serveur et exiger CSRF sur toute mutation déclenchée par une session web.

| Permission proposée | Usage | Contrôle attendu |
|---|---|---|
| `whatsapp.status.read` | État de la configuration et du service | Lecture limitée, sans secrets |
| `whatsapp.consent.read` | Consulter les consentements | Lecture des seuls dossiers autorisés |
| `whatsapp.consent.manage` | Enregistrer ou retirer un consentement | Authentification + permission + CSRF + trace d'audit |
| `whatsapp.message.send` | Autoriser une action d'envoi manuel ou une mise en file | Permission dédiée, consentement valide et contrôles métier au moment de l'envoi |
| `whatsapp.message.audit` | Consulter les résultats d'envoi et journaux | Pas de jetons, secrets ni contenu sensible inutile |
| `whatsapp.template.manage` | Gérer les modèles autorisés | Permission distincte, validation côté serveur |

Ces noms sont des **propositions** ; ils ne sont pas encore ajoutés à la table `permissions`. Ne pas attribuer automatiquement toutes ces permissions au rôle PDG ni à un autre rôle. L'attribution minimale doit être décidée après examen des responsabilités métier.

## 5. Risques et décisions avant implémentation

1. **État de la base inconnu — bloquant pour toute migration.** Dès que l'accès PostgreSQL sera disponible, exécuter uniquement l'audit SQL en lecture seule déjà préparé et comparer les résultats avec les migrations.
2. **Une seule fonction par utilisateur.** Le modèle courant ne permet pas d'empiler plusieurs rôles sur un compte. La conception WhatsApp doit respecter cette contrainte, sans inventer une table de rôles utilisateurs.
3. **Permission ≠ consentement.** Une permission interne autorise un employé à effectuer une action ; elle ne constitue jamais le consentement du parent à recevoir des messages.
4. **Permission ≠ preuve métier.** Un statut de présence modifiable n'est pas une absence confirmée ; une note enregistrée n'est pas un résultat officiellement publié ; une facture doit être revalidée avant un rappel.
5. **Pas de contournement par rôle.** Les routes WhatsApp doivent s'appuyer sur les permissions spécifiques, et non uniquement sur le nom de rôle ou une vérification côté interface.
6. **Pas d'envoi à ce stade.** Aucun appel à l'API Meta, aucune migration et aucun message ne font partie de cet audit.

## 6. Prochaine étape recommandée

Quand l'accès à PostgreSQL sera rétabli, lancer `Scripts/WHATSAPP-READONLY-DB-AUDIT.sql` et compléter par une extraction strictement en lecture seule des rôles, permissions et associations RBAC (sans mots de passe, téléphones, noms ou autres données personnelles). Ensuite seulement, fixer les permissions à créer et leurs affectations, puis préparer une migration séparée, réversible et non destructive.
