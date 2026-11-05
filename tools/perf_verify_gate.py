#!/usr/bin/env python3
"""Exercise the existing nightly gate with synthetic evidence; never edits the gate.
Usage: python3 tools/perf_verify_gate.py /absolute/output/directory
These fixtures demonstrate policy coverage, not real game performance.
"""
import copy
import json
from pathlib import Path
import subprocess
import sys

root = Path(__file__).resolve().parents[1]
out = Path(sys.argv[1]).resolve()
out.mkdir(parents=True, exist_ok=True)
keys = ['camp_q2', 'moor_q1', 'moor_q2', 'moor_q3', 'fight_q2',
        'boss_q2', 'arena_q2', 'crypt_q2']
row = dict(fps_avg=60, frame_ms_p99=20, hitches_per_min=0,
           load_ms=2500, primitives=1000000)
before = {k: row.copy() for k in keys}
base = out / 'gate-baseline.json'
base.write_text(json.dumps(before, indent=2))
cases = [('unchanged', copy.deepcopy(before)), ('seven_scenarios_missing', {'camp_q2': row.copy()})]
for name, metric, value in [('p99_500ms', 'frame_ms_p99', 500),
                            ('hitches_20_per_min', 'hitches_per_min', 20),
                            ('load_20_seconds', 'load_ms', 20000),
                            ('fps_40_control', 'fps_avg', 40)]:
    changed = copy.deepcopy(before)
    changed['fight_q2'][metric] = value
    cases.append((name, changed))
results = []
for name, changed in cases:
    path = out / ('gate-' + name + '.json')
    path.write_text(json.dumps(changed, indent=2))
    p = subprocess.run([sys.executable, str(root/'tools/nightly/bench_compare.py'),
                        str(base), str(path), '2026-11-05', 'perf', str(out/'unused.md'), '--check'],
                       cwd=root, capture_output=True, text=True, timeout=10)
    results.append(dict(case=name, exit_code=p.returncode, accepted=p.returncode == 0,
                        output=p.stdout+p.stderr))
result = {'kind': 'synthetic_gate_probe', 'results': results}
(out/'gate-results.json').write_text(json.dumps(result, indent=2)+'\n')
print(json.dumps(result, indent=2))
