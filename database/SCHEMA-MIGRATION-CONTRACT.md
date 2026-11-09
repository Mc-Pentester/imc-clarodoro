# Clarodaro — contrat de cohérence du schéma PostgreSQL

## Schéma effectif

`database/schema.sql` est le socle initial V1.1, pas un instantané complet du schéma courant. La base effective est obtenue en appliquant ce socle puis toutes les migrations de `database/migrations/` dans l'ordre lexicographique.

- Installation neuve : exécuter `database/schema.sql`, puis `php database/migrate.php --apply`.
- Mise à niveau : appliquer uniquement les migrations manquantes suivies par `schema_migrations`.
- Une base existante sans historique `schema_migrations` reste bloquée jusqu'à l'établissement d'un baseline vérifié. Ne jamais rejouer aveuglément le socle ou les anciennes migrations sur des données existantes.

## Contrat automatisé

Après les migrations, exécuter `psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f database/schema-contract.sql`. Le contrat vérifie les tables et colonnes utilisées par RBAC, références scolaires, élèves, inscriptions, résultats, présences, finances, dépenses, personnel, paies, badges et WhatsApp. Une colonne manquante provoque un échec SQL.

Toute nouvelle requête métier doit être accompagnée d'une migration additive et de ses colonnes attendues dans `schema-contract.sql`. Une migration publiée n'est jamais réécrite : ajouter une migration corrective. Les valeurs métier ne doivent pas être inventées par l'interface pour masquer une absence de colonne ou une panne PostgreSQL.
