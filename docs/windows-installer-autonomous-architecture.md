# Architecture de l'installateur Windows autonome — IMC-Clarodaro

## Objectif

Le paquet Windows prépare et intègre :
- PHP 8.4.27 NTS x64 avec PDO PostgreSQL, pdo_pgsql et pgsql ;
- PostgreSQL 18.6 x64 ;
- le redistribuable Microsoft Visual C++ x64 signé ;
- l'application, le routeur et les scripts d'orchestration.

Les runtimes sont téléchargés depuis les distributions officielles et vérifiés par SHA-256 pendant la CI. Ils sont intégrés dans l'EXE, sans être commités dans Git.

## Emplacements

- Application et runtimes : répertoire choisi, par défaut sous Program Files.
- Configuration/secrets générés : `%ProgramData%\IMC-Clarodaro\config\`.
- Données PostgreSQL : `%ProgramData%\IMC-Clarodaro\PostgreSQL\data\`.
- Journaux d'installation et PHP : `%ProgramData%\IMC-Clarodaro\logs\`.
- Sauvegardes historiques : le répertoire `backups\` de l'application est conservé ; la désinstallation ne le supprime pas.

Le chargeur `config/env.php` accepte désormais `IMC_CLARODARO_ENV_FILE` pour lire la configuration ProgramData. Sans cette variable, il conserve le comportement historique et lit le `.env` à la racine du projet.

## Première installation vierge

Quand aucun `.env` historique ni fichier de configuration ProgramData n'existe :
1. détecter le port PostgreSQL dédié 55432 ;
2. initialiser un nouveau cluster dans le répertoire ProgramData propre à Clarodaro ;
3. enregistrer le service Windows `IMC-Clarodaro-PostgreSQL` ;
4. générer des secrets aléatoires pour le superutilisateur et le rôle applicatif ;
5. créer la base `imc_clarodoro` et le rôle `imc_clarodaro_app` ;
6. poser un marqueur d'initialisation, puis exécuter `database/schema.sql` uniquement sur cette base neuve et vide ;
7. créer la table d'historique de migrations initiale et écrire le `.env` protégé dans ProgramData ;
8. exécuter `database/migrate.php --status`, puis `--apply` uniquement sur cette base nouvellement créée ;
9. démarrer le serveur PHP sur le port 8080 via la tâche planifiée SYSTEM `IMC-Clarodaro-PHP-Server`.

Le serveur PostgreSQL n'écoute que sur `127.0.0.1`. Le pare-feu n'ouvre le port HTTP 8080 que sur le profil réseau privé.

L'option de configuration initiale vérifie si un utilisateur PDG existe. Si aucun n'existe, elle demande deux fois un mot de passe puis appelle le bootstrap CLI existant. Si un PDG existe, elle ne modifie rien. L'installation silencieuse ignore l'invite ; une mise à jour ne réinitialise jamais le compte.

## Installations existantes et mises à jour

- Un `.env` historique à la racine est conservé et priorisé par le chargeur lorsque le chemin ProgramData n'est pas fourni.
- Un fichier de configuration ProgramData existant n'est jamais remplacé.
- Aucune initialisation PostgreSQL, création de base, exécution de `schema.sql` ou migration automatique n'est exécutée sur une configuration existante.
- Avant une mise à jour, seuls la tâche PHP et le service PostgreSQL dont les chemins correspondent à cette installation sont arrêtés.
- Un service ou une tâche homonyme qui ne correspond pas à l'installation Clarodaro provoque un arrêt sûr.
- Un marqueur bloque le démarrage si l'initialisation de la base neuve a été interrompue.

## Désinstallation

Le script de désinstallation vérifie la propriété des ressources, puis retire uniquement :
- la tâche PHP Clarodaro ;
- le service PostgreSQL Clarodaro ;
- la règle pare-feu Clarodaro.

Les données PostgreSQL, les secrets, le fichier de configuration, les sauvegardes et les journaux ProgramData ne sont pas supprimés.

## Limite du serveur HTTP

Le serveur PHP intégré est actuellement lancé par une tâche planifiée au démarrage. Ce n'est pas un service HTTP natif et le serveur intégré PHP n'est pas encore validé pour une charge de production multi-utilisateurs. Cette limite doit être résolue ou explicitement acceptée avant distribution commerciale.

## Tests Windows automatisés prévus dans la CI

- construction de l'EXE avec les runtimes vérifiés ;
- installation silencieuse sur un runner vierge ;
- contrôle du service PostgreSQL, du serveur PHP et de l'historique des migrations ;
- réinstallation sans désinstallation préalable ;
- chemin d'installation contenant espaces et caractères accentués ;
- témoin SQL confirmant la conservation des données après réinstallation ;
- désinstallation confirmant la conservation ProgramData et le retrait des services.

Les tests doivent rester isolés de toute base de production.

## État au 2026-11-02

Les scripts d'acquisition des runtimes, de configuration des services, de mise à jour et de désinstallation sont présents dans la PR #52. La CI a déjà révélé puis permis de corriger des erreurs de parsing PowerShell et de vérification des codes de sortie PHP. La validation finale de la compilation et du scénario Windows complet reste en attente ; le paquet ne doit pas encore être annoncé comme prêt à distribuer.
