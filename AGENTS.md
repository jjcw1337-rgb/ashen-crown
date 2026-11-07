# Ashen Crown: start here

Every coding agent (Claude Code, Codex, any machine) reads this first. It stays one page. Each part of the game has
its own short doc, listed under "Read before you start". Open only the ones your task needs.

## The game

An action roguelite in Godot 4.4.1. Each run you make a fresh hero, grow it in the Battlegrounds (a PvPvE forest of
monster camps whose chests offer skills, rites and gems) and extract to keep it. Survivors fight in the Arena, and
the Sandbox is for practice. The starting camp (Enter World) stays for now. `README.md` describes the game for
players.

## How it fits together

- **Content** is what players meet: heroes and their skills, monsters, the map and its camps, items (rites, gems,
  consumables) and the screens.
- **Systems** are the shared rules every piece of content runs on: data, skills (casting, cooldowns, aim), combat,
  effects, multiplayer, loading.
- **The pipeline** makes and ships the game: models, sounds, tests, CI and deploys. It is never shipped itself.

Every piece of content has three layers:
- **Data:** its numbers and text, in the codex (`data/codex/`).
- **Rules:** what it does: skills, damage, statuses, monster brains.
- **Look:** how it looks and sounds: bodies, effects, screens, audio.

Rules never draw. They send fx events, and every player's game draws them. A match runs on our server as a stripped
build with no pixels or meshes, so a rule that needs the look breaks the server.

## Where things live

The code is moving into `game/` by feature ([the plan](docs/architecture_cleanup.md)). Whatever hasn't moved yet is
still in `scripts/` and `assets/`.

| What | Where |
|---|---|
| A hero: code, body, weapon, skill folders, build scripts, tests | `game/heroes/<hero>/`. The Archer is the example. Heroes not moved yet: `scripts/<hero>*.gd`, `assets/models/`. |
| A hero's numbers and text (skills, rites) | `data/codex/heroes/<hero>.json`, written by the Hero Codex editor. Some numbers are still in code ([data](docs/systems/data.md)). |
| Shared rites, gems, consumables | `data/codex/shared.json`, `gems.json`, `consumables.json` |
| Monsters | stats in `scripts/data.gd` `ENEMIES`; behaviour in `scripts/enemy.gd` and the monster's own script (`bear.gd`, `sloth.gd`, `bg_boss.gd`…) |
| The map and its camps | `scripts/bg_forest.gd`, `camps.gd` |
| A map: its builder, props, the modes played on it, tests | `game/maps/<map>/`. The Arena is the example. |
| Screens (title, class picker, lobby, HUD) | `scripts/ui.gd`, `title_*.gd`, `class_stage.gd`, `mp_lobby_view.gd`, `run_ui.gd` |
| Shared systems | `scripts/` today, moving to `game/systems/` |
| Sounds, skill and rite icons | `assets/audio/sfx/` (built by `tools/audio/`), `assets/textures/skills/`, `talents/` |
| Servers | `deploy/`: the lobby service, the Nakama module, the staging setup |
| The pipeline, project-wide tests, CI | `tools/` and `.github/workflows/` |

## Read before you start

| If your task… | read |
|---|---|
| adds or changes a hero | [docs/content/heroes.md](docs/content/heroes.md) |
| adds or changes a skill | [docs/content/skills.md](docs/content/skills.md) |
| changes numbers or text | [docs/systems/data.md](docs/systems/data.md) |
| touches damage, statuses, rites or gems | [docs/systems/combat.md](docs/systems/combat.md) |
| adds anything players see | [docs/systems/effects.md](docs/systems/effects.md) |
| touches a match, a lobby, Nakama or a server | [docs/systems/multiplayer.md](docs/systems/multiplayer.md) |
| touches load time or frame time | [docs/systems/loading.md](docs/systems/loading.md), [measuring.md](docs/systems/measuring.md) |
| needs a model, a prop or a sound | [docs/pipeline/assets.md](docs/pipeline/assets.md) |
| runs tests, CI or a build | [docs/pipeline/builds.md](docs/pipeline/builds.md) |
| moves, splits or cuts code | [docs/architecture_cleanup.md](docs/architecture_cleanup.md) |

## Rules

1. **Godot 4.4.1, typed GDScript.** Write `var x: Type = ...`, because inference from a Variant counts as an error.
   After adding a `class_name`, rebuild the class cache with `godot --headless --path . --import`. On the Game
   Factory Macs Godot is `/Users/blaine/Applications/Godot_v4.4.1.app/Contents/MacOS/Godot`.
2. **Stay in your lane.** Several agents work here at once. Before you start, pull and read "Who does what" and "In
   progress" in [the plan](docs/architecture_cleanup.md), and edit only the files your task owns. Before a large edit
   to a shared file (`game.gd`, `ui.gd`, `hero.gd`, `net.gd`, `enemy.gd`), add a line under "In progress", and
   remove it when you're done. Work that isn't on the list needs an admin's say-so.
3. **Code goes where it's used.** If one skill uses it, it goes in that skill's folder. If one hero's skills share
   it, it goes in `game/heroes/<hero>/shared/`. If several heroes or monsters use it, it goes in `game/systems/`.
   Systems never name a hero. One concern per file, named for it.
4. **Rules never draw.** A skill calls `h.fx(skill, event, data)`, and an effects script draws it on every player's
   screen ([effects](docs/systems/effects.md)). Server code must never need pixels or mesh surfaces.
5. **What players read comes from the codex.** A skill's or rite's text and every number a player can see belong in
   its codex entry, and the code reads them from there, so a tooltip never disagrees with the game. Some still live in
   code (`scripts/data.gd`, `talents.gd`, `run_talents.gd`, hero scripts): move one into the codex when you touch it
   ([data](docs/systems/data.md)).
6. **Test what you touched,** with the tests beside it (`game/heroes/<hero>/tests/`, `tools/*_test.gd`). Report what
   you ran, and say so when something is unmeasured ([builds](docs/pipeline/builds.md)).
7. **Branches.** Work in your own worktree and branch, and merge `origin/staging` before you push. Push to `staging`
   when an admin asks, and to `main` only on an admin's explicit request. Never force-push over anyone's commits.
8. **Docs stay short and true.** They hold no history, because git has it. When code changes, fix the doc that
   describes it in the same commit. Comment the why in code when it isn't obvious.
9. **No secrets.** Credentials live only in local stores, GitHub's secrets and the servers. Never put them in the
   repo, prompts, logs or chat. Never commit `.godot/`, `/build/` or `.blend` files.
