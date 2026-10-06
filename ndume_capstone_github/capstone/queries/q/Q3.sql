-- Q3: vaccinations overdue as of 2026-10-01 (not followed by a later vaccination of the same medicine)
SELECT a.tag_number, h.medicine, h.next_due_on
FROM health_events h
JOIN animals a USING (animal_id)
WHERE a.status = 'active' AND h.event_type = 'vaccination' AND h.next_due_on < DATE '2026-10-01'
  AND NOT EXISTS (SELECT 1 FROM health_events h2
                  WHERE h2.animal_id = h.animal_id AND h2.medicine = h.medicine AND h2.event_date > h.event_date)
ORDER BY h.next_due_on LIMIT 50
