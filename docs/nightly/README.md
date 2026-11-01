# Nightly lab (knowledge base)

Three nightly jobs on the Game Factory Mac (launchd, New York time), one at a time, each on a fresh copy of `staging`,
each with its own test gate, push, deploy and Discord report (`tools/nightly/run.sh <job>`):

| Job | When | What | Its log |
|---|---|---|---|
| `mode` | 20:00, 3.5 h | A new multiplayer mode or map on the staging server, playable the same night | `modes/LOG.md` |
| `perf` | 00:30, 3 h | Faster and smaller: a big structural win, then as many small ones as the night allows; the download size every night | `perf/LOG.md` |
| `triage` | 05:00, 2 h | What players hit (errors, crashes, slow spots from the telemetry, `TELEMETRY.md`), worst first, at most 3 issues and 2 spots: reproduced from where they were and what they did, fixed | `triage/LOG.md` |

**The loop**: each job reads its log first (the Lessons at the top, then one short row per attempt: focus, result,
kept or not, next idea, a link to the detailed write-up), works, then adds its rows and rewrites the Lessons. Around
each job the runner benchmarks the game itself (`tools/nightly/bench.sh`, the same scenes every night) and adds a
`bench` row: a job that made the game slower doesn't ship. For modes, Blaine's and JJ's Discord feedback goes into the
mode's `feedback.md` and the log's Verdict column (keep / iterate / cut), and the next night builds on it.

| Path | What |
|---|---|
| `perf/LOG.md` | The performance log: Lessons, then one row per attempt (big / small / size, and the runner's `bench` rows) |
| `perf/runs/<date>.md` | A night's full performance write-up: what was profiled, what changed, every number, why failures failed |
| `perf/metrics.jsonl` | One JSON line per measurement (the job's own, and the runner's with `"source": "runner"`) |
| `perf/SIZE.md` | The download size per platform, night by night |
| `KPIS.md` | The official performance KPIs: the scenarios, every metric and how it's measured, the targets, Grafana |
| `TELEMETRY.md` | Player telemetry, error and crash reports, the server logs: what is sent, where it goes, how to query it |
| `triage/LOG.md` | The triage log: Lessons, then one row per issue or slow spot looked at (fixed / not reproduced / watch) |
| `triage/runs/<date>.md` | A triage night's write-up: the reports, the reproduction, the cause, the fix |
| `modes/LOG.md` | The game-mode log: Lessons, then one row per mode (pitch, result, verdict, next) |
| `modes/<date>-<slug>/README.md` | The concept, how to play it, what was built, screenshots, and the cost broken down by tool |
| `modes/<date>-<slug>/feedback.md` | Blaine's and JJ's feedback after playing (the Game Factory session files it from Discord) |
| `costs.jsonl` | One JSON line per job and night: Claude, Meshy, ElevenLabs and server cost |
| `nights/<date>-<job>.md` | Each job's report as posted |

Rules the nightly sessions follow are in `tools/nightly/perf_prompt.md` and `tools/nightly/mode_prompt.md`.
