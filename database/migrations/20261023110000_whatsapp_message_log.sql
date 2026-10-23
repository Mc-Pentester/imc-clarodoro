-- Outbound WhatsApp audit/idempotency table. Additive only; never auto-run.
CREATE TABLE IF NOT EXISTS whatsapp_message_log (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    consent_id UUID NOT NULL REFERENCES whatsapp_consents(id) ON DELETE RESTRICT,
    idempotency_key VARCHAR(120) NOT NULL UNIQUE,
    purpose VARCHAR(40) NOT NULL CHECK (
        purpose IN ('ATTENDANCE', 'RESULTS_AVAILABLE', 'PAYMENT_REMINDER', 'GENERAL')
    ),
    status VARCHAR(20) NOT NULL CHECK (
        status IN ('SIMULATED', 'PROCESSING', 'SENT', 'FAILED')
    ),
    template_name VARCHAR(128) NOT NULL,
    payload_sha256 CHAR(64) NOT NULL,
    provider_message_id VARCHAR(255),
    provider_error_code VARCHAR(80),
    initiated_by UUID NOT NULL REFERENCES users(id) ON DELETE RESTRICT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_whatsapp_message_log_status_created
    ON whatsapp_message_log(status, created_at DESC);
