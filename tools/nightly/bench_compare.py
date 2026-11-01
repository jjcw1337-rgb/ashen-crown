"""Compares the runner's KPI benchmark before and after a night's work (tools/nightly/bench.sh) and decides if it may
ship.
    python bench_compare.py <before.json> <after.json> <date> <job> <log.md> [--check]
    python bench_compare.py <a.json> <b.json> --merge <out.json>      (the better run of each scenario of the two)
--check: only the verdict (exit code), nothing written.
Prints a short Markdown summary (the report includes it), appends both sets to docs/nightly/perf/metrics.jsonl
(source "runner") and one "bench" row to the job's log. Exit 1 = a regression: the average fps over the rendering
scenarios fell more than AVG_DROP, or one scenario's more than ONE_DROP (run-to-run noise is up to ~10% on a single
scenario on this Mac), or the perf job grew the download more than 3%, or the benchmark is missing.
"""
import json
import sys

AVG_DROP, ONE_DROP = 0.07, 0.15
if len(sys.argv) > 3 and sys.argv[3] == "--merge":
    a, b = (json.load(open(p)) for p in sys.argv[1:3])
    m = {k: max((x for x in (a.get(k), b.get(k)) if x), key=lambda r: r.get("fps_avg", 0)) for k in set(a) | set(b)}
    json.dump(m, open(sys.argv[4], "w"), indent=1)
    sys.exit(0)
BEFORE, AFTER, DATE, JOB, LOG = sys.argv[1:6]
CHECK = "--check" in sys.argv
NAMES = {"camp_q2": "camp", "moor_q1": "moor Medium", "moor_q2": "moor", "moor_q3": "moor Ultra", "fight_q2": "fight",
         "boss_q2": "boss", "arena_q2": "arena", "crypt_q2": "crypt"}


def load(p):
    try:
        return json.load(open(p))
    except Exception:
        return {}


b, a = load(BEFORE), load(AFTER)
keys = [k for k in NAMES if k in b and k in a and b[k].get("fps_avg")]
if not keys:
    print("_The runner's benchmark didn't complete (no comparable scenarios), so it can't vouch for tonight's numbers._")
    sys.exit(1)

if not CHECK:
  with open("docs/nightly/perf/metrics.jsonl", "a") as f:
    for phase, d in (("before", b), ("after", a)):
        for k, row in d.items():
            f.write(json.dumps(dict({"date": DATE, "job": JOB, "source": "runner", "phase": phase}, **row)) + "\n")

ratios = {k: a[k]["fps_avg"] / b[k]["fps_avg"] for k in keys}
avg = sum(ratios.values()) / len(ratios)
worst = min(ratios, key=ratios.get)
bad = avg < 1.0 - AVG_DROP or ratios[worst] < 1.0 - ONE_DROP
parts = ["%s %.0f→%.0f" % (NAMES[k], b[k]["fps_avg"], a[k]["fps_avg"]) for k in keys]
extra = []
if "server_q2" in b and "server_q2" in a:
    extra.append("server tick p99 %.0f→%.0f ms" % (b["server_q2"].get("frame_ms_p99", 0), a["server_q2"].get("frame_ms_p99", 0)))
if "camp_q2" in keys:
    extra.append("camp %.0fM→%.0fM tris" % (b["camp_q2"]["primitives"] / 1e6, a["camp_q2"]["primitives"] / 1e6))
if "download" in b and "download" in a:
    z0, z1 = b["download"].get("mac_zip_mb", 0), a["download"].get("mac_zip_mb", 0)
    extra.append("download %.0f→%.0f MB" % (z0, z1))
    if JOB == "perf" and z0 and z1 > z0 * 1.03:     # (the perf job may not grow the download; a new mode may add assets)
        bad, worst = True, "download"
        ratios["download"] = z0 / z1
        NAMES["download"] = "download"
verdict = "BLOCKED: slower (%s %+.0f%%)" % (NAMES[worst], (ratios[worst] - 1) * 100) if bad else "ok (%+.1f%% avg fps)" % ((avg - 1) * 100)

if CHECK:
    sys.exit(1 if bad else 0)
print("**Runner's KPI benchmark** (avg fps, same scenarios on the same Mac, best of 2): " + ", ".join(parts)
      + ("; " + ", ".join(extra) if extra else "") + ". Verdict: " + verdict + ".")
with open(LOG, "a") as f:
    f.write("| %s | bench | Runner's KPI benchmark of the night's result (avg fps) | %s | %s | | `docs/nightly/perf/metrics.jsonl` |\n"
            % (DATE, ", ".join(parts) + ("; " + ", ".join(extra) if extra else ""), "no (blocked)" if bad else "shipped"))
sys.exit(1 if bad else 0)
