# Ashen Crown: project plan

The one to-do list. Everyone (Blaine, jj, every agent) works from this file: add what's asked, tick what's done,
delete what's dropped. Newest decisions win. Started 2026-11-06.

## Done today: the loading and freeze overhaul (Claude-1, taken over from Codex, 2026-11-06)

Codex's work is kept on `backup/codex-release-20261106`. Landed on staging, each tested and measured:
- [x] Its bug fixes and the **online PvP Sandbox** (`a4eddb1`); lobby service and match servers updated.
- [x] **One loader** (`ResCache` on Godot's threaded loader, scopes, exact recorded lists for every zone) and the
      lobby's **Start countdown** (`83a2900`): same load speed as before, less video memory.
- [x] **No world behind the title** (`2ffca18`): trailer end -> title 1.8 s -> 0.37 s, worst frame 1.29 s -> 0.12 s.
- Not taken: the scheduled audit, `docs/perf/`, the gate's resume machinery, `SurfaceMaterials`, Codex's
  ContentCatalog and its worker thread.
- [ ] The old co-op story test failed once in two reruns after stage 1 (player B missed the partner's kill); co-op
      is retired, so it goes with the co-op cut.
- [ ] Zone builds still run in one go under their loading screen (the camp ~0.9 s, its waypoint 0.5 s); slice them
      only if a loading screen needs to animate.

## Code cleanup: see docs/architecture_cleanup.md

The agreed order (folders per hero, reference recordings, the damage and effect system, one data source, real ids)
and the cuts are in `docs/architecture_cleanup.md`; its status lines are the to-do list. Also:
- [ ] **Backend audit:** which Nakama collections are still used now that runs aren't saved (character cloud saves,
      the shared stash, the raid stash, the KPI table).
- [ ] The ~170 test scripts wait for a world at boot (`Game._harness_camp` keeps the camp built for them); move
      them to `-- --real-boot` as they're touched.

## Before real players

- [ ] Database backups (there are none today).
- [ ] A production server and database, separate from staging.
- [ ] Steam release branch.

## Game

- [ ] Blaine's play-test feedback on the **Archer** and **Plague Doctor** in the Battlegrounds.
- [ ] The **Obsidian Wyrm's** own kit (held back from runs until it has five skills).
- Later: the Frost Serpent and Storm Wyvern (Blaine: not a priority now).
