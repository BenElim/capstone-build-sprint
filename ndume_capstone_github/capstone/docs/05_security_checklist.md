# Day 5: Security Checklist, Backup and Recovery

Each item is marked **PASS**, **PARTIAL** or **NOT DONE** with the evidence file that backs it. Gaps are listed honestly in the last section.

| # | Item | Result | Evidence |
|---|------|--------|----------|
| 1 | Least-privilege roles (no app superuser) | **PASS** | `evidence/security_catalog_checks.txt`: `capstone_app` and `capstone_readonly` are not superuser, cannot create roles/databases, do not bypass RLS. The app has no DELETE anywhere and no write access to `audit_log`. `password_hash` and `phone_enc` are not readable (column-level grants). Tests 4, 6, 9 in `tests/security_tests.out`. |
| 2 | RLS on every multi-tenant / sensitive table | **PASS** | All 11 tenant or sensitive tables have RLS and a policy (`evidence/security_catalog_checks.txt`). `breeds` is shared reference data on purpose. `sales` additionally requires role owner/manager and `audit_log` requires owner. Tests 1, 2, 3, 5 in `tests/security_tests.out`: unset tenant sees 0 rows, tenant sees only its own rows, cross-tenant insert is rejected, a worker sees 0 sales. |
| 2b | Cross-tenant references blocked | **PASS (after fix)** | Found by `tests/cross_tenant_fk_test.sql`: before V7 the insert succeeded (`tests/cross_tenant_fk_before_V7.out`). V7 adds composite foreign keys; now rejected (`tests/cross_tenant_fk_after_V7.out`). |
| 3 | Sensitive fields hashed or encrypted | **PARTIAL** | Passwords: bcrypt cost 10 via `pgcrypto` (`evidence/crypto_checks.txt`, verified with `crypt()`). Buyer phone numbers: `pgp_sym_encrypt`, unreadable by the app role. **Gap:** the demo key is written in the V5 seed file. In production the key must come from a secret manager and the application must pass it per query. Names, tag numbers and money amounts are not encrypted. |
| 4 | Audit log on critical tables | **PASS for 4 tables, deliberately limited** | Triggers on `animals`, `health_events`, `sales`, `buyers` record who, when, old and new values (`evidence/security_catalog_checks.txt`; test 7). Written by a `SECURITY DEFINER` function so the app cannot edit the trail. Encrypted phone data is stripped from the log. `weight_records`, `feed_logs`, `pastures`, `breeding_events` and `app_users` are **not** audited (volume or lower risk, a judgement call). |
| 5 | Parameterized queries only | **PARTIAL** | Demonstrated at the database level with bound parameters: injection strings match nothing and the table survives (`tests/parameterized_demo.out`). **No application code was written in this lab**, so I cannot prove the application never concatenates SQL. That needs a code review or a linter rule in the app repository. |
| 6 | Backups taken AND test restore performed | **PASS (logical backup)** | `scripts/backup.sh`: `pg_dump -Fc`, archive check, restore into a scratch database, row counts compared for 6 tables, scratch DB dropped (`evidence/backup_restore_run.txt`). |

## Backup and recovery notes

* Command (as required): `pg_dump -Fc -f backups/capstone_$(date +%F).dump capstone`. The script wraps it with a verification restore and 14-day local retention.
* **Not covered:** `pg_dump` does not include roles. Recreate roles from `V4`, or back them up with `pg_dumpall --roles-only`. Point-in-time recovery (WAL archiving) is not set up, so the recovery point is the last nightly dump (up to about 24 hours of loss). The dump file is not encrypted and not copied off the machine. Do both before real use.
* Restoring needs a superuser or the owner role, which bypasses RLS. That is expected for a restore, but keep dump files as confidential as the database.

## Known gaps and limits (read before trusting this design)

1. **Sandbox shortcuts:** the build database used local trust authentication and a superuser for migrations. Production needs password or certificate authentication, TLS, and a separate migration/owner role that is not a superuser.
2. **Placeholder secrets:** role passwords (`change-me-app`, `change-me-ro`), the encryption demo key, and the demo user passwords are placeholders in the migrations. Rotate them and move them out of source control.
3. **RLS depends on the application setting `app.ranch_id`, `app.role`, `app.user_id` honestly** (`SET LOCAL` inside each transaction, from the authenticated session). A bug that sets the wrong tenant defeats isolation. If the app uses a connection pool, always use `SET LOCAL` in a transaction so settings cannot leak between requests.
4. **Superusers and table owners bypass RLS** by design. Protect those credentials.
5. **Flyway:** the real Flyway CLI could not be downloaded in the build sandbox (blocked by network policy). The migrations use Flyway's naming and the included `run_migrations.sh` imitates `clean migrate`. **I have not run actual Flyway against these files.** Run the real command yourself before submitting (see README).
6. **MongoDB** was designed but not executed (no server available).
