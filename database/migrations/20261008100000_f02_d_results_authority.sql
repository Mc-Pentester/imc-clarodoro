-- F-02-D: server-authoritative result controls and subject grading scale.
-- Non-destructive and idempotent.

ALTER TABLE subjects
    ADD COLUMN IF NOT EXISTS max_points NUMERIC(8,2) NOT NULL DEFAULT 100;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint
        WHERE conname = 'subjects_max_points_check'
          AND conrelid = 'subjects'::regclass
    ) THEN
        ALTER TABLE subjects
            ADD CONSTRAINT subjects_max_points_check
            CHECK (max_points > 0) NOT VALID;
    END IF;
END $$;

ALTER TABLE grades
    ADD COLUMN IF NOT EXISTS assessment_number SMALLINT NOT NULL DEFAULT 1;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint
        WHERE conname = 'grades_assessment_number_check'
          AND conrelid = 'grades'::regclass
    ) THEN
        ALTER TABLE grades
            ADD CONSTRAINT grades_assessment_number_check
            CHECK (assessment_number BETWEEN 1 AND 3) NOT VALID;
    END IF;
END $$;

CREATE UNIQUE INDEX IF NOT EXISTS grades_enrollment_subject_assessment_unique
    ON grades(enrollment_id, subject_id, assessment_number);

CREATE INDEX IF NOT EXISTS idx_grades_assessment
    ON grades(enrollment_id, assessment_number);
