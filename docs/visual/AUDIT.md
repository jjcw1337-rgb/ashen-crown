# Ashen Crown: visual quality audit and overhaul

Nov 1-2, 2026 · on `test-visual-overhaul` (from `staging` 1fb8d09) · jj's brief: a complete visual overhaul toward
Diablo IV / Path of Exile 2 / Guild Wars 2, every asset inspected, Meshy and Blender with no limit, a measured
baseline first.

**Status (Nov 2, early morning):** stage 1 (rendering foundation), stage 2 (the knight's holy skill effects, the hit
flash every monster uses, the rim light in every zone, steel that reflects on the armoured knight, detail normal maps
for 27 models), stage 3 (Meshy models for Aurelius, the arena gladiators and the Ashen King, the camp's lantern and
palisade, the shared skills', Warlock's and Wraith's own effects, the monsters' heavy blows) and stage 4 (worn
flagstones, Meshy rocks, kerbstones and clutter, A2's living grass, new telegraphs, the Plague Doctor's own effects
and the last generic accents of the Demon, Warlock and Archer) are done, tested headless and committed on
`test-visual-overhaul` (merged with staging's 21 newer commits). Nothing is approved yet: every change still needs
jj's look on a real GPU (the preview build). Meshy spent by the overhaul: 1,008 credits (balance 1,043).

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
  weapon trail at 55-90% opacity across its whole width; the hit flash flat and unshaded). The flash is redone
  (stage 2); the trail was fixed on staging the same night (00e1d19) and the branch takes that version.
- **Every hero skill now has shapes of its own** (stages 2-4): no class's skills use the generic soft-dot burst,
  ring or flash any more (they were the knight's, the Warlock's, the Wraith's, the Plague Doctor's and the shared
  skills' main look, and accents for the Demon and the Archer). The warnings on the ground are a rim and a sweeping
  fill instead of flat paint.
- **The ground and what lies on it** (stage 4): the cobbled roads are worn flagstones, every zone's rocks and the old
  roads' kerbs are Meshy granite, the crates, barrels and log piles Meshy models, and Acts II and III grow the
  living grass.
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
| `terrain_lab.gd` | A strip of road (flagstones, dirt, grass) under a sun from the game camera, without loading a zone: for judging the terrain shader in a minute |
| `skill_shots.gd`, `special_shots.gd` | Frames of any class's skills (a skill's own length with `skill:secs`) and of the monsters' heavy blows, from the game camera |
| `layout_dump.gd` | A zone's interactables, enemy spawns and obstacle footprints as World builds them, one per line, for diffing two builds |
| `fx_lab.gd` | The Plague Doctor's cloud or the Last Epidemic's dome on a strip of road at night with four figures, from the game camera, at set times, without loading a zone |

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
| **Weapon trail** (every class) | `Hero._trail_shader` (staging 00e1d19) | Additive at 55-90% across its whole width: a flat white band in Forward+. Fixed the same way on staging the same night (a hot edge at the tip, a soft body fading toward the hilt and with age, streaks, Catmull-Rom smoothing); the overhaul's own version was dropped in the merge for staging's |
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
| Camp lantern (hung all over the camp) | concept (its chain edited out, so it hangs from its ring) → image-to-3D → `camp/rebake_prop.py` (clean UVs, 2k tris, 512 px) | Intact glass and a riveted iron frame; was shattered glass shards and spikes (256 px) |
| Camp palisade (34 sections round the ring) | concept (a second one: the first had gaps between the logs) → image-to-3D → `rebake_prop.py` (5k tris, 1K) | Ten tight, mossy logs in two rope bands, unevenly sharpened; 415 UV islands instead of 1,323, so the importer can make LODs; 4.2 m tall (was 3.6) |

Also in stage 3, without Meshy: **the shared skills' own looks** (`scripts/elemental_fx.gd`, `ElementalFx`). Every
class can use Earthshatter, Frost Nova, Arc and War Cry, and they were the generic burst and ring in four colours. Now
Earthshatter cracks the ground through its wedge (a crack decal running out from the blow, rock spikes heaving up and
sinking back, chunks, pebbles, a rolling dust cloud); Frost Nova spreads frost over the ground with a bright edge and
bursts a ring of ice crystals that shatter; Arc is jagged, branching lightning struck again every few frames, leaping
target to target with a flash and sparks on each; War Cry burns a war sigil into the ground, ripples the air and rolls
a wave of dust and ash out to the edge of the cry. **The Warlock's three generic effects** went the same way (`WarlockFx`):
Blight Bolt's burst is a ring of fel fire with a pale flare, sickly smoke, splashing blight and souls rising; Soul
Shackles turns his sigil under him and pulls the dark in from the edge of its reach; Fel Covenant raises a crown of fel
fire round him with souls spiralling up (fel fire: InfernalFx's flame in his palette). **The Wraith's** 20 generic bursts and
8 rings became his own: spirit light streaking out as curling wisps, shadow as soft rolling smoke, every ring a ripple
of soul-mist over the ground (`WraithFx._spirit_burst`, `_soul_ring`). **Every hit** throws streaks now (sparks cooling as
they fall, blood droplets arcing down: `Fx.streaks`), and **the monsters' heavy blows** have their own shapes too: a
boss's slam and the bear's maul crack the ground with rock spikes and dust (`ElementalFx.ground_slam`), a nova is a
ring of hellfire, or sick green fire, racing out with a heat ripple (`fire_nova`), a summoning burns a circle and raises
smoke (`summon_circle`).

The bosses cost 6 credits (concept) + 30 (model) each: 108. The camp pieces 90 (three concepts, two edits, two models).
`a2_arena_test` (the whole games) and `a3_test` (the Ashen King's fight and drop) pass with the new bosses.

## 1d. Stage 4: the ground, rocks and clutter, the last generic effects

| Change | Where | What it fixes |
|---|---|---|
| **Worn flagstones** (every cobbled road and yard) | `Mats.TERRAIN_SHADER` (`cobble()`), judged in `tools/visual_audit/terrain_lab.gd` | The cobbles were flat polygons with an even dark line round each (crazy paving). Now each stone is domed, set a little askew, its edges chipped; granite in warm and cool greys with grain; crowns polished lighter where feet and wheels wear them; moss creeping in from the joints and lichen rosettes; some stones split by a crack, a few gone (a muddy hole); joints that open up in stretches. The normal comes from the same height the colour uses (about 9 cm joint to crown). The dirt of every path got pebbles half sunk in the soil (domed, shadowed at their foot, more toward the path's edges) and grit, and Act I's forest floor fallen oak leaves lying in drifts (lobed, brown to russet, some rotting); from Medium up (`ground_detail`, `litter`) |
| **Meshy rocks and kerbstones** (every zone's scattered rocks, the kingsroad's and the Imperial Road's kerbs) | `assets/models/rocks/` (3 granite boulders, a kerb), `Props.meshy_rock` / `boulder` / `seat`, `World.kerb` | The rocks were 120-triangle faceted noise spheres in a procedural stone shader. Now photographic Meshy concepts → image-to-3D → `rebake_prop.py` (1,500 / 600 triangles, 512 px, clean UVs): a lumpy glacial erratic, a split slate outcrop, a mossy fieldstone, a chipped granite kerb laid along the road. Their own shader keeps the zones' snow and A3's soot (`Props.MESHY_PROP_SHADER`), each rock a slightly different shade. The world's random numbers are drawn in the same order, so every rock, footprint and spawn stays where it was. Checked with `layout_dump.gd` on the Act I moor, the Imperial Road and the coast: every interactable, spawn and footprint matches the original build. The only lines that differ (a crate's yaw, which oak a Feral clings to) differ between two launches of the original too, because they use Godot's global random numbers; in co-op only the host spawns monsters |
| **Meshy crates, barrels and log piles** (the fort's yards, the coast, the islands, A2, the boats) | `assets/models/props/`, `Props._clutter_into` | The code-built boxes, lathe barrels and cylinder logs (up to seven parts each) are one Meshy model each (1,200-1,800 triangles, 512 px) at the old sizes and footprints |
| **Meshy Roman set pieces** (A2's road and Aurelia, the Forgotten Ruins, the Verdant Isle) | `assets/models/roman/`, `Roman._meshy_column`, `_set_piece`, `drum` | Stacked boxes, cylinders and prisms in a procedural marble shader. Now weathered travertine: columns with fluting, chips and moss (2,400 triangles; scaled to the code-built one's height, so a colonnade's beam still sits on them), broken stumps, fallen drums, the roadside tombs (a square shrine with a tiled pediment and a bronze door, a round mausoleum with a grassy mound), inscribed milestones, the fountains, the triumphal arch over the road into Aurelia (relief panels, an inscribed attic, a bronze chariot group), the statues (a Roman emperor in marble instead of the medieval crusader carved in marble) and the cypresses (dense foliage on a short trunk instead of a nine-sided cone, now in culled chunks). Each faces the way the code-built piece did; collision unchanged. The aqueduct that strides across the road is instanced Meshy bays: two tiers of round arches in tuff and travertine blocks with the channel on top, and for the broken bays a ruin whose upper tier has fallen to a jagged, grassy top; each bay scaled so its piers line up with the old collision and are shared with the next bay, as a real aqueduct's are. Every Meshy prop now has the see-through near the hero that the code-built props had (`MESHY_PROP_SHADER`), so a tall tomb, arch, cypress or aqueduct between the camera and the hero is dithered away round him. Aurelia has 42 columns, 5 statues and 77 cypresses; the road 14 whole and 23 broken columns, 8 tombs, 4 milestones, 5 statues, 61 cypresses and the aqueduct's 23 bays |
| **Living grass in Acts II and III** | `World.living_grass`, `Grass.scatter` | The Imperial Road, Aurelia and Act III's zones had the old blade clumps (15 M triangles on the road). They grow Act I's living 3D grass now (seven species, biomes, wind, touch): A2 in its sun-dried colours, Act III charred short under the ash by the grass shader's own ash response |
| **Telegraphs** (every warning on the ground: slams, cleaves, bombs, fuses) | `Fx.telegraph` / `arc_telegraph` (`TELEGRAPH_SHADER`) | A solid unshaded disc or fan (Earthshatter's was a cream wedge brighter than anything on screen). Now a crisp glowing rim, a faint wash, and the fill sweeping out with a bright front that meets the rim as the blow lands; added light, so the ground shows through |
| **The Plague Doctor's own language** | `scripts/plague_fx.gd` (`PlagueFx`) | His 18 generic bursts, rings and flashes: slivers of the flask's glass tumbling out, glossy gobbets of poison on arcs, a wet stain splashed over the ground with rays and drops and bubbles rising off it, the gas as rolling fumes, spores off the infected, a jet of gas out of a sprung trap, the dome's gas rushing in and blown out at its collapse; Volatile Mixture is alchemist's fire (orange to green-white), sparks, soot, the bottle's glass, an air ripple and a burning stain. His clouds (Toxic Flask, the trap, the cane's slam, the dome's floor) were ~400 soft round sprites each, the generic look again: now rolling ground fog that follows the terrain (`PlagueFx.miasma`: two layers of blurred, slowly warping noise, darker where it is dense, the cobbles showing through its thin parts), noise-eroded fumes rolling up off it and spores drifting, thinning away when it ends or is ignited. The dome's foot is a noise-broken band of light in place of a flat green torus, its shell fainter. Judged in `fx_lab.gd` |
| **The Demon's, Warlock's and Archer's last generic accents** | `DemonFx.embers` / `flare` / `fire_wave`, `WarlockFx`, `ArcherFx.hunter_mark` | The Demon's 37 generic bursts, rings, flashes, slams and his charge's aura: embers cooling along his palette, the low soot lit from below, a flare, a standing wave of hellfire racing out (Hellbrand's crescent all the way round), the fissures' spouts as real flames. The Warlock's siphon and latch: life motes streaming to him, a fel flare. The Archer: the hunter's mark (three claw rakes on a ring) for his wolf's commands and the sprung snare, ice splinters where a volley arrow strikes, spirit light rising when the wolf returns. No class's skills use `Fx.burst`/`ring`/`flash` now (the generic fallback for a new class's undrawn skills stays) |

Credits for stage 4: the rocks 264 (a first text-to-3D set at 30 each came back stylised, with neon moss and a white
kerb, and was dropped; then four photographic concepts at 6 and four models at 30), the clutter 108 and the Roman
pieces 366 (ten concepts, an edit, ten models), the aqueduct 72 (two concepts, two models). Meshy spent by the overhaul:
1,008 credits; the plan's balance is 1,043 (other sessions on the account the same night took the rest).

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
| S9 | Generic recoloured skill effects | Knight Nova/Cry/Charge, Warlock, shared skills, most Wraith effects use `Fx.burst/ring/pillar` | **Done**: knight (`HolyFx`, stage 2), shared skills, Warlock, Wraith (stage 3), Plague Doctor (`PlagueFx`), the Demon's and Archer's accents (stage 4); in testing |
| S10 | Always-on fire shadows outside the budget | Fort: 12 shadowed omni lights | Fixed (stage 1) |
| S11 | Decimation facets on round props | Clay views: flask, mixture, items, lair rocks | Bottles re-shaded (stage 2); the zones' rocks are Meshy boulders now (stage 4); the sloth lairs' rocks remain |
| S12 | Model textures uncompressed in video memory | Lossy WebP decodes to RGBA8: 1.0-1.9 GB VRAM | Decision (below) |
| S13 | A2/A3 keep the old grass and code-built architecture | 15 M grass triangles on the Imperial Road; Roman.* boxes | A2's and A3's grass is the living grass; the columns, tombs, milestones, fountains and the triumphal arch are Meshy (stage 4); the aqueduct, colosseum, buildings and walls remain code-built (P2) |
| S14 | Ground is one procedural shader | No material textures or decals (camp plan phase 2 not started) | The cobbles are worn flagstones (stage 4); material textures and decals for the meadows and dirt remain (P2) |

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
| 3D models (.glb) | 142 | At the audit 101 (8 hero bodies + statue, 3 dragons, 1 boss, 22 monsters, 6 NPCs, 18 camp, 5 fort, 5 isles, 1 boat, 6 lairs, 5 trees, 7 grass species, 4 title, 3 materials, 4 Plague Doctor props, bow, 3 arrows, debris; 2.04 M triangles, 290 MB); since then the overhaul's three bosses (stage 3) and its nineteen rocks, props and Roman pieces with the aqueduct's two bays (stage 4), and the 19 staging added the same night (Verdant Isle dinosaurs and props, the dwarf, the troll tamer, the Battlegrounds bosses and the crypt floors' set pieces): 2.50 M triangles |
| Loose textures | 191 | fx flipbooks 18, grass atlas 15, UI 26, talent icons 120, items 3, Plague dyes 5, ranger 4 |
| Code-built visuals | ~30 systems | terrain, roads, procedural trees/bushes/ferns, rocks, Roman architecture, small props, waypoint, ocean, weather, the humanoid body (3 bosses/elites and the unreachable legacy acts), sculpted goblins |
| Effects | 14 scripts | Every class's own language: `HolyFx` (knight), `InfernalFx`/`DemonFx`/`DemonFistsFx`, `WarlockFx`, `WraithFx`, `PlagueFx`, `ArrowFx`/`ArcherFx`, `ElementalFx` (shared skills, monsters' blows), `FireFx` (every fire); `Fx` keeps the generic pieces a few monsters and items use, the hit streaks and the telegraphs |
| Animations | mocap heroes (14-27 clips), Meshy monsters code-posed on `Goblin.imported_rig`, Feral/NPCs/dragons with baked clips | |

The full list with every asset's numbers, scores, priority, actions and status is
[`checklist.csv`](checklist.csv) (171 rows: every model, the 19 that staging added the same night and the 19 the overhaul made included, and the code-built systems).

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
| Environment (code) | 3.0 → 3.2 | Ocean, roads, the worn flagstones, Meshy rocks, kerbs, clutter and Roman set pieces (stage 4) | Meadow and dirt without material textures or decals, procedural pines, Aurelia's buildings, aqueduct and walls |
| Effects | 3.3 → 3.7 | Fire, Fire Arrow, the Demon; every class's own language (stages 2-4) | The generic Fx a few monsters and items still share; everything still to be judged at full speed on a real GPU |
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
| 7 | ~~Camp lantern and palisade~~ **done (stage 3)** | Shard soups in the hub | Meshy + re-bake | 90 credits |
| 8 | ~~Warlock, shared and Wraith effects~~ **done (stage 3)** | Generic bursts and rings | ElementalFx, WarlockFx fel fire, WraithFx wisps and soul-mist | Code |
| 9 | Ground materials and decals | The largest area on screen | **Cobbles done (stage 4)**; next: tiling PBR sets for the meadows and dirt, height blending, decals (camp plan phase 2) | Code + textures |
| 10 | A2/A3 grass and Aurelia's architecture | Act II looks older than Act I | **A2's and A3's living grass and the Meshy columns, tombs, milestones, fountains and triumphal arch done (stage 4)**; next: the city's buildings, the aqueduct and the colosseum | Credits + code |
| 11 | Procedural pines, rocks, small props | Code-built next to Meshy | **Rocks, kerbs, crates, barrels and log piles done (stage 4)**; pines, pots and the rest of the clutter | Credits |
| 14 | ~~The Demon's, Plague Doctor's and Archer's generic accents~~ **done (stage 4)** | The last generic bursts on heroes | `PlagueFx`; `DemonFx.embers`/`flare`/`fire_wave`; `ArcherFx.hunter_mark` | Code |
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

- Everything is judged on the software renderer: brightness, the rim light's strength, the knight's new steel and
  the new effects at full speed need jj's look on a real GPU (the preview build).
- The new bosses keep the monsters' A-pose rig, skinned by distance: Aurelius's skirt of strips and the Ashen King's
  mantle stretch a little in big swings; their weapons are the game's (scimitar). Baked clips (Meshy rig + library)
  would be the next step for the act bosses.
- Meshy characters still have no LODs (their UV atlases); the re-baked camp props do. Distance culling and the
  multimesh chunks carry the rest.
- The camp's new palisade stands 4.2 m (was 3.6); it reads as sturdier, but check it against the gatehouse in play.
- The detail normal maps follow each colour map's detail, which can emboss painted patterns; checked in a lineup,
  to be checked on the heroes in play.
- The fps gain is measured in primitives and draw calls; the KPI suite on the Mac is the confirmation.
- sloth_test and fallen_test each failed one random AI check once (the slam's stun, all three Fallen attacks) and
  pass on rerun, the same as on staging.
- Texture compression (VRAM vs download) is still a decision for jj and Blaine.
- Stage 4 to check in play: the Meshy boulders stand taller than the old flattened rocks (a knee-high boulder is
  0.5-0.7 m) and the kerbs are a darker granite, also on A2's Roman road (dark basalt suits it, but judge it); the
  living grass adds about 2 s to the Imperial Road's load (304k clumps over its 110 x 334 m) and its draw cost is
  in the table above; the telegraphs add light, so their strength should be judged on a real GPU at night and in
  daylight; the Plague Doctor's and Demon's new pieces were seen in software renders only.

## 10. Production checklist

[`checklist.csv`](checklist.csv): every model and code-built system with its measurements (triangles, texture size,
UV islands and coverage, normal-map tilt, colour-map brightness), eight scores, the mean, priority (P1-P4), actions
(R rebuild, M Meshy, B Blender, T textures, S materials/shaders, A animation, O optimise) and its status, one of:
Not inspected, Inspected, Needs improvement, Being rebuilt, Blender refinement, Imported into Godot, In-game testing,
Approved. Regenerate it with `python3 tools/visual_audit/checklist.py build/visual_audit docs/visual/checklist.csv`
after re-running `glb_audit.py` and `uv_report.py`.
