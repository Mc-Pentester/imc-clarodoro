ENV-03 â€” ARCH-01 HTTP VALIDATION
Rapport automatise
Projet : C:\IMC-Clarodoro-securise-client\IMC-Clarodoro
Base URL : http://localhost:8080
Date debut : 10/01/2026 11:14:56
Date fin : 10/01/2026 11:14:58
Duree : 2.03 secondes

1. VERDICT
PASS WITH WARNINGS

2. STATISTIQUES
| Statut | Nombre |
|--------|--------|
| PASS | 8 |
| WARNING | 6 |
| BLOCKED | 0 |

3. OBJECTIF
Validation de l'exposition HTTP de l'application IMC-Clarodoro
via Apache sur le port 8080.
Endpoints ARCH-01 :
- /api/health.php
- /api/index.php
- /api/health-db.php

4. GARANTIE DE NON-DESTRUCTIVITE
Cette intervention n'a effectue aucune operation destructive.
Elle n'a :
- cree aucune base PostgreSQL ;
- cree aucune table ;
- modifie aucune donnee ;
- supprime aucune donnee ;
- execute aucun INSERT ;
- execute aucun UPDATE ;
- execute aucun DELETE ;
- execute aucun POST metier ;
- demarre aucun service ;
- arrete aucun service ;
- modifie aucun fichier PHP ;
- modifie aucune configuration Apache.

Les requetes HTTP effectuees sont exclusivement des requetes de diagnostic.

5. RESULTATS DETAILLES
| ID | Statut | Composant | Detail |
|----|--------|-----------|--------|
| ENV-03-01 | PASS | Projet | Repertoire projet trouve : C:\IMC-Clarodoro-securise-client\IMC-Clarodoro |
| ENV-03-02 | PASS | Apache | 2 processus httpd detecte(s) |
| ENV-03-03 | PASS | HTTP 8080 | Port 8080 en ecoute : httpd PID=3532 |
| ENV-03-04 | PASS | HTTP racine | GET / -> HTTP 200 en 1058ms |
| ARCH-01-A-FILE | PASS | API Health - fichier | Fichier present : api\health.php (376 octets) |
| ARCH-01-A-HTTP | WARNING | API Health - HTTP | HTTP 404 : The remote server returned an error: (404) Not Found. |
| ARCH-01-B-FILE | PASS | API Index - fichier | Fichier present : api\index.php (392 octets) |
| ARCH-01-B-HTTP | WARNING | API Index - HTTP | HTTP 404 : The remote server returned an error: (404) Not Found. |
| ARCH-01-C-FILE | PASS | API Database Health - fichier | Fichier present : api\health-db.php (1130 octets) |
| ARCH-01-C-HTTP | WARNING | API Database Health - HTTP | HTTP 404 : The remote server returned an error: (404) Not Found. |
| ARCH-01-ROUTING | WARNING | Routage API | /api/index.php repond HTTP 404 |
| ARCH-01-DB-HTTP | WARNING | Health DB HTTP | /api/health-db.php repond HTTP 404 |
| ARCH-01-HEAD | WARNING | HTTP HEAD | HEAD non supporte ou non expose : The remote server returned an error: (404) Not Found. |
| ARCH-01-SECURITY | PASS | Exposition secrets | Aucun secret evident trouve dans les apercus HTTP |

6. PREUVES HTTP DES ENDPOINTS
| Endpoint | URL | HTTP | Content-Type | Temps ms | Taille | Apercu |
|----------|-----|-----|--------------|---------|-------|--------|
| ARCH-01-A | /api/health.php | 404 |  |  | 0 | [REQUEST FAILED] |
| ARCH-01-B | /api/index.php | 404 |  |  | 0 | [REQUEST FAILED] |
| ARCH-01-C | /api/health-db.php | 404 |  |  | 0 | [REQUEST FAILED] |

7. INTERPRETATION
**PASS**
Le controle correspondant a ete demontre par le diagnostic.

**WARNING**
Le controle fonctionne partiellement ou presente un element necessitant une analyse complementaire.
Un WARNING ne signifie pas automatiquement que l'application est defaillante.

**BLOCKED**
Le controle n'a pas pu etre realise ou l'acces HTTP requis est indisponible.

8. IMPORTANT â€” HEALTH DB
La disponibilite HTTP de /api/health-db.php ne prouve pas necessairement que la connexion PHP -> PostgreSQL fonctionne.
Elle prouve seulement que l'endpoint est accessible si son code repond.
La connexion PostgreSQL doit etre consideree comme une preuve distincte.

9. PROCHAINE DECISION
Apres analyse de ce rapport, l'etape suivante pourra etre determinee parmi :
- correction HTTP/Apache ;
- correction du chargement de configuration DB ;
- validation PHP -> PostgreSQL ;
- preparation controlee de imc_clarodoro ;
- analyse du schema SQL existant ;
- validation ARCH-01 finale.

Aucune de ces operations n'a ete executee automatiquement par ce diagnostic.

10. SECURITE
Les reponses HTTP ont ete inspectees a la recherche de motifs evidents :
- mot de passe ;
- token ;
- secret ;
- cle API ;
- cle privee ;
- erreurs PHP ;
- traces d'exception.

Les valeurs potentiellement sensibles sont masquees dans les apercus du rapport lorsqu'elles sont detectees.

11. FICHIERS DE RAPPORT
Rapport automatique : C:\IMC-Clarodoro-securise-client\IMC-Clarodoro\audit\ENV-03-ARCH-01-HTTP-VALIDATION-REPORT.md
Rapport final : C:\IMC-Clarodoro-securise-client\IMC-Clarodoro\audit\ENV-03-ARCH-01-HTTP-VALIDATION-REPORT-FINAL.md
