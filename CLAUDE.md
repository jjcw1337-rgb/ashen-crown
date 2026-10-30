# Ashen Crown: notes for Claude (and humans)

A Diablo II-style isometric ARPG in **Godot 4.3** (GDScript, Forward+ with an OpenGL fallback).
Everything is procedural (models, textures, sound, music) except a few asset files: the intro video
`assets/intro.ogv`, the Act I boss King Grubb `assets/models/grubb_mutant.glb` and the gnome Warlock
`assets/models/gnome_warlock.glb`, and the knight's two bodies `knight_meshy.glb` / `knight_armored.glb` (all generated
with Meshy and rigged in Blender; see "Blender assets"). Two developers (one Windows, one Linux) push to `main`; GitHub
Actions exports Web + Windows + Linux + Mac and publishes them to GitHub Pages.

- Repo: https://github.com/jjcw1337-rgb/ashen-crown
- Live test build + downloads: https://jjcw1337-rgb.github.io/ashen-crown/
- Human setup and workflow: `CONTRIBUTING.md`. Player docs: `README.md`.

## Getting the tools (Linux)

Godot 4.3 **standard** (not .NET) must be on PATH as `godot`:
```
wget https://github.com/godotengine/godot/releases/download/4.3-stable/Godot_v4.3-stable_linux.x86_64.zip
unzip Godot_v4.3-stable_linux.x86_64.zip && sudo mv Godot_v4.3-stable_linux.x86_64 /usr/local/bin/godot
```
**Blender 4.5 LTS** (for models and rigs, see "Blender assets"): `bash tools/blender/setup_blender.sh` installs it
to `/opt` and links `blender` (checksum-verified). Claude's cloud workspace resets, so run it again in a new session;
it needs network access to `download.blender.org`. Run scripts headless: `blender -b --python script.py -- args`
(renders with Eevee work under `xvfb-run -a`). Export `.glb` into `assets/models/`, never `.blend`.

**Meshy** (AI image/text to 3D, paid plan): `python3 tools/meshy/meshy.py text|image|get|check ...` saves a `.glb` plus a
thumbnail. Key from `$MESHY_API_KEY` or `~/.config/meshy/key` (never in the repo); needs `api.meshy.ai` and
`assets.meshy.ai` reachable. Each generation costs credits; results expire on Meshy after 3 days. Clean up, rig and
export with Blender, the way King Grubb was made.

Exporting locally also needs the 4.3 export templates (Editor → Manage Export Templates), but
you normally don't export locally: pushing to `main` does it in CI.

## Commands

```
godot --headless --editor --quit                  # import / rebuild the class cache (run after adding a class_name)
godot --path .                                    # play
godot --headless --path . -s tools/playtest.gd    # main gameplay smoke test
```
Headless tests in `tools/` (each prints `[X] ...` lines; look for SCRIPT ERROR / Parse Error):
`playtest`, `unlock_test`, `test_panel_test`, `wraith_test`, `demon_test`, `warlock_test`, `a2_test`, `a3_test`, `run_switch_test`, `drag_test`,
`det_test`, `collision_test`, `aim_test`, `hoard_test`, `potion_test`, `fort_test`, `sound_test`, `char_test`, `flower_test`, `feral_test`, `talent_test`, `a2_arena_test`, `vendor_test` (the camp's traders, the trade window, walking off closes it), `ui_click_test` (no click on a window, menu, globe or the corner map walks the hero; a control that rebuilds itself on click must `accept_event()` first, or the click leaks through), and the co-op pairs `mp_test` and `mp_boss_test` (run one copy
with `-- host` and one with `-- join`; `mp_boss_test` plays King Grubb's fight with the joining player).
Tool scripts save to `user://ashen_crown_test_save.json`, never the player's save.
Balance: `tools/balance.sh` runs `tools/balance_sim.gd` (bots play every class through Act I, A2 and A3) and flags numbers
outside their target bands. See `BALANCE.md` for the protocol.
Screenshots need a display: `xvfb-run -a godot --rendering-driver opengl3 --path . -- --shot out.png --zone town`
(other flags in `game.gd` `_ready`: `--zone town|wild|lair`, `--run 0|1|2`, `--class knight|wraith|demon|warlock`, `--god`, `--fight`).
The moor's road is `World.road_style()`: the paved Old Kingsroad (2) by default; `--road 0|1|3` shows the old broad
road, the wagon trail and the moor trails for comparison. `tools/zone_overview.gd -- out.png [--road N]` renders a high view of it.

Run the relevant tests before pushing. A push to `main` publishes to everyone in ~5 minutes.

## Code map (`scripts/`)

| File | Role |
|---|---|
| `game.gd` | Root node: boot, intro, zones/travel, camera, graphics presets, settings, save/load, acts and difficulty runs (`difficulty` 0/1/2 = Act I/A2/A3), input |
| `data.gd` | **Tuning**: classes (`CLASSES`), skills per class (`SKILLS`, `skills_for`), monsters, items, uniques, acts, vendors |
| `talents.gd` | Talent trees (`Talents.TREES`: three per class), row rules, the auto build for old saves (`AUTO`) |
| `world.gd` | Zone builder: terrain, roads, buildings, trees/grass (MultiMesh chunks), spawns, `burn_points` |
| `hero.gd`, `knight.gd`, `knight_rig.gd`, `anim.gd` | Player: class (`cls`, `set_class`), stats (`recalc`), combat, skills, gear visuals, animation, co-op puppet mode |
| `wraith.gd`, `wraith_fx.gd` | Wraith class: body mesh + spectral shader on the knight skeleton; skill effects |
| `demon.gd`, `demon_fx.gd`, `demon_minion.gd` | Demon class: knight body in obsidian plate + horns/wings/tail/spikes with the solid ember-edge shader; skill effects and the Underworld screen grade; summoned demons (simple ally AI) |
| `warlock.gd`, `warlock_fx.gd` | Warlock class: the gnome (`Warlock.GNOME`: imported model on `Goblin.imported_rig`, A-pose arms aimed down, swaying hat and beard, fel flame, floating grimoire; falls back to the robed knight body without the glb); skill effects incl. the Drain Life beam (`WarlockFx.Beam`, an ImmediateMesh ribbon redrawn each frame) |
| `enemy.gd`, `projectile.gd`, `feral.gd` | Monsters/AI and missiles (host-authoritative in co-op); the Feral's baked-animation body |
| `via.gd`, `aurelia.gd`, `games.gd`, `roman.gd` | A2: the Imperial Road (wild), the city of Aurelia and its arena (lair), the arena's games (the act's boss fight), and the Roman architecture they're built from |
| `lion.gd` | The arena lion: a Meshy model on a quadruped skeleton, posed in code (no baked animations) |
| `fort.gd` | Grubb's fort (the lair in Act I; A3 keeps the crypt): the muddy approach with the guards fighting the dead, the palisade ring, gatehouse and watchtowers (Meshy props in `assets/models/fort/`), the lived-in camp scattered round Grubb's open courtyard, and the moor's goblin trail end (`Fort.trail_end`) |
| `meshy_monster.gd` | Act I monsters from Meshy (`MeshyMonster.MODELS`, zombie/fallen/archer/goblin_guard): built on `Goblin.imported_rig` with grips and weapons; `Data.ENEMIES` `"mesh"` picks them |
| `hoard.gd` | King Grubb's fight (Act I boss): Gilded Bombs, the three burst sacks, the gold scramble (piles reaching him heal him; piles a hero takes hurt him) |
| `goblin.gd`, `sculpt.gd` | Goblin models: King Grubb is the imported mutant (`Goblin.MUTANT`: joint layout + glb, skinned onto the game's skeleton); the Gold Grabbers (and Grubb's fallback) are code-sculpted (`Sculpt` melts SDF shapes into one skinned mesh). `Goblin.after_pose` adds ears, jaw, crown wobble, belly jiggle, sacks and the goblin gaits |
| `ground_item.gd`, `inter.gd` | Loot on the ground; interactables (chests, shrines, waypoints, portals, NPCs) |
| `items.gd` | Item rolls, `empower` (A2/A3 multipliers), enchanting, tooltips |
| `net.gd` | LAN co-op over ENet (UDP 24567, discovery 24568); RPC layer |
| `ui.gd`, `hud_bar.gd`, `icon_renderer.gd` | All UI built in code |
| `vendor_ui.gd` | Nameplates over the town's people and the trader's live portrait in the trade window |
| `models.gd`, `skeleton.gd`, `flora.gd`, `props.gd`, `geo.gd`, `mats.gd` | Procedural meshes and shaders |
| `weather.gd`, `fx.gd`, `sfx.gd`, `sfx_bank.gd` | Snow/ash, particles, audio (autoload `Sfx`: recorded/generated sounds from `assets/audio/sfx/` listed in the generated `sfx_bank.gd`, with the old synthesized sounds as fallback) |

## Rules and gotchas

- **Collision**: solid things are footprints (circles and rotated boxes) in `World.obstacles`. Props declare their own
  (`Props.footprint(root, radius_or_half)`) and are registered with `world.solid(node)` after placing (it reads the node's
  position, yaw and scale). Use `add_circle`/`add_box` only for things with no prop node. Movers call `world.move(pos, d, radius)`,
  which slides against the exact footprints; `blocked` (a padded 1 m grid) is only for A* and spawn spots.
- **Aiming**: Space and the skill keys fire the way the hero faces, with a light assist (`Hero.aim_ahead`). Every skill in
  `Data.SKILLS` has `"aim"`: `"facing"` (plus `"range"`), `"self"` or `"point"` (the cursor); `Hero.skill_aim` applies it.
  Give a new skill an `aim`.
- **Runs** (Act I, A2, A3) are `Data.RUNS` multipliers (`Game.run_mult`). `Items.empower` scales only flat stats; percentages
  (`Items.PCT_STATS`) stay as rolled. Re-run the balance sim after changing any of them.

- **Typed GDScript**: inference from Variant is treated as an error. Write `var x: Type = ...`.
- **Co-op**: every peer must run the same build; RPC ids depend on each script's RPC set.
- **Browser build (WebGL)** is a test build only and is fragile:
  - it is exported with **Godot 4.5.1** in CI (the desktop builds use 4.3): Godot 4.3's WebGL renderer
    blanks the whole 3D view in busy scenes (many objects near lights). Keep code working in both versions:
    e.g. `get_meta(key, null)` errors in 4.5, so check `has_meta` first;
  - keep graphics capped (`max_quality()` returns Medium on web); no intro video (excluded in the Web preset);
  - don't mute audio buses (`AudioServer.set_bus_mute`): it throws in Godot 4.3's web audio and aborts startup. Use `Sfx.set_muted`;
  - don't create audio buses with `AudioServer.add_bus()`: Godot 4.5.1's web sample playback files the new bus in front
    of Master and routes Master into it, so the whole game is silent in the browser. `Sfx._buses` uses `set_bus_count`;
- **The archer** (`scripts/archer.gd`, `Archer`; the bow class for Jace, its name still his to choose, "Archer" in
  `Data.CLASSES` until then): with a bow (`Hero.has_bow`; bows are `Data.BASES` with `"cls": "archer"`, only he can
  equip them) his attack shoots (`Archer.shoot` from `Hero.swipe_attack`/`free_attack`; `Hero.reach` is `Archer.RANGE`,
  so a clicked foe is shot from range; Anim's `"bow"` pose, the arrow looses on its impact frame). Skills: Piercing
  Shot (an arrow through a line), Volley (a rain of arrows on the cursor, hits every 0.2 s), Snare Trap (stuns the
  first enemies on it), Spirit Beast (`spirit_beast.gd`: the lion's body, ghostly, hunting for 30 s, plus the 12 s
  battle buff). Arrows, volleys, snares and beasts live on the hero (`Hero.arrows` etc.), `Archer.update`/`clear`.
  Talents: Marksman, Warden, Beastmaster (`Talents.TREES["archer"]`; specials arrow_split, snare_dur, snare_max,
  snare_wide, volley_size, beast_two). Body: the knight's procedural body dressed as a hunter (`Archer.build_body`)
  until the Meshy model; talent icons still to paint (`tools/talent_icons.py` has the archer prompts).
  `tools/archer_test.gd` checks it.
- **Adding a class**: add it to `Data.CLASSES`, give it four `SKILLS` entries with its `cls`, build its look the way `wraith.gd` does (reuse `Knight.build` for the skeleton so animation and co-op keep working), handle its skill ids in `Hero.use_skill` / `_impact`, and add glyphs in `ui.gd` `SkillGlyph`.
- **Underworld** (Demon's Phase): `game.set_underworld()` blends a screen-space grade (`DemonFx.UNDERWORLD_SHADER`), the `under_amt` global (terrain veins and rune rings in `mats.gd`), environment tweaks, rising souls and crimson monster outlines (`Enemy.set_soul_lit`). Monsters ignore a phased hero (`hero.phased`).
- **Drain Life** (Warlock Q) is a channel, not an attack: `hero.drain_t` runs while Q is held (minimum 1 s), ticks every 0.3 s in `_update_drain`, and the beams are drawn after `Anim.pose` in `_draw_drain`. Any move, target click or other skill calls `end_drain()`, which also clears the victims' green rim (`Enemy.set_drained`), the ground sigil and the looping hum (`Sfx.start_loop`). Drain ticks set `Enemy.dmg_tint` around `take_damage` for green numbers and no blood. Skill effects are local only (partners see the cast pose, not the beam), like every other class.
- **King Grubb** (Act I boss, `hoard.gd`) is host-authoritative. Every visible part of the fight (piles, bombs, burst
  sacks, shouts, a grabber's `carry_on`/`carry_off`) is an Enemy fx event string handled in `Hoard.fx`, so partners see it;
  damage, healing and gold happen only on the host. Grabbers reach the fight through `Enemy.hoard` (`Hoard.steer`).
- **Sculpted bodies** (`Sculpt`): a monster with `"model"` in `Data.ENEMIES` is built by `Goblin.build`. The body is one
  skinned mesh made once per kind (about 0.5 s) and cached; each limb is its own group so it doesn't melt into the torso.
  Its shader textures in rest space from UV/UV2 (skinned VERTEX moves). Rigid bits (teeth, claws, gold, cloth) stay
  per-joint meshes. `knight_rig.gd` copies the joints onto the bones (position, rotation and scale).
- **Blender assets** (King Grubb): the model was generated with Meshy (a Meshy concept image, then image-to-3D),
  decimated to ~80k triangles and rigged by `tools/blender/grubb_mutant.py` (bones on his anatomy named like the
  game's joints; distance weights plus fixed regions for the crowns, belly, the three gold sacks and the key). The
  `.blend` source (with the full-detail mesh) is `~/Documents/Blender/Game Factory/sources/grubb.blend`, exports go
  to `exports/`; never put a `.blend` inside the project (Godot 4.3 imports `.blend` files by launching Blender, which
  hangs headless imports). The joint layout in the script must match `Goblin.MUTANT["layout"]` (Godot axes: x, z, -y).
  `Goblin._imported` re-binds the glb's skin onto the game's skeleton by bone name, so `Anim.pose` and
  `Goblin.after_pose` drive it; the `held` meta damps his shoulder swings (his gut and arms tear the skin otherwise).
  Burst sacks are hidden by scaling their bones to ~0. Without the file he falls back to the code-sculpted king.
  The gnome Warlock works the same way (`tools/blender/gnome_warlock.py`, `Warlock.GNOME`, source
  `sources/gnome_warlock.blend`): `Goblin.imported_rig` builds the skeleton from a layout, and its `aim` turns an A-pose
  limb's rest down the limb so the hero's animation hangs it naturally. A player model also needs `grip_r`/`grip_l`/
  `mount_l`/`chest` anchors (weapons, shields, amulets; scaled for his size) and a `stride` meta (short legs step faster).
  `tools/gnome_anim.gd` renders a contact sheet of his motion.
  His look extras live in `warlock.gd`: purple cloak and green glowing hat horns (`cloak_mat`, a vertex mask on the hat),
  horn-tip smoke (`_horn_smoke`), the pixie-dust trail while moving (`_dust_trail`, world-space GPU particles),
  the hopping hat and the weapon held high when running (`_gnome_sway`). `tools/gnome_run.gd` and
  `tools/gnome_clip.gd` (movie writer) preview them.
  `tools/model_preview.gd` stages any candidate .glb in the vault for screenshots; `tools/goblin_anim.gd` renders a
  contact sheet of his motion. `tools/blender/grubb.py` (+ `grubb_gear.py`) is the earlier fully scripted Blender
  build, kept as a reference; its export isn't used. Godot's `.import` files and extracted textures under
  `assets/models/` are git-ignored (regenerated on import); run `godot --headless --editor --quit` after re-exporting.
- **Knight (no armour)** is a Meshy model (white shirt with a red crusader cross, shorts, leather sandals,
  long hair): `assets/models/knight_meshy.glb`, built by `Knight.build_meshy` on `Knight.MESHY_LAYOUT`. The hero
  wears it while the armour slot is empty (`Hero._wants_meshy`); `refresh_gear` swaps to the procedural armoured
  body when armour goes on. To rebuild it: `blender -b --python tools/blender/knight/rig_meshy_knight.py --
  <meshy.glb> <out.glb> layout.json --cross` (re-poses the A-pose to arms-down, skins by distance, splits the hair
  into five locks hA..hE of three bones, paints the cross, adds the sandals), then
  `python3 tools/blender/knight/layout_to_gd.py layout.json` rewrites the layout block in `knight.gd`. The hair
  locks are simulated in `knight_rig.gd` `_sway_hair` (springs per bone; run, footfall jolt, turning, wind).
  The knight's run is `Anim` with the `gait` meta `"knight"` (front-to-back arm pump). Preview tools:
  `tools/knight_clip.gd` (`-- outdir [side|back|close] [armored] [helm]`), `tools/gait_preview.gd`; test `tools/meshy_knight_test.gd`.
- **Knight (armour on)** is the Meshy crusader (enclosed great helm, spiked plate over mail, dark surcoat with a
  faded red cross, sword in its scabbard on the left hip, long tattered cloak): `assets/models/knight_armored.glb`,
  `Knight.build_meshy(true)` on `Knight.ARMORED_LAYOUT`. `Hero._knight_body()` picks "plain" (no armour), "armored"
  (any body armour) or "" (the procedural body, only without the glb files); the rig's `meshy` meta holds which.
  He always wears his own helm: helm items keep their stats but aren't drawn on him (`Hero.refresh_gear`), and there
  is no show/hide helm button. Rebuild from the Meshy glb: `blender -b --python tools/blender/knight/prep_crusader.py
  -- meshy.glb dec.glb --tris 70000 [--grid prefix]` (decimate, 1.8 m, feet on the ground; the grid renders are for
  placing joints), then `blender -b --python tools/blender/knight/rig_crusader_knight.py -- dec.glb out.glb layout.json
  [--debug prefix]` and `python3 tools/blender/knight/layout_to_gd.py layout.json armored`. The rig script heat-skins a
  voxel-remeshed watertight proxy (Meshy's mesh isn't watertight) and transfers the weights; the helm rides the head,
  the sword and the cloth between the legs ride the hips, the arms (and their spikes) only their own arm; the cloak
  (found by the metallic map and where it hangs) hangs on three panels of three bones (hA..hC) that `knight_rig.gd`
  `_sway_hair` swings; faces Meshy fused between parts that move apart (cloak/leg, cloak/arm, arm/hips) are cut, and
  cloak shreds left beside the A-pose arms are dropped. `--debug` renders the A-pose coloured by main bone.
  The earlier armoured knight (bare head, red tabard) is kept as `knight_statue.glb` for the arena statues.
- **Act I trees and grass** (`World.oak_forest`, set by `game.gd` when `difficulty == 0`; A2/A3 keep the old mix): three
  Meshy oaks `assets/models/trees/oakN.glb` (prepared by `tools/blender/prep_tree.py`: trunk on the origin, ~6 m, 1k
  textures) built by `Flora.oak_model(k)` with `MESHY_TREE_SHADER` (wind sway by height, snow/ash, see-through near the
  player) plus the game's leaf clusters (`OAK_LEAVES`); the moor is ~40% oaks with groves off the road. Grass is
  painted for the game's camera: nine Meshy 2D clumps drawn from 45 degrees above (`assets/textures/grass/topN.png`,
  `Flora.GRASS_TOP` sizes and weights), each on one card that leans back to face the fixed camera (`Flora._camera_card`,
  no yaw, mirrored at random; `GRASS_CARD_SHADER`), a clump per spot and a smaller one beside most, over the blade grass
  at half density. New clumps: `meshy.py draw` with "seen from above at a 45 degree camera angle ... chunky blades,
  no thin hair-like detail" and `--cutout`, then `tools/grass_prep.py meshy.png topN.png` (crops, squares, scales and
  bleeds the colour into the clear pixels; without that, far clumps go dark and blobby) and mipmaps on in the .import.
  Unmipmapped or hair-thin cut-outs flicker pixel by pixel; the card shader cuts out with alpha to coverage. The older
  upright photo cards (`gN.png`, `Flora.grass_cards`) are the fallback. The see-through near the player (trees, props)
  uses an ordered dither (`dith`), not per-pixel noise, which sparkled in the tree shadows too.
  **Sunstar Blooms** (`World._rare_flowers`, Act I only, 3 per moor, 14-34 m off the road, own seed): a glowing
  painted card (`Flora.flower_card`) and a breathing light; picking one (`Game._interact` "flower") gives +50%
  experience for 5 minutes (`Game.xp_bonus_t`, shared with the Experience Shrine; the XP bar counts it down) and is
  synced like shrines. `tools/flower_test.gd` checks the grass kinds and the blooms.
  Previews: `tools/tree_lineup.gd`, `tools/tree_shot.gd`. Meshy 2D: `meshy.py draw --cutout`.
- **Act I monsters** (Meshy): concept image, image-to-3D, decimate to ~20k triangles in `sources/act1_enemies.blend`,
  then `blender -b --python tools/blender/act1/rig_monster.py -- <decimated.glb> <out.glb> layout.json [tex px] [hints]`
  (measures the joints; hints `{"sh_z", "sh_x"}` when a hood or helmet spike fools the neck finder) and
  `python3 tools/blender/act1/layout_to_gd.py <kind> layout.json`. They keep their A-pose (arms aimed down like the
  gnome). Previews: `tools/monster_lineup.gd -- out.png kind...`, `tools/monster_shot.gd` (staged on the moor).
- **The Feral** (`feral.gd`, Act I forest): a Meshy model rigged and animated in Blender (`sources/feral.blend`:
  17 bones, skinned by distance along the body's surface because the forearms touch the knees, IK on the four
  limbs). Unlike the other monsters it plays baked, in-place animations ("crawl", "lunge", "swipe", exported as NLA
  tracks to `assets/models/monsters/feralN.glb`, five models with different rags and skin on the same rig, picked by
  where each spawns, `Feral.variant_at`), timed by `Feral.pose` from the enemy state: the crawl from `phase`,
  the attacks from their progress. Packs of 3-4 cling head-down to oak trunks well off the road
  (`World._feral_packs`, spawn entries with `"perch"`; `Enemy.perch_on`); come within ~10 m and the pack
  skitters down (`_feral_perch`, styles "perch"/"descend" carry it to co-op partners), circles about 4.5 m out,
  and one at a time lunges (`special` "feral_lunge", flying over other monsters), backs off, darts in to claw,
  backs out (`_feral_combat`, `f_state`); the lunge has a 5 s cooldown, and outrun for 6 s (beyond 9 m) the pack
  gives up and goes home, ignoring you for 8 s unless hit (`f_chase`, `f_calm`). `tools/feral_test.gd` checks it.
- **Factions** (`"faction"` in `Data.ENEMIES`: goblin, undead): a monster fights the nearest other-faction monster when
  it is closer than the hero (`Enemy.rival`, `Enemy.take_hit` so the attack code works on both); rival kills give no
  xp or loot (`killed_by_rival`). Host-side like all AI.
- **A2 is its own act** (`World.run == 1`; `Data.RUN_ACTS[1]` overrides Act I's names, boss and foes, read with
  `Data.act_info(act, run)` / `World.act_name(key)`; use those, never `Data.ACTS[...]` directly). Warm late-afternoon
  light, no snow (`Game._zone_env`; `is_snowy()` is false now). The camp is still Act I's.
  - **The Imperial Road** (`via.gd`, wild, 110 x 334 m): the road changes along its length (`Via.AMBUSH/ROMAN/
    OUTSKIRTS` are fractions of `path_poly`; `Via.at/dir_at/beside(w, t, off)` place things along it): the moor (dirt
    trail, farmstead ruin, graveyard, the waypoint), a rocky pass with an overturned wagon where bandits wait, the
    Roman road (paving patchy where it sank, then whole with kerbs, milestones, tombs along both verges, toppled
    columns, cypresses, the aqueduct striding across it with one bay always standing over the road), then
    Aurelia's outskirts (ruined colonnades, statues, a villa, a fountain, bandits holding the road) to the triumphal
    arch, the exit to the lair.
  - **Ambushes** (`World.ambushes`, `Game._check_ambushes`/`_spring_ambush`, host only): nothing is spawned until a
    hero comes within `radius` of `pos`; then the entries spawn and leap from cover onto the road
    (`Enemy.leap_from`, `leap_t`), bowmen stay on the crests. A spawn entry may carry `"name"` (the champion's).
  - **Aurelia** (`aurelia.gd`, lair, outdoors; ground levelled by a `ground_fn` that cancels the noise inside the
    zone): the city gate, the colonnaded main street with shops and apartment blocks (`_building`: shop,
    apartment or ruin), districts behind with alleys, the crossroads fountain, the temple (west) and market (east),
    the arena plaza with Varro the lanista (out in the open on the way up to the entrance) (`Inter` kind "lanista", `Game._interact`; he and his two guards are the Meshy
    bandit, the guards are non-clickable `Inter`s with `data.still`; he offers the games again after they're won, and a
    hero at the barred Gate of Life before the deal is told to find him), and the colosseum: the sand
    (`FLOOR_RX/RZ`, `floor_t`), the podium wall (solid), stepped stands, the outer arcade three storeys high on the
    north and fallen to one storey and rubble on the south so the camera sees in, the passage to the Gate of Life,
    beast/side/champion gates (`GATES`), the patron's box.
  - **The games** (`games.gd`, a node in the lair, `world.get_meta("games")`): Varro's deal calls `begin()` (a
    partner's goes through `Net.request_games`); the Gate of Life opens (its bars are an obstacle whose centre is
    moved far away while open: World's obstacles can't be removed); a hero on the sand shuts it (partners outside
    are placed in, `Net.place_player`) and the `STAGES` run: the lions, the gladiators, the beasts of the pit (with a
    champion pit lion), then the champion (`Data.ENEMIES["champion"]`, a boss: his death ends the act through
    `Game.on_enemy_killed`), who calls lions at 60% life and gladiators at 30%. Host-authoritative; everything seen
    (gates, announcements, the crowd's excitement, sounds) is an event string through `fx` / `Net.games_event`.
    In the pit stage and the champion's bout the spike traps fire (`_spike_traps`: glowing warnings, some under
    the heroes, then iron spikes 1.3 s later; they hurt beasts too, never the champion); each kill makes the crowd
    cheer (`kill`). The crowd is the game's own monsters (`Games._crowd_cards`): every kind in `Data.ENEMIES` with a finished Meshy model (`Games.finished_model`) is drawn once
    (idle and cheering, front and three-quarter, `Enemy.build_rig`/`pose_rig` in a little studio) into an atlas, and
    the stands hold camera-facing cards of them (`CARD_SHADER`, jumping and cheering with `excite`); bosses sit in the
    patron's box. A new monster joins by itself. `tools/crowd_shot.gd` screenshots it. Aurelius's shield charge (`_charge`): a red streak on the sand toward the nearest hero, a
    brace, then a dash at 15 m/s smashing each hero in the way once; Games drives him meanwhile (`Enemy.scripted`
    skips his own AI). If no living hero is near the sand for 8 s the games reset. The crowd is one MultiMesh of figures on the
    standing stands, bobbing and jumping by a shader uniform (`excite`). Sounds: `arena_horn`, `crowd_roar` (loop),
    `crowd_cheer`, `portcullis`, `lion_roar`.
  - **Roman architecture** (`roman.gd`): materials (marble, tuff, brick, tile, bronze), `arch_mesh` (an extruded
    wall with a round opening, used by the aqueduct, the colosseum's arcade, gates), columns, colonnades, tombs,
    milestones, statues (the earlier Meshy knight `knight_statue.glb` carved in marble, `Roman.STATUE_GLB`), fountains, the triumphal arch, cypresses
    (MultiMesh), ruined walls. Repeating pieces go through `Props.multimesh` with their own mesh copy
    (`Roman._own`: Geo's meshes are cached and shared, never set a material on them).
  - **Monsters**: bandits (`bandit`, `bandit_archer`: the Meshy bandit on `MeshyMonster`, faction "bandit"),
    the arena lion (`lion.gd`: Meshy model, a 20-bone skeleton from `sources/lion.blend` skinned by surface
    distance like the Feral, posed every frame in code by `Lion.pose`, the Feral's pack AI with its lunge as the
    pounce and its swipe as the maul; `tools/lion_sheet.gd`), the gladiator and the champion (procedural humanoids
    until their Meshy models: the concepts are in `exports/act2/`, the key's monthly Meshy cap stopped them).
  - Tests and previews: `tools/a2_arena_test.gd` (road, ambush, Aurelia, the whole games), `tools/via_shots.gd`,
    `tools/aurelia_shots.gd` (`overview` for a top view). Load `aurelia.gd` at run time in a `-s` tool script
    (`load(...)`): a static reference compiles it, and games.gd's `Sfx`, before the autoload exists.
- **Grubb's fort** (`fort.gd`, `World.fort` = Act I only): an outdoor zone still called "lair" (`Game.indoor()` is
  false there, so it gets the sky, snow in A2 and the outdoor light). Big pieces are Meshy props prepared by
  `tools/blender/act1/prep_prop.py` (`-- in.glb out.glb x=5|h=8|w=11 triangles [yaw] [tex]`; keep ~12k triangles for
  the palisade, which repeats ~44 times); without the glbs simple log stand-ins are built. The camp is placed by
  rejection sampling round the courtyard (`Fort._camp`), Grubb's courtyard reuses `World._hoard_room`.
  Outer works: the palisade stands on a rampart with a water-logged ditch round it (`Fort.ground`, set as
  `World.ground_fn`, the generic hook for shaping a zone's ground; the fort's slopes are coloured mud, not rock),
  a causeway and plank bridge at the gate, stakes on the ditch's lip (`_ditch`); a second, lower stockade round
  the south (`OUTER_RX/RZ`, `_outer_wall`, its own gatehouse where the track comes in; the gate battle is there
  now) enclosing the outer yard (`_outer_yard`: stables, pens, wagons of plunder, the camp's Meshy forge and
  tents, storehouses on stilts, haystacks, lantern posts, guards). Behind the throne, Grubb's great hall (Meshy,
  `assets/models/fort/hall.glb`, `HALL_YAW` turns its door toward the courtyard; source concept and raw model in
  `exports/fort/`), with braziers, banners and a treasury hut each side. Outside: stumps where the forest was
  felled, a lumber yard and a crop field (`_outskirts`). `tools/fort_shots.gd` screenshots it from the game camera.
  `tools/fort_test.gd` checks it; `tools/zone_overview.gd -- out.png --fort` renders it from above.
- **Sound**: effects are real recordings (Kenney, CC0) and ElevenLabs Sound Effects generations, picked by ear; the
  old numpy synthesis (`tools/audio/make_sfx.py`) was rejected as cheap-sounding and is kept only as a fallback.
  Pipeline (`tools/audio/`, the heavy steps run in the venv at `~/Documents/Game Factory Audio/venv`):
  `spec.py` lists every sound (source, prompt, duration, `hit` = seconds to the payoff, loop); `eleven.py [names]`
  generates candidates into `~/Documents/Game Factory Audio/candidates/<name>/` (key in `~/.config/elevenlabs/key`,
  about 10 credits per second of audio, `--dry` estimates, `--credits` shows what's left; never buy more);
  `score.py --rank` scores them (CLAP: real sound vs synth/beep, audiobox quality) so the obviously bad ones sink;
  a human picks (the Sound Picks artifact); `build_sfx.py picks.json` (`{name: [files]}`) trims each take, puts
  its payoff `hit` s in, matches loudness by category, writes `assets/audio/sfx/<name>_<take>.wav` (32 kHz, imported
  as QOA), `scripts/sfx_bank.gd` (`[takes, bus, hit]`) and `assets/audio/CREDITS.md` (source and license of every
  file). Run `godot --headless --editor --quit` after a build. `Sfx.play(name)` is heard flat (the hero's own skills, UI), `Sfx.play_at(name, pos)` is positional
  (hits, monsters; AudioStreamPlayer3D, full volume at the camera's distance). Takes rotate, pitch is nudged, at most
  three of one sound per 50 ms, buses SFX/UI/Music/Ambience with a limiter on Master, `Sfx.duck()` under big spells.
  A cast's sound starts with the cast (`Hero._attack_sound`) and `Sfx.play_synced` lands its payoff on the impact
  frame at any attack speed; monster impacts, crit stings and kill sounds come from `Enemy._hit_sound`/`die_visual`
  by `Enemy.material()`. King Grubb's voice is deep (the `cackle`/`roar` takes, never pitched up), and before his fight
  his muttering (`grubb_mutter`) carries through the fort from him, faint from ~75 m and clear in sight
  (`Hoard.murmur`, every peer locally; stops at the "intro" event). `tools/sound_test.gd` checks every skill fires its
  sounds (`Sfx.counts`) and the fort voice. The camp's song is `music_town` (jj's pick: a dark forest sanctuary, harp over a low
  string drone with a wooden flute; candidate take 13). Ambience: wind, drips in the crypt, and in Act I outside the camp (moor and fort) `forest`, soft
  trees in a breeze (`Sfx.play_music(kind, amb)`, picked in `Game.load_zone`).
- **The camp's bonfire** (`Inter` kind `"bonfire"`, `UI.open_burn`): clicking it opens the fire (`UI.Flames`) beside the
  inventory; drag an item onto the flames or right-click it to burn it for good (`UI.burn_request`, `Game.burned`: the
  `burn_item` sound and a flare); rare, unique and material items ask first. A click on an inventory item plays
  `inv_click`. `tools/bonfire_test.gd`, `tools/bonfire_shot.gd`.
- **Birds** (`scripts/birds.gd`, Act I outdoors, added by `Game.load_zone`): flocks of dark swept-wing silhouettes cross
  the sky round the hero (flapping, gliding, banking, shadows), and every 25-50 s a flock bursts out of the trees near
  him with `birds_flutter`. Cosmetic and local (not synced). Screenshot: `tools/birds_shot.gd`.
- **The party's ready check** (`Net.ask_trip`, called by `Game.travel` whenever the party has more than one player):
  the host runs a vote (`Net.vote`), every peer sees `UI.party_vote` (a small iron-and-bronze window, Join / Not yet;
  the one who asked sees "Waiting for …" and Cancel), and the host's `Game.travel_now` takes the whole party once
  everyone has said Join. A member leaving mid-vote is dropped from it (theirs is called off). The host is the party
  leader (♛ on the party list) and can remove a member (✕, `UI.confirm_kick`, `Net.kick`). `tools/mp_test.gd`
  (host + join) checks it; `tools/vote_shot.gd` screenshots the window.
- **Characters** (save slots): each character is its own save, `user://characters/<id>.json` (`Game.char_id`,
  `char_name`; the save holds `name` and `played`). `Game.list_characters()` reads them (last played first) for the
  title's Continue button and the Characters list (Play / Delete); New Character asks for a name on the class picker.
  The pre-characters save `user://ashen_crown_save.json` is adopted once as the first character and left in place.
  The pause menu's "Save and Exit to Title" is `Game.exit_to_title()`. Co-op uses the last played character and its
  name. Tools still save to the test file; `tools/char_test.gd` moves `char_dir`/`old_save` to test the real thing,
  `tools/char_shot.gd` screenshots the screens.
- **Act I camp in the forest** (`scripts/forest_camp.gd`, `ForestCamp.build`, used by `World._build_town` when
  `oak_forest` and act 0; A2/A3 keep the old camp): a ring palisade with a gatehouse, rune stones outside
  (`RUNE_SHADER` glows their runes), a bonfire, tents and lantern-hung oaks inside, the old forest beyond, and a
  dusk/mist mood (`Game._zone_env`, `theme.forest_camp`). Everything is Meshy (concept image, then image-to-3D),
  prepared in Blender: props by `tools/blender/prep_prop.py` into `assets/models/camp/`, trees by `prep_tree.py`.
  The shopkeepers are Meshy characters rigged by Meshy and animated from its clip library (`meshy.py rig` /
  `animate` / `library`), cleaned by `tools/blender/prep_npc.py` into `assets/models/npc/`; `Inter._animate`
  plays their work clips, turns them to face the hero and has them talk when he comes near (clips listed in
  `ForestCamp.SHOPS`). Their library clips walk the hips about (Catching_Breath strode 4.6 m out of the forge),
  so `ForestCamp._pin_root` pins every clip's hips over the keeper's spot. The camp is "The Forsaken Wilds"
  (`Data.ACTS[0]["town"]`); its smith Halvar Emberhammer works inside his forge behind the anvil (a SHOPS entry's
  `"inside"`: his spot in the stall's frame; `"stay"` in its clips: he never turns from his work and greets once a
  visit; his `radius` reaches the stall's front, since the stall is solid). Screenshots: `tools/camp_shots.gd`.
- **Nameplates and the trade window** (`scripts/vendor_ui.gd`): `VendorUI.Plates` (in `ui.plates`, under every
  window) floats a gold-trimmed plate with the name and trade (`VendorUI.ROLE_TITLES`) over each vendor and Varro,
  click-through, fading with distance, lit when hovered. The trade window (`UI._build_shop`, `open_shop(mode,
  title, items, who, greet)`) is headed by the trader: a live portrait (`VendorUI.Portrait`, their model in its
  own little world, from the keeper's `npc_file` meta or the humanoid's `look`, greeting then idling), name, trade,
  greeting and your gold; tabs by kind (`UI.SHOP_KINDS`; `shop_view` maps cells to `shop_items`) and a price on
  each cell, red when you can't afford it. `UI.trade_with` is the NPC whose window is open: walking more than 3 m
  past their `radius` closes it (`UI._walked_off`, the stash too). `tools/vendor_test.gd` checks all of it with
  the smith; `tools/vendor_shots.gd -- outdir [role]` screenshots a trader.
- **Skill bar and bindings** (every class, including new ones): the bar has a big slot for each mouse button and six
  hotkeys (Q E R F G V); any skill can go on any of them (`Hero.binds`, saved per character; `Hero.default_binds`:
  left mouse `attack`, right mouse `block`, the class's first four skills on Q-F). `attack` and `block` are
  `Data.COMMON_SKILLS` (`Data.skills_known(cls)` = class skills + common). Input goes through `Game._use_bind`
  (held buttons recast when ready; `Game.skill_held(id)` for Block and Drain Life's channel). Click a bar slot or
  open the skills window (K) to rebind, or drag: a skill from the skills window onto a slot, one slot onto another
  (they swap), or off the bar (cleared; left mouse never empties). Drag uses Godot's `set_drag_forwarding`
  (`UI._skill_drag`, `UI.drop_skill`, the clear in `UI._notification`); a click without a drag opens the slot's menu.
  Block: 80% less damage from the front (missiles stopped with a shield).
  Art: Meshy-painted frame and sockets in `assets/textures/ui/`. A new class needs nothing extra.
- **Talents** (`scripts/talents.gd`, the window is N; `tools/talent_test.gd`, `tools/talent_shot.gd`): three trees per
  class of seven talents in four rows (2, 2, 2, then a capstone); a row opens with 0/3/6/10 points spent above it in
  that tree (`Talents.ROW_REQ`), and a rank can't be taken back if a deeper talent would lose its row. One point a
  level from level 2: `Hero.free_talent_points()` = level - 1 - spent (nothing stored but `talents` {id: ranks} in
  the save). Reset is free; Auto-assign spends free points along `Talents.AUTO[cls]`. A save without `talents` gets
  that build for its level (`Hero.from_save`); a bad one is cleaned (`Talents.clean`). Effects are data: each
  talent's `fx` adds up into `Hero.tfx`, read with `Hero.talent(key)` (the key list is at the top of talents.gd):
  flat stats join the gear's in `recalc`; `dmg`/`dmg:<skill>` through `Hero.dmg_mult` (pass the skill as
  `_hit_enemy`'s `src` when it isn't the attack in progress), `cost:`/`cd:` through `Hero.skill_cost`/`skill_cd`
  (use those, not the raw `Data.SKILLS` numbers), the battle buffs through `Hero.buff_mult`, and each class special
  where its skill is. Icons are painted with Meshy, a 3x3 grid per tree (7 talents, the tree's emblem, a spare),
  cut into `assets/textures/talents/<id>.png` and `<cls>_tree<N>.png` (128 px, mipmaps) by `tools/talent_icons.py`
  (the prompts are in it; `prompt`, then `meshy.py draw`, then `cut`); greyed by a shader until a point can go in.
  A new class needs a `TREES` and an `AUTO` entry and its four grids; without a painted icon a talent falls back to
  its `icon` glyph (a skill id or a `t_*` in `SkillGlyph._talent_icon`). The balance sim gives its bots the auto build.
- **Globes** (`scripts/globe.gd`, `Globe`): liquid that surges after a hit, ripples on a heal, pulses and shakes
  when low, darkens when critical, swirls after a cast, rises slowly with regeneration, sends a wave up on a big
  restore, and grows with maximum life/mana. Meshy frame `globe_frame.png`, Blender glass `globe_glass.png`
  (`tools/blender/ui_glass_orb.py`, added over the liquid). Standard for every class; a special character can
  override with a `"hud"` entry in `Data.CLASSES` (see `Globe.set_style`). Preview: `tools/globe_demo.gd`.
- **Inventory (I)** (`UI._build_inventory`, jj's "Classic"): Meshy art in the action bar's iron and bronze
  (`assets/textures/ui/inv_*.png`, cut and cleaned from Meshy concepts in `exports/ui/inventory/`): a NinePatchRect
  frame (`INV_SCALE`, corners `INV_PATCH` texture px, the middle bands mirror-symmetric so they tile seamlessly,
  `draw_center` off over a tiled iron inside), the equipment in a recessed alcove with a knight's silhouette
  (`INV_EQUIP` rects and `Caption` labels), the bag's 40 sockets (`_slot(..., iron = true)`: the action bar's
  socket on a 9-patch, a rarity line inside) and the gold on a bronze plate. Every piece keeps clear of the frame's
  corner spikes and trim: `tools/inv_geometry_test.gd` samples each socket, label, the alcove and the plate against
  the frame's ornament as the 9-patch draws it. Screenshot: `tools/inventory_shot.gd`.
- **Character sheet (C)** (`UI._build_character`): Meshy frame `sheet_panel.png` (texture margin 100 so the corner
  pieces never stretch; content margins keep everything inside the gold trim), live portrait (a SubViewport on the
  shared world) in `sheet_portrait.png`, Meshy medallions `sheet_str/dex/vit/ene.png` and `sheet_plus.png`. Hover a
  stat for what each point adds (`_stat_tip`, from `Hero.recalc`); combat stats sit in a dark inset (`_combat_tip`).
  Same for every class. Screenshot: `tools/sheet_shot.gd`.
- **Skill picker** (`UI._choose_skill`, click a bar slot): the bar's own iron frame and sockets, one card per skill
  (`_picker_card`: equipped glow, the key it's on now, mana, locked level). Esc / click outside closes
  (`close_skill_picker`). Screenshot: `tools/picker_shot.gd`.
- `UNLOCK_ALL_ACTS` in `game.gd` is a testing switch (also enables the F8 testing panel: `test_immortal`, `test_onehit`, `test_stamina`, `test_allskills`, `test_fast` (super speed, `TEST_FAST` times as fast) in `game.gd`, and a level setter, `Hero.set_level`); turn off for real playthroughs.
- Don't commit `.godot/` or `build/` (ignored). Line endings are LF (`.gitattributes`).
- Intro video: Ogg Theora only; keep under ~90 MB (GitHub's limit is 100 MB per file).
- CI is `.github/workflows/deploy.yml` (container `barichello/godot-ci:4.3`). If it fails, the
  site keeps the last good build; read the failed step in the Actions tab.
- **Preview builds**: push a branch named `test-*` (`git push origin HEAD:test-something`) and
  `.github/workflows/preview.yml` builds the Windows, Linux and Mac versions as downloads on that Actions run
  (Artifacts, kept 7 days) without publishing anything. Use it to let a partner play a change before it goes to main.
