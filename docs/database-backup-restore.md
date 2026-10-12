# Sauvegarde et restauration PostgreSQL — IMC-Clarodoro

## Portée
Ce mécanisme produit une sauvegarde PostgreSQL complète au format pg_dump custom, accompagnée d'un manifeste SHA-256, et permet de la restaurer dans une base séparée. Il ne sauvegarde pas les données historiques qui existent uniquement dans le navigateur (localStorage/IndexedDB), ni les fichiers stockés hors base : ces éléments nécessitent une stratégie distincte.

## Pré-requis
- PowerShell 7 recommandé.
- pg_dump, pg_restore et psql accessibles dans PATH.
- Variables d'environnement définies dans la session, sans les enregistrer dans Git : DB_HOST (facultatif, défaut localhost), DB_PORT (facultatif, défaut 5432), DB_NAME, DB_USER et DB_PASSWORD.
- Le compte PostgreSQL doit pouvoir lire la base source, créer une base de test et s'y connecter.

## Créer une sauvegarde
Depuis la racine du dépôt, définissez les variables de connexion dans la session PowerShell :

```powershell
$env:DB_HOST = "localhost"
$env:DB_PORT = "5432"
$env:DB_NAME = "imc_clarodoro"
$env:DB_USER = "postgres"
$secure = Read-Host "Mot de passe PostgreSQL" -AsSecureString
$env:DB_PASSWORD = [System.Net.NetworkCredential]::new("", $secure).Password

.\Scripts\DB-BACKUP-RESTORE.ps1 -Mode Backup
```

La commande crée un fichier .backup et son fichier .backup.manifest.json dans backups/ par défaut. Le manifeste contient la date UTC, la taille et l'empreinte SHA-256. Copiez les deux fichiers vers un support séparé, protégé et chiffré si les données sont sensibles. Ne commitez jamais les sauvegardes dans Git.

## Tester une restauration sans toucher à la base active
Utilisez une nouvelle base cible, par exemple imc_clarodoro_restore_test. Le script refuse la base source et toute base cible existante :

```powershell
.\Scripts\DB-BACKUP-RESTORE.ps1 `
  -Mode Restore `
  -BackupFile "C:\chemin\vers\imc_clarodoro_YYYYMMDD_HHMMSS.backup" `
  -TargetDatabase "imc_clarodoro_restore_test" `
  -ConfirmRestore
```

La restauration exige le manifeste et vérifie le SHA-256 avant de créer la base. En cas d'erreur, la base de test peut être partielle; inspectez-la avant toute action. Le script ne supprime aucune base et n'utilise pas l'option --clean.

## Procédure opérationnelle minimale
1. Faire une sauvegarde avant une migration ou une opération sensible.
2. Vérifier que les deux fichiers sont présents et conserver une copie hors de la machine.
3. Régulièrement, restaurer dans une base de test distincte.
4. Vérifier les tables, le nombre d'enregistrements et quelques totaux métier critiques.
5. Ne jamais considérer une sauvegarde comme validée tant qu'une restauration réelle n'a pas réussi.
6. Mettre en place une planification automatique et une politique de rétention après validation des paramètres de l'environnement client.

## Limite importante
Ajouter ce script au dépôt ne sauvegarde pas automatiquement la base locale. Il doit être exécuté sur la machine qui héberge PostgreSQL avec les bons identifiants et outils.
