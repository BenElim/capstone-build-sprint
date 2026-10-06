-- V2: baseline indexes. PKs/UNIQUEs already exist; add FK and tenant-lookup indexes.
-- Deliberately NOT included: the composite indexes for the analytical queries.
-- Those are added in V6 only after EXPLAIN ANALYZE proves the need (see docs/04_optimization.md).
CREATE INDEX idx_app_users_ranch      ON app_users (ranch_id);
CREATE INDEX idx_pastures_ranch       ON pastures (ranch_id);
CREATE INDEX idx_animals_ranch_status ON animals (ranch_id, status);
CREATE INDEX idx_animals_breed        ON animals (breed_id);
CREATE INDEX idx_animals_pasture      ON animals (pasture_id);
CREATE INDEX idx_animals_dam          ON animals (dam_id);
CREATE INDEX idx_animals_sire         ON animals (sire_id);
CREATE INDEX idx_health_animal        ON health_events (animal_id);
CREATE INDEX idx_breeding_dam         ON breeding_events (dam_id);
CREATE INDEX idx_feed_pasture         ON feed_logs (pasture_id);
CREATE INDEX idx_sales_ranch          ON sales (ranch_id);
