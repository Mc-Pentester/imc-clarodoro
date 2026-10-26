-- Audit log for manual WhatsApp preparations. Stores hashes, never message text or full phone.
CREATE TABLE IF NOT EXISTS whatsapp_manual_preparations (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    initiated_by UUID NOT NULL REFERENCES users(id) ON DELETE RESTRICT,
    parent_id UUID NOT NULL REFERENCES parents(id) ON DELETE RESTRICT,
    consent_id UUID NOT NULL REFERENCES whatsapp_consents(id) ON DELETE RESTRICT,
    purpose VARCHAR(40) NOT NULL CHECK (
        purpose IN ('ATTENDANCE', 'RESULTS_AVAILABLE', 'PAYMENT_REMINDER', 'GENERAL')
    ),
    phone_sha256 CHAR(64) NOT NULL,
    message_sha256 CHAR(64) NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_whatsapp_manual_preparations_actor_created
    ON whatsapp_manual_preparations(initiated_by, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_whatsapp_manual_preparations_parent_created
    ON whatsapp_manual_preparations(parent_id, created_at DESC);
