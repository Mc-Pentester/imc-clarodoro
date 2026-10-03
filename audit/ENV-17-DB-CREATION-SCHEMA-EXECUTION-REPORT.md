# ENV-17 â€” DB CREATION + SCHEMA EXECUTION REPORT

Date d'exÃ©cution : 2026-10-03 11:52:50

Projet : C:\imc-clarodoro
PostgreSQL : 18.x
Host : 127.0.0.1
Port : 5432
Base : imc_clarodoro

## RÃ©sultat

ENV-17 : PASS

Mode : VerifyExisting â€” vÃ©rification non destructive de la base existante

## VÃ©rifications

| ContrÃ´le | Attendu | RÃ©el |
|---|---:|---:|
| Tables publiques | 19 | 19 |
| Foreign Keys | 17 | 17 |
| UNIQUE | 11 | 11 |
| PRIMARY KEY | 19 | 19 |
| CHECK | 23 | 23 |
| Indexes hors contraintes | 13 | 13 |
| Index UNIQUE partiel enrollment | 1 | 1 |
| FK CASCADE | 0 | 0 |
| Triggers applicatifs | 0 | 0 |

## Grades

id,enrollment_id,subject_id,grade,grade_date,created_at,updated_at

## Attendance

id,enrollment_id,attendance_date,status,comment,created_at,updated_at

## Users

id,username,email,password_hash,role_id,status,created_at,updated_at

## SÃ©curitÃ©

- DROP DATABASE : NON
- DROP TABLE : NON
- TRUNCATE : NON
- DELETE : NON
- UPDATE : NON
- Autres bases modifiÃ©es : NON
- Le service Windows PostgreSQL n'a pas Ã©tÃ© dÃ©marrÃ© par ce script.

## SchÃ©ma exÃ©cutÃ©

Aucun â€” mode VerifyExisting : le schÃ©ma existant nâ€™a pas Ã©tÃ© rejouÃ©.

## Verdict

**ENV-17-PASS**
