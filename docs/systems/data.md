# Data: the codex

`data/codex/` is the Hero Codex: the numbers and text of heroes, rites, gems and consumables.
- `heroes/<hero>.json`: one per hero (its fantasy, directions, skills and rites). `shared.json`, `gems.json` and
  `consumables.json` hold the rest.
- Only entries with `"status": "live"` reach the game.
- A skill's own numbers are its `k` (Fire Arrow: `{"dmg": 130, "burn_s": 3, …}`), which its `Skill` object reads
  with `val(key, default)`. A rite's numbers are its `k` too.
- A skill's `aoe` marks an area at the pointer (click to cast) and names its radius key in `k`
  ([skills](../content/skills.md)).

## How the game reads it

`Codex` (`game/systems/data/codex.gd`) lays the codex over the old built-in data when the game starts: `Data` (skills),
`Talents` and `RunTalents` (rites and gems), `RunBuild` (shared rites). The old copies in `game/systems/data/data.gd`,
`talents.gd` and `run_talents.gd` still hold what the codex doesn't (a skill's key, aim and tags; each rite's code),
and some damage numbers are still written in hero scripts.

The codex and the code can both change a value, so `Codex` merges them against `code_base.json` (the code's values at
the last export, written by `tools/codex_export.gd`). `tools/codex_test.gd` checks the files.

## The editor

`tools/codex/` is the Hero Codex editor, a small local web app ([README](../../tools/codex/README.md)). Save checks
and commits one file; Publish pushes it for a build.

## Rules

- Change text and numbers players see in the codex, never only in code.
- A number only the look uses (a particle count, a colour) stays a named constant in its effects script.
