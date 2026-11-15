-- Clarodaro WhatsApp: consentements individuels multi-destinataires.
-- Migration additive: conserve whatsapp_consents et son historique existant.
-- À appliquer uniquement par le processus de migration approuvé.
BEGIN;

CREATE TABLE IF NOT EXISTS whatsapp_recipient_consents (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    recipient_type VARCHAR(20) NOT NULL
        CHECK (recipient_type IN ('PARENT', 'STUDENT', 'STAFF', 'TEACHER')),
    parent_id UUID REFERENCES parents(id) ON DELETE RESTRICT,
    student_id UUID REFERENCES students(id) ON DELETE RESTRICT,
    staff_id UUID REFERENCES staff(id) ON DELETE RESTRICT,
    teacher_id UUID REFERENCES teachers(id) ON DELETE RESTRICT,
    purpose VARCHAR(40) NOT NULL
        CHECK (purpose IN ('ATTENDANCE', 'RESULTS_AVAILABLE', 'PAYMENT_REMINDER', 'GENERAL')),
    phone_e164 VARCHAR(20) NOT NULL
        CHECK (phone_e164 ~ E'^\\+[1-9][0-9]{7,14}$'),
    status VARCHAR(20) NOT NULL DEFAULT 'PENDING'
        CHECK (status IN ('PENDING', 'OPTED_IN', 'OPTED_OUT')),
    consent_source VARCHAR(255),
    evidence_reference VARCHAR(255),
    consented_at TIMESTAMPTZ,
    revoked_at TIMESTAMPTZ,
    created_by UUID REFERENCES users(id) ON DELETE RESTRICT,
    updated_by UUID REFERENCES users(id) ON DELETE RESTRICT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT whatsapp_recipient_consents_exact_owner CHECK (
        (recipient_type = 'PARENT' AND parent_id IS NOT NULL AND student_id IS NULL AND staff_id IS NULL AND teacher_id IS NULL)
        OR (recipient_type = 'STUDENT' AND parent_id IS NULL AND student_id IS NOT NULL AND staff_id IS NULL AND teacher_id IS NULL)
        OR (recipient_type = 'STAFF' AND parent_id IS NULL AND student_id IS NULL AND staff_id IS NOT NULL AND teacher_id IS NULL)
        OR (recipient_type = 'TEACHER' AND parent_id IS NULL AND student_id IS NULL AND staff_id IS NULL AND teacher_id IS NOT NULL)
    ),
    CONSTRAINT whatsapp_recipient_consents_status_timestamps CHECK (
        (status = 'OPTED_IN' AND consented_at IS NOT NULL AND revoked_at IS NULL)
        OR (status = 'OPTED_OUT' AND consented_at IS NULL AND revoked_at IS NOT NULL)
        OR (status = 'PENDING' AND consented_at IS NULL AND revoked_at IS NULL)
    )
);

CREATE UNIQUE INDEX IF NOT EXISTS whatsapp_recipient_parent_purpose_unique
    ON whatsapp_recipient_consents(parent_id, purpose) WHERE recipient_type = 'PARENT';
CREATE UNIQUE INDEX IF NOT EXISTS whatsapp_recipient_student_purpose_unique
    ON whatsapp_recipient_consents(student_id, purpose) WHERE recipient_type = 'STUDENT';
CREATE UNIQUE INDEX IF NOT EXISTS whatsapp_recipient_staff_purpose_unique
    ON whatsapp_recipient_consents(staff_id, purpose) WHERE recipient_type = 'STAFF';
CREATE UNIQUE INDEX IF NOT EXISTS whatsapp_recipient_teacher_purpose_unique
    ON whatsapp_recipient_consents(teacher_id, purpose) WHERE recipient_type = 'TEACHER';
CREATE INDEX IF NOT EXISTS idx_whatsapp_recipient_consents_active
    ON whatsapp_recipient_consents(recipient_type, purpose, status);

-- Reprise exacte de l'état actuel des consentements parents : aucune suppression
-- ni modification de whatsapp_consents ou de whatsapp_consent_audit.
INSERT INTO whatsapp_recipient_consents
    (recipient_type, parent_id, purpose, phone_e164, status, consent_source,
     evidence_reference, consented_at, revoked_at, created_by, updated_by,
     created_at, updated_at)
SELECT 'PARENT', parent_id, purpose, phone_e164, status, consent_source,
       evidence_reference, consented_at, revoked_at, created_by, updated_by,
       created_at, updated_at
FROM whatsapp_consents
ON CONFLICT DO NOTHING;

CREATE TABLE IF NOT EXISTS whatsapp_recipient_consent_audit (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    consent_id UUID NOT NULL REFERENCES whatsapp_recipient_consents(id) ON DELETE RESTRICT,
    recipient_type VARCHAR(20) NOT NULL
        CHECK (recipient_type IN ('PARENT', 'STUDENT', 'STAFF', 'TEACHER')),
    previous_status VARCHAR(20)
        CHECK (previous_status IS NULL OR previous_status IN ('PENDING', 'OPTED_IN', 'OPTED_OUT')),
    new_status VARCHAR(20) NOT NULL
        CHECK (new_status IN ('PENDING', 'OPTED_IN', 'OPTED_OUT')),
    actor_user_id UUID NOT NULL REFERENCES users(id) ON DELETE RESTRICT,
    action_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_whatsapp_recipient_consent_audit_time
    ON whatsapp_recipient_consent_audit(consent_id, action_at DESC);

CREATE OR REPLACE FUNCTION prevent_whatsapp_recipient_consent_audit_mutation()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    RAISE EXCEPTION 'whatsapp_recipient_consent_audit is append-only';
END;
$$;
DROP TRIGGER IF EXISTS whatsapp_recipient_consent_audit_no_mutation
    ON whatsapp_recipient_consent_audit;
CREATE TRIGGER whatsapp_recipient_consent_audit_no_mutation
    BEFORE UPDATE OR DELETE ON whatsapp_recipient_consent_audit
    FOR EACH ROW EXECUTE FUNCTION prevent_whatsapp_recipient_consent_audit_mutation();
DROP TRIGGER IF EXISTS whatsapp_recipient_consent_audit_no_truncate
    ON whatsapp_recipient_consent_audit;
CREATE TRIGGER whatsapp_recipient_consent_audit_no_truncate
    BEFORE TRUNCATE ON whatsapp_recipient_consent_audit
    FOR EACH STATEMENT EXECUTE FUNCTION prevent_whatsapp_recipient_consent_audit_mutation();

CREATE TABLE IF NOT EXISTS whatsapp_recipient_message_log (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    consent_id UUID NOT NULL REFERENCES whatsapp_recipient_consents(id) ON DELETE RESTRICT,
    idempotency_key VARCHAR(120) NOT NULL UNIQUE,
    purpose VARCHAR(40) NOT NULL
        CHECK (purpose IN ('ATTENDANCE', 'RESULTS_AVAILABLE', 'PAYMENT_REMINDER', 'GENERAL')),
    status VARCHAR(20) NOT NULL
        CHECK (status IN ('PROCESSING', 'SENT', 'FAILED')),
    template_name VARCHAR(128) NOT NULL,
    payload_sha256 CHAR(64) NOT NULL,
    provider_message_id VARCHAR(255),
    provider_error_code VARCHAR(80),
    initiated_by UUID NOT NULL REFERENCES users(id) ON DELETE RESTRICT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_whatsapp_recipient_message_log_status
    ON whatsapp_recipient_message_log(status, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_whatsapp_recipient_message_provider
    ON whatsapp_recipient_message_log(provider_message_id)
    WHERE provider_message_id IS NOT NULL;

-- Delivery receipts arrive asynchronously from Meta after the initial API response.
ALTER TABLE whatsapp_recipient_message_log
    DROP CONSTRAINT IF EXISTS whatsapp_recipient_message_log_status_check;
ALTER TABLE whatsapp_recipient_message_log
    ADD CONSTRAINT whatsapp_recipient_message_log_status_check
    CHECK (status IN ('PROCESSING', 'SENT', 'DELIVERED', 'READ', 'FAILED'));

CREATE TABLE IF NOT EXISTS whatsapp_webhook_events (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    provider_message_id VARCHAR(255) NOT NULL,
    provider_status VARCHAR(20) NOT NULL
        CHECK (provider_status IN ('SENT', 'DELIVERED', 'READ', 'FAILED')),
    provider_timestamp TIMESTAMPTZ NOT NULL,
    provider_error_code VARCHAR(80),
    payload_sha256 CHAR(64) NOT NULL,
    received_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT whatsapp_webhook_event_unique
        UNIQUE (provider_message_id, provider_status, provider_timestamp)
);
CREATE INDEX IF NOT EXISTS idx_whatsapp_webhook_events_message
    ON whatsapp_webhook_events(provider_message_id, provider_timestamp DESC);

CREATE OR REPLACE FUNCTION prevent_whatsapp_webhook_event_mutation()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    RAISE EXCEPTION 'whatsapp_webhook_events is append-only';
END;
$$;
DROP TRIGGER IF EXISTS whatsapp_webhook_events_no_mutation ON whatsapp_webhook_events;
CREATE TRIGGER whatsapp_webhook_events_no_mutation
    BEFORE UPDATE OR DELETE ON whatsapp_webhook_events
    FOR EACH ROW EXECUTE FUNCTION prevent_whatsapp_webhook_event_mutation();
DROP TRIGGER IF EXISTS whatsapp_webhook_events_no_truncate ON whatsapp_webhook_events;
CREATE TRIGGER whatsapp_webhook_events_no_truncate
    BEFORE TRUNCATE ON whatsapp_webhook_events
    FOR EACH STATEMENT EXECUTE FUNCTION prevent_whatsapp_webhook_event_mutation();

INSERT INTO permissions (name, description)
VALUES
    ('whatsapp.recipient.read', 'Consulter les destinataires et consentements WhatsApp'),
    ('whatsapp.recipient.manage', 'Gérer les consentements WhatsApp des parents, élèves et personnel'),
    ('whatsapp.message.audit', 'Consulter les résultats des envois WhatsApp')
ON CONFLICT (name) DO NOTHING;

-- Donner la lecture des fiches de destinataires aux rôles qui ont déjà
-- le droit d'initier un envoi. La gestion des consentements reste distincte
-- et n'est pas accordée automatiquement.
INSERT INTO role_permissions (role_id, permission_id)
SELECT rp.role_id, p_read.id
FROM role_permissions rp
INNER JOIN permissions p_send ON p_send.id = rp.permission_id AND p_send.name = 'whatsapp.message.send'
INNER JOIN permissions p_read ON p_read.name = 'whatsapp.recipient.read'
ON CONFLICT DO NOTHING;

-- Maintenir le contrat PDG : le rôle propriétaire reçoit toutes les permissions
-- explicitement créées par cette migration. Les autres rôles ne reçoivent que
-- whatsapp.recipient.read s'ils possédaient déjà whatsapp.message.send.
INSERT INTO role_permissions (role_id, permission_id)
SELECT r.id, p.id
FROM roles r
CROSS JOIN permissions p
WHERE r.name = 'PDG'
  AND p.name IN ('whatsapp.recipient.read', 'whatsapp.recipient.manage', 'whatsapp.message.audit')
ON CONFLICT DO NOTHING;

COMMIT;
