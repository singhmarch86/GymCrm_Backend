-- 038: platform (vendor) console — FR-12.
--
-- Platform admins are NOT users: users.gym_id is NOT NULL and a third value in
-- users.role would be one UPDATE away from cross-tenant access (FR-12 §1).

BEGIN;

CREATE TABLE IF NOT EXISTS platform_admins (
    id               bigserial PRIMARY KEY,
    email            varchar(200) NOT NULL,
    name             varchar(200) NOT NULL,
    password_hash    text         NOT NULL,
    -- Base32 TOTP secret. Generated at enrolment, only usable once
    -- totp_confirmed_at is set (an unconfirmed secret is never activated).
    totp_secret      varchar(64),
    totp_confirmed_at timestamptz,
    -- Last accepted 30s step: a code can never be accepted twice (§10).
    totp_last_step   bigint       NOT NULL DEFAULT 0,
    failed_attempts  integer      NOT NULL DEFAULT 0,
    locked_until     timestamptz,
    status           varchar(20)  NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'disabled')),
    created_by       bigint REFERENCES platform_admins(id),
    created_at       timestamptz  NOT NULL DEFAULT now(),
    updated_at       timestamptz  NOT NULL DEFAULT now()
);
CREATE UNIQUE INDEX IF NOT EXISTS idx_platform_admins_email ON platform_admins (LOWER(email));

-- Ten single-use recovery codes per admin, bcrypt-hashed like a password.
CREATE TABLE IF NOT EXISTS platform_recovery_codes (
    id        bigserial PRIMARY KEY,
    admin_id  bigint      NOT NULL REFERENCES platform_admins(id) ON DELETE CASCADE,
    code_hash text        NOT NULL,
    used_at   timestamptz
);
CREATE INDEX IF NOT EXISTS idx_platform_recovery_admin ON platform_recovery_codes (admin_id) WHERE used_at IS NULL;

-- Every support access (§7). Insert-only — see trigger below.
CREATE TABLE IF NOT EXISTS platform_access_log (
    id          bigserial PRIMARY KEY,
    admin_id    bigint      NOT NULL REFERENCES platform_admins(id),
    gym_id      bigint      NOT NULL REFERENCES gyms(id),
    reason      text        NOT NULL,
    started_at  timestamptz NOT NULL DEFAULT now(),
    expires_at  timestamptz NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_platform_access_gym ON platform_access_log (gym_id, started_at DESC);
CREATE INDEX IF NOT EXISTS idx_platform_access_admin ON platform_access_log (admin_id, started_at DESC);

-- Every other cross-tenant act: create/suspend/resume/plan/subscription, admin
-- creation and 2FA resets. Insert-only.
CREATE TABLE IF NOT EXISTS platform_action_log (
    id         bigserial PRIMARY KEY,
    admin_id   bigint      NOT NULL REFERENCES platform_admins(id),
    gym_id     bigint REFERENCES gyms(id),
    action     varchar(40) NOT NULL,
    detail     text,
    created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_platform_action_gym ON platform_action_log (gym_id, created_at DESC);

-- "A log the accused can edit is not a log" (§7): refuse UPDATE and DELETE.
CREATE OR REPLACE FUNCTION platform_log_insert_only() RETURNS trigger AS $$
BEGIN
    RAISE EXCEPTION '% is insert-only', TG_TABLE_NAME;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_platform_access_log_immutable ON platform_access_log;
CREATE TRIGGER trg_platform_access_log_immutable
    BEFORE UPDATE OR DELETE ON platform_access_log
    FOR EACH ROW EXECUTE FUNCTION platform_log_insert_only();

DROP TRIGGER IF EXISTS trg_platform_action_log_immutable ON platform_action_log;
CREATE TRIGGER trg_platform_action_log_immutable
    BEFORE UPDATE OR DELETE ON platform_action_log
    FOR EACH ROW EXECUTE FUNCTION platform_log_insert_only();

-- Vendor-level fields on a gym (§8): why it is suspended, and subscription.
ALTER TABLE gyms ADD COLUMN IF NOT EXISTS suspended_reason text;
ALTER TABLE gyms ADD COLUMN IF NOT EXISTS subscription_status varchar(20) NOT NULL DEFAULT 'active'
    CHECK (subscription_status IN ('trial', 'active', 'past_due', 'cancelled'));

COMMIT;
