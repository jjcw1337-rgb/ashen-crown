# Loading and first-time costs

**Goal:** nothing freezes the game the first time it appears: no loading from disk and no shader compiling while
the player is playing, and no frozen loading screen. Measured budget: no first-occurrence frame over **50 ms** on the
Mac at High (a normal frame is ~17 ms).

**Nothing is built that the player isn't going to.** The title has no world behind it (Blaine, 2026-11-06: the camp
built there at every start froze the screen ~1.3 s and was built again on Enter World): the boot loads only the
title's models during the intro, and each choice on the title (a lobby, Sandbox, a character's world) loads its own
zone; going back to the title unloads the world (`Game.unload_world`). Tool scripts still get the camp behind the
title (`Game._harness_camp`); `-- --real-boot` gives them the real start (`tools/boot_flow_test.gd`).

Every zone change follows the same order, under the loading screen:

1. **Load**: the files the place needs, on the loader's threads.
2. **Build**: the world, from memory.
3. **Warm**: draw once, unseen, what will first appear during play.
4. **Show**.

## The rules

1. **One loader: `ResCache`** (`scripts/res_cache.gd`). Nothing else calls `ResourceLoader.load_threaded_request`.
   - **Ahead of time:** `ResCache.prepare(scope, paths)` reads the files on Godot's threaded loader (many at once:
     `tools/load_bench.gd` measured the camp's 163 files at 1.2 s, against 3.1 s frozen on the main thread and 11 s on
     a single worker thread), `ResCache.wait_ready(tree, scope)` awaits them a frame at a time so the screen keeps
     drawing, and `ResCache.release(scope)` lets them go when the place is left. Scopes today: `"boot"` (the title's
     models and the camp's list, during the intro) and one per zone (`Game.load_zone`: its recorded list, then its
     monsters' models).
   - **At the moment of use:** `ResCache.inst(path)` for a scene, `ResCache.get_res(path)` for anything else. A
     prepared file returns at once; anything else loads on the main thread (counted in `ResCache.misses`) and is kept
     for the session: Godot keeps a resource only while something references it, so a bare `load()` in an effect
     re-read its .glb on every cast (each Archer arrow 14-17 ms).
2. **Lists are exact, never whole folders.** A zone's list is recorded from the built zone
   (`-- --shot x.png --zone <zone> --preload-record`, then `python3 tools/zone_preload_gen.py` writes
   `ZonePreloadData`); re-record after a zone gains or loses models (a stale list only costs speed). A folder pulls in
   files nobody uses, and their video memory.
3. **Never create a `Shader` per cast or per spawn.** Make it once and keep it in a `static var`. Each fresh Shader
   compiles again and creates new GPU pipelines.
4. **Warm what will first appear during play under the loading screen.** Godot compiles GPU pipelines the first time
   something is drawn on camera, so building it unseen is not enough: it has to be drawn. A shader is also freed with
   its last material, so keep the materials (`SkillWarm.keep`). The warm-ups:
   - `SkillWarm` (`scripts/skill_warm.gd`): the party's classes' skill effects, replayed on hidden puppets from
     recorded events (`SkillWarmData`, re-recorded by `tools/skill_warm_capture.gd` after a skill's effects change),
     in fast-forward.
   - `MonsterWarm` (`scripts/monster_warm.gd`): every monster kind that can still turn up in the zone. A new place
     that spawns monsters mid-zone needs its kinds added to `MonsterWarm.kinds`.
   - `UI.warm_windows`: the game's windows and the character sheet's portrait.
5. **Shadows:** a `discard` in a material runs in every shadow cascade. Static props cast from depth-only twins
   (`Props.shadow_twins`, `Flora.shadow_twin`).

## Measuring

See [measuring.md](measuring.md): `tools/load_bench.gd` (loading strategies on the same files), `--kpi <scenario>`
(`load_ms`), `tools/app_hitch_audit.gd` (first times across the game), `tools/stress_fight.gd` (a big fight),
`tools/fx_bench.gd` (each effect), `--fx-timing`.

## Open work (docs/PLAN.md)

Building a zone still runs in one go on the main thread under its loading screen (the camp ~0.9 s, of which the grand
waypoint 0.5 s); builders can yield a little per frame if a zone's loading screen needs to keep animating.
