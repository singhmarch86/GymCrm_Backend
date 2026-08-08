-- 021_branch_targets_transfers.sql
--
-- Gives branches operational meaning beyond isolation: targets to be measured
-- against, and a real transfer path for members who move between locations.
-- See docs/FR-06-multi-location.md.

-- ── Targets ───────────────────────────────────────────────────────────────────
-- Without a target, a league table only says who is biggest — which usually
-- just reflects branch size. Attainment against a target is what actually tells
-- an owner which branch is performing.
ALTER TABLE gyms ADD COLUMN IF NOT EXISTS monthly_revenue_target_in_paise bigint NOT NULL DEFAULT 0;
ALTER TABLE gyms ADD COLUMN IF NOT EXISTS monthly_member_target integer NOT NULL DEFAULT 0;

-- ── Member transfers between branches ─────────────────────────────────────────
-- Insert-only audit of a member moving location.
--
-- Deliberate rule: the member record moves, their financial history does NOT.
-- Payments and invoices stay with the branch that issued them, because that
-- branch already recognised the revenue and filed it under its own GSTIN —
-- moving them would rewrite two sets of books (FR-04 §1, FR-06 §3).
CREATE TABLE IF NOT EXISTS member_branch_transfers (
    id                   bigserial PRIMARY KEY,
    member_id            bigint      NOT NULL,
    from_gym_id          bigint      NOT NULL,
    to_gym_id            bigint      NOT NULL,
    reason               text,
    transferred_by_user_id bigint    NOT NULL,
    created_at           timestamptz NOT NULL DEFAULT now(),

    CONSTRAINT chk_transfer_different_branch CHECK (from_gym_id <> to_gym_id)
);

CREATE INDEX IF NOT EXISTS idx_member_transfers_member ON member_branch_transfers (member_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_member_transfers_to ON member_branch_transfers (to_gym_id, created_at DESC);
