#!/bin/sh
# Reads the player telemetry and error reports (docs/systems/telemetry.md) from a script or a session: SQL on the
# tables tm_sample, tm_error and the view tm_issue in the staging Nakama database, through ssh (no port is open).
#   sh tools/telemetry_query.sh issues      (the issues of the last 24 h, worst first)
#   sh tools/telemetry_query.sh spots       (the slowest places players were in the last 24 h)
#   sh tools/telemetry_query.sh "SELECT ... FROM tm_error ..."
Q=${1:-issues}
case $Q in
  issues) Q="SELECT fingerprint, kind, source, events, players, sessions, to_char(last_seen, 'MM-DD HH24:MI') AS last, builds, zones, left(message, 90) AS message, left(at, 60) AS at FROM tm_issue WHERE last_seen > now() - interval '24 hours' ORDER BY (kind = 'crash') DESC, players DESC, events DESC LIMIT 30" ;;
  spots) Q="SELECT zone, run, round(x / 20) * 20 AS x, round(z / 20) * 20 AS z, preset, count(*) AS samples, count(DISTINCT user_id) AS players, round(avg(fps_avg)::numeric, 1) AS fps, round(avg(fps_low1)::numeric, 1) AS low1, sum(hitches) AS hitches, round(avg(enemies)::numeric, 1) AS enemies, bool_or(boss) AS boss, min(gpu) AS gpu FROM tm_sample WHERE ts > now() - interval '24 hours' GROUP BY 1, 2, 3, 4, 5 ORDER BY fps LIMIT 20" ;;
esac
echo "$Q" | ssh ashen-crown-staging 'sudo docker exec -i ashen-staging-postgres-1 psql -q -U nakama -d nakama -P pager=off'
