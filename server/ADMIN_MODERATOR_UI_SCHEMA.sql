-- Incremental schema for the admin/moderator profile-tab redesign.
-- Apply once before deploying the matching server_patch/main.py.
ALTER TABLE permanent_ban_proposals
    ADD COLUMN IF NOT EXISTS witness_user_id TEXT REFERENCES users(id) ON DELETE SET NULL,
    ADD COLUMN IF NOT EXISTS witness_invited_at TIMESTAMPTZ;
CREATE INDEX IF NOT EXISTS idx_permanent_ban_proposals_witness
    ON permanent_ban_proposals(witness_user_id, status)
    WHERE witness_user_id IS NOT NULL;

CREATE TABLE IF NOT EXISTS moderation_recommendations (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    submitted_by TEXT NOT NULL REFERENCES users(id) ON DELETE RESTRICT,
    category TEXT NOT NULL CHECK (category IN ('security', 'member_safety', 'verification', 'workflow', 'other')),
    title TEXT NOT NULL CHECK (char_length(title) BETWEEN 5 AND 140),
    details TEXT NOT NULL CHECK (char_length(details) BETWEEN 10 AND 2000),
    status TEXT NOT NULL DEFAULT 'new' CHECK (status IN ('new', 'reviewing', 'planned', 'declined', 'completed')),
    admin_note TEXT NOT NULL DEFAULT '' CHECK (char_length(admin_note) <= 2000),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    reviewed_by TEXT REFERENCES users(id) ON DELETE SET NULL
);
CREATE INDEX IF NOT EXISTS idx_moderation_recommendations_queue
    ON moderation_recommendations(status, created_at DESC);

-- Records administrator overrides without mutating append-only moderator logs.
CREATE TABLE IF NOT EXISTS moderation_decision_overrides (
    id BIGSERIAL PRIMARY KEY,
    original_log_id BIGINT NOT NULL UNIQUE
        REFERENCES moderator_action_logs(id) ON DELETE RESTRICT,
    overridden_by TEXT NOT NULL REFERENCES users(id) ON DELETE RESTRICT,
    target_user_id TEXT REFERENCES users(id) ON DELETE SET NULL,
    override_type TEXT NOT NULL CHECK (override_type IN (
        'reopen_report', 'revoke_verification_approval'
    )),
    reason TEXT NOT NULL CHECK (char_length(reason) BETWEEN 10 AND 1000),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_moderation_decision_overrides_target
    ON moderation_decision_overrides(target_user_id, created_at DESC);

-- Admin account directory and its append-only access/action audit.
-- Phone is nullable: this app currently has no phone registration flow, so
-- existing accounts will only be searchable by phone after a trusted source
-- populates it.
ALTER TABLE users ADD COLUMN IF NOT EXISTS phone_number TEXT;
CREATE INDEX IF NOT EXISTS idx_users_phone_number_digits
    ON users ((regexp_replace(COALESCE(phone_number, ''), '[^0-9]', '', 'g')))
    WHERE phone_number IS NOT NULL;

CREATE TABLE IF NOT EXISTS admin_user_management_audit (
    id BIGSERIAL PRIMARY KEY,
    actor_user_id TEXT NOT NULL REFERENCES users(id) ON DELETE RESTRICT,
    target_user_id TEXT,
    action TEXT NOT NULL CHECK (char_length(action) BETWEEN 2 AND 64),
    reason TEXT NOT NULL DEFAULT '' CHECK (char_length(reason) <= 1000),
    metadata JSONB NOT NULL DEFAULT '{}'::jsonb,
    occurred_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_admin_user_management_audit_target
    ON admin_user_management_audit(target_user_id, occurred_at DESC);
CREATE INDEX IF NOT EXISTS idx_admin_user_management_audit_actor
    ON admin_user_management_audit(actor_user_id, occurred_at DESC);

CREATE OR REPLACE FUNCTION reject_admin_user_management_audit_mutation()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    RAISE EXCEPTION 'admin user management audit is append-only';
END;
$$;
DROP TRIGGER IF EXISTS admin_user_management_audit_append_only
    ON admin_user_management_audit;
CREATE TRIGGER admin_user_management_audit_append_only
    BEFORE UPDATE OR DELETE ON admin_user_management_audit
    FOR EACH ROW EXECUTE FUNCTION reject_admin_user_management_audit_mutation();
