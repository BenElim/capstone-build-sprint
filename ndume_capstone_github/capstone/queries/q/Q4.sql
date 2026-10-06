-- Q4: margin per sold animal = sale price - lifetime health cost (owner/manager only, via RLS)
SELECT a.tag_number, s.price_kes,
       COALESCE(sum(h.cost_kes),0) AS health_cost,
       s.price_kes - COALESCE(sum(h.cost_kes),0) AS margin_kes
FROM sales s
JOIN animals a USING (animal_id)
LEFT JOIN health_events h ON h.animal_id = s.animal_id
GROUP BY a.tag_number, s.price_kes
ORDER BY margin_kes DESC LIMIT 20
