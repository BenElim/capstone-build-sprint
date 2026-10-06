#!/usr/bin/env bash
# Redis layer demo: cache-aside herd dashboard, login sessions, rate limiting, "recent weigh-ins" feed.
# Usage: PGHOST=/tmp PGPORT=5433 REDIS_PORT=6380 ./nosql/redis_demo.sh
set -euo pipefail
R="redis-cli -p ${REDIS_PORT:-6380}"
PSQL="psql -X -At -U capstone_app -d capstone"
RANCH=${1:-1}

dash_sql="SELECT json_agg(t) FROM (
  SELECT b.name AS breed, count(*) AS head, round(avg(w.weight_kg),1) AS avg_latest_kg
  FROM animals a JOIN breeds b USING (breed_id)
  JOIN LATERAL (SELECT weight_kg FROM weight_records w WHERE w.animal_id=a.animal_id ORDER BY weighed_on DESC LIMIT 1) w ON true
  WHERE a.status='active' GROUP BY b.name ORDER BY head DESC) t"

fetch_dashboard() {   # cache-aside: try Redis, fall back to PostgreSQL, then populate with a TTL
  local key="ranch:$RANCH:dashboard:herd" v
  v=$($R GET "$key")
  if [ -n "$v" ]; then echo "HIT  $key"; return; fi
  echo "MISS $key -> querying PostgreSQL"
  v=$($PSQL -c "BEGIN; SET LOCAL app.ranch_id='$RANCH'; SET LOCAL app.role='owner'; $dash_sql;" | grep -v -E '^(BEGIN|SET|COMMIT)')
  $R SET "$key" "$v" EX 300 >/dev/null     # 5 minute TTL: dashboards may be slightly stale
}

echo "== 1. cache-aside dashboard"
$R DEL "ranch:$RANCH:dashboard:herd" >/dev/null
t0=$(date +%s%N); fetch_dashboard; t1=$(date +%s%N)
echo "   cold (PostgreSQL): $(( (t1-t0)/1000000 )) ms"
t0=$(date +%s%N); fetch_dashboard; t1=$(date +%s%N)
echo "   warm (Redis):      $(( (t1-t0)/1000000 )) ms   (includes process start of redis-cli)"
echo "   TTL left: $($R TTL ranch:$RANCH:dashboard:herd)s"
echo "   value: $($R GET ranch:$RANCH:dashboard:herd | cut -c1-120)..."

echo "== 2. invalidate on write (a new weigh-in makes the cached dashboard stale)"
$R DEL "ranch:$RANCH:dashboard:herd" >/dev/null; echo "   cache key deleted by the write path"

echo "== 3. login session (token -> user, expires with the session)"
$R HSET "session:tok_abc123" user_id 1 ranch_id "$RANCH" role owner >/dev/null
$R EXPIRE "session:tok_abc123" 1800 >/dev/null
echo "   $($R HGETALL session:tok_abc123 | paste -sd' ')  ttl=$($R TTL session:tok_abc123)s"

echo "== 4. rate limit: 5 login attempts per minute per IP"
for i in 1 2 3 4 5 6 7; do
  n=$($R INCR "ratelimit:login:203.0.113.9"); [ "$n" = 1 ] && $R EXPIRE "ratelimit:login:203.0.113.9" 60 >/dev/null
  if [ "$n" -gt 5 ]; then echo "   attempt $i: BLOCKED (count=$n)"; else echo "   attempt $i: allowed (count=$n)"; fi
done
$R DEL ratelimit:login:203.0.113.9 >/dev/null

echo "== 5. 'latest 5 weigh-ins' feed as a capped list"
$R DEL "ranch:$RANCH:feed:weighins" >/dev/null
for a in 101 102 103 104 105 106 107; do
  $R LPUSH "ranch:$RANCH:feed:weighins" "{\"animal\":$a,\"kg\":$((300+a))}" >/dev/null
  $R LTRIM "ranch:$RANCH:feed:weighins" 0 4 >/dev/null
done
echo "   length=$($R LLEN ranch:$RANCH:feed:weighins) newest=$($R LINDEX ranch:$RANCH:feed:weighins 0)"
