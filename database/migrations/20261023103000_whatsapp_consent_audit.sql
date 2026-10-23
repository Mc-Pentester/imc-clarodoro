-- Append-only audit for changes to WhatsApp consent.
-- Apply only through the approved migration process.
CREATE TABLE IF NOT EXISTS whatsapp_consent_audit (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    consent_id UUID NOT NULL REFERENCES whatsapp_consents(id) ON DELETE RESTRICT,
    parent_id UUID NOT NULL REFERENCES parents(id) ON DELETE RESTRICT,
    purpose VARCHAR(40) NOT NULL CHECK (
        purpose IN ('ATTENDANCE', 'RESULTS_AVAILABLE', 'PAYMENT_REMINDER', 'GENERAL')
    ),
    previous_status VARCHAR(20) CHECK (
        previous_status IS NULL OR previous_status IN ('PENDING', 'OPTED_IN', 'OPTED_OUT')
    ),
    new_status VARCHAR(20) NOT NULL CHECK (
        new_status IN ('PENDING', 'OPTED_IN', 'OPTED_OUT')
    ),
    actor_user_id UUID NOT NULL REFERENCES users(id) ON DELETE RESTRICT,
    action_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_whatsapp_consent_audit_parent_time
    ON whatsapp_consent_audit(parent_id, action_at DESC);
