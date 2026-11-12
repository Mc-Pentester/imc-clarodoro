-- Full application access for the PDG role.
-- Additive and idempotent: preserves users, existing roles and business data.
-- Permissions added by later migrations are granted by the server-side PDG
-- authorization override, so this also reconciles all permissions known today.
INSERT INTO role_permissions (role_id, permission_id)
SELECT r.id, p.id
FROM roles AS r
CROSS JOIN permissions AS p
WHERE r.name = 'PDG'
ON CONFLICT (role_id, permission_id) DO NOTHING;
