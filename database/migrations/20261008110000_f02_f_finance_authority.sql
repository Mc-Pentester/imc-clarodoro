-- F-02-F — Finance server authority
ALTER TABLE invoices
    ADD COLUMN IF NOT EXISTS school_year_id UUID,
    ADD COLUMN IF NOT EXISTS reduction NUMERIC(12,2) NOT NULL DEFAULT 0,
    ADD COLUMN IF NOT EXISTS reduction_reason TEXT;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint
        WHERE conname = 'invoices_reduction_check'
          AND conrelid = 'invoices'::regclass
    ) THEN
        ALTER TABLE invoices
            ADD CONSTRAINT invoices_reduction_check
            CHECK (reduction >= 0 AND reduction <= amount);
    END IF;
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint
        WHERE conname = 'invoices_school_year_fk'
          AND conrelid = 'invoices'::regclass
    ) THEN
        ALTER TABLE invoices
            ADD CONSTRAINT invoices_school_year_fk
            FOREIGN KEY (school_year_id) REFERENCES school_years(id) ON DELETE RESTRICT;
    END IF;
END $$;

CREATE TABLE IF NOT EXISTS finance_tariffs (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    school_year_id UUID NOT NULL,
    class_id UUID NOT NULL,
    amount NUMERIC(12,2) NOT NULL,
    installment1_amount NUMERIC(12,2) NOT NULL DEFAULT 0,
    installment1_label VARCHAR(150),
    installment2_amount NUMERIC(12,2) NOT NULL DEFAULT 0,
    installment2_label VARCHAR(150),
    installment3_amount NUMERIC(12,2) NOT NULL DEFAULT 0,
    installment3_label VARCHAR(150),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT finance_tariffs_amounts_check CHECK (
        amount >= 0 AND installment1_amount >= 0 AND installment2_amount >= 0 AND installment3_amount >= 0
    ),
    CONSTRAINT finance_tariffs_school_year_fk FOREIGN KEY (school_year_id) REFERENCES school_years(id) ON DELETE RESTRICT,
    CONSTRAINT finance_tariffs_class_fk FOREIGN KEY (class_id) REFERENCES classes(id) ON DELETE RESTRICT,
    CONSTRAINT finance_tariffs_unique UNIQUE (school_year_id, class_id)
);

CREATE INDEX IF NOT EXISTS idx_invoices_school_year ON invoices(school_year_id);
CREATE INDEX IF NOT EXISTS idx_finance_tariffs_school_year ON finance_tariffs(school_year_id);
