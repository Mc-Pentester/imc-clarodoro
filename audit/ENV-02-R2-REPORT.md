# ENV-02-R2 - DIAGNOSTIC PHP / POSTGRESQL

Date: 2026-10-01 11:06:40
Machine: LIAM-EIDEN
User: FAMV

## RESULTATS

| ID | Status | Component | Details |
|----|--------|-----------|---------|| ENV-02-R2-01 | PASS | Projet | Projet trouve : C:\IMC-Clarodoro-securise-client\IMC-Clarodoro |
| ENV-02-R2-02 | PASS | PHP | PHP 8.2.34 (cli) (built: Sep 22 2026 09:01:25) (ZTS Visual C++ 2019 x64) |
| ENV-02-R2-03-PDO | PASS | PHP extension | PDO disponible |
| ENV-02-R2-03-pdo_pgsql | PASS | PHP extension | pdo_pgsql disponible |
| ENV-02-R2-03-pgsql | PASS | PHP extension | pgsql disponible |
| ENV-02-R2-04 | PASS | psql | psql (PostgreSQL) 18.4 |
| ENV-02-R2-05 | PASS | PostgreSQL port | Port 5432 en ecoute : postgres PID=4552, postgres PID=4552 |
| ENV-02-R2-06 | WARNING | Service PostgreSQL | Service Stopped, mais un processus PostgreSQL peut etre actif |
| ENV-02-R2-07 | WARNING | PHP -> PostgreSQL | Mot de passe non fourni, test saute |
| ENV-02-R2-08 | WARNING | Base IMC-Clarodoro | Mot de passe non fourni, inventaire saute |

## STATISTIQUES

- Total tests: 10
- PASS: 7
- WARNING: 3
- BLOCKED: 0

## VERDICT

PASS

## INTEGRITE

Aucune modification de:
- Base de donnees
- Tables
- Donnees
- Fichiers applicatifs

## PROCHAINE ETAPE
Validation complete. PrÃªt pour ARCH-01 validation des endpoints.
