-- F-02-E — Personnel serveur PostgreSQL
-- Migration additive, non destructive.
BEGIN;

ALTER TABLE staff
    ADD COLUMN IF NOT EXISTS user_id UUID,
    ADD COLUMN IF NOT EXISTS class_name VARCHAR(150);

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint
        WHERE conname = 'staff_user_fk'
    ) THEN
        ALTER TABLE staff
            ADD CONSTRAINT staff_user_fk
            FOREIGN KEY (user_id)
            REFERENCES users(id)
            ON DELETE RESTRICT;
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint
        WHERE conname = 'staff_user_unique'
    ) THEN
        ALTER TABLE staff
            ADD CONSTRAINT staff_user_unique UNIQUE (user_id);
    END IF;
END $$;

CREATE INDEX IF NOT EXISTS idx_staff_status ON staff(status);
CREATE INDEX IF NOT EXISTS idx_staff_user ON staff(user_id);

CREATE TABLE IF NOT EXISTS staff_audit_log (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    actor_user_id UUID NOT NULL,
    staff_id UUID,
    action VARCHAR(30) NOT NULL,
    details JSONB NOT NULL DEFAULT '{}'::jsonb,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    CONSTRAINT staff_audit_actor_fk
        FOREIGN KEY (actor_user_id)
        REFERENCES users(id)
        ON DELETE RESTRICT,

    CONSTRAINT staff_audit_staff_fk
        FOREIGN KEY (staff_id)
        REFERENCES staff(id)
        ON DELETE SET NULL,

    CONSTRAINT staff_audit_action_check
        CHECK (action IN ('CREATE', 'UPDATE', 'ARCHIVE'))
);

CREATE INDEX IF NOT EXISTS idx_staff_audit_staff
    ON staff_audit_log(staff_id, created_at);

INSERT INTO permissions (name, description)
VALUES
    ('personnel.read', 'Consulter le personnel'),
    ('personnel.create', 'Créer un personnel'),
    ('personnel.update', 'Modifier un personnel'),
    ('personnel.delete', 'Archiver un personnel')
ON CONFLICT (name) DO NOTHING;

INSERT INTO role_permissions (role_id, permission_id)
SELECT r.id, p.id
FROM roles r
CROSS JOIN permissions p
WHERE r.name = 'PDG'
  AND p.name IN (
      'personnel.read',
      'personnel.create',
      'personnel.update',
      'personnel.delete'
  )
ON CONFLICT DO NOTHING;

INSERT INTO role_permissions (role_id, permission_id)
SELECT r.id, p.id
FROM roles r
CROSS JOIN permissions p
WHERE r.name IN ('Directeur', 'Secrétaire')
  AND p.name = 'personnel.read'
ON CONFLICT DO NOTHING;

COMMIT;
