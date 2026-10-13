-- Nisa Matchmaker Network additive PostgreSQL migration.
-- Apply only after taking a pg_dump. No existing tables are altered.
CREATE EXTENSION IF NOT EXISTS pgcrypto;

CREATE TABLE IF NOT EXISTS matchmaker_accounts (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL UNIQUE REFERENCES users(id) ON DELETE CASCADE,
  business_name text NOT NULL,
  phone text NOT NULL,
  notes text NOT NULL DEFAULT '',
  status text NOT NULL DEFAULT 'pending' CHECK (status IN ('pending','approved','rejected','suspended')),
  trust_score numeric(5,2) NOT NULL DEFAULT 0,
  reviewed_by uuid REFERENCES users(id) ON DELETE SET NULL,
  reviewed_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS partner_profiles (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  matchmaker_id uuid NOT NULL REFERENCES matchmaker_accounts(id) ON DELETE CASCADE,
  claimed_user_id uuid UNIQUE REFERENCES users(id) ON DELETE SET NULL,
  external_reference text NOT NULL DEFAULT '',
  full_name text NOT NULL,
  gender text NOT NULL,
  age integer CHECK (age IS NULL OR age BETWEEN 18 AND 100),
  city text NOT NULL DEFAULT '', country text NOT NULL DEFAULT 'Pakistan',
  height text NOT NULL DEFAULT '', marital_status text NOT NULL DEFAULT '',
  education text NOT NULL DEFAULT '', profession text NOT NULL DEFAULT '',
  religion text NOT NULL DEFAULT 'Islam', sect text NOT NULL DEFAULT '',
  phone text NOT NULL DEFAULT '', email text NOT NULL DEFAULT '',
  partner_preferences text NOT NULL DEFAULT '', notes text NOT NULL DEFAULT '',
  consent_status text NOT NULL DEFAULT 'pending' CHECK (consent_status IN ('pending','requested','approved','declined','revoked')),
  verification_status text NOT NULL DEFAULT 'unverified' CHECK (verification_status IN ('unverified','pending','verified','rejected')),
  visibility text NOT NULL DEFAULT 'private' CHECK (visibility IN ('private','network','active','archived')),
  source_type text NOT NULL DEFAULT 'manual', source_hash text,
  created_at timestamptz NOT NULL DEFAULT now(), updated_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS partner_profiles_matchmaker_idx ON partner_profiles(matchmaker_id, visibility);
CREATE INDEX IF NOT EXISTS partner_profiles_consent_idx ON partner_profiles(consent_status);
CREATE UNIQUE INDEX IF NOT EXISTS partner_profiles_source_hash_unique ON partner_profiles(matchmaker_id, source_hash) WHERE source_hash IS NOT NULL;

CREATE TABLE IF NOT EXISTS partner_profile_consent_events (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(), partner_profile_id uuid NOT NULL REFERENCES partner_profiles(id) ON DELETE CASCADE,
  event_type text NOT NULL CHECK (event_type IN ('requested','approved','declined','revoked')),
  channel text NOT NULL DEFAULT 'in_app', actor_user_id uuid REFERENCES users(id) ON DELETE SET NULL,
  evidence jsonb NOT NULL DEFAULT '{}'::jsonb, created_at timestamptz NOT NULL DEFAULT now()
);
CREATE TABLE IF NOT EXISTS matchmaker_audit_logs (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(), matchmaker_id uuid NOT NULL REFERENCES matchmaker_accounts(id) ON DELETE CASCADE,
  actor_user_id uuid REFERENCES users(id) ON DELETE SET NULL, event_type text NOT NULL,
  target_type text NOT NULL DEFAULT '', target_id text NOT NULL DEFAULT '', metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at timestamptz NOT NULL DEFAULT now()
);
