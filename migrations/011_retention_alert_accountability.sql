-- Migration 011: record WHO handled a retention alert, and WHAT they did.
--
-- retention_alerts previously stored only is_resolved + resolved_at, so a
-- closed alert said "someone cleared this at 14:32" — indistinguishable from a
-- staff member tidying the list without contacting anybody. A gym owner's first
-- question about this feature is "how do I know my staff actually called?", and
-- the table could not answer it.
--
-- Both columns are additive and nullable: alerts resolved before this migration
-- keep a NULL resolved_by, which correctly reads as "unknown" rather than
-- pinning historic work on whoever happens to be logged in now.

ALTER TABLE retention_alerts
    ADD COLUMN IF NOT EXISTS resolved_by BIGINT REFERENCES users(id),
    ADD COLUMN IF NOT EXISTS action_note TEXT;

COMMENT ON COLUMN retention_alerts.resolved_by IS
    'User who marked the alert handled. NULL for alerts closed before this column existed, or auto-resolved by the scan.';

COMMENT ON COLUMN retention_alerts.action_note IS
    'What the staff member actually did, e.g. "Called, will renew Friday". NULL when resolved without a note.';

-- Supports "what did each staff member handle this week", which is the
-- accountability view this migration exists to enable.
CREATE INDEX IF NOT EXISTS idx_alerts_resolved_by
    ON retention_alerts (gym_id, resolved_by, resolved_at DESC)
    WHERE is_resolved = true;
