-- Q5: pedigree: all descendants of one animal (recursive CTE)
WITH RECURSIVE tree AS (
  SELECT animal_id, tag_number, dam_id, 1 AS gen FROM animals WHERE animal_id = (SELECT min(animal_id) FROM animals WHERE sex='F')
  UNION ALL
  SELECT c.animal_id, c.tag_number, c.dam_id, t.gen + 1
  FROM animals c JOIN tree t ON c.dam_id = t.animal_id WHERE t.gen < 6)
SELECT gen, count(*) FROM tree GROUP BY gen ORDER BY gen
