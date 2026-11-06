"""Pushes a KPI benchmark (tools/nightly/bench.sh's <label>.json) into the KPI store on the staging server (the
`kpi` table, docs/systems/performance_kpis.md), which Grafana draws.
    python kpi_push.py <bench.json> <night> <job> <phase> <commit> [source] [--dry]
One row per number (long format). Goes through ssh to the postgres container (no database port is open).
"""
import json
import subprocess
import sys

args = [a for a in sys.argv[1:] if a != "--dry"]
path, night, job, phase, commit = args[:5]
source = args[5] if len(args) > 5 else "runner"
SKIP = {"scenario", "preset", "gpu_name", "resolution", "frames", "secs"}


def lit(v):
    if v is None or v == "":
        return "NULL"
    if isinstance(v, (int, float)):
        return repr(float(v))
    return "'" + str(v).replace("'", "''") + "'"


rows = []
for key, r in json.load(open(path)).items():
    for m, v in r.items():
        if m in SKIP or not isinstance(v, (int, float)) or isinstance(v, bool):
            continue
        rows.append("(%s)" % ", ".join(lit(x) for x in (night or None, job, phase, commit, source, r.get("gpu_name"),
                                                         r.get("scenario", key.split("_q")[0]), r.get("preset"), m, v)))
if not rows:
    sys.exit("nothing to push")
sql = ("INSERT INTO kpi (night, job, phase, commit, source, machine, scenario, preset, metric, value) VALUES\n"
       + ",\n".join(rows) + ";\n")
if "--dry" in sys.argv:
    print(sql)
    sys.exit(0)
p = subprocess.run(["ssh", "ashen-crown-staging", "sudo docker exec -i ashen-staging-postgres-1 psql -q -v ON_ERROR_STOP=1 -U nakama -d kpi"],
                   input=sql.encode(), capture_output=True, timeout=120)
if p.returncode != 0:
    sys.exit("push failed: " + p.stderr.decode()[-500:])
print("pushed %d KPI values" % len(rows))
