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
- Démarre PHP au démarrage de Windows via une tâche planifiée `IMC-Clarodaro-PHP-Server` sous le compte restreint LocalService, avec le routeur PHP et le port 8080.
- Ajoute une règle pare-feu TCP 8080 limitée au profil réseau privé.
- Journalise la configuration dans `%ProgramData%\IMC-Clarodaro\logs\installer-services.log`.

Les comptes PHP (LocalService) et PostgreSQL (NetworkService) sont distincts et limités ; les permissions d écriture sont accordées uniquement aux répertoires nécessaires. La tâche PHP est une tâche planifiée au démarrage, pas un service Windows natif. Le serveur PHP intégré est mono-processus sous Windows et l'accès LAN actuel utilise HTTP sans TLS. Il doit être remplacé ou complété par un serveur HTTP de production avec HTTPS avant toute distribution commerciale ; pour les essais, limiter l'accès à un réseau privé de confiance.

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
- L'option de configuration initiale vérifie d'abord si un utilisateur PDG existe. Si aucun n'existe, elle demande deux fois un mot de passe puis appelle le bootstrap CLI existant. Si un PDG existe, elle ne modifie rien. En installation silencieuse, l'invite est ignorée.
- Le compte PDG n'est jamais créé ou réinitialisé par une mise à jour. Le script peut être lancé manuellement si l'invite a été ignorée.
- La base, la configuration et les journaux d'installation/PHP sont stockés dans ProgramData. Le répertoire historique `backups` reste dans l'application. La désinstallation conserve ces données.

## Limites et validations obligatoires

L'intégration des runtimes et l'orchestration des services sont maintenant présentes dans le code, mais **ne pas distribuer comme installateur autonome validé avant les tests Windows réels** :

1. installation sur Windows vierge ;
2. vérification du service PostgreSQL et du démarrage PHP après redémarrage ;
3. accès local et depuis un autre poste du LAN ;
4. réinstallation et mise à jour avec configuration et données existantes ;
5. chemin contenant espaces et caractères accentués ;
6. conflit sur les ports 55432 et 8080 ;
7. présence d'un PostgreSQL tiers ;
8. désinstallation sans suppression de ProgramData ni des données.

Aucun test ne doit utiliser la base de production.

## Construction

Le workflow GitHub Actions **Windows installer package** télécharge les runtimes, vérifie les empreintes/signatures, prépare le payload, compile `installer/IMC-Clarodaro.iss` et publie l'artefact `IMC-Clarodaro-Windows-Installer`.
