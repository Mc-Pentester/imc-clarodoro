-- F-02-B: non-destructive subject lifecycle.
ALTER TABLE subjects ADD COLUMN IF NOT EXISTS status VARCHAR(30) NOT NULL DEFAULT 'ACTIVE';
ALTER TABLE subjects DROP CONSTRAINT IF EXISTS subjects_status_check;
ALTER TABLE subjects ADD CONSTRAINT subjects_status_check CHECK (status IN ('ACTIVE','INACTIVE','ARCHIVED'));
CREATE INDEX IF NOT EXISTS idx_subjects_status ON subjects(status);
