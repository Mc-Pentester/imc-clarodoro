-- IMC-CLARODORO
-- F-03: server-side user -> teacher scope
-- Non-destructive: creates only the missing relation and index.

CREATE TABLE IF NOT EXISTS user_teachers (
    user_id UUID PRIMARY KEY,
    teacher_id UUID NOT NULL,

    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    CONSTRAINT user_teachers_user_fk
        FOREIGN KEY (user_id)
        REFERENCES users(id)
        ON DELETE RESTRICT,

    CONSTRAINT user_teachers_teacher_fk
        FOREIGN KEY (teacher_id)
        REFERENCES teachers(id)
        ON DELETE RESTRICT
);

CREATE INDEX IF NOT EXISTS idx_user_teachers_teacher
    ON user_teachers(teacher_id);
