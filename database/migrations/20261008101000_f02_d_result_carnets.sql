-- F-02-D: server-authoritative report-card notes.
-- Non-destructive and idempotent.

CREATE TABLE IF NOT EXISTS result_carnets (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    enrollment_id UUID NOT NULL UNIQUE,
    proprete TEXT,
    conduite TEXT,
    tenue_materiels TEXT,
    retard TEXT,
    absence TEXT,
    classe_promotion TEXT,
    classe_refait TEXT,
    eleve_remis TEXT,
    observation1 TEXT,
    observation2 TEXT,
    observation3 TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT result_carnets_enrollment_fk
        FOREIGN KEY (enrollment_id)
        REFERENCES enrollments(id)
        ON DELETE RESTRICT
);
