-- 029: collections (FR-19 §3)
--
-- The collections queue needs to know two things the schema cannot currently
-- answer: has anybody chased this due, and did the member promise a date.
--
-- Without the first, "nobody has chased these" — the group that justifies the
-- whole screen, and the direct analogue of Unattended in the lead workflow —
-- cannot be computed at all. A due nobody has mentioned to anybody is
-- invisible today.
--
-- No backfill. Every existing pending payment starts with no contact recorded,
-- which puts all 45 in "nobody has chased these" on the first load. That is
-- correct: nobody has, because there was nowhere to record it.

-- Insert-only, exactly like stock_movements and lead_activities. A collection
-- attempt is a historical fact; correcting it means recording another one, not
-- editing the past.
CREATE TABLE IF NOT EXISTS payment_activities (
    id          BIGSERIAL PRIMARY KEY,
    gym_id      BIGINT NOT NULL REFERENCES gyms(id),
    payment_id  BIGINT NOT NULL REFERENCES payments(id) ON DELETE CASCADE,

    -- contact  — somebody spoke to (or tried to reach) the member
    -- promise  — the member agreed a date to pay
    -- write_off — the gym gave up on this money, with a reason
    type        VARCHAR(20) NOT NULL
                CHECK (type IN ('contact', 'promise', 'write_off')),

    -- How the contact happened. Null for promise and write_off, which are
    -- outcomes rather than channels.
    channel     VARCHAR(20)
                CHECK (channel IS NULL OR channel IN ('call', 'message', 'in_person')),

    -- Whether the member was actually reached. A call that rang out is work
    -- done and worth recording, but it is not contact, and conflating the two
    -- would make a bad week look like a good one — the same distinction the
    -- lead funnel draws between calls and reached.
    reached     BOOLEAN,

    -- Only meaningful for type='promise'.
    promised_on DATE,

    note        TEXT,

    -- Never nullable. Unattributed work is tolerated where a ledger predates
    -- the login (see staffwork), but there is no such history here — this
    -- table starts empty, so every row can and must name who did it.
    user_id     BIGINT NOT NULL REFERENCES users(id),
    created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- The queue reads the newest activity per payment, per gym.
CREATE INDEX IF NOT EXISTS idx_payment_activities_payment
    ON payment_activities (payment_id, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_payment_activities_gym_type
    ON payment_activities (gym_id, type, created_at DESC);

-- A written-off due must leave the queue and stop counting as receivable.
-- Reusing 'paid' would inflate revenue with money that never arrived, so the
-- status enum gains a fourth value.
ALTER TABLE payments DROP CONSTRAINT IF EXISTS payments_status_check;
ALTER TABLE payments ADD CONSTRAINT payments_status_check
    CHECK (status IN ('pending', 'paid', 'overdue', 'written_off'));

-- The paid-consistency rule was written when 'paid' was the only status that
-- carried a date. It still holds — written_off has no paid_date and no
-- payment_mode, which the existing constraint already requires of anything
-- that is not 'paid'. Left alone deliberately.
