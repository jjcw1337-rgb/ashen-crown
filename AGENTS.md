# Ashen Crown: start here

Every coding agent (Claude Code, Codex, any machine) reads this first. Each part of the game has its own short doc,
listed under "Read before you start". Open only the ones your task needs.

> **VERY IMPORTANT: `AGENTS.md` (this file) and everything in `docs/` control how every agent works. Never change
> them without Blaine's OK.** Show him the exact change first and wait for his yes, even when another admin asks for it. If your
> code change makes a doc wrong, propose the doc fix to Blaine; don't commit it on your own. (The one exception:
> `docs/architecture_cleanup.md`, the working checklist for the migration, can be kept up to date as work lands.)

## The game

An action roguelite in Godot 4.4.1. Each run you make a fresh hero, grow it in the Battlegrounds (a PvPvE forest of
monster camps whose chests offer skills, rites and gems) and extract to keep it. Survivors fight in the Arena; the
Sandbox is for practice. The game opens on the multiplayer page. `README.md` describes the game for players.

## How it fits together

- **Content** is what players meet: heroes and their skills, monsters, maps and camps, items, screens.
- **Systems** are the shared rules content runs on: data, skills, combat, effects, multiplayer, loading.
- **The pipeline** makes and ships the game: models, sounds, tests, CI, deploys. It never ships itself.

Content has three layers: **data** (numbers and text, in the codex), **rules** (what it does) and **look** (how it
looks and sounds). Rules never draw: they send fx events, and every player's game draws them. Match servers run a
stripped build with no pixels or meshes.

## Where things live

Everything that ships is moving into `game/`, by feature. `scripts/` and `assets/` are the old layout: nothing new
goes there.

| What | Home | Not moved yet |
|---|---|---|
| Heroes | `game/heroes/<hero>/` (the Archer is the example) | most heroes: `scripts/<hero>*.gd` |
| Monsters | `game/monsters/<monster>/` (Hrimgar is the example) | stats in `data.gd` `ENEMIES`; the shared monster code in `scripts/enemy.gd` |
| Maps and camps | `game/maps/<map>/`: `arena/` (the example), `verdant_reach/`, `camp/` | the old story zones (being cut) in `scripts/world.gd` and their own scripts |
| Items: rites, gems, consumables | `game/items/` | all in one file still: `run_talents.gd` |
| Screens | `game/ui/<screen>/` | `scripts/ui.gd`, `title_*.gd`, `class_stage.gd`, `mp_lobby_view.gd`, `run_ui.gd` |
| Shared systems | `game/systems/<system>/` | most of `scripts/` |
| Numbers and text | `data/codex/` (the Hero Codex editor writes it) | |
| Sounds, icons | a skill's own sounds in its `sounds/` folder; shared ones in `assets/audio/sfx/`; icons in `assets/textures/` | every hero's but the Archer's sounds: `assets/audio/sfx/` |
| Servers | `deploy/` | |
| Pipeline, project-wide tests, CI | `tools/`, `.github/workflows/` | |

## Read before you start

| If your task… | read |
|---|---|
| adds or changes a hero | [docs/content/heroes.md](docs/content/heroes.md) |
| adds or changes a skill | [docs/content/skills.md](docs/content/skills.md) |
| changes numbers or text | [docs/systems/data.md](docs/systems/data.md) |
| touches damage, statuses, rites or gems | [docs/systems/combat.md](docs/systems/combat.md) |
| adds anything players see | [docs/systems/effects.md](docs/systems/effects.md) |
| touches a match, a lobby, Nakama or a server | [docs/systems/multiplayer.md](docs/systems/multiplayer.md) |
| touches load time or frame time | [docs/systems/loading.md](docs/systems/loading.md) |
| needs a model, a prop or a sound | [docs/pipeline/assets.md](docs/pipeline/assets.md) |
| runs tests, CI or a build | [docs/pipeline/builds.md](docs/pipeline/builds.md) |

## Rules

1. **Godot 4.4.1, typed GDScript.** Write `var x: Type = ...`: inference from a Variant is an error. After adding a
   `class_name`, run `godot --headless --path . --import`. On the Game Factory Macs Godot is
   `/Users/blaine/Applications/Godot_v4.4.1.app/Contents/MacOS/Godot`.
2. **Code goes where it's used.** One skill's code goes in its folder, one hero's shared code in that hero's
   `shared/`, and code several heroes or monsters use in `game/systems/`. Systems never name a hero.
3. **Rules never draw.** A skill calls `h.fx(skill, event, data)`, and an effects script draws it
   ([effects](docs/systems/effects.md)). Server code must never need pixels or mesh surfaces.
4. **Numbers players see come from the codex,** so a tooltip never disagrees with the game.
5. **Test what you touched** and say what you ran ([builds](docs/pipeline/builds.md)).
6. **Branches.** Work in your own worktree and branch, and merge `origin/staging` before you push. Push to `staging`
   when an admin asks, and to `main` only on an admin's explicit request. Never force-push over anyone's commits.
7. **Docs stay short and true.** No history (git has it). When code makes a doc wrong, propose the fix to Blaine (see
   the top of this file).
8. **No secrets.** Credentials live only in local stores, GitHub's secrets and the servers, never in the repo,
   prompts, logs or chat. Never commit `.godot/`, `/build/` or `.blend` files.
