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
ORDER BY adg_kg_per_day DESC NULLS LAST LIMIT 20
