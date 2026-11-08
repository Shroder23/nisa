-- Additive policy and enforcement layer for moderation redesign.
-- Take a database backup before applying. Apply before the matching main.py.

-- Report reasons are user-facing values; triage categories remain internal.
DO $$
DECLARE c RECORD;
BEGIN
    FOR c IN
        SELECT conname FROM pg_constraint
        WHERE conrelid = 'public.reports'::regclass AND contype = 'c'
          AND pg_get_constraintdef(oid) ILIKE '%reason%'
          AND pg_get_constraintdef(oid) ILIKE '%Inappropriate profile%'
    LOOP
        EXECUTE format('ALTER TABLE public.reports DROP CONSTRAINT %I', c.conname);
    END LOOP;
END $$;

ALTER TABLE reports DROP CONSTRAINT IF EXISTS reports_reason_policy_check;
ALTER TABLE reports ADD CONSTRAINT reports_reason_policy_check CHECK (reason IN (
    'Spam', 'Inappropriate profile', 'Fake or misleading information',
    'Harassment or disrespectful behavior', 'Scam or suspicious activity',
    'Already married / dishonest status', 'Other'
));
ALTER TABLE reports DROP CONSTRAINT IF EXISTS reports_triage_category_check;
UPDATE reports SET triage_category = 'spam' WHERE reason = 'Spam';
ALTER TABLE reports ADD CONSTRAINT reports_triage_category_check CHECK
    (triage_category IN ('profile_content', 'identity_or_fraud', 'harassment', 'scam', 'marital_status', 'spam', 'other'));

ALTER TABLE verification_requests
    ADD COLUMN IF NOT EXISTS reviewer_gender_preference TEXT NOT NULL DEFAULT 'any';
ALTER TABLE verification_requests DROP CONSTRAINT IF EXISTS verification_requests_reviewer_gender_preference_check;
ALTER TABLE verification_requests ADD CONSTRAINT verification_requests_reviewer_gender_preference_check
    CHECK (reviewer_gender_preference IN ('male', 'female', 'any'));

-- Moderator gender is an explicitly assigned operational attribute, not inferred
-- from their member profile. It is used only for the verification preference and
-- permanent-ban recommendation quorum.
CREATE TABLE IF NOT EXISTS moderator_roles (
    user_id TEXT PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
    reviewer_gender TEXT CHECK (reviewer_gender IN ('male', 'female')),
    can_review_verification BOOLEAN NOT NULL DEFAULT FALSE,
    can_review_reports BOOLEAN NOT NULL DEFAULT FALSE,
    active BOOLEAN NOT NULL DEFAULT TRUE,
    added_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    added_by TEXT REFERENCES users(id) ON DELETE SET NULL
);

INSERT INTO moderator_roles (user_id, can_review_verification, can_review_reports)
SELECT user_id,
       EXISTS (SELECT 1 FROM verification_admins v WHERE v.user_id = src.user_id),
       EXISTS (SELECT 1 FROM report_admins r WHERE r.user_id = src.user_id)
FROM (
    SELECT user_id FROM verification_admins
    UNION
    SELECT user_id FROM report_admins
) src
ON CONFLICT (user_id) DO UPDATE SET
    can_review_verification = EXCLUDED.can_review_verification OR moderator_roles.can_review_verification,
    can_review_reports = EXCLUDED.can_review_reports OR moderator_roles.can_review_reports;

CREATE TABLE IF NOT EXISTS moderation_platform_admins (
    user_id TEXT PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
    added_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    added_by TEXT REFERENCES users(id) ON DELETE SET NULL
);

CREATE TABLE IF NOT EXISTS moderation_sanctions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    target_user_id TEXT NOT NULL REFERENCES users(id) ON DELETE RESTRICT,
    actor_user_id TEXT NOT NULL REFERENCES users(id) ON DELETE RESTRICT,
    sanction_type TEXT NOT NULL CHECK (sanction_type IN ('temporary_account_ban', 'pair_interaction_restriction')),
    other_user_id TEXT REFERENCES users(id) ON DELETE RESTRICT,
    report_id UUID REFERENCES reports(id) ON DELETE SET NULL,
    reason_code TEXT NOT NULL CHECK (char_length(reason_code) BETWEEN 2 AND 60),
    user_notice TEXT NOT NULL CHECK (char_length(user_notice) BETWEEN 10 AND 500),
    private_note TEXT NOT NULL DEFAULT '' CHECK (char_length(private_note) <= 2000),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    expires_at TIMESTAMPTZ NOT NULL,
    revoked_at TIMESTAMPTZ,
    revoked_by TEXT REFERENCES users(id) ON DELETE SET NULL,
    escalation_created BOOLEAN NOT NULL DEFAULT FALSE,
    CHECK (expires_at > created_at),
    CHECK ((sanction_type = 'temporary_account_ban' AND other_user_id IS NULL)
        OR (sanction_type = 'pair_interaction_restriction'
            AND other_user_id IS NOT NULL AND target_user_id <> other_user_id))
);

CREATE INDEX IF NOT EXISTS idx_moderation_sanctions_user_active
    ON moderation_sanctions(target_user_id, expires_at DESC)
    WHERE revoked_at IS NULL;
CREATE INDEX IF NOT EXISTS idx_moderation_sanctions_pair_active
    ON moderation_sanctions(target_user_id, other_user_id, expires_at DESC)
    WHERE sanction_type = 'pair_interaction_restriction' AND revoked_at IS NULL;

CREATE TABLE IF NOT EXISTS moderation_admin_cases (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    target_user_id TEXT NOT NULL REFERENCES users(id) ON DELETE RESTRICT,
    case_type TEXT NOT NULL CHECK (case_type IN ('third_temporary_ban', 'permanent_ban_proposal')),
    sanction_id UUID REFERENCES moderation_sanctions(id) ON DELETE SET NULL,
    proposal_id UUID,
    status TEXT NOT NULL DEFAULT 'pending'
        CHECK (status IN ('pending', 'upheld', 'reinstated', 'dismissed', 'account_deleted')),
    reason TEXT NOT NULL CHECK (char_length(reason) BETWEEN 10 AND 2000),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    reviewed_at TIMESTAMPTZ,
    reviewed_by TEXT REFERENCES users(id) ON DELETE SET NULL,
    decision_note TEXT NOT NULL DEFAULT '' CHECK (char_length(decision_note) <= 2000)
);
CREATE UNIQUE INDEX IF NOT EXISTS uq_moderation_admin_case_third_ban
    ON moderation_admin_cases(sanction_id) WHERE case_type = 'third_temporary_ban';
CREATE INDEX IF NOT EXISTS idx_moderation_admin_cases_queue
    ON moderation_admin_cases(status, created_at) WHERE status = 'pending';

CREATE TABLE IF NOT EXISTS permanent_ban_proposals (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    target_user_id TEXT NOT NULL REFERENCES users(id) ON DELETE RESTRICT,
    opened_by TEXT NOT NULL REFERENCES users(id) ON DELETE RESTRICT,
    report_id UUID REFERENCES reports(id) ON DELETE SET NULL,
    reason TEXT NOT NULL CHECK (char_length(reason) BETWEEN 20 AND 2000),
    status TEXT NOT NULL DEFAULT 'collecting'
        CHECK (status IN ('collecting', 'sent_to_admin', 'approved', 'rejected', 'withdrawn')),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    qualified_at TIMESTAMPTZ
);

CREATE TABLE IF NOT EXISTS permanent_ban_proposal_votes (
    proposal_id UUID NOT NULL REFERENCES permanent_ban_proposals(id) ON DELETE CASCADE,
    moderator_user_id TEXT NOT NULL REFERENCES users(id) ON DELETE RESTRICT,
    moderator_gender TEXT NOT NULL CHECK (moderator_gender IN ('male', 'female')),
    vote TEXT NOT NULL CHECK (vote IN ('support', 'withdraw')),
    reason TEXT NOT NULL CHECK (char_length(reason) BETWEEN 10 AND 1000),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    PRIMARY KEY (proposal_id, moderator_user_id)
);

ALTER TABLE moderation_admin_cases DROP CONSTRAINT IF EXISTS moderation_admin_cases_proposal_fk;
ALTER TABLE moderation_admin_cases
    ADD CONSTRAINT moderation_admin_cases_proposal_fk FOREIGN KEY (proposal_id)
    REFERENCES permanent_ban_proposals(id) ON DELETE SET NULL;

CREATE TABLE IF NOT EXISTS moderator_action_logs (
    id BIGSERIAL PRIMARY KEY,
    actor_user_id TEXT NOT NULL REFERENCES users(id) ON DELETE RESTRICT,
    target_user_id TEXT REFERENCES users(id) ON DELETE SET NULL,
    report_id UUID REFERENCES reports(id) ON DELETE SET NULL,
    sanction_id UUID REFERENCES moderation_sanctions(id) ON DELETE SET NULL,
    proposal_id UUID REFERENCES permanent_ban_proposals(id) ON DELETE SET NULL,
    event_type TEXT NOT NULL CHECK (char_length(event_type) BETWEEN 2 AND 64),
    reason TEXT NOT NULL DEFAULT '' CHECK (char_length(reason) <= 2000),
    metadata JSONB NOT NULL DEFAULT '{}'::jsonb,
    occurred_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_moderator_action_logs_time
    ON moderator_action_logs(occurred_at DESC);
CREATE INDEX IF NOT EXISTS idx_moderator_action_logs_target
    ON moderator_action_logs(target_user_id, occurred_at DESC);

CREATE OR REPLACE FUNCTION reject_moderator_action_log_mutation()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    RAISE EXCEPTION 'moderator_action_logs is append-only';
END;
$$;
DROP TRIGGER IF EXISTS moderator_action_logs_append_only ON moderator_action_logs;
CREATE TRIGGER moderator_action_logs_append_only
    BEFORE UPDATE OR DELETE ON moderator_action_logs
    FOR EACH ROW EXECUTE FUNCTION reject_moderator_action_log_mutation();

-- Store keyed digests, never raw email addresses or phone numbers, in this
-- re-registration denylist. Configure REGISTRATION_DENYLIST_HMAC_KEY securely.
CREATE TABLE IF NOT EXISTS registration_identifier_denylist (
    id BIGSERIAL PRIMARY KEY,
    identifier_type TEXT NOT NULL CHECK (identifier_type IN ('email', 'phone')),
    identifier_hmac TEXT NOT NULL CHECK (identifier_hmac ~ '^[0-9a-f]{64}$'),
    source_admin_case UUID REFERENCES moderation_admin_cases(id) ON DELETE SET NULL,
    added_by TEXT NOT NULL REFERENCES users(id) ON DELETE RESTRICT,
    reason TEXT NOT NULL CHECK (char_length(reason) BETWEEN 10 AND 1000),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE (identifier_type, identifier_hmac)
);

-- Keep the admin-case event and the decision log consistent; permanent actions
-- remain available only through the admin endpoint in the matching API patch.
