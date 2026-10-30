-- Remove everything add.sql created for a gym:  psql -v gym=1 -f remove.sql
\set ON_ERROR_STOP on
BEGIN;
DELETE FROM payments WHERE gym_id = :gym AND member_id IN
  (SELECT id FROM members WHERE gym_id = :gym AND notes = 'Sample data');
DELETE FROM members WHERE gym_id = :gym AND notes = 'Sample data';
DELETE FROM membership_plans WHERE gym_id = :gym AND description = 'Sample plan'
  AND NOT EXISTS (SELECT 1 FROM members WHERE membership_plan_id = membership_plans.id);
COMMIT;
