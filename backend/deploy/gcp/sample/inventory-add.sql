-- Sample retail inventory for ONE gym:  psql -v gym=1 -f inventory-add.sql
-- Products carry 'Sample data' in description; each gets an opening 'purchase'
-- stock movement so the audit trail matches stock_qty. Re-run safe.
\set ON_ERROR_STOP on
BEGIN;

WITH owner AS (SELECT id FROM users WHERE gym_id = :gym ORDER BY id LIMIT 1),
new_products AS (
  INSERT INTO products (gym_id, sku, name, category, description, price_in_paise, cost_in_paise, tax_rate_pct, stock_qty, reorder_level)
  SELECT :gym, v.sku, v.name, v.cat, 'Sample data', v.price, v.cost, v.tax, v.qty, v.reorder
  FROM (VALUES
    ('WHEY-1KG',  'Whey Protein 1kg',       'Supplements', 349900, 270000, 18.0, 24,  6),
    ('WHEY-2KG',  'Whey Protein 2kg',       'Supplements', 649900, 520000, 18.0, 12,  4),
    ('CREAT-250', 'Creatine 250g',          'Supplements', 129900,  90000, 18.0, 30,  8),
    ('BCAA-300',  'BCAA 300g',              'Supplements', 109900,  75000, 18.0, 18,  6),
    ('PRE-WO',    'Pre-workout 250g',       'Supplements',  99900,  68000, 18.0,  4,  6),
    ('BAR-PRO',   'Protein Bar',            'Snacks',        9900,   6500, 12.0, 120, 30),
    ('WATER-1L',  'Water Bottle 1L',        'Drinks',        2000,   1200,  5.0, 200, 50),
    ('ELEC-500',  'Electrolyte Drink 500ml','Drinks',        6000,   3800, 12.0, 60, 20),
    ('SHAKER',    'Shaker Bottle',          'Accessories',  35000,  19000, 18.0, 25, 10),
    ('GLOVES',    'Gym Gloves',             'Accessories',  59900,  34000, 18.0,  3,  5),
    ('TOWEL',     'Gym Towel',              'Accessories',  29900,  15000, 12.0, 40, 10),
    ('GI-BELT',   'Karate Belt',            'Martial Arts', 49900,  26000, 12.0, 15,  5),
    ('MITTS',     'Focus Mitts (pair)',     'Martial Arts',149900,  90000, 18.0,  8,  3)
  ) AS v(sku, name, cat, price, cost, tax, qty, reorder)
  WHERE NOT EXISTS (SELECT 1 FROM products WHERE gym_id = :gym AND description = 'Sample data')
  RETURNING id, stock_qty
)
INSERT INTO stock_movements (gym_id, product_id, movement_type, quantity, qty_after, reason, created_by_user_id)
SELECT :gym, p.id, 'purchase', p.stock_qty, p.stock_qty, 'Opening stock (sample)', (SELECT id FROM owner)
FROM new_products p;

COMMIT;
SELECT count(*) AS sample_products FROM products WHERE gym_id = :gym AND description = 'Sample data';
