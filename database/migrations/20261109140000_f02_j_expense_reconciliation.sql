-- Controlled, auditable import of legacy browser expenses.
-- Source browser data is never deleted or modified by this migration.
CREATE TABLE IF NOT EXISTS expense_reconciliation_audit (
    source_key_hash CHAR(64) PRIMARY KEY,
    source_year_label VARCHAR(50) NOT NULL,
    source_legacy_id VARCHAR(100) NOT NULL,
    target_school_year_id UUID NOT NULL REFERENCES school_years(id) ON DELETE RESTRICT,
    expense_id UUID NOT NULL REFERENCES expenses(id) ON DELETE RESTRICT,
    payload_hash CHAR(64) NOT NULL,
    actor_user_id UUID NOT NULL REFERENCES users(id) ON DELETE RESTRICT,
    action VARCHAR(20) NOT NULL DEFAULT 'IMPORTED' CHECK (action = 'IMPORTED'),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS expense_reconciliation_audit_created_at_idx
    ON expense_reconciliation_audit (created_at DESC);

INSERT INTO permissions (name, description)
VALUES ('depenses.reconcile', 'Importer et rapprocher les dépenses historiques')
ON CONFLICT (name) DO NOTHING;

INSERT INTO role_permissions (role_id, permission_id)
SELECT r.id, p.id FROM roles r CROSS JOIN permissions p
WHERE r.name = 'PDG' AND p.name = 'depenses.reconcile'
ON CONFLICT (role_id, permission_id) DO NOTHING;
