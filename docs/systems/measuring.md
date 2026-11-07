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
| fps, load time and memory per scenario | `-- --kpi <scenario> out.json` (`game/systems/telemetry/kpi.gd`) | camp, fight, boss, crypt, spot, server |
| What does a server cost? | `tools/load_bot.gd` against a server, then `ps`/`/proc` on the host | RAM, CPU per mode, with players fighting |

All frame tools need a display. Run tools that use `Sfx` through `tools/_late.gd`
(`godot --path . -s tools/_late.gd -- res://tools/<tool>.gd args`). In zsh, split argument strings with `${=args}`.

## Budgets (Mac mini, High)

- No first-occurrence frame over **50 ms**; a big fight's p99 at or under **33 ms**, worst at or under **80 ms**.
- A zone loads in **3 s or less** warm and **5 s or less** cold; no single loading-screen frame over **250 ms**.
- Servers: the per-mode cost in `deploy/lobbies/service.py` `COST`, re-measured with bots after server changes.
