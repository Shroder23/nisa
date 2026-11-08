-- Nisa Matchmaker Network - additive migration
-- Backup first. Existing user/profile tables are not modified.
CREATE EXTENSION IF NOT EXISTS pgcrypto;

CREATE TABLE IF NOT EXISTS matchmaker_accounts (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id TEXT NOT NULL UNIQUE REFERENCES users(id) ON DELETE CASCADE,
  business_name TEXT NOT NULL CHECK (length(btrim(business_name)) BETWEEN 2 AND 160),
  phone TEXT NOT NULL,
  notes TEXT NOT NULL DEFAULT '',
  status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending','approved','rejected','suspended')),
  trust_score NUMERIC(5,2) NOT NULL DEFAULT 0 CHECK (trust_score BETWEEN 0 AND 100),
  reviewed_by TEXT REFERENCES users(id) ON DELETE SET NULL,
  review_reason TEXT NOT NULL DEFAULT '',
  reviewed_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_matchmaker_accounts_status ON matchmaker_accounts(status, created_at);

CREATE TABLE IF NOT EXISTS partner_profiles (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  matchmaker_id UUID NOT NULL REFERENCES matchmaker_accounts(id) ON DELETE CASCADE,
  claimed_user_id TEXT UNIQUE REFERENCES users(id) ON DELETE SET NULL,
  external_reference TEXT NOT NULL DEFAULT '',
  full_name TEXT NOT NULL CHECK (length(btrim(full_name)) BETWEEN 2 AND 160),
  gender TEXT NOT NULL CHECK (gender IN ('Male','Female')),
  age INTEGER CHECK (age IS NULL OR age BETWEEN 18 AND 100),
  city TEXT NOT NULL DEFAULT '', country TEXT NOT NULL DEFAULT 'Pakistan',
  height TEXT NOT NULL DEFAULT '', marital_status TEXT NOT NULL DEFAULT '',
  education TEXT NOT NULL DEFAULT '', profession TEXT NOT NULL DEFAULT '',
  religion TEXT NOT NULL DEFAULT 'Islam', sect TEXT NOT NULL DEFAULT '',
  phone TEXT NOT NULL DEFAULT '', email TEXT NOT NULL DEFAULT '',
  partner_preferences TEXT NOT NULL DEFAULT '', notes TEXT NOT NULL DEFAULT '',
  consent_status TEXT NOT NULL DEFAULT 'pending' CHECK (consent_status IN ('pending','requested','approved','declined','revoked')),
  verification_status TEXT NOT NULL DEFAULT 'unverified' CHECK (verification_status IN ('unverified','pending','verified','rejected')),
  visibility TEXT NOT NULL DEFAULT 'private' CHECK (visibility IN ('private','network','active','archived')),
  source_type TEXT NOT NULL DEFAULT 'manual' CHECK (source_type IN ('manual','whatsapp_text','text','csv','json','xlsx','pdf','image','api')),
  source_hash TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(), updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CHECK (visibility = 'private' OR consent_status = 'approved')
);
CREATE INDEX IF NOT EXISTS idx_partner_profiles_owner ON partner_profiles(matchmaker_id, visibility, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_partner_profiles_consent ON partner_profiles(consent_status, verification_status);
CREATE UNIQUE INDEX IF NOT EXISTS idx_partner_profiles_source_hash ON partner_profiles(matchmaker_id, source_hash) WHERE source_hash IS NOT NULL;

CREATE TABLE IF NOT EXISTS partner_profile_consent_events (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  partner_profile_id UUID NOT NULL REFERENCES partner_profiles(id) ON DELETE CASCADE,
  event_type TEXT NOT NULL CHECK (event_type IN ('requested','approved','declined','revoked','expired')),
  channel TEXT NOT NULL DEFAULT 'email' CHECK (channel IN ('email','in_app','manual')),
  actor_user_id TEXT REFERENCES users(id) ON DELETE SET NULL,
  evidence JSONB NOT NULL DEFAULT '{}'::jsonb,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_partner_consent_profile ON partner_profile_consent_events(partner_profile_id, created_at DESC);

CREATE TABLE IF NOT EXISTS partner_profile_consent_tokens (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  partner_profile_id UUID NOT NULL REFERENCES partner_profiles(id) ON DELETE CASCADE,
  token_hash TEXT NOT NULL UNIQUE,
  expires_at TIMESTAMPTZ NOT NULL,
  used_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_partner_consent_token_expiry ON partner_profile_consent_tokens(expires_at) WHERE used_at IS NULL;

CREATE TABLE IF NOT EXISTS matchmaker_introductions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  requester_matchmaker_id UUID NOT NULL REFERENCES matchmaker_accounts(id) ON DELETE CASCADE,
  requester_profile_id UUID NOT NULL REFERENCES partner_profiles(id) ON DELETE CASCADE,
  recipient_matchmaker_id UUID NOT NULL REFERENCES matchmaker_accounts(id) ON DELETE CASCADE,
  recipient_profile_id UUID NOT NULL REFERENCES partner_profiles(id) ON DELETE CASCADE,
  message TEXT NOT NULL DEFAULT '',
  status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending','accepted','declined','cancelled')),
  responded_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(), updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CHECK (requester_matchmaker_id <> recipient_matchmaker_id)
);
CREATE INDEX IF NOT EXISTS idx_matchmaker_intro_recipient ON matchmaker_introductions(recipient_matchmaker_id, status, created_at DESC);

CREATE TABLE IF NOT EXISTS matchmaker_audit_logs (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  matchmaker_id UUID REFERENCES matchmaker_accounts(id) ON DELETE SET NULL,
  actor_user_id TEXT REFERENCES users(id) ON DELETE SET NULL,
  event_type TEXT NOT NULL, target_type TEXT NOT NULL DEFAULT '', target_id TEXT NOT NULL DEFAULT '',
  metadata JSONB NOT NULL DEFAULT '{}'::jsonb, created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_matchmaker_audit_actor ON matchmaker_audit_logs(actor_user_id, created_at DESC);
