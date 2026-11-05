#!/usr/bin/env python3
"""Summarize retained diagnostic artifacts without declaring a performance pass.
Usage: python3 tools/perf_verify_report.py OUTPUT_ROOT REPORT_JSON
"""
import json
from pathlib import Path
import re
import statistics
import sys

source, target = map(Path, sys.argv[1:3])
summary = {'scope': 'Diagnostic source-build verification, not a release benchmark',
           'runtime_revision': '8845213e29577b81fda420b2a0b89e5799231002',
           'settings': {'engine': 'Godot 4.3 Forward+', 'quality': 'High',
                        'viewport': '1600x900', 'vsync': False, 'pipeline_disk_cache': False,
                        'resources': 'Reused read-only imports; driver cache not cleared'},
           'sets': {}}
for group in ('controlled', 'quiet', 'foreground', 'native', 'flow-verified'):
    folder = source/group
    if not (folder/'run-manifest.json').exists():
        continue
    runs = []
    for m in json.loads((folder/'run-manifest.json').read_text()):
        label = m['label']
        f = folder/(label+'.json')
        row = {'label': label, 'exit': m['exit'], 'timeout': m['timeout'],
               'issue_lines': m['issue_lines'], 'other_godot_count': len(m['other_godots'])}
        if f.exists():
            d = json.loads(f.read_text())
            if 'rows' in d:
                row['flow'] = [{k:v for k,v in r.items() if k != 'wall_frames_ms'} for r in d['rows']]
            else:
                row['kpi'] = {k:v for k,v in d.items() if not k.startswith('trace')}
                row['kpi_trace_max_ms'] = max(d.get('trace_frames', [0]))
            audit = folder/(label+'.audit.json')
            if audit.exists():
                a = json.loads(audit.read_text())
                frames = a['wall_frames_ms']
                row['wall'] = {'frames': len(frames), 'max_ms': max(frames, default=0),
                               'over100': sum(x >= 100 for x in frames),
                               'p99_ms': sorted(frames)[min(len(frames)-1, int(len(frames)*.99))] if frames else 0}
                q0, q1 = a['query_start'], a['query_end']
                if frames and q0 and q1:
                    row['query'] = {'calls': q1[0]-q0[0], 'total_us': q1[1]-q0[1],
                                    'ms_per_sampled_frame': (q1[1]-q0[1])/1000/len(frames)}
                for k in ('pipeline_cache', 'observed_render_scales', 'observed_window_focus'):
                    row[k] = a.get(k)
        text = (folder/(label+'.log')).read_text()
        row['phases'] = [{'zone':z, 'phase':p, 'ms':float(t)} for z,p,t in
                         re.findall(r'\[PHASE\] (\S+) (\S+) ([\d.]+)', text)]
        row['boot_ui_setup_ms'] = [float(x) for x in re.findall(r'\[BOOT\] ui_setup ([\d.]+)', text)]
        runs.append(row)
    summary['sets'][group] = runs
gate = source/'gate-results.json'
if gate.exists():
    summary['synthetic_gate'] = json.loads(gate.read_text())
cache = []
for f in sorted(source.glob('cache-*.log')):
    for line in f.read_text().splitlines():
        if line.startswith('[CACHE] '):
            cache.append(json.loads(line[len('[CACHE] '):]))
summary['resource_cache'] = cache
target.parent.mkdir(parents=True, exist_ok=True)
target.write_text(json.dumps(summary, indent=2)+'\n')
for group, rows in summary['sets'].items():
    print(group, len(rows), 'runs; issues', sum(len(r['issue_lines']) for r in rows))
    for scenario in ('moor', 'moor_half', 'fight'):
        subset = [r for r in rows if r['label'].rsplit('-', 1)[0] == scenario and 'kpi' in r]
        if not subset:
            continue
        print(scenario, {k: {'median': statistics.median(r['kpi'][k] for r in subset),
                             'range': [min(r['kpi'][k] for r in subset), max(r['kpi'][k] for r in subset)]}
                          for k in ('fps_avg', 'gpu_ms', 'frame_ms_p99', 'load_ms')})
