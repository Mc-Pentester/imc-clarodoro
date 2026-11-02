# Architecture de l'installateur Windows autonome — IMC-Clarodaro

## Objectif confirmé

Le livrable final doit embarquer les composants nécessaires sur un poste Windows vierge :
- runtime PHP x64 et extensions PDO PostgreSQL ;
- serveur HTTP PHP géré comme service Windows propre à IMC-Clarodaro ;
- serveur PostgreSQL dédié à IMC-Clarodaro ;
- application et outils de diagnostic/sauvegarde.

Aucune installation préalable de PHP, Apache ou PostgreSQL ne doit être exigée. Apache n'est pas nécessaire : le serveur HTTP PHP peut être lancé par un service Windows supervisé, à condition que le mécanisme de service retenu soit empaqueté, maintenu et testé.

## Emplacements et propriété des données

- Application remplaçable : répertoire choisi par l'utilisateur, par défaut sous Program Files.
- Configuration/secrets : `%ProgramData%\IMC-Clarodaro\config\`.
- Données PostgreSQL : `%ProgramData%\IMC-Clarodaro\postgres-data\`.
- Sauvegardes : `%ProgramData%\IMC-Clarodaro\backups\`.
- Journaux : `%ProgramData%\IMC-Clarodaro\logs\`.
- Runtime PHP et PostgreSQL : répertoires dédiés gérés par l'application, avec versions consignées.

Le chargeur `config/env.php` lit actuellement le `.env` à la racine du projet. Avant de déplacer le fichier, il faut ajouter un mécanisme de chemin de configuration externe prioritaire, puis tester explicitement la compatibilité des installations existantes qui gardent leur `.env` à l'ancien emplacement.

## Règles PostgreSQL impératives

1. L'instance installée par IMC-Clarodaro utilise un nom de service, un port et un répertoire de données propres à l'application.
2. L'installateur détecte les services/ports/répertoires déjà utilisés avant toute action. Il ne prend jamais possession d'une instance PostgreSQL tierce.
3. Lors d'une mise à jour, il réutilise uniquement l'instance IMC-Clarodaro identifiée par son marqueur d'installation et vérifie la version majeure avant mise à niveau.
4. Il ne supprime jamais le répertoire de données lors d'une mise à jour, réparation ou désinstallation standard.
5. Il ne lance ni `initdb`, ni `createdb`, ni migration sur une base préexistante sans un état d'installation explicite et un contrôle de sauvegarde.
6. Une mise à niveau majeure PostgreSQL exige un parcours dédié, une sauvegarde vérifiée et une stratégie de retour arrière ; aucune mise à niveau majeure automatique.

## Stratégie de packaging

- Télécharger les distributions officielles et épingler leurs versions et sommes SHA-256.
- PHP : archive Windows x64 officielle, configurer `php.ini`, activer `pdo_pgsql` et `pgsql`, vérifier les DLL requises.
- PostgreSQL : utiliser une distribution Windows officielle/supportée. Le mode d'installation silencieux doit être audité ; choisir un répertoire de données distinct et un service explicitement nommé. Ne pas intégrer un installateur tiers non vérifié.
- Service applicatif : retenir un superviseur Windows maintenu et redistribuable, ou un petit service hôte signé. Ne pas faire dépendre le service d'une session utilisateur ouverte.
- Inno Setup copie les runtimes validés et exécute un script PowerShell contrôlé pour l'enregistrement des services.

## Phases de réalisation et critères de sortie

1. Corriger la détection du compilateur Inno Setup dans CI.
2. Ajouter l'acquisition reproductible des archives PHP/PostgreSQL, avec versions/SHA-256 et vérification des binaires.
3. Construire le service HTTP et son démarrage/arrêt idempotents.
4. Ajouter la configuration persistante externe sans casser le chargement des anciens `.env`.
5. Ajouter l'installation PostgreSQL isolée et son contrôle d'identité/version/port.
6. Ajouter les tests Windows : poste vierge, réinstallation, mise à jour, chemin avec accents/espaces, conflit de port, PostgreSQL tiers présent, conservation de base et désinstallation conservatrice.
7. Seulement après tests, publier un artefact marqué prêt à distribuer.

## État réel au 2026-11-02

Le paquet actuel n'embarque pas PHP, PostgreSQL ni un service applicatif. Il ne doit pas être distribué comme autonome. Le workflow Inno Setup a été corrigé pour localiser le compilateur dans les emplacements Windows courants et rechercher son chemin après installation. Les phases 2 à 6 restent à implémenter et tester.
