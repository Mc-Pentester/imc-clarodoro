-- F-02-D: server-authoritative finance foundations.
-- Non-destructive: adds finance metadata and permissions without deleting existing data.

INSERT INTO permissions (name, description)
VALUES
 ('finances.read', 'Lire les données financières'),
 ('finances.create', 'Créer une facture ou un versement financier'),
 ('finances.update', 'Modifier une donnée financière'),
 ('finances.delete', 'Archiver une donnée financière')
ON CONFLICT (name) DO NOTHING;

INSERT INTO role_permissions (role_id, permission_id)
SELECT r.id, p.id FROM roles r CROSS JOIN permissions p
WHERE r.name IN ('PDG', 'Directeur')
  AND p.name IN ('finances.read', 'finances.create', 'finances.update', 'finances.delete')
ON CONFLICT DO NOTHING;

ALTER TABLE invoices
    ADD COLUMN IF NOT EXISTS enrollment_id UUID,
    ADD COLUMN IF NOT EXISTS base_amount NUMERIC(12,2),
    ADD COLUMN IF NOT EXISTS discount_amount NUMERIC(12,2) NOT NULL DEFAULT 0,
    ADD COLUMN IF NOT EXISTS discount_reason TEXT;

UPDATE invoices SET base_amount = amount WHERE base_amount IS NULL;
ALTER TABLE invoices ALTER COLUMN base_amount SET DEFAULT 0;

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'invoices_enrollment_fk') THEN
        ALTER TABLE invoices ADD CONSTRAINT invoices_enrollment_fk
            FOREIGN KEY (enrollment_id) REFERENCES enrollments(id) ON DELETE RESTRICT;
    END IF;
END $$;

ALTER TABLE invoices DROP CONSTRAINT IF EXISTS invoices_base_amount_check;
ALTER TABLE invoices ADD CONSTRAINT invoices_base_amount_check CHECK (base_amount >= 0);
ALTER TABLE invoices DROP CONSTRAINT IF EXISTS invoices_discount_amount_check;
ALTER TABLE invoices ADD CONSTRAINT invoices_discount_amount_check
    CHECK (discount_amount >= 0 AND discount_amount <= base_amount);

CREATE INDEX IF NOT EXISTS idx_invoices_enrollment ON invoices(enrollment_id);
CREATE UNIQUE INDEX IF NOT EXISTS invoices_one_per_enrollment
    ON invoices(enrollment_id) WHERE enrollment_id IS NOT NULL AND status <> 'CANCELLED';

CREATE TABLE IF NOT EXISTS fee_schedules (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    school_year_id UUID NOT NULL,
    class_id UUID NOT NULL,
    total_amount NUMERIC(12,2) NOT NULL,
    installment_1_amount NUMERIC(12,2) NOT NULL DEFAULT 0,
    installment_1_label VARCHAR(150),
    installment_2_amount NUMERIC(12,2) NOT NULL DEFAULT 0,
    installment_2_label VARCHAR(150),
    installment_3_amount NUMERIC(12,2) NOT NULL DEFAULT 0,
    installment_3_label VARCHAR(150),
    status VARCHAR(30) NOT NULL DEFAULT 'ACTIVE',
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT fee_schedules_total_check CHECK (total_amount > 0),
    CONSTRAINT fee_schedules_installment_1_check CHECK (installment_1_amount >= 0),
    CONSTRAINT fee_schedules_installment_2_check CHECK (installment_2_amount >= 0),
    CONSTRAINT fee_schedules_installment_3_check CHECK (installment_3_amount >= 0),
    CONSTRAINT fee_schedules_sum_check CHECK (
        installment_1_amount + installment_2_amount + installment_3_amount = total_amount
    ),
    CONSTRAINT fee_schedules_status_check CHECK (status IN ('ACTIVE','INACTIVE','ARCHIVED')),
    CONSTRAINT fee_schedules_year_fk FOREIGN KEY (school_year_id)
        REFERENCES school_years(id) ON DELETE RESTRICT,
    CONSTRAINT fee_schedules_class_fk FOREIGN KEY (class_id)
        REFERENCES classes(id) ON DELETE RESTRICT
);

CREATE UNIQUE INDEX IF NOT EXISTS fee_schedules_one_active
    ON fee_schedules(school_year_id, class_id) WHERE status = 'ACTIVE';
CREATE INDEX IF NOT EXISTS idx_fee_schedules_year ON fee_schedules(school_year_id);
CREATE INDEX IF NOT EXISTS idx_fee_schedules_class ON fee_schedules(class_id);
