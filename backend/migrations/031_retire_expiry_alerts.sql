-- 031: retire the expiry alerts (FR-20)
--
-- The renewals queue (FR-19 §4) owns membership expiry now. At Risk had been
-- computing the same thing since FR-03 and nobody removed it, so 240 of 470
-- open alerts duplicated the queue and 229 members sat on both screens.
--
-- Resolved, not deleted. The rows are the record that the gym was once told
-- about these members, which is exactly the history somebody goes looking for
-- when working out why a member left. Deleting them would erase that; closing
-- them takes it off the screen and keeps it on the timeline.
--
-- resolved_by stays NULL deliberately. No person resolved these — a rule did,
-- and putting whoever ran the migration in an audit column would be a lie.

UPDATE retention_alerts
   SET is_resolved  = true,
       resolved_at  = NOW(),
       resolved_by  = NULL,
       action_note  = 'superseded by the renewals queue (FR-20)'
 WHERE is_resolved = false
   AND alert_type IN ('expiring_in_3_days', 'expiring_today', 'expired_no_renewal');

-- The alert types stay valid in the schema. Nothing generates them from here
-- on — that is enforced in the scanner, not the database — but historical rows
-- must remain readable, and a future decision to bring one back should not
-- need a migration.
