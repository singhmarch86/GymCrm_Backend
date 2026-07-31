-- Migration 010: lead_activities table
--
-- An append-only timeline of everything that happens to a lead: stage
-- transitions, logged calls, notes, follow-up reschedules. This is what powers
-- the per-lead activity feed and the "average time in stage" analytics, which
-- cannot be derived from the leads table alone (it only stores the *current*
-- status, so history is lost on every transition).
--
-- Rows are never updated or deleted — a lead's history is immutable. There is
-- no soft-delete column for that reason. When a lead is soft-deleted its
-- activities simply stop being queried.

CREATE TABLE lead_activities (
    id           BIGSERIAL     PRIMARY KEY,
    gym_id       BIGINT        NOT NULL REFERENCES gyms(id),
    lead_id      BIGINT        NOT NULL REFERENCES leads(id) ON DELETE CASCADE,

    -- Who did it. Nullable: system-generated entries (e.g. seeded history or
    -- an automated transition) have no acting user.
    user_id      BIGINT        REFERENCES users(id),

    -- What kind of entry this is.
    type         VARCHAR(30)   NOT NULL,
                 -- stage_change | call | note | follow_up_set | trial_scheduled
                 -- | created | converted | lost

    note         TEXT,

    -- Populated only for type = 'stage_change', so time-in-stage can be
    -- reconstructed by walking a lead's transitions in created_at order.
    from_status  VARCHAR(30),
    to_status    VARCHAR(30),

    created_at   TIMESTAMPTZ   NOT NULL DEFAULT NOW()
);

-- The timeline query: all activities for one lead, newest first.
CREATE INDEX idx_lead_activities_lead
    ON lead_activities (lead_id, created_at DESC);

-- Analytics: stage transitions across the gym within a date range.
CREATE INDEX idx_lead_activities_gym_type
    ON lead_activities (gym_id, type, created_at DESC);
