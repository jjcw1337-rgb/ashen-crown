#!/bin/sh
# Deploys the current commit of the staging checkout to the STAGING server, from a developer machine:
#   sh deploy/staging/deploy.sh [ssh-host]        (default ssh host alias: ashen-crown-staging)
# 1. the Nakama module, compose file, Caddyfile and Grafana's provisioning -> /opt/ashen-crown/staging/backend,
#    `docker compose up -d` (Nakama, PostgreSQL, Caddy for HTTPS, Grafana for the KPIs; kpi_setup.sh once first)
# 2. the game (git archive of HEAD, no .godot cache) -> its own release folder /opt/ashen-crown/staging/releases/<rev>-<time>,
#    imported with Godot 4.3; then the `game` link is switched to it (atomically)
# 3. NO restart (Blaine 2026-11-02: a deploy kicked players out of a raid and a co-op game): each running server keeps
#    its release and moves to the new one by itself when nobody would be hurt (ServerUpdate: a raid empty or between
#    rounds, co-op empty), systemd bringing it back. Servers that aren't running are started.
#    --now restarts them at once (emergencies only; say so in Discord first).
# Use --backend to do only step 1.
set -eu
# How many Battlegrounds raids run (Battlegrounds.RAIDS, staggered on the clock): 1 = raid I only (ashen-crown-bg);
# 3 = also raids II and III (ashen-crown-bg-raid@1, @2 on UDP 24571/24572: open those ports in the cloud firewall and
# give the droplet the memory for them first; set Battlegrounds.LIVE_RAIDS to match so clients pick among them).
BG_RAIDS=${BG_RAIDS:-1}
ONLY_BACKEND=0
NOW=0
[ "${1:-}" = "--backend" ] && { ONLY_BACKEND=1; shift; }
[ "${1:-}" = "--now" ] && { NOW=1; shift; }
HOST=${1:-ashen-crown-staging}
ROOT=$(git rev-parse --show-toplevel)
REV=$(git -C "$ROOT" rev-parse --short HEAD)
echo "deploying $REV to $HOST"
# (COPYFILE_DISABLE: macOS's tar would add ._ metadata files, and Nakama refuses to start on a ._ashen.lua)
COPYFILE_DISABLE=1 tar -C "$ROOT/deploy" -czf - nakama/modules staging/docker-compose.yml staging/Caddyfile staging/grafana staging/loki staging/ashen-crown-bg.service staging/ashen-crown-bg-raid@.service staging/ashen-crown-coop.service | ssh "$HOST" 'set -e
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
  sudo install -m 644 "$t/staging/ashen-crown-bg-raid@.service" "/etc/systemd/system/ashen-crown-bg-raid@.service"
  rm -rf $t
  cd /opt/ashen-crown/staging/backend && sudo docker compose --env-file nakama.env up -d --quiet-pull --remove-orphans
  # (a new Caddyfile is a new file: the container still has the old one bind-mounted until it restarts)
  [ $cady = 0 ] || sudo docker compose --env-file nakama.env restart caddy
  [ $mods = 0 ] || sudo docker compose --env-file nakama.env restart nakama     # (the same for the Lua module directory)
  # (Loki and Alloy read their config at start)
  sudo docker compose --env-file nakama.env restart loki alloy > /dev/null 2>&1 || true'
[ $ONLY_BACKEND = 1 ] && exit 0
UNITS="ashen-crown-bg ashen-crown-coop"
[ "$BG_RAIDS" -ge 2 ] && UNITS="$UNITS ashen-crown-bg-raid@1"
[ "$BG_RAIDS" -ge 3 ] && UNITS="$UNITS ashen-crown-bg-raid@2"
REL="$REV-$(date +%s)"
git -C "$ROOT" archive --format=tar HEAD | ssh "$HOST" "set -e
  S=/opt/ashen-crown/staging
  sudo mkdir -p \$S/releases
  # (once: the old single game folder becomes a release, and \$S/game a link)
  if [ -d \$S/game ] && [ ! -L \$S/game ]; then
    old=\$(cat \$S/game/DEPLOYED_REV 2>/dev/null || echo old)-0
    sudo mv \$S/game \$S/releases/\$old && sudo ln -sfn \$S/releases/\$old \$S/game
  fi
  sudo mkdir -p \$S/releases/$REL.tmp
  sudo tar -xf - -C \$S/releases/$REL.tmp
  echo $REV | sudo tee \$S/releases/$REL.tmp/DEPLOYED_REV > /dev/null
  sudo chown -R ashen:ashen \$S/releases/$REL.tmp
  # the import never starves the live servers (2026-11-03: a full import on the 2-CPU droplet took it down, load 39):
  # it starts from the live release's cache, so only what changed is imported, and runs last in line for the CPU
  # with a memory cap (a capped import is killed, never the game servers; the release then imports what's left
  # when it starts)
  if [ -d \$S/game/.godot ]; then sudo cp -a \$S/game/.godot \$S/releases/$REL.tmp/; fi
  sudo systemd-run --scope -q -p MemoryMax=1200M -p CPUQuota=70% --uid=ashen --gid=ashen \\
    nice -n 19 ionice -c3 /opt/ashen-crown/godot/godot --headless --path \$S/releases/$REL.tmp --import > /tmp/ashen-import.log 2>&1 || true
  sudo mv \$S/releases/$REL.tmp \$S/releases/$REL
  sudo ln -sfn \$S/releases/$REL \$S/game.next && sudo mv -Tf \$S/game.next \$S/game
  sudo systemctl daemon-reload
  sudo systemctl enable $UNITS > /dev/null 2>&1
  for u in ashen-crown-bg-raid@1 ashen-crown-bg-raid@2; do
    case ' $UNITS ' in *\" \$u \"*) ;; *) sudo systemctl disable --now \$u > /dev/null 2>&1 || true ;; esac
  done
  started=''
  for u in $UNITS; do
    if [ $NOW = 1 ]; then sudo systemctl restart \$u; started=\"\$started \$u\"
    elif ! systemctl is-active -q \$u; then sudo systemctl start \$u; started=\"\$started \$u\"
    else echo \"\$u: running, moves to $REV by itself when nobody is playing on it\"; fi
  done
  if [ -n \"\$started\" ]; then
    want=\$(echo \$started | wc -w)
    for i in \$(seq 1 120); do sleep 2; n=\$(sudo journalctl -u 'ashen-crown-*' --since '-4 min' --no-pager | grep -c 'server up' || true); [ \$n -ge \$want ] && break; done
    sudo journalctl -u 'ashen-crown-*' --since '-4 min' --no-pager | grep '\[BG\]\|\[COOP\]' | grep 'server up\|on the clock\|FAILED' | tail -6
  fi
  # old releases: keep the newest three and any a server still runs
  cd \$S/releases && for r in \$(ls -1t | grep -v '\.tmp$' | tail -n +4); do
    pgrep -f \"releases/\$r \" > /dev/null || pgrep -f \"releases/\$r\$\" > /dev/null || sudo rm -rf \$r
  done
  echo \"live: \$(readlink \$S/game)\""
