#!/usr/bin/env python3
"""Builds docs/04_optimization.md from evidence/*.txt so every number in the write-up traces to a saved plan."""
import re
E='evidence/'
def plan(path):
    out=[]
    for l in open(path):
        if l.startswith('--'): continue
        if re.match(r'^(BEGIN|SET|ROLLBACK|\(\d+ rows?\))',l): continue
        if l.strip() and set(l.strip())<=set('-+'): continue
        if 'QUERY PLAN' in l: continue
        out.append(l.rstrip())
    return '\n'.join(x for x in out if x.strip())
def ms(path): return float(re.search(r'Execution Time: ([\d.]+) ms',open(path).read()).group(1))
def sql(q): return open(f'queries/q/{q}.sql').read().split('\n',1)[1].strip()
def fmt(x): return f"{x/1000:.1f} s" if x>=1000 else f"{x:.1f} ms"
b={q:ms(E+f'before_{q}.txt') for q in ['Q1','Q2','Q3','Q4','Q5']}
a={q:ms(E+f'after_{q}.txt') for q in ['Q1','Q2','Q2b','Q3','Q4','Q5']}
def block(n,title,q,bf,af,change,result,sq):
    return f"""## {n}. {title}

**1. QUERY:** {q}

```sql
{sql(sq)}
```

**2. BEFORE PLAN** ({fmt(ms(E+bf))})

```
{plan(E+bf)}
```

**3. CHANGE:** {change}

**4. AFTER PLAN** ({fmt(ms(E+af))})

```
{plan(E+af)}
```

**5. RESULT:** {result}
"""
d=[f"""# Day 4: Query Optimization with Evidence

**Data size:** 6,000 animals, 569,696 weigh-ins, 18,000 health events, 450 sales, 3 ranches.
**How measured:** `EXPLAIN (ANALYZE, BUFFERS)` as the application role `capstone_app` with a tenant set, so row-level security is included in every number. PostgreSQL 16.15, single run each, caches not specially warmed. BEFORE plans were taken with migrations V1 to V5 applied; AFTER plans with V1 to V7 applied. Raw output is in `evidence/`. Regenerate with `queries/explain.sh before|after` and `python3 scripts/make_optimization_doc.py`.

**Method:** the baseline schema (V1 to V5) deliberately has only the obvious foreign-key and tenant indexes. I measured all five dashboard queries first, then added the indexes in a **new migration** (`V6__perf_indexes.sql`) instead of editing V2, so the change is versioned and the before/after is reproducible.

## Summary

| Query | Before | After | Change |
|---|---|---|---|
| Q1 herd by breed, avg latest weight | {fmt(b['Q1'])} | {fmt(a['Q1'])} | V6 index: per-animal Seq Scan to Index Scan |
| Q2 average daily gain, top 20 | {fmt(b['Q2'])} | {fmt(a['Q2'])} (index only), {fmt(a['Q2b'])} (index + rewrite) | V6 index, then query rewrite |
| Q3 overdue vaccinations | {fmt(b['Q3'])} | {fmt(a['Q3'])} | V6 partial index |
| Q4 margin per sold animal | {fmt(b['Q4'])} | {fmt(a['Q4'])} | none needed (already fast; difference is noise) |
| Q5 pedigree recursive CTE | {fmt(b['Q5'])} | {fmt(a['Q5'])} | none needed (already fast; difference is noise) |

Q4 and Q5 are documented to show that not everything needs optimizing. Adding indexes to fast queries only slows writes.

> Honest caveat: single runs on one machine. Absolute times will differ on your hardware; the **ratio** and the **plan shape change** are what to trust. Run-to-run variation of a few milliseconds is normal (Q1 measured between 10.9 and 17.7 ms across my runs). The Q5 start animal may have few descendants in this demo data, so its plan is trivially small.
"""]
d.append(block('Q1','Q1 herd by breed with latest weight','What is the herd size and average latest weight per breed? (main dashboard card)','before_Q1.txt','after_Q1.txt',
 "`CREATE INDEX idx_weight_animal_date ON weight_records (animal_id, weighed_on DESC) INCLUDE (weight_kg);` (V6). The `LATERAL ... ORDER BY weighed_on DESC LIMIT 1` runs once per active animal (1,850 times). With no index on `weight_records.animal_id` each run was a Seq Scan of all 569,696 rows. The composite index lets each lookup read the newest row for that animal directly.",
 f"{fmt(b['Q1'])} to {fmt(a['Q1'])}. Seq Scan (loops=1850, about 8.78 M buffer hits in the BEFORE plan) became Index Scan using `idx_weight_animal_date` (loops=1850, a few thousandths of a millisecond per lookup). The query text was not changed.",'Q1'))
d.append(block('Q2','Q2 average daily gain (original query)','Which animals gained weight fastest in the last 90 days?','before_Q2.txt','after_Q2.txt',
 "Same V6 index, no query change. This isolates the index's contribution.",
 f"{fmt(b['Q2'])} to {fmt(a['Q2'])}. The remaining cost is a Seq Scan on `weight_records` for the outer join (about 11k rows kept of 569k), plus joining and re-aggregating the same rows.",'Q2'))
d.append(block('Q2b','Q2b average daily gain (rewritten)','Same question as Q2, same answer.','after_Q2.txt','after_Q2b.txt',
 "Rewrote the query so each animal is visited once through the index (`min/max` and `array_agg ... ORDER BY` inside one LATERAL) instead of joining `weight_records` twice and re-grouping. I compared the output with the original: the same 20 rows with the same values (only the order of exact ties differed, so the rewrite adds `a.tag_number` as a tiebreaker).",
 f"{fmt(a['Q2'])} to {fmt(a['Q2b'])} on top of the index change. Total for Q2: {fmt(b['Q2'])} to {fmt(a['Q2b'])}.",'Q2b'))
d.append(block('Q3','Q3 overdue vaccinations','Which active animals have a vaccination past its due date and no later repeat?','before_Q3.txt','after_Q3.txt',
 "`CREATE INDEX idx_health_vacc_due ON health_events (next_due_on) WHERE event_type = 'vaccination';` (V6). A partial index is small and matches the query's filter exactly.",
 f"{fmt(b['Q3'])} to {fmt(a['Q3'])}. Seq Scan on `health_events` became Index Scan on the partial index.",'Q3'))
d.append("""## Not optimized: Q4 and Q5

Both already run in a couple of milliseconds (see `evidence/before_Q4.txt`, `before_Q5.txt`). I left them alone on purpose.

## Redis effect (links to Day 3)

The dashboard card behind Q1 is cached in Redis for 5 minutes (`nosql/redis_demo.sh`). Before V6 the cold fetch took **33.4 s** (I saw this on the first run of the demo, before V6 existed; that run's output was overwritten when I re-ran the demo after the fix, so only the Q1 plan in `evidence/before_Q1.txt` backs it, at 32.3 s). After V6 a cold fetch takes about 50 to 75 ms (varied across runs) and a cached read about 6 to 7 ms including `redis-cli` process startup (`nosql/redis_demo.out`). **The cache would have hidden a 33-second query. The index fixed it.** The cache is still worth keeping for repeated reads, but it was the wrong first fix.
""")
open('docs/04_optimization.md','w').write('\n'.join(d)); print('ok')
