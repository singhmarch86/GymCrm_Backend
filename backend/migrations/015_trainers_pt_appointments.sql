-- 015_trainers_pt_appointments.sql
--
-- Three parity items completed together: Instructor/trainer management
-- (was a stub), Personal training packages (was a stub), and Appointment
-- booking (was missing — this is the calendar primitive for it).
-- See docs/FR-03-trainers-pt-appointments.md.
--
-- trainers is deliberately separate from users — a trainer here is a roster
-- entry with compensation details, not necessarily a login account. It is
-- also unrelated to class_schedules.trainer_user_id (migration 013), which
-- stays a users FK for group-class coverage. See FR-03 §0.
--
-- DATA SAFETY: purely additive — three new tables, no existing table
-- altered. Re-runnable via IF NOT EXISTS throughout.

BEGIN;

-- ─── trainers ─────────────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS trainers (
    id                bigserial PRIMARY KEY,
    gym_id            bigint       NOT NULL,

    first_name        varchar(100) NOT NULL,
    last_name         varchar(100) NOT NULL,
    phone             varchar(20)  NOT NULL,
    email             varchar(200),
    specialization    varchar(100),

    status            varchar(20)  NOT NULL DEFAULT 'active',
    salary_in_paise   bigint,
    commission_pct    numeric(5,2),

    created_at        timestamptz  NOT NULL DEFAULT now(),
    updated_at        timestamptz  NOT NULL DEFAULT now(),
    deleted_at        timestamptz,

    CONSTRAINT chk_trainers_status CHECK (status IN ('active', 'inactive')),
    CONSTRAINT chk_trainers_commission_range CHECK (
        commission_pct IS NULL OR (commission_pct >= 0 AND commission_pct <= 100)
    )
);

CREATE INDEX IF NOT EXISTS idx_trainers_gym
    ON trainers (gym_id)
    WHERE deleted_at IS NULL;

COMMENT ON TABLE trainers IS
    'PT roster with compensation details. Not a users row — many trainers '
    'never log into the app. Unrelated to class_schedules.trainer_user_id. '
    'See FR-03 §0.';

-- ─── pt_packages ──────────────────────────────────────────────────────────────
--
-- One row IS the sold package — a session-credit counter, not a catalog
-- entry. sessions_used only increments when an appointment against this
-- package is completed (see pt_appointments below), never at purchase.

CREATE TABLE IF NOT EXISTS pt_packages (
    id                bigserial PRIMARY KEY,
    gym_id            bigint       NOT NULL,
    member_id         bigint       NOT NULL,
    trainer_id        bigint       NOT NULL REFERENCES trainers(id),

    package_name      varchar(150) NOT NULL,
    total_sessions    integer      NOT NULL,
    sessions_used     integer      NOT NULL DEFAULT 0,
    amount_in_paise   bigint       NOT NULL,
    expiry_date       date,

    status            varchar(20)  NOT NULL DEFAULT 'active',

    created_at        timestamptz  NOT NULL DEFAULT now(),
    updated_at        timestamptz  NOT NULL DEFAULT now(),

    CONSTRAINT chk_pt_packages_status CHECK (status IN ('active', 'expired', 'cancelled')),
    CONSTRAINT chk_pt_packages_total_positive CHECK (total_sessions > 0),
    CONSTRAINT chk_pt_packages_used_nonneg CHECK (sessions_used >= 0),
    CONSTRAINT chk_pt_packages_used_not_over CHECK (sessions_used <= total_sessions),
    CONSTRAINT chk_pt_packages_amount_nonneg CHECK (amount_in_paise >= 0)
);

CREATE INDEX IF NOT EXISTS idx_pt_packages_member
    ON pt_packages (member_id, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_pt_packages_trainer
    ON pt_packages (trainer_id, created_at DESC);

COMMENT ON TABLE pt_packages IS
    'A sold PT package. sessions_used increments only when an appointment '
    'against it is completed — never at purchase or booking. FR-03 §2.';

-- ─── pt_appointments ──────────────────────────────────────────────────────────
--
-- Booking never checks or reserves a credit; the guard is on completing an
-- appointment, which is the one place a session credit is actually consumed.
-- No double-booking detection in v1 — see FR-03 §3, §4.

CREATE TABLE IF NOT EXISTS pt_appointments (
    id                bigserial PRIMARY KEY,
    gym_id            bigint       NOT NULL,
    pt_package_id     bigint       NOT NULL REFERENCES pt_packages(id),
    trainer_id        bigint       NOT NULL REFERENCES trainers(id),
    member_id         bigint       NOT NULL, -- denormalized off the package for convenient querying

    scheduled_at      timestamptz  NOT NULL,
    duration_minutes  integer      NOT NULL DEFAULT 60,
    status            varchar(20)  NOT NULL DEFAULT 'scheduled',
    notes             text,

    created_by_user_id bigint      NOT NULL,
    created_at        timestamptz  NOT NULL DEFAULT now(),
    updated_at        timestamptz  NOT NULL DEFAULT now(),

    CONSTRAINT chk_pt_appointments_status CHECK (
        status IN ('scheduled', 'completed', 'cancelled', 'no_show')
    ),
    CONSTRAINT chk_pt_appointments_duration_positive CHECK (duration_minutes > 0)
);

-- Dominant read: a trainer's or member's upcoming schedule.
CREATE INDEX IF NOT EXISTS idx_pt_appointments_trainer_time
    ON pt_appointments (trainer_id, scheduled_at);

CREATE INDEX IF NOT EXISTS idx_pt_appointments_member_time
    ON pt_appointments (member_id, scheduled_at DESC);

CREATE INDEX IF NOT EXISTS idx_pt_appointments_package
    ON pt_appointments (pt_package_id);

COMMENT ON TABLE pt_appointments IS
    'A 1:1 trainer/member booking. Completing one increments the linked '
    'package''s sessions_used; booking and cancelling do not touch it. '
    'FR-03 §3.';

COMMIT;
