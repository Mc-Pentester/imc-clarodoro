-- F-02-A: staged server-authoritative student profile metadata.
-- Non-destructive: existing student rows receive an empty JSON object.
ALTER TABLE students
    ADD COLUMN IF NOT EXISTS profile_data JSONB NOT NULL DEFAULT '{}'::jsonb;

ALTER TABLE students
    DROP CONSTRAINT IF EXISTS students_profile_data_object_check;

ALTER TABLE students
    ADD CONSTRAINT students_profile_data_object_check
    CHECK (jsonb_typeof(profile_data) = 'object');
