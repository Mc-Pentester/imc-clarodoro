# ENV-17 — DB CREATION + SCHEMA EXECUTION

Date : 2026-10-01 13:20:00

Projet : C:\IMC-Clarodoro-securise-client\IMC-Clarodoro

PostgreSQL : 18.4
Host : 127.0.0.1
Port : 5432

## 1. Pré-check

PostgreSQL accessible : FAIL
Utilisateur : postgres
Base admin : postgres

**Erreur :** psql.exe n'a pas répondu après 10 secondes lors de la tentative de connexion. Le service PostgreSQL peut ne pas être démarré ou la connexion est bloquée.

## 2. État avant création

imc_clarodoro existait : NON TESTÉ

## 3. Création

Non exécuté - échec du pré-check PostgreSQL.

## 4. Exécution schema.sql

Fichier : database/schema.sql

SQL exécuté : NON

Résultat : REVIEW-REQUIRED

## 5. Tables

Attendu : 19
Réel : NON TESTÉ
Résultat : REVIEW-REQUIRED

## 6. Foreign Keys

Attendu : 17
Réel : NON TESTÉ
Résultat : REVIEW-REQUIRED

## 7. Delete Rules

RESTRICT : NON TESTÉ
CASCADE : NON TESTÉ

## 8. UNIQUE

Attendu : 14
Réel : NON TESTÉ

## 9. CHECK

Attendu : 23
Réel : NON TESTÉ

## 10. INDEX

CREATE INDEX attendus : 13
Réel : NON TESTÉ

## 11. Grades

enrollment_id : NON TESTÉ
student_id absent : NON TESTÉ
coefficient absent : NON TESTÉ

## 12. Attendance

enrollment_id : NON TESTÉ
student_id absent : NON TESTÉ
class_id absent : NON TESTÉ

## 13. Authentication

password_hash : NON TESTÉ
password absent : NON TESTÉ

## 14. Triggers

Attendu : 0
Réel : NON TESTÉ

## 15. Tables V1 exclues

sections : NON TESTÉ
holidays : NON TESTÉ

## 16. PDO

Connexion PDO : NON TESTÉ

Base retournée : NON TESTÉ

Nombre de tables retourné : NON TESTÉ

## 17. Sécurité d'exécution

Autres bases modifiées : NON

DROP DATABASE : NON

DROP TABLE : NON

TRUNCATE : NON

DELETE : NON

UPDATE : NON

## 18. Verdict

ENV-17-REVIEW-REQUIRED

**Échec du pré-check PostgreSQL :** La connexion psql.exe à PostgreSQL 18 sur 127.0.0.1:5432 n'a pas répondu dans le délai imparti (10 secondes). 

**Recommandations :**
1. Vérifier que le service PostgreSQL 18 est démarré
2. Vérifier que le port 5432 est accessible
3. Vérifier que l'authentification postgres fonctionne
4. Relancer ENV-17 après correction de la connexion PostgreSQL

Le fichier database/schema.sql V1.1 est intact et prêt pour exécution une fois la connexion PostgreSQL rétablie.
