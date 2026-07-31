-- ============================================================
-- Migration: 002_members_update.sql
-- Splits name → first_name + last_name
-- Adds membership_plan_id, start_date, expiry_date
-- ============================================================

-- Step 1: add new columns (nullable first so existing rows don't violate NOT NULL)
ALTER TABLE members
    ADD COLUMN IF NOT EXISTS first_name VARCHAR(100),
    ADD COLUMN IF NOT EXISTS last_name  VARCHAR(100),
    ADD COLUMN IF NOT EXISTS membership_plan_id BIGINT REFERENCES membership_plans(id),
    ADD COLUMN IF NOT EXISTS start_date  DATE,
    ADD COLUMN IF NOT EXISTS expiry_date DATE;

-- Step 2: backfill first_name from existing name column (split on first space)
UPDATE members
SET first_name = SPLIT_PART(name, ' ', 1),
    last_name  = NULLIF(TRIM(SUBSTRING(name FROM POSITION(' ' IN name))), '');

-- Step 3: set NOT NULL now that backfill is done
ALTER TABLE members
    ALTER COLUMN first_name SET NOT NULL,
    ALTER COLUMN last_name  SET NOT NULL;

-- Step 4: drop the old name column
ALTER TABLE members DROP COLUMN IF EXISTS name;

-- Step 5: new indexes
CREATE INDEX IF NOT EXISTS idx_members_gym_firstname
    ON members (gym_id, first_name)
    WHERE deleted_at IS NULL;

CREATE INDEX IF NOT EXISTS idx_members_gym_expiry
    ON members (gym_id, expiry_date)
    WHERE deleted_at IS NULL AND expiry_date IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_members_plan
    ON members (membership_plan_id)
    WHERE deleted_at IS NULL AND membership_plan_id IS NOT NULL;
