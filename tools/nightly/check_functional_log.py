"""Fail unexpected runtime errors; explicitly report the existing Godot 4.3 dummy-renderer defect."""
import re
import sys
from pathlib import Path

def inspect(text, telemetry_fixture=False):
    lines = re.sub(r'\x1b\[[0-9;]*m', '', text).splitlines()
    known, errors, warnings = 0, [], []
    expected = {f'ERROR: telemetry test error {n}' for n in (1234, 5678)}
    injections_ok = telemetry_fixture and all(lines.count(s) == 1 for s in expected) and all(
        lines.count(f'[T] EXPECT TELEMETRY INJECTION {n}') == 1 for n in (1234, 5678)) and (
        '[T] ok   an error from the log, fingerprinted: one issue, counted twice (2)' in lines
        and '[T] done, 0 failed' in lines)
    if telemetry_fixture and not injections_ok:
        errors.append('Telemetry fixture did not prove exactly its two expected error injections')
    for i, line in enumerate(lines):
        if 'WARNING:' in line:
            warnings.append(line)
        if re.search(r'SCRIPT ERROR|Parse Error|Compile Error|ERROR:|\bFAIL\b', line):
            stack = lines[i + 1] if i + 1 < len(lines) else ''
            if line.strip() == 'ERROR: Parameter "m" is null.' and 'servers/rendering/dummy/storage/mesh_storage.h:120' in stack:
                known += 1
            elif injections_ok and line in expected and 'at: push_error (core/variant/variant_utility.cpp:' in stack:
                pass
            else:
                errors.append(line)
    return known, errors, warnings

if __name__ == '__main__':
    telemetry_fixture = '--telemetry-fixture' in sys.argv[2:]
    known, errors, warnings = inspect(Path(sys.argv[1]).read_text(), telemetry_fixture)
    if telemetry_fixture and not errors:
        print('Verified exactly two intentional telemetry error injections and their reporting assertions.')
    if known or warnings:
        print(f'Runtime caveat: {known} known dummy mesh errors; {len(warnings)} warnings (full log retained).')
    for error in errors[:8]:
        print(error)
    sys.exit(1 if errors else 0)
