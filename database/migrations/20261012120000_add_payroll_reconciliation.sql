-- Additive and non-destructive: allow explicit, auditable import of legacy payroll rows.
ALTER TABLE payroll_entries
    ADD COLUMN IF NOT EXISTS legacy_source_key CHAR(64);

CREATE UNIQUE INDEX IF NOT EXISTS uq_payroll_entries_legacy_source_key
    ON payroll_entries (legacy_source_key)
    WHERE legacy_source_key IS NOT NULL;

CREATE TABLE IF NOT EXISTS payroll_reconciliation_audit (
    source_key_hash CHAR(64) PRIMARY KEY,
    source_staff_id TEXT NOT NULL,
    target_staff_id UUID NOT NULL REFERENCES staff(id) ON DELETE RESTRICT,
    school_year_id UUID NOT NULL REFERENCES school_years(id) ON DELETE RESTRICT,
    payroll_month SMALLINT NOT NULL CHECK (payroll_month BETWEEN 1 AND 12),
    payroll_entry_id UUID NOT NULL REFERENCES payroll_entries(id) ON DELETE RESTRICT,
    actor_user_id UUID NOT NULL REFERENCES users(id) ON DELETE RESTRICT,
    action VARCHAR(20) NOT NULL CHECK (action IN ('IMPORTED')),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_payroll_reconciliation_audit_created_at
    ON payroll_reconciliation_audit (created_at DESC);

INSERT INTO permissions (name, description)
VALUES ('paies.reconcile', 'Rapprocher les paies historiques après confirmation')
ON CONFLICT (name) DO NOTHING;

INSERT INTO role_permissions (role_id, permission_id)
SELECT r.id, p.id
FROM roles r
CROSS JOIN permissions p
WHERE r.name = 'PDG'
  AND p.name = 'paies.reconcile'
ON CONFLICT DO NOTHING;
