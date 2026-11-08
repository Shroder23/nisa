-- Fix HTTP 500 from the Google auth route when the DB still has the original
-- Step 21 api_rate_limit_events scope check. This preserves existing events.
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
