-- Migration 006: redesign attendance table
-- Previous schema had recorded_by, wrong column name (checked_in vs checked_in_at).
-- New schema matches approved design with correct indexes.

DROP TABLE IF EXISTS attendance;

CREATE TABLE attendance (
    id              BIGSERIAL    PRIMARY KEY,
    gym_id          BIGINT       NOT NULL REFERENCES gyms(id),
    member_id       BIGINT       NOT NULL REFERENCES members(id),
    checked_in_at   TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
    checked_in_date DATE         NOT NULL DEFAULT CURRENT_DATE,
    created_at      TIMESTAMPTZ  NOT NULL DEFAULT NOW()
);

-- Duplicate prevention: one check-in per member per day per gym
-- This is the hard enforcement layer — service layer checks first, DB catches races
CREATE UNIQUE INDEX idx_attendance_unique_daily
    ON attendance (gym_id, member_id, checked_in_date);

-- Dashboard queries: today/week/month attendance counts
CREATE INDEX idx_attendance_gym_date
    ON attendance (gym_id, checked_in_date DESC);

-- Member history + retention inactivity queries
-- "Find members who haven't checked in for 7/14/30 days"
CREATE INDEX idx_attendance_gym_member_date
    ON attendance (gym_id, member_id, checked_in_date DESC);
