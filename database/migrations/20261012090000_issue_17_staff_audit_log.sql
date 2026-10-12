-- Issue #17: additive, idempotent personnel audit trail.
-- No existing staff or user rows are modified or deleted.
CREATE TABLE IF NOT EXISTS staff_audit_log (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    actor_user_id UUID NOT NULL,
    staff_id UUID,
    action VARCHAR(20) NOT NULL,
    details JSONB NOT NULL DEFAULT '{}'::jsonb,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT staff_audit_log_action_check
        CHECK (action IN ('CREATE', 'UPDATE', 'ARCHIVE')),
    CONSTRAINT staff_audit_log_details_object_check
        CHECK (jsonb_typeof(details) = 'object'),
    CONSTRAINT staff_audit_log_actor_fk
        FOREIGN KEY (actor_user_id) REFERENCES users(id) ON DELETE RESTRICT,
    CONSTRAINT staff_audit_log_staff_fk
        FOREIGN KEY (staff_id) REFERENCES staff(id) ON DELETE RESTRICT
);

CREATE INDEX IF NOT EXISTS idx_staff_audit_log_staff_created
    ON staff_audit_log (staff_id, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_staff_audit_log_actor_created
    ON staff_audit_log (actor_user_id, created_at DESC);
