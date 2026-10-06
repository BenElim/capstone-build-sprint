# Day 4: Query Optimization with Evidence

**Data size:** 6,000 animals, 569,696 weigh-ins, 18,000 health events, 450 sales, 3 ranches.
**How measured:** `EXPLAIN (ANALYZE, BUFFERS)` as the application role `capstone_app` with a tenant set, so row-level security is included in every number. PostgreSQL 16.15, single run each, caches not specially warmed. BEFORE plans were taken with migrations V1 to V5 applied; AFTER plans with V1 to V7 applied. Raw output is in `evidence/`. Regenerate with `queries/explain.sh before|after` and `python3 scripts/make_optimization_doc.py`.

**Method:** the baseline schema (V1 to V5) deliberately has only the obvious foreign-key and tenant indexes. I measured all five dashboard queries first, then added the indexes in a **new migration** (`V6__perf_indexes.sql`) instead of editing V2, so the change is versioned and the before/after is reproducible.

## Summary

| Query | Before | After | Change |
|---|---|---|---|
| Q1 herd by breed, avg latest weight | 32.3 s | 10.9 ms | V6 index: per-animal Seq Scan to Index Scan |
| Q2 average daily gain, top 20 | 35.4 s | 57.9 ms (index only), 18.0 ms (index + rewrite) | V6 index, then query rewrite |
| Q3 overdue vaccinations | 10.5 ms | 0.8 ms | V6 partial index |
| Q4 margin per sold animal | 1.6 ms | 1.5 ms | none needed (already fast; difference is noise) |
| Q5 pedigree recursive CTE | 0.2 ms | 0.2 ms | none needed (already fast; difference is noise) |

Q4 and Q5 are documented to show that not everything needs optimizing. Adding indexes to fast queries only slows writes.

> Honest caveat: single runs on one machine. Absolute times will differ on your hardware; the **ratio** and the **plan shape change** are what to trust. Run-to-run variation of a few milliseconds is normal (Q1 measured between 10.9 and 17.7 ms across my runs). The Q5 start animal may have few descendants in this demo data, so its plan is trivially small.

## Q1. Q1 herd by breed with latest weight

**1. QUERY:** What is the herd size and average latest weight per breed? (main dashboard card)

```sql
SELECT b.name AS breed, count(*) AS head, round(avg(w.weight_kg),1) AS avg_latest_kg
FROM animals a
JOIN breeds b USING (breed_id)
JOIN LATERAL (SELECT weight_kg FROM weight_records w
              WHERE w.animal_id = a.animal_id ORDER BY weighed_on DESC LIMIT 1) w ON true
WHERE a.status = 'active'
GROUP BY b.name ORDER BY head DESC
```

**2. BEFORE PLAN** (32.3 s)

```
 Sort  (cost=35132951.97..35132951.98 rows=5 width=47) (actual time=32326.904..32326.908 rows=5 loops=1)
   Sort Key: (count(*)) DESC
   Sort Method: quicksort  Memory: 25kB
   Buffers: shared hit=8783849
   ->  GroupAggregate  (cost=19025.95..35132951.91 rows=5 width=47) (actual time=6566.697..32326.872 rows=5 loops=1)
         Group Key: b.name
         Buffers: shared hit=8783846
         ->  Nested Loop  (cost=19025.95..35132937.96 rows=1850 width=13) (actual time=227.679..32322.462 rows=1850 loops=1)
               Buffers: shared hit=8783846
               ->  Nested Loop  (cost=35.39..351.09 rows=1850 width=15) (actual time=205.931..210.593 rows=1850 loops=1)
                     Join Filter: (a.breed_id = b.breed_id)
                     Rows Removed by Join Filter: 7400
                     Buffers: shared hit=43
                     ->  Index Scan using breeds_name_key on breeds b  (cost=0.13..12.21 rows=5 width=11) (actual time=0.003..0.025 rows=5 loops=1)
                           Buffers: shared hit=2
                     ->  Materialize  (cost=35.26..204.75 rows=1850 width=12) (actual time=41.183..41.784 rows=1850 loops=5)
                           Buffers: shared hit=41
                           ->  Bitmap Heap Scan on animals a  (cost=35.26..195.50 rows=1850 width=12) (actual time=205.909..206.841 rows=1850 loops=1)
                                 Recheck Cond: ((ranch_id = (NULLIF(current_setting('app.ranch_id'::text, true), ''::text))::integer) AND (status = 'active'::text))
                                 Heap Blocks: exact=37
                                 Buffers: shared hit=41
                                 ->  Bitmap Index Scan on idx_animals_ranch_status  (cost=0.00..34.79 rows=1850 width=0) (actual time=205.881..205.882 rows=1850 loops=1)
                                       Index Cond: ((ranch_id = (NULLIF(current_setting('app.ranch_id'::text, true), ''::text))::integer) AND (status = 'active'::text))
                                       Buffers: shared hit=4
               ->  Limit  (cost=18990.57..18990.57 rows=1 width=10) (actual time=17.355..17.356 rows=1 loops=1850)
                     Buffers: shared hit=8783803
                     ->  Sort  (cost=18990.57..18990.65 rows=33 width=10) (actual time=17.353..17.353 rows=1 loops=1850)
                           Sort Key: w.weighed_on DESC
                           Sort Method: top-N heapsort  Memory: 25kB
                           Buffers: shared hit=8783803
                           ->  Seq Scan on weight_records w  (cost=0.00..18990.40 rows=33 width=10) (actual time=6.827..17.335 rows=95 loops=1850)
                                 Filter: ((animal_id = a.animal_id) AND (ranch_id = (NULLIF(current_setting('app.ranch_id'::text, true), ''::text))::integer))
                                 Rows Removed by Filter: 569601
                                 Buffers: shared hit=8783800
 Planning:
   Buffers: shared hit=390 dirtied=1
 Planning Time: 0.941 ms
 JIT:
   Functions: 21
   Options: Inlining true, Optimization true, Expressions true, Deforming true
   Timing: Generation 0.946 ms, Inlining 65.048 ms, Optimization 85.011 ms, Emission 55.798 ms, Total 206.803 ms
 Execution Time: 32344.796 ms
```

**3. CHANGE:** `CREATE INDEX idx_weight_animal_date ON weight_records (animal_id, weighed_on DESC) INCLUDE (weight_kg);` (V6). The `LATERAL ... ORDER BY weighed_on DESC LIMIT 1` runs once per active animal (1,850 times). With no index on `weight_records.animal_id` each run was a Seq Scan of all 569,696 rows. The composite index lets each lookup read the newest row for that animal directly.

**4. AFTER PLAN** (10.9 ms)

```
 Sort  (cost=18373.18..18373.20 rows=5 width=47) (actual time=10.842..10.845 rows=5 loops=1)
   Sort Key: (count(*)) DESC
   Sort Method: quicksort  Memory: 25kB
   Buffers: shared hit=7446
   ->  GroupAggregate  (cost=35.81..18373.13 rows=5 width=47) (actual time=3.594..10.816 rows=5 loops=1)
         Group Key: b.name
         Buffers: shared hit=7443
         ->  Nested Loop  (cost=35.81..18359.18 rows=1850 width=13) (actual time=0.105..10.459 rows=1850 loops=1)
               Buffers: shared hit=7443
               ->  Nested Loop  (cost=35.39..351.09 rows=1850 width=15) (actual time=0.080..1.965 rows=1850 loops=1)
                     Join Filter: (a.breed_id = b.breed_id)
                     Rows Removed by Join Filter: 7400
                     Buffers: shared hit=43
                     ->  Index Scan using breeds_name_key on breeds b  (cost=0.13..12.21 rows=5 width=11) (actual time=0.005..0.009 rows=5 loops=1)
                           Buffers: shared hit=2
                     ->  Materialize  (cost=35.26..204.75 rows=1850 width=12) (actual time=0.014..0.240 rows=1850 loops=5)
                           Buffers: shared hit=41
                           ->  Bitmap Heap Scan on animals a  (cost=35.26..195.50 rows=1850 width=12) (actual time=0.065..0.388 rows=1850 loops=1)
                                 Recheck Cond: ((ranch_id = (NULLIF(current_setting('app.ranch_id'::text, true), ''::text))::integer) AND (status = 'active'::text))
                                 Heap Blocks: exact=37
                                 Buffers: shared hit=41
                                 ->  Bitmap Index Scan on idx_animals_ranch_status  (cost=0.00..34.79 rows=1850 width=0) (actual time=0.052..0.052 rows=1850 loops=1)
                                       Index Cond: ((ranch_id = (NULLIF(current_setting('app.ranch_id'::text, true), ''::text))::integer) AND (status = 'active'::text))
                                       Buffers: shared hit=4
               ->  Limit  (cost=0.42..9.71 rows=1 width=10) (actual time=0.004..0.004 rows=1 loops=1850)
                     Buffers: shared hit=7400
                     ->  Index Scan using idx_weight_animal_date on weight_records w  (cost=0.42..306.97 rows=33 width=10) (actual time=0.004..0.004 rows=1 loops=1850)
                           Index Cond: (animal_id = a.animal_id)
                           Filter: (ranch_id = (NULLIF(current_setting('app.ranch_id'::text, true), ''::text))::integer)
                           Buffers: shared hit=7400
 Planning:
   Buffers: shared hit=442
 Planning Time: 1.064 ms
 Execution Time: 10.949 ms
```

**5. RESULT:** 32.3 s to 10.9 ms. Seq Scan (loops=1850, about 8.78 M buffer hits in the BEFORE plan) became Index Scan using `idx_weight_animal_date` (loops=1850, a few thousandths of a millisecond per lookup). The query text was not changed.

## Q2. Q2 average daily gain (original query)

**1. QUERY:** Which animals gained weight fastest in the last 90 days?

```sql
SELECT a.tag_number,
       round((max(w.weight_kg) FILTER (WHERE w.weighed_on = l.last_d)
            - max(w.weight_kg) FILTER (WHERE w.weighed_on = l.first_d))
            / NULLIF(l.last_d - l.first_d, 0), 3) AS adg_kg_per_day
FROM animals a
JOIN weight_records w ON w.animal_id = a.animal_id AND w.weighed_on >= DATE '2026-10-01' - 90
JOIN LATERAL (SELECT min(weighed_on) first_d, max(weighed_on) last_d
              FROM weight_records x WHERE x.animal_id = a.animal_id AND x.weighed_on >= DATE '2026-10-01' - 90) l ON true
WHERE a.status = 'active'
GROUP BY a.tag_number, l.first_d, l.last_d
HAVING l.last_d > l.first_d
ORDER BY adg_kg_per_day DESC NULLS LAST LIMIT 20
```

**2. BEFORE PLAN** (35.4 s)

```
 Limit  (cost=38092552.99..38092553.04 rows=20 width=49) (actual time=35398.520..35398.526 rows=20 loops=1)
   Buffers: shared hit=8789830
   ->  Sort  (cost=38092552.99..38092557.62 rows=1850 width=49) (actual time=35132.114..35132.118 rows=20 loops=1)
         Sort Key: (round(((max(w.weight_kg) FILTER (WHERE (w.weighed_on = (max(x.weighed_on)))) - max(w.weight_kg) FILTER (WHERE (w.weighed_on = (min(x.weighed_on))))) / (NULLIF(((max(x.weighed_on)) - (min(x.weighed_on))), 0))::numeric), 3)) DESC NULLS LAST
         Sort Method: top-N heapsort  Memory: 27kB
         Buffers: shared hit=8789830
         ->  GroupAggregate  (cost=40994.35..38092503.76 rows=1850 width=49) (actual time=206.789..35130.640 rows=1571 loops=1)
               Group Key: a.tag_number, (min(x.weighed_on)), (max(x.weighed_on))
               Buffers: shared hit=8789827
               ->  Incremental Sort  (cost=40994.35..38092398.08 rows=3396 width=27) (actual time=206.733..35125.587 rows=10051 loops=1)
                     Sort Key: a.tag_number, (min(x.weighed_on)), (max(x.weighed_on))
                     Presorted Key: a.tag_number
                     Full-sort Groups: 295  Sort Method: quicksort  Average Memory: 27kB  Peak Memory: 27kB
                     Buffers: shared hit=8789827
                     ->  Nested Loop  (cost=20414.94..38092299.37 rows=3396 width=27) (actual time=52.753..35114.776 rows=10051 loops=1)
                           Join Filter: (a.animal_id = w.animal_id)
                           Rows Removed by Join Filter: 17057293
                           Buffers: shared hit=8789821
                           ->  Nested Loop  (cost=20414.94..37767615.19 rows=1850 width=25) (actual time=37.064..33361.920 rows=1571 loops=1)
                                 Buffers: shared hit=8785073
                                 ->  Index Scan using animals_ranch_id_tag_number_key on animals a  (cost=0.29..452.56 rows=1850 width=17) (actual time=0.053..7.389 rows=1850 loops=1)
                                       Index Cond: (ranch_id = (NULLIF(current_setting('app.ranch_id'::text, true), ''::text))::integer)
                                       Filter: (status = 'active'::text)
                                       Rows Removed by Filter: 150
                                       Buffers: shared hit=1273
                                 ->  Aggregate  (cost=20414.65..20414.66 rows=1 width=8) (actual time=18.027..18.027 rows=1 loops=1850)
                                       Filter: (max(x.weighed_on) > min(x.weighed_on))
                                       Rows Removed by Filter: 0
                                       Buffers: shared hit=8783800
                                       ->  Seq Scan on weight_records x  (cost=0.00..20414.64 rows=2 width=4) (actual time=9.409..18.021 rows=5 loops=1850)
                                             Filter: ((weighed_on >= '2026-07-03'::date) AND (animal_id = a.animal_id) AND (ranch_id = (NULLIF(current_setting('app.ranch_id'::text, true), ''::text))::integer))
                                             Rows Removed by Filter: 569691
                                             Buffers: shared hit=8783800
                           ->  Materialize  (cost=0.00..19045.48 rows=11015 width=18) (actual time=0.001..0.521 rows=10864 loops=1571)
                                 Buffers: shared hit=4748
                                 ->  Seq Scan on weight_records w  (cost=0.00..18990.40 rows=11015 width=18) (actual time=0.019..19.478 rows=10864 loops=1)
                                       Filter: ((weighed_on >= '2026-07-03'::date) AND (ranch_id = (NULLIF(current_setting('app.ranch_id'::text, true), ''::text))::integer))
                                       Rows Removed by Filter: 558832
                                       Buffers: shared hit=4748
 Planning:
   Buffers: shared hit=370
 Planning Time: 1.039 ms
 JIT:
   Functions: 27
   Options: Inlining true, Optimization true, Expressions true, Deforming true
   Timing: Generation 1.424 ms, Inlining 64.201 ms, Optimization 124.231 ms, Emission 78.078 ms, Total 267.934 ms
 Execution Time: 35413.472 ms
```

**3. CHANGE:** Same V6 index, no query change. This isolates the index's contribution.

**4. AFTER PLAN** (57.9 ms)

```
 Limit  (cost=64179.05..64179.10 rows=20 width=49) (actual time=57.719..57.726 rows=20 loops=1)
   Buffers: shared hit=11227
   ->  Sort  (cost=64179.05..64183.67 rows=1850 width=49) (actual time=57.718..57.723 rows=20 loops=1)
         Sort Key: (round(((max(w.weight_kg) FILTER (WHERE (w.weighed_on = l.last_d)) - max(w.weight_kg) FILTER (WHERE (w.weighed_on = l.first_d))) / (NULLIF((l.last_d - l.first_d), 0))::numeric), 3)) DESC NULLS LAST
         Sort Method: top-N heapsort  Memory: 27kB
         Buffers: shared hit=11227
         ->  GroupAggregate  (cost=64016.75..64129.82 rows=1850 width=49) (actual time=54.741..57.363 rows=1571 loops=1)
               Group Key: a.tag_number, l.first_d, l.last_d
               Buffers: shared hit=11224
               ->  Sort  (cost=64016.75..64025.10 rows=3341 width=27) (actual time=54.723..55.180 rows=10051 loops=1)
                     Sort Key: a.tag_number, l.first_d, l.last_d
                     Sort Method: quicksort  Memory: 934kB
                     Buffers: shared hit=11224
                     ->  Nested Loop  (cost=242.67..63821.20 rows=3341 width=27) (actual time=0.739..50.154 rows=10051 loops=1)
                           Buffers: shared hit=11218
                           ->  Hash Join  (cost=218.63..19237.50 rows=3341 width=27) (actual time=0.718..36.861 rows=10059 loops=1)
                                 Hash Cond: (w.animal_id = a.animal_id)
                                 Buffers: shared hit=4789
                                 ->  Seq Scan on weight_records w  (cost=0.00..18990.40 rows=10836 width=18) (actual time=0.069..34.092 rows=10864 loops=1)
                                       Filter: ((weighed_on >= '2026-07-03'::date) AND (ranch_id = (NULLIF(current_setting('app.ranch_id'::text, true), ''::text))::integer))
                                       Rows Removed by Filter: 558832
                                       Buffers: shared hit=4748
                                 ->  Hash  (cost=195.50..195.50 rows=1850 width=17) (actual time=0.633..0.634 rows=1850 loops=1)
                                       Buckets: 2048  Batches: 1  Memory Usage: 118kB
                                       Buffers: shared hit=41
                                       ->  Bitmap Heap Scan on animals a  (cost=35.26..195.50 rows=1850 width=17) (actual time=0.063..0.321 rows=1850 loops=1)
                                             Recheck Cond: ((ranch_id = (NULLIF(current_setting('app.ranch_id'::text, true), ''::text))::integer) AND (status = 'active'::text))
                                             Heap Blocks: exact=37
                                             Buffers: shared hit=41
                                             ->  Bitmap Index Scan on idx_animals_ranch_status  (cost=0.00..34.79 rows=1850 width=0) (actual time=0.051..0.052 rows=1850 loops=1)
                                                   Index Cond: ((ranch_id = (NULLIF(current_setting('app.ranch_id'::text, true), ''::text))::integer) AND (status = 'active'::text))
                                                   Buffers: shared hit=4
                           ->  Memoize  (cost=24.04..24.06 rows=1 width=8) (actual time=0.001..0.001 rows=1 loops=10059)
                                 Cache Key: a.animal_id
                                 Cache Mode: binary
                                 Hits: 8480  Misses: 1579  Evictions: 0  Overflows: 0  Memory Usage: 173kB
                                 Buffers: shared hit=6429
                                 ->  Subquery Scan on l  (cost=24.03..24.05 rows=1 width=8) (actual time=0.005..0.005 rows=1 loops=1579)
                                       Buffers: shared hit=6429
                                       ->  Aggregate  (cost=24.03..24.04 rows=1 width=8) (actual time=0.005..0.005 rows=1 loops=1579)
                                             Filter: (max(x.weighed_on) > min(x.weighed_on))
                                             Rows Removed by Filter: 0
                                             Buffers: shared hit=6429
                                             ->  Index Scan using idx_weight_animal_date on weight_records x  (cost=0.42..24.02 rows=2 width=4) (actual time=0.003..0.004 rows=6 loops=1579)
                                                   Index Cond: ((animal_id = a.animal_id) AND (weighed_on >= '2026-07-03'::date))
                                                   Filter: (ranch_id = (NULLIF(current_setting('app.ranch_id'::text, true), ''::text))::integer)
                                                   Buffers: shared hit=6429
 Planning:
   Buffers: shared hit=434
 Planning Time: 1.407 ms
 Execution Time: 57.944 ms
```

**5. RESULT:** 35.4 s to 57.9 ms. The remaining cost is a Seq Scan on `weight_records` for the outer join (about 11k rows kept of 569k), plus joining and re-aggregating the same rows.

## Q2b. Q2b average daily gain (rewritten)

**1. QUERY:** Same question as Q2, same answer.

```sql
SELECT a.tag_number,
       round((l.last_kg - l.first_kg) / NULLIF(l.last_d - l.first_d, 0), 3) AS adg_kg_per_day
FROM animals a
JOIN LATERAL (
    SELECT min(weighed_on) AS first_d, max(weighed_on) AS last_d,
           (array_agg(weight_kg ORDER BY weighed_on))[1]      AS first_kg,
           (array_agg(weight_kg ORDER BY weighed_on DESC))[1] AS last_kg
    FROM weight_records w
    WHERE w.animal_id = a.animal_id AND w.weighed_on >= DATE '2026-10-01' - 90) l ON true
WHERE a.status = 'active' AND l.last_d > l.first_d
ORDER BY adg_kg_per_day DESC NULLS LAST, a.tag_number LIMIT 20
```

**2. BEFORE PLAN** (57.9 ms)

```
 Limit  (cost=64179.05..64179.10 rows=20 width=49) (actual time=57.719..57.726 rows=20 loops=1)
   Buffers: shared hit=11227
   ->  Sort  (cost=64179.05..64183.67 rows=1850 width=49) (actual time=57.718..57.723 rows=20 loops=1)
         Sort Key: (round(((max(w.weight_kg) FILTER (WHERE (w.weighed_on = l.last_d)) - max(w.weight_kg) FILTER (WHERE (w.weighed_on = l.first_d))) / (NULLIF((l.last_d - l.first_d), 0))::numeric), 3)) DESC NULLS LAST
         Sort Method: top-N heapsort  Memory: 27kB
         Buffers: shared hit=11227
         ->  GroupAggregate  (cost=64016.75..64129.82 rows=1850 width=49) (actual time=54.741..57.363 rows=1571 loops=1)
               Group Key: a.tag_number, l.first_d, l.last_d
               Buffers: shared hit=11224
               ->  Sort  (cost=64016.75..64025.10 rows=3341 width=27) (actual time=54.723..55.180 rows=10051 loops=1)
                     Sort Key: a.tag_number, l.first_d, l.last_d
                     Sort Method: quicksort  Memory: 934kB
                     Buffers: shared hit=11224
                     ->  Nested Loop  (cost=242.67..63821.20 rows=3341 width=27) (actual time=0.739..50.154 rows=10051 loops=1)
                           Buffers: shared hit=11218
                           ->  Hash Join  (cost=218.63..19237.50 rows=3341 width=27) (actual time=0.718..36.861 rows=10059 loops=1)
                                 Hash Cond: (w.animal_id = a.animal_id)
                                 Buffers: shared hit=4789
                                 ->  Seq Scan on weight_records w  (cost=0.00..18990.40 rows=10836 width=18) (actual time=0.069..34.092 rows=10864 loops=1)
                                       Filter: ((weighed_on >= '2026-07-03'::date) AND (ranch_id = (NULLIF(current_setting('app.ranch_id'::text, true), ''::text))::integer))
                                       Rows Removed by Filter: 558832
                                       Buffers: shared hit=4748
                                 ->  Hash  (cost=195.50..195.50 rows=1850 width=17) (actual time=0.633..0.634 rows=1850 loops=1)
                                       Buckets: 2048  Batches: 1  Memory Usage: 118kB
                                       Buffers: shared hit=41
                                       ->  Bitmap Heap Scan on animals a  (cost=35.26..195.50 rows=1850 width=17) (actual time=0.063..0.321 rows=1850 loops=1)
                                             Recheck Cond: ((ranch_id = (NULLIF(current_setting('app.ranch_id'::text, true), ''::text))::integer) AND (status = 'active'::text))
                                             Heap Blocks: exact=37
                                             Buffers: shared hit=41
                                             ->  Bitmap Index Scan on idx_animals_ranch_status  (cost=0.00..34.79 rows=1850 width=0) (actual time=0.051..0.052 rows=1850 loops=1)
                                                   Index Cond: ((ranch_id = (NULLIF(current_setting('app.ranch_id'::text, true), ''::text))::integer) AND (status = 'active'::text))
                                                   Buffers: shared hit=4
                           ->  Memoize  (cost=24.04..24.06 rows=1 width=8) (actual time=0.001..0.001 rows=1 loops=10059)
                                 Cache Key: a.animal_id
                                 Cache Mode: binary
                                 Hits: 8480  Misses: 1579  Evictions: 0  Overflows: 0  Memory Usage: 173kB
                                 Buffers: shared hit=6429
                                 ->  Subquery Scan on l  (cost=24.03..24.05 rows=1 width=8) (actual time=0.005..0.005 rows=1 loops=1579)
                                       Buffers: shared hit=6429
                                       ->  Aggregate  (cost=24.03..24.04 rows=1 width=8) (actual time=0.005..0.005 rows=1 loops=1579)
                                             Filter: (max(x.weighed_on) > min(x.weighed_on))
                                             Rows Removed by Filter: 0
                                             Buffers: shared hit=6429
                                             ->  Index Scan using idx_weight_animal_date on weight_records x  (cost=0.42..24.02 rows=2 width=4) (actual time=0.003..0.004 rows=6 loops=1579)
                                                   Index Cond: ((animal_id = a.animal_id) AND (weighed_on >= '2026-07-03'::date))
                                                   Filter: (ranch_id = (NULLIF(current_setting('app.ranch_id'::text, true), ''::text))::integer)
                                                   Buffers: shared hit=6429
 Planning:
   Buffers: shared hit=434
 Planning Time: 1.407 ms
 Execution Time: 57.944 ms
```

**3. CHANGE:** Rewrote the query so each animal is visited once through the index (`min/max` and `array_agg ... ORDER BY` inside one LATERAL) instead of joining `weight_records` twice and re-grouping. I compared the output with the original: the same 20 rows with the same values (only the order of exact ties differed, so the rewrite adds `a.tag_number` as a tiebreaker).

**4. AFTER PLAN** (18.0 ms)

```
 Limit  (cost=44876.68..44876.73 rows=20 width=41) (actual time=17.910..17.914 rows=20 loops=1)
   Buffers: shared hit=8990
   ->  Sort  (cost=44876.68..44881.30 rows=1850 width=41) (actual time=17.909..17.911 rows=20 loops=1)
         Sort Key: (round(((((array_agg(w.weight_kg ORDER BY w.weighed_on DESC))[1]) - ((array_agg(w.weight_kg ORDER BY w.weighed_on))[1])) / (NULLIF(((max(w.weighed_on)) - (min(w.weighed_on))), 0))::numeric), 3)) DESC NULLS LAST, a.tag_number
         Sort Method: top-N heapsort  Memory: 26kB
         Buffers: shared hit=8990
         ->  Nested Loop  (cost=24.04..44827.45 rows=1850 width=41) (actual time=0.081..17.472 rows=1571 loops=1)
               Buffers: shared hit=8984
               ->  Seq Scan on animals a  (cost=0.00..264.00 rows=1850 width=17) (actual time=0.009..1.566 rows=1850 loops=1)
                     Filter: ((status = 'active'::text) AND (ranch_id = (NULLIF(current_setting('app.ranch_id'::text, true), ''::text))::integer))
                     Rows Removed by Filter: 4150
                     Buffers: shared hit=114
               ->  Aggregate  (cost=24.04..24.05 rows=1 width=72) (actual time=0.008..0.008 rows=1 loops=1850)
                     Filter: (max(w.weighed_on) > min(w.weighed_on))
                     Rows Removed by Filter: 0
                     Buffers: shared hit=8870
                     ->  Index Scan Backward using idx_weight_animal_date on weight_records w  (cost=0.42..24.02 rows=2 width=10) (actual time=0.003..0.005 rows=5 loops=1850)
                           Index Cond: ((animal_id = a.animal_id) AND (weighed_on >= '2026-07-03'::date))
                           Filter: (ranch_id = (NULLIF(current_setting('app.ranch_id'::text, true), ''::text))::integer)
                           Buffers: shared hit=8867
 Planning:
   Buffers: shared hit=399
 Planning Time: 0.928 ms
 Execution Time: 17.997 ms
```

**5. RESULT:** 57.9 ms to 18.0 ms on top of the index change. Total for Q2: 35.4 s to 18.0 ms.

## Q3. Q3 overdue vaccinations

**1. QUERY:** Which active animals have a vaccination past its due date and no later repeat?

```sql
SELECT a.tag_number, h.medicine, h.next_due_on
FROM health_events h
JOIN animals a USING (animal_id)
WHERE a.status = 'active' AND h.event_type = 'vaccination' AND h.next_due_on < DATE '2026-10-01'
  AND NOT EXISTS (SELECT 1 FROM health_events h2
                  WHERE h2.animal_id = h.animal_id AND h2.medicine = h.medicine AND h2.event_date > h.event_date)
ORDER BY h.next_due_on LIMIT 50
```

**2. BEFORE PLAN** (10.5 ms)

```
 Limit  (cost=1602.03..1602.15 rows=50 width=27) (actual time=10.375..10.384 rows=50 loops=1)
   Buffers: shared hit=11070
   ->  Sort  (cost=1602.03..1603.36 rows=532 width=27) (actual time=10.374..10.379 rows=50 loops=1)
         Sort Key: h.next_due_on
         Sort Method: top-N heapsort  Memory: 30kB
         Buffers: shared hit=11070
         ->  Nested Loop Anti Join  (cost=218.92..1584.36 rows=532 width=27) (actual time=0.762..9.646 rows=3576 loops=1)
               Buffers: shared hit=11067
               ->  Hash Join  (cost=218.63..937.42 rows=798 width=39) (actual time=0.723..4.752 rows=3576 loops=1)
                     Hash Cond: (h.animal_id = a.animal_id)
                     Buffers: shared hit=258
                     ->  Seq Scan on health_events h  (cost=0.00..712.00 rows=2587 width=30) (actual time=0.006..3.281 rows=3876 loops=1)
                           Filter: ((next_due_on < '2026-10-01'::date) AND (event_type = 'vaccination'::text) AND (ranch_id = (NULLIF(current_setting('app.ranch_id'::text, true), ''::text))::integer))
                           Rows Removed by Filter: 14124
                           Buffers: shared hit=217
                     ->  Hash  (cost=195.50..195.50 rows=1850 width=17) (actual time=0.703..0.704 rows=1850 loops=1)
                           Buckets: 2048  Batches: 1  Memory Usage: 118kB
                           Buffers: shared hit=41
                           ->  Bitmap Heap Scan on animals a  (cost=35.26..195.50 rows=1850 width=17) (actual time=0.072..0.357 rows=1850 loops=1)
                                 Recheck Cond: ((ranch_id = (NULLIF(current_setting('app.ranch_id'::text, true), ''::text))::integer) AND (status = 'active'::text))
                                 Heap Blocks: exact=37
                                 Buffers: shared hit=41
                                 ->  Bitmap Index Scan on idx_animals_ranch_status  (cost=0.00..34.79 rows=1850 width=0) (actual time=0.061..0.061 rows=1850 loops=1)
                                       Index Cond: ((ranch_id = (NULLIF(current_setting('app.ranch_id'::text, true), ''::text))::integer) AND (status = 'active'::text))
                                       Buffers: shared hit=4
               ->  Index Scan using idx_health_animal on health_events h2  (cost=0.29..0.80 rows=1 width=26) (actual time=0.001..0.001 rows=0 loops=3576)
                     Index Cond: (animal_id = h.animal_id)
                     Filter: ((event_date > h.event_date) AND (medicine = h.medicine) AND (ranch_id = (NULLIF(current_setting('app.ranch_id'::text, true), ''::text))::integer))
                     Rows Removed by Filter: 3
                     Buffers: shared hit=10809
 Planning:
   Buffers: shared hit=481 dirtied=4
 Planning Time: 1.440 ms
 Execution Time: 10.486 ms
```

**3. CHANGE:** `CREATE INDEX idx_health_vacc_due ON health_events (next_due_on) WHERE event_type = 'vaccination';` (V6). A partial index is small and matches the query's filter exactly.

**4. AFTER PLAN** (0.8 ms)

```
 Limit  (cost=0.88..270.04 rows=50 width=27) (actual time=0.056..0.702 rows=50 loops=1)
   Buffers: shared hit=445
   ->  Nested Loop Anti Join  (cost=0.88..2864.83 rows=532 width=27) (actual time=0.055..0.693 rows=50 loops=1)
         Buffers: shared hit=445
         ->  Nested Loop  (cost=0.59..2217.89 rows=798 width=39) (actual time=0.041..0.472 rows=50 loops=1)
               Buffers: shared hit=294
               ->  Index Scan using idx_health_vacc_due on health_events h  (cost=0.29..969.84 rows=2587 width=30) (actual time=0.017..0.210 rows=51 loops=1)
                     Index Cond: (next_due_on < '2026-10-01'::date)
                     Filter: (ranch_id = (NULLIF(current_setting('app.ranch_id'::text, true), ''::text))::integer)
                     Rows Removed by Filter: 89
                     Buffers: shared hit=141
               ->  Memoize  (cost=0.30..0.54 rows=1 width=17) (actual time=0.005..0.005 rows=1 loops=51)
                     Cache Key: h.animal_id
                     Cache Mode: logical
                     Hits: 0  Misses: 51  Evictions: 0  Overflows: 0  Memory Usage: 7kB
                     Buffers: shared hit=153
                     ->  Index Scan using animals_ranch_animal_uk on animals a  (cost=0.29..0.53 rows=1 width=17) (actual time=0.004..0.004 rows=1 loops=51)
                           Index Cond: ((ranch_id = (NULLIF(current_setting('app.ranch_id'::text, true), ''::text))::integer) AND (animal_id = h.animal_id))
                           Filter: (status = 'active'::text)
                           Rows Removed by Filter: 0
                           Buffers: shared hit=153
         ->  Index Scan using idx_health_animal on health_events h2  (cost=0.29..0.80 rows=1 width=26) (actual time=0.004..0.004 rows=0 loops=50)
               Index Cond: (animal_id = h.animal_id)
               Filter: ((event_date > h.event_date) AND (medicine = h.medicine) AND (ranch_id = (NULLIF(current_setting('app.ranch_id'::text, true), ''::text))::integer))
               Rows Removed by Filter: 3
               Buffers: shared hit=151
 Planning:
   Buffers: shared hit=537
 Planning Time: 1.878 ms
 Execution Time: 0.819 ms
```

**5. RESULT:** 10.5 ms to 0.8 ms. Seq Scan on `health_events` became Index Scan on the partial index.

## Not optimized: Q4 and Q5

Both already run in a couple of milliseconds (see `evidence/before_Q4.txt`, `before_Q5.txt`). I left them alone on purpose.

## Redis effect (links to Day 3)

The dashboard card behind Q1 is cached in Redis for 5 minutes (`nosql/redis_demo.sh`). Before V6 the cold fetch took **33.4 s** (I saw this on the first run of the demo, before V6 existed; that run's output was overwritten when I re-ran the demo after the fix, so only the Q1 plan in `evidence/before_Q1.txt` backs it, at 32.3 s). After V6 a cold fetch takes about 50 to 75 ms (varied across runs) and a cached read about 6 to 7 ms including `redis-cli` process startup (`nosql/redis_demo.out`). **The cache would have hidden a 33-second query. The index fixed it.** The cache is still worth keeping for repeated reads, but it was the wrong first fix.
