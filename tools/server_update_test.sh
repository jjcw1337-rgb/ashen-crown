#!/bin/bash
# A deploy never kicks players (ServerUpdate, scripts/server_update.gd): a co-op server running release r1 behind a
# `game` link keeps running while two players play (tools/coop_server_test.gd a/b) after the link moves to r2, and
# restarts into it once they've gone; an empty one restarts within ServerUpdate.CHECK.
#   bash tools/server_update_test.sh            prints PASS or FAIL lines; exit 1 on a failure
set -u
G=${GODOT:-$HOME/Applications/Godot_v4.4.1.app/Contents/MacOS/Godot}
ROOT=$(cd "$(dirname "$0")/.." && pwd)
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
mkdir -p "$T/rel1" "$T/rel2"
git -C "$ROOT" ls-files -z -co --exclude-standard | (cd "$ROOT" && xargs -0 tar -cf - 2>/dev/null) | tar -xf - -C "$T/rel1"
echo r1 > "$T/rel1/DEPLOYED_REV"; echo r2 > "$T/rel2/DEPLOYED_REV"
ln -sfn "$T/rel1" "$T/game"
"$G" --headless --path "$T/rel1" --import > /dev/null 2>&1
fails=0
ok() { if eval "$2"; then echo "PASS $1"; else echo "FAIL $1"; fails=$((fails+1)); fi; }
ASHEN_LIVE_DIR="$T/game" "$G" --headless --path "$T/rel1" -- --server --coop --port 24597 > "$T/s.log" 2>&1 & s=$!
sleep 15
"$G" --headless --path "$T/rel1" -s tools/coop_server_test.gd -- a 24597 > "$T/a.log" 2>&1 & a=$!
"$G" --headless --path "$T/rel1" -s tools/coop_server_test.gd -- b 24597 > "$T/b.log" 2>&1 & b=$!
sleep 20
ln -sfn "$T/rel2" "$T/game"
wait $a $b
ok "players played on through the deploy" "grep -aq 'done, 0 failed' '$T/a.log' && grep -aq 'done, 0 failed' '$T/b.log'"
ok "the server waited for them" "grep -aq 'waiting for the players' '$T/s.log'"
sleep 30
ok "then it restarted into the new release" "! kill -0 $s 2>/dev/null && grep -aq 'restarting into it' '$T/s.log'"
kill $s 2>/dev/null
exit $(( fails > 0 ))
