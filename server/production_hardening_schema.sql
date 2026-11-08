-- Atomic API request throttles and immediate access-token logout revocation.
-- Apply before deploying the matching main.py.
CREATE TABLE IF NOT EXISTS api_rate_limit_events (
    id BIGSERIAL PRIMARY KEY,
    scope TEXT NOT NULL CHECK (scope IN (
        'otp_request_ip', 'otp_request_email', 'otp_verify_ip', 'otp_verify_email',
        'verification_submit_user'
    )),
    subject_hash CHAR(64) NOT NULL,
    occurred_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_api_rate_limit_events_scope_subject_time
    ON api_rate_limit_events(scope, subject_hash, occurred_at DESC);

CREATE TABLE IF NOT EXISTS revoked_access_tokens (
    jti TEXT PRIMARY KEY,
    expires_at TIMESTAMPTZ NOT NULL,
    revoked_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_revoked_access_tokens_expires
    ON revoked_access_tokens(expires_at);
