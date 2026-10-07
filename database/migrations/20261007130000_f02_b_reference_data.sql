-- F-02-B: server-authoritative academic reference data.
-- Non-destructive: creates only missing permissions/table/constraint/indexes.
INSERT INTO permissions (name, description)
VALUES
 ('annees.read','Lire les années scolaires'),
 ('annees.create','Créer une année scolaire'),
 ('annees.update','Modifier une année scolaire'),
 ('annees.delete','Archiver une année scolaire'),
 ('matieres.read','Lire les matières'),
 ('matieres.create','Créer une matière'),
 ('matieres.update','Modifier une matière'),
 ('matieres.delete','Archiver une matière'),
 ('vacances.read','Lire les périodes de vacances'),
 ('vacances.create','Créer une période de vacances'),
 ('vacances.update','Modifier une période de vacances'),
 ('vacances.delete','Archiver une période de vacances')
ON CONFLICT (name) DO NOTHING;

CREATE TABLE IF NOT EXISTS vacations (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name VARCHAR(150) NOT NULL,
    start_date DATE NOT NULL,
    end_date DATE NOT NULL,
    status VARCHAR(30) NOT NULL DEFAULT 'ACTIVE',
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT vacations_dates_check CHECK (end_date >= start_date),
    CONSTRAINT vacations_status_check CHECK (status IN ('ACTIVE','INACTIVE','ARCHIVED')),
    CONSTRAINT vacations_name_unique UNIQUE (name)
);

CREATE INDEX IF NOT EXISTS idx_vacations_status ON vacations(status);

-- Une seule année scolaire active à la fois.
CREATE UNIQUE INDEX IF NOT EXISTS school_years_one_active
    ON school_years ((status))
    WHERE status = 'ACTIVE';
