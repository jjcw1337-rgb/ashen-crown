class_name SteamLink
extends Node
## Co-op through Steam (Blaine, 2026-11-05: single player and co-op merged, "you join your friend's world"). The
## player's own game hosts; friends come in through Steam: an invite, "Join Game" on the friends list, or the lobby
## browser's list of friends' open worlds. The connection is SteamMultiplayerPeer (Steam's relay: no ports, no router
## trouble) plugged into Net like ENet is, so the co-op code is the same. During development the game runs as
## Spacewar (App ID 480, Valve's test app that every Steam account owns); BuildEnv's `steam_app_id` takes over once
## Ashen Crown has its own. Without Steam (no client running, the web build, servers) `ok` is false and nothing
## here does anything. Plugins: addons/godotsteam (GodotSteam 4.15, the last Godot 4.1-4.3 build) and
## addons/steam-multiplayer-peer (ExpressoBits 0.2.1).

const DEV_APP_ID := 480
const LOBBY_TAG := "ashen-crown"      # lobby data "game": Spacewar's lobbies are shared with every developer testing on it

var game
var ok := false
var steam: Object
var lobby := 0                         # the Steam lobby of the world we host or are in (0: none)
var hosting := false
var _join_after_title := 0             # a lobby to join once the title is up (launched by "Join Game")

func setup(g) -> void:
	game = g
	if OS.get_cmdline_user_args().has("--server") or DisplayServer.get_name() == "headless" or OS.has_feature("web"):
		return
	if not Engine.has_singleton("Steam") or not ClassDB.class_exists("SteamMultiplayerPeer"):
		return
	var app := str(BuildEnv.value("steam_app_id")) if str(BuildEnv.value("steam_app_id")) != "" else str(DEV_APP_ID)
	OS.set_environment("SteamAppId", app)
	OS.set_environment("SteamGameId", app)
	steam = Engine.get_singleton("Steam")
	var r: Dictionary = steam.steamInitEx()
	ok = int(r.get("status", 1)) == 0
	if not ok:
		print("[STEAM] not available: ", r.get("verbal", ""))
		return
	print("[STEAM] ready as app %s, %s" % [app, steam.getPersonaName()])
	steam.lobby_created.connect(_on_lobby_created)
	steam.lobby_joined.connect(_on_lobby_joined)
	steam.join_requested.connect(_on_join_requested)
	# launched from a friend's "Join Game": +connect_lobby <id> on the command line
	var a := OS.get_cmdline_args()
	var i := a.find("+connect_lobby")
	if i >= 0 and i + 1 < a.size():
		_join_after_title = int(a[i + 1])

func _process(_delta: float) -> void:
	if not ok:
		return
	steam.run_callbacks()
	if _join_after_title != 0 and game.ui != null and game.ui.title_panel != null and game.ui.title_panel.visible and not game._busy:
		var l := _join_after_title
		_join_after_title = 0
		join_world(l)

# ---------------------------------------------------------------- hosting
## Open the world we're playing to Steam friends (the pause menu's Invite Friends): host through Steam, make a
## friends-only lobby friends can join from their friends list, then show Steam's invite dialog.
func invite() -> void:
	if not ok:
		return
	if not hosting:
		if game.net.active:
			game.ui.message("You're already in a co-op game.", Color(1, 0.6, 0.45))
			print("[STEAM] invite: already in a co-op game")
			return
		var p: MultiplayerPeer = ClassDB.instantiate("SteamMultiplayerPeer")
		var err: int = p.call("create_host", 0)
		if err != OK or game.net.host_with(p) != OK:
			game.ui.message("Steam couldn't open your world to friends.", Color(1, 0.5, 0.4))
			print("[STEAM] invite: create_host failed (%d)" % err)
			return
		hosting = true
		steam.createLobby(steam.LOBBY_TYPE_FRIENDS_ONLY, Net.MAX_CLIENTS + 1)
		game.ui.message("Your world is open to your Steam friends.", Color(0.5, 1.0, 0.5))
	if lobby != 0:
		steam.activateGameOverlayInviteDialog(lobby)

func _on_lobby_created(result: int, id: int) -> void:
	if result != 1 or not hosting:
		return
	lobby = id
	steam.setLobbyData(lobby, "game", LOBBY_TAG)
	steam.setLobbyData(lobby, "host", str(game.char_name))
	steam.setLobbyData(lobby, "act", ["Act I", "Act II", "Act III"][clampi(int(game.difficulty), 0, 2)])
	steam.setRichPresence("connect", "+connect_lobby %d" % lobby)
	steam.setRichPresence("status", "Playing %s" % str(game.char_name))
	steam.activateGameOverlayInviteDialog(lobby)

## Our world closes (back to the title, or the network shut down): friends see it gone.
func close_world() -> void:
	if not ok:
		return
	if lobby != 0:
		steam.leaveLobby(lobby)
	lobby = 0
	hosting = false
	steam.clearRichPresence()

# ---------------------------------------------------------------- joining
## A friend's "Join Game" or an accepted invite, while we're running.
func _on_join_requested(id: int, _friend: int) -> void:
	join_world(id)

func join_world(id: int) -> void:
	if not ok or id == 0:
		return
	if game.playing:
		await game.exit_to_title()
	steam.joinLobby(id)

func _on_lobby_joined(id: int, _permissions: int, _locked: bool, response: int) -> void:
	if hosting:
		return
	if response != 1:
		game.ui.message("That world is closed now.", Color(1, 0.6, 0.45))
		return
	var owner: int = steam.getLobbyOwner(id)
	if owner == 0 or owner == steam.getSteamID():
		return
	lobby = id
	game.start_join_steam(owner)

## A client's peer to the friend hosting the world.
func client_peer(owner: int) -> MultiplayerPeer:
	var p: MultiplayerPeer = ClassDB.instantiate("SteamMultiplayerPeer")
	return p if p.call("create_client", owner, 0) == OK else null

## Steam friends whose open world we can join (the lobby browser's list): [{name, lobby}].
func friends_worlds() -> Array:
	var out: Array = []
	if not ok:
		return out
	var flag: int = steam.FRIEND_FLAG_IMMEDIATE
	for i in steam.getFriendCount(flag):
		var f: int = steam.getFriendByIndex(i, flag)
		var played: Dictionary = steam.getFriendGamePlayed(f)
		if played.is_empty() or int(played.get("id", 0)) != int(OS.get_environment("SteamAppId")):
			continue
		var l := int(played.get("lobby", 0))
		if l != 0:
			out.append({"name": steam.getFriendPersonaName(f), "lobby": l})
	return out
