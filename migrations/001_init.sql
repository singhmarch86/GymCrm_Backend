-- ============================================================
-- Migration: 001_init.sql
-- Punjab Gym SaaS — V1 schema
-- Run via: golang-migrate
-- ============================================================

-- ── GYMS (tenants) ──────────────────────────────────────────
CREATE TABLE gyms (
    id          BIGSERIAL PRIMARY KEY,
    name        VARCHAR(200)  NOT NULL,
    owner_name  VARCHAR(200)  NOT NULL,
    phone       VARCHAR(20)   NOT NULL,
    email       VARCHAR(200),
    address     TEXT,
    city        VARCHAR(100)  NOT NULL DEFAULT 'Ludhiana',
    state       VARCHAR(100)  NOT NULL DEFAULT 'Punjab',
    status      VARCHAR(20)   NOT NULL DEFAULT 'active'
                              CHECK (status IN ('active', 'suspended', 'inactive')),
    created_at  TIMESTAMPTZ   NOT NULL DEFAULT NOW(),
    updated_at  TIMESTAMPTZ   NOT NULL DEFAULT NOW()
);

CREATE UNIQUE INDEX idx_gyms_phone ON gyms (phone);
CREATE UNIQUE INDEX idx_gyms_email ON gyms (email) WHERE email IS NOT NULL;
CREATE INDEX idx_gyms_status ON gyms (status);

-- ── USERS (owners + staff) ───────────────────────────────────
CREATE TABLE users (
    id            BIGSERIAL PRIMARY KEY,
    gym_id        BIGINT        NOT NULL REFERENCES gyms(id),
    name          VARCHAR(200)  NOT NULL,
    phone         VARCHAR(20)   NOT NULL,
    email         VARCHAR(200),
    password_hash VARCHAR(255)  NOT NULL,
    role          VARCHAR(20)   NOT NULL DEFAULT 'staff'
                                CHECK (role IN ('owner', 'staff')),
    status        VARCHAR(20)   NOT NULL DEFAULT 'active'
                                CHECK (status IN ('active', 'inactive')),
    created_at    TIMESTAMPTZ   NOT NULL DEFAULT NOW(),
    updated_at    TIMESTAMPTZ   NOT NULL DEFAULT NOW()
);

-- One phone number per gym (not globally unique — same phone can be owner of two gyms)
CREATE UNIQUE INDEX idx_users_gym_phone ON users (gym_id, phone);
CREATE INDEX idx_users_gym_id ON users (gym_id);
CREATE INDEX idx_users_role ON users (gym_id, role);

-- ── REFRESH TOKENS ───────────────────────────────────────────
CREATE TABLE refresh_tokens (
    id          BIGSERIAL PRIMARY KEY,
    user_id     BIGINT        NOT NULL REFERENCES users(id),
    gym_id      BIGINT        NOT NULL REFERENCES gyms(id), -- denormalised for fast tenant check
    token_hash  VARCHAR(255)  NOT NULL,
    expires_at  TIMESTAMPTZ   NOT NULL,
    revoked_at  TIMESTAMPTZ,
    created_at  TIMESTAMPTZ   NOT NULL DEFAULT NOW()
);

CREATE UNIQUE INDEX idx_refresh_tokens_hash ON refresh_tokens (token_hash);
CREATE INDEX idx_refresh_tokens_user ON refresh_tokens (user_id);
-- Partial index: only live tokens need fast lookup
CREATE INDEX idx_refresh_tokens_active ON refresh_tokens (user_id, expires_at)
    WHERE revoked_at IS NULL;

-- ── MEMBERS ──────────────────────────────────────────────────
CREATE TABLE members (
    id            BIGSERIAL PRIMARY KEY,
    gym_id        BIGINT        NOT NULL REFERENCES gyms(id),
    name          VARCHAR(200)  NOT NULL,
    phone         VARCHAR(20)   NOT NULL,
    email         VARCHAR(200),
    date_of_birth DATE,
    gender        VARCHAR(10)   CHECK (gender IN ('male', 'female', 'other')),
    address       TEXT,
    join_date     DATE          NOT NULL DEFAULT CURRENT_DATE,
    status        VARCHAR(20)   NOT NULL DEFAULT 'active'
                                CHECK (status IN ('active', 'expired', 'inactive', 'churned')),
    notes         TEXT,
    created_at    TIMESTAMPTZ   NOT NULL DEFAULT NOW(),
    updated_at    TIMESTAMPTZ   NOT NULL DEFAULT NOW(),
    deleted_at    TIMESTAMPTZ   -- soft delete
);

-- Phone unique per gym, only among non-deleted rows
CREATE UNIQUE INDEX idx_members_gym_phone
    ON members (gym_id, phone)
    WHERE deleted_at IS NULL;

-- Core tenant query index
CREATE INDEX idx_members_gym_status ON members (gym_id, status)
    WHERE deleted_at IS NULL;

-- Search by name within a gym (ILIKE uses this via pg_trgm in V2; plain index helps prefix search)
CREATE INDEX idx_members_gym_name ON members (gym_id, name)
    WHERE deleted_at IS NULL;

-- Soft delete index (GORM needs this for WHERE deleted_at IS NULL queries)
CREATE INDEX idx_members_deleted_at ON members (deleted_at);

-- ── MEMBERSHIP PLANS ─────────────────────────────────────────
CREATE TABLE membership_plans (
    id              BIGSERIAL PRIMARY KEY,
    gym_id          BIGINT        NOT NULL REFERENCES gyms(id),
    name            VARCHAR(200)  NOT NULL,
    duration_days   INT           NOT NULL CHECK (duration_days > 0),
    price_in_paise  BIGINT        NOT NULL CHECK (price_in_paise >= 0),
    description     TEXT,
    is_active       BOOLEAN       NOT NULL DEFAULT TRUE,
    created_at      TIMESTAMPTZ   NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMPTZ   NOT NULL DEFAULT NOW(),
    deleted_at      TIMESTAMPTZ   -- soft delete
);

CREATE INDEX idx_plans_gym_active ON membership_plans (gym_id, is_active)
    WHERE deleted_at IS NULL;

-- ── RENEWALS ─────────────────────────────────────────────────
CREATE TABLE renewals (
    id               BIGSERIAL PRIMARY KEY,
    gym_id           BIGINT        NOT NULL REFERENCES gyms(id),
    member_id        BIGINT        NOT NULL REFERENCES members(id),
    plan_id          BIGINT        NOT NULL REFERENCES membership_plans(id),
    start_date       DATE          NOT NULL,
    end_date         DATE          NOT NULL,
    paid_amount_in_paise BIGINT    NOT NULL CHECK (paid_amount_in_paise >= 0),
    payment_mode     VARCHAR(30)   NOT NULL DEFAULT 'cash'
                                   CHECK (payment_mode IN ('cash', 'upi', 'other')),
    status           VARCHAR(20)   NOT NULL DEFAULT 'active'
                                   CHECK (status IN ('active', 'expired', 'cancelled')),
    notes            TEXT,
    created_by       BIGINT        NOT NULL REFERENCES users(id),
    created_at       TIMESTAMPTZ   NOT NULL DEFAULT NOW(),
    updated_at       TIMESTAMPTZ   NOT NULL DEFAULT NOW(),

    CONSTRAINT chk_renewal_dates CHECK (end_date > start_date)
);

-- Core tenant query: all renewals for a gym
CREATE INDEX idx_renewals_gym ON renewals (gym_id, member_id);

-- Expiry queries: "who is expiring this week?" — used heavily
CREATE INDEX idx_renewals_gym_expiry ON renewals (gym_id, end_date, status);

-- Member renewal history (most recent first)
CREATE INDEX idx_renewals_member ON renewals (member_id, end_date DESC);

-- Active renewals lookup (most frequent query pattern)
CREATE INDEX idx_renewals_active ON renewals (gym_id, status, end_date)
    WHERE status = 'active';

-- ── ATTENDANCE ───────────────────────────────────────────────
CREATE TABLE attendance (
    id               BIGSERIAL PRIMARY KEY,
    gym_id           BIGINT        NOT NULL REFERENCES gyms(id),
    member_id        BIGINT        NOT NULL REFERENCES members(id),
    checked_in       TIMESTAMPTZ   NOT NULL DEFAULT NOW(),
    checked_in_date  DATE          NOT NULL DEFAULT CURRENT_DATE, -- for fast date-range queries
    recorded_by      BIGINT        NOT NULL REFERENCES users(id),
    created_at       TIMESTAMPTZ   NOT NULL DEFAULT NOW()
);

-- Core tenant + date range query: "who came in this week?"
CREATE INDEX idx_attendance_gym_date ON attendance (gym_id, checked_in_date);

-- Per-member history
CREATE INDEX idx_attendance_member_date ON attendance (member_id, checked_in_date DESC);

-- Retention job query: "members who haven't checked in for 14 days"
-- This index supports: WHERE gym_id = ? AND member_id NOT IN (SELECT ...)
CREATE INDEX idx_attendance_gym_member ON attendance (gym_id, member_id, checked_in_date DESC);

-- ── RETENTION ALERTS ─────────────────────────────────────────
CREATE TABLE retention_alerts (
    id          BIGSERIAL PRIMARY KEY,
    gym_id      BIGINT        NOT NULL REFERENCES gyms(id),
    member_id   BIGINT        NOT NULL REFERENCES members(id),
    alert_type  VARCHAR(50)   NOT NULL
                              CHECK (alert_type IN (
                                  'expiring_in_3_days',
                                  'expiring_today',
                                  'expired_no_renewal',
                                  'inactive_1_week',
                                  'inactive_2_weeks'
                              )),
    severity    VARCHAR(20)   NOT NULL
                              CHECK (severity IN ('low', 'medium', 'high')),
    message     TEXT          NOT NULL,
    is_resolved BOOLEAN       NOT NULL DEFAULT FALSE,
    resolved_at TIMESTAMPTZ,
    created_at  TIMESTAMPTZ   NOT NULL DEFAULT NOW()
);

-- Dashboard query: unresolved alerts per gym
CREATE INDEX idx_alerts_gym_unresolved ON retention_alerts (gym_id, is_resolved, created_at DESC)
    WHERE is_resolved = FALSE;

-- Per-member alert history
CREATE INDEX idx_alerts_member ON retention_alerts (gym_id, member_id, created_at DESC);

-- Prevent duplicate alerts of the same type for the same member
-- (retention job checks this before inserting)
CREATE UNIQUE INDEX idx_alerts_no_duplicate
    ON retention_alerts (gym_id, member_id, alert_type)
    WHERE is_resolved = FALSE;

-- ── NOTIFICATIONS ────────────────────────────────────────────
CREATE TABLE notifications (
    id          BIGSERIAL PRIMARY KEY,
    gym_id      BIGINT        NOT NULL REFERENCES gyms(id),
    member_id   BIGINT        NOT NULL REFERENCES members(id),
    alert_id    BIGINT        REFERENCES retention_alerts(id),
    channel     VARCHAR(20)   NOT NULL DEFAULT 'whatsapp'
                              CHECK (channel IN ('whatsapp', 'sms')),
    template_id VARCHAR(100)  NOT NULL,
    message     TEXT          NOT NULL,
    status      VARCHAR(20)   NOT NULL DEFAULT 'pending'
                              CHECK (status IN ('pending', 'sent', 'failed')),
    sent_at     TIMESTAMPTZ,
    created_by  BIGINT        NOT NULL REFERENCES users(id),
    created_at  TIMESTAMPTZ   NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_notif_gym_status ON notifications (gym_id, status, created_at DESC);
CREATE INDEX idx_notif_member ON notifications (gym_id, member_id, created_at DESC);

-- ── NOTIFICATION TEMPLATES ───────────────────────────────────
CREATE TABLE notification_templates (
    id          BIGSERIAL PRIMARY KEY,
    gym_id      BIGINT        NOT NULL REFERENCES gyms(id),
    template_id VARCHAR(100)  NOT NULL,
    name        VARCHAR(200)  NOT NULL,
    body        TEXT          NOT NULL,
    is_default  BOOLEAN       NOT NULL DEFAULT FALSE,
    created_at  TIMESTAMPTZ   NOT NULL DEFAULT NOW(),
    updated_at  TIMESTAMPTZ   NOT NULL DEFAULT NOW()
);

-- One template_id per gym
CREATE UNIQUE INDEX idx_templates_gym_tid ON notification_templates (gym_id, template_id);

-- ── UPDATED_AT TRIGGER (applied to all mutable tables) ───────
-- Postgres doesn't auto-update updated_at — we use a trigger.
CREATE OR REPLACE FUNCTION set_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_gyms_updated_at
    BEFORE UPDATE ON gyms
    FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE TRIGGER trg_users_updated_at
    BEFORE UPDATE ON users
    FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE TRIGGER trg_members_updated_at
    BEFORE UPDATE ON members
    FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE TRIGGER trg_plans_updated_at
    BEFORE UPDATE ON membership_plans
    FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE TRIGGER trg_renewals_updated_at
    BEFORE UPDATE ON renewals
    FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE TRIGGER trg_templates_updated_at
    BEFORE UPDATE ON notification_templates
    FOR EACH ROW EXECUTE FUNCTION set_updated_at();
