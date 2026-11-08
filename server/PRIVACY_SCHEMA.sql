-- Nisa privacy controls and independent recipient unread state.
-- Run once against the existing PostgreSQL database before restarting the API.

CREATE TABLE IF NOT EXISTS user_privacy_settings (
    user_id TEXT PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
    show_online_status BOOLEAN NOT NULL DEFAULT TRUE,
    share_read_receipts BOOLEAN NOT NULL DEFAULT TRUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS user_presence (
    user_id TEXT PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
    is_online BOOLEAN NOT NULL DEFAULT FALSE,
    last_seen_at TIMESTAMPTZ
);

-- Keep private unread state independent from read_at, which is visible to the
-- sender when the recipient allows read receipts.
ALTER TABLE messages
    ADD COLUMN IF NOT EXISTS recipient_read_at TIMESTAMPTZ;

-- Preserve existing read state for messages that were already read before this
-- migration. If a recipient later disables receipts, read_at can be cleared
-- without making these messages unread again.
UPDATE messages
SET recipient_read_at = read_at
WHERE recipient_read_at IS NULL
  AND read_at IS NOT NULL;
