# Ashen Crown: notes for Claude (and humans)

A Diablo II-style isometric ARPG in **Godot 4.3** (GDScript, Forward+ with an OpenGL fallback).
Everything is procedural (models, textures, sound, music) except two asset files: the intro video
`assets/intro.ogv` and the Act I boss, King Grubb, `assets/models/grubb_mutant.glb` (generated with Meshy,
rigged in Blender; see "Blender assets"). Two developers (one Windows, one Linux) push to `main`; GitHub
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
`det_test`, `collision_test`, `aim_test`, `hoard_test`, `potion_test`, and the co-op pairs `mp_test` and `mp_boss_test` (run one copy
with `-- host` and one with `-- join`; `mp_boss_test` plays King Grubb's fight with the joining player).
Tool scripts save to `user://ashen_crown_test_save.json`, never the player's save.
Balance: `tools/balance.sh` runs `tools/balance_sim.gd` (bots play every class through Act I, A2 and A3) and flags numbers
outside their target bands. See `BALANCE.md` for the protocol.
Screenshots need a display: `xvfb-run -a godot --rendering-driver opengl3 --path . -- --shot out.png --zone town`
(other flags in `game.gd` `_ready`: `--zone town|wild|lair`, `--run 0|1|2`, `--god`, `--fight`).

Run the relevant tests before pushing. A push to `main` publishes to everyone in ~5 minutes.

## Code map (`scripts/`)

| File | Role |
|---|---|
| `game.gd` | Root node: boot, intro, zones/travel, camera, graphics presets, settings, save/load, acts and difficulty runs (`difficulty` 0/1/2 = Act I/A2/A3), input |
| `data.gd` | **Tuning**: classes (`CLASSES`), skills per class (`SKILLS`, `skills_for`), monsters, items, uniques, acts, vendors |
| `world.gd` | Zone builder: terrain, roads, buildings, trees/grass (MultiMesh chunks), spawns, `burn_points` |
| `hero.gd`, `knight.gd`, `knight_rig.gd`, `anim.gd` | Player: class (`cls`, `set_class`), stats (`recalc`), combat, skills, gear visuals, animation, co-op puppet mode |
| `wraith.gd`, `wraith_fx.gd` | Wraith class: body mesh + spectral shader on the knight skeleton; skill effects |
| `demon.gd`, `demon_fx.gd`, `demon_minion.gd` | Demon class: knight body in obsidian plate + horns/wings/tail/spikes with the solid ember-edge shader; skill effects and the Underworld screen grade; summoned demons (simple ally AI) |
| `warlock.gd`, `warlock_fx.gd` | Warlock class: knight body in a long robe (`robe` gear key) + hood, horns, fel flame, floating grimoire; skill effects incl. the Drain Life beam (`WarlockFx.Beam`, an ImmediateMesh ribbon redrawn each frame) |
| `enemy.gd`, `projectile.gd` | Monsters/AI and missiles (host-authoritative in co-op) |
| `hoard.gd` | King Grubb's fight (Act I boss): Gilded Bombs, the three burst sacks, the gold scramble (piles reaching him heal him; piles a hero takes hurt him) |
| `goblin.gd`, `sculpt.gd` | Goblin models: King Grubb is the imported mutant (`Goblin.MUTANT`: joint layout + glb, skinned onto the game's skeleton); the Gold Grabbers (and Grubb's fallback) are code-sculpted (`Sculpt` melts SDF shapes into one skinned mesh). `Goblin.after_pose` adds ears, jaw, crown wobble, belly jiggle, sacks and the goblin gaits |
| `ground_item.gd`, `inter.gd` | Loot on the ground; interactables (chests, shrines, waypoints, portals, NPCs) |
| `items.gd` | Item rolls, `empower` (A2/A3 multipliers), enchanting, tooltips |
| `net.gd` | LAN co-op over ENet (UDP 24567, discovery 24568); RPC layer |
| `ui.gd`, `hud_bar.gd`, `icon_renderer.gd` | All UI built in code |
| `models.gd`, `skeleton.gd`, `flora.gd`, `props.gd`, `geo.gd`, `mats.gd` | Procedural meshes and shaders |
| `weather.gd`, `fx.gd`, `sfx.gd` | Snow/ash, particles, synthesized audio (autoload `Sfx`) |

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
  `tools/model_preview.gd` stages any candidate .glb in the vault for screenshots; `tools/goblin_anim.gd` renders a
  contact sheet of his motion. `tools/blender/grubb.py` (+ `grubb_gear.py`) is the earlier fully scripted Blender
  build, kept as a reference; its export isn't used. Godot's `.import` files and extracted textures under
  `assets/models/` are git-ignored (regenerated on import); run `godot --headless --editor --quit` after re-exporting.
- `UNLOCK_ALL_ACTS` in `game.gd` is a testing switch (also enables the F8 testing panel: `test_immortal`, `test_onehit`, `test_stamina`, `test_allskills` in `game.gd`, and a level setter, `Hero.set_level`); turn off for real playthroughs.
- Don't commit `.godot/` or `build/` (ignored). Line endings are LF (`.gitattributes`).
- Intro video: Ogg Theora only; keep under ~90 MB (GitHub's limit is 100 MB per file).
- CI is `.github/workflows/deploy.yml` (container `barichello/godot-ci:4.3`). If it fails, the
  site keeps the last good build; read the failed step in the Actions tab.
