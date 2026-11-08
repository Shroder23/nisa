-- P0.3 session inventory and revocation.
-- Run after the existing auth schema and before deploying the matching main.py.

ALTER TABLE refresh_tokens
    ADD COLUMN IF NOT EXISTS session_id UUID,
    ADD COLUMN IF NOT EXISTS device_label TEXT,
    ADD COLUMN IF NOT EXISTS device_platform TEXT,
    ADD COLUMN IF NOT EXISTS session_created_at TIMESTAMPTZ,
    ADD COLUMN IF NOT EXISTS last_used_at TIMESTAMPTZ;

-- Existing active refresh tokens continue to work. Assign each existing token
-- chain a session identity so the first token refresh can keep it stable.
UPDATE refresh_tokens
SET session_id = COALESCE(session_id, gen_random_uuid()),
    device_label = COALESCE(NULLIF(device_label, ''), 'Existing device'),
    device_platform = COALESCE(NULLIF(device_platform, ''), 'unknown'),
    session_created_at = COALESCE(session_created_at, NOW()),
    last_used_at = COALESCE(last_used_at, NOW());

ALTER TABLE refresh_tokens
    ALTER COLUMN session_id SET NOT NULL,
    ALTER COLUMN device_label SET DEFAULT 'Unknown device',
    ALTER COLUMN device_platform SET DEFAULT 'unknown',
    ALTER COLUMN session_created_at SET DEFAULT NOW(),
    ALTER COLUMN session_created_at SET NOT NULL,
    ALTER COLUMN last_used_at SET DEFAULT NOW(),
    ALTER COLUMN last_used_at SET NOT NULL;

CREATE INDEX IF NOT EXISTS idx_refresh_tokens_user_session_active
    ON refresh_tokens (user_id, session_id, expires_at DESC)
    WHERE revoked_at IS NULL;

CREATE TABLE IF NOT EXISTS revoked_auth_sessions (
    session_id UUID PRIMARY KEY,
    user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    revoked_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_revoked_auth_sessions_user_time
    ON revoked_auth_sessions (user_id, revoked_at DESC);
