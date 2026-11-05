# Installateur Windows — IMC-Clarodaro

## Runtimes embarqués

La version 1.1.0 du paquet prépare et intègre les runtimes Windows x64 suivants depuis les distributions officielles, avec vérification des archives PHP et PostgreSQL par SHA-256 :

- PHP 8.4.27 NTS x64 avec PDO PostgreSQL (pdo_pgsql) et pgsql.
- PostgreSQL 18.6 x64 (binaires EDB : bin, lib, share).
- Redistribuable Microsoft Visual C++ x64, dont la signature Authenticode Microsoft est vérifiée.

Les binaires ne sont pas stockés dans Git. Le workflow Windows les télécharge, les vérifie, teste les exécutables et les extensions PHP, puis les incorpore à l'EXE Inno Setup.

## Configuration Windows ajoutée

Après copie des fichiers, l'installateur exécute `Configure-Windows-Services.ps1` :

- Sur une première installation réellement vierge (aucun .env applicatif), crée une instance PostgreSQL dédiée dans `%ProgramData%\IMC-Clarodaro\PostgreSQL\data`.
- Le runtime PostgreSQL (bin, lib, share) est installé sous `%ProgramData%\IMC-Clarodaro\runtime\postgresql`, un chemin système ASCII indépendant du dossier d'installation ; cela évite les conversions de chemins accentués dans `initdb` et les processus PostgreSQL. Il est conservé à la désinstallation pour permettre une réinstallation sûre.
- Enregistre uniquement le service `IMC-Clarodaro-PostgreSQL` sous le compte restreint NetworkService, avec les données sous ProgramData et le port local 55432 par défaut.
- Crée un rôle applicatif et une base dédiés avec des secrets aléatoires ; la configuration protégée est conservée dans `%ProgramData%\IMC-Clarodaro\config\.env`.
- Exécute `database/schema.sql` uniquement sur cette base neuve et vide, crée l'historique de migrations initial, puis lance `database/migrate.php --status` et `--apply`.
- Démarre PHP au démarrage de Windows via une tâche planifiée `IMC-Clarodaro-PHP-Server` sous le compte restreint LocalService, avec le routeur PHP et le port 18080.
- Ajoute une aucune règle pare-feu entrante n'est créée ; le serveur écoute uniquement sur 127.0.0.1:18080.
- Journalise la configuration dans `%ProgramData%\IMC-Clarodaro\logs\installer-services.log`.

Les comptes PHP (LocalService) et PostgreSQL (NetworkService) sont distincts et limités ; les permissions d écriture sont accordées uniquement aux répertoires nécessaires. La tâche PHP est une tâche planifiée au démarrage, pas un service Windows natif. Le serveur PHP intégré est mono-processus sous Windows et écoute exclusivement sur 127.0.0.1:18080. Aucun accès LAN en HTTP clair n'est activé et aucune règle pare-feu entrante n'est créée. Pour un accès depuis d'autres postes, déployer explicitement un reverse proxy HTTPS avec certificat et filtrage réseau ; ne pas exposer directement le serveur PHP intégré.

## Protections de données et mises à jour

- Un fichier `.env` existant à la racine est conservé et traité comme configuration historique : aucune nouvelle base n'est créée et aucune migration n'est appliquée automatiquement.
- Une configuration ProgramData déjà présente est conservée sans réécriture.
- Avant une mise à jour, seuls la tâche PHP et le service PostgreSQL appartenant à cette installation sont arrêtés proprement ; les données restent intactes.
- Lors du passage depuis le précédent emplacement du runtime PostgreSQL sous `{app}`, le script vérifie strictement le service Clarodaro (exécutable historique, cluster ProgramData et compte NetworkService), le retire puis le réenregistre depuis le runtime ASCII ProgramData. Il ne lance jamais `initdb` ni ne recrée la base pendant cette transition.
- À la désinstallation, seuls la tâche, le service et la règle pare-feu Clarodaro vérifiés sont retirés. Le dossier ProgramData (base, configuration, secrets et journaux) est conservé, ainsi que les répertoires applicatifs backups, uploads et storage.
- Lors d'une réinstallation après désinstallation, si le `.env` ProgramData indique la base locale et que `PG_VERSION` existe, le service PostgreSQL est réenregistré sur le cluster conservé. Aucun `initdb`, `schema.sql` ou migration n'est rejoué.
- Un répertoire de données existant sans configuration cohérente n'est jamais réinitialisé.
- Une initialisation interrompue laisse un marqueur qui bloque le démarrage automatique jusqu'à réparation.
- `database/schema.sql` et les migrations ne sont jamais exécutés sur une base existante ; ils sont réservés à la création d'une base neuve par cet installateur. Aucune restauration n'est lancée.
- Après la préparation de la base et le démarrage des services, l'installateur affiche une fenêtre obligatoire de création du compte PDG si aucun utilisateur portant l'identifiant `pdg` ou le rôle `PDG` n'existe. Le mot de passe est masqué, confirmé deux fois, validé (12 caractères ASCII imprimables minimum), puis transmis au bootstrap CLI ; seul son hash est stocké.
- Si un compte PDG existe déjà, l'installateur ne demande aucun nouveau mot de passe et conserve son hash, son rôle et ses permissions. Cette règle s'applique aux mises à jour, réinstallations et réinstallations après désinstallation.
- Annuler ou échouer la création du PDG interrompt le parcours d'installation : l'installation ne peut pas être déclarée terminée sans compte PDG. Les données et comptes existants ne sont pas réinitialisés.
- En mode silencieux, aucun dialogue ne peut être affiché : le déploiement doit fournir explicitement `IMC_BOOTSTRAP_PASSWORD` dans l'environnement du processus d'installation. Sans cette variable, l'installation silencieuse est refusée. Le workflow CI fournit un secret de test dédié et vérifie que le hash PDG ne change pas après réinstallation.
- La base, la configuration et les journaux d'installation/PHP sont stockés dans ProgramData. Le répertoire historique `backups` reste dans l'application. La désinstallation conserve ces données.

## Limites et validations obligatoires

L'intégration des runtimes et l'orchestration des services sont maintenant présentes dans le code, mais **ne pas distribuer comme installateur autonome validé avant les tests Windows réels** :

1. installation sur Windows vierge ;
2. vérification du service PostgreSQL et du démarrage PHP après redémarrage ;
3. accès local et depuis un autre poste du LAN ;
4. réinstallation et mise à jour avec configuration et données existantes ;
5. chemin contenant espaces et caractères accentués ;
6. conflit sur les ports 55432 et 18080 ;
7. présence d'un PostgreSQL tiers ;
8. désinstallation sans suppression de ProgramData ni des données.

Aucun test ne doit utiliser la base de production.

## Construction

Le workflow GitHub Actions **Windows installer package** télécharge les runtimes, vérifie les empreintes/signatures, prépare le payload, compile `installer/IMC-Clarodaro.iss` et publie l'artefact `IMC-Clarodaro-Windows-Installer`.
