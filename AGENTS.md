# Ashen Crown: start here

Every coding agent (Claude Code, Codex, any machine) reads this first. Keep it to one page.

**The game:** an action roguelite in Godot 4.4.1. Each run you make a fresh hero, grow it in the Battlegrounds (a
PvPvE forest of monster camps whose chests offer skills, rites and gems) and extract to keep it. The Arena is for
survivors. `README.md` describes it for players.

## Where things live (one place each)

The code is moving into `game/` ([docs/architecture_cleanup.md](docs/architecture_cleanup.md): the target layout
and who works on what). Until something has moved, it's in `scripts/` or `assets/`.

| What | The one place |
|---|---|
| A hero's skills and rites: numbers and text | `data/codex/heroes/<hero>.json` (the Hero Codex; its editor writes here). The old copies in `scripts/data.gd`, `talents.gd` and `run_talents.gd` are being removed, so edit the codex. |
| Shared rites, gems, consumables | `data/codex/shared.json`, `gems.json`, `consumables.json` |
| A hero's code, model, skill assets, build scripts, tests | `game/heroes/<hero>/` (heroes not moved yet: `scripts/<hero>*.gd`, `assets/models/`) |
| Shared rules and effects: combat, skills, fx, bodies, loading | `game/systems/` (being set up; until then `scripts/`) |
| Monsters | stats in `scripts/data.gd` `ENEMIES`, brains in `scripts/enemy.gd` (until `game/monsters/`) |
| The map, its camps and bosses | `scripts/bg_forest.gd`, `camps.gd`, `bg_boss.gd` (until `game/maps/`) |
| Screens (title, class picker, lobby, HUD) | `scripts/ui.gd`, `title_*.gd`, `class_stage.gd`, `mp_lobby_view.gd`, `run_ui.gd` (until `game/ui/`) |
| Sounds | `assets/audio/sfx/`, built by `tools/audio/` (the list is `spec.py`) |
| Skill and rite icons | `assets/textures/skills/`, `assets/textures/talents/` |
| Servers and what a build connects to | `deploy/` and the GitHub repository's variables. Secrets live only on the servers. |
| The asset pipeline, CI, project-wide tests | `tools/` (never shipped) |
| How-tos for each concern | `docs/patterns/`; adding a hero: `docs/character_workflow.md` |

## Rules

1. **Godot 4.4.1.** On the Game Factory Macs it's `/Users/blaine/Applications/Godot_v4.4.1.app/Contents/MacOS/Godot`.
   Write typed GDScript: `var x: Type = ...`, because inference from a Variant counts as an error.
2. **Branches.** Work in your own worktree and branch, and merge `origin/staging` before you push. Push to `staging`
   when an admin asks. Push to `main` only on an explicit admin request. Never force-push over anyone else's commits.
3. **Test what you touched.** Run the tests beside it (`game/heroes/<hero>/tests/`, `tools/*_test.gd`). A script that
   fails with "Identifier not found: Sfx" has to run through `tools/_late.gd -- res://<script>`. Report what you
   tested, and say so when something is unmeasured. (`tools/nightly/gate.sh` runs about 40 tests, roughly 25 min,
   for when you want everything.)
4. **Where new code goes.** If one skill uses it, it goes in that skill's folder. If one hero's skills share it, it
   goes in `game/heroes/<hero>/shared/`. If several heroes or monsters use it, it goes in `game/systems/`. Systems never name a
   hero.
5. **Skill code never draws.** A skill calls `h.fx(skill, event, data)` and an effects script draws it, on every
   player's screen ([effects](docs/patterns/effects.md)). Dedicated servers have no pixels or meshes
   ([servers](docs/patterns/servers.md)).
6. **No secrets.** Never put credentials in the repo, prompts, logs or chat. Never commit `.godot/`, `/build/` or
   `.blend` files.
7. **Docs stay short and current.** Docs hold no history, because git has it. When code changes, fix the doc that
   describes it in the same commit.

## Patterns: read the one for your task

[Loading](docs/patterns/loading.md) · [Servers](docs/patterns/servers.md) ·
[Multiplayer](docs/patterns/multiplayer.md) · [Effects](docs/patterns/effects.md) ·
[Measuring](docs/patterns/measuring.md) · [Code organization](docs/patterns/code-organization.md) ·
[Making assets](docs/patterns/assets.md)
