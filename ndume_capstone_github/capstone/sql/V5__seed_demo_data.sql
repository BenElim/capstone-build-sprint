-- V5: deterministic demo data (3 ranches, ~6,000 animals, ~600k weigh-ins).
-- Demo only: passwords below are placeholders, and the phone-encryption key is a demo key.
SELECT setseed(0.42);

INSERT INTO ranches (name, county) VALUES
    ('Ndume Ranch', 'Nakuru'), ('Laikipia Plains Ranch', 'Laikipia'), ('Mara Edge Ranch', 'Narok');

INSERT INTO breeds (name, purpose) VALUES
    ('Boran','beef'), ('Sahiwal','dual'), ('Friesian','dairy'), ('Ankole','dual'), ('Angus','beef');

INSERT INTO app_users (ranch_id, email, password_hash, full_name, role)
SELECT r.ranch_id, u.local || '@ranch' || r.ranch_id || '.example',
       crypt('demo-' || u.local || '-' || r.ranch_id, gen_salt('bf', 10)), initcap(u.local) || ' R' || r.ranch_id, u.role
FROM ranches r
CROSS JOIN (VALUES ('owner','owner'),('manager','manager'),('vet','vet'),('worker','worker')) AS u(local, role);

INSERT INTO pastures (ranch_id, name, area_ha, capacity_head)
SELECT r.ranch_id, 'Pasture ' || p, 20 + p * 5, 300 + p * 40
FROM ranches r, generate_series(1,6) p
ORDER BY r.ranch_id, p;

-- animals: 2000 per ranch
INSERT INTO animals (ranch_id, tag_number, name, breed_id, sex, birth_date, pasture_id)
SELECT r.ranch_id,
       'R' || r.ranch_id || '-' || lpad(i::text, 5, '0'),
       NULL,
       1 + floor(random()*5)::int,
       CASE WHEN random() < 0.6 THEN 'F' ELSE 'M' END,
       DATE '2026-10-01' - (200 + floor(random()*2300))::int,
       (SELECT p.pasture_id FROM pastures p WHERE p.ranch_id = r.ranch_id
         ORDER BY p.pasture_id OFFSET (i % 6) LIMIT 1)    -- always one of this ranch's own pastures
FROM ranches r, generate_series(1,2000) i
ORDER BY r.ranch_id, i;                                   -- contiguous ids per ranch

-- pedigree: older females/males within the same ranch act as parents for younger animals
UPDATE animals a SET
    dam_id  = (SELECT d.animal_id FROM animals d
               WHERE d.ranch_id = a.ranch_id AND d.sex = 'F' AND d.birth_date < a.birth_date - 700
               ORDER BY d.animal_id # a.animal_id LIMIT 1),
    sire_id = (SELECT s.animal_id FROM animals s
               WHERE s.ranch_id = a.ranch_id AND s.sex = 'M' AND s.birth_date < a.birth_date - 700
               ORDER BY s.animal_id # (a.animal_id * 7) LIMIT 1)
WHERE a.animal_id % 3 <> 0 AND a.birth_date > DATE '2026-10-01' - 1500;

-- weigh-ins every 14 days from birth (cap 150 per animal) with growth + noise
INSERT INTO weight_records (animal_id, ranch_id, weighed_on, weight_kg, recorded_by)
SELECT a.animal_id, a.ranch_id, a.birth_date + (k * 14),
       round((32 + (k * 14) * (0.35 + (a.animal_id % 7) * 0.03) + (random() - 0.5) * 12)::numeric, 1),
       (SELECT min(u.user_id) FROM app_users u WHERE u.ranch_id = a.ranch_id AND u.role = 'worker')
FROM animals a
CROSS JOIN LATERAL generate_series(0, LEAST(150, ((DATE '2026-10-01' - a.birth_date) / 14)::int)) k;

-- health events: two vaccinations + one deworming per animal, some with a next-due date
INSERT INTO health_events (animal_id, ranch_id, event_date, event_type, medicine, next_due_on, cost_kes, recorded_by)
SELECT a.animal_id, a.ranch_id, a.birth_date + v.off, v.t, v.med,
       CASE WHEN v.t = 'vaccination' THEN a.birth_date + v.off + 180 END,
       round((100 + random()*400)::numeric, 2),
       (SELECT min(u.user_id) FROM app_users u WHERE u.ranch_id = a.ranch_id AND u.role = 'vet')
FROM animals a
CROSS JOIN (VALUES (60,'vaccination','FMD vaccine'),(120,'vaccination','Lumpy skin vaccine'),(90,'deworming','Albendazole')) v(off, t, med)
WHERE a.birth_date + v.off <= DATE '2026-10-01';

-- feed logs: daily per pasture for the last 180 days
INSERT INTO feed_logs (ranch_id, pasture_id, logged_on, feed_type, quantity_kg, cost_kes)
SELECT p.ranch_id, p.pasture_id, d::date,
       (ARRAY['hay','silage','dairy meal','mineral lick'])[1 + (extract(doy FROM d)::int % 4)],
       round((200 + random()*300)::numeric, 1), round((1500 + random()*2500)::numeric, 2)
FROM pastures p, generate_series(DATE '2026-04-04', DATE '2026-10-01', '1 day') d;

-- breeding events for ~300 dams per ranch
INSERT INTO breeding_events (ranch_id, dam_id, sire_id, mated_on, expected_calving, outcome)
SELECT a.ranch_id, a.animal_id,
       (SELECT s.animal_id FROM animals s WHERE s.ranch_id = a.ranch_id AND s.sex='M' ORDER BY s.animal_id # a.animal_id LIMIT 1),
       DATE '2026-01-15' + (a.animal_id % 120)::int,
       DATE '2026-01-15' + (a.animal_id % 120)::int + 283,
       'pending'
FROM animals a WHERE a.sex = 'F' AND a.birth_date < DATE '2024-10-01' AND a.animal_id % 5 = 0;

-- buyers (phone encrypted with a demo key) and sales (~8% of animals)
INSERT INTO buyers (ranch_id, name, phone_enc)
SELECT r.ranch_id, 'Buyer ' || b, pgp_sym_encrypt('+2547' || lpad((r.ranch_id * 1000 + b)::text, 8, '0'), 'demo-key-change-me')
FROM ranches r, generate_series(1,12) b
ORDER BY r.ranch_id, b;

INSERT INTO sales (ranch_id, animal_id, buyer_id, sold_on, price_kes, weight_at_sale_kg)
SELECT a.ranch_id, a.animal_id,
       (SELECT b.buyer_id FROM buyers b WHERE b.ranch_id = a.ranch_id
         ORDER BY b.buyer_id OFFSET (a.animal_id % 12)::int LIMIT 1),   -- buyer from the same ranch
       DATE '2026-10-01' - (a.animal_id % 300)::int,
       round((35000 + (a.animal_id % 40) * 1000 + random()*5000)::numeric, 2),
       (SELECT w.weight_kg FROM weight_records w WHERE w.animal_id = a.animal_id ORDER BY w.weighed_on DESC LIMIT 1)
FROM animals a
WHERE a.animal_id % 12 = 0 AND a.status = 'active' AND a.birth_date < DATE '2026-10-01' - 400;

ANALYZE;

-- integrity gate: fail the migration if any seeded row references another tenant's data
DO $$ DECLARE bad integer;
BEGIN
  SELECT count(*) INTO bad FROM animals a JOIN pastures p USING (pasture_id) WHERE p.ranch_id <> a.ranch_id;
  IF bad > 0 THEN RAISE EXCEPTION 'cross-tenant animal->pasture refs: %', bad; END IF;
  SELECT count(*) INTO bad FROM sales s JOIN buyers b USING (buyer_id) WHERE b.ranch_id <> s.ranch_id;
  IF bad > 0 THEN RAISE EXCEPTION 'cross-tenant sale->buyer refs: %', bad; END IF;
  SELECT count(*) INTO bad FROM sales s JOIN animals a USING (animal_id) WHERE a.ranch_id <> s.ranch_id;
  IF bad > 0 THEN RAISE EXCEPTION 'cross-tenant sale->animal refs: %', bad; END IF;
  SELECT count(*) INTO bad FROM animals a JOIN animals d ON d.animal_id = a.dam_id WHERE d.ranch_id <> a.ranch_id;
  IF bad > 0 THEN RAISE EXCEPTION 'cross-tenant pedigree refs: %', bad; END IF;
END $$;
