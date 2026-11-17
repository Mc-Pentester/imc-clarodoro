-- Independent parent directory and least-privilege access.
-- Existing parents and student-parent associations are preserved.
INSERT INTO permissions (name, description)
VALUES
    ('parents.read', 'Consulter les fiches parents et leurs associations'),
    ('parents.create', 'Créer une fiche parent'),
    ('parents.update', 'Modifier une fiche parent'),
    ('parents.link', 'Associer ou dissocier un parent et un élève')
ON CONFLICT (name) DO NOTHING;

-- Grant the directory to school leadership/secretariat and to the same roles
-- already authorized to create or update student records. PDG also has the
-- application-wide authorization bypass.
INSERT INTO role_permissions (role_id, permission_id)
SELECT DISTINCT rp.role_id, p.id
FROM role_permissions rp
INNER JOIN permissions student_permission
    ON student_permission.id = rp.permission_id
CROSS JOIN permissions p
WHERE student_permission.name IN ('eleves.create', 'eleves.update')
  AND p.name IN ('parents.read', 'parents.create', 'parents.update', 'parents.link')
ON CONFLICT (role_id, permission_id) DO NOTHING;

INSERT INTO role_permissions (role_id, permission_id)
SELECT r.id, p.id
FROM roles r
CROSS JOIN permissions p
WHERE r.name IN ('PDG', 'Directeur', 'Secrétaire', 'Secretaire')
  AND p.name IN ('parents.read', 'parents.create', 'parents.update', 'parents.link')
ON CONFLICT (role_id, permission_id) DO NOTHING;
