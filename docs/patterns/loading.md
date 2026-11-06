# Loading and first-time costs

**Goal:** nothing freezes the game the first time it appears: no loading from disk and no shader compiling while
the player is playing. Measured budget: no first-occurrence frame over **50 ms** on the Mac mini at High (a normal
frame is ~18 ms).

## The rules

1. **Declare preparation and ownership through `ContentCatalog` + `ResCache`.** Before activating a screen,
   zone or combat family, call `prepare(scope, paths)`, await `wait_ready`, and release that scope when its owner
   leaves. Requests share Godot's resident resource; ownership determines retention. `get_res`/`inst` remain
   transitional fallbacks, with per-path synchronous misses reported and rejected by performance checks.
   New content in a declared family is discovered in source and exported packs; unusual dynamic paths must
   be declared explicitly. See [the shared implementation](../perf/IMPLEMENTATION.md).
2. **Never create a `Shader` per cast or per spawn.** Make it once and keep it in a `static var`:
   `if _sh == null: _sh = Shader.new(); _sh.code = ...`. Each fresh Shader compiles again and creates new GPU
   pipelines.
3. **Warm what will first appear during play under the loading screen.** First-use GPU preparation can remain after a
   resource loads, so exercise the actual rendered variant; building it unseen is not enough. A shader is also freed
   with its last material, so keep the materials (`SkillWarm.keep`). The warm-ups that exist:
   - `SkillWarm` (`scripts/skill_warm.gd`): prepared class skill effects (current class in solo, all classes online), replayed on puppets from
     recorded events (`SkillWarmData`, re-recorded by `tools/skill_warm_capture.gd` after a skill's effects change).
   - `MonsterWarm` (`scripts/monster_warm.gd`): every monster kind that can still turn up in the zone. A new
     place that spawns monsters mid-zone needs its kinds added to `MonsterWarm.kinds`.
   - `UI.warm_windows`: the game's windows and the character sheet's portrait.
4. **Load resources on the shared worker; assemble scenes on the main thread.** `Game.load_zone` prepares
   catalog roots and recorded zone paths, constructs the world, then prepares visuals before enabling play.
   A loaded file is not an instantiated scene or a compiled GPU pipeline. Terrain rows and grass use the shared incremental job path. Forest/camp/fern loops use
   cooperative checkpoints; mesh uploads and other atomic builder work still need measurement. Boot preparation also keeps
   `Game._busy` true until the first world is ready. Dedicated servers skip client presentation preparation.
5. **Reuse derived data with the same lifetime.** `ResCache.mesh_parts(path)` extracts immutable mesh/local-offset
   recipes once per owned scene; vial and vat shatters create only their live debris nodes on subsequent bursts.
   Callers must not mutate recipes. Releasing the final owner retires the derived cache too; active consumers
   retain their own references. This is not a general pool of live nodes or a change to particle quality.
6. **Shadows:** a `discard` in a material runs in every shadow cascade. Static props cast from depth-only twins
   (`Props.shadow_twins`, `Flora.shadow_twin`).

## Measuring

See [measuring.md](measuring.md): `tools/app_hitch_audit.gd` (first times across the game), `tools/stress_fight.gd`
(a big fight), `tools/fx_bench.gd` (each effect), `--fx-timing`.

## Lifetimes and open work

Opening a solo world to friends uses `Game.prepare_host_presentation`; it reuses the combat scope without
rebuilding the world. Return to title releases combat/warm-only references. Some legacy caches remain
session-long; ownership release does not free resources still held by live nodes.

Use `SurfaceMaterials.assign(instance, surface, material)` for surface overrides; custom mesh scripts inherit
`SurfaceMaterials`. It clears overrides before deletion to avoid stale material handles with cached meshes
(Godot #85817), without copying the meshes. The lifecycle test exercises retention and release.

See [coverage and remaining work](../perf/COVERAGE.md). Terrain and grass assembly are incremental; the PvP forest and ferns also yield between batches.
Use `await world.scatter_grass` and await yielding builders: CI flags bypasses of these APIs. Online
roster-specific preparation, remaining atomic construction and long-session memory still need measured work.
