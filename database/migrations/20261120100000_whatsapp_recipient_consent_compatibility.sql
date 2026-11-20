-- Extend generic WhatsApp consent records without losing legacy proof metadata.
-- Additive and idempotent. Never run automatically against a production database.
ALTER TABLE whatsapp_recipient_consents
    ADD COLUMN IF NOT EXISTS consent_method VARCHAR(24),
    ADD COLUMN IF NOT EXISTS consent_email VARCHAR(255),
    ADD COLUMN IF NOT EXISTS email_verified_at TIMESTAMPTZ,
    ADD COLUMN IF NOT EXISTS consent_text_version VARCHAR(40);

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'whatsapp_recipient_consents_method_check') THEN
        ALTER TABLE whatsapp_recipient_consents
            ADD CONSTRAINT whatsapp_recipient_consents_method_check
            CHECK (consent_method IS NULL OR consent_method IN ('PAPER', 'DIGITAL_EMAIL'));
    END IF;
END $$;

ALTER TABLE whatsapp_recipient_consents
    DROP CONSTRAINT IF EXISTS whatsapp_recipient_consents_status_timestamps;
ALTER TABLE whatsapp_recipient_consents
    ADD CONSTRAINT whatsapp_recipient_consents_status_timestamps CHECK (
        (status = 'OPTED_IN' AND consented_at IS NOT NULL AND revoked_at IS NULL)
        OR (status = 'OPTED_OUT' AND revoked_at IS NOT NULL)
        OR (status = 'PENDING' AND consented_at IS NULL AND revoked_at IS NULL)
    );

ALTER TABLE whatsapp_recipient_consent_audit
    ALTER COLUMN actor_user_id DROP NOT NULL,
    ADD COLUMN IF NOT EXISTS consent_method VARCHAR(24),
    ADD COLUMN IF NOT EXISTS evidence_reference VARCHAR(255),
    ADD COLUMN IF NOT EXISTS consent_email VARCHAR(255),
    ADD COLUMN IF NOT EXISTS consent_text_version VARCHAR(40),
    ADD COLUMN IF NOT EXISTS actor_type VARCHAR(24) NOT NULL DEFAULT 'SCHOOL_USER';

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint
        WHERE conname = 'whatsapp_recipient_consent_audit_actor_type_check'
    ) THEN
        ALTER TABLE whatsapp_recipient_consent_audit
            ADD CONSTRAINT whatsapp_recipient_consent_audit_actor_type_check
            CHECK (actor_type IN ('SCHOOL_USER', 'PARENT_EMAIL'));
    END IF;
END $$;

-- Backfill the generic parent read model from the authoritative legacy consent
-- rows, including proof method, verified email and original consent timestamps.
UPDATE whatsapp_recipient_consents generic
SET consent_method = legacy.consent_method,
    consent_email = legacy.consent_email,
    email_verified_at = legacy.email_verified_at,
    consent_text_version = legacy.consent_text_version,
    consent_source = legacy.consent_source,
    evidence_reference = legacy.evidence_reference,
    consented_at = legacy.consented_at,
    revoked_at = legacy.revoked_at,
    updated_at = GREATEST(generic.updated_at, legacy.updated_at)
FROM whatsapp_consents legacy
WHERE generic.recipient_type = 'PARENT'
  AND generic.parent_id = legacy.parent_id
  AND generic.purpose = legacy.purpose;
