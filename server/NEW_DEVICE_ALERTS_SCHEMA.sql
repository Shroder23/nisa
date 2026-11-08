-- P0.3: one-time new-install sign-in alert tracking.
-- The client sends a cryptographically random per-install ID; this table stores
-- only its SHA-256 digest. It is not a hardware identifier or location record.

CREATE TABLE IF NOT EXISTS known_auth_devices (
    user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    device_key_hash CHAR(64) NOT NULL
        CHECK (device_key_hash ~ '^[0-9a-f]{64}$'),
    device_label TEXT NOT NULL DEFAULT 'Unknown device',
    device_platform TEXT NOT NULL DEFAULT 'unknown',
    first_seen_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    last_seen_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    PRIMARY KEY (user_id, device_key_hash)
);

CREATE INDEX IF NOT EXISTS idx_known_auth_devices_user_last_seen
    ON known_auth_devices (user_id, last_seen_at DESC);
