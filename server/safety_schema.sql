-- Additive PostgreSQL migration for member blocking and user reports.
-- Apply this file after taking the existing Nisa database backup and before
-- deploying the matching API main.py.

CREATE TABLE IF NOT EXISTS blocks (
    blocker_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    blocked_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    PRIMARY KEY (blocker_id, blocked_id),
    CHECK (blocker_id <> blocked_id)
);

CREATE INDEX IF NOT EXISTS idx_blocks_blocked_by
    ON blocks(blocked_id, blocker_id);

CREATE TABLE IF NOT EXISTS reports (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    -- Keep submitted IDs as snapshots so later account deletion cannot erase
    -- the identity references needed for moderation history.
    reporter_id TEXT NOT NULL,
    reported_user_id TEXT NOT NULL,
    reason TEXT NOT NULL CHECK (reason IN (
        'Inappropriate profile',
        'Fake or misleading information',
        'Harassment or disrespectful behavior',
        'Scam or suspicious activity',
        'Already married / dishonest status',
        'Other'
    )),
    details TEXT NOT NULL DEFAULT '',
    CHECK (char_length(details) <= 2000),
    CHECK (reason <> 'Other' OR char_length(details) >= 10),
    status TEXT NOT NULL DEFAULT 'pending'
        CHECK (status IN ('pending', 'reviewing', 'resolved', 'dismissed')),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    reviewed_at TIMESTAMPTZ,
    reviewed_by TEXT,
    CHECK (reporter_id <> reported_user_id)
);

CREATE INDEX IF NOT EXISTS idx_reports_review_queue
    ON reports(status, created_at);

CREATE INDEX IF NOT EXISTS idx_reports_target
    ON reports(reported_user_id, created_at);


-- Separate allow-list and audit trail for report moderation.
CREATE TABLE IF NOT EXISTS report_admins (
    user_id TEXT PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
    added_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    added_by TEXT
);

CREATE TABLE IF NOT EXISTS report_moderation_audit (
    id BIGSERIAL PRIMARY KEY,
    admin_user_id TEXT NOT NULL,
    report_id UUID REFERENCES reports(id) ON DELETE SET NULL,
    reporter_id TEXT,
    reported_user_id TEXT,
    action TEXT NOT NULL CHECK (action IN ('view_queue', 'view_report', 'set_reviewing', 'resolve', 'dismiss')),
    notes TEXT NOT NULL DEFAULT '' CHECK (char_length(notes) <= 2000),
    occurred_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_report_moderation_audit_report
    ON report_moderation_audit(report_id, occurred_at DESC);
