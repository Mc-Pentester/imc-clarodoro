-- Restore the PDG permission required by the protected payroll legacy-reconciliation page.
-- The original reconciliation migration may have run before the first PDG role existed.
-- This follow-up is additive and idempotent; it does not broaden access to other roles.
INSERT INTO permissions (name, description)
VALUES ('paies.reconcile', 'Rapprocher les paies historiques après confirmation')
ON CONFLICT (name) DO NOTHING;

INSERT INTO role_permissions (role_id, permission_id)
SELECT r.id, p.id
FROM roles AS r
CROSS JOIN permissions AS p
WHERE r.name = 'PDG'
  AND p.name = 'paies.reconcile'
ON CONFLICT (role_id, permission_id) DO NOTHING;
