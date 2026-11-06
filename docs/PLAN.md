# Ashen Crown: project plan

The one to-do list. Everyone (Blaine, jj, every agent) works from this file: add what's asked, tick what's done,
delete what's dropped. Newest decisions win. Started 2026-11-06.

## In flight

- [ ] **Codex's perf release → staging** (`test-codex-release-20261106`). Gate 2026-11-06: 2 failures to fix first
      (vendor_test: the smith no longer hammers at the anvil; the sandbox lobby test didn't run because another Godot
      was open). Before it pushes: drop `tools/performance_audit/install.py` (no scheduled jobs) and the
      `docs/perf/evidence/*.json` logs.
- [ ] **Time a Battlegrounds load once it lands.** If it's much slower than ~8 s, load only the classes in the match.
- [ ] **Loader fix (Codex's next task):** Godot's threaded loader instead of the single worker thread, exact file
      lists instead of whole folders, only the match's classes, SkillWarm's fast-forward back. Done = load time no
      worse than before, video memory no higher.
- [ ] **README and root docs cleanup → staging** (`claude-1/readme`, waiting for the staging lock).

## Code cleanup (Blaine, 2026-11-06: "go file by file and clean it up")

- [ ] `docs/` reorganized: current docs only, finished plans and old task prompts removed.
- [ ] `CLAUDE.md` cut from ~2,100 lines to the rules that are still true (no acts, co-op, King Grubb, crypt, traders).
- [ ] **One source for skill and rite data:** the numbers and text live only in `data/codex/` JSON. Remove the
      duplicates from `data.gd` / `run_talents.gd`, then `code_base.json` and the three-way merge.
- [ ] **Skill IDs match their names** (`pierce` → `fire_arrow`, `snare` → `thunderstep`, `toxic` →
      `pestilence_vial`...), with an alias map for old saves.
- [ ] **Story-mode leftovers removed:** acts A2/A3, LAN/online co-op, the camp's traders and quests, King Grubb, the
      crypt, the Vigil. Check `docs/cleanup.md` for what still depends on each.
- [ ] **Backend audit:** which Nakama collections are still used now that runs aren't saved (character cloud saves,
      the shared stash, the raid stash, the KPI table).
- [ ] Decide on Codex's **online Sandbox** lobby mode (built 2026-11-05, not requested as part of perf).

## Before real players

- [ ] Database backups (there are none today).
- [ ] A production server and database, separate from staging.
- [ ] Steam release branch.

## Game

- [ ] Blaine's play-test feedback on the **Archer** and **Plague Doctor** in the Battlegrounds.
- [ ] The **Obsidian Wyrm's** own kit (held back from runs until it has five skills).
- Later: the Frost Serpent and Storm Wyvern (Blaine: not a priority now).
