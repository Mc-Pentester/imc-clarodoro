# Installateur Windows — IMC-Clarodoro

## Runtimes désormais embarqués

La version 1.1.0 du paquet inclut les binaires Windows x64 suivants, téléchargés depuis leurs sources officielles et vérifiés par SHA-256 pendant la CI :

- PHP 8.4.27 NTS x64, avec PDO PostgreSQL (pdo_pgsql) et l'extension pgsql.
- PostgreSQL 18.6 x64 (binaires EDB : bin, lib, share).
- Le manifeste runtime-manifest.json consigne les versions, sources et empreintes vérifiées.

Les archives binaires ne sont pas stockées dans Git : le workflow Windows les télécharge, contrôle leurs empreintes, vérifie que PHP charge les extensions PostgreSQL et que les exécutables PostgreSQL démarrent, puis les incorpore à l'EXE Inno Setup.

## Protections de données

- Le runtime est installé dans le dossier applicatif ; il est distinct des données PostgreSQL.
- Le paquet ne supprime pas les fichiers .env, les sauvegardes ou les journaux existants.
- Aucun répertoire de données PostgreSQL existant n'est initialisé, remplacé ou supprimé.
- Aucun database/schema.sql, migration, restauration ou bootstrap PDG n'est exécuté pendant l'installation ou la mise à jour.
- Aucun service PostgreSQL tiers n'est arrêté, remplacé ou réenregistré.
- La désinstallation ne contient aucune suppression de données persistantes.

## Limite fonctionnelle à ne pas masquer

Cette étape embarque les deux runtimes dans l'installateur, mais ne constitue pas encore la configuration complète d'un poste vierge : l'enregistrement du service PostgreSQL propre à Clarodaro, l'initialisation strictement conditionnelle d'un nouveau cluster, la configuration persistante de la base et le démarrage du serveur PHP comme service Windows restent à implémenter et tester. L'EXE ne doit donc pas encore être annoncé comme installation autonome prête à l'exploitation.

Pour une installation existante, la configuration actuelle et la base déjà utilisée doivent continuer à être conservées ; les nouveaux binaires ne doivent jamais provoquer de migration majeure ni de réinitialisation de données.

## Construction

Le workflow GitHub Actions Windows installer package prépare les runtimes depuis les distributions officielles, vérifie les SHA-256, compile installer/IMC-Clarodoro.iss et publie l'artefact IMC-Clarodaro-Windows-Installer.
