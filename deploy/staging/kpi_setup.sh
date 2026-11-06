#!/bin/sh
# One-time (idempotent) setup of the KPI store and Grafana on the STAGING server (docs/systems/performance_kpis.md):
#   sh deploy/staging/kpi_setup.sh [ssh-host]
# Makes the passwords on the server (GRAFANA_ADMIN_PASSWORD, GRAFANA_PG_PASSWORD appended to nakama.env, mode 600;
# never printed), the `kpi` database, the read-only role grafana_ro and the table. Then `deploy.sh` (or
# `deploy.sh --backend`) starts Grafana with the rest of the backend. Grafana's admin password is copied to this Mac's
# ~/.config/ashen-grafana/admin_password (mode 600) so a person can log in.
set -eu
HOST=${1:-ashen-crown-staging}
ROOT=$(git rev-parse --show-toplevel)
ssh "$HOST" 'set -e
  E=/opt/ashen-crown/staging/backend/nakama.env
  for k in GRAFANA_ADMIN_PASSWORD GRAFANA_PG_PASSWORD; do
    sudo grep -q "^$k=" $E || echo "$k=$(openssl rand -hex 18)" | sudo tee -a $E > /dev/null
  done
  sudo chmod 600 $E'
ssh "$HOST" 'set -e
  E=/opt/ashen-crown/staging/backend/nakama.env
  PW=$(sudo grep "^GRAFANA_PG_PASSWORD=" $E | cut -d= -f2)
  P="sudo docker exec -i ashen-staging-postgres-1 psql -v ON_ERROR_STOP=1 -q -U nakama"
  $P -d nakama -tc "SELECT 1 FROM pg_database WHERE datname = '"'"'kpi'"'"'" | grep -q 1 || $P -d nakama -c "CREATE DATABASE kpi"
  $P -d nakama -tc "SELECT 1 FROM pg_roles WHERE rolname = '"'"'grafana_ro'"'"'" | grep -q 1 || $P -d nakama -c "CREATE ROLE grafana_ro LOGIN"
  echo "ALTER ROLE grafana_ro PASSWORD '"'"'$PW'"'"';" | $P -d nakama
  $P -d kpi -c "GRANT CONNECT ON DATABASE kpi TO grafana_ro; GRANT USAGE ON SCHEMA public TO grafana_ro"
  # (the telemetry tables in Nakama'"'"'s database: the module grants SELECT on them, docs/systems/telemetry.md)
  $P -d nakama -c "GRANT CONNECT ON DATABASE nakama TO grafana_ro; GRANT USAGE ON SCHEMA public TO grafana_ro"' 
ssh "$HOST" 'sudo docker exec -i ashen-staging-postgres-1 psql -v ON_ERROR_STOP=1 -q -U nakama -d kpi' < "$ROOT/deploy/staging/kpi_schema.sql"
mkdir -p ~/.config/ashen-grafana && chmod 700 ~/.config/ashen-grafana
ssh "$HOST" 'sudo grep "^GRAFANA_ADMIN_PASSWORD=" /opt/ashen-crown/staging/backend/nakama.env | cut -d= -f2' > ~/.config/ashen-grafana/admin_password
chmod 600 ~/.config/ashen-grafana/admin_password
echo "KPI store ready; Grafana's admin password is in ~/.config/ashen-grafana/admin_password"
