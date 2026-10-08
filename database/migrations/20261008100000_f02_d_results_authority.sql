-- F-02-D: server-authoritative result controls and subject grading scale.
-- Non-destructive and idempotent.

ALTER TABLE subjects
    ADD COLUMN IF NOT EXISTS max_points NUMERIC(8,2) NOT NULL DEFAULT 100;

ALTER TABLE subjects
    ADD CONSTRAINT subjects_max_points_check
    CHECK (max_points > 0)
    NOT VALID;

ALTER TABLE grades
    ADD COLUMN IF NOT EXISTS assessment_number SMALLINT NOT NULL DEFAULT 1;

ALTER TABLE grades
    ADD CONSTRAINT grades_assessment_number_check
    CHECK (assessment_number BETWEEN 1 AND 3)
    NOT VALID;

CREATE UNIQUE INDEX IF NOT EXISTS grades_enrollment_subject_assessment_unique
    ON grades(enrollment_id, subject_id, assessment_number);

CREATE INDEX IF NOT EXISTS idx_grades_assessment
    ON grades(enrollment_id, assessment_number);
