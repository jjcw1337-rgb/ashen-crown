# Data: the codex

Where a hero's numbers and text come from, how the game reads them, and what still lives in code.

## The files

`data/codex/` is the Hero Codex:
- `heroes/<hero>.json`: one per hero. It holds the fantasy, three directions, the skills and the rites.
- `shared.json`: skills and rites any hero can find.
- `gems.json`, `consumables.json`.
- `code_base.json`: the values the code had at the last export (see "Code against codex").
- `fx_keys.json`: which rite effect keys the game reads, so the editor only allows rites the code can run.

A skill entry has `id, status, name, rarity, direction, desc, mana, cd, lvl`, and some add `range`, `power`, `use`,
`role`, `run` and `tags`. A rite entry has `id, status, name, rarity, direction, max, text, icon`, and most add `fx`
(some also `k`, `proc`, `per`, `requires`, `run`). `scripts/codex.gd`'s
header describes the format. Only entries with `"status": "live"` reach the game.

## How the game reads it

`Codex` (`scripts/codex.gd`) reads each file once. When a data script loads, it lays the codex over its built-in
entries: `Data` (skills, including the shared ones, and run skills), `Talents`, `RunTalents` (rites and gems) and `RunBuild`
(the shared rites, over its generic passives). A
missing or broken file falls back to the built-in data.

**What the codex sets today:**
- **Skills:** name, desc, mana, cd, use (timing), power (damage multiplier), range, role, rarity, direction, and `k`:
  the skill's own numbers, which its `Skill` object reads with `val(key, default)` (Fire Arrow's dmg, burn, burn_s…).
- **Rites:** name, text, max, fx, rarity, k.
- Live rites with no code behind them still reach the camp chests (`Codex.extra_rites`), if every effect key they
  use is one the game reads (`fx_keys.json`, or `dmg:`, `cd:`, `cost:`).

**What is still only in code:**
- `Data.SKILLS`: the class, key, unlock level, aim, tags and the other `SkillSpec` fields (`hit`, `dmg`, `area`,
  `dot`, `pvp`…). The codex's `lvl` and `tags` are ignored at runtime.
- `Data.CLASSES`: each class's name, stats, weapon and description.
- `Talents.TREES` and `RunTalents`' themes and each rite's proc.
- **Skills' base damage.** The codex's `power` multiplies it, but the base is in code: `SkillSpec` fields in
  `Data.SKILLS`, or constants in the hero's script. The Archer's multipliers, ranges and radii are constants in
  `archer.gd` (Fire Arrow ×1.3, `RANGE`, `VOLLEY_R`…), so changing "130%" in a codex `desc` changes only the tooltip. Moving these into the codex is
  part of the plan, the Archer first ([architecture cleanup](../architecture_cleanup.md), steps 2 and 5).

## Code against codex

The codex and the code can both change a value. `Codex._take` merges them three ways against `code_base.json`:
- if only the code changed a field since the last export, the code's value is kept;
- if both changed it, the codex wins;
- otherwise the codex's value is used.

`tools/codex_export.gd` rewrites `code_base.json`, and `tools/codex_test.gd` checks the files. Both go away once the
codex is the only copy.

## The editor

`tools/codex/` is the Hero Codex editor, a small local web app (`server.py`, `index.html`, [README](../../tools/codex/README.md)).
- **Save** checks the file (ids, rarity, numbers; a live entry can't be deleted; a new live rite must use effect keys
  the game reads). It writes `data/codex/<file>` and commits only that file.
- **Publish** pushes the branch for a preview build.
- In live mode, Publish runs the export and `codex_test`, then fast-forwards `staging`.

## Rules

- Change a skill's or rite's text and live numbers in its codex file, never only in code.
- A new number a player can see belongs in the codex, with the code reading it. A number only the look uses (a
  particle count, a colour) stays a named constant at the top of the effects file.
- `CodexBook` (`scripts/codex_book.gd`) shows the hero files in the game's Codex book, so a codex entry is also what
  players read.
