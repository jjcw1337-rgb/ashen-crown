#!/bin/sh
# Makes a player account an Ashen Crown admin (or not) on the staging backend: the game shows that account its admin
# tools (the Escape menu's Admin column) in any build, and the Battlegrounds server lets it raid with "Go to level 20"
# gear (deploy/nakama/modules/ashen.lua: admin_set / admin_status / admin_check).
#   sh tools/admin_role.sh <account id> on|off ["name"] [ssh-host]
# The account id is shown in the Admin column ("account ...") and in the Battlegrounds screen's log line
# "[Cloud] account". The call runs on the server itself, with Nakama's runtime key read there: the key never leaves it.
set -eu
ID=${1:?account id}
ON=${2:?on or off}
NAME=${3:-}
HOST=${4:-ashen-crown-staging}
case "$ID" in *[!0-9a-f-]*) echo "not an account id: $ID"; exit 1 ;; esac
case "$NAME" in *[!A-Za-z0-9\ _.-]*) echo "keep the name to letters, digits, spaces"; exit 1 ;; esac
ADMIN=false
[ "$ON" = on ] && ADMIN=true
ssh "$HOST" "set -e; K=\$(sudo sed -n 's/^NAKAMA_HTTP_KEY=//p' /opt/ashen-crown/staging/backend/nakama.env); \
  curl -s -X POST \"http://127.0.0.1:7350/v2/rpc/admin_set?http_key=\$K&unwrap\" -H 'Content-Type: application/json' \
  -d '{\"user_id\":\"$ID\",\"admin\":$ADMIN,\"name\":\"$NAME\"}'"
echo
