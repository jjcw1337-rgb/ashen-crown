"""Reuse completed network checks after a runner interruption, only for identical runtime/test inputs."""
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
from check_functional_log import inspect

ROOT = Path(__file__).resolve().parents[2]
GROUP = sys.argv[4] if len(sys.argv) > 4 else "bg"
CASES = {
    "bg": [("bg_test_server", "gate_bg_server.log", "S"), ("bg_test_client", "gate_bg_client.log", "C")],
    "pvp": [("pvp_server", "gate_pvp_server.log", "SERVER"), ("pvp_attacker", "gate_pvp_a.log", "A"), ("pvp_victim", "gate_pvp_b.log", "B")],
}[GROUP]
FILES = tuple(row[1] for row in CASES)

def inputs():
    paths = subprocess.check_output(['git', 'ls-files', '-z'], cwd=ROOT).decode().split('\0')
    # Include game data/assets, shaders, native extensions, project settings and GDScript fixtures.
    return sorted(p for p in paths if p and (p.startswith(('scripts/', 'assets/', 'addons/', 'data/')) or
        p.endswith(('.godot', '.tscn', '.tres')) or p.startswith('tools/') and p.endswith(('.gd', '.gd.uid'))))

def fingerprint():
    digest = hashlib.sha256()
    for name in inputs():
        digest.update(name.encode() + b'\0')
        digest.update(hashlib.sha256((ROOT / name).read_bytes()).digest())
    for path in (ROOT / "override.cfg", Path(os.environ.get("GODOT_BIN", "/Users/blaine/Applications/Godot_v4.4.1.app/Contents/MacOS/Godot"))):
        digest.update(hashlib.sha256(path.read_bytes()).digest())
    return digest.hexdigest()

def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

def validate_logs(folder):
    driver = (folder / 'driver.log').read_text()
    for name, filename, prefix in CASES:
        assert 'GREEN ' + name in driver, 'The original gate did not verify exit/log status'
        text = (folder / filename).read_text()
        assert not inspect(text)[1], 'Runtime errors in checkpoint'
        assert f"[{prefix}] done, 0 failed" in text
        if GROUP == 'bg': assert 'ok   content owners and loading jobs retired' in text

def main():
    mode, old = sys.argv[1], Path(sys.argv[2]).resolve()
    validate_logs(old)
    stamp = old / (GROUP + '-checkpoint.json')
    if mode == 'save':
        commit = sys.argv[3]
        subprocess.run(['git', 'diff', '--exit-code', '--quiet', commit, '--', *inputs()], cwd=ROOT, check=True)
        stamp.write_text(json.dumps({'runtime': fingerprint(), 'source_commit': commit,
            'logs': {f: digest(old / f) for f in FILES}}, indent=2))
        print('Recorded completed ' + GROUP + ' checks at ' + commit)
    elif mode == 'restore':
        data = json.loads(stamp.read_text())
        assert data['runtime'] == fingerprint(), 'Game or fixture changed; rerun network checks'
        assert all(data['logs'][f] == digest(old / f) for f in FILES), 'Checkpoint logs changed'
        dest = Path(sys.argv[3]).resolve()
        assert dest != old
        for f in (*FILES, GROUP + '-checkpoint.json', 'battlegrounds.png'):
            if (old / f).is_file(): shutil.copyfile(old / f, dest / f)
        print('Reused completed ' + GROUP + ' checks; identical game/fixture inputs, exit 0 and logs revalidated.')
    else:
        raise ValueError('Unknown mode')

if __name__ == '__main__':
    main()
