#!/bin/sh
# Deploys the current commit of the staging checkout to the STAGING server, from a developer machine:
#   sh deploy/staging/deploy.sh [ssh-host]        (default ssh host alias: ashen-crown-staging)
# 1. the Nakama module and compose file -> /opt/ashen-crown/staging/backend, `docker compose up -d`
# 2. the game (git archive of HEAD, no .godot cache) -> /opt/ashen-crown/staging/game, imported with Godot 4.3
# 3. restarts the Battlegrounds service and waits for "[BG] server up".
set -eu
HOST=${1:-ashen-crown-staging}
ROOT=$(git rev-parse --show-toplevel)
REV=$(git -C "$ROOT" rev-parse --short HEAD)
echo "deploying $REV to $HOST"
tar -C "$ROOT/deploy" -czf - nakama/modules staging/docker-compose.yml staging/ashen-crown-bg.service | ssh "$HOST" 'set -e
  t=$(mktemp -d); tar -xzf - -C $t
  sudo install -m 644 $t/staging/docker-compose.yml /opt/ashen-crown/staging/backend/docker-compose.yml
  sudo rm -rf /opt/ashen-crown/staging/backend/modules && sudo cp -r $t/nakama/modules /opt/ashen-crown/staging/backend/modules
  sudo install -m 644 $t/staging/ashen-crown-bg.service /etc/systemd/system/ashen-crown-bg.service
  rm -rf $t
  cd /opt/ashen-crown/staging/backend && sudo docker compose --env-file nakama.env up -d --quiet-pull'
git -C "$ROOT" archive --format=tar HEAD | ssh "$HOST" "set -e
  sudo rm -rf /opt/ashen-crown/staging/game.new && sudo mkdir -p /opt/ashen-crown/staging/game.new
  sudo tar -xf - -C /opt/ashen-crown/staging/game.new
  echo $REV | sudo tee /opt/ashen-crown/staging/game.new/DEPLOYED_REV > /dev/null
  sudo chown -R ashen:ashen /opt/ashen-crown/staging/game.new
  sudo -u ashen /opt/ashen-crown/godot/godot --headless --path /opt/ashen-crown/staging/game.new --import > /tmp/ashen-import.log 2>&1 || true
  sudo systemctl stop ashen-crown-bg 2>/dev/null || true
  sudo rm -rf /opt/ashen-crown/staging/game && sudo mv /opt/ashen-crown/staging/game.new /opt/ashen-crown/staging/game
  sudo systemctl daemon-reload && sudo systemctl enable --now ashen-crown-bg > /dev/null
  sudo systemctl restart ashen-crown-bg
  for i in \$(seq 1 90); do sleep 2; sudo journalctl -u ashen-crown-bg --since '-3 min' --no-pager | grep -q 'server up' && break; done
  sudo journalctl -u ashen-crown-bg --since '-3 min' --no-pager | grep '\[BG\]' | tail -3"
