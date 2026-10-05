-- 037: which pricing tier each gym is actually on.
--
-- Every gym today gets every feature — the three-tier pricing sheet
-- (Normal / Medium / Premium) exists as a sales document but nothing in
-- the software checks it. This adds the one field that says which tier a
-- gym is paying for; internal/entitlements is what actually enforces it,
-- reading this column through the tenant context on every gated route.
--
-- Existing gyms default to 'premium', not 'normal': every gym already in
-- this database signed up when everything was free to use, so silently
-- downgrading them to Normal the moment this migration runs would take
-- features away nobody told them they'd lose. New gyms should be created
-- with an explicit tier going forward (see internal/devseed and
-- internal/auth's RegisterGym) — this default only protects the past.

BEGIN;

ALTER TABLE gyms
    ADD COLUMN IF NOT EXISTS plan_tier VARCHAR(20) NOT NULL DEFAULT 'premium'
        CHECK (plan_tier IN ('normal', 'medium', 'premium'));

COMMIT;
