# Measuring

**Rule:** don't call something fixed without a number from the same tool, preset and run count, before and after.
Frame-time comparisons need a quiet machine (nothing else running; no measurements while `/tmp/ashen-nightly.lock`
exists) and **3 runs**, with the median and the spread reported: the big fight's worst frame varied 56-117 ms between
identical runs.

| Question | Tool | Notes |
|---|---|---|
| What freezes the first time it happens? | `tools/app_hitch_audit.gd -- [--monsters-only] [--all-monsters]` | windows, loot, zone changes, spawns; first and second time |
| How does a big fight run? | `tools/stress_fight.gd -- [hero] [partners] [secs] [foes] [--q N] [--nowarm] [--fx-timing]` | worst frames with what was cast, CPU/GPU split |
| What does each skill effect cost? | `tools/fx_bench.gd -- [classes] [rounds]` | after warming |
| Title, camp, first casts | `tools/hitch_probe.gd -- title\|camp\|skills <cls>` | |
| Which call was slow? | run with `--fx-timing` | prints skill/effect calls over 6 ms |
| fps per scenario, every night | `scripts/kpi.gd`, `tools/nightly/bench.sh` | camp, moor, fight, boss, arena, crypt, server |
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

`--kpi pvp3v3` floods six Demon/Plague/Archer presentation actors; this exceeds legal cooldown concurrency.
Actual six-client team/round correctness is a separate test, not implied by that replay. The complete suite,
not a single successful scene, is required for performance acceptance. See [results and limits](../perf/IMPLEMENTATION_RESULTS.md).

The functional gate runs tools after autoload initialization and rejects nonzero exits and script/compile/runtime
errors. Its known Godot4.3 dummy null-mesh defect is explicitly counted, never called an error-free render pass.
Use `GATE_BG_PORT`, `GATE_PVP_PORT`, `GATE_COOP_PORT`, `GATE_QUEUE_PORT` and `GATE_LAN_PORT` for separate local test ports;
never collide with another agent's servers. A functional gate is separate from the rendered performance budgets.
On macOS the gate defaults to native rendering for title/character/Archer checks (`GATE_UI_RENDERED=1`).
Other platforms default headless; the flag can explicitly select native rendering on a display machine. The historical Godot4.3
headless title/character shutdown emits a PagedAllocator error on the pre-change baseline too; it is retained
as a defect, not added to the error allowlist. Those historical rendered title/character/Archer checks were clean; engine upgrades require rerunning them. Archer also reproduces the shutdown error headless
on the candidate despite explicit scene teardown; its baseline has not been rerun. Tools which instantiate the
main scene must set `current_scene` explicitly, matching a normal game launch.
