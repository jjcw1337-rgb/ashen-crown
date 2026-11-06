#!/bin/bash
# A skill's performance cost (docs/nightly/KPIS.md "Skills"): the KPI fight (24 monsters on the moor, High preset,
# 1600x900, a real window) with the class using only its weapon, then casting only this skill every 1.2 s, and the
# difference. Run it on every new or redone skill before it ships:
#   bash tools/skill_perf.sh <class> <skill id> [quality 0-3] [secs]
# PASS: no new stutters (frames of 100 ms or more) and the average frame at most BUDGET % slower than the weapon alone.
# The JSONs (with --trace: every frame, and when each cast went off) stay in $OUT for a closer look.
set -u
CLS=$1; SKILL=$2; Q=${3:-2}; SECS=${4:-25}
BUDGET=20
G=${GODOT:-/Users/blaine/Applications/Godot_v4.4.1.app/Contents/MacOS/Godot}
OUT=${OUT:-/tmp/skill_perf}
mkdir -p "$OUT"
cd "$(dirname "$0")/.."
for s in none "$SKILL"; do
  "$G" --path . --resolution 1600x900 -- --kpi fight "$OUT/${CLS}_$s.json" --class "$CLS" --skill "$s" --quality "$Q" --secs "$SECS" --trace > "$OUT/${CLS}_$s.log" 2>&1
done
python3 - "$OUT/${CLS}_none.json" "$OUT/${CLS}_$SKILL.json" "$BUDGET" "$SKILL" <<'EOF'
import json, sys
a, b = json.load(open(sys.argv[1])), json.load(open(sys.argv[2]))
budget, skill = float(sys.argv[3]), sys.argv[4]
cost = (1000 / b["fps_avg"]) / (1000 / a["fps_avg"]) * 100 - 100
new_hitch = b["hitches_per_min"] - a["hitches_per_min"]
for k in ["fps_avg", "fps_low1", "frame_ms_p99", "hitches_per_min", "gpu_ms", "draw_calls", "objects"]:
    print("  %-16s weapon %8s   %s %8s" % (k, a[k], skill, b[k]))
print("  casts: %d   frame cost: %+.1f%% (budget %d%%)   new stutters/min: %+.1f" % (len(b.get("trace_casts", [])), cost, budget, new_hitch))
ok = cost <= budget and new_hitch <= 0.5 and len(b.get("trace_casts", [])) > 0
print("PASS" if ok else "FAIL")
sys.exit(0 if ok else 1)
EOF
