# Ashen Crown: visual quality audit and overhaul

Nov 1-2, 2026 · on `test-visual-overhaul` (from `staging` 1fb8d09) · jj's brief: a complete visual overhaul toward
Diablo IV / Path of Exile 2 / Guild Wars 2, every asset inspected, Meshy and Blender with no limit, a measured
baseline first.

**Status (Nov 2, ~midnight):** stage 1 (rendering foundation), stage 2 (the knight's holy skill effects, the weapon
trail and hit flash every class uses, the rim light in every zone, steel that reflects on the armoured knight, detail
normal maps for 27 models) and stage 3 (Meshy models for Aurelius, the arena gladiators and the Ashen King) are done,
tested headless and committed on `test-visual-overhaul`. Nothing is approved yet: every change still needs jj's look
on a real GPU (the preview build). Meshy spent so far: 108 of the 2,614 monthly credits.

## Summary

- **The camp drew 150 M triangles a frame at High; it now draws 11.7 M** (draw calls 3,891 → 2,841). Two causes:
  the character sheet's portrait, a hidden 61-pixel view, re-rendered the whole world and its shadow maps every
  frame (66 M), and the camp's trees and palisade were single multimeshes the size of the map, so nothing could be
  culled and every tree went into every shadow pass, including all six faces of each shadowed lantern. The Mac's
  nightly benchmark had the camp at 12.4 fps.
- **No Meshy model has LODs.** Godot's importer can't simplify a mesh whose UV atlas is thousands of islands
  (median 1,323 per model, 62% of the texture used): nearly every vertex is a seam. Every monster, prop and tree
  draws in full at any distance. Re-unwrapping the existing (decimated) meshes doesn't fix it; rebuilding from
  Meshy's full-detail output through the existing re-bake pipeline (voxel remesh, clean unwrap, bake) does.
- **27 models (29%) ship with a normal map that adds nothing** (mean tilt ~1°), so their surfaces shade like smooth
  plastic: King Grubb, the gnome Warlock, the zombie, fallen, goblin guard, bone archer, all three Hollow Sloths,
  the fort's buildings, the sloth lairs' props, the materials and the Plague Doctor's items. New detail normal maps
  are generated (stage 2).
- **Two of the three act bosses had no model.** Aurelius (A2) and the Ashen King (A3), and A2's gladiators, were
  the code-built humanoid (stage 3: now Meshy models on the game's rig, see section 1c). The knight's skills were
  the generic effects recoloured gold (stage 2: their own holy visual language, section 1b).
- **The armoured knight read as a black blob** because Meshy painted his plate at 5% reflectance (a metal's colour
  is its reflectance). Lifted to dark steel where the metal map says metal; cloth untouched (stage 2).
- **Every class's swing drew a flat white sheet and every struck foe turned into a white paper cut-out** (the
  weapon trail at 55-90% opacity across its whole width; the hit flash flat and unshaded). Both redone (stage 2).
- The Meshy heroes, monsters, NPCs and camp stalls are good designs (mostly 3-4 of 5). Their common weaknesses are
  value (near-black albedo: the median colour map is 0.24, the armoured knight 0.20, the dragons 0.16) and reading
  against dark ground, which the lighting has to solve.

## How it was measured

Everything here can be re-run; the tools are in `tools/visual_audit/`.

| Tool | What it gives |
|---|---|
| `glb_audit.py` | Every model: triangles, textures (size, format, maps), joints, clips, bytes; every loose texture |
| `uv_report.py` | UV islands and coverage, colour-map brightness, normal-map strength (mean tilt), roughness |
| `scene_census.gd` | Every zone built as the game builds it: geometry by mesh, instances, shadow casters, lights, particles |
| `frame_stats.gd` | Draw calls, primitives and objects per frame for the scene and the shadow passes, per viewport, VRAM, screenshots |
| `model_sheet.py`, `contact_sheet.py` | Blender sheets of all 101 models (two views and a clay view) with their stats |
| `normals_from_albedo.py` | Detail normal maps for models whose Meshy normal map is flat (stage 2) |
| `checklist.py` | `checklist.csv`: every asset's measurements, scores, priority, actions and status |

The cloud workspace has no GPU, but Mesa's software Vulkan (lavapipe) runs Godot's real Forward+ renderer, so the
renders have the volumetric fog, SSAO and SSIL the old OpenGL screenshots lacked, and draw-call and primitive counts
are exact: the camp's 149.9 M here matches the Mac's 152.5 M. Frame times in the cloud mean nothing; the fps effect
must be measured on real hardware (`--kpi`, the nightly benchmark). Brightness should still be confirmed on jj's
PC before grading decisions are final.

## 1. Performance: before and after (stage 1)

High preset, 1600x900, hero at each zone's start, average of 3 frames after 12 to settle (`frame_stats.gd --fast`:
screen-space effects off, which changes no geometry counts). Primitives are triangles drawn in all passes.

<!-- perf:q2 -->
| Zone | Draw calls before → after | Primitives before → after | of which shadows | VRAM (MB) |
|---|---|---|---|---|
| Act I camp | 3,967 → **2,856** | 149.9 M → **11.9 M** (-92%) | 78.3 M → 8.7 M | 1232 → 1221 |
| A2 Imperial Road | 2,938 → **1,877** | 10.8 M → **4.6 M** (-58%) | 3.0 M → 3.1 M | 1151 → 1141 |
| A2 camp | 3,013 → **2,679** | 27.4 M → **3.7 M** (-87%) | 16.1 M → 2.5 M | 875 → 865 |

Still to measure: Cairnfell Moor, Grubb's Fort, Mournwater Coast, A2 Aurelia + arena, Battlegrounds crypt.
<!-- /perf:q2 -->

Medium preset (the default on integrated GPUs):

<!-- perf:q1 -->
| Zone | Draw calls before → after | Primitives before → after |
|---|---|---|

Still to measure: Act I camp, Cairnfell Moor, Grubb's Fort, Mournwater Coast, A2 Imperial Road, A2 camp, A2 Aurelia + arena, Battlegrounds crypt.
<!-- /perf:q1 -->

What changed (commit "Visual overhaul stage 1"):

1. **The hidden portrait.** `UI.sheet_view` was `UPDATE_WHEN_PARENT_VISIBLE`, which asks the parent *viewport* (the
   screen, always visible), so the closed character sheet rendered the scene and its shadows every frame in every
   zone. Now it renders only while the sheet is open, and with no omni shadow maps of its own.
2. **The camp's multimeshes** (palisade, rune stones, inner oaks, 340 forest trees) are chunked with
   `World.mm_chunked`, like every other zone's (trees get the moor's 90 m draw distance). The A2/A3 town's pines too.
3. **Sun shadow cascades fitted to the camera** (`Game._fit_shadows`). The camera never sees closer than ~10 m or
   farther than ~35 m (45 m zoomed out); Godot's default splits over 70 m spent two of four cascades on empty air in
   front of the lens and one past the top of the screen. Texel size where the hero stands: High 2.5 → 2.0 cm,
   Ultra 1.6 → 1.0 cm, Low/Medium 10.9 → 4.8 cm (two splits). The reach follows the zoom; sailing keeps the old split.
4. **Fire shadows under the budget.** Shadow-casting fires join `Grade`'s shadow group (nearest 1/2/4/6 by preset);
   the fort had 12 always-on shadowed omni lights (72 extra shadow passes).
5. **Ultra's LOD threshold** was 0 (LODs off); now half a pixel.

## 1b. Stage 2: the free visual work

| Change | Where | What it fixes |
|---|---|---|
| **Holy visual language for the knight** | `scripts/holy_fx.gd` (`HolyFx`), `knight_fx.gd` | Holy Nova, Battle Cry and Charge were `Fx.ring/burst/pillar` in gold. Now: a sacred seal drawn on the ground (rings, 48 ticks, 16 rays, four crosses), a gold-and-white holy fire ring, a streaked light column, a screen-space shockwave (Forward+ only), sunbursts, rising motes and a glinting trail behind the charge. Compiled once per zone (`HolyFx.warm`); co-op events unchanged |
| **Weapon trail** (every class) | `Hero.TRAIL_SHADER` | Additive at 55-90% across its whole width: a flat white band in Forward+. Now a hot thin edge at the tip, a streaked body thinning toward the hilt, a quadratic tail |
| **Hit flash** (every monster) | `Enemy.FLASH_SHADER`, `Enemy.flash_color` | Flat unshaded white at 60% turned the struck into cut-outs. Now rim-weighted (the facing middle under half as bright) and fading over its 0.12 s; Molten Fists' molten flash and Drain Life's coloured one go through `flash_color` |
| **Rim light in every zone** | `Grade.RIMS`, `Game._rim_kind` | Dusk, inside, day and ash rims (the camp keeps its own), so the hero reads on dark ground |
| **Steel that reflects** | `tools/visual_audit/metal_lift.py` | The armoured knight's plate (both bodies), the Fallen Reaver's iron and the Pestilent Trap: metal reflectance 0.26 → 0.50 (knight) / 0.42, metal roughness -0.1 |
| **Detail normal maps** | `tools/visual_audit/normals_from_albedo.py` | 27 models whose Meshy normal map was flat (mean tilt ~1°) get island-aware detail at 7°; the two round bottles re-shaded (`smooth_normals.py`) |

Tried and **not adopted**: a procedural Blender oak (`tools/blender/trees/oak_gen.py`: bark from a procedural
material baked to colour/normal/roughness, one UV island per branch, LOD-friendly). Compared in the game renderer
with the leaf clusters the game adds (`tools/visual_audit/oak_compare.gd`), the Meshy oaks win: in play their shard
canopy is hidden under the leaves and they read as full, rooted oaks; the procedural ones looked sparse and oversized.
The oaks drop from P1 to P2 (a Meshy regeneration with a modelled canopy, when the rest is done).

## 1c. Stage 3: Meshy rebuilds

| Asset | Pipeline | Result |
|---|---|---|
| Aurelius, Champion of the Arena (A2 boss) | `meshy.py draw` concept → `image` (A-pose, 60k) → `act1/prep_monster.py` (30k) → `act1/rig_monster.py` (13 joints, `crotch` hint: his skirt of strips hangs between the legs) → `layout_to_gd.py champion` | Lion-faced bronze cuirass and pauldron, crimson crest and pteruges; 2K textures. Kept out of the patron's box he fights under |
| Gladiator (A2 arena) | the same, 20k, 1K | Bronze helm, manica, loincloth, greaves; joins the arena's crowd cards by itself |
| The Ashen King (A3 boss) | the same, 30k, 2K, + `emission_from_albedo.py` | Charred plate whose painted ember cracks and eyes now glow (an emission map, strength 4); skull face, spiked crown, ermine mantle. `Data.ENEMIES["ashen_king"]` gets `"mesh"` (the code-built king stays as the fallback) |

Each costs 6 credits (concept) + 30 (model): 108 credits for the three. `a2_arena_test` (the whole games) and `a3_test`
(the Ashen King's fight and drop) pass with them.

## 2. Systemic findings, ranked

| # | Finding | Evidence | Status |
|---|---|---|---|
| S1 | Character-sheet portrait renders the world every frame | 66 M of the camp's 150 M primitives | Fixed (stage 1) |
| S2 | Camp multimeshes unchunked: unculled in every pass | 78 M shadow primitives in the camp | Fixed (stage 1) |
| S3 | No Meshy model has LODs: shattered UV atlases block simplification | 0 LODs from Godot's importer; median 1,323 islands, 62% coverage | Rebuild via the re-bake pipeline (roadmap) |
| S4 | Shadow cascades not fitted to the isometric camera | One 2048 cascade over the whole view on High, 11 cm texels on Low/Medium | Fixed (stage 1) |
| S5 | Flat normal maps on 27 models | Mean tilt < 3° (median of the rest 7.3°) | Detail normals generated (stage 2), testing |
| S6 | Two act bosses and the gladiators have no model | Data.ENEMIES `"mesh"` names with no glb | **Meshy models (stage 3)**, testing |
| S7 | Oak and pine models are crumpled low-poly shards | Model sheets; on screen hundreds of times | In play the leaf clusters hide it (oak_compare.gd); a procedural rebuild lost. P2 |
| S8 | Characters read as dark blobs on dark ground | Colour maps 0.14-0.24; camp frame median luminance 0.12, p90 0.19; the knight's plate at 5% reflectance | Rim light in every zone, metal lift on the knight (stage 2); grading needs real-GPU review |
| S9 | Generic recoloured skill effects | Knight Nova/Cry/Charge, Warlock, shared skills, most Wraith effects use `Fx.burst/ring/pillar` | Knight done (`HolyFx`, stage 2); the rest P2 |
| S10 | Always-on fire shadows outside the budget | Fort: 12 shadowed omni lights | Fixed (stage 1) |
| S11 | Decimation facets on round props | Clay views: flask, mixture, items, lair rocks | Bottles re-shaded (stage 2); shard rocks need a rebuild |
| S12 | Model textures uncompressed in video memory | Lossy WebP decodes to RGBA8: 1.0-1.9 GB VRAM | Decision (below) |
| S13 | A2/A3 keep the old grass and code-built architecture | 15 M grass triangles on the Imperial Road; Roman.* boxes | Roadmap P2 |
| S14 | Ground is one procedural shader | No material textures or decals (camp plan phase 2 not started) | Roadmap P2 |

Measured and **not** a problem: texture gutters. Meshy fills the space between islands with averaged colour, so
mipmaps don't darken the models at a distance (`uv_report.py` dark@64: within ±1%). And the grass already has its
own two-LOD system and alpha-to-coverage with MSAA.

## 3. Rendering pipeline (Godot 4.3, Forward+)

| Setting | Low | Medium | High | Ultra | Assessment |
|---|---|---|---|---|---|
| Renderer | Forward+ (Vulkan); OpenGL "Safe Mode"; web = 4.5.1 GL, Medium max | | | | Right for the target. A single Godot version (4.5) would bring AgX and better shadows (camp plan phase 5) |
| Default | integrated GPU → Medium; discrete → High; RTX 30+/RX 6800+ → Ultra | | | | Sensible |
| Anti-aliasing | MSAA 2x | 2x | 4x | 8x | Grass uses alpha-to-coverage, so MSAA covers foliage. 8x on Ultra is costly with dense grass; 4x is the sweet spot. FSR2 native AA worth a real-GPU trial later |
| Sun shadow atlas, splits | 2048, 2 | 2048, 2 | 4096, 4 | 8192, 4 | **Splits now fitted** (S4); blend between cascades on High/Ultra |
| Soft shadow filter | low | low | high | ultra | Fine |
| Omni shadows | budget 1 | 2 | 4 | 6 | **All fire lights now in the budget** (S10) |
| SSAO | off | medium | medium | ultra | Fine (radius 1.2, intensity 2.2) |
| SSIL | off | off | medium | high | Fine |
| SSR | off | off | off | on | Few wet or polished surfaces; fine |
| Volumetric fog | off | off | 96x64 | 160x128 | Gives the mist; also lifts the blacks (S8) |
| SDFGI | off | off | off | on | Expensive for an isometric game lit mostly by moving lights; measure on real hardware before keeping it |
| Mesh LOD threshold | 1 px | 1 px | 1 px | **0.5 px** (was 0 = off) | Matters only once models have LODs (S3) |
| Tonemap | ACES, white 6, exposure 1.05-1.5 by zone | | | | No AgX in 4.3 |
| Grade | LUT + vignette + grain in the camp only (`Grade`), saturation/contrast elsewhere | | | | Every zone deserves a look (roadmap) |
| Reflections | sky; SSR on Ultra | | | | No reflection probes: metal armour reflects the dark sky and reads black. Probes near fires are a cheap win (roadmap) |
| Texture filtering | anisotropic 8x | | | | Fine |
| Texture compression | lossy WebP q0.9, decoded to RGBA8 in VRAM | | | | See below |

**Texture compression decision (for jj and Blaine).** The download went from 725 to 302 MiB by importing model
textures as lossy WebP, which the GPU holds uncompressed: 1.0-1.9 GB of VRAM. VRAM compression (BPTC/S3TC on
desktop) would cut that about 4x and lighten every texture fetch, but the .pck would grow by roughly the textures'
share again. Basis Universal sits between. Not changed; worth measuring before Act II's content lands.

## 4. Inventory

| Kind | Count | Notes |
|---|---|---|
| 3D models (.glb) | 101 | 8 hero bodies + statue, 3 dragons, 1 boss, 22 monsters, 6 NPCs, 18 camp, 5 fort, 5 isles, 1 boat, 6 lairs, 5 trees, 7 grass species, 4 title, 3 materials, 4 Plague Doctor props, bow, 3 arrows, debris. 2.04 M triangles, 290 MB |
| Loose textures | 191 | fx flipbooks 18, grass atlas 15, UI 26, talent icons 120, items 3, Plague dyes 5, ranger 4 |
| Code-built visuals | ~30 systems | terrain, roads, procedural trees/bushes/ferns, rocks, Roman architecture, small props, waypoint, ocean, weather, the humanoid body (3 bosses/elites and the unreachable legacy acts), sculpted goblins |
| Effects | 11 scripts | FireFx and ArrowFx/InfernalFx/DemonFx (custom shaders, flipbooks) vs KnightFx/WarlockFx/SharedFx/Fx (generic) |
| Animations | mocap heroes (14-27 clips), Meshy monsters code-posed on `Goblin.imported_rig`, Feral/NPCs/dragons with baked clips | |

The full list with every asset's numbers, scores, priority, actions and status is
[`checklist.csv`](checklist.csv) (132 rows).

## 5. Quality by category

Scores 1-5 against the D4/PoE2 bar at the game camera (detail per asset in the checklist).

| Category | Mean | What's good | What holds it back |
|---|---|---|---|
| Heroes (8) | 3.3 | Strong, distinct designs (demon, gnome, plague doctor, wraith); motion capture | Near-black albedo, weak or flat normals (gnome, armoured knight), no LODs, 45-70k tris |
| Bosses (3) | 2.5 | King Grubb | Aurelius and the Ashen King are code-built placeholders |
| Monsters (22) | 3.1 | Bear, Sloths, Ferals, Fallen variants | Flat normals (zombie, fallen, goblin guard, archer, sloths); gladiators missing; code-posed A-poses |
| NPCs (6) | 3.4 | Six distinct traders with clips | Dark; no LODs |
| Camp (18) | 3.2 | Stalls, gate, re-baked set pieces | Palisade and lantern are shard soups (512/256 px) |
| Fort, isles, lairs, title (20) | 3.2 | Solid Meshy architecture | Flat normals (fort, lairs); facets on rocks |
| Trees (5) | 2.6 | The dead tree | Oaks and old pine: crumpled shard canopies |
| Grass (7) | 3.9 | Living 3D grass with wind and touch | A2/A3 still on the old clumps |
| Environment (code) | 3.0 | Ocean, roads | Terrain shader without materials or decals, procedural pines/rocks/props, Roman boxes |
| Effects | 3.3 | Fire, Fire Arrow, the Demon | Knight, Warlock, shared skills, generic Fx |
| UI and screens | 3.6 | D4-style HUD and frames, the title | Character close-ups expose dark/flat textures |
| Rendering | 3.0 | Full Forward+ feature set, presets | Was the performance problem (fixed in part); grading, reflections |

## 6. Ranked roadmap

| # | Item | Why | Actions | Cost |
|---|---|---|---|---|
| 1 | ~~Aurelius, the gladiators, the Ashen King~~ **done (stage 3)** | Two act bosses and an elite were placeholders | Meshy concept → image-to-3D → Blender rig (`tools/blender/act1/rig_monster.py`) → `MeshyMonster.MODELS` | 108 credits |
| 2 | Oak trees (3) and the old pine | Shard canopies in model sheets, hidden in play | Re-judged in the game: fine for now; a procedural rebuild lost. Later: Meshy with a modelled canopy, LODs and impostors | ~36 credits each |
| 3 | ~~Knight skill effects (Nova, Battle Cry, Charge)~~ **done (stage 2)** | The default class looked generic | `HolyFx`: seal, holy fire ring, light column, shockwave, sunbursts, motes | Code |
| 4 | ~~Detail normals for the 27 flat models~~ **done (stage 2)** | Plastic shading | Generated, checked in a lineup, committed | Free |
| 5 | Hero readability | Dark heroes on dark ground | Rim light in every zone and the knight's steel (done); per-zone grade and reflection probes near fires (to do, real GPU) | Code |
| 6 | LODs for Meshy models | Monsters and props draw in full at any distance | Re-bake from Meshy's full-detail output (needs regeneration: the originals expired) | Credits per model |
| 7 | Camp lantern and palisade | Shard soups in the hub | Meshy + re-bake | ~72 credits |
| 8 | Warlock, shared and Wraith effects | Generic bursts and rings | Custom shaders and flipbooks | Code |
| 9 | Ground materials and decals | The largest area on screen | Camp plan phase 2 (tiling PBR sets, height blending, decals) | Code + textures |
| 10 | A2/A3 grass and Aurelia's architecture | Act II looks older than Act I | Living grass in A2/A3; Meshy Roman set pieces | Credits + code |
| 11 | Procedural pines, rocks, small props | Code-built next to Meshy | Meshy kits | Credits |
| 12 | Material items, Plague Doctor props, lair rocks | Facets and flat normals | Smooth normals / regenerate | Small |
| 13 | Texture compression | VRAM 1-1.9 GB | Decide download vs VRAM | Decision |

## 7. Meshy requirements

Each asset: a concept image (`meshy.py draw`, ~6 credits) matched to the game's palette and the existing design,
then image-to-3D (~30 credits), downloaded at full detail (results expire after 3 days), then Blender. Characters
keep their identity: the brief for each comes from its `Data.ENEMIES` look (colours, height, bulk, weapon) and its
role, so nothing comes back as generic armour.

| Asset | Brief | Pipeline after Meshy |
|---|---|---|
| Aurelius, Champion of the Arena | Towering arena champion (1.5x a man), gilded bronze muscle cuirass, crimson cape and loincloth, plumed helm, curved blade; the arena's undefeated star | `rig_monster.py` (A-pose, 13 joints), `layout_to_gd.py champion`, weapon grip |
| Gladiator | Bronze-armoured arena fighter, off-white tunic, one shoulder guard, scimitar; three looks by tint | as above |
| The Ashen King | Burned undead king in charred plate with a crown of black iron, embers glowing in the cracks, ash falling from him | as above + ember emission map |
| Oak x3, old pine | Gnarled oaks with readable bark and branch structure (leaves from the game's cards) | `prep_tree.py` + re-bake (clean UVs, LODs) |
| Camp lantern, palisade | Iron lantern with intact glass; sharpened log wall section | `rebake_prop.py` |

The key reached the cloud workspace on Nov 1 at 23:23 (kept in `~/.config/meshy/key`, never in the repo). The balance
was 2,614 monthly credits; stage 3 spent 108 (three concepts at 6, three models at 30). "Everything" (~100 models)
would be ~3,600, so the rest goes by the roadmap's order.

## 8. Blender requirements

- Rig new Meshy characters with the existing scripts (`act1/rig_monster.py`, `knight/rig_crusader_knight.py`),
  keeping joint names and layouts so `Goblin.imported_rig` and the animation code drive them unchanged.
- Re-bake every new Meshy model with `camp/rebake_prop.py` from its full-detail download: voxel remesh, clean
  unwrap, PNG normals, so the importer can make LODs (S3).
- Tried and dropped: re-unwrapping the repo's decimated meshes in place. Welded and smart-projected, the forge went
  from 2,692 islands to 5,716 (Meshy's surface is a crumpled soup); the originals are needed.
- Smooth-by-angle normals for faceted round props (flask, mixture, items) when they're regenerated.

## 9. Remaining problems and risks

- Everything is judged on the software renderer; brightness and the rim light's strength need jj's real-GPU look.
- The detail normal maps follow the colour map's detail, which can emboss painted patterns; checked on the zombie,
  to be checked in game on the heroes.
- Without regenerated sources, existing Meshy models can't get LODs; until then culling and draw distances carry
  the performance.
- The fps gain from stage 1 is measured in primitives and draw calls; the KPI on the Mac is the confirmation.

## 10. Production checklist

[`checklist.csv`](checklist.csv): every model and code-built system with its measurements (triangles, texture size,
UV islands and coverage, normal-map tilt, colour-map brightness), eight scores, the mean, priority (P1-P4), actions
(R rebuild, M Meshy, B Blender, T textures, S materials/shaders, A animation, O optimise) and its status, one of:
Not inspected, Inspected, Needs improvement, Being rebuilt, Blender refinement, Imported into Godot, In-game testing,
Approved. Regenerate it with `python3 tools/visual_audit/checklist.py build/visual_audit docs/visual/checklist.csv`
after re-running `glb_audit.py` and `uv_report.py`.
