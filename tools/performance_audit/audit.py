#!/usr/bin/env python3
"""Read-only nightly audit of the exported staging client. No AI calls, pushes or deploys."""
import argparse
import datetime as dt
import fcntl
import hashlib
import json
import math
import os
from pathlib import Path
import plistlib
import re
import shutil
import signal
import statistics
import subprocess
import sys
import time
import zipfile

REPO = 'jjcw1337-rgb/ashen-crown'
LOCK = Path('/Users/blaine/dev/game-factory-agents/lock.py')
OWNER = 'codex-nightly-audit'
LEGACY = Path('/tmp/ashen-nightly.lock')
ROOT = Path('/Users/blaine/Library/Application Support/ashen-performance-audit')
SCENARIOS = ['camp:2', 'moor:1', 'moor:2', 'moor:3', 'fight:2', 'boss:2', 'arena:2', 'crypt:2', 'pvp3v3:2', 'pvp_dragons:2', 'pvp_forest:2', 'server:2']
METRICS = ['fps_avg', 'frame_ms_p99', 'frame_ms_max', 'first_use_max_ms', 'hitches_per_min', 'load_ms', 'ram_mb', 'vram_mb']
CONTRACTS = ['content_cache_test', 'content_contract_test', 'content_catalog_test', 'content_parts_test',
             'nightly_surface_material_test', 'coop_fx_test', 'content_host_test', 'sandbox_test', 'sandbox_entry_test', 'pvp_sim']
MARKERS = {
    'isolation': '[AUDIT] isolated user directory verified',
    'pvp_sim': '[PVP] done,',
    'sandbox_test': '[SB] done, 0 failed', 'sandbox_entry_test': '[SANDBOX ENTRY] done, 0 failed',
    'content_cache_test': '[CACHE TEST]', 'content_contract_test': '[CONTENT CONTRACT]',
    'content_catalog_test': '[CATALOG]', 'content_parts_test': '[PARTS]',
    'nightly_surface_material_test': '[SURFACE]', 'coop_fx_test': '[X] done, 0 failed',
    'content_host_test': '[HOST CONTENT] ok teardown has no owned or pending resources',
}
ANSI = re.compile(r'\x1b\[[0-9;]*m')

class Deferred(Exception): pass


def command(argv, cwd=None):
    return subprocess.check_output([str(x) for x in argv], cwd=cwd, text=True, stderr=subprocess.PIPE, timeout=120)


def engines():
    rows = command(['ps', '-Ao', 'pid=,comm=']).splitlines()
    return {int(a): b for a, b in (row.strip().split(None, 1) for row in rows if len(row.strip().split(None, 1)) == 2)
            if 'godot' in Path(b).name.lower() or Path(b).name == 'Ashen Crown'}


def errors(text):
    text = ANSI.sub('', text)
    return [line for line in text.splitlines() if re.search(r'SCRIPT ERROR|Parse Error|Compile Error|ERROR:|WARNING:|\bFAIL\b|crashed', line)]


def eligible(now, previous):
    # launchd retries every 15 minutes, but only this one-hour evening window is eligible.
    minute = now.hour * 60 + now.minute
    return 22*60+30 <= minute < 23*60+30 and not (
        previous.get('date') == now.date().isoformat() and previous.get('state') not in ['deferred', 'running'])


def evaluate(groups):
    problems, summary = [], {}
    for key in SCENARIOS:
        runs = groups.get(key, [])
        if len(runs) != 3:
            problems.append(f'{key}: expected three complete repeats, got {len(runs)}')
            continue
        for i, row in enumerate(runs):
            prefix = f'{key} repeat {i+1}'
            if not row.get('valid'): problems.append(prefix + ': invalid run')
            m = row.get('metrics', {})
            if key != 'server:2' and m.get('focused') is not True: problems.append(prefix + ': window unfocused')
            if any(not isinstance(m.get(k), (float, int)) or not math.isfinite(m[k]) for k in METRICS):
                problems.append(prefix + ': missing/nonfinite metrics')
                continue
            if m.get('gameplay_sync_misses') != {}: problems.append(prefix + ': cache misses or missing cache instrumentation')
            if key.startswith('pvp'):
                p = m.get('pvp', {})
                if p.get('actors') != 6 or p.get('teams') != [3, 3] or p.get('bursts', 0) < 3 or p.get('presentation_events', 0) < 1:
                    problems.append(prefix + ': incomplete six-actor spell flood')
                expected = {'pvp3v3:2': ['demon','plague','archer']*2,
                            'pvp_dragons:2': ['wyrm','serpent','wyvern']*2,
                            'pvp_forest:2': ['warlock','wraith','plague']*2}[key]
                if p.get('classes') != expected or p.get('profile') != key.split(':')[0]:
                    problems.append(prefix + ': wrong/missing PvP roster or profile')
                zone = {'pvp3v3:2': 'arena', 'pvp_dragons:2': 'sandbox', 'pvp_forest:2': 'bg'}[key]
                if m.get('environment') != zone: problems.append(prefix + ': wrong/missing environment')
        if all(all(isinstance(r.get('metrics', {}).get(k), (float, int)) and math.isfinite(r['metrics'][k]) for k in METRICS) for r in runs):
            summary[key] = {k: {'median': statistics.median(r['metrics'][k] for r in runs),
                                'worst': (min if k == 'fps_avg' else max)(r['metrics'][k] for r in runs)} for k in METRICS}
    return problems, summary


def balance_issues(data):
    issues = []
    for cls in ['demon', 'plague', 'archer']:
        for gear in ['fresh', 'geared']:
            key = f'{cls}:20:{gear}'
            row = data.get(key, {})
            if row.get('cls') != cls or row.get('lvl') != 20 or row.get('gear') != gear or any(
                isinstance(row.get(k), bool) or not isinstance(row.get(k), (int, float)) or
                not math.isfinite(row[k]) or row[k] <= 0 for k in ['dps', 'ehp', 'life']):
                issues.append('PvP simulator missing/invalid moving-target result: '+key)
    return issues


def compare(summary, baseline):
    findings = []
    for key, metrics in summary.items():
        if key not in baseline: continue
        for metric, values in metrics.items():
            for statistic in ['median', 'worst']:
                before, after = baseline[key][metric][statistic], values[statistic]
                bad = after < before * .9 if metric == 'fps_avg' else after > before * 1.2 + (1 if metric == 'hitches_per_min' else 2)
                if bad: findings.append(f'{key} {metric} {statistic}: {before:.1f} -> {after:.1f}')
    return findings


def budget_issues(summary):
    result = []
    for key, metrics in summary.items():
        if key == 'server:2': continue
        caps = {'first_use_max_ms': 50, 'load_ms': 5000}
        if key in ['fight:2', 'boss:2'] or key.startswith('pvp'): caps.update(frame_ms_p99=33, frame_ms_max=80)
        for metric, cap in caps.items():
            if metrics[metric]['worst'] > cap: result.append(f'{key} {metric}: {metrics[metric]["worst"]:.1f} > {cap}')
    return result


def extract_mac(archive, destination):
    with zipfile.ZipFile(archive) as z:
        chosen = [i for i in z.infolist() if '.app/' in i.filename and ('/Contents/' in i.filename)]
        if not chosen: raise RuntimeError('Mac application missing from artifact')
        if sum(i.file_size for i in chosen) > 6 * 1024**3: raise RuntimeError('Unexpected Mac artifact expansion')
        for info in chosen:
            path = Path(info.filename)
            if path.is_absolute() or '..' in path.parts or ((info.external_attr >> 16) & 0o170000) == 0o120000:
                raise RuntimeError('Unsafe archive path or symlink')
            target = destination / path
            if info.is_dir(): target.mkdir(parents=True, exist_ok=True); continue
            target.parent.mkdir(parents=True, exist_ok=True)
            with z.open(info) as src, target.open('wb') as dst: shutil.copyfileobj(src, dst)
    apps = list(destination.rglob('*.app'))
    if len(apps) != 1: raise RuntimeError('Expected one Mac application')
    app = apps[0]
    data = plistlib.loads((app/'Contents/Info.plist').read_bytes())
    executable = app/'Contents/MacOS'/data['CFBundleExecutable']
    if not executable.resolve().is_relative_to(app.resolve()): raise RuntimeError('Unsafe bundle executable')
    executable.chmod(0o755)
    packs = list((app/'Contents/Resources').glob('*.pck'))
    if len(packs) != 1: raise RuntimeError('Expected one pack')
    return executable, packs[0]


class Audit:
    def __init__(self, root, repo):
        self.root, self.repo = root, repo
        self.start = time.monotonic()
        self.current = None
        self.claimed = False
        self.last_memory_check = 0
        self.report = {'date': dt.date.today().isoformat(), 'state': 'running', 'checks': {}, 'runs': {}, 'issues': []}
        self.out = root/'runs'/dt.datetime.now().strftime('%Y%m%d-%H%M%S')
        self.out.mkdir(parents=True, exist_ok=True)

    def save(self):
        self.report['updated'] = dt.datetime.now().astimezone().isoformat()
        self.report['output'] = str(self.out)
        for target in [self.out/'report.json', self.root/'latest.json']:
            temp = target.with_suffix('.tmp')
            temp.write_text(json.dumps(self.report, indent=2)+'\n'); temp.replace(target)
        lines = [f"Nightly performance audit — {self.report['date']}", f"State: {self.report['state']}",
                 f"Revision: {self.report.get('revision', 'not selected')}", f"Evidence: {self.out}", '']
        lines += self.report['issues'] or (['Complete valid audit: no regression or budget finding.'] if self.report['state'] == 'passed' else ['No finding recorded yet. A running/deferred report is not a pass.'])
        if self.report.get('baseline_note'): lines += ['', self.report['baseline_note']]
        if self.report.get('summary'):
            lines += ['', '| Scenario | Median FPS | Worst p99 ms | First-use max ms | Load max ms | VRAM max MB |', '|---|---:|---:|---:|---:|---:|']
            for key, metrics in self.report['summary'].items():
                values = [metrics[m][stat] for m, stat in [('fps_avg','median'),('frame_ms_p99','worst'),('first_use_max_ms','worst'),('load_ms','worst'),('vram_mb','worst')]]
                lines.append('| '+key+' | '+' | '.join(f'{v:.1f}' for v in values)+' |')
        (self.root/'latest.md').write_text('\n'.join(lines)+'\n')

    def safe(self, own=0):
        if not own or time.monotonic()-self.last_memory_check > 10:
            pressure = command(['memory_pressure', '-Q'])
            match = re.search(r'memory free percentage: (\d+)%', pressure)
            if not match: raise Deferred('Could not verify memory headroom')
            free = int(match.group(1))
            self.report['minimum_memory_free_percent'] = min(free, self.report.get('minimum_memory_free_percent', 100))
            if free < (5 if own else 15): raise Deferred('Insufficient memory headroom')
            self.last_memory_check = time.monotonic()
        if LEGACY.exists(): raise Deferred('Existing nightly job is active')
        if set(engines()) - {own}: raise Deferred('Another Godot/game process is active')
        if shutil.disk_usage(self.root).free < 6*1024**3: raise Deferred('Less than 6 GiB free disk; stopped own workload')
        if time.monotonic()-self.start > 75*60: raise Deferred('75-minute audit deadline reached')

    def stop(self):
        if self.current is not None:
            try: os.killpg(self.current.pid, signal.SIGTERM)
            except ProcessLookupError: pass
            try: self.current.wait(timeout=8)
            except subprocess.TimeoutExpired:
                try: os.killpg(self.current.pid, signal.SIGKILL)
                except ProcessLookupError: pass
                self.current.wait()
            self.current = None

    def run(self, name, argv, timeout=300):
        self.safe()
        started = time.monotonic()
        path = self.out/(name+'.log')
        with path.open('w') as log:
            self.current = subprocess.Popen([str(x) for x in argv], stdout=log, stderr=subprocess.STDOUT,
                                            cwd=self.out, start_new_session=True)
            try:
                while self.current.poll() is None:
                    self.safe(self.current.pid)
                    if time.monotonic()-started > timeout: raise RuntimeError(name + ' timed out')
                    time.sleep(1)
                code = self.current.returncode
            finally: self.stop()
        text = path.read_text(errors='replace')
        bad = errors(text)
        if MARKERS.get(name, '[KPI]') not in text: bad.append('Missing completion marker')
        row = {'exit': code, 'valid': code == 0 and not bad, 'error_or_warning_count': len(bad), 'log': str(path),
               'seconds': round(time.monotonic()-started, 2)}
        self.report['checks'][name] = row
        self.save()
        return row

    def execute(self):
        claims = json.loads(command([sys.executable, LOCK, 'status']))
        if 'heavy-tests' in claims: raise Deferred('heavy-tests owned by '+claims['heavy-tests']['owner'])
        self.safe()
        if shutil.disk_usage(self.root).free < 16*1024**3: raise Deferred('Need 16 GiB free before artifact download and GPU tests')
        result = subprocess.run([sys.executable, str(LOCK), 'acquire', 'heavy-tests', '--owner', OWNER,
                                 '--note', f'Published-build audit {self.out.name}'], capture_output=True)
        if result.returncode: raise Deferred('heavy-tests claim unavailable')
        self.claimed = True
        command(['git', 'fetch', 'origin', 'staging'], self.repo)
        sha = command(['git', 'rev-parse', 'origin/staging'], self.repo).strip()
        self.report['revision'] = sha
        for name in CONTRACTS:
            try: command(['git', 'cat-file', '-e', sha+':tools/'+name+'.gd'], self.repo)
            except subprocess.CalledProcessError: raise Deferred('Staging does not yet include required contract: '+name)
        kpi = command(['git', 'show', sha+':scripts/kpi.gd'], self.repo)
        if any('"'+name+'"' not in kpi for name in ['pvp3v3', 'pvp_dragons', 'pvp_forest']):
            raise Deferred('Staging does not yet include all required PvP stress profiles')
        inventory = {}
        paths = command(['git', 'ls-tree', '-r', '--name-only', sha, 'scripts'], self.repo).splitlines()
        for path in paths:
            if not path.endswith('.gd'): continue
            content = command(['git', 'show', sha+':'+path], self.repo)
            counts = {label: len(re.findall(pattern, content)) for label, pattern in {
                'load_sites': r'(?<![\w.])load\(', 'preload_sites': r'\bpreload\(',
                'shader_new_sites': r'\bShader\.new\(', 'resource_fallback_sites': r'ResCache\.get_res\('
            }.items()}
            if any(counts.values()): inventory[path] = counts
        self.report['static_inventory'] = inventory
        self.report['inventory_note'] = 'Lexical sites, not proven hot-path calls or defects'
        last_inventory = self.root/'last-inventory.json'
        previous = json.loads(last_inventory.read_text()) if last_inventory.exists() else {}
        self.report['inventory_changes'] = {path: {'before': previous.get(path), 'after': inventory.get(path)}
            for path in sorted(set(previous) | set(inventory)) if previous.get(path) != inventory.get(path)}
        last_inventory.write_text(json.dumps(inventory, indent=2)+'\n')

        runs = json.loads(command(['gh', 'api', f'repos/{REPO}/actions/workflows/staging.yml/runs?branch=staging&per_page=10']))['workflow_runs']
        matches = [r for r in runs if r['head_sha'] == sha and r['conclusion'] == 'success']
        if not matches: raise Deferred('Latest staging revision has no successful published build yet')
        run_id = matches[0]['id']; self.report['ci_run'] = run_id
        artifacts = json.loads(command(['gh', 'api', f'repos/{REPO}/actions/runs/{run_id}/artifacts']))['artifacts']
        artifact = next((a for a in artifacts if a['name'] == 'AshenCrown-staging' and not a['expired']), None)
        if artifact is None: raise Deferred('Published staging artifact unavailable')
        # Cache is exclusively this runner's. Preserve raw reports, replace only its downloaded application.
        cache = self.root/'artifact'
        if cache.exists(): shutil.rmtree(cache)
        cache.mkdir()
        archive = cache/'staging.zip'
        with archive.open('wb') as output:
            p = subprocess.Popen(['gh', 'api', f'repos/{REPO}/actions/artifacts/{artifact["id"]}/zip'], stdout=output, stderr=subprocess.DEVNULL, start_new_session=True)
            self.current = p
            try:
                limit = time.monotonic()+900
                while p.poll() is None:
                    self.safe()
                    if time.monotonic()>limit: raise RuntimeError('Artifact download timed out')
                    time.sleep(1)
                if p.returncode: raise RuntimeError('Artifact download failed')
            finally: self.stop()
        with archive.open('rb') as src:
            digest = hashlib.sha256()
            for block in iter(lambda: src.read(1024*1024), b''): digest.update(block)
        self.report['artifact_sha256'] = digest.hexdigest()
        expected = artifact.get('digest')
        if expected and expected != 'sha256:'+digest.hexdigest(): raise RuntimeError('Artifact checksum mismatch')
        executable, pack = extract_mac(archive, cache/'mac')
        archive.unlink()
        user_dir = 'AshenCrown-NightlyAudit-'+self.out.name
        (pack.parent/'override.cfg').write_text('[application]\nconfig/use_custom_user_dir=true\nconfig/custom_user_dir_name="'+user_dir+'"\n[display]\nwindow/size/mode=0\nwindow/size/window_width_override=1600\nwindow/size/window_height_override=900\nwindow/vsync/vsync_mode=0\n')
        bootstrap = Path(__file__).with_name('bootstrap.gd')
        base = [executable, '-ApplePersistenceIgnoreState', 'YES', '--main-pack', pack, '-s', bootstrap]
        self.report['engine'] = command([executable, '--version']).strip()
        if not self.run('isolation', base+['--headless', '--', '--audit-mode', 'isolation'])['valid']:
            raise RuntimeError('User-data isolation failed')
        for test in CONTRACTS:
            args = [] if test in ['content_host_test', 'sandbox_test', 'sandbox_entry_test', 'pvp_sim'] else ['--headless']
            extra = []
            if test == 'pvp_sim':
                extra = ['classes=demon,plague,archer', 'levels=20', 'moving', 'out='+str(self.out/'pvp-balance.json')]
            if test in ['sandbox_test', 'sandbox_entry_test', 'pvp_sim']: args += ['--fixed-fps', '60']
            row = self.run(test, base+args+['--', '--audit-mode', test]+extra, timeout=900)
            if not row['valid']: self.report['issues'].append(test+': errors, warnings or failed assertions; inspect private log')
            if test == 'pvp_sim':
                target = self.out/'pvp-balance.json'
                data = json.loads(target.read_text()) if target.exists() else {}
                self.report['issues'] += balance_issues(data)
                self.report['balance'] = data
                for line in (self.out/(test+'.log')).read_text(errors='replace').splitlines():
                    if '[PVP-FLAG]' in line: self.report['issues'].append(line.strip())
        for scenario in SCENARIOS:
            name, quality = scenario.split(':')
            self.report['runs'][scenario] = []
            for repeat in range(1, 4):
                label = f'{name}-q{quality}-r{repeat}'
                target = self.out/(label+'.json')
                args = ['--headless'] if name == 'server' else []
                extra = ['--server', '--port', '24891'] if name == 'server' else []
                row = self.run(label, base+args+['--', '--audit-mode', 'kpi', '--kpi', name, target, '--quality', quality]+extra)
                row['metrics'] = json.loads(target.read_text()) if target.exists() else {}
                self.report['runs'][scenario].append(row)
        issues, summary = evaluate(self.report['runs'])
        self.report['issues'].extend(issues)
        self.report['summary'] = summary
        self.report['budget_findings'] = budget_issues(summary)
        identity = {'engine': self.report['engine'], 'gpu': self.report['runs'].get('camp:2', [{}])[0].get('metrics', {}).get('gpu_name'), 'resolution': self.report['runs'].get('camp:2', [{}])[0].get('metrics', {}).get('resolution'), 'policy': 2, 'maps': {key: rows[0].get('metrics', {}).get('map_title') for key, rows in self.report['runs'].items() if rows}}
        fingerprint = hashlib.sha256(json.dumps(identity, sort_keys=True).encode()).hexdigest()[:16]
        baseline_file = self.root/('baseline-'+fingerprint+'.json')
        self.report['comparison_identity'] = identity
        self.report['regressions'] = []
        if not self.report['issues']:
            if baseline_file.exists():
                previous = json.loads(baseline_file.read_text())
                self.report['regressions'] = compare(summary, previous['summary'])
                self.report['baseline_revision'] = previous['revision']
            else:
                baseline_file.write_text(json.dumps({'revision': sha, 'summary': summary, 'identity': identity}, indent=2)+'\n')
                self.report['baseline_revision'] = sha
                self.report['baseline_note'] = 'First valid measurement; no improvement claim'
        self.report['issues'] += self.report['budget_findings'] + self.report['regressions']
        self.report['state'] = 'findings' if self.report['issues'] else 'passed'


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--repo', type=Path, required=True)
    parser.add_argument('--root', type=Path, default=ROOT)
    parser.add_argument('--scheduled', action='store_true')
    parser.add_argument('--preflight', action='store_true')
    args = parser.parse_args()
    os.umask(0o077)
    args.root.mkdir(parents=True, exist_ok=True)
    with (args.root/'runner.lock').open('w') as mutex:
        try: fcntl.flock(mutex, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError: return 0
        latest = args.root/'latest.json'
        previous = json.loads(latest.read_text()) if latest.exists() else {}
        if args.scheduled and not eligible(dt.datetime.now(), previous): return 0
        audit = Audit(args.root, args.repo)
        audit.save()
        def interrupted(signum, _frame): raise Deferred('Audit interrupted by signal '+str(signum))
        for sig in [signal.SIGTERM, signal.SIGINT, signal.SIGHUP]: signal.signal(sig, interrupted)
        try:
            if args.preflight:
                claims = json.loads(command([sys.executable, LOCK, 'status']))
                audit.safe()
                if 'heavy-tests' in claims: raise Deferred('heavy-tests owned by '+claims['heavy-tests']['owner'])
                audit.report['state'] = 'preflight_only'
                audit.report['issues'].append('No game workloads executed; this is not a performance pass')
            else: audit.execute()
        except Deferred as exc:
            audit.report['state'] = 'deferred'; audit.report['issues'].append(str(exc))
        except Exception as exc:
            audit.report['state'] = 'failed'; audit.report['issues'].append(type(exc).__name__+': '+str(exc) if not isinstance(exc, subprocess.CalledProcessError) else 'External command failed; no command output included')
        finally:
            audit.stop()
            if audit.claimed:
                subprocess.run([sys.executable, str(LOCK), 'release', 'heavy-tests', '--owner', OWNER], stdout=subprocess.DEVNULL, check=True)
            audit.save()
        print(json.dumps({'state': audit.report['state'], 'report': str(args.root/'latest.md')}))
        return 0 if audit.report['state'] in ['passed', 'preflight_only', 'deferred'] else 1

if __name__ == '__main__':
    raise SystemExit(main())
