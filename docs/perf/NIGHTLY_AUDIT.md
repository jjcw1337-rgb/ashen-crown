# Published-build nightly performance audit

Blaine requested this on 2026-11-05. This is a read-only audit; the existing 00:30 Claude
optimization job and 05:00 triage job remain separate. No model/API calls, paid generation,
code changes, pushes, deployments or Discord messages are performed by this new job.

## Schedule and reports

Install with `/usr/bin/python3 tools/performance_audit/install.py`. The macOS LaunchAgent
`com.gamefactory.ashen-performance-audit` runs at **22:30 Mac local time** (currently
America/New_York). Busy runs retry every 15 minutes until 23:30. A completed report with
findings is retained; it is not repeatedly rerun until it happens to pass. An audit has a
75-minute maximum runtime. The Mac must be awake and its user session logged in for GPU tests.

Reports: `~/Library/Application Support/ashen-performance-audit/latest.md` and `latest.json`.
Detailed logs, JSON metrics and screenshots live in `runs/<timestamp>/`. Native engine logs
can contain the signed-in Steam identity: keep these local/private; share sanitized summaries.
The installed runner is an immutable version under `~/dev/ashen-crown-performance-audit-runner/`.
Reinstall deliberately when its code changes; it never silently executes an updated runner.

## What runs

- Select the successful staging workflow for **the current origin/staging SHA**. A pending or
  missing build is incomplete, not permission to label an old build current.
- Download the existing CI artifact, verify its provided digest when available, extract only
  the Mac application, and run its executable/PCK. No asset import or editor is launched.
- Verify an isolated `AshenCrown-NightlyAudit-*` user directory before creating a game scene.
  `--main-pack` reads override.cfg beside the PCK; putting it in the working directory is
  insufficient ([Godot 4.4 source](https://github.com/godotengine/godot/blob/4.4/core/config/project_settings.cpp)).
  Cloud is disabled in the test bootstrap. Player characters and settings are not test inputs.
- Cache ownership/cancellation, content declarations, actual catalog loads, BG/Arena world construction
  without undeclared cache requests, fragment reuse,
  cached-mesh material retirement, all-class spell replay and solo-to-co-op preparation/cleanup.
- Three fresh-process repeats each: camp, moor at Medium/High/Ultra, combat, boss, Aurelia,
  Battlegrounds, **three six-actor PvP floods** (mixed Demon/Plague/Archer, moving dragons, and
  forest summoners/status effects), and the local headless server tick: twelve profiles total.
  PvP requires the declared roster/environment, six actors/two teams, at least three bursts and actual events. This is not a
  six-network-client match or proof of public competitive authority.
- Sandbox solo entry, bot damage/respawn, mode-specific buttons, repeated mixed-bot/monster cleanup
  and temporary-character isolation. The existing PvP simulator measures moving-target Demon/Plague/Archer
  damage at level20 with fresh/geared builds; its duel flags are review findings, not automatic balance edits.
  Hosted Sandbox late-join/respawn/save checks use the separate two-client `sandbox_lobby_test.gd`;
  they are a release check, not part of this one-process nightly job.
- Median **and worst-repeat** FPS, p99/worst/first-use frames, hitches, loading time and engine
  memory counters; zero observed gameplay cache misses. These counters are not OS RSS/total memory.
- Per-file lexical load/preload/Shader.new/cache-fallback inventory, for review; counts are not
  automatically classified as hot-path defects.

All required scenarios, three repeats, completion markers, finite metrics, exit codes and logs
are checked. Warnings and runtime errors invalidate benchmark acceptance even if assertions
print success. Focus must be retained for rendered scenarios. Each repeat is a fresh process,
but OS/driver caches may remain warm: **no cold-driver-cache claim**.

The first complete valid run establishes a pinned baseline for its engine/GPU/resolution/map/policy.
It does not prove improvement. Later nights compare against that baseline; an engine change
starts a separate baseline. FPS losses over10% and other metric growth over20% plus a small
noise floor are findings. Current project budgets also flag first-use over50ms, loading over5s,
and combat/PvP p99 over33ms or worst frame over80ms. Memory is tracked for regression; no
unmeasured universal VRAM limit is invented. A bad baseline does not waive absolute budgets.

## Coordination and bounded use

Acquire `heavy-tests` as `codex-nightly-audit`. Never steal another owner's persistent claim,
including a claim left after a crash. A preexisting claim, legacy nightly lock, another game
process, missing desktop focus, memory/disk pressure, timeout or missing required contract is
reported explicitly. The audit stops only its own process group and releases only its own claim.
The legacy nightly runner predates cooperative claims; this audit detects its lock and stops
its own workload if that runner starts. It does not modify or restart the existing jobs.

Require16GiB free before downloading and at least6GiB while running. Require15% reported memory
headroom before a workload and stop below5% during it. Run one game process at a time; the local
server profile uses UDP24891. No shared mutable import cache, staging checkout or live server is used.
Only the audit's own downloaded application cache is replaced. Reports and evidence are retained.

## Verification and rollout limits

`python3 -m unittest discover -s tools/performance_audit -v` exercises coverage, worst-repeat
regressions, nonfinite/missing data, spell-flood coverage, runtime-error rejection, schedule
retry bounds, archive containment and cooperative-lock deferral. `--preflight` exercises the
installed environment without starting a game or claiming a performance pass.

The full workload requires the shared performance contracts/profile to have reached staging.
Until then it reports the missing requirement and defers. A loaded LaunchAgent and passing
runner tests do not constitute a completed nightly GPU audit. The staging rollout itself still
requires its separate full functional gate and publication verification.
