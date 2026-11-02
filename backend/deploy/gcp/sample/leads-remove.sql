-- Remove what leads-add.sql created:  psql -v gym=1 -f leads-remove.sql
\set ON_ERROR_STOP on
BEGIN;
DELETE FROM leads WHERE gym_id = :gym AND notes = 'Sample data' AND converted_member_id IS NULL;
COMMIT;
