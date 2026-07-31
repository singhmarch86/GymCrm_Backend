-- Migration 004: membership_plans — add case-insensitive unique name index
-- LOWER(name) expression index enforces case-insensitive uniqueness per gym.
-- "Monthly Basic" and "monthly basic" are treated as the same plan name.
-- Partial: deleted plans release their name back for reuse.

CREATE UNIQUE INDEX idx_plans_gym_name_lower
    ON membership_plans (gym_id, LOWER(name))
    WHERE deleted_at IS NULL;
