#!/usr/bin/env python3
"""What a dedicated server costs (Blaine's capacity audit, 2026-11-05): starts one headless server from this checkout,
samples its memory and CPU, and adds bot players (tools/load_bot.gd: they join, walk and fight) in steps.

  python3 tools/server_cost.py coop|bg [--steps 0,1,4] [--phase 30] [--port 24681] [--godot PATH] [-- server args]

Prints one JSON line per step ({"players", "rss_mb", "cpu_pct_of_one_core"}) and a RESULT line. On macOS the RSS is
only indicative (memory compression); the CPU is comparable night to night. The droplet's real numbers (and the
costs service.py COST uses) come from the same bots against a server there: docs/patterns/servers.md."""
import argparse, json, os, re, subprocess, sys, time
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ap = argparse.ArgumentParser()
ap.add_argument("mode", choices=["coop", "bg"])
ap.add_argument("--steps", default="0,1,4")
ap.add_argument("--phase", type=float, default=30)
ap.add_argument("--port", type=int, default=24681)
ap.add_argument("--godot", default=os.environ.get("GODOT", "/Users/blaine/Applications/Godot_v4.4.1.app/Contents/MacOS/Godot"))
ap.add_argument("extra", nargs="*")
a = ap.parse_args()
def sample(pid):
    o = subprocess.run(["ps", "-o", "rss=,time=", "-p", str(pid)], capture_output=True, text=True).stdout.split()
    if len(o) < 2: return None, None
    p = [float(x) for x in o[1].split(":")]
    return int(o[0]) / 1024.0, p[-1] + (p[-2] * 60 if len(p) > 1 else 0) + (p[-3] * 3600 if len(p) > 2 else 0)
args = [a.godot, "--headless", "--path", ROOT, "--", "--server", "--port", str(a.port)] + (["--coop"] if a.mode == "coop" else []) + a.extra
srv = subprocess.Popen(args, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
res = {"mode": a.mode, "phases": []}
t0 = time.time(); prev = None
while time.time() - t0 < 60:
    time.sleep(1); r, _ = sample(srv.pid)
    if r is None: break
    if prev is not None and time.time() - t0 > 8 and abs(r - prev) < 5: break
    prev = r
res["startup_s"] = round(time.time() - t0, 1)
bots = []
steps = [int(x) for x in a.steps.split(",")]
for n in steps:
    while len(bots) < n:
        i = len(bots)
        ba = [a.godot, "--headless", "--path", ROOT, "-s", "tools/load_bot.gd", "--", a.mode, str(a.port), str(int(a.phase * (len(steps) + 1))), "n", str(i)] + (["lead"] if i == 0 else [])
        bots.append(subprocess.Popen(ba, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL))
    time.sleep(25 if n else 5)
    r0, c0 = sample(srv.pid); ts = time.time(); rs = []
    while time.time() - ts < a.phase:
        time.sleep(2); r, _ = sample(srv.pid)
        if r is None: break
        rs.append(r)
    r1, c1 = sample(srv.pid)
    if r1 is None or not rs:
        res["phases"].append({"players": n, "error": "server exited"}); break
    res["phases"].append({"players": n, "rss_mb": round(sum(rs) / len(rs)), "cpu_pct_of_one_core": round(100 * (c1 - c0) / (time.time() - ts), 1)})
    print(json.dumps(res["phases"][-1]), flush=True)
for b in bots: b.terminate()
srv.terminate()
try: srv.wait(5)
except Exception: srv.kill()
print("RESULT", json.dumps(res))
