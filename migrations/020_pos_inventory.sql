-- 020_pos_inventory.sql
--
-- Retail: products, stock movements, and counter sales.
-- See docs/FR-07-pos-inventory.md.
--
-- Additive only. Stock is per gym, which under FR-06 means per branch.

CREATE TABLE IF NOT EXISTS products (
    id                 bigserial PRIMARY KEY,
    gym_id             bigint       NOT NULL,
    sku                varchar(60),
    name               varchar(200) NOT NULL,
    category           varchar(80),
    description        text,

    price_in_paise     bigint       NOT NULL,          -- what the member pays
    cost_in_paise      bigint       NOT NULL DEFAULT 0, -- what the gym paid; drives margin
    tax_rate_pct       numeric(5,2) NOT NULL DEFAULT 18.00,

    -- Kept in step with stock_movements, never edited directly (FR-07 §1).
    stock_qty          integer      NOT NULL DEFAULT 0,
    reorder_level      integer      NOT NULL DEFAULT 0,

    is_active          boolean      NOT NULL DEFAULT true,
    created_at         timestamptz  NOT NULL DEFAULT now(),
    updated_at         timestamptz  NOT NULL DEFAULT now(),
    deleted_at         timestamptz,

    CONSTRAINT chk_products_price_nonneg CHECK (price_in_paise >= 0),
    CONSTRAINT chk_products_cost_nonneg  CHECK (cost_in_paise >= 0),
    CONSTRAINT chk_products_reorder_nonneg CHECK (reorder_level >= 0),
    CONSTRAINT chk_products_tax_range CHECK (tax_rate_pct >= 0 AND tax_rate_pct <= 100)
);

CREATE INDEX IF NOT EXISTS idx_products_gym ON products (gym_id, is_active);
-- SKUs are unique per gym when present; many products legitimately have none.
CREATE UNIQUE INDEX IF NOT EXISTS idx_products_gym_sku
    ON products (gym_id, LOWER(sku)) WHERE sku IS NOT NULL AND deleted_at IS NULL;

-- ── Stock movements: the audit trail behind every stock level ─────────────────
-- Insert-only. A wrong movement is corrected by a compensating movement, never
-- by editing or deleting the original (FR-07 §1).
CREATE TABLE IF NOT EXISTS stock_movements (
    id              bigserial PRIMARY KEY,
    gym_id          bigint      NOT NULL,
    product_id      bigint      NOT NULL REFERENCES products(id),

    movement_type   varchar(20) NOT NULL,  -- purchase|sale|adjustment|return|wastage
    -- Signed: positive adds stock, negative removes it. Storing the sign rather
    -- than inferring it from the type keeps the arithmetic honest for
    -- adjustments, which go both ways.
    quantity        integer     NOT NULL,
    qty_after       integer     NOT NULL,  -- resulting level, for point-in-time audit

    reason          text,
    sale_id         bigint,                -- set when the movement came from a sale
    created_by_user_id bigint   NOT NULL,
    created_at      timestamptz NOT NULL DEFAULT now(),

    CONSTRAINT chk_stock_movement_type
        CHECK (movement_type IN ('purchase', 'sale', 'adjustment', 'return', 'wastage')),
    CONSTRAINT chk_stock_movement_qty_nonzero CHECK (quantity <> 0)
);

CREATE INDEX IF NOT EXISTS idx_stock_movements_product ON stock_movements (product_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_stock_movements_gym ON stock_movements (gym_id, created_at DESC);

-- ── Sales ─────────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS sales (
    id                 bigserial PRIMARY KEY,
    gym_id             bigint      NOT NULL,
    -- Optional: a walk-in buying a shaker has no member record.
    member_id          bigint,

    sale_number        varchar(50),
    subtotal_in_paise  bigint      NOT NULL DEFAULT 0,
    tax_in_paise       bigint      NOT NULL DEFAULT 0,
    discount_in_paise  bigint      NOT NULL DEFAULT 0,
    total_in_paise     bigint      NOT NULL DEFAULT 0,

    payment_mode       varchar(20) NOT NULL DEFAULT 'cash',
    -- A refund is its own sale with negative quantities, pointing back at what
    -- it reverses (FR-07 §2.1).
    is_refund          boolean     NOT NULL DEFAULT false,
    refund_of_sale_id  bigint REFERENCES sales(id),
    reason             text,

    invoice_id         bigint,     -- set if an invoice was raised for this sale
    notes              text,
    created_by_user_id bigint      NOT NULL,
    created_at         timestamptz NOT NULL DEFAULT now(),

    CONSTRAINT chk_sales_mode
        CHECK (payment_mode IN ('cash', 'upi', 'credit_card', 'debit_card', 'bank_transfer', 'account')),
    CONSTRAINT chk_sales_refund_reason
        CHECK (is_refund = false OR reason IS NOT NULL)
);

CREATE INDEX IF NOT EXISTS idx_sales_gym_date ON sales (gym_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_sales_member ON sales (member_id);

CREATE TABLE IF NOT EXISTS sale_items (
    id                  bigserial PRIMARY KEY,
    gym_id              bigint       NOT NULL,
    sale_id             bigint       NOT NULL REFERENCES sales(id) ON DELETE CASCADE,
    product_id          bigint       NOT NULL REFERENCES products(id),

    -- Snapshots: a later price change must never rewrite a completed sale.
    product_name        varchar(200) NOT NULL,
    unit_price_in_paise bigint       NOT NULL,
    cost_in_paise       bigint       NOT NULL DEFAULT 0,
    tax_rate_pct        numeric(5,2) NOT NULL DEFAULT 18.00,

    quantity            integer      NOT NULL,
    line_total_in_paise bigint       NOT NULL DEFAULT 0,

    created_at          timestamptz  NOT NULL DEFAULT now(),

    CONSTRAINT chk_sale_items_qty_nonzero CHECK (quantity <> 0)
);

CREATE INDEX IF NOT EXISTS idx_sale_items_sale ON sale_items (sale_id);
CREATE INDEX IF NOT EXISTS idx_sale_items_product ON sale_items (product_id);

-- Per-gym retail setting: whether the counter may sell stock it doesn't hold
-- (FR-07 §1.1). Lives on the existing billing settings row rather than a new
-- table — it is one flag, not a module.
ALTER TABLE gym_billing_settings
    ADD COLUMN IF NOT EXISTS allow_negative_stock boolean NOT NULL DEFAULT false;
