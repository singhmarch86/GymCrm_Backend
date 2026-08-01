-- 013_classes_booking.sql
--
-- Classes, recurring schedules, materialized sessions, and bookings with
-- waitlist. See docs/FR-02-classes-booking.md for the business rules.
--
-- DATA SAFETY: purely additive — four new tables, no existing table altered.
-- Re-runnable via IF NOT EXISTS throughout.

BEGIN;

-- ─── class_types: the offering ───────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS class_types (
    id                bigserial PRIMARY KEY,
    gym_id            bigint      NOT NULL,
    name              varchar(100) NOT NULL,
    description       text,
    duration_minutes  integer     NOT NULL,
    default_capacity  integer     NOT NULL,
    is_active         boolean     NOT NULL DEFAULT true,
    created_at        timestamptz NOT NULL DEFAULT now(),
    updated_at        timestamptz NOT NULL DEFAULT now(),
    deleted_at        timestamptz,

    CONSTRAINT chk_class_types_duration_positive CHECK (duration_minutes > 0),
    CONSTRAINT chk_class_types_capacity_positive CHECK (default_capacity > 0)
);

CREATE INDEX IF NOT EXISTS idx_class_types_gym
    ON class_types (gym_id)
    WHERE deleted_at IS NULL;

COMMENT ON TABLE class_types IS
    'The class offering (Yoga, Zumba). Long-lived, edited rarely. See FR-02 §1.';

-- ─── class_schedules: the recurrence rule ────────────────────────────────────

CREATE TABLE IF NOT EXISTS class_schedules (
    id                bigserial PRIMARY KEY,
    gym_id            bigint      NOT NULL,
    class_type_id     bigint      NOT NULL REFERENCES class_types(id),

    day_of_week       smallint    NOT NULL,  -- 0=Sunday .. 6=Saturday
    start_time        time        NOT NULL,
    duration_minutes  integer     NOT NULL,
    capacity          integer     NOT NULL,
    trainer_user_id   bigint,                -- nullable: unassigned is valid, FR-02 §0.2

    effective_from    date        NOT NULL,
    effective_until   date,                  -- NULL = open-ended

    is_active         boolean     NOT NULL DEFAULT true,
    created_at        timestamptz NOT NULL DEFAULT now(),
    updated_at        timestamptz NOT NULL DEFAULT now(),
    deleted_at        timestamptz,

    CONSTRAINT chk_class_schedules_day CHECK (day_of_week BETWEEN 0 AND 6),
    CONSTRAINT chk_class_schedules_duration_positive CHECK (duration_minutes > 0),
    CONSTRAINT chk_class_schedules_capacity_positive CHECK (capacity > 0),
    CONSTRAINT chk_class_schedules_date_range CHECK (
        effective_until IS NULL OR effective_until >= effective_from
    )
);

CREATE INDEX IF NOT EXISTS idx_class_schedules_gym_active
    ON class_schedules (gym_id, is_active)
    WHERE deleted_at IS NULL;

COMMENT ON TABLE class_schedules IS
    'Recurrence rule: day/time/trainer/capacity. Editing this NEVER retroactively '
    'changes already-materialized sessions — see FR-02 §0.1 and §2.';

-- ─── class_sessions: one materialized occurrence ─────────────────────────────
--
-- Fields are COPIED from the schedule at generation time (capacity, trainer,
-- duration), then independently editable per-session. This is what makes a
-- substitute trainer or one-off capacity bump possible without touching the
-- recurrence rule or any other session. FR-02 §3.1.

CREATE TABLE IF NOT EXISTS class_sessions (
    id                bigserial PRIMARY KEY,
    gym_id            bigint      NOT NULL,
    schedule_id       bigint      REFERENCES class_schedules(id), -- nullable: ad-hoc sessions allowed
    class_type_id     bigint      NOT NULL REFERENCES class_types(id),

    session_date      date        NOT NULL,
    start_time        time        NOT NULL,
    duration_minutes  integer     NOT NULL,
    capacity          integer     NOT NULL,
    trainer_user_id   bigint,

    status            varchar(20) NOT NULL DEFAULT 'scheduled',

    created_at        timestamptz NOT NULL DEFAULT now(),
    updated_at        timestamptz NOT NULL DEFAULT now(),

    CONSTRAINT chk_class_sessions_status CHECK (
        status IN ('scheduled', 'cancelled', 'completed')
    ),
    CONSTRAINT chk_class_sessions_duration_positive CHECK (duration_minutes > 0),
    CONSTRAINT chk_class_sessions_capacity_positive CHECK (capacity > 0)
);

-- Generation idempotency: re-running the rolling-window generator for a date
-- range that already has sessions must never create duplicates. FR-02 §2.
CREATE UNIQUE INDEX IF NOT EXISTS idx_class_sessions_schedule_date
    ON class_sessions (schedule_id, session_date)
    WHERE schedule_id IS NOT NULL;

-- Dominant read: "what's on today / this week" for the booking screen.
CREATE INDEX IF NOT EXISTS idx_class_sessions_gym_date
    ON class_sessions (gym_id, session_date, start_time);

COMMENT ON TABLE class_sessions IS
    'One bookable occurrence. Capacity/trainer/duration are a snapshot from the '
    'schedule, not a live reference — see FR-02 §0.1, §3.1.';

-- ─── bookings: one member × one session ──────────────────────────────────────

CREATE TABLE IF NOT EXISTS bookings (
    id                  bigserial PRIMARY KEY,
    gym_id              bigint      NOT NULL,
    session_id          bigint      NOT NULL REFERENCES class_sessions(id),
    member_id           bigint      NOT NULL,

    status              varchar(20) NOT NULL DEFAULT 'booked',
    waitlist_position    integer,             -- only meaningful while status = 'waitlisted'

    booked_at           timestamptz NOT NULL DEFAULT now(),
    cancelled_at        timestamptz,
    cancel_reason        varchar(30),         -- 'member', 'late', 'session_cancelled' — FR-02 §3.3, §4.2

    created_at          timestamptz NOT NULL DEFAULT now(),
    updated_at          timestamptz NOT NULL DEFAULT now(),

    CONSTRAINT chk_bookings_status CHECK (
        status IN ('booked', 'waitlisted', 'cancelled', 'attended', 'no_show')
    )
);

-- A member may hold only one ACTIVE (booked/waitlisted) booking per session.
-- Rebooking after cancelling is fine — the partial predicate only covers the
-- live states. FR-02 §4.1.
CREATE UNIQUE INDEX IF NOT EXISTS idx_bookings_member_session_active
    ON bookings (session_id, member_id)
    WHERE status IN ('booked', 'waitlisted');

-- Waitlist promotion reads this in FIFO order. FR-02 §4.3.
CREATE INDEX IF NOT EXISTS idx_bookings_session_waitlist
    ON bookings (session_id, waitlist_position)
    WHERE status = 'waitlisted';

-- Member's own booking history / upcoming classes.
CREATE INDEX IF NOT EXISTS idx_bookings_member
    ON bookings (member_id, created_at DESC);

COMMENT ON TABLE bookings IS
    'One member''s claim on one session. waitlist_position is assigned once at '
    'join time and never renumbered on cancellation — FR-02 §4.3.';

COMMIT;
