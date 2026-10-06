-- F-07 — Normalisation canonique des rôles RBAC
-- Valeurs canoniques : PDG, Directeur, Enseignant, Secrétaire, Surveillant, Autre
-- Migration idempotente et non destructive : les FK role_permissions restent intactes.

BEGIN;

UPDATE roles
SET name = 'Enseignant',
    updated_at = NOW()
WHERE name = 'ENSEIGNANT'
  AND NOT EXISTS (
      SELECT 1 FROM roles WHERE name = 'Enseignant'
  );

DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM roles WHERE name = 'ENSEIGNANT') THEN
        RAISE EXCEPTION 'F-07: rôle legacy ENSEIGNANT encore présent après normalisation';
    END IF;
END $$;

ALTER TABLE roles
    DROP CONSTRAINT IF EXISTS roles_name_canonical_check;

ALTER TABLE roles
    ADD CONSTRAINT roles_name_canonical_check
    CHECK (name IN (
        'PDG',
        'Directeur',
        'Enseignant',
        'Secrétaire',
        'Surveillant',
        'Autre'
    ));

COMMIT;
