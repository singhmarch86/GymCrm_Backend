-- 033: stock transfers between branches (FR-22).
--
-- Branches already exist as gym rows under an organization, and products are
-- already per-gym — so stock is per-branch by construction. What was missing
-- was any way to move it, and any way to see it all at once. Until now the
-- only honest answer to "do we have protein at Model Town" was to phone them.
--
-- A transfer is two stock movements and one header tying them together. The
-- movements already existed as the audit trail for every level change; this
-- keeps that property rather than inventing a second one, so a product's
-- history still reads as a single ordered list wherever it is read from.

BEGIN;

-- The pair of movements a transfer writes. Existing types are unchanged, so
-- nothing already recorded is reinterpreted.
ALTER TABLE stock_movements DROP CONSTRAINT IF EXISTS chk_stock_movement_type;
ALTER TABLE stock_movements ADD CONSTRAINT chk_stock_movement_type
  CHECK (movement_type IN (
    'purchase', 'sale', 'adjustment', 'return', 'wastage',
    'transfer_out', 'transfer_in'
  ));

CREATE TABLE IF NOT EXISTS stock_transfers (
  id                BIGSERIAL PRIMARY KEY,

  from_gym_id       BIGINT NOT NULL REFERENCES gyms(id),
  to_gym_id         BIGINT NOT NULL REFERENCES gyms(id),

  -- Two product rows, because the same physical item is a separate row at
  -- each branch. The destination row is created on first receipt if the
  -- branch does not carry the item yet — sending stock somewhere that does
  -- not stock it is a large part of why anyone transfers.
  from_product_id   BIGINT NOT NULL REFERENCES products(id),
  to_product_id     BIGINT NOT NULL REFERENCES products(id),

  quantity          INTEGER NOT NULL,

  -- Valued at the sending branch's cost, captured at the time of the move.
  -- Cost prices drift, and a transfer re-priced by a later purchase would
  -- quietly restate what left the building last month.
  unit_cost_in_paise BIGINT NOT NULL DEFAULT 0,
  value_in_paise     BIGINT NOT NULL DEFAULT 0,

  reason            TEXT,
  created_by_user_id BIGINT NOT NULL REFERENCES users(id),
  created_at        TIMESTAMPTZ NOT NULL DEFAULT now(),

  CONSTRAINT chk_stock_transfer_qty_positive CHECK (quantity > 0),
  CONSTRAINT chk_stock_transfer_not_same_branch CHECK (from_gym_id <> to_gym_id)
);

-- Links each side of the pair back to its header, so a movement on a product's
-- history can say where the stock went rather than just that it left.
ALTER TABLE stock_movements
  ADD COLUMN IF NOT EXISTS transfer_id BIGINT REFERENCES stock_transfers(id);

CREATE INDEX IF NOT EXISTS idx_stock_transfers_from
  ON stock_transfers (from_gym_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_stock_transfers_to
  ON stock_transfers (to_gym_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_stock_movements_transfer
  ON stock_movements (transfer_id) WHERE transfer_id IS NOT NULL;

COMMIT;
