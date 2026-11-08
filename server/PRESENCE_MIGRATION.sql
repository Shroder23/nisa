-- Online / last-seen state for API messaging. Safe to run more than once.
ALTER TABLE users
    ADD COLUMN IF NOT EXISTS is_online BOOLEAN NOT NULL DEFAULT FALSE;

ALTER TABLE users
    ADD COLUMN IF NOT EXISTS last_seen_at TIMESTAMPTZ;

CREATE INDEX IF NOT EXISTS users_last_seen_at_idx
    ON users (last_seen_at);
