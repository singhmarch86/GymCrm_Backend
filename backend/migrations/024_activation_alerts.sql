-- 024_activation_alerts.sql
-- FR-10: watch members through their first 90 days.
--
-- No new tables. The three activation states are cheap to compute from
-- members + attendance, and a stored profile would be one more thing to keep
-- in step with reality for no gain.

BEGIN;

ALTER TABLE retention_alerts DROP CONSTRAINT IF EXISTS retention_alerts_alert_type_check;
ALTER TABLE retention_alerts ADD CONSTRAINT retention_alerts_alert_type_check
    CHECK (alert_type IN (
        'expiring_in_3_days',
        'expiring_today',
        'expired_no_renewal',
        'inactive_1_week',
        'inactive_2_weeks',
        'rhythm_break',
        'activation_no_first_visit',
        'activation_slow_start',
        'activation_going_quiet'
    ));

-- The programme is driven entirely off join_date, so that lookup has to be
-- fast once a gym has thousands of members. join_date is deliberately the
-- filter rather than start_date: start_date moves forward on every renewal,
-- and a member who renewed last week is not a new member (FR-10 §1).
CREATE INDEX IF NOT EXISTS idx_members_gym_join_date
    ON members (gym_id, join_date DESC)
    WHERE deleted_at IS NULL;

COMMIT;
