#!/usr/bin/env bash
# usage: queries/explain.sh <label: before|after> [Q1 Q2 ...]
set -euo pipefail
label=$1; shift
qs=${*:-Q1 Q2 Q3 Q4 Q5}
for q in $qs; do
  out=evidence/${label}_${q}.txt
  {
    echo "-- $(head -1 queries/q/$q.sql)"
    echo "-- run as capstone_app, tenant ranch 1, role owner (RLS active), $(date -u +%FT%TZ)"
    psql -X -q -h "${PGHOST:-/tmp}" -p "${PGPORT:-5433}" -U capstone_app -d capstone \
      -c "BEGIN" -c "SET LOCAL app.ranch_id='1'" -c "SET LOCAL app.role='owner'" -c "SET statement_timeout='300s'" \
      -c "EXPLAIN (ANALYZE, BUFFERS) $(sed 1d queries/q/$q.sql)" -c "ROLLBACK"
  } > "$out" 2>&1
  echo "$q: $(grep -E 'Execution Time' "$out")"
done
