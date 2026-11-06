# Measuring

**Rule:** don't call something fixed without a number from the same tool, preset and run count, before and after.
Frame-time comparisons need a quiet machine (nothing else running: check the `heavy-tests` claim) and **3 runs**, with the median and the spread reported: the big fight's worst frame varied 56-117 ms between
identical runs.

| Question | Tool | Notes |
|---|---|---|
| What freezes the first time it happens? | `tools/app_hitch_audit.gd -- [--monsters-only] [--all-monsters]` | windows, loot, zone changes, spawns; first and second time |
| How does a big fight run? | `tools/stress_fight.gd -- [hero] [partners] [secs] [foes] [--q N] [--nowarm] [--fx-timing]` | worst frames with what was cast, CPU/GPU split |
| What does each skill effect cost? | `tools/fx_bench.gd -- [classes] [rounds]` | after warming |
| Title, camp, first casts | `tools/hitch_probe.gd -- title\|camp\|skills <cls>` | |
| Which call was slow? | run with `--fx-timing` | prints skill/effect calls over 6 ms |
| FPS and six-actor PvP floods | `scripts/kpi.gd`, `tools/nightly/bench.sh` | camp, moor, fight, boss, arena, Battlegrounds, PvP, server |
| Has the published build regressed? | [manual audit tools](../perf/NIGHTLY_AUDIT.md) | Three repeats, lifecycle checks and a retained report; scheduled jobs removed |
| What does a server cost? | `tools/load_bot.gd` against a server, then `ps`/`/proc` on the host | RAM, CPU per mode, with players fighting |

All frame tools need a display. Run tools that use `Sfx` through `tools/_late.gd`
(`godot --path . -s tools/_late.gd -- res://tools/<tool>.gd args`). In zsh, split argument strings with `${=args}`.

## Budgets (Mac mini, High)

- No first-occurrence frame over **50 ms**; a big fight's p99 at or under **33 ms**, worst at or under **80 ms**.
- A zone loads in **3 s or less** warm and **5 s or less** cold; no single loading-screen frame over **250 ms**.
- Servers: the per-mode cost in `deploy/lobbies/service.py` `COST`, re-measured with bots after server changes.

## Shared acceptance rules

The schema2 KPI clock is monotonic wall time, independent of combat hitstop. Preserve the first-use window,
p99, maximum frame, hitches/minute, loading time and memory as well as average FPS. Keep all three raw repeats:
`bench_compare.py` checks both medians and worst repeats, requires complete scenario/context coverage, and
rejects synchronous gameplay cache misses. Never promote a baseline just because average FPS improves.

`--kpi pvp3v3` floods six Demon/Plague/Archer presentation actors; `pvp_dragons` adds moving dragon effects,
and `pvp_forest` exercises summoners/status effects in the current Battlegrounds map. These exceed legal cooldown concurrency.
Actual six-client team/round correctness is a separate test, not implied by that replay. The complete suite,
not a single successful scene, is required for performance acceptance. See [results and limits](../perf/IMPLEMENTATION_RESULTS.md).

The functional gate checks exit codes and runtime logs as well as assertions. Native rendering and actual
network tests cover different behavior; a passing spell replay alone does not verify a multiplayer match.
Keep engine-specific failures and incomplete runs visible; detailed history belongs in the
[staging results](../perf/STAGING_RESULTS.md), not an expanding error allowlist.

On the shared Mac, claim `heavy-tests` and respect the legacy nightly lock. Use isolated saves and separate
ports (`GATE_BG_PORT`, `GATE_PVP_PORT`, `GATE_COOP_PORT`, `GATE_QUEUE_PORT`, `GATE_LAN_PORT`). Tools that instantiate
the main scene set `current_scene`, matching a normal launch. See [coverage](../perf/COVERAGE.md) for what is
implemented, verified and still pending. The nightly report can be deferred; that is not a performance pass.
