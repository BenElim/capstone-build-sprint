-- V7: found by tests/cross_tenant_fk_test.sql (evidence: tests/cross_tenant_fk_before_V7.out).
-- Foreign-key checks run with the table owner's rights and ignore RLS, so tenant 1 could insert a row
-- (ranch_id = 1) that points at tenant 2's animal. Composite FKs tie the child's ranch_id to the parent's.
ALTER TABLE animals  ADD CONSTRAINT animals_ranch_animal_uk   UNIQUE (ranch_id, animal_id);
ALTER TABLE pastures ADD CONSTRAINT pastures_ranch_pasture_uk UNIQUE (ranch_id, pasture_id);
ALTER TABLE buyers   ADD CONSTRAINT buyers_ranch_buyer_uk     UNIQUE (ranch_id, buyer_id);

ALTER TABLE weight_records  ADD CONSTRAINT weight_same_ranch  FOREIGN KEY (ranch_id, animal_id)  REFERENCES animals  (ranch_id, animal_id);
ALTER TABLE health_events   ADD CONSTRAINT health_same_ranch  FOREIGN KEY (ranch_id, animal_id)  REFERENCES animals  (ranch_id, animal_id);
ALTER TABLE sales           ADD CONSTRAINT sales_animal_same_ranch FOREIGN KEY (ranch_id, animal_id) REFERENCES animals (ranch_id, animal_id);
ALTER TABLE sales           ADD CONSTRAINT sales_buyer_same_ranch  FOREIGN KEY (ranch_id, buyer_id)  REFERENCES buyers  (ranch_id, buyer_id);
ALTER TABLE feed_logs       ADD CONSTRAINT feed_same_ranch    FOREIGN KEY (ranch_id, pasture_id) REFERENCES pastures (ranch_id, pasture_id);
ALTER TABLE animals         ADD CONSTRAINT animals_pasture_same_ranch FOREIGN KEY (ranch_id, pasture_id) REFERENCES pastures (ranch_id, pasture_id);
ALTER TABLE breeding_events ADD CONSTRAINT breeding_dam_same_ranch FOREIGN KEY (ranch_id, dam_id) REFERENCES animals (ranch_id, animal_id);
