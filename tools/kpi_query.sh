#!/bin/sh
# Reads the performance KPI store (docs/systems/performance_kpis.md) from a script or a session: SQL on the `kpi` table, through
# ssh (no database port is open), as CSV-ish aligned text.
#   sh tools/kpi_query.sh "SELECT scenario, value FROM kpi WHERE metric = 'fps_avg' ORDER BY ts DESC LIMIT 10"
#   sh tools/kpi_query.sh latest        (the latest value of every metric of every scenario)
Q=${1:-latest}
[ "$Q" = latest ] && Q="SELECT DISTINCT ON (scenario, preset, metric) scenario, preset, metric, value, to_char(ts, 'YYYY-MM-DD HH24:MI') AS measured, phase, commit FROM kpi WHERE source = 'runner' ORDER BY scenario, preset, metric, ts DESC"
echo "$Q" | ssh ashen-crown-staging 'sudo docker exec -i ashen-staging-postgres-1 psql -q -U nakama -d kpi -P pager=off'
