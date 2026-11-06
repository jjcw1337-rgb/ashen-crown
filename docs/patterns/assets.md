# Making assets: Meshy → Blender → Godot

**Goal:** everything new that is seen in the game is a real made asset (Meshy art, a Blender-prepared model, a
simulated effect, a recorded sound), judged in the game's own renderer, and cheap to draw. Placeholder primitives,
painted-on flames and recoloured generic bursts are not finished work. This page is the route; the detailed
recipes it links are the source of truth.

## The route

1. **Concept (Meshy 2D, ~6 credits a take).** `meshy.py draw "<prompt>" -o <out>` or `meshy.py edit <ref.png>
   "<change>" --ref <more.png>`. For anything an admin will choose between (art, sound, music), make **three takes**
   and let them pick (jj's rule). Character sheets: full body, symmetrical A-pose, plain grey background, even light.
2. **Model (Meshy image-to-3D ~30 credits; text-to-3D ~10).** Text-to-3D is a coin toss beyond simple objects: use
   concept → image-to-3D for anything with a shape that matters. Look at the four turnaround renders before going on.
3. **Prepare in Blender (headless, local).** Pick the script for the kind of thing, and keep the editable `.blend` in
   `~/Documents/Blender/Game Factory/sources/` (never inside the project); export `.glb` into `assets/models/`.
   - Props: `tools/blender/prep_prop.py` (size, axis, triangles, texture size); repeated or LOD-worthy pieces
     re-baked onto clean UVs with `tools/blender/camp/rebake_prop.py` (Meshy's own UVs leave the importer no LODs).
   - Characters and heroes: Meshy auto-rig + library clips, then a `prep_<id>_mocap.py` (copy Doug's), following
     `docs/character_workflow.md` step by step (gates at every step).
   - Monsters: `tools/blender/act1/prep_monster.py` then `rig_monster.py` (+ `layout_to_gd.py`); four-legged:
     `act1/rig_quadruped.py` on the lion's skeleton; NPCs: `tools/blender/prep_npc.py`.
   - Check a prepared model beside a man-sized post: `tools/blender/prop_sheet.py` (prints sizes too).
4. **Effects.** Fire, smoke, fog, liquid and ice are simulations (Mantaflow/FLIP in Blender, rendered to flipbooks,
   packed by `tools/fx_flipbook.py` / `tools/fx_smokebook.py` / `tools/flipbook_pack.py`), and broken things are
   real fractured pieces (`tools/blender/fx/fracture_rock.py`). The bar is in [effects.md](effects.md); each class
   has its own visual language; effects are events (`effects.md`).
5. **2D art in the UI.** Skill, talent, item and gem icons are Meshy-painted 3x3 grids cut by
   `tools/skill_icons.py` / `tools/talent_icons.py` (one grid ≈ 6 credits; palette per class); ground paintings and
   decals by `game/heroes/plague/build/ground_decal.py`; tiling textures by `make_tile_textures.py`.
6. **Sound.** ElevenLabs through `tools/audio/` (spec → candidates → score → a human picks → `build_sfx.py`); never
   synthesized.
7. **Import and look.** `godot --headless --editor --quit-after 2000`, then screenshots or frame clips in the game
   renderer from the game camera (each feature has a `*_shots.gd` / `*_clip.gd` tool; Forward+ with
   `--rendering-driver vulkan` when the look depends on it). Look at every frame you claim is good. Judge candidates
   in the game, not in model sheets.

## Performance rules for anything new (see `loading.md`, `measuring.md`)

- **Budgets:** props ≤ 10k triangles with 1k textures (pieces repeated many times ~12k or less); monsters ~20k
  (bosses 30k, 2k textures); heroes 50–60k. Textures import as lossy WebP q0.9 with mipmaps (UI and cut-outs lossless).
- **Load once:** models and textures used during play through `ResCache`; one cached `Shader` per effect kind, never
  one per cast or spawn.
- **Warm it:** re-record `SkillWarmData` (`tools/skill_warm_capture.gd`) after a skill's effects change; add new
  mid-zone monster kinds to `MonsterWarm.kinds`; re-record a zone's preload list (`--preload-record`,
  `tools/zone_preload_gen.py`) when it gains models.
- **Draw cheaply:** repeated things through `World.mm_chunked` / `Props.multimesh` (never one map-wide MultiMesh);
  static props cast shadows from depth-only twins (`Props.shadow_twins`, foliage `Flora.shadow_twin`); effect lights
  with shadows only through `Fx.effect_shadow`; tall props keep the see-through near the hero (`Props.see_through`).
- **Prove it:** `bash tools/skill_perf.sh <class> <skill>` for every new or redone skill; the KPI suite before and
  after anything that changes a zone (`--kpi`, slower = not shipped); dedicated servers never need pixels or mesh
  surfaces (`servers.md`).

## Spending and coordination

- Meshy and ElevenLabs use the Game Factory credentials through `/Users/blaine/dev/game-factory-codex/services.py`
  (`meshy check` shows the live balance). Either admin's request covers existing credits; purchases need an explicit
  spending request.
- Hold the `asset-budget` claim while submitting paid jobs, record each job's handle, and resume a pending job
  instead of paying for it twice. Hold `blender` only for the shared GUI scene; headless Blender on your own files
  needs no claim.
- A downloaded model (Sketchfab, Poly Haven) needs its URL, author, licence and attribution recorded beside it before
  it goes in the game.
