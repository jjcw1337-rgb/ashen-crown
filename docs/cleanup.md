# Retired features: what's hidden, what still depends on it, when it can go

The multiplayer overhaul (Blaine, 2026-11-06) retires features by switching them off in one place
(`scripts/mp_mode.gd`, `MpMode`) before deleting anything. Each row: what's off, where the switch acts, the code that
stays and why, and the condition for deleting it.

| Retired | Switch / where it acts | Code kept | Delete when |
|---|---|---|---|
| **Endless Waves** (the Last Flame) | `MpMode.WAVES = false`: the lobby browser offers no Waves mode or solo start (`LobbyClient`), the waypoints list no "vigil" activity (`Game.waypoint_activities`, `waypoint_activity_go`), the camp's Vigil Gate says it is sealed (`Game._interact` "vigil_gate"), and the lobby service refuses new Waves lobbies (`service.py` `LIVE_MODES`) | `vigil.gd`, `flame_board.gd` (the leaderboard), the Vigil zone in `World.build`, `match_instance.gd`'s waves branch, `Net`'s vigil RPCs (`vigil_feed`, `request_vigil`, `vigil_hi`) and the Nakama leaderboard | no save, test or tool loads the Vigil zone (`tools/nightly_vigil_test.gd` and `vigil_test` are the last users: retire them with it) and nobody wants the mode back |
| **Create New Character** on the title | `MpMode.CREATE_CHARACTER = false`: the sidebar's button is hidden (`TitleHome._build_sidebar`) | the class picker (`UI._build_class_picker`, `ClassStage`), `UI._title_choose("new")` and character saves: single player's Enter World loads characters, and the Battlegrounds lobby's class choice reuses the class stage | single player gets its own way to make a character, or the old characters are migrated |
| **Lobby modes** other than Battlegrounds and Arena | `MpMode.MODES` (the game), `LIVE_MODES` (the lobby service) | `service.py`'s `MODES` capacity table keeps `waves` so a lobby made before the switch still finishes | no `waves` lobby in any state database |
| **The always-on co-op server** (pending) | not yet: waits for Steam co-op to be confirmed by a two-player test | `coop_server.gd`, `ashen-crown-coop.service`, the party queue (`party_queue*.gd`) | Steam co-op confirmed; then stop the service on the droplet and remove the co-op tab's leftovers |

Rules: hide the entry points and stop the execution paths first; delete self-contained code once nothing uses it;
no commented-out blocks; one row here per retired feature, removed when its code is.
