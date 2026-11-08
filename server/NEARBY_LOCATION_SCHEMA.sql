-- Location sharing is optional and independent from the member's public city.
-- Raw device coordinates are rounded by the API before they reach this table.
CREATE TABLE IF NOT EXISTS profile_locations (
    user_id UUID PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
    latitude DOUBLE PRECISION NOT NULL CHECK (latitude BETWEEN -90 AND 90),
    longitude DOUBLE PRECISION NOT NULL CHECK (longitude BETWEEN -180 AND 180),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

COMMENT ON TABLE profile_locations IS
    'Optional city-scale coordinates used only to rank nearby recommendations. Never return coordinates to clients.';
