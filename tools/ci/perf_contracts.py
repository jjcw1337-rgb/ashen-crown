#!/usr/bin/env python3
"""Run cheap content/lifecycle contracts on an imported project and reject Godot's false-green exits."""
import re
import subprocess
import sys
from pathlib import Path

# Cache residency can outlive instances. All per-instance surface overrides must
# register the predelete cleanup, including new content added after this migration.
for source in Path('scripts').glob('*.gd'):
    if source.name == 'surface_materials.gd':
        continue
    for line_number, line in enumerate(source.read_text().splitlines(), 1):
        if re.search(r'\bset_surface_override_material\s*\(', line.split('#', 1)[0]):
            raise SystemExit(f'{source}:{line_number}: use SurfaceMaterials.assign for safe retirement')

engine = sys.argv[1] if len(sys.argv) > 1 else 'godot'
for tool in ['content_parse_test', 'content_cache_test', 'content_contract_test', 'content_catalog_test', 'content_parts_test', 'nightly_surface_material_test']:
    run = subprocess.run([engine, '--headless', '--path', '.', '-s', 'tools/_late.gd', '--',
                          f'res://tools/{tool}.gd'], capture_output=True, text=True, timeout=240 if tool == "content_catalog_test" else 120)
    log = run.stdout + run.stderr
    print(log, end='')
    if run.returncode or re.search(r'SCRIPT ERROR|Parse Error|ERROR:|WARNING:|crashed', log):
        raise SystemExit(f'Performance contract failed: {tool}')
