# Performance system audit

2026-11-05 · desktop Godot 4.3 Forward+ · source baseline `8845213e29577b81fda420b2a0b89e5799231002`

This is a code audit and implementation design, informed by `codex_perf_brief.md`, the current source, recorded project measurements, and primary developer documentation. It is **not a completed runtime overhaul or a new performance benchmark**. No game, server, rendering setting, asset, or shared cache was changed for this audit. See [RESULTS.md](RESULTS.md) for what was actually verified.

## The explanation without engine terminology

The game must make a new picture about every 16.7 milliseconds to deliver 60 frames per second. There are several ways to miss that deadline:

- It goes to the cupboard to fetch a dragon while you are already fighting the dragon: **loading**.
- It has the dragon's pieces, but still needs to assemble them: **object creation and scene construction**.
- It has assembled the dragon, but the graphics card has never drawn that particular dragon/fire/shadow combination: **first-use graphics preparation**.
- Everything is ready, but it is trying to draw too much fire and grass every picture: **ongoing rendering cost**.
- Every monster repeatedly searches the entire room to find its neighbors: **ongoing simulation/query cost**.

Our system should prepare the next room before opening its door, assemble big jobs in small pieces, rehearse likely visual effects, keep a bounded cupboard of reusable parts, and check every new feature against the same stopwatch. Loading everything forever would eventually fill the cupboard; caching alone cannot make an expensive picture cheap.

## The equivalent of a SaaS architecture audit

| Familiar application fix | Equivalent here | Concrete candidate |
|---|---|---|
| Central data-access layer with observable cache misses | One asset-access service with explicit readiness and ownership | Extend `ResCache`; do not merely rename `load()` |
| Batch/prefetch a request's dependencies | Prepare the next zone and party's dependencies together | Replace incomplete recorded zone lists with a validated content catalogue |
| Move long work out of a request and bound each batch | Background resource I/O and incremental scene assembly | Split `World.build` into budgeted stages |
| Add a spatial database index | Query nearby enemies through a spatial grid | Profile and then replace repeated full enemy scans |
| Reuse connections and expensive prepared objects | Reuse immutable materials/meshes and selected transient objects | Build on `Geo`, audio pools and measured projectile allocation |
| Bound cache size and expire by ownership | Release zone/party resources when their owners retire | Replace unbounded session retention with measured lifetime scopes |
| Query latency and regression gates | Frame-time distributions, loading phases, memory and coverage gates | Repair benchmark selection and missing-scenario handling |
| Increase database capacity | More server capacity only for a demonstrated server bottleneck | A droplet upgrade will not fix local shader compilation or GPU overdraw |

## What the research supports

**Separate resource loading from readiness.** Godot's threaded request starts background work; collecting its result before it is ready can still block. A loading service therefore needs an explicit readiness barrier and error handling. [Godot 4.3 background loading](https://docs.godotengine.org/en/4.3/tutorials/io/background_loading.html)

**Schedule scene work separately.** Godot's active scene tree is not thread-safe, and rendering operations have additional restrictions. Use workers for suitable isolated data preparation; attach nodes and mutate the live world in bounded main-thread batches. Moving the whole existing world builder to a thread is not the solution. [Godot 4.3 thread-safe APIs](https://docs.godotengine.org/en/4.3/tutorials/performance/thread_safe_apis.html)

**Prepare actual draw combinations.** Epic's discussion of pipeline-state precaching distinguishes loading an asset from preparing its graphics pipelines. Materials, mesh formats and rendering states matter. The transferable practice is to prepare likely combinations before first visible use and track misses; Unreal's implementation is not a package we can drop into Godot. [Epic: game engines and shader stuttering](https://www.unrealengine.com/tech-blog/game-engines-and-shader-stuttering-unreal-engines-solution-to-the-problem)

**Give loaded content an owner.** Unity's Addressables discussion emphasizes grouping content by use and releasing handles; pooled instances also keep dependencies alive. The applicable principle is explicit asset lifetime, not replacing Godot with Addressables. [Unity: optimizing memory and build size](https://unity.com/blog/engine-platform/extended-q-a-optimizing-memory-and-build-size-with-addressables)

**Measure stalls by subsystem and hardware.** Riot describes looking beyond average frame rate, separating frame costs and investigating spikes on relevant hardware. We should keep CPU, GPU, loading and network measurements distinct instead of labeling every pause an asset problem. [Riot: the case of the missing milliseconds](https://www.riotgames.com/en/news/profiling-case-missing-milliseconds)

**Use engine-version-appropriate techniques.** Godot's newer pipeline machinery includes improvements introduced in 4.4. This project uses 4.3, so those features cannot be assumed to exist here. A future engine upgrade deserves a separate controlled comparison; it is not a prerequisite for this plan. [Godot 4.5 pipeline compilation documentation](https://docs.godotengine.org/en/4.5/tutorials/performance/pipeline_compilations.html)

## Findings in this revision

The inventory is reproducible with `python3 tools/perf_inventory.py`. It finds **146 direct `load` sites, 30 `ResCache` accesses, 7 `preload` sites, and 108 `Shader.new` sites** in `scripts/**/*.gd`, plus background request/collection calls. These are lexical locations, **not counts of bugs, uncached shaders, expensive executions, or gameplay-reachable calls**. Shader builders often already retain their shader. Review callers and measurements before changing them. [Full inventory](asset-access-inventory.csv)

| Priority | Evidence from source | Consequence and proposed action |
|---|---|---|
| 1 | [`ResCache.get_res`](../../scripts/res_cache.gd#L11) performs synchronous `load(path)` on a miss; `inst` still instantiates the scene. | Repeated use improves, but first use and object creation can still hitch. Add requests, readiness, miss telemetry and explicit scopes before migrating hot callers. |
| 1 | [`Game.load_zone`](../../scripts/game.gd#L1383) starts requests, then calls `world.build` synchronously; [`ZonePreload.finish`](../../scripts/zone_preload.gd#L34) collects without polling readiness. | A background request can still turn into a wait inside construction. Separate request, ready, assemble and warm stages. Measure each phase. |
| 1 | [`ZonePreloadData`](../../scripts/zone_preload_data.gd) contains only `0:bg`, `0:lair`, `0:town`, `0:wild`, `1:lair`. Its recorder inspects model origins in an already-built tree. | Coverage is incomplete; transient effects, audio, textures loaded independently and unvisited branches are not comprehensively discovered. Use declared dependencies plus import dependency traversal and runtime access traces. |
| 1 | [`SkillWarm.run`](../../scripts/skill_warm.gd#L34) uses class-only session flags; its comment explicitly postpones a mid-zone partner's class until the next zone. [`MonsterWarm`](../../scripts/monster_warm.gd) warms bodies/overlays. | Late joins, preset changes, delayed skill stages and boss attacks need explicit coverage. Introduce warm recipes and contextual readiness; retain existing successful warmers as adapters. |
| 1 | [`World.build`](../../scripts/world.gd#L1022), [`Grass.scatter`](../../scripts/grass.gd#L129), [`Game._capture_map`](../../scripts/game.gd#L1507) perform separate substantial construction/render work. | Files being resident does not make these operations free. Profile and chunk generation/attachment; measure minimap capture and old-world retirement independently. |
| 1 | [`bench_compare.py`](../../tools/nightly/bench_compare.py) compares averages over intersecting scenario keys; best-run merging selects highest FPS. [`bench.sh`](../../tools/nightly/bench.sh) also selects the best result when repeated. | Partial coverage and intermittent stalls can escape the gate. Require expected coverage, retain every run, compare median-of-three and frame-time tails. |
| 2 | [`Game.enemies_near`](../../scripts/game.gd#L1728) scans live enemy children and builds a result array on each call; many skills and behaviors call it. | This is the closest equivalent to a repeated unindexed query. Count calls/candidates/time, then introduce a zone-owned spatial index if it materially contributes to CPU cost. |
| 2 | [`Projectile.launch`](../../scripts/projectile.gd#L13) creates particles, process material, gradient/texture, quad and light for relevant projectiles. | Cache immutable resources and trial a bounded reusable visual pool where allocation is measured expensive. Preserve collision, ownership, timers and cleanup semantics. |
| 2 | `ResCache._held` and `SkillWarm` retained resources have session lifetime. | Retention deliberately prevents repeat work, but lacks explicit budgets/ownership. Measure bounded working sets and release unused scopes; invalidate readiness when dependencies are actually released. |
| 2 | [Tracked image import inventory](image-import-inventory.json): 200 mode-0 and 94 mode-1 PNG/JPEG import configurations. | Review asset roles, dimensions, mipmaps and exported formats. These files do not describe every embedded GLB texture or prove wasted memory. Do not bulk-convert UI images. |

Both warmers mark entries done before their work finishes. That is a lifecycle risk to address with success/failure/cancellation state, not proof that a particular reported pause was caused by it. The skill warmer also temporarily changes global time scale and sound state: cancellation must restore those states reliably.

The current title path already starts asynchronous boot requests and releases its preload references later. Audio has reusable voice pools; `Geo` caches primitive meshes; effect shadow lights already have a cap of two in [`Fx.effect_shadow`](../../scripts/fx.gd#L11); UI has [`warm_windows`](../../scripts/ui.gd#L2382). Keep these improvements. The opportunity is to put their scheduling, ownership, budgets and coverage under shared rules.

### Loading is only part of the problem

The repository's [November 5 measurements](../nightly/perf/runs/2026-11-05.md) and [work log](../nightly/nights/2026-11-05-perf.md) record meaningful gains from preload/warm work, and significant GPU costs from grass, shadows and antialiasing. These are **historical measurements reported by the project**, not rerun here. GPU ablation numbers overlap and must not be added as independent savings.

A prepared spell can still draw too many transparent pixels, lights and shadow passes on every frame. After loading fixes, sustained combat needs a separate rendering budget and CPU profile. Maintain readable gameplay telegraphs; prioritize cheaper equivalent rendering and cosmetic detail scaling, rather than changing combat rules.

Texture file size is also different from runtime memory. Godot's lossless/lossy disk compression does not provide the same memory reduction as GPU compression; mipmaps and platform formats matter. Evaluate representative large 3D textures with exported-build memory and screenshot comparisons. Compression may change appearance even at unchanged resolution. [Godot 4.3 image import](https://docs.godotengine.org/en/4.3/tutorials/assets_pipeline/importing_images.html)

## Proposed system

```text
Content catalogue (zone + monsters + party skills + UI)
        |
        v
Request resources -> wait for ready -> assemble in small batches
        |                                      |
        |                                      v
  scoped residency                    rehearse required draw recipes
        |                                      |
        +-------------------------------> ready for play
                                               |
                                    retire owners / release scope

Every stage reports timings, failures, cache misses and retained resources.
```

### 1. One catalogue and one asset-access boundary

Each content entry declares required assets, dependent entries, possible summons/delayed effects, warm recipe IDs and lifetime scope. Existing `Data` registries remain authoritative for content; avoid creating a competing list of available monsters or activities.

Generate dependency closure from declared entries and imported resource dependencies, then compare it with observed runtime accesses. Static scanning catches obvious bypasses; it cannot infer arbitrary procedural code, string-built paths or every conditional effect. A new effect still needs a declaration/recipe, with tests making omissions visible.

An illustrative API is `request_scope(id)`, `await_ready(handle)`, `get_ready(path, handle)` and `release_scope(handle)`. It wraps existing loaders and cache facilities. During play, `get_ready` does not secretly perform expensive synchronous loading: required missing content triggers an explicit preparation/recovery path; optional decoration may use a logged fallback. Errors, timeouts and cancellation are first-class states.

Start instrumentation and warnings before enforcing rules. Keep reviewed exceptions for boot, test tools and unavoidable synchronous boundaries. Do not replace every `load` with a cache lookup and call the problem solved.

### 2. One loading coordinator

Split transition timing into retiring old content, resource readiness, terrain/props, navigation/collisions, grass, monster construction, minimap, visual preparation and final activation. Existing full-zone timing cannot tell which phase dominates.

Pure data generation may run on workers using isolated inputs. Live scene creation/attachment is performed in measured batches on the main thread. Initially experiment with a small per-frame construction budget, then tune it on the target machine. One individual expensive operation can exceed that budget; yielding after an oversized task does not make it incremental.

Cancellation uses a transition generation ID: stale completions cannot attach to a replacement world. Avoid holding both complete worlds in memory by default. Prepare dependencies early, overlap only within a measured memory limit, and retire old nodes incrementally where behavior allows.

### 3. One visual-preparation registry

Adapt `SkillWarm`, `MonsterWarm` and UI warming into recipes. A recipe describes representative mesh/material/pass combinations and delayed stages; completion is recorded only after success. Keys include relevant content revision, renderer/preset and variant context, rather than class name alone.

Prepare local and joining players' required effects during admission or ahead of first use. A graphics preset change also schedules affected preparation. Neither should invoke the existing large global-time-scale warm-up blindly in the middle of active combat. Separate a safe visual-only rehearsal context from live simulation.

Godot 4.3 rehearsal cannot guarantee coverage of every driver pipeline. Record first-use misses and extend representative tests. Keep headless servers out of GPU preparation entirely.

### 4. Bounded residency and reusable work

Use small core, current-zone/adjacent-zone, and active-party scopes. Share immutable resources across scopes and release only when no owner needs them. Distinguish asset residency, instantiated objects and graphics preparation; they are three different kinds of reuse.

Measure memory before choosing capacity. On unified-memory hardware, do not add overlapping RSS and graphics estimates into a fictitious total. Label unsupported counters. A cache filling and reaching a plateau is not the same as a leak; inspect repeated identical loops and retained references after retirement.

Pool only measured hot objects, with limits and reset contracts. Reuse material/shader resources without accidentally sharing mutable per-instance parameters. For a spatial enemy index, validate spawn/death, teleport, moving cell boundaries, large radii and multiplayer authority against the old query results before replacing the implementation.

### 5. Performance becomes a content acceptance rule

A new spell/monster/zone supplies its dependencies, warm recipe where needed, representative scenario and budget classification. CI checks declarations and access exceptions; a real-renderer benchmark job checks frame time and memory. This makes omissions discoverable as content grows; it does not promise automatic optimization of arbitrary new code.

Use cheap structural checks on each change, targeted performance runs for affected content, and a broader scheduled sweep. Do not run the entire all-class/all-zone matrix on every text change.

## Implementation sequence and proof required

1. **Repair measurement first.** Add phase spans and asset miss counters; require complete scenario sets and error-free execution; retain three runs and report median plus range. Establish new baselines before claiming improvement.
2. **Complete one vertical slice.** Use title → camp → moor → busy fight → return, including a newly joining class. Integrate scoped requests, readiness and existing warmers here. Show reduced cold-event stalls without shifting them into a longer unexplained loading pause or leaking memory.
3. **Chunk the measured loading bottleneck.** Change the largest measured construction phase first, preserving deterministic world layout, collisions and services. Compare seed-matched screenshots and gameplay traversal as well as timing.
4. **Address sustained fight cost.** Profile CPU queries and GPU passes separately. Trial the spatial index, resource reuse/pools and visual budgets only where evidence supports them; compare one change at a time.
5. **Expand catalogue and gates.** Cover all registered classes, acts, special zones, waves, Battlegrounds and PvP Arena; run Low/Medium/High, delayed summons, new party members, preset changes and repeated travel. Add a 30-minute fixed-loop memory soak and targeted import-format experiments.

The brief's thresholds are useful proposed acceptance targets, not proven outcomes: first-event frame <50 ms, fight p99 ≤33 ms and worst ≤80 ms, no >100 ms combat stall, warm/cold transitions ≤3/5 seconds, and <5% memory growth after the first repeat loop. Tie each to named hardware, resolution and workload. A 33 ms p99 still allows roughly 30 FPS at the tail; a loading frame of 250 ms is visibly frozen. Report both total wait and loading-screen responsiveness, and distinguish a 60 FPS goal from an interim acceptance threshold.

Define **cold** precisely: fresh process, cold application residency, or cold shader/pipeline cache are different experiments. Filesystem/driver caches may remain warm. Use isolated test profiles/cache locations where supported; never erase another developer's caches to manufacture a cold run.

Capture deterministic seed/input, revision, exported/source build, renderer, preset, physical resolution, frame cap, hardware, cache condition and background load. Keep CPU and GPU samples aligned and do not add overlapping timings. Use timeouts and isolated saves. Baseline known failing tests on the same revision; do not adopt the brief's claimed pre-existing failures without reproduction.

The existing fight harness also periodically walks the whole world tree for counts, has randomized spawn placement, and explicitly warms its added party members. Account for measurement overhead, fix the seed and add a truly unprepared late-join case. The existing KPI excludes loading/settling from normal frame statistics, so it needs a separate transition report. Its older `arena` scenario refers to Aurelia's arena content and must not stand in for new PvP Arena coverage.

## Decision

Build a shared preparation/lifetime/measurement system around the good work already present. Prioritize observable misses and a single end-to-end slice before a broad mechanical rewrite. No database-style infrastructure purchase, wholesale ECS conversion, engine upgrade, blanket texture reduction, or promise to eliminate every shader stall is justified by this audit.
