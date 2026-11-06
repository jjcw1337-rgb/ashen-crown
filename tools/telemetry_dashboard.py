"""Writes the Grafana dashboard of the player telemetry, error reports and server logs (docs/systems/telemetry.md):
    python3 tools/telemetry_dashboard.py deploy/staging/grafana/dashboards/telemetry.json
(edit the panels here, not in the JSON)."""
import json
import sys

PG = {"type": "grafana-postgresql-datasource", "uid": "tm-pg"}
LOKI = {"type": "loki", "uid": "loki"}
panels, pid = [], [0]


def nid():
    pid[0] += 1
    return pid[0]


def sql(s, fmt="table"):
    return [{"refId": "A", "datasource": PG, "rawQuery": True, "editorMode": "code", "format": fmt, "rawSql": s}]


def add(p, x, y, w, h):
    p["id"] = nid()
    p["gridPos"] = {"x": x, "y": y, "w": w, "h": h}
    panels.append(p)


def stat(title, s, desc, steps):
    return {"type": "stat", "title": title, "description": desc, "datasource": PG, "targets": sql(s),
            "options": {"reduceOptions": {"calcs": ["lastNotNull"], "values": False}, "colorMode": "background", "graphMode": "none"},
            "fieldConfig": {"defaults": {"thresholds": {"mode": "absolute", "steps": steps}}, "overrides": []}}


def table(title, s, desc):
    return {"type": "table", "title": title, "description": desc, "datasource": PG, "targets": sql(s),
            "options": {"showHeader": True, "cellHeight": "sm"}, "fieldConfig": {"defaults": {}, "overrides": []}}


def series(title, s, desc, unit="none"):
    return {"type": "timeseries", "title": title, "description": desc, "datasource": PG, "targets": sql(s, "time_series"),
            "fieldConfig": {"defaults": {"unit": unit, "custom": {"drawStyle": "line", "lineWidth": 2, "showPoints": "auto", "spanNulls": True}}, "overrides": []},
            "options": {"legend": {"displayMode": "list", "placement": "bottom"}, "tooltip": {"mode": "multi"}}}


def logs(title, expr, desc):
    return {"type": "logs", "title": title, "description": desc, "datasource": LOKI,
            "targets": [{"refId": "A", "datasource": LOKI, "expr": expr, "queryType": "range"}],
            "options": {"showTime": True, "wrapLogMessage": True, "sortOrder": "Descending", "enableLogDetails": True}}


red = [{"color": "green", "value": None}, {"color": "orange", "value": 1}, {"color": "red", "value": 5}]
add({"type": "text", "title": "", "options": {"mode": "markdown", "content":
     "**Players and errors.** What the staging builds send (`scripts/telemetry.gd`: a performance sample a minute of play, "
     "every error and crash with where the player was and what they did), and the servers' logs (Loki). The nightly triage job "
     "(05:00) works from the same data: `tools/telemetry_query.sh issues` / `spots`. Docs: `docs/systems/telemetry.md`."}}, 0, 0, 24, 3)
add(stat("Open issues (in range)", "SELECT count(DISTINCT fingerprint) AS issues FROM tm_error WHERE $__timeFilter(ts)",
         "Distinct errors (fingerprints) seen in the time range.", red), 0, 3, 6, 4)
add(stat("Crashes (in range)", "SELECT count(*) AS crashes FROM tm_error WHERE kind = 'crash' AND $__timeFilter(ts)",
         "Sessions that ended without shutting down.", [{"color": "green", "value": None}, {"color": "red", "value": 1}]), 6, 3, 6, 4)
add(stat("Players (in range)", "SELECT count(DISTINCT user_id) AS players FROM tm_sample WHERE $__timeFilter(ts)",
         "Players who sent performance samples.", [{"color": "blue", "value": None}]), 12, 3, 6, 4)
add(stat("Players' average fps (in range)", "SELECT round(avg(fps_avg)::numeric, 1) AS fps FROM tm_sample WHERE $__timeFilter(ts)",
         "Average fps over every sample.", [{"color": "red", "value": None}, {"color": "orange", "value": 30}, {"color": "green", "value": 60}]), 18, 3, 6, 4)
add(table("Issues, worst first",
          "SELECT kind, source, count(*) AS reports, sum(count) AS events, count(DISTINCT user_id) AS players, max(ts) AS last_seen, "
          "string_agg(DISTINCT build, ' ') AS builds, string_agg(DISTINCT zone, ' ') AS zones, min(message) AS message, min(at) AS at, fingerprint "
          "FROM tm_error WHERE $__timeFilter(ts) GROUP BY fingerprint, kind, source ORDER BY (kind = 'crash') DESC, players DESC, events DESC LIMIT 50",
          "One row per issue (errors grouped by fingerprint): crashes first, then by players hit, then by events."), 0, 7, 24, 10)
add(series("Errors per hour", "SELECT date_trunc('hour', ts) AS time, kind AS metric, sum(count) AS value FROM tm_error WHERE $__timeFilter(ts) GROUP BY 1, 2 ORDER BY 1",
           "Error events per hour, by kind (script, error, crash)."), 0, 17, 12, 8)
add(series("Players' fps by zone", "SELECT date_trunc('hour', ts) AS time, zone AS metric, avg(fps_avg) AS value FROM tm_sample WHERE $__timeFilter(ts) GROUP BY 1, 2 ORDER BY 1",
           "The hourly average of the players' fps, per zone."), 12, 17, 12, 8)
add(table("Slowest spots (20 m squares)",
          "SELECT zone, run, round(x / 20) * 20 AS x, round(z / 20) * 20 AS z, preset, count(*) AS samples, count(DISTINCT user_id) AS players, "
          "round(avg(fps_avg)::numeric, 1) AS fps, round(avg(fps_low1)::numeric, 1) AS low1, sum(hitches) AS hitches, round(avg(enemies)::numeric, 1) AS enemies, "
          "bool_or(boss) AS boss, min(gpu) AS gpu FROM tm_sample WHERE $__timeFilter(ts) GROUP BY 1, 2, 3, 4, 5 ORDER BY fps LIMIT 30",
          "Where players were when it ran worst: the world cut into 20 m squares per zone and preset, slowest first."), 0, 25, 24, 10)
add(table("Latest crashes",
          "SELECT ts, user_id, context->>'zone' AS zone, context->>'class' AS class, context->>'gpu' AS gpu, build, message, right(tail, 300) AS log_end "
          "FROM tm_error WHERE kind = 'crash' AND $__timeFilter(ts) ORDER BY ts DESC LIMIT 20",
          "Each crash with where it happened and the end of its log."), 0, 35, 24, 8)
add(logs("Server errors (Loki)", '{host="staging", level="error"}', "Error lines from the game servers, Nakama, Caddy, Postgres and Grafana."), 0, 43, 24, 10)
add(logs("Game servers' log (Loki)", '{unit=~"ashen-crown-.*"}', "Everything the Battlegrounds and co-op servers print."), 0, 53, 24, 10)
dash = {"uid": "ashen-telemetry", "title": "Ashen Crown: players, errors and logs", "tags": ["ashen-crown", "telemetry"],
        "timezone": "America/New_York", "schemaVersion": 39, "version": 1, "time": {"from": "now-24h", "to": "now"}, "panels": panels}
json.dump(dash, open(sys.argv[1], "w"), indent=1)
