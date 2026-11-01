# Nightly lab (knowledge base)

Every night at 03:00 New York time, `tools/nightly/run.sh` (launchd on the Game Factory Mac) runs two big
autonomous Claude sessions on a fresh copy of `staging`, tests the result, merges it into `staging` (so itch.io and
the staging server get it), and posts the morning report to Discord. Everything it learns is kept here, so each
night builds on the last.

| Path | What |
|---|---|
| `perf/CONCEPTS.md` | One line per night: date, the performance idea tried, the measured result, kept or reverted |
| `perf/runs/<date>.md` | The night's full performance log: what was profiled, what changed, before/after numbers, screenshots |
| `perf/metrics.jsonl` | One JSON line per measurement (date, preset, scene, fps, 1% low, draw calls, primitives, GPU ms) |
| `modes/INDEX.md` | Every game mode or map ever built: date, name, one-line pitch, status, feedback score |
| `modes/<date>-<slug>/README.md` | The concept, how to play it, what was built, screenshots, and the cost broken down by tool |
| `modes/<date>-<slug>/feedback.md` | Blaine's and JJ's feedback after playing (the Game Factory session files it from Discord) |
| `costs.jsonl` | One JSON line per night: Claude, Meshy, ElevenLabs and server cost of each phase |
| `nights/<date>.md` | The morning report as posted (hype included) |

Rules the nightly sessions follow are in `tools/nightly/perf_prompt.md` and `tools/nightly/mode_prompt.md`.
