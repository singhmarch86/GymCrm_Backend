-- 025_counter_prompts.sql
-- FR-11: one line of context at the front desk, at the moment the member is
-- standing there.

BEGIN;

-- Insert-only record of what was shown. Two jobs: it powers the 7-day cooldown
-- (FR-11 §4), and it is the only way anyone will ever be able to answer
-- "does this actually work?" — which nobody can answer today.
CREATE TABLE IF NOT EXISTS counter_prompt_log (
    id              BIGSERIAL PRIMARY KEY,
    gym_id          BIGINT      NOT NULL REFERENCES gyms(id),
    member_id       BIGINT      NOT NULL REFERENCES members(id),

    prompt_kind     VARCHAR(30) NOT NULL,
    prompt_text     TEXT        NOT NULL,

    -- Who was at the desk. Not for blame — for working out later whether the
    -- prompts are reaching anyone.
    shown_by_user_id BIGINT     REFERENCES users(id),
    shown_at        TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    -- Optional on purpose (FR-11 §5): mandatory logging at a busy counter gets
    -- clicked through meaninglessly, which is worse than no data because it
    -- looks like data.
    acted           BOOLEAN     NOT NULL DEFAULT false,
    acted_at        TIMESTAMPTZ,
    action_note     TEXT,

    CONSTRAINT counter_prompt_kind_check CHECK (prompt_kind IN (
        'first_visit', 'welcome_back', 'alert', 'pt_low', 'restock', 'wallet_low'
    ))
);

-- The cooldown lookup: "has this member seen this kind in the last 7 days".
CREATE INDEX IF NOT EXISTS idx_counter_prompt_cooldown
    ON counter_prompt_log (gym_id, member_id, prompt_kind, shown_at DESC);

CREATE INDEX IF NOT EXISTS idx_counter_prompt_recent
    ON counter_prompt_log (gym_id, shown_at DESC);

COMMIT;
