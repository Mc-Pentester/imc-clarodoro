-- Parent-facing digital consent by verified email + auditable paper consent metadata.
-- Additive only. Apply through the approved migration process; never auto-run.
ALTER TABLE whatsapp_consents
    ADD COLUMN IF NOT EXISTS consent_method VARCHAR(24),
    ADD COLUMN IF NOT EXISTS consent_email VARCHAR(255),
    ADD COLUMN IF NOT EXISTS email_verified_at TIMESTAMPTZ,
    ADD COLUMN IF NOT EXISTS consent_text_version VARCHAR(40);
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'whatsapp_consents_method_check') THEN
        ALTER TABLE whatsapp_consents ADD CONSTRAINT whatsapp_consents_method_check
        CHECK (consent_method IS NULL OR consent_method IN ('PAPER', 'DIGITAL_EMAIL'));
    END IF;
END $$;

ALTER TABLE whatsapp_consent_audit
    ADD COLUMN IF NOT EXISTS consent_method VARCHAR(24),
    ADD COLUMN IF NOT EXISTS evidence_reference VARCHAR(255),
    ADD COLUMN IF NOT EXISTS consent_email VARCHAR(255),
    ADD COLUMN IF NOT EXISTS consent_text_version VARCHAR(40),
    ADD COLUMN IF NOT EXISTS actor_type VARCHAR(24) NOT NULL DEFAULT 'SCHOOL_USER';
ALTER TABLE whatsapp_consent_audit ALTER COLUMN actor_user_id DROP NOT NULL;
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'whatsapp_consent_audit_actor_type_check') THEN
        ALTER TABLE whatsapp_consent_audit ADD CONSTRAINT whatsapp_consent_audit_actor_type_check
        CHECK (actor_type IN ('SCHOOL_USER', 'PARENT_EMAIL'));
    END IF;
END $$;

CREATE TABLE IF NOT EXISTS whatsapp_consent_email_challenges (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    parent_id UUID NOT NULL REFERENCES parents(id) ON DELETE RESTRICT,
    email VARCHAR(255) NOT NULL,
    invitation_token_hash CHAR(64) NOT NULL UNIQUE,
    verification_code_hash CHAR(64) NOT NULL,
    expires_at TIMESTAMPTZ NOT NULL,
    attempts SMALLINT NOT NULL DEFAULT 0 CHECK (attempts BETWEEN 0 AND 5),
    used_at TIMESTAMPTZ,
    initiated_by UUID NOT NULL REFERENCES users(id) ON DELETE RESTRICT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_whatsapp_consent_email_challenges_parent_created
    ON whatsapp_consent_email_challenges(parent_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_whatsapp_consent_email_challenges_expiry
    ON whatsapp_consent_email_challenges(expires_at) WHERE used_at IS NULL;
