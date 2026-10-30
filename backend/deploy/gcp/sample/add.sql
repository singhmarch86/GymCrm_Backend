-- Sample members, plans and payments for ONE gym, for demos.
--   psql -v gym=1 -f add.sql
-- Everything is tagged ('Sample data' in members.notes, 'Sample plan' in the
-- plan description) so remove.sql can take it out again. Safe to re-run: it
-- does nothing if the sample members already exist.
\set ON_ERROR_STOP on
BEGIN;

INSERT INTO membership_plans (gym_id, name, duration_days, price_in_paise, description)
SELECT :gym, v.name, v.days, v.price, 'Sample plan'
FROM (VALUES
  ('Monthly Training',    30,  150000),
  ('Quarterly Training',  90,  400000),
  ('Annual Training',    365, 1200000)
) AS v(name, days, price)
WHERE NOT EXISTS (SELECT 1 FROM members WHERE gym_id = :gym AND notes = 'Sample data')
ON CONFLICT DO NOTHING;

WITH people AS (
  SELECT * FROM unnest(
    ARRAY['Arjun','Simran','Harpreet','Manpreet','Gurpreet','Jaspreet','Navneet','Kiran','Rohan','Anmol',
          'Tanvi','Karan','Amrit','Pooja','Vikram','Neha','Sahil','Divya','Ishaan','Ritika',
          'Aman','Jasleen','Ravneet','Mehak','Yuvraj','Sukhmani','Dev','Gunjan','Lakshay','Prabhjot'],
    ARRAY['Singh','Kaur','Gill','Sandhu','Dhillon','Sidhu','Bajwa','Grewal','Mann','Brar',
          'Sharma','Verma','Randhawa','Chopra','Khanna','Malhotra','Bedi','Sethi','Walia','Arora',
          'Thakur','Johal','Cheema','Virk','Atwal','Bhatia','Kapoor','Gupta','Ahuja','Tiwana'],
    ARRAY['male','female','male','female','male','female','male','female','male','male',
          'female','male','male','female','male','female','male','female','male','female',
          'male','female','male','female','male','female','male','female','male','male']
  ) WITH ORDINALITY AS t(fn, ln, gender, n)
),
plans AS (
  SELECT id, duration_days, row_number() OVER (ORDER BY duration_days) AS r
  FROM membership_plans WHERE gym_id = :gym AND deleted_at IS NULL AND description = 'Sample plan'
),
planned AS (
  SELECT p.*, pl.id AS plan_id, pl.duration_days,
         -- Start dates spread over the last ~100 days so some memberships have lapsed.
         (CURRENT_DATE - ((p.n * 13) % 100)::int) AS start_date
  FROM people p JOIN plans pl ON pl.r = ((p.n - 1) % 3) + 1
)
INSERT INTO members (gym_id, phone, email, gender, join_date, status, notes, first_name, last_name,
                     membership_plan_id, start_date, expiry_date, date_of_birth, address)
SELECT :gym,
       '90000' || lpad(n::text, 5, '0'),
       lower(fn || '.' || ln || n) || '@example.com',
       gender,
       start_date - ((n % 4) * 30)::int,
       CASE WHEN start_date + duration_days < CURRENT_DATE THEN 'expired' ELSE 'active' END,
       'Sample data',
       fn, ln, plan_id, start_date, start_date + duration_days,
       DATE '1985-01-01' + ((n * 421) % 6000)::int,
       'Sample address, Amritsar'
FROM planned
WHERE NOT EXISTS (SELECT 1 FROM members WHERE gym_id = :gym AND notes = 'Sample data');

-- One paid payment per sample member at their start date...
INSERT INTO payments (gym_id, member_id, plan_id, amount_in_paise, status, payment_mode, due_date, paid_date, notes)
SELECT m.gym_id, m.id, m.membership_plan_id, pl.price_in_paise, 'paid',
       (ARRAY['cash','upi','upi','debit_card'])[1 + (m.id % 4)::int],
       m.start_date, m.start_date, 'Sample data'
FROM members m JOIN membership_plans pl ON pl.id = m.membership_plan_id
WHERE m.gym_id = :gym AND m.notes = 'Sample data'
  AND NOT EXISTS (SELECT 1 FROM payments p WHERE p.member_id = m.id);

-- ...and an overdue renewal for every other lapsed member.
INSERT INTO payments (gym_id, member_id, plan_id, amount_in_paise, status, due_date, notes)
SELECT m.gym_id, m.id, m.membership_plan_id, pl.price_in_paise, 'overdue', m.expiry_date, 'Sample data'
FROM members m JOIN membership_plans pl ON pl.id = m.membership_plan_id
WHERE m.gym_id = :gym AND m.notes = 'Sample data' AND m.status = 'expired' AND m.id % 2 = 0
  AND NOT EXISTS (SELECT 1 FROM payments p WHERE p.member_id = m.id AND p.status = 'overdue');

COMMIT;
