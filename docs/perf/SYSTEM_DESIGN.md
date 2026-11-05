# Shared performance systems: proposed design

Status: design for review, not implemented. Read with [the source audit](AUDIT.md) and [targeted verification](VERIFICATION.md). Scope includes title, menus, world transitions, combat, late joins and headless worlds; different surfaces use different parts of the same contracts.

## Plain-language model

Imagine a stage play. The asset service brings the right props backstage and keeps track of who still needs them. The transition coordinator builds the next set a little at a time while the curtain is up. Visual preparation rehearses the lights and effects before the audience sees them. The stopwatch checks whether the show actually pauses. Content rules make every new scene follow the same process. Even with all props ready, too many actors or lights can still overload the stage; that is a separate ongoing cost.

## Five systems to unify

| System | Owns | Existing pieces to preserve and connect | Required contract |
|---|---|---|---|
| **Performance measurement and gates** | Scenario definitions, clocks, phase timings, budgets, run validity and reports | `Kpi`, `KpiProbe`, `FxTiming`, stress/first-use tools, nightly comparison and Grafana | Every result states what ran, on which build/hardware/settings, what failed, and which clock produced each metric. Missing required coverage never passes. |
| **Content readiness and residency** | Dependency catalogue, loading requests, readiness, retention and release | `Data`, `ZonePreload`, `ResCache`, boot preloads, model/material caches | A consumer can ask for a content scope and determine whether its mandatory dependencies are ready. Hot-path access cannot hide an unreported blocking load. Each retained resource has an owner. |
| **World and screen lifecycle coordinator** | Transition phases, work scheduling, cancellation, activation and retirement | `Game.load_zone`, `World.build`, grass/minimap construction, screen setup, effect cleanup | A transition is observable and cancellable. Stale asynchronous work cannot attach to a replaced world. Readiness includes construction, not just files. |
| **Visual preparation and cost policy** | Warm recipes, variant readiness, quality context and ongoing visual budgets | `SkillWarm`, `MonsterWarm`, UI warming, `SkillFx`, `Fx.effect_shadow`, quality presets | A visible effect follows the same preparation and cost rules regardless of who cast it or which screen shows it. Preparation and per-frame drawing cost are measured separately. |
| **Content acceptance and dependency validation** | Rules for adding content, generated coverage, reviewed exceptions and required tests | Existing content tables, capture tools, inventory script, skill tests, CI/nightly | A new monster/spell/zone cannot silently bypass declarations, lifetime rules and representative performance coverage. Rules are checked, not merely written in a handbook. |

These are shared responsibilities, not a requirement to create five giant manager nodes or rewrite every class. Introduce small interfaces around existing working code, then migrate consumers by feature. The catalogue is a view of existing content definitions plus explicit dependencies, not a second competing gameplay database.

## 1. One measurement language

The shared scenario description names its startup route, initial state, seed/input schedule, party/classes, renderer/preset, resolution, window focus, cache condition and required outputs. A title scenario must use the title flow; a KPI that jumps directly into a zone is not its substitute. New PvP Arena and Aurelia's older arena scenario have separate IDs. Assert that the intended workload actually happened: required casts, relevant nearby/visible enemies, party participants and completed transitions. A nominal 24-enemy scenario is not a substitute for the reported multi-class spell-heavy fight.

Use monotonic elapsed time between rendered-frame observations for user-visible stalls, keeping simulation delta as a different metric. Record CPU script/physics, renderer CPU, GPU and queue/network timings separately. Do not add overlapping intervals. Phase reports include total time and worst frame during loading. A result's validity envelope contains runtime errors, timeout/completion status, unexpected concurrent processes and missing artifacts.

Preserve individual runs. Compare median-of-three and range, with p99/max and stall counts; a median does not excuse a severe outlier. Keep release gates distinct from exploratory diagnostics. Diagnostic visual ablations cannot be published as a new quality preset or a shipping performance improvement.

The existing FPS regression check remains useful as one check, alongside coverage, first-use stalls, transition responsiveness, memory and functional correctness. Match absolute thresholds to named hardware and workload; do not silently substitute the brief's 33 ms p99 for the existing KPI document's 25 ms goal.

## 2. Content moves through explicit readiness states

```text
declared -> requested -> resources ready -> constructed -> visually prepared -> active
                |              |                |                |
                +--------------+----------------+----------------+-> failed/cancelled
active -> retiring -> released
```

Each request has a generation ID, a dependency set and an ownership handle. Suggested scopes are core UI, current world, selected/active party classes, and short-lived previews. Shared resources survive while any scope owns them. An eviction policy considers estimated cost and measured memory pressure; actual budget values are determined by working-set measurements rather than guessed now.

`get_ready(path, handle)` provides an already-resident dependency. In development, an undeclared/missing request produces a structured diagnostic. Mandatory gameplay content goes through explicit recovery/preparation; optional decoration may use a documented fallback. No silent null caching forever after a transient failure. Failed/cancelled requests can retry; concurrent requests share one load.

Dependency discovery combines explicit declarations, imported-resource dependency traversal and runtime traces. A regex scan cannot establish full dynamic reachability. Generated output includes source/content fingerprints, and stale coverage is visible. Do not retain every model merely because it exists in the repository.

## 3. One lifecycle, with bounded work per frame

The coordinator owns ordered phases: prepare dependencies, retire previous state, construct world data, attach terrain/props/collisions, place actors, capture auxiliary views, prepare visuals, activate. It can report precisely which stage is slow.

Move suitable pure data computation to workers using isolated inputs. Budget main-thread node creation/attachment in batches; split any individual operation that exceeds the budget. Yielding after a single giant operation does not solve its freeze. The actual batch budget is chosen from measurements on target hardware.

A new feature should use these contracts instead of adding its own private loading loop, cache or cleanup convention. An adapter can keep the existing implementation while exposing readiness, ownership and timing.

The same lifecycle rules apply to UI preview worlds and title scenes. They need not run all world phases. Headless servers skip visual preparation and screenshots, but still need construction, dependency lifetime, cancellation and tick/memory measurement.

Retirement must cancel callbacks and remove hero/puppet effect state as well as free world nodes. Claude's separate triage branch already contains related fixes; integrate those through normal coordination instead of creating a conflicting cleanup implementation. Test interruption at every awaited boundary, disconnect during load, repeated travel and returning home.

## 4. Visual readiness and runtime cost share a policy

A warm recipe declares representative mesh/material/pass combinations and delayed visual stages. It is keyed by relevant content/variant and rendering settings, marked complete after success, and invalidated when required resources or render context change. Adapt existing class/monster/UI warmers; do not discard their established coverage.

A late-joining class, equipment preview or preset switch requests its newly needed recipes. Running the current global-time-scale warm-up in an active battle is not a safe universal solution: preparation needs a visual-only context or an explicit loading boundary. Godot 4.3 cannot guarantee complete pipeline coverage from arbitrary procedural effects, so record observed misses and expand tests.

After readiness, visual cost still has limits: shared immutable meshes/materials, bounded shadowed lights, transparent particle area/density, update frequency and active instances. Preserve gameplay telegraphs and simulation. Evaluate cheaper equivalent rendering before visible quality reductions. The current two-shadow-light cap and audio voice pools are useful foundations.

Pools are optional implementations under this policy, not a requirement to pool everything. A pool must reset timers, callbacks, owner/target references and material parameters; it has a maximum size and a retirement path. Compression changes require asset-role and visual checks; file compression is not automatically GPU-memory compression.

## 5. New content has an enforceable completion checklist

For a new spell, the author selects existing asset dependencies, supplies any new draw recipe/delayed stages, declares ownership and provides one representative first-use and repeated-use scenario. For a zone, include its possible monster/summon dependencies and a traversal/transition scenario. For UI, include opening/closing and its preview lifetime.

Automated checks verify referenced paths, content coverage, known bypasses and structural rules cheaply. Real-renderer runs verify affected scenarios; broader scheduled sweeps test interactions and memory. Keep exceptions reviewed and scoped. New content requires some explicit integration work; the benefit is a repeatable path and visible omissions.

## What should not become a mandatory rewrite yet

- **Spatial enemy index:** a plausible replacement for repeated full scans, but measure total query time and candidate counts at representative populations first. Preserve semantics with equivalence checks for moving, spawning, dying and teleporting enemies. It is an optimization behind a query interface, not the foundation of the whole architecture.
- **Object pooling everywhere:** prioritize measured allocation hot spots; pooled objects introduce their own stale-state and memory-retention risks.
- **Engine upgrade or server resize:** separate experiments only when they address a measured constraint. Neither automatically repairs local content preparation and lifecycle design.
- **Bulk asset conversion or preloading the whole game:** both can create new memory/load-time problems. Use measured scopes and representative visual verification.

## Implementation order after design review

1. Make the benchmark trustworthy and establish repeatable baselines with no competing renderer; reconcile the two frame clocks and gate required coverage/errors.
2. Apply readiness/ownership/coordinator contracts to one title → camp → moor → fight → return flow, including a late-joining class and an interrupted transition.
3. Split the largest measured construction/preparation stages, then verify timing, visual parity, gameplay and bounded repeated-loop memory.
4. Expand by content family. Address measured sustained rendering/query/allocation costs independently, with one-variable comparisons.
5. Enforce the new-content rules after adapters exist, so enforcement drives migration instead of breaking every existing caller at once.

This is consistent with Godot's distinction between ongoing frame cost, intermittent stalls and loading time, and its recommendation to test bottleneck hypotheses rather than optimize every suspicious call. [Godot 4.3 optimization guidance](https://docs.godotengine.org/en/4.3/tutorials/performance/general_optimization.html) Riot's approach supports comparable hardware/workloads and actionable subsystem timing. [Riot profiling](https://www.riotgames.com/en/news/profiling-case-missing-milliseconds)
