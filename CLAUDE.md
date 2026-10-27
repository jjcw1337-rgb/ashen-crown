# Ashen Crown: notes for Claude (and humans)

A Diablo II-style isometric ARPG in **Godot 4.3** (GDScript, Forward+ with an OpenGL fallback).
Everything is procedural (models, textures, sound, music); the only asset file is the intro
video `assets/intro.ogv`. Two developers (one Windows, one Linux) push to `main`; GitHub
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
`det_test`, `mp_test` (co-op: run one copy with `-- host` and one with `-- join`).
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
| `ground_item.gd`, `inter.gd` | Loot on the ground; interactables (chests, shrines, waypoints, portals, NPCs) |
| `items.gd` | Item rolls, `empower` (A2/A3 multipliers), enchanting, tooltips |
| `net.gd` | LAN co-op over ENet (UDP 24567, discovery 24568); RPC layer |
| `ui.gd`, `hud_bar.gd`, `icon_renderer.gd` | All UI built in code |
| `models.gd`, `skeleton.gd`, `flora.gd`, `props.gd`, `geo.gd`, `mats.gd` | Procedural meshes and shaders |
| `weather.gd`, `fx.gd`, `sfx.gd` | Snow/ash, particles, synthesized audio (autoload `Sfx`) |

## Rules and gotchas

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
- `UNLOCK_ALL_ACTS` in `game.gd` is a testing switch (also enables the F8 testing panel: `test_immortal`, `test_onehit` in `game.gd`); turn off for real playthroughs.
- Don't commit `.godot/` or `build/` (ignored). Line endings are LF (`.gitattributes`).
- Intro video: Ogg Theora only; keep under ~90 MB (GitHub's limit is 100 MB per file).
- CI is `.github/workflows/deploy.yml` (container `barichello/godot-ci:4.3`). If it fails, the
  site keeps the last good build; read the failed step in the Actions tab.
