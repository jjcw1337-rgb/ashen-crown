# In-game chat (game/ui/chat/)

A match's chat: Enter opens the line (bottom left), Enter sends, Escape closes; `/t` at the start sends to your
team only (a Battlegrounds duo's pair, an Arena team). While it's open the line glows neon, its border and glow
drifting green to blue under a TYPING tag, so it's plain your keys type, not cast. Lines fade after 12 s; the whole log shows while typing.

| File | What |
|---|---|
| `chat_box.gd` | `ChatBox`: the log and the line (UI.chat, made by `ChatBox.attach`); `add` shows what the server relays |

The network side is in `game/systems/net/net.gd` ("chat"): `send_chat` → `sv_chat` (the server: the sender's name from its own
records, CHAT_MAX characters, at most CHAT_RATE lines in CHAT_WINDOW s, team lines by `Battlegrounds.team_of`) →
`cl_chat`. While the line is open the hero doesn't walk (`Game.wasd_dir`). Tested in
`game/maps/verdant_reach/tests/bg_pvp_test.gd` (a line reaches the other player, a team line doesn't reach a foe,
a flood is cut).
