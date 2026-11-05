#!/usr/bin/env python3
"""Run targeted diagnostic pairs, retaining all results and concurrent Godot evidence.
Requires a prepared runtime-only checkout and isolated user directory in override.cfg.
Never imports assets, edits engine settings, stops other processes or publishes metrics.
Usage: python3 tools/perf_verify_runs.py GODOT OUTPUT_DIRECTORY [--flow] [--require-quiet] [--only moor,fight] [--foreground] [--native]
"""
import json
from pathlib import Path
import re
import subprocess
import sys
import time

root = Path(__file__).resolve().parents[1]
godot, output = sys.argv[1:3]
out = Path(output).resolve()
out.mkdir(parents=True, exist_ok=True)
if not (root/'override.cfg').exists() or 'config/custom_user_dir_name=' not in (root/'override.cfg').read_text():
    raise SystemExit('Set an isolated audit user directory in this worktree first.')

def other_godots(own=None):
    lines = subprocess.check_output(['ps', '-Ao', 'pid=,args='], text=True).splitlines()
    return [line.strip() for line in lines if len(line.split()) > 1
            and line.split()[1].endswith('/MacOS/Godot') and line.split()[0] != str(own)]

cases = [('moor', 'moor', []), ('moor_half', 'moor', ['--envoff', 'half']),
         ('fight', 'fight', [])]
if '--flow' in sys.argv:
    cases = [('flow', None, [])]
if '--only' in sys.argv:
    selected = sys.argv[sys.argv.index('--only') + 1].split(',')
    cases = [case for case in cases if case[0] in selected]
    if not cases:
        raise SystemExit('No matching diagnostic scenarios.')
results = []
for repeat in range(1, 4):
    # Alternate the paired intervention order to reduce simple warm-cache/order bias.
    order = cases if repeat != 2 or len(cases) == 1 else [cases[1], cases[0]] + cases[2:]
    for name, scenario, extra in order:
        if Path('/tmp/ashen-nightly.lock').exists():
            raise SystemExit('Nightly lock present; no performance run started.')
        others = other_godots()
        if others and '--require-quiet' in sys.argv:
            raise SystemExit('Another Godot is active; quiet comparison not started.')
        if any('--headless' not in s for s in others):
            raise SystemExit('Another rendered Godot is active; leave it untouched and retry later.')
        label = f'{name}-{repeat}'
        cmd = [godot, '--path', str(root), '--resolution', '1600x900', '--position', '0,0',
               '-s', 'tools/_late.gd', '--', 'res://tools/perf_kpi_entry.gd', '--kpi', scenario,
               str(out/(label+'.json')), '--quality', '2', '--secs', '15', '--trace'] + extra
        if '--foreground' in sys.argv:
            cmd.append('--foreground')
        if '--native' in sys.argv:
            cmd = [godot, '--path', str(root), '--resolution', '1600x900', '--position', '0,0',
                   '--', '--kpi', scenario, str(out/(label+'.json')), '--quality', '2',
                   '--secs', '15', '--trace', '--audit-seed'] + extra
        if scenario is None:
            cmd = [godot, '--path', str(root), '--resolution', '1600x900', '--position', '0,0',
                   '-s', 'tools/_late.gd', '--', 'res://tools/perf_flow_probe.gd',
                   '--out', str(out/(label+'.json'))]
        started = time.monotonic()
        observed = set(others)
        timed_out = False
        print('START', label, 'other headless processes:', len(others), flush=True)
        with (out/(label+'.log')).open('w') as log:
            p = subprocess.Popen(cmd, cwd=root, stdout=log, stderr=subprocess.STDOUT)
            while p.poll() is None:
                observed.update(other_godots(p.pid))
                if time.monotonic() - started > 150:
                    timed_out = True
                    p.kill()
                    p.wait()
                    break
                time.sleep(1)
        text = (out/(label+'.log')).read_text(errors='replace')
        issues = [s for s in text.splitlines() if re.search(r'ERROR|WARNING|\[mvk-error\]|Parse Error', s)]
        entry = dict(label=label, command=cmd, exit=p.returncode, timeout=timed_out,
                     seconds=round(time.monotonic()-started, 2), other_godots=sorted(observed),
                     issue_lines=issues)
        results.append(entry)
        (out/'run-manifest.json').write_text(json.dumps(results, indent=2)+'\n')
        print('END', label, 'exit', p.returncode, 'issues', len(issues), 'seconds', entry['seconds'], flush=True)
        if observed and '--require-quiet' in sys.argv:
            raise SystemExit('Concurrent Godot appeared: this run is contaminated; no further run started.')
        if timed_out or 'SCRIPT ERROR' in text or 'Parse Error' in text or p.returncode != 0:
            raise SystemExit('Invalid run; inspect log before continuing.')
