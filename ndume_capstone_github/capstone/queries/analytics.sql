-- Analytical queries for the Ndume Ranch dashboard. All run as the app role with a tenant set:
--   BEGIN; SET LOCAL app.ranch_id='1'; SET LOCAL app.role='owner';  <query>;  COMMIT;

-- Q1: herd by breed with average LATEST weight (dashboard card)
SELECT b.name AS breed, count(*) AS head, round(avg(w.weight_kg),1) AS avg_latest_kg
FROM animals a
JOIN breeds b USING (breed_id)
JOIN LATERAL (SELECT weight_kg FROM weight_records w
              WHERE w.animal_id = a.animal_id ORDER BY weighed_on DESC LIMIT 1) w ON true
WHERE a.status = 'active'
GROUP BY b.name ORDER BY head DESC;

-- Q2: average daily gain (kg/day) per animal over the last 90 days, top 20
SELECT a.tag_number,
       round((max(w.weight_kg) FILTER (WHERE w.weighed_on = l.last_d)
            - max(w.weight_kg) FILTER (WHERE w.weighed_on = l.first_d))
            / NULLIF(l.last_d - l.first_d, 0), 3) AS adg_kg_per_day
FROM animals a
JOIN weight_records w ON w.animal_id = a.animal_id AND w.weighed_on >= DATE '2026-10-01' - 90
JOIN LATERAL (SELECT min(weighed_on) first_d, max(weighed_on) last_d
              FROM weight_records x WHERE x.animal_id = a.animal_id AND x.weighed_on >= DATE '2026-10-01' - 90) l ON true
WHERE a.status = 'active'
GROUP BY a.tag_number, l.first_d, l.last_d
HAVING l.last_d > l.first_d
ORDER BY adg_kg_per_day DESC NULLS LAST LIMIT 20;

-- Q3: vaccinations overdue as of 2026-10-01 (not followed by a later vaccination of the same medicine)
SELECT a.tag_number, h.medicine, h.next_due_on
FROM health_events h
JOIN animals a USING (animal_id)
WHERE a.status = 'active' AND h.event_type = 'vaccination' AND h.next_due_on < DATE '2026-10-01'
  AND NOT EXISTS (SELECT 1 FROM health_events h2
                  WHERE h2.animal_id = h.animal_id AND h2.medicine = h.medicine AND h2.event_date > h.event_date)
ORDER BY h.next_due_on LIMIT 50;

-- Q4: margin per sold animal = sale price - lifetime health cost (owner/manager only, via RLS)
SELECT a.tag_number, s.price_kes,
       COALESCE(sum(h.cost_kes),0) AS health_cost,
       s.price_kes - COALESCE(sum(h.cost_kes),0) AS margin_kes
FROM sales s
JOIN animals a USING (animal_id)
LEFT JOIN health_events h ON h.animal_id = s.animal_id
GROUP BY a.tag_number, s.price_kes
ORDER BY margin_kes DESC LIMIT 20;

-- Q5: pedigree: all descendants of one animal (recursive CTE)
WITH RECURSIVE tree AS (
  SELECT animal_id, tag_number, dam_id, 1 AS gen FROM animals WHERE animal_id = (SELECT min(animal_id) FROM animals WHERE sex='F')
  UNION ALL
  SELECT c.animal_id, c.tag_number, c.dam_id, t.gen + 1
  FROM animals c JOIN tree t ON c.dam_id = t.animal_id WHERE t.gen < 6)
SELECT gen, count(*) FROM tree GROUP BY gen ORDER BY gen;
