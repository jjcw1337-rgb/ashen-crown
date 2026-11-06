# Dedicated servers

**Goal:** many game worlds per machine. A server runs the rules (positions, monsters, hits, loot); the players' games
hold every asset and draw everything. Measured on the staging droplet (4 GB, 2 vCPU) on 2026-11-05:

| A Battlegrounds world | Full game as server | Lean server |
|---|---|---|
| RAM | 1.25 GB | ~0.4 GB |
| CPU, empty | 31% of a core | 13% |
| CPU, 6 players fighting | 95% | 24% |

## The rules

1. **Servers run the stripped "Linux Server" export** (`export_presets.cfg`: dedicated server, everything stripped
   to placeholders). Textures have no pixels; meshes keep only their bounding box and have no surfaces. Staging CI
   exports it with the release template (4.4.1; 4.3's segfaulted on it) as the `AshenCrown-server` artifact, which is
   never uploaded to itch or Steam. Its prints flush at once (`run/flush_stdout_on_print.dedicated_server`).
2. **Server code must never need pixels or mesh surfaces.** Anything that reads an image or a mesh's vertices gets a
   guard for the empty case (see `UI._scaled_tex`, `Flora.oak_model`'s leaves). Collision is footprints in code
   (`World.obstacles`), never mesh data.
3. **A server doesn't animate.** `Enemy.server_nopose` (on with `--server`) skips posing bodies nobody sees; bones
   stay in their rest pose. Don't make gameplay depend on a bone's animated position.
4. **A server ticks at 30 fps** (`Battlegrounds.server_tick`; the lobby's match workers too); physics stays at 60.
5. **One process per match, started on Start, never while a lobby waits** (`deploy/lobbies/service.py`). It starts when
   there is room (`COST` per mode: free memory plus headroom, a CPU budget, a free port), else "Servers are full right
   now". A finished match's process quits by itself; each mode has a longest life (`LIMIT`).
6. **Measure a mode's real cost with bots** before changing `COST`: `tools/load_bot.gd` (joins and fights).

## Deploying

`sh deploy/lobbies/update.sh` installs the latest staging CI's server export and the lobby service, refusing while
a match is in progress. Game ports are UDP 24600 + `--ports` (each must be open in the cloud firewall). Announce
restarts in Discord first. See `docs/systems/multiplayer_lobbies.md` for the full setup.
