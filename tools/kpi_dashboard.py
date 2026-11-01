"""Writes the Grafana dashboard of the performance KPIs: python3 tools/kpi_dashboard.py deploy/staging/grafana/dashboards/kpis.json
(edit the panels here, not in the JSON; docs/nightly/KPIS.md lists the metrics)."""
import json, sys
DS = {"type": "grafana-postgresql-datasource", "uid": "kpi-pg"}
W = "source = '$source' AND $__timeFilter(ts)"
panels, y = [], 0
pid = [0]
def nid():
    pid[0] += 1
    return pid[0]
def q(sql, fmt="time_series"):
    return [{"refId": "A", "datasource": DS, "rawQuery": True, "editorMode": "code", "format": fmt, "rawSql": sql}]
def stat(title, metric, x, w, desc, steps, unit="none", dec=0):
    sql = ("SELECT DISTINCT ON (scenario) ts AS time, scenario AS metric, value FROM kpi WHERE metric = '%s' "
           "AND preset = $preset AND scenario <> 'server' AND source = '$source' ORDER BY scenario, ts DESC" % metric)
    return {"id": nid(), "type": "stat", "title": title, "description": desc, "datasource": DS, "gridPos": {"x": x, "y": y, "w": w, "h": 5},
            "targets": q(sql), "options": {"reduceOptions": {"calcs": ["lastNotNull"], "values": False}, "colorMode": "background",
            "graphMode": "none", "textMode": "value_and_name", "justifyMode": "center", "orientation": "horizontal"},
            "fieldConfig": {"defaults": {"unit": unit, "decimals": dec, "thresholds": {"mode": "absolute", "steps": steps}}, "overrides": []}}
def ts(title, sql, x, w, desc, unit="none", lower_better=False, h=8):
    return {"id": nid(), "type": "timeseries", "title": title, "description": desc + (" Lower is better." if lower_better else " Higher is better."),
            "datasource": DS, "gridPos": {"x": x, "y": y, "w": w, "h": h}, "targets": q(sql),
            "fieldConfig": {"defaults": {"unit": unit, "custom": {"drawStyle": "line", "lineWidth": 2, "showPoints": "always", "pointSize": 5,
                            "spanNulls": True}}, "overrides": []},
            "options": {"legend": {"displayMode": "table", "placement": "right", "calcs": ["lastNotNull", "min", "max"]}, "tooltip": {"mode": "multi"}}}
def series(metric, scale="value", where="scenario <> 'server' AND preset = $preset"):
    return ("SELECT ts AS time, scenario AS metric, %s AS value FROM kpi WHERE metric = '%s' AND %s AND %s ORDER BY ts" % (scale, metric, where, W))
fpsteps = [{"color": "red", "value": None}, {"color": "orange", "value": 30}, {"color": "green", "value": 60}]
panels.append({"id": nid(), "type": "text", "title": "", "gridPos": {"x": 0, "y": y, "w": 24, "h": 3}, "options": {"mode": "markdown", "content":
    "**Ashen Crown performance KPIs.** Fixed scripted scenarios (`scripts/kpi.gd`) measured on the Game Factory Mac (Apple M6, 1600x900 window) "
    "around every nightly job; definitions and targets: `docs/nightly/KPIS.md`. Targets: **60 fps average, 45 fps 1% low, 0 hitches, under 3 s loads, "
    "a download under 200 MB.** `phase` before = staging as it stood when a job started; after = that job's result."}})
y += 3
panels.append(stat("Average fps now", "fps_avg", 0, 12, "The latest average frames per second of each scenario. Target 60.", fpsteps))
panels.append(stat("1% low fps now", "fps_low1", 12, 12, "The average fps of the slowest 1% of frames: how bad the dips get. Target 45.",
                   [{"color": "red", "value": None}, {"color": "orange", "value": 25}, {"color": "green", "value": 45}]))
y += 5
panels.append(ts("Average fps", series("fps_avg"), 0, 12, "Frames per second over the scenario's measured seconds."))
panels.append(ts("1% low fps", series("fps_low1"), 12, 12, "fps of the slowest 1% of frames (stutter and dips)."))
y += 8
panels.append(ts("Frame time p99 (ms)", series("frame_ms_p99"), 0, 8, "99th percentile frame time.", "ms", True))
panels.append(ts("Hitches per minute", series("hitches_per_min"), 8, 8, "Frames of 100 ms or more (a visible stutter), per minute.", "none", True))
panels.append(ts("Load time (ms)", series("load_ms"), 16, 8, "Entering the scenario's zone: from load_zone to ready.", "ms", True))
y += 8
panels.append(ts("Triangles per frame (millions)", series("primitives", "value / 1e6"), 0, 8, "Primitives drawn per frame (incl. shadow passes).", "none", True))
panels.append(ts("Draw calls per frame", series("draw_calls"), 8, 8, "Draw calls per frame.", "none", True))
panels.append(ts("GPU time (ms)", series("gpu_ms"), 16, 8, "GPU time per frame. When it's well under the frame time, the CPU (main thread) is the limit.", "ms", True))
y += 8
panels.append(ts("Main thread, peak (ms)", series("cpu_process_peak_ms"), 0, 8, "The slowest frame's _process time in each second (Godot's TIME_PROCESS), averaged.", "ms", True))
panels.append(ts("Video memory (MB)", series("vram_mb"), 8, 8, "GPU memory in use at the end of the scenario.", "none", True))
panels.append(ts("RAM (MB)", series("ram_mb"), 16, 8, "Static memory in use at the end of the scenario.", "none", True))
y += 8
panels.append(ts("Dedicated server: tick time (ms)", "SELECT ts AS time, metric, value FROM kpi WHERE scenario = 'server' AND metric IN ('frame_ms_median', 'frame_ms_p99', 'cpu_process_peak_ms') AND " + W + " ORDER BY ts",
                 0, 12, "The headless Battlegrounds server running the crypt: its tick (frame) time median and p99, and the slowest tick's process time.", "ms", True))
panels.append(ts("Download size (MB)", "SELECT ts AS time, metric, value FROM kpi WHERE scenario = 'download' AND " + W + " ORDER BY ts",
                 12, 12, "The macOS export: the .zip players download, and the .pck inside it.", "none", True))
y += 8
panels.append({"id": nid(), "type": "table", "title": "Every KPI, latest value", "datasource": DS, "gridPos": {"x": 0, "y": y, "w": 24, "h": 14},
               "targets": q("SELECT DISTINCT ON (scenario, preset, metric) scenario, preset, metric, value, ts AS measured, commit, phase FROM kpi "
                            "WHERE source = '$source' ORDER BY scenario, preset, metric, ts DESC", "table"),
               "fieldConfig": {"defaults": {}, "overrides": []}, "options": {"showHeader": True}})
dash = {"uid": "ashen-kpis", "title": "Ashen Crown: performance KPIs", "tags": ["ashen-crown", "kpi"], "timezone": "America/New_York",
        "schemaVersion": 39, "version": 1, "refresh": "", "time": {"from": "now-30d", "to": "now"}, "panels": panels,
        "templating": {"list": [
            {"name": "preset", "label": "Graphics preset", "type": "custom", "query": "0,1,2,3", "current": {"text": "2", "value": "2"},
             "options": [{"text": str(i), "value": str(i), "selected": i == 2} for i in range(4)]},
            {"name": "source", "label": "Source", "type": "custom", "query": "runner,player,manual", "current": {"text": "runner", "value": "runner"},
             "options": [{"text": s, "value": s, "selected": s == "runner"} for s in ("runner", "player", "manual")]}]}}
json.dump(dash, open(sys.argv[1], "w"), indent=1)
