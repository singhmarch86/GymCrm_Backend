-- Somebody to call.
--
-- The strongest case in the whole member form and the last one missing: right
-- now a member collapses on the gym floor and the software has nobody to ring.
-- Every other field on that form is about selling to them or reporting on
-- them; this one is the only field that exists for their sake.

ALTER TABLE members ADD COLUMN IF NOT EXISTS emergency_contact_name  VARCHAR(200);
ALTER TABLE members ADD COLUMN IF NOT EXISTS emergency_contact_phone VARCHAR(20);

-- Two columns, not three. A "relationship" field was considered and dropped:
-- in the moment somebody needs this, whether the number belongs to a spouse or
-- a brother changes nothing about what you do with it, and it is one more
-- question asked at a counter while somebody waits to join.

-- No index. This is never searched or filtered — it is read once, for one
-- member, in an emergency. An index here would cost every write and serve no
-- read that will ever happen.

-- Nullable, no backfill, no validation beyond length. 809 existing members
-- have no emergency contact and that is simply true; inventing one, or making
-- the column NOT NULL and forcing a placeholder, would turn a blank into a
-- lie at exactly the moment somebody is relying on it.
