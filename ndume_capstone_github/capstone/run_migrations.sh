#!/usr/bin/env bash
# Flyway-compatible stand-in: `./run_migrations.sh clean migrate`
# Used because the Flyway CLI could not be downloaded in the build sandbox.
# Same file naming (V<n>__desc.sql), same history table (flyway_schema_history), same
# checksum + in-order semantics. On a normal machine run the real thing instead:
#     flyway -url=jdbc:postgresql://localhost:5432/capstone -user=... -locations=filesystem:sql clean migrate
set -euo pipefail
: "${PGHOST:=localhost}" "${PGPORT:=5432}" "${PGUSER:=postgres}" "${PGDATABASE:=capstone}"
export PGHOST PGPORT PGUSER PGDATABASE
DIR="$(cd "$(dirname "$0")" && pwd)/sql"
psql_q() { psql -v ON_ERROR_STOP=1 -X -q "$@"; }

do_clean() {
  echo "[clean] dropping public schema objects"
  psql_q -c "DROP SCHEMA public CASCADE; CREATE SCHEMA public;"
  psql_q -c "DO \$\$ BEGIN IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname='capstone_app') THEN
               EXECUTE 'DROP OWNED BY capstone_app'; EXECUTE 'DROP ROLE capstone_app'; END IF;
             IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname='capstone_readonly') THEN
               EXECUTE 'DROP OWNED BY capstone_readonly'; EXECUTE 'DROP ROLE capstone_readonly'; END IF; END \$\$;"
}

do_migrate() {
  psql_q -c "CREATE TABLE IF NOT EXISTS flyway_schema_history (
      installed_rank serial PRIMARY KEY, version text, description text, script text,
      checksum text, installed_by text DEFAULT current_user, installed_on timestamptz DEFAULT now(),
      execution_time_ms integer, success boolean)"
  for f in $(ls "$DIR"/V*__*.sql | sort -V); do
    base=$(basename "$f"); ver=${base%%__*}; ver=${ver#V}; desc=${base#*__}; desc=${desc%.sql}
    sum=$(sha256sum "$f" | cut -c1-16)
    have=$(psql_q -At -c "SELECT checksum FROM flyway_schema_history WHERE version='$ver' AND success")
    if [ -n "$have" ]; then
      [ "$have" = "$sum" ] || { echo "CHECKSUM MISMATCH on $base (applied migrations must not change)"; exit 1; }
      echo "[skip]    $base"; continue
    fi
    start=$(date +%s%3N)
    psql_q -1 -f "$f" >/dev/null
    ms=$(( $(date +%s%3N) - start ))
    psql_q -c "INSERT INTO flyway_schema_history (version,description,script,checksum,execution_time_ms,success)
               VALUES ('$ver','${desc//_/ }','$base','$sum',$ms,true)"
    echo "[applied] $base (${ms} ms)"
  done
  echo "Successfully applied migrations."
}

for cmd in "$@"; do case "$cmd" in clean) do_clean;; migrate) do_migrate;; *) echo "unknown: $cmd"; exit 2;; esac; done
