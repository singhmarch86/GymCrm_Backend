-- Migration 007: payments table
--
-- Payments become the financial source of truth. Renewals remain the
-- membership lifecycle source of truth. The two are linked from the
-- RENEWALS side: renewals.payment_id (added in migration 008) points back
-- at the payment that funded it. payments does NOT reference renewals —
-- a payment is the cause, a renewal is one possible effect, and the FK
-- direction reflects that (effect points to cause, not the other way).
--
-- This also means payments can exist with no renewal at all in the future
-- (PT session fees, one-off charges) without ever needing a nullable
-- "renewal_id" column here that would mostly sit empty.
--
-- status:
--   'paid'    — money has been collected. Set at insert time for the
--               Collect Payment flow (Sprint 4 only ever inserts 'paid' rows).
--   'pending' — a due exists but hasn't been collected yet. Not created by
--               any endpoint in Sprint 4 — reserved for a future "generate
--               dues" job that pre-creates pending rows ahead of expiry.
--   'overdue' — a pending row whose due_date has passed. Computed at read
--               time in Go (see payments.Service), not stored — mirrors the
--               pattern already used for members.ExpiryStatus in Sprint 3.

CREATE TABLE payments (
    id                   BIGSERIAL     PRIMARY KEY,
    gym_id               BIGINT        NOT NULL REFERENCES gyms(id),
    member_id            BIGINT        NOT NULL REFERENCES members(id),
    plan_id              BIGINT        REFERENCES membership_plans(id),

    amount_in_paise      BIGINT        NOT NULL CHECK (amount_in_paise > 0),

    status                VARCHAR(20)  NOT NULL DEFAULT 'paid'
                                        CHECK (status IN ('pending', 'paid', 'overdue')),

    payment_mode          VARCHAR(20)  CHECK (payment_mode IN
                                        ('cash', 'upi', 'credit_card', 'debit_card', 'bank_transfer')),

    due_date              DATE,
    paid_date             DATE,

    collected_by_user_id  BIGINT       REFERENCES users(id),
    reference_number      VARCHAR(100),
    notes                 TEXT,

    created_at             TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at             TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    -- A paid payment must have a paid_date and a payment_mode.
    -- A pending/overdue payment must NOT have a paid_date yet.
    CONSTRAINT chk_payments_paid_consistency CHECK (
        (status = 'paid' AND paid_date IS NOT NULL AND payment_mode IS NOT NULL)
        OR
        (status != 'paid' AND paid_date IS NULL)
    )
);

-- Member payment history (most common query — used by GET /members/{id}/payments)
CREATE INDEX idx_payments_gym_member
    ON payments (gym_id, member_id, paid_date DESC NULLS LAST, due_date DESC NULLS LAST);

-- Dashboard revenue aggregation: today / this month
CREATE INDEX idx_payments_gym_paid_date
    ON payments (gym_id, paid_date DESC)
    WHERE status = 'paid';

-- Pending/overdue dues lookup
CREATE INDEX idx_payments_gym_status
    ON payments (gym_id, status, due_date);

CREATE TRIGGER trg_payments_updated_at
    BEFORE UPDATE ON payments
    FOR EACH ROW EXECUTE FUNCTION set_updated_at();
