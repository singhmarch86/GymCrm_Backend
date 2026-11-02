-- Sample leads for ONE gym:  psql -v gym=1 -f leads-add.sql
-- Tagged 'Sample data' in notes; phones 9100000001-24. Spread across the
-- pipeline stages (not 'joined', which needs a real member). Re-run safe.
\set ON_ERROR_STOP on
BEGIN;

WITH ins AS (
  INSERT INTO leads (gym_id, name, phone, gender, source, goal, notes, status, trial_date, follow_up_date, lost_reason, created_at)
  SELECT :gym, v.name, '91000000' || lpad(v.n::text, 2, '0'), v.gender, v.source, v.goal, 'Sample data', v.status,
         CASE WHEN v.status IN ('trial_scheduled','trial_completed') THEN current_date + v.d ELSE NULL END,
         CASE WHEN v.status NOT IN ('lost') THEN current_date + (v.n % 5) - 1 ELSE NULL END,
         CASE WHEN v.status = 'lost' THEN v.lost END,
         now() - (v.n || ' days')::interval
  FROM (VALUES
    (1,'Aditya Rana','male','walk_in','muscle_gain','new_lead',0,NULL),
    (2,'Sanya Kohli','female','instagram','weight_loss','new_lead',0,NULL),
    (3,'Bhavya Sood','female','website','fitness','new_lead',0,NULL),
    (4,'Harsh Vora','male','whatsapp','muscle_gain','new_lead',0,NULL),
    (5,'Tarun Mehra','male','google','fitness','new_lead',0,NULL),
    (6,'Ishita Jain','female','referral','weight_loss','contacted',0,NULL),
    (7,'Gagan Dhaliwal','male','walk_in','muscle_gain','contacted',0,NULL),
    (8,'Reema Soni','female','facebook','weight_loss','contacted',0,NULL),
    (9,'Nikhil Batra','male','instagram','fitness','contacted',0,NULL),
    (10,'Palak Anand','female','walk_in','fitness','contacted',0,NULL),
    (11,'Rudra Pratap','male','referral','muscle_gain','trial_scheduled',1,NULL),
    (12,'Meher Kaur','female','instagram','weight_loss','trial_scheduled',2,NULL),
    (13,'Kunal Saini','male','walk_in','fitness','trial_scheduled',3,NULL),
    (14,'Zoya Khan','female','website','weight_loss','trial_scheduled',1,NULL),
    (15,'Daljit Pannu','male','walk_in','muscle_gain','trial_completed',-1,NULL),
    (16,'Aarohi Sen','female','google','fitness','trial_completed',-2,NULL),
    (17,'Pranav Joshi','male','whatsapp','muscle_gain','trial_completed',-1,NULL),
    (18,'Lovepreet Brar','male','referral','weight_loss','trial_completed',-3,NULL),
    (19,'Mansi Dua','female','facebook','weight_loss','lost',0,'Joined a gym closer to home'),
    (20,'Rishabh Goel','male','walk_in','fitness','lost',0,'Fees too high'),
    (21,'Sneha Rao','female','instagram','weight_loss','lost',0,'Not interested'),
    (22,'Veer Chauhan','male','other','muscle_gain','lost',0,'Moving to another city'),
    (23,'Avni Bhalla','female','walk_in','fitness','new_lead',0,NULL),
    (24,'Jashan Sekhon','male','referral','muscle_gain','contacted',0,NULL)
  ) AS v(n, name, gender, source, goal, status, d, lost)
  WHERE NOT EXISTS (SELECT 1 FROM leads WHERE gym_id = :gym AND notes = 'Sample data')
  RETURNING id, status, created_at
)
INSERT INTO lead_activities (gym_id, lead_id, type, note, to_status, created_at)
SELECT :gym, id, 'created', 'Lead added', 'new_lead', created_at FROM ins;

COMMIT;
SELECT status, count(*) FROM leads WHERE gym_id = :gym AND notes = 'Sample data' GROUP BY 1 ORDER BY 1;
