-- The KPI store (docs/systems/performance_kpis.md). One row per measured number: long format, so a new metric or scenario needs
-- no schema change. Written by tools/nightly/kpi_push.py (the nightly runner's benchmark, source 'runner'; later
-- players' builds, source 'player'), read by Grafana (role grafana_ro) and tools/kpi_query.sh.
CREATE TABLE IF NOT EXISTS kpi (
  id bigserial PRIMARY KEY,
  ts timestamptz NOT NULL DEFAULT now(),   -- when it was measured
  night date,                              -- the nightly run's date (NULL outside the nightly)
  job text,                                -- perf / mode / manual
  phase text,                              -- before (= staging as it stood) / after (= the night's result)
  commit text,                             -- the commit measured
  source text NOT NULL DEFAULT 'runner',   -- runner / player / manual
  machine text,                            -- the GPU (e.g. "Apple M6")
  scenario text NOT NULL,                  -- camp, moor, fight, boss, arena, crypt, server, download
  preset int,                              -- graphics preset 0-3 (Low..Ultra)
  metric text NOT NULL,                    -- fps_avg, fps_low1, frame_ms_p99, hitches_per_min, ...
  value double precision NOT NULL
);
CREATE INDEX IF NOT EXISTS kpi_lookup ON kpi (scenario, metric, ts);
GRANT SELECT ON kpi TO grafana_ro;
