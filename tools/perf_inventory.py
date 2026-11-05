#!/usr/bin/env python3
"""Reproducible lexical performance inventory, NOT a reachability proof or lint gate.
Run from any directory. Includes scripts/*.gd, excludes comments and string contents.
Classifications describe access style; a cached first access can still block.
"""
import csv, json, re, subprocess
from collections import Counter
from pathlib import Path
ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'docs/perf'
# Preserve newlines/offsets so every finding has an exact source location.
TOKEN = re.compile(r'"""[\s\S]*?"""|\'\'\'[\s\S]*?\'\'\'|"(?:\\.|[^"\\])*"|\'(?:\\.|[^\'\\])*\'|#[^\n]*')
def blank(m): return ''.join('\n' if c == '\n' else ' ' for c in m.group())
PAT = re.compile(r'\b(?:ResCache\.(?:inst|get_res|hold)|ResourceLoader\.(?:load|load_threaded_request|load_threaded_get)|load|preload|Shader\.new)\s*\(')
rows=[]
for p in sorted((ROOT/'scripts').rglob('*.gd')):
    source=p.read_text(); clean=TOKEN.sub(blank, source)
    lines=source.splitlines(); fn='<top-level>'
    for i, line in enumerate(clean.splitlines(), 1):
        m=re.match(r'(?:static\s+)?func\s+(\w+)\(', line)
        if m: fn=m.group(1)
        for m in PAT.finditer(line):
            api=m.group().split('(')[0].strip()
            literal=re.match(r'\s*["\']([^"\']+)["\']',lines[i-1][m.end():])
            path=literal.group(1) if literal else '<dynamic/expression>'
            if api.startswith('ResCache.'): style='retained-cache-access; first miss can block'
            elif api=='preload': style='script-load-time; not a runtime load call'
            elif api=='ResourceLoader.load_threaded_request': style='background request'
            elif api=='ResourceLoader.load_threaded_get': style='collection; can block unless ready'
            elif api=='Shader.new': style='shader creation; inspect caching and callers'
            elif path.endswith('.gd'): style='script load; inspect first use'
            else: style='direct load; inspect retention and callers'
            rows.append(dict(file=str(p.relative_to(ROOT)),line=i,function=fn,api=api,path=path,classification=style,source=lines[i-1].strip()))
OUT.mkdir(exist_ok=True,parents=True)
with (OUT/'asset-access-inventory.csv').open('w') as f:
    w=csv.DictWriter(f,fieldnames=list(rows[0]));w.writeheader();w.writerows(rows)
imports=[]
tracked=subprocess.check_output(['git','ls-files','assets'],cwd=ROOT,text=True).splitlines()
for name in tracked:
    if not name.endswith(('.png.import','.jpg.import','.jpeg.import')): continue
    text=(ROOT/name).read_text();m=re.search(r'^compress/mode=(\d+)',text,re.M)
    imports.append({'file':name,'compress_mode':int(m.group(1)) if m else None})
summary={'revision':subprocess.check_output(['git','rev-parse','HEAD'],cwd=ROOT,text=True).strip(),
         'scope':'Lexical callsites in scripts/**/*.gd; no call-graph or performance-cost claim.',
         'calls_by_api':dict(Counter(r['api'] for r in rows)),
         'tracked_image_import_modes':dict(Counter(str(r['compress_mode']) for r in imports)),
         'manifest_keys':re.findall(r'^\s*"(\d+:[^"]+)":', (ROOT/'scripts/zone_preload_data.gd').read_text(), re.M)}
(OUT/'inventory-summary.json').write_text(json.dumps(summary,indent=2)+'\n')
(OUT/'image-import-inventory.json').write_text(json.dumps(imports,indent=2)+'\n')
print(json.dumps(summary,indent=2))
