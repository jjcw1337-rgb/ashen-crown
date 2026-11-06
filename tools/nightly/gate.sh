#!/bin/bash
# The nightly gate: the tests that must pass before a night's work goes to `staging`.
#   bash tools/nightly/gate.sh <log dir>        (exit 0 = all green)
# Single-process tests, then the pairs: the Battlegrounds server + client and the co-op host + join.
# A test fails on any "FAIL" line, a Parse Error, or not finishing within its limit.
set -u
OUT=${1:-/tmp}
mkdir -p "$OUT"
G=${GODOT_BIN:-/Users/blaine/Applications/Godot_v4.4.1.app/Contents/MacOS/Godot}
[ ! -e /tmp/ashen-nightly.lock ] || { echo "Nightly owns the test window"; exit 1; }
BG_PORT=${GATE_BG_PORT:-24631}
PVP_PORT=${GATE_PVP_PORT:-24641}
COOP_PORT=${GATE_COOP_PORT:-24651}
LAN_PORT=${GATE_LAN_PORT:-24567}
QUEUE_PORT=${GATE_QUEUE_PORT:-$((COOP_PORT - 1))}
NATIVE_DEFAULT=0
[ "$(uname -s)" = Darwin ] && NATIVE_DEFAULT=1
UI_RENDERED=${GATE_UI_RENDERED:-$NATIVE_DEFAULT}
BAD=0

# wait for a pid up to N seconds; kill it after
waitfor() { local p=$1 n=$2; for i in $(seq 1 "$n"); do kill -0 "$p" 2>/dev/null || { wait "$p"; return $?; }; sleep 1; done; kill "$p" 2>/dev/null; wait "$p" 2>/dev/null; return 124; }

# A LAN host builds a world before opening its socket. Start clients on readiness,
# not a three-second guess that races asynchronous preparation.
waitready() { local p=$1 log=$2; for i in $(seq 1 180); do
  grep -q "^\[GATE_READY\] host_port=$LAN_PORT$" "$log" && return 0
  kill -0 "$p" 2>/dev/null || return 1
  sleep 1
 done; return 1; }

check() {  # name, log, child exit status (124 means timeout)
  local name=$1 log=$2 ok=$3 f e
  # (a test script that doesn't compile at all prints "Failed to load script" and no result lines, not "Parse
  # Error": that's a red too, or a broken test reads as green, as playtest did until 2026-11-02. Tools are now run after autoload initialization, so script/compile errors are always red.)
  if [ ! -s "$log" ]; then echo "RED   $name (no log at $log)"; BAD=1; return; fi
  f=$(grep -c 'FAIL' "$log"); e=$(grep -Ec 'SCRIPT ERROR|Parse Error|Compile Error' "$log")
  if [ "$(grep -c '^\[' "$log")" = 0 ] && grep -q 'Failed to load script' "$log"; then e=$((e + 1)); fi
  if [ "$name" = telemetry_test ]; then
    if ! python3 tools/nightly/check_functional_log.py "$log" --telemetry-fixture; then e=$((e + 1)); fi
  else
    if ! python3 tools/nightly/check_functional_log.py "$log"; then e=$((e + 1)); fi
  fi
  if [ "$ok" != 0 ] || [ "$f" -gt 0 ] || [ "$e" -gt 0 ]; then
    echo "RED   $name (fails $f, error markers $e, exit $ok)"; grep -m5 'FAIL\|Parse Error\|Failed to load script' "$log"; BAD=1
  else
    echo "GREEN $name"
  fi
}

# Native compile/type checks precede expensive world and network tests.
"$G" --headless --path . -s tools/_late.gd -- res://tools/content_parse_test.gd > "$OUT/gate_content_parse_test.log" 2>&1 & p=$!
waitfor $p 60; rc=$?; check content_parse_test "$OUT/gate_content_parse_test.log" "$rc"
[ "$BAD" = 0 ] || exit "$BAD"

# Corrupt-save recovery is part of the integrated release; check it before long match tests.
if [ "$UI_RENDERED" = 1 ]; then
  "$G" --path . -s tools/char_test.gd > "$OUT/gate_char_test.log" 2>&1 & p=$!
else
  "$G" --headless --path . -s tools/char_test.gd > "$OUT/gate_char_test.log" 2>&1 & p=$!
fi
waitfor $p 400; rc=$?; check char_test "$OUT/gate_char_test.log" "$rc"
[ "$BAD" = 0 ] || exit "$BAD"

# Check the corrected projectile and newly integrated run/Warlock fixtures before long matches.
for t in archer_sweep_test run_talents_test warlock_hex_test; do
  if [ "$t" = warlock_hex_test ]; then
    if [ "$UI_RENDERED" = 1 ]; then
      "$G" --path . --fixed-fps 60 -s tools/_late.gd -- res://tools/$t.gd > "$OUT/gate_$t.log" 2>&1 & p=$!
    else
      "$G" --headless --path . --fixed-fps 60 -s tools/_late.gd -- res://tools/$t.gd > "$OUT/gate_$t.log" 2>&1 & p=$!
    fi
  else
    "$G" --headless --path . -s tools/_late.gd -- res://tools/$t.gd > "$OUT/gate_$t.log" 2>&1 & p=$!
  fi
  waitfor $p 600; rc=$?; check $t "$OUT/gate_$t.log" "$rc"
  [ "$BAD" = 0 ] || exit "$BAD"
done

# Prioritize the affected competitive modes before the broader regression suite.
# A completed pair may be reused after an infrastructure interruption only when
# the checkpoint verifies identical runtime/assets/fixtures and the original clean exits.
if [ -n "${GATE_BG_CHECKPOINT:-}" ] && python3 tools/nightly/gate_checkpoint.py restore "$GATE_BG_CHECKPOINT" "$OUT"; then
  check bg_test_server "$OUT/gate_bg_server.log" 0
  check bg_test_client "$OUT/gate_bg_client.log" 0
else
# the Battlegrounds pair
"$G" --headless --path . -s tools/_late.gd -- res://tools/bg_test.gd --server --port "$BG_PORT" --raid-fast server > "$OUT/gate_bg_server.log" 2>&1 & s=$!
sleep 6
if [ "$UI_RENDERED" = 1 ]; then
  "$G" --path . -s tools/_late.gd -- res://tools/bg_test.gd client "$BG_PORT" --capture "$OUT/battlegrounds.png" > "$OUT/gate_bg_client.log" 2>&1 & c=$!
else
  "$G" --headless --path . -s tools/_late.gd -- res://tools/bg_test.gd client "$BG_PORT" --capture "$OUT/battlegrounds.png" > "$OUT/gate_bg_client.log" 2>&1 & c=$!
fi
waitfor $c 420; rc=$?; waitfor $s 200; rs=$?
check bg_test_server "$OUT/gate_bg_server.log" $rs
check bg_test_client "$OUT/gate_bg_client.log" $rc

fi

if [ -n "${GATE_PVP_CHECKPOINT:-}" ] && python3 tools/nightly/gate_checkpoint.py restore "$GATE_PVP_CHECKPOINT" "$OUT" pvp; then
  check pvp_server "$OUT/gate_pvp_server.log" 0
  check pvp_attacker "$OUT/gate_pvp_a.log" 0
  check pvp_victim "$OUT/gate_pvp_b.log" 0
else
# Battlegrounds PvP: a server and two players
"$G" --headless --path . -s tools/_late.gd -- res://tools/bg_pvp_test.gd --server --port "$PVP_PORT" --raid-fast server > "$OUT/gate_pvp_server.log" 2>&1 & s=$!
sleep 6
"$G" --headless --path . -s tools/_late.gd -- res://tools/bg_pvp_test.gd a "$PVP_PORT" > "$OUT/gate_pvp_a.log" 2>&1 & a=$!
"$G" --headless --path . -s tools/_late.gd -- res://tools/bg_pvp_test.gd b "$PVP_PORT" > "$OUT/gate_pvp_b.log" 2>&1 & b=$!
waitfor $s 300; rc=$?; waitfor $a 30; ra=$?; waitfor $b 30; rb=$?
check pvp_server "$OUT/gate_pvp_server.log" $rc
check pvp_attacker "$OUT/gate_pvp_a.log" $ra
check pvp_victim "$OUT/gate_pvp_b.log" $rb


fi

for t in archer_bow_spring_test terrain_job_test content_contract_test content_world_test playtest coop_fx_test title_test ui_click_test grass_test intro_skip_test controls_test telemetry_test screen_test skill_spec_test stamina_test raid_schedule_test run_build_test camp_test survivor_test; do
  if [ "$t" = title_test ] || [ "$t" = char_test ]; then
    # Avoid empty arrays under the Mac's Bash 3.2 + set -u.
    if [ "$UI_RENDERED" = 1 ]; then
      "$G" --path . -s "tools/$t.gd" > "$OUT/gate_$t.log" 2>&1 & p=$!
    else
      "$G" --headless --path . -s "tools/$t.gd" > "$OUT/gate_$t.log" 2>&1 & p=$!
    fi
  else
    "$G" --headless --path . -s tools/_late.gd -- res://tools/$t.gd > "$OUT/gate_$t.log" 2>&1 & p=$!
  fi
  limit=400
  # Full real-time replay includes every class plus shared skills, not just the first class.
  [ "$t" = coop_fx_test ] && limit=1200
  waitfor $p "$limit"; check $t "$OUT/gate_$t.log" $?
done
for t in archer_test plague_test sandbox_test sandbox_entry_test; do
  if [ "$t" != plague_test ] && [ "$UI_RENDERED" = 1 ]; then
    "$G" --path . --fixed-fps 60 -s tools/_late.gd -- res://tools/$t.gd > "$OUT/gate_$t.log" 2>&1 & p=$!
  else
    "$G" --headless --path . --fixed-fps 60 -s tools/_late.gd -- res://tools/$t.gd > "$OUT/gate_$t.log" 2>&1 & p=$!
  fi
  waitfor $p 400; check $t "$OUT/gate_$t.log" $?
done
# the camp's people and the island (they reach the Sfx autoload: run late)
for t in camp_life_test vendor_test guard_test codex_test codex_book_test camp_reach_test; do
  if [ "$t" = codex_book_test ] && [ "$UI_RENDERED" = 1 ]; then
    "$G" --path . --fixed-fps 60 -s tools/_late.gd -- res://tools/$t.gd shots "$OUT/codex_book" > "$OUT/gate_$t.log" 2>&1 & p=$!
  else
    "$G" --headless --path . --fixed-fps 60 -s tools/_late.gd -- res://tools/$t.gd > "$OUT/gate_$t.log" 2>&1 & p=$!
  fi
  waitfor $p 400; check $t "$OUT/gate_$t.log" $?
done

# the online co-op server with two players
"$G" --headless --path . -s tools/_late.gd -- res://tools/coop_server_test.gd --server --coop --port "$COOP_PORT" --queue-port "$QUEUE_PORT" server > "$OUT/gate_coop_server.log" 2>&1 & s=$!
sleep 6
"$G" --headless --path . -s tools/_late.gd -- res://tools/coop_server_test.gd a "$COOP_PORT" > "$OUT/gate_coop_a.log" 2>&1 & a=$!
"$G" --headless --path . -s tools/_late.gd -- res://tools/coop_server_test.gd b "$COOP_PORT" > "$OUT/gate_coop_b.log" 2>&1 & b=$!
waitfor $s 300; rc=$?; waitfor $a 30; ra=$?; waitfor $b 30; rb=$?
check coop_server "$OUT/gate_coop_server.log" $rc
check coop_player_a "$OUT/gate_coop_a.log" $ra
check coop_player_b "$OUT/gate_coop_b.log" $rb

# the co-op pairs
for t in mp_test plague_mp_test; do
  "$G" --headless --path . -s tools/_late.gd -- host --test-port "$LAN_PORT" res://tools/$t.gd > "$OUT/gate_${t}_host.log" 2>&1 & h=$!
  if ! waitready "$h" "$OUT/gate_${t}_host.log"; then
    echo "RED   ${t}_host (did not become ready)"; BAD=1
    kill "$h" 2>/dev/null; wait "$h" 2>/dev/null
    continue
  fi
  "$G" --headless --path . -s tools/_late.gd -- join --test-port "$LAN_PORT" res://tools/$t.gd > "$OUT/gate_${t}_join.log" 2>&1 & j=$!
  waitfor $j 300; rc=$?; waitfor $h 60; rh=$?
  check ${t}_host "$OUT/gate_${t}_host.log" $rh
  check ${t}_join "$OUT/gate_${t}_join.log" $rc
done

# Actual lobby workers and two clients: survivor Arena and late-joining Sandbox.
# The caller holds heavy-tests; ports and output stay separate from other agents.
for mode in arena sandbox; do
  if [ "$UI_RENDERED" = 1 ]; then
    python3 tools/nightly/lobby_gate.py "$mode" "$OUT/${mode}_lobby" --godot "$G" --rendered --broker-port "${GATE_BROKER_PORT:-7354}" --worker-port "${GATE_WORKER_PORT:-24640}" > "$OUT/gate_${mode}_lobby.log" 2>&1
  else
    python3 tools/nightly/lobby_gate.py "$mode" "$OUT/${mode}_lobby" --godot "$G" --broker-port "${GATE_BROKER_PORT:-7354}" --worker-port "${GATE_WORKER_PORT:-24640}" > "$OUT/gate_${mode}_lobby.log" 2>&1
  fi
  rc=$?
  if [ "$rc" = 0 ]; then echo "GREEN ${mode}_lobby"; else echo "RED   ${mode}_lobby (see $OUT/gate_${mode}_lobby.log)"; BAD=1; fi
done

# any test the night added: tools/nightly_*_test.gd (single process) are run too
for f in tools/nightly_*_test.gd; do
  [ -f "$f" ] || continue
  t=$(basename "$f" .gd)
  if [ "$t" = nightly_vigil_test ] && [ "$UI_RENDERED" = 1 ]; then
    "$G" --path . -s tools/_late.gd -- "res://$f" > "$OUT/gate_$t.log" 2>&1 & p=$!
  else
    "$G" --headless --path . -s tools/_late.gd -- "res://$f" > "$OUT/gate_$t.log" 2>&1 & p=$!
  fi
  waitfor $p 400; check $t "$OUT/gate_$t.log" $?
done
exit $BAD
