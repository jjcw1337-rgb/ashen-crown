#!/usr/bin/env python3
"""Run cheap content/lifecycle contracts on an imported project and reject Godot's false-green exits."""
import re
import subprocess
import sys

engine = sys.argv[1] if len(sys.argv) > 1 else 'godot'
for tool in ['content_parse_test', 'content_cache_test', 'content_contract_test']:
    run = subprocess.run([engine, '--headless', '--path', '.', '-s', 'tools/_late.gd', '--',
                          f'res://tools/{tool}.gd'], capture_output=True, text=True, timeout=120)
    log = run.stdout + run.stderr
    print(log, end='')
    if run.returncode or re.search(r'SCRIPT ERROR|Parse Error|ERROR:|WARNING:|crashed', log):
        raise SystemExit(f'Performance contract failed: {tool}')
