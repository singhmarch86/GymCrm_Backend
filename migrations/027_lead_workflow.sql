-- FR-18 — every open lead has one next step, owned by someone, with a date.
--
-- Deliberately separate from follow_up_date, which stays exactly as it is and
-- keeps backing the follow-up queue. The two answer different questions:
-- follow_up_date is "when do I contact them again", next_step is "what am I
-- doing and why". A lead can have a trial booked next Tuesday *and* a
-- confirmation call on Monday; collapsing those into one column loses the
-- second every time.

ALTER TABLE leads ADD COLUMN IF NOT EXISTS next_step     VARCHAR(40);
ALTER TABLE leads ADD COLUMN IF NOT EXISTS next_step_due DATE;

-- The workflow query's whole job is "what is due, and what has nothing at
-- all". Partial index over open leads only: joined and lost carry no next step
-- by design (FR-18 §6), and in a mature gym they are most of the table.
CREATE INDEX IF NOT EXISTS idx_leads_next_step_due
    ON leads (gym_id, next_step_due, assigned_user_id)
    WHERE deleted_at IS NULL AND status NOT IN ('joined', 'lost');

-- No backfill, on purpose.
--
-- Every existing lead starts with a null next step, which places it in
-- Unattended. That is not a migration defect — it is the true state of the
-- pipeline, and the first honest picture the gym will get. Inventing a step
-- and a date for 47 leads nobody has looked at would hide exactly the problem
-- this feature exists to surface.
--
-- Values are validated in Go rather than by a CHECK constraint, matching how
-- lead status and activity type are already handled. FR-18 §2's defaults are
-- expected to be corrected by the pilot gym, and that should not need a
-- migration.
