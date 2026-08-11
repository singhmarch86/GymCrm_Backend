-- FR-16 — what came of a follow-up, alongside what was done.
--
-- Nullable with no default and no backfill, deliberately. Every row written
-- before today genuinely has no recorded outcome, and inventing one — even
-- 'answered' as a "sensible" default — would make every count computed from
-- this column a lie about work nobody did.

ALTER TABLE lead_activities ADD COLUMN IF NOT EXISTS outcome VARCHAR(30);

-- Partial index: only rows that carry an outcome are worth indexing. In the
-- demo set that excludes 102 stage_change rows out of 111, and in a real gym
-- the ratio is worse — pipeline history vastly outnumbers logged calls.
CREATE INDEX IF NOT EXISTS idx_lead_activities_outcome
    ON lead_activities (gym_id, outcome, created_at DESC)
    WHERE outcome IS NOT NULL;

-- Values are validated in Go rather than by a CHECK constraint, matching how
-- activity `type` is handled two columns over. A CHECK here would mean a
-- migration every time the vocabulary changes, and FR-16 §1 expects the pilot
-- gym to revise this list at least once.
