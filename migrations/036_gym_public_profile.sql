-- 036: public advertisement profile for each gym.
--
-- Every gym in this system is a row in gyms (see internal/gyms/model.go —
-- what internal/branches treats as "a branch" is the same table, seen from
-- a chain's perspective). None of that record is meant to be shown to
-- anyone outside the gym's own staff. This adds the handful of fields a
-- public, unauthenticated advertisement page needs: a short tagline, a
-- longer description, a cover photo, and a slug for the page's own URL.
--
-- Deliberately NOT here: a shop, a product list, prices, or anything tying
-- this page to Archecommerce — this is a marketing page for the gym itself,
-- nothing transactional (see docs/manual-deck's own "What This Software
-- Does Not Do": no member-facing app, nothing this reuses that boundary).
--
-- published defaults to false: a gym exists in this table the moment it's
-- registered, long before anyone has written a tagline or picked a photo.
-- An empty advertisement page is worse than no page at all, so nothing is
-- publicly reachable until a human at the gym (or the platform, on their
-- behalf) explicitly turns it on.

BEGIN;

ALTER TABLE gyms
    ADD COLUMN IF NOT EXISTS public_slug        VARCHAR(120) UNIQUE,
    ADD COLUMN IF NOT EXISTS tagline             VARCHAR(200),
    ADD COLUMN IF NOT EXISTS public_description  TEXT,
    ADD COLUMN IF NOT EXISTS cover_photo_url      TEXT,
    ADD COLUMN IF NOT EXISTS amenities           JSONB        NOT NULL DEFAULT '[]',
    ADD COLUMN IF NOT EXISTS public_phone        VARCHAR(20),
    ADD COLUMN IF NOT EXISTS published           BOOLEAN      NOT NULL DEFAULT FALSE;

-- Public reads are always "give me the published gym at this slug" — never
-- by id (ids are also used internally, and predictable/enumerable; a slug
-- is the one identifier meant to leave the building).
CREATE INDEX IF NOT EXISTS idx_gyms_public_slug_published
    ON gyms (public_slug)
    WHERE published = TRUE;

COMMIT;
