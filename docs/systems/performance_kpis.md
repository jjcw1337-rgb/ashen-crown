# Performance KPIs (the official numbers)

How fast and how big Ashen Crown is, measured the same way every time so a change can be compared before and after.
Run them on demand (the nightly runner, its KPI database and dashboard were removed on 2026-11-06): the same scenario
three times on each side, on the same machine, nothing else running.

## Scenarios

Each is a scripted scene (`game/systems/telemetry/kpi.gd`, `SCENARIOS`), deterministic (fixed seeds, paths and spawns), the hero
immortal. Each loads its zone (timed), settles 4 s (shaders compile, monsters wake), then is measured for its
seconds, every frame. Run one yourself, in any build:
`AshenCrown -- --kpi <scenario> out.json [--quality 0-3] [--secs N]` (writes out.json and out.png, then quits).

| Scenario | Where | What happens | Seconds |
|---|---|---|---|
| `camp` | Act I camp | The hero walks a 7 m loop past the tents, the bonfire and the traders | 15 |
| `fight` | The Arena's hall | The knight fights 24 monsters at once with his attack and every skill; kills are replaced | 20 |
| `boss` | The Arena's hall | The King Grubb fight: the knight on him with skills | 25 |
| `crypt` | Battlegrounds | The Verdant Reach (the id is older): walking a loop, fighting what's there | 20 |
| `server` | Battlegrounds server | The headless dedicated server running the raid (`-- --server --kpi server out.json`) | 30 |
| `spot` | any zone | The hero standing at `--pos x,z` in `--zone` (default `bg`), turning, `--foes N` monsters about | 15 |
| `download` | (export) | The macOS export: the .zip players download and the .pck inside | |

Compare at **High** (preset 2) on the Game Factory Mac (Apple M6) unless the change is about another preset.

## Metrics and targets

| Metric | What it is, exactly | Target |
|---|---|---|
| `fps_avg` | Frames rendered / wall-clock seconds over the measured window | **≥ 60** (floor 30) |
| `fps_low1` | 1000 / the mean of the slowest 1% of frame times: how bad the dips get | **≥ 45** |
| `frame_ms_median` | Median frame time (ms) | ≤ 16.7 |
| `frame_ms_p99` | 99th-percentile frame time (ms) | ≤ 25 |
| `hitches_per_min` | Frames of 100 ms or longer (a visible stutter), per minute | **0** |
| `load_ms` | Entering the zone: `Game.load_zone` start to ready (for `server`: engine start to the raid being up) | **≤ 3000** |
| `cpu_process_peak_ms` | Godot's `TIME_PROCESS`: the slowest frame's main-thread process time in each second, averaged | ≤ 16 |
| `cpu_physics_peak_ms` | The same for the physics step | ≤ 4 |
| `script_ms` | Every node's `_process` in a frame (average), timed between two probe nodes processed first and last (`game/systems/telemetry/kpi_probe.gd`). `cpu_process_peak_ms` includes drawing and the wait for the GPU, so this is the scripts' real cost | ≤ 8 |
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

Each run writes its JSON (`out.json`, every metric above) and a screenshot. Put the before/after numbers in the commit
message; nothing stores them centrally.

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

Rules for skill effects: a light that casts shadows uses `Fx.effect_shadow`; effects that
repeat share meshes, materials and textures (made once, cached) instead of building new ones each cast; a partner's
copy (the puppet) draws the same effect, so four players casting is four times the cost: keep `skill_perf` well inside
its budget.

## Finding what costs (profiling flags, any scenario)

`--census` (writes `<out>.census.txt`: every visible mesh by triangles x instances, shadow casting, visibility range;
every light; every SubViewport), `--hide name,a,b` / `--hide Props#10-40` (hide parts to see what they cost),
`--noshadow omni,dir`, `--envoff ssao,ssil,vfog,msaa,glow,half,softmed,softlow,atlas2k,terrainflat,terrainnofd,plainomni`,
`--mmnoshadow N`, `--mmchunk N` (0 = MultiMesh chunking off), `--notwins` (no oak shadow twins), `--nocast a,b`
(geometry whose name contains a or b casts no shadow; `all-mm` = everything not instanced) with `--castlist` (the
visible meshes and instanced casters by triangles), `--grassshadow lod0|lod1|near|lod1near` (Ultra's grass shadow
twins), `--envoff` also `sdfgi,ssr,msaa4,grassnopatch,grassflatfrag,grassdegen,grasslod<m>`, and for the spot
scenario `--pos oakN`. **Check the switch took**: an `--envoff` can be undone by a later `apply_quality` (11-03:
`sdfgi` didn't stick in `--fixed-fps` runs); if gpu_ms didn't move, the screenshots compare nothing. Comparing looks: run both sides with `--fixed-fps 30` (time-driven scenes come out the same
frame) and compare against two identical runs, not against zero (particles, AI and the crowd differ every run).

## Adding a scenario or a metric

A scenario: an entry in `Kpi.SCENARIOS`, its staging in `Kpi._stage` and driving in `Kpi._drive`, . A metric: add it to the dictionary
in `Kpi._finish`.

## Next (not built yet)

- **Players' numbers**: the staging builds sending a small sample every minute of real play (fps, 1% low, hitches,
  zone, preset, GPU) through Nakama into the same table (`source` = player), so we see real Windows PCs in real fights.
- Bots on the dedicated server (several fake players fighting), so `server` measures it under load.
