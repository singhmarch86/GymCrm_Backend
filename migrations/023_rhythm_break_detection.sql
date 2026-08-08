-- 023_rhythm_break_detection.sql
-- FR-09: detect members whose training *time* has broken while their visit
-- count still looks healthy.

BEGIN;

-- The rhythm break is a new kind of retention alert, not a new alert system.
-- Widening the existing CHECK keeps every behaviour the At Risk queue already
-- has: dedup, auto-resolve, action notes, staff attribution.
ALTER TABLE retention_alerts DROP CONSTRAINT IF EXISTS retention_alerts_alert_type_check;
ALTER TABLE retention_alerts ADD CONSTRAINT retention_alerts_alert_type_check
    CHECK (alert_type IN (
        'expiring_in_3_days',
        'expiring_today',
        'expired_no_renewal',
        'inactive_1_week',
        'inactive_2_weeks',
        'rhythm_break'
    ));

-- One row per member, rewritten by each scan. This is a *description* of how a
-- member trains, not an accusation — it is written for every eligible member,
-- broken rhythm or not, and drives "trains Tue/Thu around 6:30pm" on the member
-- profile as well as the alert detail.
CREATE TABLE IF NOT EXISTS member_rhythm_profiles (
    gym_id                BIGINT      NOT NULL REFERENCES gyms(id),
    member_id             BIGINT      NOT NULL REFERENCES members(id),

    computed_as_of        DATE        NOT NULL,

    -- Minutes past local midnight (IST). Circular mean of baseline check-ins.
    anchor_minute         INT         NOT NULL,

    baseline_visits       INT         NOT NULL,
    baseline_weeks        INT         NOT NULL,
    baseline_consistency  NUMERIC(4,3) NOT NULL,
    baseline_rate         NUMERIC(6,3) NOT NULL,  -- visits per week

    recent_visits         INT         NOT NULL,
    recent_consistency    NUMERIC(4,3) NOT NULL,
    recent_rate           NUMERIC(6,3) NOT NULL,

    -- Visits that landed inside the ±window, for the human-readable message.
    baseline_on_slot      INT         NOT NULL,
    recent_on_slot        INT         NOT NULL,

    -- 7-char bitmaps, Sunday first, e.g. '.MTWT..' — context only, never gates
    -- the alert (FR-09 §6).
    baseline_weekdays     VARCHAR(7)  NOT NULL DEFAULT '.......',
    recent_weekdays       VARCHAR(7)  NOT NULL DEFAULT '.......',

    is_broken             BOOLEAN     NOT NULL DEFAULT false,
    updated_at            TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    PRIMARY KEY (gym_id, member_id)
);

CREATE INDEX IF NOT EXISTS idx_rhythm_profiles_broken
    ON member_rhythm_profiles (gym_id, is_broken, updated_at DESC);

COMMIT;
