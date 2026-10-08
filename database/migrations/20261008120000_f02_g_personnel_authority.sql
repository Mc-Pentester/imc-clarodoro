ALTER TABLE staff
    ADD COLUMN IF NOT EXISTS user_id UUID,
    ADD COLUMN IF NOT EXISTS class_name VARCHAR(150);

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint
        WHERE conname = 'staff_user_fk'
          AND conrelid = 'staff'::regclass
    ) THEN
        ALTER TABLE staff
            ADD CONSTRAINT staff_user_fk
            FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE RESTRICT;
    END IF;
END $$;

CREATE UNIQUE INDEX IF NOT EXISTS staff_user_id_unique
    ON staff(user_id) WHERE user_id IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_staff_status ON staff(status);
CREATE INDEX IF NOT EXISTS idx_staff_last_name ON staff(last_name);
