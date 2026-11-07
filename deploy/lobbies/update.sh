#!/bin/sh
# Update the staging droplet's multiplayer matches: the staging CI's dedicated-server export (artifact
# AshenCrown-server: the stripped "Linux Server" build, one file) and this checkout's lobby service and its unit.
# Usage: sh deploy/lobbies/update.sh [--force] [ci-run-id] [ssh-host]   (default: the latest green "Staging build")
# Restarting the lobby service ends any match in progress, so when the service changed it refuses while one is
# starting or playing, unless --force (staging: Blaine 2026-11-06, "just kill them"). A new server build alone never
# restarts it.
# Waiting lobbies survive (they are rows in its database). The game release and the co-op server are untouched.
set -eu
FORCE=0
[ "${1:-}" = "--force" ] && { FORCE=1; shift; }
HOST=${2:-ashen-crown-staging}
RUN=${1:-$(gh run list --branch staging --workflow "Staging build" --status success --limit 1 --json databaseId -q '.[0].databaseId')}
ROOT=$(git rev-parse --show-toplevel)
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
gh run download "$RUN" -n AshenCrown-server -D "$T"
REV=$(cat "$T/DEPLOYED_REV")
[ -s "$T/AshenCrown.x86_64" ] || { echo "run $RUN has no server export"; exit 1; }
echo "server build $REV (CI run $RUN) -> $HOST"
S=/opt/ashen-crown/staging
# Only a changed lobby service (or its unit) needs the restart that ends matches in progress. A new server build alone
# is a symlink swap: a running match keeps the binary it started with, the next one starts on the new build.
LOCAL_SUM=$(cat "$ROOT/deploy/lobbies/service.py" "$ROOT/deploy/lobbies/ashen-crown-lobbies.service" | shasum -a 256 | cut -c1-64)
REMOTE_SUM=$(ssh "$HOST" "cat $S/lobbies/service.py /etc/systemd/system/ashen-crown-lobbies.service 2>/dev/null | sha256sum | cut -c1-64")
RESTART=1
[ "$LOCAL_SUM" = "$REMOTE_SUM" ] && RESTART=0
if [ "$RESTART" = 1 ]; then
  BUSY=$(ssh "$HOST" "sudo python3 -c \"import sqlite3,json,os; p='/var/lib/ashen-lobbies/lobbies.sqlite'; print(sum(json.loads(d)['state'] in ('starting','playing') for (d,) in sqlite3.connect(p).execute('select data from state')) if os.path.exists(p) else 0)\"")
  [ "$BUSY" = 0 ] || [ "$FORCE" = 1 ] || { echo "the lobby service changed and $BUSY match(es) are in progress: try again when they finish (or --force)"; exit 1; }
  [ "$BUSY" = 0 ] || echo "--force: ending $BUSY match(es) in progress"
else
  echo "the lobby service is unchanged: only the server build is swapped (matches in progress keep theirs)"
fi
ssh "$HOST" "sudo install -d -o ashen -g ashen $S/server/$REV $S/lobbies"
# (the whole export: the binary and its pack, DEPLOYED_REV, and any GDExtension libraries the export put beside it)
COPYFILE_DISABLE=1 tar -C "$T" -cf - . | ssh "$HOST" "sudo tar -xf - -C $S/server/$REV"
COPYFILE_DISABLE=1 tar -C "$ROOT/deploy/lobbies" -cf - service.py ashen-crown-lobbies.service | ssh "$HOST" "set -e
  sudo chmod +x $S/server/$REV/AshenCrown.x86_64; sudo chown -R ashen:ashen $S/server/$REV
  t=\$(mktemp -d); tar -xf - -C \$t
  sudo install -o ashen -g ashen -m 644 \$t/service.py $S/lobbies/service.py
  sudo install -m 644 \$t/ashen-crown-lobbies.service /etc/systemd/system/ashen-crown-lobbies.service
  rm -rf \$t
  sudo ln -sfn $S/server/$REV $S/server/current.next && sudo mv -Tf $S/server/current.next $S/server/current
  if [ $RESTART = 1 ]; then sudo systemctl daemon-reload; sudo systemctl restart ashen-crown-lobbies; sleep 2; fi
  systemctl is-active ashen-crown-lobbies
  # keep the three newest server builds
  ls -1dt $S/server/*/ | grep -v current | tail -n +4 | xargs -r sudo rm -rf"
echo "matches now run server build $REV"
