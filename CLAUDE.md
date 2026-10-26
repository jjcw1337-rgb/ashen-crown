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
`playtest`, `unlock_test`, `kit_test`, `a2_test`, `a3_test`, `run_switch_test`, `drag_test`,
`det_test`, `mp_test` (co-op: run one copy with `-- host` and one with `-- join`).
Screenshots need a display: `xvfb-run -a godot --rendering-driver opengl3 --path . -- --shot out.png --zone town`
(other flags in `game.gd` `_ready`: `--zone town|wild|lair`, `--run 0|1|2`, `--god`, `--fight`).

Run the relevant tests before pushing. A push to `main` publishes to everyone in ~5 minutes.

## Code map (`scripts/`)

| File | Role |
|---|---|
| `game.gd` | Root node: boot, intro, zones/travel, camera, graphics presets, settings, save/load, acts and difficulty runs (`difficulty` 0/1/2 = Act I/A2/A3), input |
| `data.gd` | **Tuning**: monsters, item bases, affixes, uniques, skills, acts, vendors |
| `world.gd` | Zone builder: terrain, roads, buildings, trees/grass (MultiMesh chunks), spawns, `burn_points` |
| `hero.gd`, `knight.gd`, `knight_rig.gd`, `anim.gd` | Player: stats (`recalc`), combat, skills, gear visuals, animation, co-op puppet mode, `test_kit` |
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
  - keep graphics capped (`max_quality()` returns Medium on web);
  - no grass blades on web (`_scatter_grass` returns early) and no intro video (excluded in the Web preset);
  - don't mute audio buses (`AudioServer.set_bus_mute`): it throws in Godot 4.3's web audio and aborts startup. Use `Sfx.set_muted`;
  - known open issue: Cairnfell Moor's 3D view goes blank in the browser with ~15+ monsters in the zone. Desktop builds are fine.
- `UNLOCK_ALL_ACTS` in `game.gd` is a testing switch (also enables F8 gear); turn off for real playthroughs.
- Don't commit `.godot/` or `build/` (ignored). Line endings are LF (`.gitattributes`).
- Intro video: Ogg Theora only; keep under ~90 MB (GitHub's limit is 100 MB per file).
- CI is `.github/workflows/deploy.yml` (container `barichello/godot-ci:4.3`). If it fails, the
  site keeps the last good build; read the failed step in the Actions tab.
