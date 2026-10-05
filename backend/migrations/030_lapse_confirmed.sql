-- 030: confirming a lapse (FR-19 §4)
--
-- The renewals queue needs a way for an item to leave it without being
-- renewed. Otherwise every member who genuinely walked away sits in the queue
-- forever, and a queue that cannot reach zero stops being read (FR-19 §1).
--
-- Reuses membership_events rather than adding a table: a lapse is a membership
-- lifecycle fact, it belongs on the member's timeline next to freezes and
-- upgrades, and the reason column already exists. The only thing missing was
-- permission for the type.
--
-- Deliberately NOT 'terminate'. Terminating is ending a live membership the
-- gym decided to end; confirming a lapse is recording that somebody did not
-- come back. Folding them together would lose the distinction on the timeline
-- and in every count built from it.

ALTER TABLE membership_events DROP CONSTRAINT IF EXISTS chk_membership_events_type;
ALTER TABLE membership_events ADD CONSTRAINT chk_membership_events_type
    CHECK (event_type IN (
        'freeze', 'unfreeze', 'upgrade',
        'transfer_out', 'transfer_in',
        'terminate',
        'lapse_confirmed'
    ));

-- No backfill and no status change here. Confirming a lapse sets the member's
-- status to 'churned' in application code, which is where the existing
-- lifecycle rules live — doing it in SQL would bypass them.
