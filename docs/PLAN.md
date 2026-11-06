# Ashen Crown: project plan

The one to-do list. Everyone (Blaine, jj, every agent) works from this file: add what's asked, tick what's done,
delete what's dropped. Newest decisions win. Started 2026-11-06.

## In flight: the loading and freeze overhaul (Claude-1 took it over from Codex, 2026-11-06)

Codex's 55 commits and its uncommitted work are kept on `backup/codex-release-20261106` (and the local branch
`claude-1/codex-takeover`). They land in stages, each tested and measured against staging before the next:

- [ ] **1. Fixes.** Bug fixes taken from Codex's work, nothing structural: bowstring blow-up on slow frames, arrows
      skipping enemies on long frames, quiet save recovery, the server's shadow-twin buffer, freed-callback crashes,
      story text in run menus, the boot race, the world paused and the 3D view off under the loading screen, the
      Plague Doctor's debris built once, the uncommitted `still_joined` guards on enemy RPCs.
- [ ] **2. One building pattern.** Builders yield with `await world.slice()` in their loops, so every zone builds a
      little per frame under the loading screen. One mechanism (Codex had two: job objects and checkpoints). Camp
      first (its freeze), then fort, coast, islands, the others. Rolls stay in the same order.
- [ ] **3. One loading service.** Replaces ResCache, ZonePreload, the boot preload and Codex's ContentCatalog with
      one: Godot's threaded loader (parallel), **exact recorded file lists** per zone and per class (no whole
      folders), only the classes in the match, released when a zone is left. Done = load into a Battlegrounds
      match no slower than staging and video memory no higher, with the numbers.
- [ ] **4. One warm-up phase** under the loading screen: the match's classes' skills, the zone's monsters, the
      windows, in fast-forward (Codex had slowed it 4x).
- [ ] **5. Docs follow:** `docs/patterns/loading.md` describes exactly that, nothing else.
- Not taken: the scheduled performance audit (`tools/performance_audit/`, its workflow), `docs/perf/` (20 write-ups,
  ~9k lines of logs), the gate's checkpoint/resume machinery, one-off analysis scripts.
- To decide (Blaine): **online Sandbox** as a lobby mode (Codex built it 2026-11-05; on its own branch until then);
  `SurfaceMaterials` (a workaround for a Godot crash; kept only if the crash reproduces).
- [ ] Smith test (`vendor_test`) failed in Codex's last gate: Halvar plays idle/talk clips instead of forging.
      Check whether staging has it too.

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
