-- 012_membership_lifecycle.sql
--
-- Membership lifecycle: freeze, unfreeze, upgrade, transfer, terminate.
-- See docs/FR-01-membership-lifecycle.md for the business rules these support.
--
-- DATA SAFETY: this migration runs against a live database (151 members).
-- Every ALTER uses IF NOT EXISTS; every new column is either nullable or has a
-- DEFAULT, so no existing row is invalidated. No existing column is dropped,
-- renamed, or retyped. Re-runnable.

BEGIN;

-- ─── members: current lifecycle state ────────────────────────────────────────
-- The member row holds CURRENT state only. History lives in membership_events.

ALTER TABLE members
    ADD COLUMN IF NOT EXISTS frozen_from          date,
    ADD COLUMN IF NOT EXISTS frozen_until         date,
    ADD COLUMN IF NOT EXISTS freeze_days_used_ytd integer NOT NULL DEFAULT 0,
    ADD COLUMN IF NOT EXISTS freeze_year_start    date,
    ADD COLUMN IF NOT EXISTS terminated_at        date,
    ADD COLUMN IF NOT EXISTS termination_reason   text;

COMMENT ON COLUMN members.frozen_from IS
    'Start of the current freeze window. NULL when not frozen.';
COMMENT ON COLUMN members.frozen_until IS
    'Requested end of the current freeze. Member auto-thaws once this date passes; '
    'an early unfreeze recalculates the extension to days actually used (FR-01 §1).';
COMMENT ON COLUMN members.freeze_days_used_ytd IS
    'Days frozen so far in the current membership year, debited by ACTUAL days used. '
    'Resets when freeze_year_start rolls to the next join_date anniversary.';
COMMENT ON COLUMN members.freeze_year_start IS
    'Anniversary date the current freeze allowance is measured from. NULL until first freeze.';

-- members_status_check predates this migration and allowed only
-- active/expired/inactive/churned. Lifecycle adds two more states, so the
-- constraint is widened — never narrowed, so no existing row can be invalidated.
ALTER TABLE members DROP CONSTRAINT IF EXISTS members_status_check;
ALTER TABLE members ADD CONSTRAINT members_status_check CHECK (
    status IN ('active', 'expired', 'inactive', 'churned', 'frozen', 'terminated')
);

-- Partial index: only frozen members are ever scanned for auto-thaw.
CREATE INDEX IF NOT EXISTS idx_members_frozen_until
    ON members (frozen_until)
    WHERE deleted_at IS NULL AND frozen_until IS NOT NULL;

-- ─── membership_events: immutable audit ──────────────────────────────────────
-- One row per lifecycle operation. Never UPDATEd, never DELETEd, never
-- soft-deleted — same contract as the renewals table.
--
-- A transfer writes TWO rows (transfer_out on the source, transfer_in on the
-- target), each pointing at the other via related_member_id, so the full chain
-- of a resold membership is always reconstructable.

CREATE TABLE IF NOT EXISTS membership_events (
    id                       bigserial PRIMARY KEY,
    gym_id                   bigint      NOT NULL,
    member_id                bigint      NOT NULL,

    event_type               varchar(20) NOT NULL,
    effective_date           date        NOT NULL,

    -- State captured either side of the operation. Nullable because not every
    -- event type touches every field (a freeze does not change the plan).
    old_plan_id              bigint,
    new_plan_id              bigint,
    old_expiry_date          date,
    new_expiry_date          date,
    old_status               varchar(20),
    new_status               varchar(20),

    -- Freeze-specific
    freeze_start             date,
    freeze_end               date,
    freeze_days              integer,

    -- Money, in paise, matching renewals.amount_paid_in_paise.
    -- amount_due_in_paise:    positive = member owes (upgrade delta, fees)
    -- amount_credit_in_paise: positive = member is owed (downgrade credit, refund)
    -- Neither is collected or paid here — lifecycle records, payments moves money.
    amount_due_in_paise      bigint      NOT NULL DEFAULT 0,
    amount_credit_in_paise   bigint      NOT NULL DEFAULT 0,
    fee_in_paise             bigint      NOT NULL DEFAULT 0,

    -- Transfer pairing
    related_member_id        bigint,

    reason                   text,
    notes                    text,
    performed_by_user_id     bigint      NOT NULL,
    created_at               timestamptz NOT NULL DEFAULT now(),

    CONSTRAINT chk_membership_events_type CHECK (
        event_type IN ('freeze', 'unfreeze', 'upgrade', 'transfer_out', 'transfer_in', 'terminate')
    ),
    CONSTRAINT chk_membership_events_freeze_window CHECK (
        freeze_end IS NULL OR freeze_start IS NULL OR freeze_end >= freeze_start
    ),
    CONSTRAINT chk_membership_events_money_nonneg CHECK (
        amount_due_in_paise >= 0 AND amount_credit_in_paise >= 0 AND fee_in_paise >= 0
    ),
    -- A transfer is meaningless without its counterpart.
    CONSTRAINT chk_membership_events_transfer_pairing CHECK (
        event_type NOT IN ('transfer_out', 'transfer_in') OR related_member_id IS NOT NULL
    )
);

COMMENT ON TABLE membership_events IS
    'Immutable audit of membership state transitions. Insert-only: never updated or deleted. '
    'members holds current state; this table holds how it got there. See docs/FR-01-membership-lifecycle.md.';

-- Member timeline — the dominant read pattern (member detail screen).
CREATE INDEX IF NOT EXISTS idx_membership_events_member
    ON membership_events (member_id, effective_date DESC, id DESC);

-- Gym-wide reporting by type and date.
CREATE INDEX IF NOT EXISTS idx_membership_events_gym_type_date
    ON membership_events (gym_id, event_type, effective_date DESC);

-- Follow a transferred membership across members.
CREATE INDEX IF NOT EXISTS idx_membership_events_related
    ON membership_events (related_member_id)
    WHERE related_member_id IS NOT NULL;

-- Staff attribution, mirroring the retention_alerts accountability work in 011.
CREATE INDEX IF NOT EXISTS idx_membership_events_performed_by
    ON membership_events (performed_by_user_id, effective_date DESC);

COMMIT;
