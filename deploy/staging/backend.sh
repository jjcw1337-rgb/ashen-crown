#!/bin/sh
# Deploys the STAGING backend from this checkout, from a developer machine:
#   sh deploy/staging/backend.sh [ssh-host]        (default ssh host alias: ashen-crown-staging)
# The Nakama module, the compose file (Nakama, PostgreSQL, Caddy for HTTPS, Grafana, Loki and Alloy), the Caddyfile and
# Grafana's and Loki's config -> /opt/ashen-crown/staging/backend, then `docker compose up -d`, restarting only what
# changed. The game's match servers are deployed separately: deploy/lobbies/update.sh (the CI's server export).
set -eu
HOST=${1:-ashen-crown-staging}
ROOT=$(git rev-parse --show-toplevel)
REV=$(git -C "$ROOT" rev-parse --short HEAD)
echo "backend $REV -> $HOST"
# (COPYFILE_DISABLE: macOS's tar would add ._ metadata files, and Nakama refuses to start on a ._ashen.lua)
COPYFILE_DISABLE=1 tar -C "$ROOT/deploy" -czf - nakama/modules staging/docker-compose.yml staging/Caddyfile staging/grafana staging/loki | ssh "$HOST" 'set -e
  t=$(mktemp -d); tar -xzf - -C $t 2>/dev/null; find $t -name "._*" -delete
  sudo install -m 644 $t/staging/docker-compose.yml /opt/ashen-crown/staging/backend/docker-compose.yml
  cady=0; sudo cmp -s $t/staging/Caddyfile /opt/ashen-crown/staging/backend/Caddyfile || cady=1
  sudo install -m 644 $t/staging/Caddyfile /opt/ashen-crown/staging/backend/Caddyfile
  ip=$(curl -fs http://169.254.169.254/metadata/v1/interfaces/public/0/ipv4/address)
  sudo sed -i "/^STAGING_HOST=/d" /opt/ashen-crown/staging/backend/nakama.env
  echo "STAGING_HOST=$ip" | sudo tee -a /opt/ashen-crown/staging/backend/nakama.env > /dev/null
  mods=0; sudo diff -rq $t/nakama/modules /opt/ashen-crown/staging/backend/modules > /dev/null 2>&1 || mods=1
  sudo rm -rf /opt/ashen-crown/staging/backend/modules && sudo cp -r $t/nakama/modules /opt/ashen-crown/staging/backend/modules
  sudo rm -rf /opt/ashen-crown/staging/backend/grafana && sudo cp -r $t/staging/grafana /opt/ashen-crown/staging/backend/grafana
  sudo rm -rf /opt/ashen-crown/staging/backend/loki && sudo cp -r $t/staging/loki /opt/ashen-crown/staging/backend/loki
  sudo chmod -R a+rX /opt/ashen-crown/staging/backend/grafana /opt/ashen-crown/staging/backend/loki
  rm -rf $t
  cd /opt/ashen-crown/staging/backend && sudo docker compose --env-file nakama.env up -d --quiet-pull --remove-orphans
  # (a new Caddyfile is a new file: the container still has the old one bind-mounted until it restarts)
  [ $cady = 0 ] || sudo docker compose --env-file nakama.env restart caddy
  [ $mods = 0 ] || sudo docker compose --env-file nakama.env restart nakama     # (the same for the Lua module directory)
  # (Loki and Alloy read their config at start)
  sudo docker compose --env-file nakama.env restart loki alloy > /dev/null 2>&1 || true'
