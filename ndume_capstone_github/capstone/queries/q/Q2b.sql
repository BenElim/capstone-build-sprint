-- Q2b: average daily gain, rewritten: one index-driven pass per animal instead of join + re-aggregate
SELECT a.tag_number,
       round((l.last_kg - l.first_kg) / NULLIF(l.last_d - l.first_d, 0), 3) AS adg_kg_per_day
FROM animals a
JOIN LATERAL (
    SELECT min(weighed_on) AS first_d, max(weighed_on) AS last_d,
           (array_agg(weight_kg ORDER BY weighed_on))[1]      AS first_kg,
           (array_agg(weight_kg ORDER BY weighed_on DESC))[1] AS last_kg
    FROM weight_records w
    WHERE w.animal_id = a.animal_id AND w.weighed_on >= DATE '2026-10-01' - 90) l ON true
WHERE a.status = 'active' AND l.last_d > l.first_d
ORDER BY adg_kg_per_day DESC NULLS LAST, a.tag_number LIMIT 20
