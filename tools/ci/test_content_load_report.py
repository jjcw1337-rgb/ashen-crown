"""Diagnostic reports must preserve failed/repeated loads and reject missing evidence."""
import importlib.util
import json
from pathlib import Path
import unittest

spec = importlib.util.spec_from_file_location(
    "content_load_report", Path(__file__).resolve().parents[1] / "content_load_report.py")
report = importlib.util.module_from_spec(spec)
spec.loader.exec_module(report)


def record(path, ms, ok=True, cached=False):
    return report.MARKER + json.dumps({"path": path, "load_ms": ms,
                                     "ok": ok, "cached_before": cached})


class ContentLoadReportTest(unittest.TestCase):
    def test_repeated_roots_and_failures_are_not_dropped(self):
        result = report.summarize("\n".join([
            "Godot startup", record("res://large.glb", 100),
            record("res://small.png", 2), record("res://large.glb", 20, cached=True),
            record("res://missing.glb", 3, ok=False)]))
        self.assertEqual(result["inclusive_worker_ms"], 125)
        self.assertEqual(result["loads"], 4)
        self.assertEqual(result["failures"], 1)
        self.assertEqual(result["resources"][0], {
            "path": "res://large.glb", "loads": 2, "total_ms": 120,
            "max_ms": 100, "failures": 0, "cached_loads": 1})

    def test_missing_trace_is_not_a_zero_cost_pass(self):
        with self.assertRaisesRegex(ValueError, "No resource trace"):
            report.summarize("[CONTENT CONTRACT] 20 checks / 0 failures")

    def test_corrupt_trace_is_not_silently_skipped(self):
        for bad in ["{", "null", "[]", "{}", json.dumps({"path": "x", "load_ms": -1,
                                                        "ok": True, "cached_before": False}),
                    json.dumps({"path": "x", "load_ms": float("nan"),
                                "ok": True, "cached_before": False})]:
            with self.subTest(bad=bad), self.assertRaisesRegex(ValueError, "line 2"):
                report.summarize(record("good", 1) + "\n" + report.MARKER + bad)


if __name__ == "__main__":
    unittest.main()
