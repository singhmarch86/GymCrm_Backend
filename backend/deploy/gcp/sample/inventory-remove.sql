-- Remove what inventory-add.sql created:  psql -v gym=1 -f inventory-remove.sql
-- Only products with no sales are removed (their history would be lost).
\set ON_ERROR_STOP on
BEGIN;
DELETE FROM stock_movements WHERE gym_id = :gym AND reason = 'Opening stock (sample)'
  AND product_id IN (SELECT id FROM products WHERE gym_id = :gym AND description = 'Sample data'
                     AND NOT EXISTS (SELECT 1 FROM stock_movements m WHERE m.product_id = products.id AND m.movement_type = 'sale'));
DELETE FROM products WHERE gym_id = :gym AND description = 'Sample data'
  AND NOT EXISTS (SELECT 1 FROM stock_movements m WHERE m.product_id = products.id);
COMMIT;
