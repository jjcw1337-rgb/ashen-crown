# The Arena (game/maps/arena/)

The stone hall where survivors fight in teams (the **Arena** mode) and where anyone practises (the **Sandbox**). This
folder is the template for every map: the map, its pieces, the modes played on it, and their tests, in one place.

| File | What |
|---|---|
| `arena_map.gd` | `ArenaMap`: builds the hall (zones `arena` and `sandbox`, `World.build`) and says where players start (`team_spawn`, `ring_spawn`) |
| `arena_props.gd`, `props/`, `textures/` | `ArenaProps`: the hall's Meshy pieces (pillar, sconce, candles, bones), its wall stone and the see-through on tall pieces |
| `arena_match.gd` | The Arena's rules on its match server: Ember against Frost, rounds of 3 minutes, first to two |
| `sandbox.gd` | `Sandbox`: practice. Solo with bots and monster packs; the temporary hero, its meters and panel |
| `bot_brain.gd` | `BotBrain`: the Sandbox's computer players, playing a hero's real skills the way a decent player would |
| `sandbox_match.gd` | Sandbox online: free-for-all on a match server, automatic respawns, nothing saved |
| `tests/` | `arena_round_test`, `arena_survivor_test`, `lobby_team_test`, `sandbox_test`, `sandbox_entry_test`, `sandbox_lobby_test` |
| `tools/` | `sandbox_shot` (screenshots) |

How a match gets here: the lobby service starts a match server with `--match-config`; `game/systems/net/match_instance.gd`
loads the mode's script from this folder and the zone; players join with their lobby ticket.

Still borrowed from outside, to go when their homes exist:
- `arena_match.gd` extends `Battlegrounds` (`game/maps/verdant_reach/battlegrounds.gd`) for the server's PvP checks (`pvp_pair`,
  statuses, breakable things). Those move to `systems/` with the damage and effect system
  (docs/architecture_cleanup.md, step 3).
- The Arena's state on the client (`Game.arena_mode`, `arena_state`, `Net.cl_arena_state`/`cl_arena_reset`, its HUD in
  `LobbyClient`) still lives in the shared files.
