-- 019_multi_location.sql
--
-- Organizations (gym chains) and per-user branch access.
-- See docs/FR-06-multi-location.md.
--
-- The deliberate non-change: gym_id remains the ONE tenancy boundary. A branch
-- IS a gym. Nothing in any existing table or query is touched, so no query can
-- be accidentally missed and leak data between branches (FR-06 §0).
--
-- Additive and backfilled so behaviour is identical on day one: every existing
-- gym becomes a single-branch organization, and every existing user gets an
-- explicit grant to the gym they already had.

CREATE TABLE IF NOT EXISTS organizations (
    id         bigserial PRIMARY KEY,
    name       varchar(200) NOT NULL,
    created_at timestamptz  NOT NULL DEFAULT now(),
    updated_at timestamptz  NOT NULL DEFAULT now()
);

-- Nullable: a standalone gym with no chain is a perfectly normal state, and
-- making this required would force ceremony on the common single-gym case.
ALTER TABLE gyms ADD COLUMN IF NOT EXISTS organization_id bigint REFERENCES organizations(id);
CREATE INDEX IF NOT EXISTS idx_gyms_organization ON gyms (organization_id);

-- A short human label for the branch, distinct from the gym's full name:
-- "Model Town" reads better in a branch switcher than "FitZone Model Town".
ALTER TABLE gyms ADD COLUMN IF NOT EXISTS branch_name varchar(100);

-- ── Per-user branch access ────────────────────────────────────────────────────
-- Which branches a user may act in, and their role in each. Role is per grant:
-- a manager at one branch may be ordinary staff at another (FR-06 §1.2).
CREATE TABLE IF NOT EXISTS user_gym_access (
    id         bigserial PRIMARY KEY,
    user_id    bigint      NOT NULL,
    gym_id     bigint      NOT NULL,
    role       varchar(20) NOT NULL DEFAULT 'staff',
    created_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT chk_user_gym_access_role CHECK (role IN ('owner', 'manager', 'staff')),
    CONSTRAINT uq_user_gym UNIQUE (user_id, gym_id)
);

CREATE INDEX IF NOT EXISTS idx_user_gym_access_user ON user_gym_access (user_id);
CREATE INDEX IF NOT EXISTS idx_user_gym_access_gym  ON user_gym_access (gym_id);

-- ── Backfill ──────────────────────────────────────────────────────────────────
-- Each existing gym becomes its own one-branch organization.
INSERT INTO organizations (name)
SELECT g.name FROM gyms g
WHERE g.organization_id IS NULL
  AND NOT EXISTS (SELECT 1 FROM organizations o WHERE o.name = g.name);

UPDATE gyms g
SET organization_id = o.id, updated_at = now()
FROM organizations o
WHERE g.organization_id IS NULL AND o.name = g.name;

UPDATE gyms SET branch_name = name WHERE branch_name IS NULL;

-- Every existing user gets an explicit grant to the gym they already belong to,
-- at the role they already hold. Without this, the first switch-aware request
-- would find no grants and lock everyone out of their own gym.
INSERT INTO user_gym_access (user_id, gym_id, role)
SELECT u.id, u.gym_id,
       CASE WHEN u.role IN ('owner', 'manager', 'staff') THEN u.role ELSE 'staff' END
FROM users u
ON CONFLICT (user_id, gym_id) DO NOTHING;
