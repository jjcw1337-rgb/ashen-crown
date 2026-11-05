# Multiplayer shape

Two kinds of multiplayer, deliberately different (Blaine, 2026-11-05):

| | Single player + co-op | Multiplayer modes |
|---|---|---|
| Entry | **Enter World**; friends join your world | **Multiplayer**: the lobby browser |
| Who hosts | the player's own game | our dedicated servers, one process per match |
| Connection | Steam (invites, "Join Game", Steam's relay); LAN and direct address hidden in the lobby browser's "Local network" row | UDP game ports on the droplet |
| Modes | the story, Act I-III | Battlegrounds, Arena 1v1/2v2/3v3, Endless Waves |
| Host leaves | the session ends; everyone keeps their character | the match runs on |

## The rules

1. **One network layer.** `Net` (`scripts/net.gd`) drives everything through Godot's `MultiplayerPeer`; ENet (LAN,
   dedicated servers) and Steam differ only in the peer that is plugged in. Never write transport-specific game code.
2. **The host is authoritative.** Monsters, loot and damage resolve on the host (or the dedicated server); partners
   send what they do and draw what they are told. A partner's damage reaches the host through the existing RPCs.
3. **Everything a skill shows is an fx event** (see [effects.md](effects.md)), so partners see it without new RPCs.
4. **Every peer runs the same build**: RPC ids depend on each script's RPC set. The game says when versions differ.
5. **Steam during development is Spacewar (App ID 480)**: real invites and relay from our own builds with Steam
   running. Our own App ID comes later ($100 Steam Direct, needs an admin's OK).
6. **Friends are Steam friends.** No friends database of our own. A Steam ID is linked to the player's Nakama
   account, so a cross-play friend list could later be imported into Nakama.
