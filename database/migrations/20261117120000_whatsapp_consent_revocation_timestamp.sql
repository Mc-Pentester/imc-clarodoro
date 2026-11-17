-- Preserve the original consent timestamp when an existing consent is revoked.
-- Additive and safe for existing rows; no consent records are deleted or rewritten.
ALTER TABLE whatsapp_consents
    DROP CONSTRAINT IF EXISTS whatsapp_consents_status_timestamps;

ALTER TABLE whatsapp_consents
    ADD CONSTRAINT whatsapp_consents_status_timestamps CHECK (
        (status = 'OPTED_IN' AND consented_at IS NOT NULL AND revoked_at IS NULL)
        OR (status = 'OPTED_OUT' AND revoked_at IS NOT NULL)
        OR (status = 'PENDING' AND consented_at IS NULL AND revoked_at IS NULL)
    );
