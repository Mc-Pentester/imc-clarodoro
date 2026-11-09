-- Reconcile permissions that were introduced by migrations which may run
-- before the first-run bootstrap creates the default roles.
-- Additive and idempotent: no existing role or user is removed or replaced.

INSERT INTO permissions (name, description)
VALUES
    ('presences.read', 'Lire les présences'),
    ('presences.create', 'Créer une présence'),
    ('presences.update', 'Modifier une présence'),
    ('whatsapp.message.send', 'Préparer un message WhatsApp manuel'),
    ('whatsapp.consent.read', 'Consulter les consentements WhatsApp')
ON CONFLICT (name) DO NOTHING;

INSERT INTO role_permissions (role_id, permission_id)
SELECT r.id, p.id
FROM roles AS r
CROSS JOIN permissions AS p
WHERE r.name IN ('PDG', 'Directeur', 'Enseignant')
  AND p.name IN ('presences.read', 'presences.create', 'presences.update')
ON CONFLICT (role_id, permission_id) DO NOTHING;

INSERT INTO role_permissions (role_id, permission_id)
SELECT r.id, p.id
FROM roles AS r
CROSS JOIN permissions AS p
WHERE r.name = 'PDG'
  AND p.name IN ('whatsapp.message.send', 'whatsapp.consent.read')
ON CONFLICT (role_id, permission_id) DO NOTHING;
