-- Private parent/guardian verification requests and reviewer access controls.
-- Apply before deploying the matching API code.

CREATE TABLE IF NOT EXISTS verification_admins (
    user_id TEXT PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
    added_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    added_by TEXT
);

CREATE TABLE IF NOT EXISTS verification_requests (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    guardian_name TEXT NOT NULL CHECK (char_length(guardian_name) BETWEEN 1 AND 120),
    guardian_relationship TEXT NOT NULL CHECK (guardian_relationship IN ('mother', 'father', 'wali')),
    guardian_id_file TEXT,
    authority_proof_file TEXT,
    confirmation_video_file TEXT,
    video_duration_seconds NUMERIC(5,2) NOT NULL CHECK (video_duration_seconds BETWEEN 10 AND 30),
    consent_confirmed_at TIMESTAMPTZ NOT NULL,
    status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN (
        'pending', 'approved', 'rejected', 'resubmission_required'
    )),
    submitted_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    reviewed_at TIMESTAMPTZ,
    reviewed_by TEXT,
    reviewer_notes TEXT,
    rejection_reason TEXT,
    CHECK (
        (status = 'pending'
            AND guardian_id_file IS NOT NULL
            AND confirmation_video_file IS NOT NULL
            AND ((guardian_relationship = 'wali' AND authority_proof_file IS NOT NULL)
                OR (guardian_relationship IN ('mother', 'father') AND authority_proof_file IS NULL)))
        OR (status <> 'pending'
            AND guardian_id_file IS NULL
            AND confirmation_video_file IS NULL
            AND authority_proof_file IS NULL)
    )
);

CREATE UNIQUE INDEX IF NOT EXISTS uq_verification_request_pending_user
    ON verification_requests(user_id) WHERE status = 'pending';

CREATE INDEX IF NOT EXISTS idx_verification_requests_review_queue
    ON verification_requests(status, submitted_at);

CREATE TABLE IF NOT EXISTS verification_admin_audit (
    id BIGSERIAL PRIMARY KEY,
    admin_user_id TEXT NOT NULL,
    request_id UUID REFERENCES verification_requests(id) ON DELETE SET NULL,
    subject_user_id TEXT,
    action TEXT NOT NULL CHECK (action IN (
        'view_queue', 'view_id', 'view_video', 'view_authority',
        'approve', 'reject', 'request_resubmission'
    )),
    notes TEXT,
    occurred_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_verification_admin_audit_request
    ON verification_admin_audit(request_id, occurred_at DESC);

CREATE INDEX IF NOT EXISTS idx_verification_admin_audit_subject
    ON verification_admin_audit(subject_user_id, occurred_at DESC);

-- No legacy Firestore verification evidence is copied to the active API.
-- Existing raw archive rows remain available in firestore_import_archive.
