# Player telemetry, errors and logs

What the game and its servers report, where it goes, and how it's used. Built 2026-11-01 on the stack we run:
the game → Nakama → PostgreSQL for game events, Loki for the servers' raw logs, Grafana over both. (The nightly triage job and
the 5-minute alert watcher that acted on it were removed on 2026-11-06, Blaine: read it by hand or through Grafana.)

- **Dashboard**: https://161.35.185.195/grafana/ → "Ashen Crown: players, errors and logs" (login in `KPIS.md`).
- **From a script**: `sh tools/telemetry_query.sh issues` (errors grouped into issues, worst first), `spots` (the
  slowest places players stood), or any SQL on `tm_sample` / `tm_error` / `tm_issue`.
- **From Claude**: the `grafana` MCP (read-only): datasources "Telemetry" (the tables) and "Logs" (Loki).

## Why not Sentry

Sentry's Godot SDK needs Godot 4.5 for its current versions (we're on 4.3; only the old 0.x line supports 4.3),
self-hosted Sentry wants ~16 GB of RAM, and the hosted one is another account and bill. GlitchTip (a lighter
Sentry-compatible server) would be a second stack on a small box. What we need from error tracking (errors grouped
into issues by fingerprint, counted per player and build, with the stack line, the PC, the game state and the player's
last actions, ranked worst first, plus crash detection) is a small amount of code on what we already run. Loki is the
other half: every raw line the servers print, searchable by time and text.

## What the game sends (`scripts/telemetry.gd`, `Telemetry`)

On in cloud builds that aren't production (staging); in production only if `user://settings.cfg` has
`[telemetry] on=true` (a settings toggle is still to come); never in tools, tests, screenshots or KPI runs. The
dedicated servers send their errors too (the runtime http_key). Player ids are Nakama's anonymous device accounts.

| What | When | Fields |
|---|---|---|
| Performance sample (`tm_sample`) | every 60 s of play (not paused, not loading) | fps_avg, fps_low1, frame_p99, hitches (frames ≥ 100 ms), secs; zone, run, x, z, class, level, preset, bg (in a raid), enemies (alive within 25 m), boss (a boss fighting), partners, dead; build, env, os, gpu, res, vram_mb |
| Error (`tm_error`, kind `script`/`error`) | the log is read every 15 s; each new ERROR / SCRIPT ERROR | message, at (the "at:" line: function and file:line), fingerprint, count (in the session), context (build, zone, x, z, class, level, preset, GPU, OS, CPU), crumbs |
| Crash (`tm_error`, kind `crash`) | at the next start, when the last session never shut down | the message (the last error/crash line of that session's log), tail (its last 80 log lines), that session's context and crumbs |

**Fingerprint**: md5 of the kind + the message with numbers, hex and quoted strings replaced by `#` + the location
the same way; so one bug is one issue whatever the values. A session sends each issue once (its count adds up until
sent). **Crumbs** (`Telemetry.crumb(kind, data)`, the last 30, each with the time, zone and position): `start`,
`enter` (a zone), `level`, `died`, `boss` (a boss fight began), `raid` (Battlegrounds). Add more where they help.
Batches go up every 60 s (at most 20 of each), through the Nakama RPC `telemetry` (players, with their session) or
`telemetry_server` (the servers, http_key); `deploy/nakama/modules/ashen.lua` stores them (it creates the tables and
the `tm_issue` view at start, and grants Grafana's read-only role SELECT on them). Offline they wait (up to 200).

## The servers' logs (Loki)

`deploy/staging/docker-compose.yml`: Loki (30 days kept, `deploy/staging/loki/loki.yml`) and Grafana Alloy
(`deploy/staging/loki/alloy.alloy`) shipping the systemd journal (label `unit`: `ashen-crown-bg.service`,
`ashen-crown-coop.service`, ...) and every container's output (label `container`: Nakama, Caddy, Postgres, Grafana).
Lines with ERROR / SCRIPT ERROR / panic / a JSON `"level":"error"` also get `level="error"`. In Grafana: Explore →
Logs, e.g. `{unit="ashen-crown-bg.service"} |= "SCRIPT ERROR"`.

## Tests

`tools/telemetry_test.gd` (in the gate, `tools/nightly/gate.sh`): off in tools, a crash from a session that didn't end, an error read
from the log and fingerprinted (twice = one issue counted twice) with the crumbs and the PC, a sample with its
hitches; with `-- cloud <url> <key>` it also sends them to that Nakama.
