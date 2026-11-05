#!/usr/bin/env python3
"""Run one KPI without silently accepting runtime errors, timeouts or competing Godot processes."""
import json
from pathlib import Path
import re
import subprocess
import sys
import time


def other_engines(engine, own=0):
    # The nightly benchmark runs on the Mac. comm avoids collecting unrelated process arguments.
    rows = subprocess.check_output(['ps', '-Ao', 'pid=,comm='], text=True).splitlines()
    name = Path(engine).name.lower()
    result = []
    for row in rows:
        fields = row.strip().split(None, 1)
        if len(fields) != 2:
            continue
        pid, executable = fields
        candidate = Path(executable).name.lower()
        if int(pid) != own and (candidate == name or candidate.startswith('godot')):
            result.append(int(pid))
    return result


def run(prefix, command, timeout=240):
    prefix = Path(prefix)
    prefix.parent.mkdir(parents=True, exist_ok=True)
    # A refused or failed run must not inherit an older result with the same label.
    prefix.with_suffix(".json").unlink(missing_ok=True)
    competitors = set(other_engines(command[0]))
    code = 'not_started'
    timed_out = False
    with prefix.with_suffix('.log').open('w') as log:
        if competitors:
            log.write('ERROR: another Godot process is active; benchmark not started.\n')
        else:
            proc = subprocess.Popen(command, stdout=log, stderr=subprocess.STDOUT)
            deadline = time.monotonic() + timeout
            while proc.poll() is None:
                competitors.update(other_engines(command[0], proc.pid))
                if time.monotonic() >= deadline:
                    timed_out = True
                    proc.terminate()
                    try:
                        proc.wait(timeout=10)
                    except subprocess.TimeoutExpired:
                        proc.kill()
                        proc.wait()
                    break
                time.sleep(.5)
            code = proc.returncode
    text = prefix.with_suffix('.log').read_text()
    errors = re.findall(r'^.*(?:SCRIPT ERROR|Parse Error|ERROR:|WARNING:|crashed).*$', text, re.M)
    validation = dict(clean=code == 0 and not errors and not timed_out,
                      quiet=not competitors, other_godots=sorted(competitors), exit=code,
                      timed_out=timed_out, errors=errors)
    prefix.with_suffix('.validation.json').write_text(json.dumps(validation, indent=1))
    prefix.with_suffix('.exit').write_text(str(code))
    print(prefix.name, json.dumps(validation))
    return 0 if validation['clean'] and validation['quiet'] else 1


if __name__ == '__main__':
    raise SystemExit(run(sys.argv[1], sys.argv[2:]))
