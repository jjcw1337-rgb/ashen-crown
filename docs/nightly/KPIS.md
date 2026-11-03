# Performance KPIs (the official numbers)

How fast and how big Ashen Crown is, measured the same way every time so the numbers can be compared night to night.
The nightly runner measures them around every job (`tools/nightly/bench.sh`), a job that makes them worse doesn't
ship, and they're kept in Grafana.

- **Dashboard**: https://161.35.185.195/grafana/ (user `admin`, password on the Game Factory Mac in
  `~/.config/ashen-grafana/admin_password`). The home dashboard is "Ashen Crown: performance KPIs".
- **From a script**: `sh tools/kpi_query.sh latest` (every scenario's latest numbers) or
  `sh tools/kpi_query.sh "SELECT ... FROM kpi ..."`.
- **From Claude**: the `grafana` MCP (read-only), registered for every Claude session on the Mac.

## Scenarios

Each is a scripted scene (`scripts/kpi.gd`, `SCENARIOS`), deterministic (fixed seeds, paths and spawns), the hero
immortal. Each loads its zone (timed), settles 4 s (shaders compile, monsters wake), then is measured for its
seconds, every frame. Run one yourself, in any build:
`AshenCrown -- --kpi <scenario> out.json [--quality 0-3] [--secs N]` (writes out.json and out.png, then quits).

| Scenario | Where | What happens | Seconds |
|---|---|---|---|
| `camp` | Act I camp | The hero walks a 7 m loop past the tents, the bonfire and the traders | 15 |
| `moor` | Act I moor | The hero runs up the road at 7 m/s: grass, oaks, the world streaming in | 20 |
| `fight` | Act I moor | The knight fights 24 monsters at once with his attack and every skill; kills are replaced | 20 |
| `boss` | Grubb's fort | The King Grubb fight: the knight on him with skills | 25 |
| `arena` | A2 Aurelia | The arena games running (lions, the crowd), the knight on the sand | 25 |
| `crypt` | Battlegrounds | The Hollow Crypt: walking a loop through the rooms, fighting what's there | 20 |
| `server` | Battlegrounds server | The headless dedicated server running the crypt (`-- --server --kpi server out.json`) | 30 |
| `download` | (export) | The macOS export: the .zip players download and the .pck inside | |

The nightly benchmark runs every scenario at **High** (preset 2), the moor also at Medium and Ultra, each twice
(the better run kept), on the Game Factory Mac (Apple M6, a 1600x900 window).

## Metrics and targets

| Metric | What it is, exactly | Target |
|---|---|---|
| `fps_avg` | Frames rendered / wall-clock seconds over the measured window | **≥ 60** (floor 30) |
| `fps_low1` | 1000 / the mean of the slowest 1% of frame times: how bad the dips get | **≥ 45** |
| `frame_ms_median` | Median frame time (ms) | ≤ 16.7 |
| `frame_ms_p99` | 99th-percentile frame time (ms) | ≤ 25 |
| `hitches_per_min` | Frames of 100 ms or longer (a visible stutter), per minute | **0** |
| `load_ms` | Entering the zone: `Game.load_zone` start to ready (for `server`: engine start to the crypt being up) | **≤ 3000** |
| `cpu_process_peak_ms` | Godot's `TIME_PROCESS`: the slowest frame's main-thread process time in each second, averaged | ≤ 16 |
| `cpu_physics_peak_ms` | The same for the physics step | ≤ 4 |
| `script_ms` | Every node's `_process` in a frame (average), timed between two probe nodes processed first and last (`scripts/kpi_probe.gd`). `cpu_process_peak_ms` includes drawing and the wait for the GPU, so this is the scripts' real cost | ≤ 8 |
| `physics_ms`, `render_cpu_ms` | The same for `_physics_process`; the renderer's CPU time (viewport render + frame setup) | |
| `gpu_ms` | GPU time per frame (`viewport_get_measured_render_time_gpu`); far below the frame time = the CPU is the limit | ≤ 12 |
| `draw_calls` | Draw calls per frame (average) | ≤ 2000 |
| `primitives` | Triangles drawn per frame, all passes (average) | ≤ 10 M |
| `objects` | Objects drawn per frame (average) | |
| `vram_mb` | Video memory in use at the end | ≤ 1500 |
| `ram_mb` | Static (script and engine) memory at the end | ≤ 500 |
| `nodes`, `enemies` | Scene nodes and monsters alive at the end (context for the rest) | |
| `mac_zip_mb`, `pck_mb` | The macOS download and its .pck (scenario `download`) | **≤ 200** |
| server `frame_ms_p99`, `hitches_per_min` | The dedicated server's tick: p99 tick time and ticks of 100 ms+ | ≤ 50, 0 |

Targets are where we want a mid-range PC to be; the Mac is the yardstick that stays the same.

## Where the numbers go

- `tools/nightly/bench.sh <dir> <label>` runs the suite into `<dir>/<label>.json`.
- `tools/nightly/kpi_push.py` puts it in the KPI store: PostgreSQL database `kpi` on the staging server, table `kpi`
  (`deploy/staging/kpi_schema.sql`): one row per number with `ts`, `night`, `job` (perf / mode / manual), `phase`
  (before = staging as it stood when a job started, after = the job's result), `commit`, `source` (runner, later
  player), `machine`, `scenario`, `preset`, `metric`, `value`.
- `tools/nightly/bench_compare.py` writes the night's `bench` row in the job's log, appends to
  `docs/nightly/perf/metrics.jsonl`, and blocks the ship if the average fps fell more than 7% (one scenario 15%), or
  the perf job grew the download more than 3%.
- Grafana (`deploy/staging/docker-compose.yml`, provisioned from `deploy/staging/grafana/`) reads it through the
  read-only role `grafana_ro`. The dashboard is generated: edit `tools/kpi_dashboard.py`, then
  `python3 tools/kpi_dashboard.py deploy/staging/grafana/dashboards/kpis.json` and `sh deploy/staging/deploy.sh --backend`.
- Setup (once, done 2026-11-01): `sh deploy/staging/kpi_setup.sh` (passwords made on the server, the database, the role).

## Skills

Every new or redone skill is measured before it ships: `bash tools/skill_perf.sh <class> <skill id>` runs the
`fight` scenario twice in a real window (High, 1600x900): the class using only its weapon, then casting only that
skill every 1.2 s (`--kpi fight --class C --skill id --trace`), and compares them. **PASS**: no new stutters (frames
of 100 ms or more) and the average frame at most **20%** slower than the weapon alone. `--trace` puts every frame's
time and each cast's frame in the JSON, so a stutter can be lined up with what caused it (e.g. "1.1 s after each
cast" = where the arrow lands).

Found this way (2026-11-01): Fire Arrow made 14 stutters a minute in the fight, each about 1 s after the cast,
where the arrow lands: every shot lit new shadow-casting lights, and a new omni light with shadows renders the
scene round it into a cube map (6 passes). Fix with nothing taken from the look: effect lights' shadows go through
`Fx.effect_shadow` (dual-paraboloid maps, 2 passes, and at most `Fx.EFFECT_SHADOWS` = 2 at once across every effect
and every player). After: 0 stutters, +13.5% frame time (PASS).

Rules for skill effects (CLAUDE.md "Skill design"): a light that casts shadows uses `Fx.effect_shadow`; effects that
repeat share meshes, materials and textures (made once, cached) instead of building new ones each cast; a partner's
copy (the puppet) draws the same effect, so four players casting is four times the cost: keep `skill_perf` well inside
its budget.

## Finding what costs (profiling flags, any scenario)

`--census` (writes `<out>.census.txt`: every visible mesh by triangles x instances, shadow casting, visibility range;
every light; every SubViewport), `--hide name,a,b` / `--hide Props#10-40` (hide parts to see what they cost),
`--noshadow omni,dir`, `--envoff ssao,ssil,vfog,msaa,glow,half,softmed,softlow,atlas2k,terrainflat,terrainnofd,plainomni`,
`--mmnoshadow N`, `--mmchunk N` (0 = MultiMesh chunking off), `--notwins` (no oak shadow twins), and for the spot
scenario `--pos oakN`. Comparing looks: run both sides with `--fixed-fps 30` (time-driven scenes come out the same
frame) and compare against two identical runs, not against zero (particles, AI and the crowd differ every run).

## Adding a scenario or a metric

A scenario: an entry in `Kpi.SCENARIOS`, its staging in `Kpi._stage` and driving in `Kpi._drive`, then add it to the
list in `tools/nightly/bench.sh` (and `NAMES` in `bench_compare.py` to gate on it). A metric: add it to the dictionary
in `Kpi._finish`; it's stored and shown in the table panel automatically (a graph needs a panel in
`tools/kpi_dashboard.py`).

## Next (not built yet)

- **Players' numbers**: the staging builds sending a small sample every minute of real play (fps, 1% low, hitches,
  zone, preset, GPU) through Nakama into the same table (`source` = player), so we see real Windows PCs in real fights.
- Bots on the dedicated server (several fake players fighting), so `server` measures it under load.
