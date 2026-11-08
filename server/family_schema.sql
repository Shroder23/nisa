-- Additive PostgreSQL migration for the Phase 9B family / guardian flow.
-- Family details are visible only to the owning account and the invitee whose
-- verified API email exactly matches the invitation email.

CREATE TABLE IF NOT EXISTS family_members (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    legacy_id TEXT UNIQUE,
    owner_user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    name TEXT NOT NULL CHECK (char_length(name) BETWEEN 1 AND 120),
    role TEXT NOT NULL CHECK (role IN (
        'father', 'mother', 'brother', 'sister', 'guardian', 'other'
    )),
    email TEXT,
    phone TEXT,
    invitation_status TEXT NOT NULL DEFAULT 'pending'
        CHECK (invitation_status IN (
            'pending', 'email_confirmed', 'accepted', 'declined', 'cancelled'
        )),
    linked_user_id TEXT REFERENCES users(id) ON DELETE SET NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CHECK (email IS NOT NULL OR phone IS NOT NULL),
    CHECK (email IS NULL OR char_length(email) <= 254),
    CHECK (phone IS NULL OR char_length(phone) <= 32)
);

CREATE TABLE IF NOT EXISTS family_invitations (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    legacy_id TEXT UNIQUE,
    family_member_id UUID UNIQUE REFERENCES family_members(id) ON DELETE SET NULL,
    owner_user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    owner_name TEXT NOT NULL CHECK (char_length(owner_name) BETWEEN 1 AND 120),
    member_name TEXT NOT NULL CHECK (char_length(member_name) BETWEEN 1 AND 120),
    role TEXT NOT NULL CHECK (role IN (
        'father', 'mother', 'brother', 'sister', 'guardian', 'other'
    )),
    invitee_email TEXT,
    invitee_phone TEXT,
    invitee_user_id TEXT REFERENCES users(id) ON DELETE SET NULL,
    status TEXT NOT NULL DEFAULT 'pending'
        CHECK (status IN (
            'pending', 'email_confirmed', 'accepted', 'declined', 'cancelled'
        )),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    responded_at TIMESTAMPTZ,
    CHECK (invitee_email IS NOT NULL OR invitee_phone IS NOT NULL)
);

CREATE INDEX IF NOT EXISTS idx_family_members_owner
    ON family_members(owner_user_id, created_at);

CREATE INDEX IF NOT EXISTS idx_family_invitations_incoming
    ON family_invitations(invitee_email, status, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_family_invitations_member
    ON family_invitations(family_member_id);

CREATE INDEX IF NOT EXISTS idx_family_invitations_owner
    ON family_invitations(owner_user_id, status, created_at DESC);

-- Migrate the already-imported Firestore family records where the owner has a
-- unique-email account in PostgreSQL. The raw Firestore archive remains intact.
DO $$
BEGIN
    IF to_regclass('public.firestore_import_archive') IS NOT NULL THEN
        WITH email_counts AS (
            SELECT
                LOWER(BTRIM(source_document->'data'->>'email')) AS email,
                COUNT(*) AS account_count
            FROM firestore_import_archive
            WHERE collection_name = 'private_users'
              AND NULLIF(BTRIM(source_document->'data'->>'email'), '') IS NOT NULL
            GROUP BY LOWER(BTRIM(source_document->'data'->>'email'))
        ), source_user_map AS (
            SELECT pu.document_id AS source_uid, u.id AS user_id
            FROM firestore_import_archive pu
            JOIN email_counts ec
              ON ec.email = LOWER(BTRIM(pu.source_document->'data'->>'email'))
             AND ec.account_count = 1
            JOIN users u
              ON LOWER(u.email) = ec.email
             AND u.account_status = 'active'
            WHERE pu.collection_name = 'private_users'
        )
        INSERT INTO family_members (
            legacy_id, owner_user_id, name, role, email, phone,
            invitation_status, linked_user_id, created_at
        )
        SELECT
            fm.document_id,
            owner_map.user_id,
            COALESCE(NULLIF(BTRIM(fm.source_document->'data'->>'name'), ''), 'Family member'),
            CASE WHEN fm.source_document->'data'->>'role' IN
                ('father', 'mother', 'brother', 'sister', 'guardian', 'other')
                THEN fm.source_document->'data'->>'role' ELSE 'other' END,
            NULLIF(LOWER(BTRIM(fm.source_document->'data'->>'email')), ''),
            NULLIF(BTRIM(fm.source_document->'data'->>'phone'), ''),
            CASE COALESCE(fm.source_document->'data'->>'invitationStatus', 'pending')
                WHEN 'emailConfirmed' THEN 'email_confirmed'
                WHEN 'accepted' THEN 'accepted'
                WHEN 'declined' THEN 'declined'
                WHEN 'cancelled' THEN 'cancelled'
                ELSE 'pending' END,
            linked_map.user_id,
            COALESCE(
                NULLIF(fm.source_document->'data'->'createdAt'->>'value', '')::timestamptz,
                NOW()
            )
        FROM firestore_import_archive fm
        JOIN source_user_map owner_map
          ON owner_map.source_uid = fm.source_document->'data'->>'ownerUid'
        LEFT JOIN source_user_map linked_map
          ON linked_map.source_uid = fm.source_document->'data'->>'linkedUid'
        WHERE fm.collection_name = 'family_members'
          AND (
              NULLIF(BTRIM(fm.source_document->'data'->>'email'), '') IS NOT NULL
              OR NULLIF(BTRIM(fm.source_document->'data'->>'phone'), '') IS NOT NULL
          )
        ON CONFLICT (legacy_id) DO NOTHING;

        WITH email_counts AS (
            SELECT
                LOWER(BTRIM(source_document->'data'->>'email')) AS email,
                COUNT(*) AS account_count
            FROM firestore_import_archive
            WHERE collection_name = 'private_users'
              AND NULLIF(BTRIM(source_document->'data'->>'email'), '') IS NOT NULL
            GROUP BY LOWER(BTRIM(source_document->'data'->>'email'))
        ), source_user_map AS (
            SELECT pu.document_id AS source_uid, u.id AS user_id
            FROM firestore_import_archive pu
            JOIN email_counts ec
              ON ec.email = LOWER(BTRIM(pu.source_document->'data'->>'email'))
             AND ec.account_count = 1
            JOIN users u ON LOWER(u.email) = ec.email
             AND u.account_status = 'active'
            WHERE pu.collection_name = 'private_users'
        )
        INSERT INTO family_invitations (
            legacy_id, family_member_id, owner_user_id, owner_name,
            member_name, role, invitee_email, invitee_phone,
            invitee_user_id, status, created_at, responded_at
        )
        SELECT
            fi.document_id,
            member.id,
            owner_map.user_id,
            COALESCE(NULLIF(BTRIM(fi.source_document->'data'->>'ownerName'), ''), 'Nisa Member'),
            COALESCE(
                NULLIF(BTRIM(fi.source_document->'data'->>'inviteeName'), ''),
                member.name,
                'Family member'
            ),
            CASE WHEN fi.source_document->'data'->>'role' IN
                ('father', 'mother', 'brother', 'sister', 'guardian', 'other')
                THEN fi.source_document->'data'->>'role' ELSE 'other' END,
            NULLIF(LOWER(BTRIM(fi.source_document->'data'->>'email')), ''),
            NULLIF(BTRIM(fi.source_document->'data'->>'phone'), ''),
            invitee_map.user_id,
            CASE COALESCE(fi.source_document->'data'->>'status', 'pending')
                WHEN 'emailConfirmed' THEN 'email_confirmed'
                WHEN 'accepted' THEN 'accepted'
                WHEN 'declined' THEN 'declined'
                WHEN 'cancelled' THEN 'cancelled'
                ELSE 'pending' END,
            COALESCE(
                NULLIF(fi.source_document->'data'->'createdAt'->>'value', '')::timestamptz,
                NOW()
            ),
            NULLIF(fi.source_document->'data'->'respondedAt'->>'value', '')::timestamptz
        FROM firestore_import_archive fi
        JOIN source_user_map owner_map
          ON owner_map.source_uid = fi.source_document->'data'->>'ownerUid'
        LEFT JOIN family_members member
          ON member.legacy_id = fi.source_document->'data'->>'familyMemberId'
        LEFT JOIN source_user_map invitee_map
          ON invitee_map.source_uid = fi.source_document->'data'->>'inviteeUid'
        WHERE fi.collection_name = 'family_invitations'
          AND (
              NULLIF(BTRIM(fi.source_document->'data'->>'email'), '') IS NOT NULL
              OR NULLIF(BTRIM(fi.source_document->'data'->>'phone'), '') IS NOT NULL
          )
        ON CONFLICT (legacy_id) DO NOTHING;
    END IF;
END $$;
