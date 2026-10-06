-- Q1: herd by breed with average LATEST weight (dashboard card)
SELECT b.name AS breed, count(*) AS head, round(avg(w.weight_kg),1) AS avg_latest_kg
FROM animals a
JOIN breeds b USING (breed_id)
JOIN LATERAL (SELECT weight_kg FROM weight_records w
              WHERE w.animal_id = a.animal_id ORDER BY weighed_on DESC LIMIT 1) w ON true
WHERE a.status = 'active'
GROUP BY b.name ORDER BY head DESC
