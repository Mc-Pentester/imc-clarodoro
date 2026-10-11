-- Persist generated student badges in PostgreSQL.
-- Non-destructive and idempotent.
CREATE TABLE IF NOT EXISTS student_badges (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    student_id UUID NOT NULL,
    created_by UUID NOT NULL,
    badge_data JSONB NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT student_badges_student_fk
        FOREIGN KEY (student_id) REFERENCES students(id) ON DELETE RESTRICT,
    CONSTRAINT student_badges_created_by_fk
        FOREIGN KEY (created_by) REFERENCES users(id) ON DELETE RESTRICT,
    CONSTRAINT student_badges_data_object_check
        CHECK (jsonb_typeof(badge_data) = 'object')
);

CREATE INDEX IF NOT EXISTS student_badges_student_created_idx
    ON student_badges (student_id, created_at DESC);

INSERT INTO permissions (name, description)
VALUES ('badge.create', 'Enregistrer un badge élève côté serveur')
ON CONFLICT (name) DO NOTHING;

INSERT INTO role_permissions (role_id, permission_id)
SELECT r.id, p.id
FROM roles r
CROSS JOIN permissions p
WHERE r.name IN ('PDG', 'Directeur')
  AND p.name = 'badge.create'
ON CONFLICT (role_id, permission_id) DO NOTHING;
