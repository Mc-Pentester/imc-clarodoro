-- Add the least-privilege permission to administer academic levels and classes.
INSERT INTO permissions (name, description)
VALUES ('classes.manage', 'Créer, modifier et archiver les niveaux et classes scolaires')
ON CONFLICT (name) DO NOTHING;
INSERT INTO role_permissions (role_id, permission_id)
SELECT r.id,p.id FROM roles r CROSS JOIN permissions p
WHERE r.name='PDG' AND p.name='classes.manage'
ON CONFLICT (role_id,permission_id) DO NOTHING;
