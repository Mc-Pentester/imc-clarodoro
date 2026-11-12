-- Restore the complete least-privilege PDG access required by payroll and manual WhatsApp.
-- Additive and idempotent. Consent administration remains a separate permission.
INSERT INTO permissions (name, description)
VALUES
    ('paies.read', 'Lire les paies du personnel'),
    ('paies.create', 'Créer une paie du personnel'),
    ('paies.update', 'Modifier une paie du personnel'),
    ('whatsapp.message.send', 'Préparer un message WhatsApp manuel'),
    ('whatsapp.consent.read', 'Consulter les consentements WhatsApp')
ON CONFLICT (name) DO NOTHING;

INSERT INTO role_permissions (role_id, permission_id)
SELECT r.id, p.id
FROM roles AS r
CROSS JOIN permissions AS p
WHERE r.name = 'PDG'
  AND p.name IN (
      'paies.read',
      'paies.create',
      'paies.update',
      'whatsapp.message.send',
      'whatsapp.consent.read'
  )
ON CONFLICT (role_id, permission_id) DO NOTHING;
