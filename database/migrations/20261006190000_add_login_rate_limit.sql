-- F-05: persistent login rate limiting
CREATE TABLE IF NOT EXISTS auth_login_attempts (
    key_hash CHAR(64) PRIMARY KEY,
    failed_attempts INTEGER NOT NULL DEFAULT 0,
    first_failed_at TIMESTAMPTZ NOT NULL,
    blocked_until TIMESTAMPTZ NULL,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_auth_login_attempts_blocked_until
    ON auth_login_attempts (blocked_until);
