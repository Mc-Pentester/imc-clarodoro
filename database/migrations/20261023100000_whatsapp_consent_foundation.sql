-- WhatsApp consent foundation. Not executed automatically.
-- Consent is purpose-specific; is_primary on student_parents is not consent.
CREATE TABLE IF NOT EXISTS whatsapp_consents (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    parent_id UUID NOT NULL REFERENCES parents(id) ON DELETE RESTRICT,
    purpose VARCHAR(40) NOT NULL CHECK (
        purpose IN ('ATTENDANCE', 'RESULTS_AVAILABLE', 'PAYMENT_REMINDER', 'GENERAL')
    ),
    phone_e164 VARCHAR(20) NOT NULL CHECK (phone_e164 ~ E'^\\+[1-9][0-9]{7,14}$'),
    status VARCHAR(20) NOT NULL DEFAULT 'PENDING' CHECK (
        status IN ('PENDING', 'OPTED_IN', 'OPTED_OUT')
    ),
    consent_source VARCHAR(255),
    evidence_reference VARCHAR(255),
    consented_at TIMESTAMPTZ,
    revoked_at TIMESTAMPTZ,
    created_by UUID REFERENCES users(id) ON DELETE RESTRICT,
    updated_by UUID REFERENCES users(id) ON DELETE RESTRICT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT whatsapp_consents_parent_purpose_unique UNIQUE (parent_id, purpose),
    CONSTRAINT whatsapp_consents_status_timestamps CHECK (
        (status = 'OPTED_IN' AND consented_at IS NOT NULL AND revoked_at IS NULL)
        OR (status = 'OPTED_OUT' AND revoked_at IS NOT NULL)
        OR (status = 'PENDING' AND consented_at IS NULL AND revoked_at IS NULL)
    )
);
CREATE INDEX IF NOT EXISTS idx_whatsapp_consents_status_purpose
    ON whatsapp_consents(status, purpose);

INSERT INTO permissions (name, description)
VALUES
    ('whatsapp.consent.read', 'Consulter les consentements WhatsApp'),
    ('whatsapp.consent.manage', 'Enregistrer ou retirer un consentement WhatsApp'),
    ('whatsapp.message.send', 'Envoyer un modèle WhatsApp autorisé')
ON CONFLICT (name) DO NOTHING;
