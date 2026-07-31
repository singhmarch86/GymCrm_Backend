-- Migration 009: leads table
--
-- Leads are prospective members moving through a 6-stage sales pipeline.
-- Soft-deleted (deleted_at) — same pattern as members and plans.
-- No FK to members yet — conversion is a future sprint.
-- assigned_user_id references the gym staff member handling this lead.

CREATE TABLE leads (
    id                  BIGSERIAL     PRIMARY KEY,
    gym_id              BIGINT        NOT NULL REFERENCES gyms(id),

    -- Basic info
    name                VARCHAR(200)  NOT NULL,
    phone               VARCHAR(20)   NOT NULL,
    email               VARCHAR(200),
    gender              VARCHAR(10),  -- male | female | other

    -- Lead context
    source              VARCHAR(50)   NOT NULL DEFAULT 'walk_in',
                        -- walk_in | referral | instagram | facebook |
                        -- google | whatsapp | website | other
    goal                VARCHAR(50),  -- weight_loss | muscle_gain | fitness |
                        -- sports | rehabilitation | other
    notes               TEXT,

    -- Pipeline
    status              VARCHAR(30)   NOT NULL DEFAULT 'new_lead',
                        -- new_lead | contacted | trial_scheduled |
                        -- trial_completed | joined | lost

    -- Key dates
    trial_date          DATE,         -- when the trial session is/was
    follow_up_date      DATE,         -- next follow-up reminder
    lost_reason         TEXT,         -- only set when status = 'lost'

    -- Assignment
    assigned_user_id    BIGINT        REFERENCES users(id),  -- gym staff

    -- Future: link to member when converted
    converted_member_id BIGINT,       -- no FK yet — members table might be in a different context

    created_at          TIMESTAMPTZ   NOT NULL DEFAULT NOW(),
    updated_at          TIMESTAMPTZ   NOT NULL DEFAULT NOW(),
    deleted_at          TIMESTAMPTZ   -- soft delete
);

-- Primary queries
CREATE INDEX idx_leads_gym_status
    ON leads (gym_id, status)
    WHERE deleted_at IS NULL;

CREATE INDEX idx_leads_gym_followup
    ON leads (gym_id, follow_up_date)
    WHERE deleted_at IS NULL AND follow_up_date IS NOT NULL;

CREATE INDEX idx_leads_gym_created
    ON leads (gym_id, created_at DESC)
    WHERE deleted_at IS NULL;

-- Source distribution (reports)
CREATE INDEX idx_leads_gym_source
    ON leads (gym_id, source)
    WHERE deleted_at IS NULL;

CREATE TRIGGER trg_leads_updated_at
    BEFORE UPDATE ON leads
    FOR EACH ROW EXECUTE FUNCTION set_updated_at();
