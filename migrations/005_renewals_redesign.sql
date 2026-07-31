-- Migration 005: redesign renewals table
-- Previous schema had start_date/end_date/status/payment_mode.
-- New schema matches audit trail requirements:
-- old_expiry_date, new_expiry_date, renewal_date, renewed_by_user_id.

DROP TABLE IF EXISTS renewals;

CREATE TABLE renewals (
    id                   BIGSERIAL PRIMARY KEY,
    gym_id               BIGINT        NOT NULL REFERENCES gyms(id),
    member_id            BIGINT        NOT NULL REFERENCES members(id),
    plan_id              BIGINT        NOT NULL REFERENCES membership_plans(id),
    amount_paid_in_paise BIGINT        NOT NULL CHECK (amount_paid_in_paise > 0),
    old_expiry_date      DATE,                    -- NULL for first-time members
    new_expiry_date      DATE          NOT NULL,
    renewal_date         DATE          NOT NULL DEFAULT CURRENT_DATE,
    renewed_by_user_id   BIGINT        NOT NULL REFERENCES users(id),
    notes                TEXT,
    created_at           TIMESTAMPTZ   NOT NULL DEFAULT NOW(),
    updated_at           TIMESTAMPTZ   NOT NULL DEFAULT NOW(),

    CONSTRAINT chk_renewal_new_expiry CHECK (new_expiry_date > renewal_date)
);

-- Member renewal history (most common query)
CREATE INDEX idx_renewals_gym_member
    ON renewals (gym_id, member_id);

-- Recent renewals dashboard
CREATE INDEX idx_renewals_gym_date
    ON renewals (gym_id, renewal_date DESC);

-- Combined: tenant + member + date (GET /members/{id}/renewals sorted)
CREATE INDEX idx_renewals_member_date
    ON renewals (gym_id, member_id, renewal_date DESC);

-- Plan usage filter
CREATE INDEX idx_renewals_plan
    ON renewals (plan_id);

-- updated_at trigger
CREATE TRIGGER trg_renewals_updated_at
    BEFORE UPDATE ON renewals
    FOR EACH ROW EXECUTE FUNCTION set_updated_at();
