-- Nisa API authentication update. Run once against the existing PostgreSQL database
-- before restarting the API with the matching server_patch/main.py.

CREATE TABLE IF NOT EXISTS api_password_credentials (
    user_id TEXT PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
    salt_hex TEXT NOT NULL CHECK (length(salt_hex) = 32),
    password_hash_hex TEXT NOT NULL CHECK (length(password_hash_hex) = 64),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- The authentication routes add independent rate-limit buckets. The earlier
-- production-hardening schema allowed only OTP and verification scopes.
ALTER TABLE api_rate_limit_events
    DROP CONSTRAINT IF EXISTS api_rate_limit_events_scope_check;

ALTER TABLE api_rate_limit_events
    ADD CONSTRAINT api_rate_limit_events_scope_check
    CHECK (scope IN (
        'otp_request_ip', 'otp_request_email',
        'otp_verify_ip', 'otp_verify_email',
        'verification_submit_user',
        'email_lookup_ip', 'email_lookup_email',
        'password_login_ip', 'password_login_email',
        'password_reset_ip', 'password_reset_email',
        'password_reset_verify_ip', 'password_reset_verify_email',
        'google_login_ip', 'google_login_email'
    ));

-- Password reset codes use their own purpose so they cannot be mistaken for
-- registration codes. Preserve existing values while allowing both purposes.
DO $$
DECLARE constraint_row RECORD;
BEGIN
    FOR constraint_row IN
        SELECT conname
        FROM pg_constraint
        WHERE conrelid = 'email_otps'::regclass
          AND contype = 'c'
          AND pg_get_constraintdef(oid) ILIKE '%purpose%'
    LOOP
        EXECUTE format('ALTER TABLE email_otps DROP CONSTRAINT %I', constraint_row.conname);
    END LOOP;
END $$;

ALTER TABLE email_otps
    ALTER COLUMN purpose TYPE TEXT USING purpose::TEXT;

ALTER TABLE email_otps
    DROP CONSTRAINT IF EXISTS email_otps_purpose_allowed;

ALTER TABLE email_otps
    ADD CONSTRAINT email_otps_purpose_allowed
    CHECK (purpose IN ('registration', 'password_reset'));
