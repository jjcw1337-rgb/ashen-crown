# Multiplayer lobbies and arena

The post-intro home has Single Player, Co-op and Multiplayer. Multiplayer opens one browser for
Battlegrounds, The Last Flame (endless waves) and Arena. The same browser is available from the
in-game waypoint, using the current character. Sandbox remains an admin test tool.

## Player flow

Create a lobby, select Arena team size (1v1, 2v2 or 3v3), join a team, mark Ready, and let the owner
press Start. Joining or changing teams/stakes clears readiness. The owner transfers to another
member if they leave before starting. Stale waiting members expire after 90 seconds.

Waiting lobbies allocate no Godot world. Starting allocates a free server slot and issues one-time
admission tickets. The browser waits for the worker to listen before transferring players. Arena
requires full balanced teams; waves and Battlegrounds can start alone. Active wave games and raids
inside their entry window appear in the same list and accept late joins. Arena closes entry at Start.
A full server leaves the waiting lobby intact and explains that a match slot is occupied.

Arena uses the existing Proving Crypt geometry and PvP combat rules. Teams are Ember and Frost,
friendly fire is excluded, each round has a countdown, and the first team to win two rounds wins.
A round lasts at most three minutes; remaining team health breaks a timeout. Tied rounds replay,
with a draw after seven total rounds. Disconnecting counts as leaving the fight, not a free reset.
Casual arena uses a temporary character copy and restores the saved character afterwards.

The Last Flame has a direct solo entry and multiplayer lobby entry. Multiplayer kindles the flame
once participants arrive. No story/Vigil unlock is required to enter from Multiplayer.
Battlegrounds retains its extraction and full-loot rules, but the lobby owner starts each raid.
An empty or completed instance exits instead of starting another empty round.

## Optional item matches

The current rule is **one selected bag item per player**, explicitly locked before Ready. The lobby
shows every stake. Everyone must accept the final stakes with Ready; the owner cannot change stakes
after acceptance. The winning team keeps its own stakes and splits losing stakes in roster order.
Cancelling before play, startup failure, a server crash or a drawn match refunds stakes. Disconnecting
during a running fight does not refund a stake automatically. Ordinary equipped/carried items are
not wagered merely by enabling this option.

The service records settlement receipts in SQLite. The client removes a locked item from the save
with an atomic journal/removal marker, then applies a receipt once to its original character. Full
bags leave rewards pending. Collect Arena Rewards on the home lobby screen retries them. Interrupted
journal writes/removals and repeated receipts are covered by tests. The escrow journal is deliberately
not a `.json` character file.

**Trust boundary:** ordinary heroes and their inventories are still editable offline saves, and the
existing combat transport trusts client state. This is private/unranked item play, not a cheat-proof
ranked economy. The service prevents ticket reuse, duplicate committed UIDs and repeated settlement;
it does not prove that a client legitimately earned an item. Competitive item play needs authoritative
inventory ownership and combat validation, not just more lobby processes.

## Server setup and capacity

This is the DigitalOcean droplet, not Dropbox. The existing deployed setup runs persistent Godot BG
and co-op worlds beside Nakama/Postgres and monitoring. On 2026-11-05 at 00:56 UTC the 4 GB / 2 vCPU
host had about 688 MB available RAM and 893 MB swap in use. Three Godot processes were observed; this
change did not stop or alter them. A later read-only check at 01:58 UTC showed ~1708 MB available,
but all 2047 MB of swap in use, load 2.11, and three Godot processes still running. Available RAM
alone is not evidence of safe additional capacity. The existing host was **not** already configured to allocate one
independent process per user-created lobby.

The new lightweight Python service authenticates existing Nakama sessions, stores lobby state and
receipts in SQLite, and starts an imported Godot release only on Start. Each match has its own process,
UDP port, world, participants and lifecycle. Match workers redeem admission tickets over a loopback
HTTP endpoint. The public API is HTTPS `/lobbies`; `/worker` must never be reverse-proxied publicly.
A manager restart aborts uncertain matches and refunds stakes; systemd kills its old child workers.

**Measured capacity (Blaine's audit, 2026-11-05)**, on this droplet with bot players (`tools/load_bot.gd`):
the full game release as a server holds 1.25 GB per world whatever happens in it (it loads every texture
and sound); the stripped **Linux Server** export (CI artifact `AshenCrown-server`) 393-476 MB. With servers
not posing bodies and ticking at 30 fps, a Battlegrounds world costs ~13% of a core empty and ~24% with six
players fighting (was 31% / 95%). The map is the base cost; each fighting player adds a little.

So there is **no fixed slot count**: `service.py` starts a match when there is room for it (`COST` per mode:
free memory for its world plus `--min-free-mb` headroom, a CPU budget of `--cpu-budget` x cores less
`--reserve-cpu` for the backend, a free port among `--ports` from `--first-port`), else every player in
the lobby reads "Servers are full right now" and the lobby stays open. `--slots` is only a hard ceiling.
A bigger machine simply holds more. Each mode has its own longest life (`LIMIT`); a finished match's
process quits by itself (the 30 s stop is only for one that hangs). The unit lets the manager and its
matches use 2.8 GB and 180% CPU; open UDP `24600-24615` in the cloud firewall for them.

`sh deploy/lobbies/update.sh [ci-run]` installs the latest staging CI's server export and this checkout's
service and unit (`/opt/ashen-crown/staging/server/current`, `/opt/ashen-crown/staging/lobbies/service.py`)
and restarts the manager, refusing while a match is starting or playing.

## Preview and rollout

1. Build/import the matching Linux release **off-host**. The checked-in staging deploy script still
   performs a capped import on the droplet; do not use that path for this rollout. Use the Linux
   preview export (executable plus PCK) or a fully imported Linux release prepared in CI.
   For an exported build, point `--godot` at its Linux executable, keep its PCK alongside it, and
   place a `DEPLOYED_REV` file containing the same seven-character build revision in `--game`.
   Keep the previous release for rollback. Client and worker Net RPC signatures must match, including
   the existing co-op server if these clients use Co-op. The manager pins its worker release path; restart it deliberately for a new worker release.
   Private development does not gate admission on client build revisions (Blaine, 2026-11-05).
   New cosmetic/client builds can connect without a server redeploy. RPC or shared gameplay changes
   still need an actual multiplayer test and, when necessary, a worker/co-op update.
2. Verify the actual deployment user, Godot binary, release path, Nakama loopback port and existing
   services before installing `deploy/lobbies/ashen-crown-lobbies.service`; it is a template.
3. Configure the authenticated HTTPS site's Caddy routing, before Nakama's catch-all:

   ```caddyfile
   handle /lobbies {
       request_body {
           max_size 16KB
       }
       reverse_proxy 127.0.0.1:7352
   }
   ```

   Keep `/worker` loopback-only. Do not run `--dev` on a remotely accessible service. No new secret is
   embedded in clients: the browser uses the current Nakama bearer session over HTTPS. Workers use
   random per-match keys in mode-0600 manifests. Use the existing protected BG server configuration
   for server-side Nakama stash/admin RPCs; never place it in the repository.
4. Coordinate retirement of the old permanent BG world, then start the manager with `--slots 1`.
   Open **UDP 24600** in the host/cloud firewall for that slot. Each additional approved slot needs
   another UDP port, more measured capacity, and a larger unit budget. HTTPS remains the lobby API.
   Existing co-op queue ports are separate and are not required by these three modes.
5. Deploy matching preview clients with `lobby_url` pointing at the site's HTTPS origin (staging
   builds derive it from Nakama's configured URL). Verify authenticated remote discovery, two-client
   joins, late joins, arena results, item refunds, disconnects and worker cleanup before public release.
6. Monitor manager restarts, per-worker logs and host pressure. Retain SQLite receipts across release
   changes and back up the state directory. Old terminal worker logs/manifests can be archived after
   review; do not delete unclaimed receipts or reuse a new empty database during an ordinary upgrade.

No server, firewall, service restart or production release is performed by this code change.

## Local verification

Use a separately imported worktree and isolated saves. Example:

```sh
python3 -m unittest discover -s deploy/lobbies -v
python3 deploy/lobbies/service.py --dev --state /tmp/ashen-lobby-test --game "$PWD" --godot /path/to/godot
# Separate terminals, with the same build:
godot --path . --script tools/lobby_game_test.gd -- a wager
godot --path . --script tools/lobby_game_test.gd -- b wager
godot --headless --path . --script tools/lobby_stakes_test.gd
godot --path . --script tools/lobby_modes_test.gd
```

The network tests create disposable heroes in separate test directories. Review **all** client and
worker logs for runtime/parse errors and shutdown warnings, not just assertion totals.

Godot 4.3's dummy renderer still reports `mesh_get_surface_count: Parameter "m" is null` while
creating/freeing mesh scenes in headless runs. This matches the upstream
[confirmed headless mesh issue](https://github.com/godotengine/godot/issues/86806); these runs are
not clean error-free passes. The separate BG scenery leak (instantiating props before rejecting
placement) and headless icon renderer awaiting a nonexistent draw frame are fixed here. An engine
upgrade is outside this change and would need its own compatibility/visual validation.
