#!/bin/sh
# Runs the balance sim and keeps a dated report in build/balance/ (git-ignored).
# Usage: tools/balance.sh [sim args, e.g. classes=knight,warlock or quick]
# Godot: $GODOT if set, else `godot` on PATH. Exit code 2 = something flagged, 1 = the sim broke.
cd "$(dirname "$0")/.." || exit 1
GODOT_BIN="${GODOT:-godot}"
OUT=build/balance
mkdir -p "$OUT"
STAMP=$(date +%Y-%m-%d_%H%M)
"$GODOT_BIN" --headless --fixed-fps 30 --path . -s tools/balance_sim.gd -- "out=$OUT/$STAMP.json" "$@" > "$OUT/$STAMP.log" 2>&1
grep -q "^\[BAL\] wrote" "$OUT/$STAMP.log" || { echo "balance sim failed, see $OUT/$STAMP.log"; exit 1; }
grep "^\[BAL" "$OUT/$STAMP.log" > "$OUT/$STAMP.txt"
cp "$OUT/$STAMP.txt" "$OUT/latest.txt"
cp "$OUT/$STAMP.json" "$OUT/latest.json"
grep "^\[BAL\] [0-9]* results" "$OUT/$STAMP.txt"
grep -q "^\[BAL-FLAG\]" "$OUT/$STAMP.txt" && exit 2
exit 0
