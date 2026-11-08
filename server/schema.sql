CREATE EXTENSION IF NOT EXISTS pgcrypto;

CREATE TABLE IF NOT EXISTS users (
    id TEXT PRIMARY KEY,
    email TEXT UNIQUE,
    display_name TEXT,
    account_status TEXT NOT NULL DEFAULT 'draft'
        CHECK (account_status IN ('draft', 'active', 'disabled', 'deleted')),
    registration_step TEXT NOT NULL DEFAULT 'basic_profile',
    is_online BOOLEAN NOT NULL DEFAULT FALSE,
    last_seen_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS profiles (
    user_id TEXT PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
    full_name TEXT NOT NULL,
    date_of_birth DATE,
    gender TEXT,
    country TEXT NOT NULL DEFAULT 'Pakistan',
    city TEXT NOT NULL DEFAULT 'Karachi',
    height_cm INTEGER,
    marital_status TEXT NOT NULL DEFAULT 'Single (Never Married)',
    children_count INTEGER NOT NULL DEFAULT 0,
    religion TEXT NOT NULL DEFAULT 'Islam',
    sect TEXT NOT NULL DEFAULT 'Sunni',
    caste TEXT,
    education TEXT,
    education_rank INTEGER,
    profession TEXT,
    primary_language TEXT DEFAULT 'Urdu',
    religious_practice TEXT DEFAULT 'Any',
    relocation_preference TEXT DEFAULT 'Maybe',
    photo_url TEXT,
    is_verified BOOLEAN NOT NULL DEFAULT FALSE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS matrimonial_preferences (
    user_id TEXT PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
    min_age INTEGER NOT NULL DEFAULT 18,
    max_age INTEGER NOT NULL DEFAULT 60,
    min_height_cm INTEGER,
    max_height_cm INTEGER,
    preferred_country TEXT NOT NULL DEFAULT 'Pakistan',
    preferred_city TEXT NOT NULL DEFAULT 'Karachi',
    preferred_marital_status TEXT NOT NULL DEFAULT 'Single (Never Married)',
    minimum_education TEXT,
    minimum_education_rank INTEGER,
    preferred_religion TEXT DEFAULT 'Islam',
    preferred_religious_practice TEXT DEFAULT 'Any',
    relocation_preference TEXT DEFAULT 'Maybe',
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS interests (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    sender_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    receiver_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    status TEXT NOT NULL DEFAULT 'pending'
        CHECK (status IN ('pending', 'accepted', 'declined', 'cancelled')),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE (sender_id, receiver_id)
);

CREATE TABLE IF NOT EXISTS matches (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_a TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    user_b TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE (user_a, user_b),
    CHECK (user_a <> user_b)
);

CREATE TABLE IF NOT EXISTS conversations (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_a TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    user_b TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    last_message_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE (user_a, user_b),
    CHECK (user_a <> user_b)
);

CREATE TABLE IF NOT EXISTS messages (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    conversation_id UUID NOT NULL REFERENCES conversations(id) ON DELETE CASCADE,
    sender_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    body TEXT NOT NULL,
    sent_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    delivered_at TIMESTAMPTZ,
    read_at TIMESTAMPTZ
);

CREATE TABLE IF NOT EXISTS notifications (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    recipient_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    actor_id TEXT REFERENCES users(id) ON DELETE SET NULL,
    notification_type TEXT NOT NULL,
    title TEXT NOT NULL,
    body TEXT,
    target_screen TEXT,
    target_id TEXT,
    is_read BOOLEAN NOT NULL DEFAULT FALSE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS profile_photos (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    file_path TEXT NOT NULL,
    display_order INTEGER NOT NULL DEFAULT 0,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_users_status
    ON users(account_status);

CREATE INDEX IF NOT EXISTS idx_profiles_search
    ON profiles(country, city, gender, marital_status, education_rank);

CREATE INDEX IF NOT EXISTS idx_profiles_height
    ON profiles(height_cm);

CREATE INDEX IF NOT EXISTS idx_interests_receiver
    ON interests(receiver_id, status);

CREATE INDEX IF NOT EXISTS idx_messages_conversation
    ON messages(conversation_id, sent_at);

CREATE INDEX IF NOT EXISTS idx_notifications_recipient
    ON notifications(recipient_id, is_read, created_at);
