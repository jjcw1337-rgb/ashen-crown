#!/bin/sh
# Deploys the current commit of the staging checkout to the STAGING server, from a developer machine:
#   sh deploy/staging/deploy.sh [ssh-host]        (default ssh host alias: ashen-crown-staging)
# 1. the Nakama module, compose file, Caddyfile and Grafana's provisioning -> /opt/ashen-crown/staging/backend,
#    `docker compose up -d` (Nakama, PostgreSQL, Caddy for HTTPS, Grafana for the KPIs; kpi_setup.sh once first)
# 2. the game (git archive of HEAD, no .godot cache) -> /opt/ashen-crown/staging/game, imported with Godot 4.3
# 3. restarts the Battlegrounds (UDP 24567) and online co-op (UDP 24570) services and waits for both "server up".
# Use --backend to do only step 1.
set -eu
ONLY_BACKEND=0
[ "${1:-}" = "--backend" ] && { ONLY_BACKEND=1; shift; }
HOST=${1:-ashen-crown-staging}
ROOT=$(git rev-parse --show-toplevel)
REV=$(git -C "$ROOT" rev-parse --short HEAD)
echo "deploying $REV to $HOST"
# (COPYFILE_DISABLE: macOS's tar would add ._ metadata files, and Nakama refuses to start on a ._ashen.lua)
COPYFILE_DISABLE=1 tar -C "$ROOT/deploy" -czf - nakama/modules staging/docker-compose.yml staging/Caddyfile staging/grafana staging/loki staging/ashen-crown-bg.service staging/ashen-crown-coop.service | ssh "$HOST" 'set -e
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
  sudo install -m 644 $t/staging/ashen-crown-bg.service /etc/systemd/system/ashen-crown-bg.service
  sudo install -m 644 $t/staging/ashen-crown-coop.service /etc/systemd/system/ashen-crown-coop.service
  rm -rf $t
  cd /opt/ashen-crown/staging/backend && sudo docker compose --env-file nakama.env up -d --quiet-pull --remove-orphans
  # (a new Caddyfile is a new file: the container still has the old one bind-mounted until it restarts)
  [ $cady = 0 ] || sudo docker compose --env-file nakama.env restart caddy
  [ $mods = 0 ] || sudo docker compose --env-file nakama.env restart nakama     # (the same for the Lua module directory)
  # (Loki and Alloy read their config at start)
  sudo docker compose --env-file nakama.env restart loki alloy > /dev/null 2>&1 || true'
[ $ONLY_BACKEND = 1 ] && exit 0
git -C "$ROOT" archive --format=tar HEAD | ssh "$HOST" "set -e
  sudo rm -rf /opt/ashen-crown/staging/game.new && sudo mkdir -p /opt/ashen-crown/staging/game.new
  sudo tar -xf - -C /opt/ashen-crown/staging/game.new
  echo $REV | sudo tee /opt/ashen-crown/staging/game.new/DEPLOYED_REV > /dev/null
  sudo chown -R ashen:ashen /opt/ashen-crown/staging/game.new
  sudo -u ashen /opt/ashen-crown/godot/godot --headless --path /opt/ashen-crown/staging/game.new --import > /tmp/ashen-import.log 2>&1 || true
  sudo systemctl stop ashen-crown-bg ashen-crown-coop 2>/dev/null || true
  sudo rm -rf /opt/ashen-crown/staging/game && sudo mv /opt/ashen-crown/staging/game.new /opt/ashen-crown/staging/game
  sudo systemctl daemon-reload && sudo systemctl enable --now ashen-crown-bg ashen-crown-coop > /dev/null
  sudo systemctl restart ashen-crown-bg ashen-crown-coop
  for i in \$(seq 1 90); do sleep 2; n=\$(sudo journalctl -u ashen-crown-bg -u ashen-crown-coop --since '-3 min' --no-pager | grep -c 'server up' || true); [ \$n -ge 2 ] && break; done
  sudo journalctl -u ashen-crown-bg -u ashen-crown-coop --since '-3 min' --no-pager | grep '\[BG\]\|\[COOP\]' | tail -4"
