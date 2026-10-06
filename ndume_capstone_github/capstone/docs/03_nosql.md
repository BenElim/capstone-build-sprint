# Day 3: NoSQL Layer

Principle: PostgreSQL stays the system of record. A second store is added only where it solves a problem PostgreSQL solves worse.

| Store | Used for | Status in this build |
|---|---|---|
| Redis | dashboard cache, login sessions, rate limiting, recent-activity feed | **Built and run** (`nosql/redis_demo.sh`, output in `nosql/redis_demo.out`) |
| MongoDB | collar sensor readings (GPS, temperature) | **Designed, script written, NOT run.** No MongoDB server could be installed in the build sandbox. Run `nosql/mongo/collar_readings.js` with `mongosh` to verify. |

## Redis

| Use | Key pattern | Why Redis beats PostgreSQL here |
|---|---|---|
| Herd dashboard cache | `ranch:<id>:dashboard:herd` with a 300 s TTL | The same aggregate is read on every dashboard load but changes only when weights or sales change. A key lookup in memory is far cheaper than recomputing an aggregate over 570k rows, and TTL expiry is built in (PostgreSQL has no per-row expiry). |
| Sessions | `session:<token>` (hash), expires in 30 min | Short-lived, key-value, high read rate, must expire by itself. Putting it in PostgreSQL would add write load and need a cleanup job. |
| Rate limiting | `ratelimit:login:<ip>` with `INCR` + `EXPIRE` | Atomic counters with expiry in one round trip. Doing this in PostgreSQL needs row locks or a table that churns. |
| Recent weigh-ins feed | `ranch:<id>:feed:weighins` (list, `LTRIM` to 5) | A capped, newest-first list is a native Redis structure. |

**Measured result (this sandbox):** cold dashboard fetch from PostgreSQL about 50 to 75 ms across runs (after the V6 index), cached read about 6 to 7 ms including `redis-cli` process start. Before the index was added the cold fetch was about 30 seconds, which is the real lesson: **a cache must not be used to hide a missing index.** Fix the query first, cache second.

**Pattern:** cache-aside. Read Redis first. On a miss, query PostgreSQL (with the tenant set, so RLS still applies) and store the result with a TTL. The write path deletes the key when weights or sales change.

**Risks and rules**
* Tenant isolation lives in the key name (`ranch:<id>:`). The application must build the key from the authenticated session, never from user input.
* Redis is not durable by default and is **never** the only copy of anything. Losing it costs speed, not data.
* Do not cache `sales` or financial totals for non-owner roles. Cache per role, or skip caching, for anything gated by RLS roles.
* Bind Redis to localhost or a private network, set `requirepass`/ACLs in production.

## MongoDB (design only)

**Problem:** neck collars emit a reading (GPS, temperature, battery) every few minutes per animal. For 6,000 animals at 5-minute intervals that is about 1.7 million readings per day. Different collar vendors send different fields.

**Why a document store fits:** append-only, never updated, queried only by animal and time range, vendor-specific fields vary without migrations, and old data should expire automatically.

**Why not PostgreSQL:** it could store this (a partitioned table would work), but that means a schema migration every time a vendor changes fields, and the volume would dwarf the transactional data in the same database and slow its backups. This is a judgement call, not a hard limit. At small scale plain PostgreSQL is the simpler choice.

**Design** (`nosql/mongo/collar_readings.js`): a time-series collection (`timeField: ts`, `metaField: {ranch_id, animal_id, collar_id}`), 180-day automatic expiry, an index on the metadata and time, and two example access patterns (latest reading per animal, fever alert). IDs refer back to PostgreSQL keys; alerts that matter become `health_events` rows in PostgreSQL so they stay relational and audited.

**Honesty note:** this script has not been executed. Syntax and the time-series options follow the MongoDB 5.0+ documentation as I know it, so treat it as a starting point and test it before relying on it.
