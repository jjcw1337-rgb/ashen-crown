# Implementation verification — 2026-11-05

Preview implementation; not a staging/production rollout or a certified performance pass.
Source worktree: `test-codex-perf`. Main measurement baseline: `009420c` with identical diagnostic-only KPI
clock and six-actor workload backported; its ResCache miss counter is a stub, so baseline misses are **unmeasured**.
The candidate integrates Claude's committed lean-server and lobby-capacity work through `326faf3`.

## Completed checks

- Resource ownership/coalescing/cancellation/release: 20 checks, no runtime errors.
- Final catalog source coverage: 1,694 checks, no runtime errors. These check declared roots exist, not that every
  dynamically constructed asset path in the entire game is declared.
- Benchmark gate/runner: 9 Python tests, including missing coverage, a hidden bad repeat, false-green exit zero,
  timeouts, concurrent engine processes, FPS/stall/load/RAM/VRAM regression and mismatched settings.
- Integrated lobby service: 49 Python tests pass.
- Real local six-client 3v3 before the lean-server integration: 36 assertions, round/result/return-home checks;
  no script/parse failures, but known Godot 4.3 headless dummy null-mesh errors remain. Not an error-free run.
- Synchronous vs scheduled construction: town, moor, coast and Verdant Isle preserve grass buffer hashes,
  spawns, obstacles and interactables. Known headless dummy null-mesh errors remain. No RNG-order change accepted.
  Moor's 1.7-second grass job yielded 194 times; largest atomic step was 16.1 ms (cooperative target is 4 ms,
  not a hard bound). Town 23 yields/2.8 ms max; Verdant Isle 249 yields/13.1 ms max. These are diagnostics,
  not GPU performance measurements.

## First controlled 3v3 experiment: useful, but rejected as the final loading policy

Three baseline and three candidate runs, real Forward+, 1600×900, High, focused throughout, no other Godot
observed during those six runs. Pipeline disk cache disabled identically in the local test override due to a
previous MoltenVK cache startup failure; no cold-driver-cache or exported-build claim. Every run replayed 688
presentation events across six actors/four synchronized floods. Runtime logs clean after fixing the common
harness teardown (actors must outlive their delayed effects until the tree exits).

| Median | Before | Initial candidate |
|---|---:|---:|
| Average FPS | 13.4 | 21.3 |
| p99 frame | 836 ms | 319 ms |
| First-use worst frame | 5,870 ms | 1,461 ms |
| Preparation including actor setup | 8,390 ms | 31,313 ms |
| Reported video memory | 1,820 MB | 3,426 MB |

One candidate repeat had a 1,680 ms p99: the median must not conceal that regression. All candidate repeats also
exposed one undeclared Spirit Beast root. The gate would reject this candidate for resource misses, loading,
video memory and worst-repeat stalls even though its median FPS improved. The shared preparation mechanism
helps first-use behavior; this does **not** establish that all-class warmup meets the game's performance targets.

The catalog was then corrected to declare the summoned wolf directly and to remove unrelated outdoor/Roman
scenery from the PvP hall. A clean rendered check of that revision had zero observed gameplay cache misses and
reported 2,894 MB video memory. Another Godot process started during this check; its timing/FPS is excluded from
controlled comparison. Further quiet repeats and full user-flow checks are tracked below as they complete.

Compact pilot evidence: [implementation-pvp-pilot.json](evidence/implementation-pvp-pilot.json).
Full logs, frames, screenshots, failed pilots and local network records remain under workspace
`output/perf-implementation/`. Native-loader crashes from abandoned pilots remain retained; they are not successes.

## Acceptance limits

This is an implemented shared path and a measured first migration, not a completed optimization of every
screen, asset and effect. Remaining costs include procedural node/material creation, sustained GPU effect load,
monolithic world/minimap sections, session-long legacy/material pins and the cost of preparing every possible
online class. Full suite certification, all class combinations, Windows/Linux GPU runs and long memory soaks
remain required. Existing synchronous fallbacks are counted, not silently declared impossible. The six-actor
burst is presentation replay; actual network gameplay correctness is tested separately.
