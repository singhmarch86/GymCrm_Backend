-- Backfill synthetic pipeline history for development seed leads.
--
-- WHY: time-in-stage analytics are derived from lead_activities stage_change
-- rows. Seeded leads were inserted at their final status with no transition
-- history, so the funnel has counts but no durations. This reconstructs a
-- plausible path to each lead's current stage so the analytics render.
--
-- THIS IS FABRICATED DATA. Every row is written with user_id = NULL (no acting
-- user) and a note that says so, so it is distinguishable from genuine activity
-- both in the database and in the app's timeline UI. Never run this against a
-- production database.
--
-- Idempotent: leads that already have stage_change history are skipped, so
-- rerunning cannot duplicate rows or clobber real transitions.

BEGIN;

WITH progression AS (
    SELECT ARRAY['new_lead','contacted','trial_scheduled','trial_completed','joined']::text[] AS stages
),
targets AS (
    SELECT
        l.id,
        l.gym_id,
        l.created_at,
        l.status = 'lost' AS is_lost,
        CASE
            -- A lost lead dropped out partway; vary the exit point by id so
            -- the losses aren't all clustered at the same stage.
            WHEN l.status = 'lost' THEN 1 + (l.id % 3)
            ELSE COALESCE(array_position(p.stages, l.status), 1) - 1
        END AS steps
    FROM leads l
    CROSS JOIN progression p
    WHERE l.deleted_at IS NULL
      AND NOT EXISTS (
          SELECT 1 FROM lead_activities la
          WHERE la.lead_id = l.id AND la.type = 'stage_change'
      )
)

-- Forward transitions: new_lead → … → current stage.
-- Timestamps are spread evenly across the lead's lifetime so each transition
-- lands after the previous one and durations come out positive.
INSERT INTO lead_activities (gym_id, lead_id, user_id, type, note, from_status, to_status, created_at)
SELECT
    t.gym_id,
    t.id,
    NULL::bigint, -- system-generated: no acting user
    'stage_change',
    'Backfilled history (synthetic development data)',
    p.stages[s],
    p.stages[s + 1],
    t.created_at + ((now() - t.created_at) * s / (t.steps + 1))
FROM targets t
CROSS JOIN progression p
CROSS JOIN LATERAL generate_series(1, t.steps) AS s
WHERE t.steps > 0

UNION ALL

-- Final exit transition for leads that were lost.
SELECT
    t.gym_id,
    t.id,
    NULL::bigint, -- system-generated: no acting user
    'stage_change',
    'Backfilled history (synthetic development data)',
    p.stages[t.steps + 1],
    'lost',
    t.created_at + ((now() - t.created_at) * (t.steps + 1) / (t.steps + 2))
FROM targets t
CROSS JOIN progression p
WHERE t.is_lost;

COMMIT;
