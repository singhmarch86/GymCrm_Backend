-- 014_visitors_referrals.sql
--
-- Two acquisition-tracking features that were previously missing/stub:
--   visitors  — walk-in check-in/out log, distinct from leads (an enquiry)
--               and members (a paying signup). Converting a visitor to a
--               lead is explicit and optional, reusing leads.source='walk_in'
--               which already existed as a default before this migration.
--   referrals — member-to-member referral tracking. Reward is FREE DAYS
--               added to the referrer's membership, not cash — matches the
--               reward_days field already present in the Flutter Referral
--               model before any backend existed for it.
--
-- DATA SAFETY: purely additive — two new tables, no existing table altered.
-- Re-runnable via IF NOT EXISTS throughout.

BEGIN;

-- ─── visitors ─────────────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS visitors (
    id                  bigserial PRIMARY KEY,
    gym_id              bigint      NOT NULL,

    name                varchar(200) NOT NULL,
    phone               varchar(20),
    purpose             varchar(20)  NOT NULL DEFAULT 'trial',

    checked_in_at       timestamptz NOT NULL DEFAULT now(),
    checked_out_at      timestamptz,
    host_staff_user_id  bigint,

    converted_lead_id   bigint REFERENCES leads(id),

    notes               text,
    created_at          timestamptz NOT NULL DEFAULT now(),
    updated_at          timestamptz NOT NULL DEFAULT now(),

    CONSTRAINT chk_visitors_purpose CHECK (
        purpose IN ('trial', 'guest', 'tour', 'other')
    ),
    CONSTRAINT chk_visitors_checkout_after_checkin CHECK (
        checked_out_at IS NULL OR checked_out_at >= checked_in_at
    )
);

-- Dominant read: "who's visited today / this week."
CREATE INDEX IF NOT EXISTS idx_visitors_gym_checkin
    ON visitors (gym_id, checked_in_at DESC);

-- "Who's currently in the building" — still-checked-in visitors.
CREATE INDEX IF NOT EXISTS idx_visitors_gym_open
    ON visitors (gym_id, checked_in_at)
    WHERE checked_out_at IS NULL;

COMMENT ON TABLE visitors IS
    'Walk-in visit log — distinct from leads (an enquiry) and members (a '
    'signup). converted_lead_id is set only when staff explicitly convert a '
    'visit into a lead; nothing here happens automatically.';

-- ─── referrals ────────────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS referrals (
    id                   bigserial PRIMARY KEY,
    gym_id               bigint      NOT NULL,

    referrer_member_id   bigint      NOT NULL,

    referred_name        varchar(200) NOT NULL,
    referred_phone       varchar(20)  NOT NULL,
    referred_lead_id     bigint REFERENCES leads(id),
    referred_member_id   bigint,

    status               varchar(20) NOT NULL DEFAULT 'pending',

    -- Reward is FREE DAYS added to the referrer's membership on payout, not
    -- cash — matches the Flutter model's reward_days field, predating any
    -- backend for this feature.
    reward_days          integer,
    reward_given_at      timestamptz,

    notes                text,
    created_by_user_id   bigint      NOT NULL,
    created_at           timestamptz NOT NULL DEFAULT now(),
    updated_at           timestamptz NOT NULL DEFAULT now(),

    CONSTRAINT chk_referrals_status CHECK (
        status IN ('pending', 'joined', 'rewarded', 'expired')
    ),
    CONSTRAINT chk_referrals_reward_days_positive CHECK (
        reward_days IS NULL OR reward_days > 0
    ),
    -- Rewarded implies the days and the timestamp are both actually set —
    -- a rewarded referral with no recorded payout is a data-integrity bug
    -- waiting to be asked about in six months.
    CONSTRAINT chk_referrals_rewarded_has_payout CHECK (
        status != 'rewarded' OR (reward_days IS NOT NULL AND reward_given_at IS NOT NULL)
    )
);

CREATE INDEX IF NOT EXISTS idx_referrals_gym_status
    ON referrals (gym_id, status, created_at DESC);

-- A member's own referral history.
CREATE INDEX IF NOT EXISTS idx_referrals_referrer
    ON referrals (referrer_member_id, created_at DESC);

COMMENT ON TABLE referrals IS
    'Member-to-member referral tracking. Reward is free membership days '
    'credited to the referrer on payout — never cash, never automatic.';

COMMIT;
