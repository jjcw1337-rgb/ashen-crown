#!/bin/bash
# The nightly gate: the tests that must pass before a night's work goes to `staging`.
#   bash tools/nightly/gate.sh <log dir>        (exit 0 = all green)
# Single-process tests, then the pairs: the Battlegrounds server + client and the co-op host + join.
# A test fails on any "FAIL" line, a Parse Error, or not finishing within its limit.
set -u
OUT=${1:-/tmp}
G=/Users/blaine/Applications/Godot_v4.3.app/Contents/MacOS/Godot
BAD=0

# wait for a pid up to N seconds; kill it after
waitfor() { local p=$1 n=$2; for i in $(seq 1 "$n"); do kill -0 "$p" 2>/dev/null || return 0; sleep 1; done; kill "$p" 2>/dev/null; return 1; }

check() {  # name, log, finished-in-time
  local name=$1 log=$2 ok=$3 f e
  f=$(grep -c 'FAIL' "$log"); e=$(grep -c 'Parse Error' "$log")
  if [ "$ok" != 0 ] || [ "$f" -gt 0 ] || [ "$e" -gt 0 ]; then
    echo "RED   $name (fails $f, parse errors $e, timed out $ok)"; grep -m5 'FAIL\|Parse Error' "$log"; BAD=1
  else
    echo "GREEN $name"
  fi
}

for t in playtest coop_fx_test title_test char_test ui_click_test grass_test intro_skip_test; do
  "$G" --headless --path . -s tools/$t.gd > "$OUT/gate_$t.log" 2>&1 & p=$!
  waitfor $p 400; check $t "$OUT/gate_$t.log" $?
done
for t in archer_test plague_test; do
  "$G" --headless --path . --fixed-fps 60 -s tools/$t.gd > "$OUT/gate_$t.log" 2>&1 & p=$!
  waitfor $p 400; check $t "$OUT/gate_$t.log" $?
done

# the Battlegrounds pair
"$G" --headless --path . -s tools/bg_test.gd -- --server --port 24631 server > "$OUT/gate_bg_server.log" 2>&1 & s=$!
sleep 6
"$G" --headless --path . -s tools/bg_test.gd -- client 24631 > "$OUT/gate_bg_client.log" 2>&1 & c=$!
waitfor $c 300; rc=$?; waitfor $s 60
check bg_test_server "$OUT/gate_bg_server.log" 0
check bg_test_client "$OUT/gate_bg_client.log" $rc

# the online co-op server with two players
"$G" --headless --path . -s tools/coop_server_test.gd -- --server --coop --port 24651 server > "$OUT/gate_coop_server.log" 2>&1 & s=$!
sleep 6
"$G" --headless --path . -s tools/coop_server_test.gd -- a 24651 > "$OUT/gate_coop_a.log" 2>&1 & a=$!
"$G" --headless --path . -s tools/coop_server_test.gd -- b 24651 > "$OUT/gate_coop_b.log" 2>&1 & b=$!
waitfor $s 300; rc=$?; waitfor $a 30; waitfor $b 30
check coop_server "$OUT/gate_coop_server.log" $rc
check coop_player_a "$OUT/gate_coop_a.log" 0
check coop_player_b "$OUT/gate_coop_b.log" 0

# the co-op pairs
for t in mp_test plague_mp_test; do
  "$G" --headless --path . -s tools/$t.gd -- host > "$OUT/gate_${t}_host.log" 2>&1 & h=$!
  sleep 3
  "$G" --headless --path . -s tools/$t.gd -- join > "$OUT/gate_${t}_join.log" 2>&1 & j=$!
  waitfor $j 300; rc=$?; waitfor $h 60
  check ${t}_host "$OUT/gate_${t}_host.log" 0
  check ${t}_join "$OUT/gate_${t}_join.log" $rc
done

# any test the night added: tools/nightly_*_test.gd (single process) are run too
for f in tools/nightly_*_test.gd; do
  [ -f "$f" ] || continue
  t=$(basename "$f" .gd)
  "$G" --headless --path . -s "$f" > "$OUT/gate_$t.log" 2>&1 & p=$!
  waitfor $p 400; check $t "$OUT/gate_$t.log" $?
done
exit $BAD
