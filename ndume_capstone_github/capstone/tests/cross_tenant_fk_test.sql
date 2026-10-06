-- Can tenant 1 attach its own-ranch row to ANOTHER tenant's parent row? (FK checks bypass RLS)
-- Ranch-2 animal id below was looked up as admin: 2001
BEGIN; SET LOCAL app.ranch_id='1'; SET LOCAL app.role='owner'; SET LOCAL app.user_id='1';
\echo '--- tenant 1 inserts a weigh-in pointing at a ranch-2 animal (expect REJECTED after V7)'
INSERT INTO weight_records (animal_id, ranch_id, weighed_on, weight_kg) VALUES (2001, 1, current_date, 100);
ROLLBACK;
