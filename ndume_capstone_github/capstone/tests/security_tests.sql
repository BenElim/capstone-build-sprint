-- Security verification. Run as the app role: psql -U capstone_app -f tests/security_tests.sql
\set ON_ERROR_STOP off
\echo '--- 1. no tenant set => fail closed (expect 0)'
SELECT count(*) AS animals_visible FROM animals;

\echo '--- 2. tenant 1 sees only its own rows (expect 1 distinct ranch, 2000 rows)'
BEGIN; SET LOCAL app.ranch_id='1'; SET LOCAL app.role='owner'; SET LOCAL app.user_id='1';
SELECT count(*) AS animals, count(DISTINCT ranch_id) AS ranches FROM animals;
\echo '--- 3. cannot insert a row for another tenant (expect RLS error)'
INSERT INTO pastures (ranch_id,name,area_ha,capacity_head) VALUES (2,'Evil',1,1);
ROLLBACK;

\echo '--- 4. password_hash and phone_enc are not readable (expect permission denied x2)'
BEGIN; SET LOCAL app.ranch_id='1';
SELECT password_hash FROM app_users LIMIT 1;
ROLLBACK;
BEGIN; SET LOCAL app.ranch_id='1';
SELECT phone_enc FROM buyers LIMIT 1;
ROLLBACK;

\echo '--- 5. worker cannot see sales (expect 0), owner can (expect >0)'
BEGIN; SET LOCAL app.ranch_id='1'; SET LOCAL app.role='worker'; SELECT count(*) AS worker_sales FROM sales; ROLLBACK;
BEGIN; SET LOCAL app.ranch_id='1'; SET LOCAL app.role='owner';  SELECT count(*) AS owner_sales  FROM sales; ROLLBACK;

\echo '--- 6. app cannot delete or tamper with audit log (expect permission denied x2)'
BEGIN; DELETE FROM animals WHERE false; ROLLBACK;
BEGIN; SET LOCAL app.ranch_id='1'; SET LOCAL app.role='owner'; DELETE FROM audit_log; ROLLBACK;
BEGIN; INSERT INTO audit_log (table_name,row_pk,action) VALUES ('x','1','INSERT'); ROLLBACK;

\echo '--- 7. audit trail is written for an update made by the app (expect 1 UPDATE row)'
BEGIN; SET LOCAL app.ranch_id='1'; SET LOCAL app.role='owner'; SET LOCAL app.user_id='1';
UPDATE animals SET name='Test Bull' WHERE animal_id = (SELECT min(animal_id) FROM animals);
SELECT action, changed_by, new_data->>'name' AS new_name FROM audit_log
 WHERE table_name='animals' AND action='UPDATE' ORDER BY audit_id DESC LIMIT 1;
ROLLBACK;

\echo '--- 8. selling an already-sold animal is rejected (expect exception)'
BEGIN; SET LOCAL app.ranch_id='1'; SET LOCAL app.role='owner';
INSERT INTO sales (ranch_id, animal_id, buyer_id, sold_on, price_kes)
SELECT s.ranch_id, s.animal_id, s.buyer_id, current_date, 1000 FROM sales s LIMIT 1;
ROLLBACK;

\echo '--- 9. app role is not a superuser'
SELECT rolname, rolsuper, rolcreaterole, rolcreatedb FROM pg_roles WHERE rolname IN ('capstone_app','capstone_readonly');
