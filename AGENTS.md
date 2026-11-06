# Ashen Crown: start here

Every coding agent (Claude Code, Codex, any machine) reads this first. Keep it to one page.

**The game:** an action roguelite in Godot 4.4.1. Each run you make a fresh hero, grow it in the Battlegrounds (a
PvPvE forest of monster camps whose chests offer skills, rites and gems) and extract to keep it. The Arena is for
survivors. `README.md` describes it for players.

## Where things are

The code is moving to the layout in [docs/architecture_cleanup.md](docs/architecture_cleanup.md), which also says
who is working on which part.

| Path | What's there |
|---|---|
| `heroes/<hero>/` | Everything one hero owns: code, model, `skills/<skill>/` with each skill's own assets, `build/` (Blender and other build scripts), `tests/`, `tools/` (previews). Done so far: archer, plague. |
| `systems/` | Shared rules and effects that any hero uses (being set up) |
| `scripts/` | Everything not moved yet: `game.gd` (boot, zones), `hero.gd`, `enemy.gd`, `net.gd`, `ui.gd`, `world.gd`, … |
| `assets/` | Models, textures and audio not moved yet |
| `data/codex/` | Skill, rite, gem and consumable data (the Hero Codex; its editor is in `tools/codex/`) |
| `tools/` | Project-wide tests, previews, the asset pipeline (`meshy/`, `blender/`, `audio/`) and CI. Never shipped. |
| `deploy/` | The staging server, the lobby service and Nakama |
| `docs/PLAN.md` | The to-do list |

## Rules

1. **Godot 4.4.1.** On the Game Factory Macs it's `/Users/blaine/Applications/Godot_v4.4.1.app/Contents/MacOS/Godot`.
   Write typed GDScript: `var x: Type = ...`, because inference from a Variant counts as an error.
2. **Branches.** Work in your own worktree and branch, and merge `origin/staging` before you push. Push to `staging`
   when an admin asks. Push to `main` only on an explicit admin request. Never force-push over anyone else's commits.
3. **Test what you touched.** Run the tests beside it (`heroes/<hero>/tests/`, `tools/*_test.gd`). A script that
   fails with "Identifier not found: Sfx" has to run through `tools/_late.gd -- res://<script>`. Report what you
   tested, and say so when something is unmeasured. (`tools/nightly/gate.sh` runs about 40 tests, roughly 25 min,
   for when you want everything.)
4. **Where new code goes.** If one skill uses it, it goes in that skill's folder. If one hero's skills share it, it
   goes in `heroes/<hero>/shared/`. If several heroes or monsters use it, it goes in `systems/`. Systems never name a
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
