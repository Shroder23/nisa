-- Speed up primary profile-photo lookup and replacement.
CREATE INDEX IF NOT EXISTS idx_profile_photos_user_order
    ON profile_photos(user_id, display_order);
