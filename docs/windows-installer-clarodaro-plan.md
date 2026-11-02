# Préparation de l'installateur Windows — IMC-Clarodaro

## État de départ vérifié

- L'application est une application PHP avec PostgreSQL ; le dépôt ne contient pas encore de véritable installateur Windows ni de workflow de packaging dédié.
- Le chargement de `.env` est déjà relatif à la racine du projet dans `config/env.php`. Les variables du processus restent prioritaires.
- La connexion PostgreSQL est centralisée dans `config/database.php`.
- Le schéma de référence utilise les tables `users`, `roles` et `role_permissions`. La table `users` impose un nom d'utilisateur unique, un hash de mot de passe et une référence de rôle.
- La procédure actuelle de récupération du compte PDG est une réinitialisation locale CLI : `Scripts/RESET-PDG-PASSWORD.php`. L'endpoint HTTP `api/auth/reset-pdg-password.php` renvoie volontairement HTTP 410. La page `reinitialiser-mot-de-passe.html` explique cette procédure. Ces éléments doivent rester inchangés.

## Principes non négociables

1. Installation dans un répertoire choisi/détecté, sans chemin de projet codé en dur.
2. Toutes les commandes doivent fonctionner avec des chemins contenant espaces et caractères accentués.
3. Les données persistantes et secrets sont séparés des fichiers applicatifs remplaçables.
4. Une mise à jour ou réparation remplace uniquement les fichiers applicatifs gérés par l'installateur ; elle conserve `.env`, les sauvegardes, les fichiers de données, les comptes, rôles et permissions.
5. Aucune suppression, recréation, restauration ou initialisation automatique de la base PostgreSQL existante.
6. Aucun raccourci ou service dupliqué lors d'une réinstallation.
7. Le compte PDG initial est créé uniquement si aucun compte PDG n'existe. Une installation déjà initialisée ne doit jamais réinitialiser ce compte.
8. La récupération PDG existante via CLI est conservée sans changement fonctionnel.

## Architecture proposée

- Installateur Windows Inno Setup (à confirmer selon les dépendances de packaging disponibles).
- Répertoire applicatif versionné, par défaut sous `%ProgramFiles%\IMC-Clarodaro`, avec possibilité de choisir le dossier.
- Répertoire de données persistant sous `%ProgramData%\IMC-Clarodaro` pour `.env`, journaux et sauvegardes ; les chemins effectifs seront enregistrés dans une configuration runtime hors du répertoire applicatif.
- PHP et ses extensions PostgreSQL embarqués ou installés dans un emplacement géré par l'application, jamais supposés présents dans `C:\PHP`.
- Détection PostgreSQL existant et validation de connexion. L'installateur ne doit pas installer/initialiser une instance ni exécuter `database/schema.sql` sur une base existante.
- Assistant de première initialisation protégé côté serveur, transactionnel et à usage unique : vérifier l'absence de compte PDG, vérifier le rôle PDG existant, créer uniquement le compte initial. En présence d'un PDG, refuser la création et renvoyer vers la connexion.
- Arrêt/redémarrage contrôlé du seul processus/service applicatif géré par l'installateur ; ne jamais arrêter ou remplacer PostgreSQL.

## Conditions avant implémentation

- Identifier et figer la méthode de lancement locale (serveur PHP intégré ou serveur web Windows) et son mode de démarrage.
- Définir où sont conservés les fichiers persistants déjà utilisés par les sauvegardes.
- Vérifier les scripts de sauvegarde/restauration et leur dépendance au chemin du projet avant de déplacer les données.
- Ajouter des tests automatisés pour première initialisation, PDG déjà existant, réinstallation, chemin avec espaces/accents, et non-altération des rôles/permissions/données.
- Construire et tester le paquet sur un runner Windows avant publication.

## Tests de non-régression obligatoires

- Installation neuve : l'assistant de création PDG apparaît si et seulement si aucun PDG n'existe.
- Deux soumissions simultanées : un seul compte initial peut être créé.
- Réinstallation avec compte PDG : aucune modification de son identifiant, hash, rôle ou statut.
- Mise à jour : conservation octet pour octet du `.env` et des sauvegardes.
- Base existante : aucune instruction destructive ou réinitialisation du schéma.
- Récupération : le script CLI existant et l'endpoint HTTP désactivé gardent exactement leur comportement.
- Installation et mise à jour depuis un chemin tel que `C:\Applications\École IMC\Clarodaro`.
- Un seul raccourci et une seule entrée de démarrage après plusieurs réinstallations.

Ce document est une spécification de travail, pas la déclaration qu'un installateur est déjà disponible.


## Résultats de l'inspection approfondie du schéma et de l'authentification

- La table `users` ne contient actuellement aucun champ de nom complet ni de relation de profil utilisateur. Le formulaire PDG demandé nécessite donc une évolution additive du schéma (par exemple `users.full_name`) et une migration dédiée, sans reconstruction de la base.
- La connexion utilise `users.username`, `users.password_hash`, `users.role_id` et `users.status`. Le nom complet peut être ajouté sans modifier le mécanisme de connexion.
- **Blocage de sécurité confirmé :** `bootstrap-auth.php` utilise `ON CONFLICT (username) DO UPDATE` pour le compte `pdg`, ce qui remplace son hash, son rôle et son statut si le script est relancé. L'installateur ne devra jamais appeler ce script. La procédure de récupération PDG demeure distincte et inchangée.
- Le workflow CI actuel vérifie la syntaxe PHP/PowerShell et des règles de séparation des pages. Il n'existe pas encore de job de construction/test d'un installateur Windows.
- Les anciens scripts `ENV-01` et `ENV-02-R2` contiennent des chemins fixes. Ils ne doivent pas être réutilisés tels quels par l'installateur ; leur rôle opérationnel doit être établi avant toute modification.

### Décision de conception à appliquer

La création initiale doit être un endpoint distinct, transactionnel et à usage unique. Il devra verrouiller la vérification d'absence de PDG, vérifier que le rôle `PDG` existe déjà, insérer un seul utilisateur et ne modifier aucune permission, aucun rôle ni compte existant. La migration du nom complet sera additive et ne changera aucune donnée existante. Le script de récupération PDG ne sera pas modifié.
