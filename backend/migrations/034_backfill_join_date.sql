-- 034: backfill join_date, which nothing had ever written.
--
-- The column has existed since the first migration with a default of
-- CURRENT_DATE, but no Go model mapped it and the importer never inserted it.
-- Every member therefore carried the date their row was created, whatever
-- their real history: a gym of four-year veterans looked like it opened this
-- morning.
--
-- It was not merely cosmetic. The inactivity alerts skip anyone inside their
-- first 90 days, because "inactive 1 week" tells the wrong story about
-- somebody who joined nine days ago (FR-10 §4). With join_date always
-- effectively today, every member was permanently inside that window, and At
-- Risk raised zero inactivity alerts no matter how many members had stopped
-- coming. On the dev database that hid 200 of them.
--
-- The repair uses the earliest date the row can evidence: the first
-- attendance, the current term's start, and the creation timestamp. Whichever
-- is earliest is the closest defensible answer to "since when".
--
-- Deliberately conservative in two ways. It only ever moves a join_date
-- earlier, so a date somebody has since corrected by hand is never overwritten
-- with a guess. And it leaves rows alone when there is no earlier evidence at
-- all, rather than inventing a tenure — a member who genuinely joined today
-- should keep today.

BEGIN;

WITH evidence AS (
    SELECT m.id,
           LEAST(
               m.join_date,
               COALESCE(m.start_date,      m.join_date),
               COALESCE(m.created_at::date, m.join_date),
               COALESCE((SELECT MIN(a.checked_in_date)
                           FROM attendance a
                          WHERE a.member_id = m.id
                            AND a.gym_id = m.gym_id), m.join_date)
           ) AS earliest
      FROM members m
)
UPDATE members m
   SET join_date  = e.earliest,
       updated_at = m.updated_at   -- untouched: this corrects a record, it is
                                   -- not a change somebody made to the member
  FROM evidence e
 WHERE e.id = m.id
   AND e.earliest < m.join_date;

COMMIT;
