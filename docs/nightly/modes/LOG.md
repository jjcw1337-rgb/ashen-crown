# Game-mode job: attempts and results

The short log every nightly game-mode run reads first and adds to (`tools/nightly/mode_prompt.md`). One row per mode
or map built (or attempted), newest last. **Result**: playable / not, with the tests. **Verdict**: Blaine's and JJ's
call after playing (keep / iterate / cut, filed from Discord by the Game Factory session; empty until they've played).
**Next**: what the next run should build on or change. **Details**: the mode's folder (README, feedback, screenshots).
Rows with Mode `bench` are the runner's benchmark of the night's result (a mode mustn't slow the game down).

## Lessons (rewritten by each run: at most 8 bullets, the most useful first)

- No player feedback yet (first mode night, 2026-11-01): read `feedback.md` of every row once the Verdict column fills.
- Two players can only reach the staging server on UDP 24567 (the Crypt) and 24570 (online co-op): a new server
  process needs a firewall rule and a systemd unit; put new modes on one of those two (a zone on the co-op server, or
  a mode inside `Battlegrounds`) instead.
- A new zone on the co-op server is cheap: a `World.build` case, a `Game.zone_title`/`indoor` line, an Inter that
  `travel`s (the ready check comes free), and a node in the world with host state + `Net` events (`vigil.gd`, `games.gd`).
- Monsters can attack an objective: give it `dead`, `radius`, `take_hit` and set `Enemy.taunt` to it (`Vigil.Flame`);
  monster missiles hit the `"objective"` group (`projectile.gd`).
- Don't add lights or fires to the camp, the moor or the fort: they are KPI scenes and a slower bench blocks the ship.
- `-s` test scripts: avoid `is Enemy` / `is GroundItem` (compiles them before the `Sfx` autoload); use `"pvp_pid" in e`.
  After adding a `class_name`, run `godot --headless --editor --quit-after 3000` (plain `--quit` misses the cache).
- Single-process tests in the gate run solo, which exercises the same host code as co-op; add a server + two players
  test (`tools/vigil_coop_test.gd` is a template) and run it by hand.
- Screenshots: `tools/vigil_shots.gd` (windowed on the Mac, Forward+) gives stills and `mode_frame_*.png` in one go.

## Log

| Date | Mode | Pitch | Result | Verdict | Next | Details |
|---|---|---|---|---|---|---|
| 2026-11-01 | The Last Flame | Co-op horde defence: hold the last fire against ten waves of the dead, on the online co-op server | playable (nightly_vigil_test 38/38, vigil_coop_test server+2 green) | | Next: play it as two and tune (flame life, counts); a best-wave record; music; maybe endless mode or wave modifiers | [2026-11-01-last-flame](<2026-11-01-last-flame/README.md>) |
| 2026-11-01 | bench | Runner's KPI benchmark of the night's result (avg fps) | camp 13→13, moor Medium 41→41, moor 21→21, moor Ultra 7→7, fight 20→20, boss 42→42, arena 86→84, crypt 104→95; server tick p99 107→111 ms, camp 143M→143M tris, download 371→372 MB | shipped | | `docs/nightly/perf/metrics.jsonl` |
