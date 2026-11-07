# The multiplayer page (game/ui/lobby/)

The game's home screen: the lobby browser for the Battlegrounds (solo or duo), the Arena and the Sandbox, and each
lobby's room (members, class or survivor, pairs or teams, ready, start).

| File | What |
|---|---|
| `lobby_client.gd` | `LobbyClient`: talks to the lobby service (deploy/lobbies/service.py): list, create, join, pick, ready, start; hands a started match's ticket to the game |
| `mp_lobby_view.gd` | `MpLobbyView`: the page itself: the mode tabs, the list, a lobby's room, the class tiles, the pair picker |
| `mp_style.gd` | `MpStyle`: its look (buttons, labels, tags) |
| `lobby_stage.gd` | `TitleStage`: the 3D stage behind the page, where the chosen class stands |
| `lobby_stakes.gd` | the Arena's item stakes (dormant: no lobby offers them yet) |
| `tests/` | `lobby_ui_test` (the page at three sizes), `lobby_game_test`, `lobby_modes_test`, `lobby_late_join_test`, `lobby_stakes_test`, `mp_test` |
| `tools/` | `mp_lobby_shots` |

The rest of the screens are still in `scripts/ui.gd` (HUD, run windows, menus) and `scripts/run_ui.gd`, to be split
into `game/ui/<screen>/`.
