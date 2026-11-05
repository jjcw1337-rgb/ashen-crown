#!/bin/sh
# Update the staging droplet's multiplayer matches: the staging CI's dedicated-server export (artifact
# AshenCrown-server: the stripped "Linux Server" build, one file) and this checkout's lobby service and its unit.
# Usage: sh deploy/lobbies/update.sh [ci-run-id] [ssh-host]     (default: the latest green "Staging build")
# Restarting the lobby service ends any match in progress, so it refuses while one is starting or playing.
# Waiting lobbies survive (they are rows in its database). The game release and the co-op server are untouched.
set -eu
HOST=${2:-ashen-crown-staging}
RUN=${1:-$(gh run list --branch staging --workflow "Staging build" --status success --limit 1 --json databaseId -q '.[0].databaseId')}
ROOT=$(git rev-parse --show-toplevel)
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
gh run download "$RUN" -n AshenCrown-server -D "$T"
REV=$(cat "$T/DEPLOYED_REV")
[ -s "$T/AshenCrown.x86_64" ] || { echo "run $RUN has no server export"; exit 1; }
echo "server build $REV (CI run $RUN) -> $HOST"
BUSY=$(ssh "$HOST" "sudo python3 -c \"import sqlite3,json,os; p='/var/lib/ashen-lobbies/lobbies.sqlite'; print(sum(json.loads(d)['state'] in ('starting','playing') for (d,) in sqlite3.connect(p).execute('select data from state')) if os.path.exists(p) else 0)\"")
[ "$BUSY" = 0 ] || { echo "$BUSY match(es) in progress: try again when they finish"; exit 1; }
S=/opt/ashen-crown/staging
ssh "$HOST" "sudo install -d -o ashen -g ashen $S/server/$REV $S/lobbies"
COPYFILE_DISABLE=1 tar -C "$T" -cf - AshenCrown.x86_64 DEPLOYED_REV | ssh "$HOST" "sudo tar -xf - -C $S/server/$REV"
COPYFILE_DISABLE=1 tar -C "$ROOT/deploy/lobbies" -cf - service.py ashen-crown-lobbies.service | ssh "$HOST" "set -e
  sudo chmod +x $S/server/$REV/AshenCrown.x86_64; sudo chown -R ashen:ashen $S/server/$REV
  t=\$(mktemp -d); tar -xf - -C \$t
  sudo install -o ashen -g ashen -m 644 \$t/service.py $S/lobbies/service.py
  sudo install -m 644 \$t/ashen-crown-lobbies.service /etc/systemd/system/ashen-crown-lobbies.service
  rm -rf \$t
  sudo ln -sfn $S/server/$REV $S/server/current.next && sudo mv -Tf $S/server/current.next $S/server/current
  sudo systemctl daemon-reload
  sudo systemctl restart ashen-crown-lobbies
  sleep 2; systemctl is-active ashen-crown-lobbies
  # keep the three newest server builds
  ls -1dt $S/server/*/ | grep -v current | tail -n +4 | xargs -r sudo rm -rf"
echo "matches now run server build $REV"
