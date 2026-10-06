#!/usr/bin/env bash
# Daily logical backup + automatic verification restore into a scratch database.
# Cron example (02:30 daily):  30 2 * * *  /opt/ndume/scripts/backup.sh >> /var/log/ndume_backup.log 2>&1
set -euo pipefail
cd "$(dirname "$0")/.."
: "${PGHOST:=localhost}" "${PGPORT:=5432}" "${PGUSER:=postgres}"
export PGHOST PGPORT PGUSER
mkdir -p backups
FILE="backups/capstone_$(date +%F).dump"

pg_dump -Fc -f "$FILE" capstone
echo "backup written: $FILE ($(du -h "$FILE" | cut -f1))"
pg_restore -l "$FILE" > /dev/null && echo "archive readable: OK"

# test restore into a throwaway database, compare row counts with the source
SCRATCH=capstone_restore_test
dropdb --if-exists "$SCRATCH"; createdb "$SCRATCH"
pg_restore --no-owner -d "$SCRATCH" "$FILE" 2>/tmp/restore_err.txt || true
for t in ranches animals weight_records health_events sales audit_log; do
  a=$(psql -At -d capstone -c "SELECT count(*) FROM $t"); b=$(psql -At -d "$SCRATCH" -c "SELECT count(*) FROM $t")
  [ "$a" = "$b" ] && echo "restore check $t: $a = $b OK" || { echo "restore check $t: MISMATCH $a vs $b"; exit 1; }
done
dropdb "$SCRATCH"
find backups -name 'capstone_*.dump' -mtime +14 -delete      # keep 14 days locally; copy offsite too
echo "backup + test restore: SUCCESS"
