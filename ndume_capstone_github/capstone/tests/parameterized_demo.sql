-- Parameterized queries: values travel separately from SQL text (extended protocol via psql \bind).
-- An injection attempt is treated as plain data, so it matches nothing and does no harm.
BEGIN; SET LOCAL app.ranch_id='1'; SET LOCAL app.role='owner';
\echo '--- normal lookup by tag'
SELECT tag_number, status FROM animals WHERE tag_number = $1 \bind 'R1-00012' \g
\echo '--- injection attempt as a bound parameter (expect 0 rows)'
SELECT tag_number FROM animals WHERE tag_number = $1 \bind 'x'' OR ''1''=''1' \g
\echo '--- injection attempt that would drop a table if concatenated (expect 0 rows, table intact)'
SELECT tag_number FROM animals WHERE tag_number = $1 \bind '''; DROP TABLE animals; --' \g
SELECT count(*) AS animals_still_there FROM animals;
ROLLBACK;
