-- F-02-C: server-authoritative results and attendance permissions.
-- Non-destructive and idempotent.

INSERT INTO permissions (name, description)
VALUES
 ('resultats.read','Lire les résultats scolaires'),
 ('resultats.create','Créer un résultat scolaire'),
 ('resultats.update','Modifier un résultat scolaire'),
 ('presences.read','Lire les présences'),
 ('presences.create','Créer une présence'),
 ('presences.update','Modifier une présence')
ON CONFLICT (name) DO NOTHING;

INSERT INTO role_permissions (role_id, permission_id)
SELECT r.id, p.id
FROM roles r
CROSS JOIN permissions p
WHERE r.name IN ('PDG','Directeur','Enseignant')
  AND p.name IN (
    'resultats.read','resultats.create','resultats.update',
    'presences.read','presences.create','presences.update'
  )
ON CONFLICT (role_id, permission_id) DO NOTHING;
