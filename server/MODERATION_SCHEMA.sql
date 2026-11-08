-- Additive, repeatable P0.4 report operations migration.
-- Apply after the P0.2 privacy and P0.3 session migrations.

ALTER TABLE reports
    ADD COLUMN IF NOT EXISTS triage_category TEXT,
    ADD COLUMN IF NOT EXISTS priority SMALLINT,
    ADD COLUMN IF NOT EXISTS updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    ADD COLUMN IF NOT EXISTS outcome_code TEXT,
    ADD COLUMN IF NOT EXISTS appeal_status TEXT NOT NULL DEFAULT 'none',
    ADD COLUMN IF NOT EXISTS appeal_details TEXT NOT NULL DEFAULT '',
    ADD COLUMN IF NOT EXISTS appeal_submitted_at TIMESTAMPTZ,
    ADD COLUMN IF NOT EXISTS appeal_reviewed_at TIMESTAMPTZ,
    ADD COLUMN IF NOT EXISTS appeal_reviewed_by TEXT,
    ADD COLUMN IF NOT EXISTS evidence_expires_at TIMESTAMPTZ,
    ADD COLUMN IF NOT EXISTS evidence_redacted_at TIMESTAMPTZ;

UPDATE reports
SET triage_category = CASE reason
        WHEN 'Inappropriate profile' THEN 'profile_content'
        WHEN 'Fake or misleading information' THEN 'identity_or_fraud'
        WHEN 'Harassment or disrespectful behavior' THEN 'harassment'
        WHEN 'Scam or suspicious activity' THEN 'scam'
        WHEN 'Already married / dishonest status' THEN 'marital_status'
        ELSE 'other'
    END
WHERE triage_category IS NULL;

UPDATE reports
SET priority = CASE
        WHEN reason IN ('Harassment or disrespectful behavior', 'Scam or suspicious activity') THEN 3
        ELSE 2
    END
WHERE priority IS NULL;

ALTER TABLE reports
    ALTER COLUMN triage_category SET DEFAULT 'other',
    ALTER COLUMN triage_category SET NOT NULL,
    ALTER COLUMN priority SET DEFAULT 2,
    ALTER COLUMN priority SET NOT NULL;

UPDATE reports
SET evidence_expires_at = reviewed_at + INTERVAL '180 days'
WHERE status IN ('resolved', 'dismissed')
  AND reviewed_at IS NOT NULL
  AND evidence_expires_at IS NULL;

ALTER TABLE reports DROP CONSTRAINT IF EXISTS reports_triage_category_check;
ALTER TABLE reports ADD CONSTRAINT reports_triage_category_check
    CHECK (triage_category IN ('profile_content', 'identity_or_fraud', 'harassment', 'scam', 'marital_status', 'other'));

ALTER TABLE reports DROP CONSTRAINT IF EXISTS reports_priority_check;
ALTER TABLE reports ADD CONSTRAINT reports_priority_check CHECK (priority BETWEEN 1 AND 3);

ALTER TABLE reports DROP CONSTRAINT IF EXISTS reports_appeal_status_check;
ALTER TABLE reports ADD CONSTRAINT reports_appeal_status_check
    CHECK (appeal_status IN ('none', 'pending', 'accepted', 'rejected'));

-- The original migration requires details for "Other". Permit those details
-- to be erased after the documented evidence-retention period.
DO $$
DECLARE c RECORD;
BEGIN
    FOR c IN
        SELECT conname
        FROM pg_constraint
        WHERE conrelid = 'public.reports'::regclass
          AND contype = 'c'
          AND pg_get_constraintdef(oid) ILIKE '%reason%'
          AND pg_get_constraintdef(oid) ILIKE '%char_length(details)%'
          AND pg_get_constraintdef(oid) ILIKE '%>=%'
    LOOP
        EXECUTE format('ALTER TABLE public.reports DROP CONSTRAINT %I', c.conname);
    END LOOP;
END $$;

ALTER TABLE reports DROP CONSTRAINT IF EXISTS reports_other_details_min_len;
ALTER TABLE reports ADD CONSTRAINT reports_other_details_min_len
    CHECK (reason <> 'Other' OR char_length(details) >= 10 OR evidence_redacted_at IS NOT NULL);

-- Keep the action audit append-only while expanding the event vocabulary.
DO $$
DECLARE c RECORD;
BEGIN
    FOR c IN
        SELECT conname
        FROM pg_constraint
        WHERE conrelid = 'public.report_moderation_audit'::regclass
          AND contype = 'c'
          AND pg_get_constraintdef(oid) ILIKE '%action%'
    LOOP
        EXECUTE format('ALTER TABLE public.report_moderation_audit DROP CONSTRAINT %I', c.conname);
    END LOOP;
END $$;

ALTER TABLE report_moderation_audit
    ADD COLUMN IF NOT EXISTS metadata JSONB NOT NULL DEFAULT '{}'::jsonb;

ALTER TABLE report_moderation_audit
    ALTER COLUMN admin_user_id DROP NOT NULL,
    ADD COLUMN IF NOT EXISTS actor_type TEXT NOT NULL DEFAULT 'moderator',
    ADD COLUMN IF NOT EXISTS actor_user_id TEXT;

ALTER TABLE report_moderation_audit DROP CONSTRAINT IF EXISTS report_moderation_audit_action_check;
ALTER TABLE report_moderation_audit ADD CONSTRAINT report_moderation_audit_action_check
    CHECK (action IN (
        'view_queue', 'view_report', 'report_submitted', 'set_reviewing', 'resolve', 'dismiss',
        'appeal_submitted', 'appeal_accepted', 'appeal_rejected',
        'retention_redact', 'triage_updated'
    ));

CREATE INDEX IF NOT EXISTS idx_reports_moderation_priority_queue
    ON reports (status, priority DESC, created_at ASC)
    WHERE status IN ('pending', 'reviewing');

CREATE INDEX IF NOT EXISTS idx_reports_pending_appeals
    ON reports (appeal_submitted_at ASC)
    WHERE appeal_status = 'pending';

CREATE INDEX IF NOT EXISTS idx_reports_evidence_retention
    ON reports (evidence_expires_at)
    WHERE evidence_expires_at IS NOT NULL AND evidence_redacted_at IS NULL;
