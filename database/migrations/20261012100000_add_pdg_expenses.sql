-- Persist PDG expenses in PostgreSQL without touching legacy browser data.
-- Idempotent: safe to run repeatedly.
CREATE TABLE IF NOT EXISTS expenses (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    school_year_id UUID NOT NULL,
    description VARCHAR(500) NOT NULL,
    legacy_id VARCHAR(100),
    amount NUMERIC(12,2) NOT NULL,
    expense_date DATE NOT NULL,
    created_by UUID NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT expenses_description_not_blank CHECK (length(trim(description)) > 0),
    CONSTRAINT expenses_amount_positive CHECK (amount > 0),
    CONSTRAINT expenses_school_year_fk
        FOREIGN KEY (school_year_id) REFERENCES school_years(id) ON DELETE RESTRICT,
    CONSTRAINT expenses_created_by_fk
        FOREIGN KEY (created_by) REFERENCES users(id) ON DELETE RESTRICT
);

ALTER TABLE expenses ADD COLUMN IF NOT EXISTS legacy_id VARCHAR(100);

CREATE UNIQUE INDEX IF NOT EXISTS expenses_school_year_legacy_id_uidx
    ON expenses (school_year_id, legacy_id) WHERE legacy_id IS NOT NULL;

CREATE INDEX IF NOT EXISTS expenses_school_year_date_idx
    ON expenses (school_year_id, expense_date DESC, created_at DESC);

INSERT INTO permissions (name, description)
VALUES
    ('depenses.read', 'Consulter les dépenses de l’établissement'),
    ('depenses.create', 'Enregistrer une dépense de l’établissement'),
    ('depenses.delete', 'Supprimer une dépense de l’établissement')
ON CONFLICT (name) DO NOTHING;

INSERT INTO role_permissions (role_id, permission_id)
SELECT r.id, p.id
FROM roles r
CROSS JOIN permissions p
WHERE r.name = 'PDG'
  AND p.name IN ('depenses.read', 'depenses.create', 'depenses.delete')
ON CONFLICT (role_id, permission_id) DO NOTHING;
