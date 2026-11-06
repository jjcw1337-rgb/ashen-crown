"""Fail-closed performance gate. Three complete, comparable repeats; median metrics, raw runs retained.
python bench_compare.py BEFORE AFTER DATE JOB LOG [--check]
python bench_compare.py A B --merge OUT  # combine raw runs, never select the best result
A fresh schema-2 baseline is required; old simulation-clock/best-run data is not comparable.
"""
import json
import math
from pathlib import Path
import statistics
import sys

NAMES = {"camp_q2": "camp", "moor_q1": "moor Medium", "moor_q2": "moor", "moor_q3": "moor Ultra",
         "fight_q2": "fight", "boss_q2": "boss", "arena_q2": "Aurelia", "crypt_q2": "Battlegrounds",
         "pvp3v3_q2": "3v3 spell flood", "pvp_dragons_q2": "moving dragons", "pvp_forest_q2": "forest summoners", "server_q2": "server"}
METRICS = ("fps_avg", "frame_ms_p99", "frame_ms_max", "first_use_max_ms", "hitches_per_min", "load_ms", "ram_mb", "vram_mb")
CONTEXT = ("schema", "clock", "engine", "renderer", "gpu_name", "resolution", "preset", "scenario", "class", "skill", "environment", "map_title")


def aggregate(rows):
    """Keep samples and take each numeric metric's median. Never hide a failed/missing repeat."""
    rows = [r for row in rows for r in row.get("runs", [row])]
    if not rows:
        raise ValueError("no samples")
    result = dict(rows[0])
    for key in result:
        values = [r.get(key) for r in rows]
        if all(isinstance(v, (int, float)) and not isinstance(v, bool) for v in values):
            result[key] = statistics.median(values)
    result["runs"] = rows
    return result


def validate(data, label):
    errors = []
    for key in NAMES:
        if key not in data:
            errors.append(f"{label}: missing {key}")
            continue
        row = data[key]
        runs = row.get("runs", [])
        if len(runs) < 3:
            errors.append(f"{label}/{key}: needs at least three repeats")
        for i, run in enumerate(runs or [row]):
            prefix = f"{label}/{key}/run{i+1}"
            if run.get("schema") != 2 or run.get("clock") != "monotonic_wall":
                errors.append(f"{prefix}: incompatible measurement schema/clock")
            if run.get("validation", {}).get("clean") is not True:
                errors.append(f"{prefix}: missing clean exit/log validation")
            if run.get("validation", {}).get("quiet") is not True:
                errors.append(f"{prefix}: missing quiet-machine validation")
            if key != "server_q2" and run.get("focused") is not True:
                errors.append(f"{prefix}: not focused throughout measurement")
            for metric in METRICS:
                value = run.get(metric)
                if isinstance(value, bool) or not isinstance(value, (int, float)) or not math.isfinite(value) or value < 0:
                    errors.append(f"{prefix}: invalid {metric}")
            if run.get("frames", 0) <= 0 or run.get("secs", 0) < 10 or run.get("fps_avg", 0) <= 0:
                errors.append(f"{prefix}: incomplete measurement")
            if any(c not in run for c in CONTEXT):
                errors.append(f"{prefix}: missing comparison context")
            if any(run.get(c) != row.get(c) for c in CONTEXT):
                errors.append(f"{prefix}: mixed measurement contexts")
            if run.get("gameplay_sync_misses"):
                errors.append(f"{prefix}: synchronous resource misses during play")
            if key.startswith("pvp"):
                pvp = run.get("pvp", {})
                if pvp.get("actors") != 6 or pvp.get("teams") != [3, 3] or pvp.get("bursts", 0) < 2 or pvp.get("presentation_events", 0) <= 0:
                    errors.append(f"{prefix}: incomplete 3v3 workload")
        # Reject edited summaries that don't describe their retained samples.
        if runs:
            expected = aggregate(runs)
            for metric in METRICS:
                if row.get(metric) != expected.get(metric):
                    errors.append(f"{label}/{key}: summary mismatch for {metric}")
    return errors


def compare(before, after, job="perf"):
    errors = validate(before, "before") + validate(after, "after")
    if errors:
        return errors
    fps_ratios = []
    for key in NAMES:
        b, a = before[key], after[key]
        if any(b.get(c) != a.get(c) for c in CONTEXT):
            errors.append(f"{key}: incomparable hardware/settings/workload")
        ratio = a["fps_avg"] / b["fps_avg"]
        if key != "server_q2":
            fps_ratios.append(ratio)
            if ratio < .85:
                errors.append(f"{key}: FPS fell over 15%")
        # Noise allowances are explicit; stalls and load time count independently of average FPS.
        for metric, fraction, floor in [("frame_ms_p99", .20, 2), ("frame_ms_max", .20, 10),
                                        ("first_use_max_ms", .20, 10), ("hitches_per_min", .20, 1),
                                        ("load_ms", .20, 500), ("ram_mb", .15, 16), ("vram_mb", .15, 64)]:
            if a[metric] > b[metric] + max(b[metric] * fraction, floor):
                errors.append(f"{key}: {metric} regressed {b[metric]} -> {a[metric]}")
            worst_b = max(r[metric] for r in b["runs"])
            worst_a = max(r[metric] for r in a["runs"])
            if worst_a > worst_b + max(worst_b * fraction, floor):
                errors.append(f"{key}: worst repeat {metric} regressed {worst_b} -> {worst_a}")
    if statistics.mean(fps_ratios) < .93:
        errors.append("average FPS fell over 7%")
    if job == "perf" and "download" in before:
        old = before["download"].get("mac_zip_mb", 0)
        new = after.get("download", {}).get("mac_zip_mb", 0)
        if not new or new > old * 1.03:
            errors.append("download missing or grew over 3%")
    return errors


def main(args):
    try:
        before, after = (json.loads(Path(p).read_text()) for p in args[:2])
        if args[2] == "--merge":
            if set(before) != set(after):
                raise ValueError("cannot merge incomplete scenario sets")
            result = {k: aggregate([before[k], after[k]]) if k != "download" else after[k] for k in before}
            Path(args[3]).write_text(json.dumps(result, indent=1))
            return 0
        date, job, log = args[2:5]
        errors = compare(before, after, job)
        verdict = "BLOCKED: " + "; ".join(errors) if errors else "PASS: complete comparable median measurements; no threshold regressions"
        print(verdict)
        if "--check" not in args:
            with Path(log).open("a") as f:
                f.write(f"\n{date} benchmark: {verdict}\n")
        return int(bool(errors))
    except (ValueError, OSError, KeyError, TypeError, IndexError) as e:
        print(f"BLOCKED: invalid benchmark: {e}")
        return 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
