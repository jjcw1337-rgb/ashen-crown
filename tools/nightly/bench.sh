#!/bin/bash
# The nightly runner's own benchmark: the official performance KPIs (docs/nightly/KPIS.md, scripts/kpi.gd), the
# scoreboard a night's work is judged by, independent of what the session reports.
#   bash tools/nightly/bench.sh <out dir> <label>       (run from the checkout; writes <out dir>/<label>.json)
# Every scenario at High (2), the moor also at Medium (1) and Ultra (3), the dedicated server headless, and the
# download (the macOS export's .zip and .pck). BENCH_RUNS=2 runs each twice (the better run kept, by average fps).
# ~12 min a run. Needs the GUI session (a real window and GPU), as launchd's job has.
set -u
OUT=$1; LABEL=$2
G=/Users/blaine/Applications/Godot_v4.3.app/Contents/MacOS/Godot
mkdir -p "$OUT"
for sc in camp:2 moor:1 moor:2 moor:3 fight:2 boss:2 arena:2 crypt:2 server:2; do
  s=${sc%%:*}; q=${sc##*:}
  for r in $(seq 1 "${BENCH_RUNS:-1}"); do
    f="$OUT/${LABEL}_${s}_q${q}_r$r"
    if [ "$s" = server ]; then
      "$G" --headless --path . -- --server --port 24691 --kpi server "$f.json" > "$f.log" 2>&1 &
    else
      "$G" --path . --resolution 1600x900 -- --kpi "$s" "$f.json" --quality "$q" > "$f.log" 2>&1 &
    fi
    p=$!; for i in $(seq 1 150); do kill -0 $p 2>/dev/null || break; sleep 1; done; kill $p 2>/dev/null
  done
done
# the download: the macOS export's .zip and the .pck in it, from a fresh checkout of HEAD imported from scratch the way
# CI does (a working copy's import cache keeps old import settings; ~70 s)
T=$(mktemp -d)/fresh
git worktree add -q --detach "$T" HEAD && ( cd "$T" && "$G" --headless --path . --import > /dev/null 2>&1 \
  && "$G" --headless --path . --export-release "macOS" "$OUT/${LABEL}_mac.zip" ) > "$OUT/${LABEL}_export.log" 2>&1
git worktree remove --force "$T" 2>/dev/null
python3 -I - "$OUT" "$LABEL" <<'EOF'
import glob, json, os, re, sys, zipfile
out, label = sys.argv[1], sys.argv[2]
res = {}
z = os.path.join(out, label + "_mac.zip")
if os.path.exists(z) and os.path.getsize(z) > 0:
    pck = sum(i.file_size for i in zipfile.ZipFile(z).infolist() if i.filename.endswith(".pck"))
    res["download"] = {"scenario": "download", "mac_zip_mb": round(os.path.getsize(z) / 2**20, 1), "pck_mb": round(pck / 2**20, 1)}
    os.remove(z)
for f in sorted(glob.glob(os.path.join(out, label + "_*_r*.json"))):
    try:
        row = json.load(open(f))
    except Exception:
        continue
    key = re.sub(r"_r\d+\.json$", "", os.path.basename(f))[len(label) + 1:]
    if key not in res or row.get("fps_avg", 0) > res[key].get("fps_avg", 0):
        res[key] = row
json.dump(res, open(os.path.join(out, label + ".json"), "w"), indent=1)
print(label, {k: v.get("fps_avg") for k, v in res.items()})
EOF
