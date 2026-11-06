#!/bin/sh
# One-time (idempotent) setup of Grafana on the STAGING server (docs/systems/telemetry.md):
#   sh deploy/staging/grafana_setup.sh [ssh-host]
# Makes the passwords on the server (GRAFANA_ADMIN_PASSWORD, GRAFANA_PG_PASSWORD appended to nakama.env, mode 600;
# never printed) and the read-only role grafana_ro that reads the telemetry tables. Then `backend.sh` starts Grafana
# with the rest of the backend. Grafana's admin password is copied to this Mac's
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
  $P -d nakama -tc "SELECT 1 FROM pg_roles WHERE rolname = '"'"'grafana_ro'"'"'" | grep -q 1 || $P -d nakama -c "CREATE ROLE grafana_ro LOGIN"
  echo "ALTER ROLE grafana_ro PASSWORD '"'"'$PW'"'"';" | $P -d nakama
  # (the telemetry tables in Nakama'"'"'s database: the module grants SELECT on them, docs/systems/telemetry.md)
  $P -d nakama -c "GRANT CONNECT ON DATABASE nakama TO grafana_ro; GRANT USAGE ON SCHEMA public TO grafana_ro"' 
mkdir -p ~/.config/ashen-grafana && chmod 700 ~/.config/ashen-grafana
ssh "$HOST" 'sudo grep "^GRAFANA_ADMIN_PASSWORD=" /opt/ashen-crown/staging/backend/nakama.env | cut -d= -f2' > ~/.config/ashen-grafana/admin_password
chmod 600 ~/.config/ashen-grafana/admin_password
echo "Grafana ready;'s admin password is in ~/.config/ashen-grafana/admin_password"
