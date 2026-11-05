# Shared content preparation implementation

This branch implements a common preparation path in the existing Godot 4.3 game. It is a preview candidate;
performance acceptance is separate from successful functional tests and exports. See IMPLEMENTATION_RESULTS.md
for measured results and remaining limits. It does not change damage, PvP rules, or network RPC signatures.

## The three systems developers use

1. **Content catalog and resource ownership:** declare a screen/zone/combat family's asset roots in
   `ContentCatalog`; acquire a named `ResCache` scope before activation, await readiness, and release the scope
   when its owner leaves. Requests share one load and one resident resource. Existing consumers retain their
   own references safely after a scope is released. Unconverted synchronous calls are counted by path.
2. **Preparation and activation:** `Game.load_zone` prepares resources, assembles the world, prepares monster
   models and visual recipes, then enables play. `World` can run incremental presentation jobs while preserving
   construction order. Grass is the first migrated job across camp, moor, fort, road, coast and islands.
3. **Permanent acceptance checks:** CI verifies resource lifecycle and content declarations. The benchmark
   retains first-use stalls, all repeats and runtime errors; requires complete coverage including 3v3; and
   rejects regressions in stalls, loading, memory and FPS independently.

## Resource lifetime and threading

`prepare(scope, paths)` records ownership and coalesces repeated requests. `status(scope)` distinguishes ready,
failed and cancelled. `wait_ready(tree, scope)` yields frames; `release(scope)` drops only that owner's claims.
A pending cancelled request finishes safely and its unowned result is discarded. Final teardown joins an
outstanding worker; ordinary release does not wait for disk I/O.

The background worker only loads resource files. Nodes, scene-tree insertion, physics and rendering setup stay
on the main thread. One worker is active at a time, following Godot's advice to use one loading thread and avoid
concurrent modification of shared resources. Early experiments with the Godot threaded-status API crashed inside
the native loader; the exact native cause is unproven. The final path uses an owned Thread and collects its result
only after the worker has finished. No engine upgrade is required.

Godot already caches resources. This layer supplies ownership, readiness and diagnostics around it; it does not
replace Godot's importer or duplicate imported dependencies. Catalog root files can be discovered from their
named directories in source and exported packs (`.import` / `.remap` names are normalized).

`get_res` remains a compatibility fallback. A missed root can still load synchronously and acquire a legacy
session pin. That is visible in metrics and rejected during benchmark gameplay. This migration is therefore
observable rather than pretending all direct `load()` calls have disappeared. Direct engine loads outside
ResCache are not captured by this counter; the inventory and code review remain necessary.

## Context and memory policy

Dedicated servers never acquire client presentation bundles or run visual warmers. Their simulation, collision
and other required data remain under the existing server builders, compatible with the lean server work.
Solo preparation selects the current class. Online/competitive preparation currently covers all classes so an
unknown late arrival does not bypass class readiness. Assets shared across spells form a session combat family;
zone assets belong to the current zone. During transition, old and incoming assets can overlap until the old
world is retired. This is a deliberate peak-memory tradeoff that must be measured.

Legacy compatibility pins and existing shader/material warm caches are still session-long. This is not a
byte-budgeted LRU cache, and clearing a scope cannot force GPU memory to fall while another object retains a
resource. Byte-budgeted eviction, roster-specific online preparation and all UI caches need further measured
work if the residency results exceed target. Loading everything at startup is not the contract.

## Incremental construction

`Grass.ScatterJob.step()` performs one grid row or one output bucket. `World.finish_visuals()` runs steps until
its cooperative 4 ms budget is used, then yields a frame. A step cannot be preempted: `max_step_ms` records
overshoots so an oversized step can be split further. The synchronous Grass API drains the same job for old
callers and headless world tests. Scheduled jobs execute at the original construction point to preserve random
number use and collision/layout order.

Only presentation assembly is scheduled. Simulation-critical layout does not become partially playable. Other
world builder loops, minimap capture and first-use GPU compilation can still block; they must be measured and
migrated deliberately. An `await` around a large monolithic function alone does not split its work.

## Visual preparation and PvP

Warm recipes are keyed by renderer, GPU, quality, MSAA and class/kind, and marked complete after drawing. Warmup
no longer changes global Engine.time_scale; doing so can accelerate an unrelated live multiplayer simulation.
Existing shader/material retention is preserved. A file being resident does not imply its GPU pipeline has
compiled or that constructing hundreds of particles is cheap.

`--kpi pvp3v3` creates six rendered actors, Demon/Plague/Archer on both sides, and replays every recorded event in
synchronized six-second floods. It reports first-use and steady-state frame times, per-event construction time,
FX node peaks and resource misses. This intentionally exceeds legal cooldown concurrency to expose worst cases.
It is a **presentation stress replay**, not six network clients casting legal skills. The separate six-client
lobby team test verifies admission, teams, rounds/results and transport teardown. Neither replaces full live
network gameplay profiling or a sweep of every class combination.

## Adding content without recreating the problem

- New content inside a declared family is discovered automatically. A new family needs a catalog declaration;
  a new class also needs its roots and a visual recipe. CI rejects missing class declarations and missing roots.
- Acquire resources before a screen, zone or encounter uses them; reuse its owner scope. Do not add a new global
  cache or untracked hot-path `load()` to solve an individual hitch.
- Expensive procedural construction needs small resumable steps. Preserve deterministic layout and test parity
  before scheduling it. Register the caller's await all the way to Game; old synchronous callers keep the default.
- A new effect must be represented in the warm/event capture and exercised in the burst profile. Check actual
  rendering, not only a resource loader test. Shared mutable materials must be duplicated before per-instance edits.
- Run lifecycle/coverage contracts and the affected gameplay tests, then compare three quiet, focused repeats
  on identical settings. Keep failed attempts. A missing scenario, error, changed resolution or synchronous
  gameplay miss blocks certification. Relative non-regression is not the same as meeting the FPS target.

Cheap contracts run in preview, staging and desktop release CI. GPU performance runs require a real GPU/window;
GitHub's headless export runner is not a substitute. The nightly comparison enforces the complete measurement
contract and does not automatically bless the current slow build as a new baseline.

## References

- [Godot 4.3 thread-safe APIs](https://docs.godotengine.org/en/4.3/tutorials/performance/thread_safe_apis.html):
  one background loader, shared resource cautions, main-thread scene-tree work.
- [Godot 4.3 background loading](https://docs.godotengine.org/en/4.3/tutorials/io/background_loading.html):
  asynchronous resource preparation and the blocking risk of collecting an unfinished request.
- [Unity Addressables memory management](https://docs.unity.cn/Packages/com.unity.addressables@1.21/manual/MemoryManagement.html):
  explicit ownership/release and resource dependencies; conceptual precedent, not a Unity API port.
- Further primary Epic/Riot/Godot sources and the original code audit are in [AUDIT.md](AUDIT.md).
