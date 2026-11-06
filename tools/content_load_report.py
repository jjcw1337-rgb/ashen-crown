#!/usr/bin/env python3
"""Rank inclusive resource-load time from one --content-trace Godot process log.

This explains resource preparation, not total loading, VRAM or gameplay performance.
Do not combine logs from concurrent processes: worker time would be double-counted.
"""
import argparse
import json
import math
from pathlib import Path

MARKER = "[CONTENT LOAD] "


def summarize(log: str) -> dict:
    paths = {}
    for number, line in enumerate(log.splitlines(), 1):
        if MARKER not in line:
            continue
        try:
            event = json.loads(line.split(MARKER, 1)[1])
            path = event["path"]
            elapsed = event["load_ms"]
            if (not isinstance(path, str) or not path
                    or isinstance(elapsed, bool) or not isinstance(elapsed, (int, float))
                    or not math.isfinite(elapsed) or elapsed < 0
                    or not isinstance(event["ok"], bool)
                    or not isinstance(event["cached_before"], bool)):
                raise ValueError("invalid load record")
        except (ValueError, KeyError, TypeError) as exc:
            raise ValueError(f"Malformed resource trace at line {number}") from exc
        row = paths.setdefault(path, {"path": path, "loads": 0, "total_ms": 0.0,
                                      "max_ms": 0.0, "failures": 0, "cached_loads": 0})
        row["loads"] += 1
        row["total_ms"] += elapsed
        row["max_ms"] = max(row["max_ms"], elapsed)
        row["failures"] += int(not event["ok"])
        row["cached_loads"] += int(event["cached_before"])
    if not paths:
        raise ValueError("No resource trace records; rerun with --content-trace")
    rows = sorted(paths.values(), key=lambda row: (-row["total_ms"], row["path"]))
    return {"inclusive_worker_ms": sum(row["total_ms"] for row in rows),
            "loads": sum(row["loads"] for row in rows),
            "failures": sum(row["failures"] for row in rows), "resources": rows}


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("log", type=Path)
    args = parser.parse_args()
    try:
        report = summarize(args.log.read_text())
    except (ValueError, OSError) as exc:
        parser.exit(2, f"{exc}\n")
    print(json.dumps(report, indent=2))
    if report["failures"]:
        raise SystemExit(1)


if __name__ == "__main__":
    main()
