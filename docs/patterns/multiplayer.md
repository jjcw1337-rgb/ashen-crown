# Multiplayer shape

Two kinds of multiplayer, deliberately different (Blaine, 2026-11-05):

| | Single player + co-op | Multiplayer modes |
|---|---|---|
| Entry | **Enter World**; friends join your world | **Multiplayer**: the lobby browser |
| Who hosts | the player's own game | our dedicated servers, one process per match |
| Connection | Steam (invites, "Join Game", Steam's relay); LAN and direct address hidden in the lobby browser's "Local network" row | UDP game ports on the droplet |
| Modes | the story, Act I-III | Battlegrounds, survivor Arena 1v1/2v2/3v3, Sandbox practice |
| Host leaves | the session ends; everyone keeps their character | the match runs on |

## The rules

1. **One network layer.** `Net` (`scripts/net.gd`) drives everything through Godot's `MultiplayerPeer`; ENet (LAN,
   dedicated servers) and Steam differ only in the peer that is plugged in. Never write transport-specific game code.
2. **The host is authoritative.** Monsters, loot and damage resolve on the host (or the dedicated server); partners
   send what they do and draw what they are told. A partner's damage reaches the host through the existing RPCs.
   Delayed remote-enemy effects must check `still_joined(peer)` before sending; a world can finish retiring
   after its transport has closed.
3. **Everything a skill shows is an fx event** (see [effects.md](effects.md)), so partners see it without new RPCs.
4. **Peers need compatible RPC sets and simulation behavior.** Exact build-SHA admission was explicitly removed
   for development by Blaine; do not restore it. Client-only presentation changes can interoperate across revisions.
   Changes to the network contract require matching deployment and real client/server tests. A join that reaches
   the host but never receives its welcome offers an update diagnostic; it is not exact-SHA enforcement.
5. **Steam during development is Spacewar (App ID 480)**: real invites and relay from our own builds with Steam
   running. Our own App ID comes later ($100 Steam Direct, needs an admin's OK; then BuildEnv `steam_app_id`).
   `SteamLink` (`scripts/steam_link.gd`, GodotSteam 4.23.2 in `addons/godotsteam`, its `SteamMultiplayerPeer`
   built in) does it all: the pause menu's Invite Friends opens your world (a friends-only Steam lobby, rich presence
   for "Join Game") and hosts through Steam; a friend's invite or "Join Game" joins (`Game.start_join_steam`); the
   lobby browser lists friends' open worlds. Without Steam running nothing changes. Check a build with
   `-- --steam-selftest` (opens and closes a host peer, prints the result, quits).
6. **Friends are Steam friends.** No friends database of our own. A Steam ID is linked to the player's Nakama
   account, so a cross-play friend list could later be imported into Nakama.

Sandbox also has direct solo entry without sign-in or a lobby. Hosted practice uses temporary heroes,
free-for-all damage and respawns; bots and monster packs are solo-only. Waves is currently retired.
See [Sandbox behavior and rollout status](../perf/SANDBOX.md); prepared source is not a deployed feature.
