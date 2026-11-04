# Game-mode job: attempts and results

The short log every nightly game-mode run reads first and adds to (`tools/nightly/mode_prompt.md`). One row per mode
or map built (or attempted), newest last. **Result**: playable / not, with the tests. **Verdict**: Blaine's and JJ's
call after playing (keep / iterate / cut, filed from Discord by the Game Factory session; empty until they've played).
**Next**: what the next run should build on or change. **Details**: the mode's folder (README, feedback, screenshots).
Rows with Mode `bench` are the runner's benchmark of the night's result (a mode mustn't slow the game down).

## Lessons (rewritten by each run: at most 8 bullets, the most useful first)

- No player feedback yet on either mode (2026-11-01 Last Flame, 2026-11-02 Gauntlet): read `feedback.md` of every row
  once the Verdict column fills, and build on what they liked before starting anything new.
- Put new modes on the two ports players can reach: UDP 24567 (the Crypt) and 24570 (online co-op). A zone on the
  co-op server is the cheapest: a `World.build` case, `Game.zone_title`/`indoor`/`_zone_env` lines, an Inter that
  `travel`s (ready check free), a node with host state + `Net` events (`vigil.gd`, `gauntlet.gd` are templates).
- The game already has strong bosses with their own brains and intro cards (trex, Sloths, `BgBoss` Hrimgar and
  Mossbeard): `game.spawn_enemy` them and they fight anywhere. A boss outside its act must skip
  `Game.on_enemy_killed`'s act victory (`boss_killed`, portal, victory screen): guard by zone.
- Clients compute an enemy's `max_life` from their own setup; if the host scales it, send the new max in an event
  (`Gauntlet`'s "king" event) or the life bar overflows.
- Balance probes with bots (`vigil_sim.gd`, `gauntlet_sim.gd`) don't dodge, so they read harder than players will
  find it: use them for orders of magnitude. In zsh `$args` doesn't word-split: run multi-arg loops under `bash -c`.
- Don't add lights or fires to the camp, the moor or the fort: they are KPI scenes and a slower bench blocks the ship.
- `-s` test scripts: avoid `is Enemy` / `is GroundItem` (use `"pvp_pid" in e`); after a new `class_name` run
  `godot --headless --editor --quit-after 3000`. Godot is `/Users/blaine/Applications/Godot_v4.3.app/Contents/MacOS/Godot`.
- Screenshots: `tools/vigil_shots.gd` / `tools/gauntlet_shots.gd` (windowed on the Mac, `--resolution 1600x900`) give
  stills and `mode_frame_*.png`; keep a mode's HUD under `ui.boss_bar_box` while a boss bar is up.

## Log

| Date | Mode | Pitch | Result | Verdict | Next | Details |
|---|---|---|---|---|---|---|
| 2026-11-01 | The Last Flame | Co-op horde defence: hold the last fire against ten waves of the dead, on the online co-op server | playable (nightly_vigil_test 38/38, vigil_coop_test server+2 green) | iterate (Blaine, 2026-11-03: make it endless, a wave leaderboard on the title) | Next: play it as two and tune (flame life, counts); a best-wave record; music; maybe endless mode or wave modifiers | [2026-11-01-last-flame](<2026-11-01-last-flame/README.md>) |
| 2026-11-01 | bench | Runner's KPI benchmark of the night's result (avg fps) | camp 13→13, moor Medium 41→41, moor 21→21, moor Ultra 7→7, fight 20→20, boss 42→42, arena 86→84, crypt 104→95; server tick p99 107→111 ms, camp 143M→143M tris, download 371→372 MB | shipped | | `docs/nightly/perf/metrics.jsonl` |
| 2026-11-02 | The Gauntlet of Kings | Co-op boss rush: four kings back to back, shared lives, pick Mercy / Wrath / Greed between fights, beat the hall's record | playable (nightly_gauntlet_test 57/57, gauntlet_coop_test server+2 green) | cut (Blaine, 2026-11-03: "kinda sucked"; deleted from the game) | Next: play it as two and tune (kings' life and damage, lives); more offerings or a weekly king order; the record on the title | [2026-11-02-gauntlet](<2026-11-02-gauntlet/README.md>) |
| 2026-11-02 | bench | Runner's KPI benchmark of the night's result (avg fps) | camp 22→41, moor Medium 46→58, moor 37→38, moor Ultra 11→11, fight 35→35, boss 53→54, arena 96→96, crypt 94→93; server tick p99 100→100 ms, camp 17M→17M tris, download 494→495 MB | shipped | | `docs/nightly/perf/metrics.jsonl` |
