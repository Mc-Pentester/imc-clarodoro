# P0-A.3-A — STUDENTS READ API REPORT

## Objectif

Créer la première API métier réelle du projet en utilisant le nouveau garde serveur P0-A.2 (RBAC).

## Endpoint

**URL:** `/api/students/index.php`
**Méthodes:**
- GET: permission `eleves.read` (testé par P0-A.3-A)
- POST: permission `eleves.create` (testé par P0-A.3-B)
- PUT/PATCH/DELETE: 405 (testé par P0-A.3-A)

**Note:** P0-A.3-A se concentre sur GET et la protection des méthodes non implémentées. P0-A.3-B teste la création POST.

## Table PostgreSQL

**Table:** `students`
**Colonnes exposées:**
- id
- matricule
- last_name
- first_name
- date_of_birth
- sex
- address
- phone
- status
- created_at
- updated_at

**Ordre:** `created_at DESC, id DESC`

## Sécurité

- Utilise `requirePermission($pdo, 'eleves.read')` avant toute requête SQL
- Refuse PUT/PATCH/DELETE (405)
- Refuse les requêtes non authentifiées (401)
- Refuse les requêtes sans permission (403)
- Ignore les paramètres de query string (?role=, ?permission=)
- Ignore les headers (X-Role, X-Permission)
- Source d'autorisation exclusivement PostgreSQL via requirePermission()
- POST est géré par P0-A.3-B (création étudiant)

## Fichiers créés

1. `api/students/index.php` - Endpoint API students (GET only)
2. `tests/security/P0-A.3-A-students-read.ps1` - Tests de sécurité PowerShell

## Validation syntaxe

- PHP (api/students/index.php): PASS
- PowerShell (tests/security/P0-A.3-A-students-read.ps1): PASS

## Tests de sécurité

Les tests suivants sont définis dans le script PowerShell:

1. GET sans session → 401
2. LOGIN PDG → 200
3. GET avec session PDG → 200 (vérifie success, students, count)
4. GET avec ?role=Autre → 200 (paramètre ignoré)
5. GET avec X-Role header → 200 (header ignoré)
6. GET avec X-Permission header → 200 (header ignoré)
7. PUT → 405
8. DELETE → 405
9. LOGOUT → 200
10. GET après logout → 401

**Note:** POST n'est pas testé dans P0-A.3-A car géré par P0-A.3-B (création étudiant).

## Résultats runtime

**Statut:** PENDING (en attente d'exécution par l'utilisateur)

Le test a été corrigé pour utiliser une méthode fiable de construction JSON (fichier temporaire UTF-8 sans BOM) afin d'éviter les problèmes d'interpolation.

Les tests runtime nécessitent:
- Serveur PHP en cours (http://127.0.0.1:8090)
- Variable d'environnement PDG_PASSWORD définie

Pour exécuter les tests:
```powershell
$env:PDG_PASSWORD = 'your_pdg_password'
php -S 127.0.0.1:8090
.\tests\security\P0-A.3-A-students-read.ps1
```

**Note:** Le test accepte `students=[]` et `count=0` (absence de données métier n'est pas une erreur).

## Limites

- Phase lecture seule pour GET (testé par P0-A.3-A)
- POST géré par P0-A.3-B (création étudiant)
- PUT/PATCH/DELETE non implémentés (405)
- Aucune donnée de test créée par P0-A.3-A
- Aucune modification de la base de données
- Aucune modification des rôles ou permissions

## Conclusion

**P0-A.3-A — PARTIAL**

Validation statique: PASS
Tests runtime: PENDING (en attente d'exécution par l'utilisateur)

La conclusion sera mise à jour à PASS ou FAIL après exécution des tests runtime.
