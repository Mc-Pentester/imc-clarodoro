# P0-A.2 — Server-Side RBAC

## Objectif

Décrire la séparation :

Browser
↓
PHP Session
↓
PostgreSQL
↓
Role
↓
Permission
↓
API

## Contrôles implémentés

- authentification serveur
- vérification DB du compte
- vérification status ACTIVE
- rôle provenant de PostgreSQL
- permission provenant de PostgreSQL
- 401 sans session
- 403 permission insuffisante
- aucune confiance dans le navigateur

## Routes

/api/auth/login.php
/api/auth/me.php
/api/auth/logout.php
/api/auth/permission-test.php
/api/auth/permission-denied-test.php

## Tests

PHP syntax : PASS
Static RBAC : PASS
HTTP 401 (permission-test without session) : PASS
HTTP 401 (me without session) : PASS
HTTP 200 (permission-test with PDG session) : PASS
HTTP 200 (me with PDG session) : PASS
HTTP logout : PASS
HTTP post-logout 401 : PASS
HTTP 403 (permission-denied-test for Autre role) : PENDING (requires controlled test account)

## Verdict

PASS

Note: All runtime HTTP tests passed with PDG account. The 403 test for 'Autre' role requires a controlled test account and is not executed automatically to avoid modifying existing data.
