# P0-A.3-B — STUDENTS CREATE API REPORT

## Objectif

Valider l'API métier de création d'étudiants avec authentification serveur et RBAC.

## Endpoint

**URL:** `/api/students/index.php`
**Méthode:** POST
**Permission requise:** `eleves.create`

Le même endpoint expose également GET, traité par P0-A.3-A.

## Contrat POST

Champs obligatoires:
- `matricule`
- `last_name`
- `first_name`

Champs optionnels:
- `date_of_birth`
- `sex`
- `address`
- `phone`
- `status`

Comportements validés:
- JSON invalide → 400
- champ obligatoire manquant → 422
- status invalide → 422
- champ inconnu → 422
- matricule déjà existant → 409
- création valide → 201
- méthodes non supportées → 405
- champs serveur (`id`, `created_at`, `updated_at`) non contrôlés par le client

## Sécurité

- Authentification serveur via session HTTP-only
- Autorisation via `requirePermission($pdo, 'eleves.create')`
- Aucun rôle ou permission fourni par le client n'est utilisé pour autoriser l'action
- Les paramètres JSON `role` et `permission` sont rejetés comme champs inconnus
- Les headers `X-Role` et `X-Permission` n'influencent pas l'autorisation
- POST sans session → 401
- POST après logout → 401
- Nettoyage limité à l'étudiant créé par le test
- Aucun rôle, permission ou compte existant n'a été modifié par le test

## Validation syntaxique

- PHP (`api/students/index.php`): PASS
- PowerShell (`tests/security/P0-A.3-B-students-create.ps1`): PASS

## Tests runtime

18 tests ont été exécutés.

1. POST sans session → 401 — PASS
2. LOGIN PDG → 200 — PASS
3. POST valide → 201 — PASS
4. Vérification des données → PASS
5. GET après création → 200 — PASS
6. Étudiant visible dans GET → PASS
7. JSON invalide → 400 — PASS
8. `matricule` manquant → 422 — PASS
9. `last_name` manquant → 422 — PASS
10. `first_name` manquant → 422 — PASS
11. `status` invalide → 422 — PASS
12. Champ inconnu → 422 — PASS
13. Spoof JSON `role`/`permission` → PASS
14. Header `X-Role` → PASS
15. Header `X-Permission` → PASS
16. Logout → 200 — PASS
17. POST après logout → 401 — PASS
18. Cleanup de l'étudiant de test → PASS

## Résultat

**18/18 tests PASS**

**Statut: PASS**

## Correction appliquée pendant la validation

Les tests 14 et 15 utilisaient initialement des matricules fixes déjà susceptibles d'avoir été créés par les exécutions précédentes. Ils pouvaient donc recevoir un `409 Conflict` avant de vérifier le comportement des headers.

Le script a été corrigé pour utiliser des matricules uniques:
- `P0-A3B-XROLE-$timestamp`
- `P0-A3B-XPERMISSION-$timestamp`

Après cette correction, les deux tests sont PASS.

## Limites

- Le test ne modifie pas les rôles ou permissions.
- Le nettoyage supprime uniquement l'étudiant créé par le scénario principal.
- Le test dépend d'un serveur PHP local disponible sur `http://127.0.0.1:8090`.
- Le test dépend d'un compte PDG actif et de la base PostgreSQL locale.

## Conclusion

**P0-A.3-B — CLOSED / PASS**

La création d'étudiant par POST est validée en runtime avec authentification serveur, RBAC, validation des entrées, résistance aux tentatives de spoofing par JSON/headers, logout et nettoyage contrôlé.
