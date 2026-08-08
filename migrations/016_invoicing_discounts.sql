-- 016_invoicing_discounts.sql
--
-- Invoicing and discounts. See docs/FR-04-invoicing-discounts.md.
--
-- Additive only: creates new tables and adds one nullable column to payments.
-- Nothing existing is dropped, narrowed, or backfilled destructively.

-- ── Per-gym billing settings ──────────────────────────────────────────────────
-- Kept out of the `gyms` table: these are billing concerns with their own
-- lifecycle, and a gym with no row here simply uses the defaults below.
CREATE TABLE IF NOT EXISTS gym_billing_settings (
    gym_id              bigint PRIMARY KEY,
    invoice_prefix      varchar(20)   NOT NULL DEFAULT 'INV',
    gstin               varchar(20),
    default_tax_rate    numeric(5,2)  NOT NULL DEFAULT 18.00,
    default_sac_code    varchar(10)   DEFAULT '999723',
    -- FR-04 §5.3 — exclusive means tax is added on top of the listed price.
    prices_include_tax  boolean       NOT NULL DEFAULT false,
    legal_name          varchar(200),
    address_line        text,
    state_name          varchar(100),
    created_at          timestamptz   NOT NULL DEFAULT now(),
    updated_at          timestamptz   NOT NULL DEFAULT now(),
    CONSTRAINT chk_billing_tax_rate_range CHECK (default_tax_rate >= 0 AND default_tax_rate <= 100)
);

-- ── Invoice number sequences ──────────────────────────────────────────────────
-- One row per (gym, financial year). Locked FOR UPDATE when issuing so numbering
-- stays gapless under concurrency — FR-04 §1.1. Deliberately NOT a Postgres
-- sequence: those are non-transactional and leave gaps on rollback.
CREATE TABLE IF NOT EXISTS invoice_sequences (
    gym_id          bigint      NOT NULL,
    financial_year  varchar(9)  NOT NULL,   -- e.g. '2026-27'
    last_seq        integer     NOT NULL DEFAULT 0,
    updated_at      timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (gym_id, financial_year),
    CONSTRAINT chk_invoice_seq_nonneg CHECK (last_seq >= 0)
);

-- ── Discounts ─────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS discounts (
    id            bigserial PRIMARY KEY,
    gym_id        bigint        NOT NULL,
    code          varchar(50)   NOT NULL,
    name          varchar(150)  NOT NULL,
    discount_type varchar(10)   NOT NULL,          -- percent | flat
    value         numeric(12,2) NOT NULL,          -- percent: 25.00 | flat: paise
    valid_from    date,
    valid_until   date,
    max_uses      integer,                         -- NULL = unlimited
    times_used    integer       NOT NULL DEFAULT 0,
    is_active     boolean       NOT NULL DEFAULT true,
    created_at    timestamptz   NOT NULL DEFAULT now(),
    updated_at    timestamptz   NOT NULL DEFAULT now(),
    CONSTRAINT chk_discounts_type  CHECK (discount_type IN ('percent', 'flat')),
    CONSTRAINT chk_discounts_value CHECK (value >= 0),
    CONSTRAINT chk_discounts_percent_range
        CHECK (discount_type <> 'percent' OR value <= 100),
    CONSTRAINT chk_discounts_uses  CHECK (times_used >= 0),
    CONSTRAINT chk_discounts_max_uses CHECK (max_uses IS NULL OR max_uses > 0),
    CONSTRAINT chk_discounts_date_order
        CHECK (valid_from IS NULL OR valid_until IS NULL OR valid_until >= valid_from)
);

-- Codes are unique per gym, case-insensitively.
CREATE UNIQUE INDEX IF NOT EXISTS idx_discounts_gym_code
    ON discounts (gym_id, LOWER(code));

-- ── Invoices ──────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS invoices (
    id                    bigserial PRIMARY KEY,
    gym_id                bigint       NOT NULL,
    member_id             bigint       NOT NULL,

    -- NULL while draft; assigned atomically at issue time and never reused.
    invoice_number        varchar(50),
    financial_year        varchar(9),
    status                varchar(20)  NOT NULL DEFAULT 'draft',  -- draft|issued|cancelled

    invoice_date          date,
    due_date              date,

    -- Snapshotted at issue so a later settings change never alters a document
    -- already handed to a member (FR-04 §3).
    place_of_supply       varchar(100),
    gstin                 varchar(20),
    prices_include_tax    boolean      NOT NULL DEFAULT false,

    -- Invoice-level discount, resolved to paise at application time (FR-04 §4).
    discount_id           bigint REFERENCES discounts(id),
    discount_code         varchar(50),
    discount_label        varchar(150),
    discount_reason       text,
    discount_in_paise     bigint       NOT NULL DEFAULT 0,

    subtotal_in_paise     bigint       NOT NULL DEFAULT 0,  -- gross, before discount
    tax_in_paise          bigint       NOT NULL DEFAULT 0,
    total_in_paise        bigint       NOT NULL DEFAULT 0,

    notes                 text,
    cancelled_reason      text,
    cancelled_at          timestamptz,
    cancelled_by_user_id  bigint,
    created_by_user_id    bigint       NOT NULL,
    created_at            timestamptz  NOT NULL DEFAULT now(),
    updated_at            timestamptz  NOT NULL DEFAULT now(),

    CONSTRAINT chk_invoices_status CHECK (status IN ('draft', 'issued', 'cancelled')),
    CONSTRAINT chk_invoices_amounts_nonneg
        CHECK (subtotal_in_paise >= 0 AND tax_in_paise >= 0
               AND total_in_paise >= 0 AND discount_in_paise >= 0),
    -- An issued or cancelled invoice must carry its number; a draft must not.
    CONSTRAINT chk_invoices_number_presence
        CHECK ((status = 'draft'  AND invoice_number IS NULL)
            OR (status <> 'draft' AND invoice_number IS NOT NULL)),
    CONSTRAINT chk_invoices_cancel_reason
        CHECK (status <> 'cancelled' OR cancelled_reason IS NOT NULL)
);

-- Numbers are unique per gym. Partial index so many drafts (NULL number) coexist.
CREATE UNIQUE INDEX IF NOT EXISTS idx_invoices_gym_number
    ON invoices (gym_id, invoice_number)
    WHERE invoice_number IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_invoices_gym_member ON invoices (gym_id, member_id);
CREATE INDEX IF NOT EXISTS idx_invoices_gym_status ON invoices (gym_id, status);

-- ── Invoice line items ────────────────────────────────────────────────────────
-- Every line is a snapshot: description and price are copied at add time so a
-- later plan price change never rewrites history (FR-04 §3).
CREATE TABLE IF NOT EXISTS invoice_items (
    id                   bigserial PRIMARY KEY,
    gym_id               bigint        NOT NULL,
    invoice_id           bigint        NOT NULL REFERENCES invoices(id) ON DELETE CASCADE,

    description          varchar(300)  NOT NULL,
    item_type            varchar(20)   NOT NULL DEFAULT 'custom', -- plan|pt_package|product|custom
    -- Intentionally NOT a foreign key: the source row may be deleted later and
    -- the line must survive unchanged.
    reference_id         bigint,

    quantity             integer       NOT NULL DEFAULT 1,
    unit_price_in_paise  bigint        NOT NULL,
    discount_in_paise    bigint        NOT NULL DEFAULT 0,
    tax_rate_pct         numeric(5,2)  NOT NULL DEFAULT 18.00,
    sac_code             varchar(10),

    tax_in_paise         bigint        NOT NULL DEFAULT 0,
    line_total_in_paise  bigint        NOT NULL DEFAULT 0,

    created_at           timestamptz   NOT NULL DEFAULT now(),

    CONSTRAINT chk_invoice_items_type
        CHECK (item_type IN ('plan', 'pt_package', 'product', 'custom')),
    CONSTRAINT chk_invoice_items_qty CHECK (quantity > 0),
    CONSTRAINT chk_invoice_items_price_nonneg CHECK (unit_price_in_paise >= 0),
    CONSTRAINT chk_invoice_items_discount_nonneg CHECK (discount_in_paise >= 0),
    CONSTRAINT chk_invoice_items_tax_range CHECK (tax_rate_pct >= 0 AND tax_rate_pct <= 100)
);

CREATE INDEX IF NOT EXISTS idx_invoice_items_invoice ON invoice_items (invoice_id);

-- ── Link payments to invoices ─────────────────────────────────────────────────
-- Nullable: payments already exist without invoices and must keep working
-- untouched. One invoice may be settled by several payments (part payments),
-- which is why the link lives here rather than as a single payment_id on the
-- invoice.
ALTER TABLE payments ADD COLUMN IF NOT EXISTS invoice_id bigint REFERENCES invoices(id);
CREATE INDEX IF NOT EXISTS idx_payments_invoice ON payments (invoice_id);
