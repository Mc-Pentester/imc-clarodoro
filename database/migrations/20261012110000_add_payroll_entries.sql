-- P1: Payroll records are persisted in PostgreSQL, not browser localStorage.
-- Additive and non-destructive: existing browser data remains available for idempotent import.
INSERT INTO permissions (name, description)
VALUES
    ('paies.read', 'Lire les paies du personnel'),
    ('paies.create', 'Créer une paie du personnel'),
    ('paies.update', 'Modifier une paie du personnel')
ON CONFLICT (name) DO NOTHING;

CREATE TABLE IF NOT EXISTS payroll_entries (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    staff_id UUID NOT NULL REFERENCES staff(id) ON DELETE RESTRICT,
    school_year_id UUID NOT NULL REFERENCES school_years(id) ON DELETE RESTRICT,
    payroll_month SMALLINT NOT NULL CHECK (payroll_month BETWEEN 1 AND 12),
    base_amount NUMERIC(12,2) NOT NULL DEFAULT 0 CHECK (base_amount >= 0),
    bonus_amount NUMERIC(12,2) NOT NULL DEFAULT 0 CHECK (bonus_amount >= 0),
    deduction_amount NUMERIC(12,2) NOT NULL DEFAULT 0 CHECK (deduction_amount >= 0),
    net_amount NUMERIC(12,2) GENERATED ALWAYS AS (
        GREATEST(0::numeric, base_amount + bonus_amount - deduction_amount)
    ) STORED,
    status VARCHAR(20) NOT NULL DEFAULT 'UNPAID'
        CHECK (status IN ('UNPAID', 'PARTIAL', 'PAID')),
    recorded_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT payroll_entries_staff_year_month_unique
        UNIQUE (staff_id, school_year_id, payroll_month)
);

CREATE INDEX IF NOT EXISTS idx_payroll_entries_year_month
    ON payroll_entries (school_year_id, payroll_month);

CREATE INDEX IF NOT EXISTS idx_payroll_entries_staff
    ON payroll_entries (staff_id);
