-- Migration 003: fix gym email unique index
-- Empty string '' was being treated as a duplicate across gyms.
-- Drop the old index and recreate it to exclude empty strings.

DROP INDEX IF EXISTS idx_gyms_email;

CREATE UNIQUE INDEX idx_gyms_email
    ON gyms (email)
    WHERE email IS NOT NULL AND email != '';
