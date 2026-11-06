#!/usr/bin/env python3
"""Bounded Arena/Sandbox acceptance: isolated local broker, two clients and one worker.
Caller owns the heavy-tests claim and configures an isolated Godot user directory.
No live endpoints, imports, deployments or changes to another process.
"""
import argparse
import json
import os
from pathlib import Path
import re
import shutil
import signal
import socket
import subprocess
import sys
import time

from check_functional_log import inspect
from run_kpi import other_engines


def in_group(pid, group):
    try:
        return os.getpgid(pid) == group
    except ProcessLookupError:
        return False


def run(args):
    root = Path.cwd()
    out = Path(args.output).resolve()
    out.mkdir(parents=True, exist_ok=False)
    processes, handles = [], []
    result = {'mode': args.mode, 'passed': False}

    def start(name, command):
        handle = (out / (name + '.log')).open('w')
        handles.append(handle)
        process = subprocess.Popen(command, stdout=handle, stderr=subprocess.STDOUT,
                                   cwd=root, start_new_session=True)
        processes.append(process)
        return process

    try:
        if Path('/tmp/ashen-nightly.lock').exists():
            raise RuntimeError('Legacy nightly owns the test window')
        if other_engines(args.godot):
            raise RuntimeError('Another Godot is active; keep the shared test window exclusive')
        if shutil.disk_usage(root).free < 8 * 2**30:
            raise RuntimeError('Need 8 GiB free before this bounded network run')
        for port, kind in [(args.broker_port, socket.SOCK_STREAM), (args.worker_port, socket.SOCK_DGRAM)]:
            with socket.socket(socket.AF_INET, kind) as sock:
                sock.bind(('127.0.0.1', port))
        broker = start('broker', [sys.executable, 'deploy/lobbies/service.py', '--dev',
            '--state', str(out / 'state'), '--game', str(root), '--godot', args.godot,
            '--port', str(args.broker_port), '--first-port', str(args.worker_port),
            '--ports', '1', '--slots', '1'])
        for _ in range(40):
            with socket.socket() as sock:
                if sock.connect_ex(('127.0.0.1', args.broker_port)) == 0:
                    break
            if broker.poll() is not None:
                raise RuntimeError('Local broker exited before listening')
            time.sleep(.25)
        else:
            raise RuntimeError('Local broker did not become ready')
        url = 'http://127.0.0.1:%d' % args.broker_port
        roles = ('a', 'b') if args.mode == 'arena' else ('host', 'guest')
        fixture = 'arena_survivor_test' if args.mode == 'arena' else 'sandbox_lobby_test'
        clients = []
        for index, role in enumerate(roles):
            command = [args.godot]
            if index or not args.rendered:
                command.append('--headless')
            command += ['--path', str(root), '-s', 'tools/_late.gd', '--', role,
                        'res://tools/%s.gd' % fixture,
                        '--broker' if args.mode == 'arena' else '--broker-url', url]
            if args.mode == 'sandbox':
                command += ['--run-id', out.name]
            if index == 0 and args.rendered:
                command += ['--capture', str(out / (args.mode + '.png'))]
            clients.append(start(role, command))
        deadline = time.monotonic() + args.timeout
        minimum_free = shutil.disk_usage(root).free / 2**30
        while any(p.poll() is None for p in clients):
            if Path('/tmp/ashen-nightly.lock').exists():
                raise RuntimeError('Legacy nightly acquired the test window; stopped own group')
            competing = []
            for pid in other_engines(args.godot):
                try:
                    if os.getpgid(pid) not in {p.pid for p in processes}:
                        competing.append(pid)
                except ProcessLookupError:
                    pass
            if competing:
                raise RuntimeError('Another Godot entered the test window; stopped own group')
            minimum_free = min(minimum_free, shutil.disk_usage(root).free / 2**30)
            if minimum_free < 6:
                raise RuntimeError('Stopped own processes at 6 GiB disk reserve')
            if time.monotonic() >= deadline:
                raise RuntimeError('Network acceptance deadline exceeded')
            if broker.poll() is not None:
                raise RuntimeError('Local broker exited during acceptance')
            time.sleep(1)
        result.update(exit_codes=[p.returncode for p in clients], minimum_free_gib=minimum_free)
        # Retain proof that the match worker naturally exited after both players left.
        workers_done = False
        for _ in range(30):
            with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as sock:
                try:
                    sock.bind(('127.0.0.1', args.worker_port))
                    if not any(in_group(pid, broker.pid) for pid in other_engines(args.godot)):
                        workers_done = True
                        break
                except OSError:
                    pass
            time.sleep(1)
        result['worker_exited_and_port_released'] = workers_done
    except Exception as exc:
        result['failure'] = str(exc)
    finally:
        # Broker workers inherit its process group. Never signal by executable name or shared port.
        for process in processes:
            try:
                os.killpg(process.pid, signal.SIGTERM)
            except ProcessLookupError:
                pass
        for process in processes:
            try:
                process.wait(timeout=10)
            except subprocess.TimeoutExpired:
                os.killpg(process.pid, signal.SIGKILL)
                process.wait()
        for handle in handles:
            handle.close()
        result['logs'] = {}
        for path in sorted(out.rglob('*.log')):
            known, errors, warnings = inspect(path.read_text(errors='replace'))
            result['logs'][str(path.relative_to(out))] = dict(known=known, errors=errors, warnings=warnings)
        completed = True
        for role in (('a', 'b') if args.mode == 'arena' else ('host', 'guest')):
            path = out / (role + '.log')
            completed &= path.exists() and bool(re.search(r'done \d+ checks / 0 failures', path.read_text(errors='replace')))
        result['passed'] = (not result.get('failure') and result.get('exit_codes') == [0, 0]
                            and result.get('worker_exited_and_port_released') and completed
                            and not any(log['errors'] for log in result['logs'].values()))
        (out / 'result.json').write_text(json.dumps(result, indent=2))
        print(json.dumps(result, indent=2))
    return 0 if result['passed'] else 1


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('mode', choices=['arena', 'sandbox'])
    parser.add_argument('output')
    parser.add_argument('--godot', required=True)
    parser.add_argument('--broker-port', type=int, default=7354)
    parser.add_argument('--worker-port', type=int, default=24640)
    parser.add_argument('--timeout', type=int, default=600)
    parser.add_argument('--rendered', action='store_true')
    def interrupted(_signum, _frame):
        raise InterruptedError('Network gate interrupted; cleaning up own process groups')
    signal.signal(signal.SIGTERM, interrupted)
    raise SystemExit(run(parser.parse_args()))
