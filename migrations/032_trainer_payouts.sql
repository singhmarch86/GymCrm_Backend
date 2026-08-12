-- 032: trainer payouts + the PT package/payment link (FR-21 §2)
--
-- Two changes that only make sense together.
--
-- The gym pays trainers three ways at once — a fixed salary, a percentage of
-- personal training sold, and a rate per session delivered — and which ones
-- apply varies by trainer. Nothing recorded any of it. `trainers` has carried
-- salary_in_paise and commission_pct since migration 015 and not one line of
-- code has ever read them: no payout is computed, none is stored, and there is
-- no way to say a trainer has been paid.
--
-- Commission is why the payment link belongs in the same migration. Commission
-- must accrue on money RECEIVED, not on packages created. Without a link from
-- a payment to the package it paid for, the only options are to pay commission
-- when a package is created — handing a trainer 20% of money the gym has not
-- collected — or to treat every payment by that member as PT revenue, which
-- counts membership fees twice. Both are cash leaving against revenue that
-- never arrived, which is a worse leak than the one this feature set out to
-- find.

-- ── The link ────────────────────────────────────────────────────────────────
--
-- Nullable, and deliberately not backfilled. Which historical payment covered
-- which package cannot be reconstructed honestly — matching on amount would
-- guess, and a guess here becomes a commission payment to a real person.
-- Existing rows stay NULL and are excluded from commission, which understates
-- rather than invents.
ALTER TABLE payments
    ADD COLUMN IF NOT EXISTS pt_package_id BIGINT REFERENCES pt_packages(id);

CREATE INDEX IF NOT EXISTS idx_payments_pt_package
    ON payments (pt_package_id) WHERE pt_package_id IS NOT NULL;

-- ── The third pay scheme ────────────────────────────────────────────────────
--
-- salary_in_paise and commission_pct already exist. This completes the set, so
-- a trainer can be on any combination of the three: the columns are additive
-- rather than a pay_type enum, because the gym confirmed some trainers are on
-- a base salary AND commission.
ALTER TABLE trainers
    ADD COLUMN IF NOT EXISTS per_session_in_paise BIGINT;

ALTER TABLE trainers
    ADD CONSTRAINT chk_trainers_per_session_nonneg
    CHECK (per_session_in_paise IS NULL OR per_session_in_paise >= 0);

-- ── Payouts ─────────────────────────────────────────────────────────────────
--
-- One row per trainer per period. The unique constraint is the point: paying
-- the same person twice for the same month is the single most expensive
-- mistake this table can prevent, and it is easy to make when two people share
-- a login at month end.
CREATE TABLE IF NOT EXISTS trainer_payouts (
    id           BIGSERIAL PRIMARY KEY,
    gym_id       BIGINT NOT NULL REFERENCES gyms(id),
    trainer_id   BIGINT NOT NULL REFERENCES trainers(id),

    period_start DATE NOT NULL,
    period_end   DATE NOT NULL,

    -- Each scheme kept separate. A trainer querying "why is this less than
    -- last month" needs to see which part moved, and one merged total cannot
    -- answer that.
    salary_in_paise     BIGINT NOT NULL DEFAULT 0,
    commission_in_paise BIGINT NOT NULL DEFAULT 0,
    sessions_in_paise   BIGINT NOT NULL DEFAULT 0,

    -- Deductions and one-offs. Signed: an advance recovered is negative.
    adjustment_in_paise BIGINT NOT NULL DEFAULT 0,
    adjustment_reason   TEXT,

    total_in_paise BIGINT NOT NULL DEFAULT 0,

    -- draft  → computed and reviewable, nothing has left the gym
    -- paid   → money handed over, recorded by a named person
    -- cancelled → abandoned before payment, kept for the audit trail
    status VARCHAR(20) NOT NULL DEFAULT 'draft',

    notes TEXT,

    paid_at         TIMESTAMPTZ,
    paid_by_user_id BIGINT REFERENCES users(id),
    payment_mode    VARCHAR(20),
    reference_number VARCHAR(100),

    created_by_user_id BIGINT NOT NULL REFERENCES users(id),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    CONSTRAINT chk_trainer_payouts_status
        CHECK (status IN ('draft', 'paid', 'cancelled')),
    CONSTRAINT chk_trainer_payouts_period
        CHECK (period_end >= period_start),
    -- A paid payout must say who paid it and when. A payment with no hand
    -- attached to it is the row nobody can explain six months later.
    CONSTRAINT chk_trainer_payouts_paid_consistency
        CHECK (
            (status = 'paid' AND paid_at IS NOT NULL AND paid_by_user_id IS NOT NULL)
            OR status <> 'paid'
        )
);

-- Only one live payout per trainer per period. Cancelled ones are excluded so
-- a mistake can be abandoned and redone.
CREATE UNIQUE INDEX IF NOT EXISTS uq_trainer_payouts_period
    ON trainer_payouts (gym_id, trainer_id, period_start, period_end)
    WHERE status <> 'cancelled';

CREATE INDEX IF NOT EXISTS idx_trainer_payouts_gym_status
    ON trainer_payouts (gym_id, status, period_end DESC);

-- ── Payout lines ────────────────────────────────────────────────────────────
--
-- What a total is made of. Without these, "commission Rs 1,000" is a number
-- nobody can check — not the owner approving it, and not the trainer being
-- asked to accept it. Every line names the package or session behind it.
--
-- Snapshotted at computation time, like invoice items: a package price that
-- changes later must never rewrite a payout that has been paid.
CREATE TABLE IF NOT EXISTS trainer_payout_lines (
    id        BIGSERIAL PRIMARY KEY,
    gym_id    BIGINT NOT NULL REFERENCES gyms(id),
    payout_id BIGINT NOT NULL REFERENCES trainer_payouts(id) ON DELETE CASCADE,

    -- salary | commission | session | adjustment
    kind VARCHAR(20) NOT NULL,

    -- The package or appointment this line came from, where there is one.
    reference_id BIGINT,

    description     TEXT   NOT NULL,
    amount_in_paise BIGINT NOT NULL,

    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    CONSTRAINT chk_trainer_payout_lines_kind
        CHECK (kind IN ('salary', 'commission', 'session', 'adjustment'))
);

CREATE INDEX IF NOT EXISTS idx_trainer_payout_lines_payout
    ON trainer_payout_lines (payout_id);
