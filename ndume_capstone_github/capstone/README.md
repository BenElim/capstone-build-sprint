# Ndume Ranch: Capstone Database Project

A multi-tenant cattle ranch management database. Many ranches share one PostgreSQL 16 database, and each ranch sees only its own data (row-level security). Includes versioned migrations, a Redis layer, a MongoDB design, query-optimization evidence, security tests, and a backup with a verified test restore.

![ER diagram](docs/er_diagram.png)

## Results at a glance

| Query | Before | After | Fix |
|---|---|---|---|
| Herd by breed (dashboard card) | 32.3 s | 10.9 ms | composite index on `weight_records (animal_id, weighed_on DESC)` |
| Average daily gain, top 20 | 35.4 s | 18.0 ms | same index + query rewrite |
| Overdue vaccinations | 10.5 ms | 0.8 ms | partial index |

Measured with `EXPLAIN (ANALYZE, BUFFERS)` on 569,696 weigh-ins, single runs on one machine. Raw plans: [`evidence/`](evidence). Write-up: [`docs/04_optimization.md`](docs/04_optimization.md).

## Repository layout

| Path | What |
|---|---|
| `docs/01_requirements.md`, `docs/er_diagram.*` | Day 1: requirements and ER diagram (Mermaid source included) |
| `sql/V1` to `V7` | Day 2: Flyway-style migrations (V6 indexes and V7 tenant-safe foreign keys were added after testing) |
| `nosql/`, `docs/03_nosql.md` | Day 3: Redis demo (run) and MongoDB script (not run) |
| `queries/`, `evidence/`, `docs/04_optimization.md` | Day 4: analytical queries, before/after plans |
| `scripts/backup.sh`, `tests/`, `docs/05_security_checklist.md` | Day 5: backup + test restore, security tests, checklist |
| `presentation/Ndume_Ranch_Capstone.pptx` | Final walkthrough deck |
| `docs/feedback_log.md` | Fill in the feedback you get on the ER design |

## Run it

Requirements: PostgreSQL 16 (with `pgcrypto`), `psql`, optionally Redis and Flyway.

```bash
createdb capstone

# Real Flyway (recommended):
flyway -url=jdbc:postgresql://localhost:5432/capstone -user=postgres \
       -locations=filesystem:sql -cleanDisabled=false clean migrate

# Or the included stand-in (same file naming and history table):
./run_migrations.sh clean migrate

psql -U capstone_app -d capstone -f tests/security_tests.sql   # security tests
./queries/explain.sh after                                      # EXPLAIN ANALYZE evidence
./scripts/backup.sh                                             # pg_dump -Fc + test restore
```

Set `PGHOST`, `PGPORT` and `PGUSER` first if your server is not on the defaults.

Demo logins (seed data only): `owner@ranch1.example` / `demo-owner-1`, and the same pattern for `manager`, `vet`, `worker` and ranches 2 and 3. **Demo passwords, role passwords and the phone-encryption key are placeholders. Change them before any real use.**

## Security summary

Least-privilege roles, RLS on 11 tables, bcrypt passwords, encrypted buyer phone numbers, audit log on four critical tables, tenant-consistent foreign keys, and a tested backup restore. See [`docs/05_security_checklist.md`](docs/05_security_checklist.md) for evidence and the full list of gaps.

## Honest status

* Real Flyway was **not** run when this was built (download blocked in the build environment). Run the Flyway command above and confirm it succeeds before submitting.
* The MongoDB script is **designed, not executed**.
* No application code is included, so parameterized-query safety is shown at the database level only.
* The Day 1 feedback step is yours to complete: share the ER diagram and record comments in `docs/feedback_log.md`.
