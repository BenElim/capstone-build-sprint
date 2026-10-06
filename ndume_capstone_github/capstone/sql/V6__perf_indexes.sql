-- V6: added AFTER measuring (evidence/before_Q1.txt, before_Q2.txt): each animal's weight lookup
-- did a Seq Scan over all of weight_records. This composite index serves
--   "latest weight for animal X"  and  "weights for animal X since date D"
-- and INCLUDE (weight_kg) keeps the value in the index so the heap visit is only needed for the RLS tenant check.
CREATE INDEX idx_weight_animal_date ON weight_records (animal_id, weighed_on DESC) INCLUDE (weight_kg);
-- Partial index for the overdue-vaccination dashboard card (small: only rows that can ever be overdue).
CREATE INDEX idx_health_vacc_due ON health_events (next_due_on) WHERE event_type = 'vaccination';
ANALYZE weight_records;   -- VACUUM cannot run inside a migration transaction
