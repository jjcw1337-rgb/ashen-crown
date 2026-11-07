# Ashen Crown

A dark-fantasy action roguelite in the isometric style of Diablo II, built in Godot 4.4.1.
You make a fresh hero for each run, grow it in a shared PvPvE map, and extract to keep it.

## How a run works

1. **Pick a hero and join a Battlegrounds lobby.** Everyone starts at level 0 in the Verdant Reach, an
   open forest, with only a basic attack.
2. **Clear camps.** Each camp is a pack of monsters guarding a sealed chest. Harder camps (tiers I-III,
   then the bosses) give more experience and better loot.
3. **Pick 1 of 3 from the chest.** The choices are skills and rites:
   - **Skills**: active abilities, on right mouse and Q E R F.
   - **Rites**: passives that stack. Some add stats, others change how a skill works.
   The camp's tier sets the odds of **Common**, **Uncommon** and **Rare** picks. Rares are the run-changers.
4. **Pick up the rest of the chest.** Chests also give gear, **consumables** for the belt (potions,
   flasks, scrolls) and sometimes a **gem**, a one-of-a-kind power-up that bends a build.
5. **Extract or lose it.** Other players are in the same map. Reach an extraction portal to save your
   hero as a **survivor**. Survivors can fight each other in the **Arena** (1v1, 2v2, 3v3).

### Three directions per hero

Every hero has three directions a build can take, for example the Archer's Flame, Frost, and Storm and Hunt.
Each skill and rite belongs to one direction, or is shared by all builds. The more a build has of one
direction, the more the chests offer it, so a run that keeps picking one direction becomes that kind of hero.

### The Hero Codex

All skills, rites, gems and consumables are data in `data/codex/` (JSON), and the game loads them from
there. **The Codex editor: https://blaines-mac-mini.tail7f9b03.ts.net.** Open it once with the key link from
the admins' Discord channel. It edits the data in the browser and publishes to `staging`; see
`tools/codex/README.md` for details.
Players can browse what they've discovered in game from the Codex button on the multiplayer screen.

## Play

Builds come from **itch.io**: install the [itch app](https://itch.io/app), sign in with an account that
has access to the private `ashen-crown-staging` page, and install it. The app updates the game by itself.

- **Mac:** the build isn't notarized, so the first launch is blocked. Go to **System Settings → Privacy &
  Security** and click **Open Anyway**.
- **Windows:** SmartScreen may warn that the app is unrecognized. Choose **More info → Run anyway**.
- **Black screen?** On Windows run `Ashen Crown (Safe Mode).bat`, which uses the OpenGL renderer.

## Controls

| Input | Action |
|---|---|
| WASD | Move |
| Mouse | Aim. Everything goes toward the pointer |
| Left mouse | Basic attack |
| Right mouse, Q E R F | Skills |
| Q E R F on an area skill | Shows where it will land; left mouse casts it there, Esc or the key again cancels (the pause menu's "Quick cast" casts it on the key) |
| Space | Dodge roll (hold to sprint after it) |
| Shift (hold) | Sprint |
| 1–4 | Use a belt consumable |
| I / K / N | Your run's build: skills, rites, gear, gems |
| Tab / M | Large map / minimap |
| Esc | Cancel an aimed skill, close windows, pause menu |

## Working on it

- **Setup:** install [Godot 4.4.1](https://godotengine.org/download/archive/4.4.1-stable/) (standard, not
  .NET), clone `jjcw1337-rgb/ashen-crown`, import `project.godot` and press F5. The first open takes a
  minute while Godot builds `.godot/` (never committed). For models, use Blender 4.5 LTS and keep `.blend`
  files outside the project; only `.glb` exports go in the project, next to what uses them.
- **Workflow:** work on your own branch, test what you change, then merge to `staging`. Pushes to
  `staging` build Windows, Mac and Linux and upload them to itch.io and Steam's staging branch. `main`
  changes only when an admin asks.
- **How the code is organized and its rules:** [AGENTS.md](AGENTS.md) (for people and AI agents alike),
  and one doc per part of the game in [docs/](docs/).

### Project layout

| Path | What's there |
|---|---|
| `game/heroes/<hero>/` | Everything one hero owns: code, model, skills with their assets, build scripts, tests |
| `game/maps/<map>/` | Everything one map owns: its builder, props, the modes played on it, tests: `arena/`, `verdant_reach/` |
| `game/monsters/<monster>/` | Everything one monster owns: model, body, brain, look, tests |
| `scripts/game.gd` | Boot, zones, camera, input, saving |
| `game/systems/world/` | The world every map is built on: `World` (terrain, paths, collision, chests), props, flora, grass, birds, weather, colour grading |
| `scripts/hero.gd`, `enemy.gd` | Players and monsters |
| `game/items/run_build.gd`, `run_talents.gd`, `run_ui.gd` | A run's hero, its rites, gems and consumables, and its windows |
| `scripts/<class>_skills.gd`, `*_fx.gd` | Each class's skills and their effects |
| `scripts/net.gd`, `lobby_client.gd` | Networking and the lobby browser |
| `data/codex/` | Skills, rites, gems and consumables as data |
| `assets/` | Models (Meshy, rigged in Blender), textures, audio, the intro video |
| `tools/` | Headless tests, preview renderers, the asset pipeline |
| `deploy/` | The staging server, lobby service and Nakama backend |
