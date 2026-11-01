"""The telemetry watcher (docs/nightly/TELEMETRY.md, "Alerts and hotfix runs"): launchd runs it every 5 minutes on the
Game Factory Mac (tools/nightly/install.sh). It reads the staging telemetry (over ssh, like tools/telemetry_query.sh):
  - ALERTS, posted to the Discord channel at once: any crash, an error never seen before, an error spike (SPIKE events
    in an hour), a place where players ran under SLOW_FPS for SLOW_SAMPLES minutes;
  - HOTFIX RUNS: when an alert is serious (a crash; a new error that hit 2+ players or 10+ times; a slow spot) and that
    issue was never investigated, it starts a focused triage run on it (tools/nightly/run.sh hotfix) instead of
    waiting for the 05:00 triage. At most one run every MIN_GAP_H hours and MAX_RUNS_DAY a day; never while a nightly
    job holds the lock (it tries again next time). Anything else waits for the 05:00 sweep.
State (what was alerted and investigated, the runs today) is in ~/Library/Application Support/ashen-nightly/watch.json.
    python3 watch.py [--dry]      (--dry: prints what it would post and start)
"""
import json
import os
import subprocess
import sys
import calendar
import time
import urllib.request

STATE_DIR = os.path.expanduser("~/Library/Application Support/ashen-nightly")
STATE = os.path.join(STATE_DIR, "watch.json")
RUNNER = os.path.expanduser("~/dev/ashen-crown-nightly-runner/run.sh")
LOCK = "/tmp/ashen-nightly.lock"
ENV = os.path.expanduser("~/.claude/channels/discord/.env")
CHANNEL = "1564444926765178890"
SPIKE = 50              # events of one issue in an hour
SLOW_FPS = 30.0
SLOW_SAMPLES = 5        # minutes of play (one sample a minute) in one 20 m square, in the last hour
MIN_GAP_H = 2.0
MAX_RUNS_DAY = 3
DRY = "--dry" in sys.argv


def sql(q):
    """Rows of a query on the telemetry tables, as lists of strings."""
    p = subprocess.run(["ssh", "-o", "ConnectTimeout=15", "ashen-crown-staging",
                        "sudo docker exec -i ashen-staging-postgres-1 psql -q -t -A -F '\x1f' -U nakama -d nakama"],
                       input=q.encode(), capture_output=True, timeout=60)
    if p.returncode != 0:
        raise SystemExit("query failed: " + p.stderr.decode()[-300:])
    return [line.split("\x1f") for line in p.stdout.decode().splitlines() if line.strip()]


def token():
    with open(ENV) as f:
        for line in f:
            if line.startswith("DISCORD_BOT_TOKEN="):
                return line.split("=", 1)[1].strip().strip('"')
    raise SystemExit("no DISCORD_BOT_TOKEN")


def post(text):
    if DRY:
        print("POST:", text)
        return
    body = json.dumps({"content": text[:1990], "allowed_mentions": {"parse": []}}).encode()
    req = urllib.request.Request("https://discord.com/api/v10/channels/%s/messages" % CHANNEL, data=body,
                                 headers={"Authorization": "Bot " + token(), "Content-Type": "application/json",
                                          "User-Agent": "AshenCrownWatch (github.com/jjcw1337-rgb/ashen-crown, 1.0)"})
    urllib.request.urlopen(req, timeout=30).read()


def load():
    try:
        return json.load(open(STATE))
    except Exception:
        return {"since": time.strftime("%Y-%m-%d %H:%M:%S+00", time.gmtime(time.time() - 600)), "alerted": {}, "investigated": {}, "runs": []}


st = load()
since = st["since"]
now_s = time.strftime("%Y-%m-%d %H:%M:%S+00", time.gmtime())
real = "build <> 'dev' AND coalesce(env, '') <> 'local'"      # (a developer's own runs aren't players)
alerts, serious = [], []

for fp, kind, src, msg, at, players, events, zone in sql(
        "SELECT fingerprint, kind, source, left(min(message), 160), left(min(at), 80), count(DISTINCT user_id), sum(count), "
        "string_agg(DISTINCT zone, ' ') FROM tm_error WHERE ts > '%s' AND %s GROUP BY fingerprint, kind, source" % (since, real)):
    first = sql("SELECT min(ts) > '%s' FROM tm_error WHERE fingerprint = '%s'" % (since, fp))[0][0] == "t"
    players, events = int(players), int(float(events))
    key = "fp:" + fp
    if kind == "crash":
        alerts.append("💥 **Crash** (%s, %s): %s" % (src, zone or "?", msg))
        serious.append({"key": key, "what": "crash %s: %s" % (fp, msg)})
    elif first and key not in st["alerted"]:
        alerts.append("🐞 **New error** (%s, %s, %d players, %d times): `%s` at `%s`" % (src, zone or "?", players, events, msg, at))
        st["alerted"][key] = now_s
        if players >= 2 or events >= 10:
            serious.append({"key": key, "what": "error %s: %s at %s" % (fp, msg, at)})

for fp, msg, n in sql("SELECT fingerprint, left(min(message), 120), sum(count) FROM tm_error WHERE ts > now() - interval '1 hour' "
                      "AND %s GROUP BY fingerprint HAVING sum(count) >= %d" % (real, SPIKE)):
    key = "spike:%s:%s" % (fp, now_s[:13])
    if key not in st["alerted"]:
        alerts.append("📈 **Error spike**: %s times in the last hour: `%s`" % (n, msg))
        st["alerted"][key] = now_s

for zone, run, x, z, preset, n, fps, low, players in sql(
        "SELECT zone, run, round(x / 20) * 20, round(z / 20) * 20, preset, count(*), round(avg(fps_avg)::numeric, 1), "
        "round(avg(fps_low1)::numeric, 1), count(DISTINCT user_id) FROM tm_sample WHERE ts > now() - interval '1 hour' AND %s "
        "GROUP BY 1, 2, 3, 4, 5 HAVING count(*) >= %d AND avg(fps_avg) < %s" % (real, SLOW_SAMPLES, SLOW_FPS)):
    key = "spot:%s:%s:%s:%s:%s" % (zone, run, x, z, preset)
    if st["alerted"].get(key, "")[:10] != now_s[:10]:      # (once a day per place)
        alerts.append("🐢 **Slow spot**: %s (act run %s) at %s,%s on preset %s: %s fps (1%% low %s) over %s minutes, %s player(s)"
                      % (zone, run, x, z, preset, fps, low, n, players))
        st["alerted"][key] = now_s
        serious.append({"key": key, "what": "slow spot: zone %s, run %s, x %s, z %s, preset %s: %s fps over %s samples"
                        % (zone, run, x, z, preset, fps, n)})

if alerts:
    post("🚨 **Telemetry alert** (staging)\n" + "\n".join(alerts[:12]) + "\nDashboard: https://161.35.185.195/grafana/d/ashen-telemetry")

# a hotfix run for the worst new serious issue, within the caps
day = now_s[:10]
st["runs"] = [r for r in st["runs"] if r[:10] == day]
todo = [s for s in serious if s["key"] not in st["investigated"]]
last = max((calendar.timegm(time.strptime(r[:19], "%Y-%m-%d %H:%M:%S")) for r in st["runs"]), default=0)
gap_ok = time.time() - last >= MIN_GAP_H * 3600
busy = os.path.isdir(LOCK)
if todo and len(st["runs"]) < MAX_RUNS_DAY and gap_ok and not busy:
    focus = todo[0]
    with open(os.path.join(STATE_DIR, "hotfix_focus.json"), "w") as f:
        json.dump(focus, f)
    if DRY:
        print("START hotfix:", focus)
    else:
        subprocess.Popen(["/bin/bash", RUNNER, "hotfix"], start_new_session=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        post("🛠️ Starting a hotfix run on it now: %s (run %d of %d today). The report follows when it's done." % (focus["what"][:300], len(st["runs"]) + 1, MAX_RUNS_DAY))
    st["investigated"][focus["key"]] = now_s
    st["runs"].append(now_s)
elif todo:
    print("serious issues waiting:", len(todo), "(cap reached, too soon, or a job running)")

st["since"] = now_s
if not DRY:
    with open(STATE, "w") as f:
        json.dump(st, f, indent=1)
print("checked since", since, ":", len(alerts), "alert(s),", len(todo), "waiting")
