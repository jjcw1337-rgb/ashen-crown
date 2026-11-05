# Loading and first-time costs

**Goal:** nothing freezes the game the first time it appears: no loading from disk and no shader compiling while
the player is playing. Measured budget: no first-occurrence frame over **50 ms** on the Mac mini at High (a normal
frame is ~18 ms).

## The rules

1. **Everything that can load during play goes through `ResCache`** (`scripts/res_cache.gd`): `ResCache.inst(path)`
   for a scene, `ResCache.get_res(path)` for anything else. Godot keeps a resource only while something references
   it, so a bare `load()` in an effect re-read its .glb on every cast (each Archer arrow 14-17 ms). `ResCache` holds
   it for the session. Monster bodies load through it too.
2. **Never create a `Shader` per cast or per spawn.** Make it once and keep it in a `static var`:
   `if _sh == null: _sh = Shader.new(); _sh.code = ...`. Each fresh Shader compiles again and creates new GPU
   pipelines.
3. **Warm what will first appear during play under the loading screen.** Godot 4.3 compiles GPU pipelines the first
   time something is drawn on camera, so building it unseen is not enough: it has to be drawn. A shader is also freed
   with its last material, so keep the materials (`SkillWarm.keep`). The warm-ups that exist:
   - `SkillWarm` (`scripts/skill_warm.gd`): every party class's skill effects, replayed on hidden puppets from
     recorded events (`SkillWarmData`, re-recorded by `tools/skill_warm_capture.gd` after a skill's effects change).
   - `MonsterWarm` (`scripts/monster_warm.gd`): every monster kind that can still turn up in the zone. A new
     place that spawns monsters mid-zone needs its kinds added to `MonsterWarm.kinds`.
   - `UI.warm_windows`: the game's windows and the character sheet's portrait.
4. **Load on worker threads before building.** `ZonePreload` (`scripts/zone_preload.gd`) requests a zone's .glb
   files as the loading screen goes up, and the boot preloads the title's and the camp's
   (`Game._boot_preload`). Re-record the zone lists (`--preload-record`, `tools/zone_preload_gen.py`) after a zone
   gains or loses models; a stale list only costs speed.
5. **Shadows:** a `discard` in a material runs in every shadow cascade. Static props cast from depth-only twins
   (`Props.shadow_twins`, `Flora.shadow_twin`).

## Measuring

See [measuring.md](measuring.md): `tools/app_hitch_audit.gd` (first times across the game), `tools/stress_fight.gd`
(a big fight), `tools/fx_bench.gd` (each effect), `--fx-timing`.

## Not covered yet (open work)

Monster spells and boss effects, Act II/III and the Battlegrounds/arena map loads, a cold first launch (empty shader
caches), memory over a long session, and machines other than the Mac mini. The budgets these must meet are in
[measuring.md](measuring.md).
