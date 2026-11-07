#!/bin/bash
# The nightly gate: the tests that must pass before a night's work goes to `staging`.
#   bash tools/nightly/gate.sh <log dir>        (exit 0 = all green)
# Single-process tests, then the pairs: the Battlegrounds server + client and the co-op host + join.
# A test fails on any "FAIL" line, a Parse Error, or not finishing within its limit.
set -u
OUT=${1:-/tmp}
mkdir -p "$OUT"
G=/Users/blaine/Applications/Godot_v4.4.1.app/Contents/MacOS/Godot
BAD=0

# wait for a pid up to N seconds; kill it after
waitfor() { local p=$1 n=$2; for i in $(seq 1 "$n"); do kill -0 "$p" 2>/dev/null || return 0; sleep 1; done; kill "$p" 2>/dev/null; return 1; }

check() {  # name, log, finished-in-time
  local name=$1 log=$2 ok=$3 f e
  # (a test script that doesn't compile at all prints "Failed to load script" and no result lines, not "Parse
  # Error": that's a red too, or a broken test reads as green, as playtest did until 2026-11-02. Many tests print a
  # "Compile Error ... Sfx" for a class they reference before the autoload exists and still run: those aren't red.)
  if [ ! -s "$log" ]; then echo "RED   $name (no log at $log)"; BAD=1; return; fi
  f=$(grep -c 'FAIL' "$log"); e=$(grep -c 'Parse Error' "$log")
  if [ "$(grep -c '^\[' "$log")" = 0 ] && grep -q 'Failed to load script' "$log"; then e=$((e + 1)); fi
  if [ "$ok" != 0 ] || [ "$f" -gt 0 ] || [ "$e" -gt 0 ]; then
    echo "RED   $name (fails $f, parse errors $e, timed out $ok)"; grep -m5 'FAIL\|Parse Error\|Failed to load script' "$log"; BAD=1
  else
    echo "GREEN $name"
  fi
}

for t in playtest coop_fx_test title_test char_test ui_click_test grass_test intro_skip_test controls_test telemetry_test screen_test skill_spec_test stamina_test run_build_test survivor_test; do
  "$G" --headless --path . -s tools/$t.gd > "$OUT/gate_$t.log" 2>&1 & p=$!
  waitfor $p 400; check $t "$OUT/gate_$t.log" $?
done
for f in game/heroes/archer/tests/archer_test.gd game/heroes/plague/tests/plague_test.gd tools/warlock_hex_test.gd game/maps/verdant_reach/tests/camp_test.gd; do
  t=$(basename "$f" .gd)
  "$G" --headless --path . --fixed-fps 60 -s "$f" > "$OUT/gate_$t.log" 2>&1 & p=$!
  waitfor $p 400; check $t "$OUT/gate_$t.log" $?
done
# the camp's people and the island (they reach the Sfx autoload: run late)
for f in game/maps/camp/tests/camp_life_test.gd game/maps/camp/tests/vendor_test.gd game/maps/camp/tests/guard_test.gd tools/codex_test.gd tools/codex_book_test.gd game/maps/verdant_reach/tests/camp_reach_test.gd; do
  t=$(basename "$f" .gd)
  "$G" --headless --path . --fixed-fps 60 -s tools/_late.gd -- res://$f > "$OUT/gate_$t.log" 2>&1 & p=$!
  waitfor $p 400; check $t "$OUT/gate_$t.log" $?
done

# the Battlegrounds pair
"$G" --headless --path . -s game/maps/verdant_reach/tests/bg_test.gd -- --server --port 24631 --raid-fast server > "$OUT/gate_bg_server.log" 2>&1 & s=$!
sleep 6
"$G" --headless --path . -s game/maps/verdant_reach/tests/bg_test.gd -- client 24631 > "$OUT/gate_bg_client.log" 2>&1 & c=$!
waitfor $c 420; rc=$?; waitfor $s 200
check bg_test_server "$OUT/gate_bg_server.log" 0
check bg_test_client "$OUT/gate_bg_client.log" $rc

# Battlegrounds PvP: a server and two players
"$G" --headless --path . -s game/maps/verdant_reach/tests/bg_pvp_test.gd -- --server --port 24641 --raid-fast server > "$OUT/gate_pvp_server.log" 2>&1 & s=$!
sleep 6
"$G" --headless --path . -s game/maps/verdant_reach/tests/bg_pvp_test.gd -- a 24641 > "$OUT/gate_pvp_a.log" 2>&1 & a=$!
"$G" --headless --path . -s game/maps/verdant_reach/tests/bg_pvp_test.gd -- b 24641 > "$OUT/gate_pvp_b.log" 2>&1 & b=$!
waitfor $s 300; rc=$?; waitfor $a 30; waitfor $b 30
check pvp_server "$OUT/gate_pvp_server.log" $rc
check pvp_attacker "$OUT/gate_pvp_a.log" 0
check pvp_victim "$OUT/gate_pvp_b.log" 0


# the co-op pairs
for f in tools/mp_test.gd game/heroes/plague/tests/plague_mp_test.gd; do
  t=$(basename "$f" .gd)
  "$G" --headless --path . -s "$f" -- host > "$OUT/gate_${t}_host.log" 2>&1 & h=$!
  sleep 3
  "$G" --headless --path . -s "$f" -- join > "$OUT/gate_${t}_join.log" 2>&1 & j=$!
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
