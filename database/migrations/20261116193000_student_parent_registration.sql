-- Clarodaro: normalized parent identity. Additive; preserves existing records.
ALTER TABLE parents ADD COLUMN IF NOT EXISTS ninu VARCHAR(10);

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint
        WHERE conname = 'parents_ninu_format_check'
          AND conrelid = 'parents'::regclass
    ) THEN
        ALTER TABLE parents ADD CONSTRAINT parents_ninu_format_check
            CHECK (ninu IS NULL OR ninu ~ '^[0-9]{10}$');
    END IF;
END $$;

CREATE UNIQUE INDEX IF NOT EXISTS parents_ninu_unique
    ON parents (ninu) WHERE ninu IS NOT NULL;
