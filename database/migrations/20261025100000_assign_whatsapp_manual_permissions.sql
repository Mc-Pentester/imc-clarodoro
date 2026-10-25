-- Grant the manual WhatsApp workflow to the PDG role only.
-- Deliberately do not grant whatsapp.consent.manage: consent administration remains separate.
-- Idempotent: safe to apply more than once.
INSERT INTO role_permissions (role_id, permission_id)
SELECT r.id, p.id
FROM roles AS r
JOIN permissions AS p
  ON p.name IN ('whatsapp.message.send', 'whatsapp.consent.read')
WHERE r.name = 'PDG'
ON CONFLICT DO NOTHING;
