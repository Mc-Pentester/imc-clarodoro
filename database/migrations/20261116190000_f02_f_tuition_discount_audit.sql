-- Tuition discounts: preserve both the applied amount and the user's chosen discount mode.
ALTER TABLE invoices
    ADD COLUMN IF NOT EXISTS reduction_type VARCHAR(10) NOT NULL DEFAULT 'FIXED',
    ADD COLUMN IF NOT EXISTS reduction_percent NUMERIC(5,2) NOT NULL DEFAULT 0;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint
        WHERE conname = 'invoices_reduction_type_check'
          AND conrelid = 'invoices'::regclass
    ) THEN
        ALTER TABLE invoices
            ADD CONSTRAINT invoices_reduction_type_check
            CHECK (reduction_type IN ('FIXED', 'PERCENT'));
    END IF;
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint
        WHERE conname = 'invoices_reduction_percent_check'
          AND conrelid = 'invoices'::regclass
    ) THEN
        ALTER TABLE invoices
            ADD CONSTRAINT invoices_reduction_percent_check
            CHECK (reduction_percent >= 0 AND reduction_percent <= 100);
    END IF;
END $$;

CREATE TABLE IF NOT EXISTS invoice_reduction_audit (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    invoice_id UUID NOT NULL REFERENCES invoices(id) ON DELETE RESTRICT,
    actor_user_id UUID NOT NULL REFERENCES users(id) ON DELETE RESTRICT,
    old_reduction NUMERIC(12,2) NOT NULL,
    new_reduction NUMERIC(12,2) NOT NULL,
    old_reduction_type VARCHAR(10) NOT NULL,
    new_reduction_type VARCHAR(10) NOT NULL,
    old_reduction_percent NUMERIC(5,2) NOT NULL DEFAULT 0,
    new_reduction_percent NUMERIC(5,2) NOT NULL DEFAULT 0,
    old_reason TEXT,
    new_reason TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_invoice_reduction_audit_invoice
    ON invoice_reduction_audit(invoice_id, created_at DESC);

CREATE OR REPLACE FUNCTION prevent_invoice_reduction_audit_mutation()
RETURNS TRIGGER AS $$
BEGIN
    RAISE EXCEPTION 'invoice_reduction_audit is append-only';
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS invoice_reduction_audit_immutable ON invoice_reduction_audit;
CREATE TRIGGER invoice_reduction_audit_immutable
BEFORE UPDATE OR DELETE ON invoice_reduction_audit
FOR EACH ROW EXECUTE FUNCTION prevent_invoice_reduction_audit_mutation();
