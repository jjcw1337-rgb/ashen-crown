class_name SteamLink
extends Node
## Co-op through Steam (Blaine, 2026-11-05: single player and co-op merged, "you join your friend's world"). The
## player's own game hosts; friends come in through Steam: an invite, "Join Game" on the friends list, or the lobby
## browser's list of friends' open worlds. The connection is SteamMultiplayerPeer (Steam's relay: no ports, no router
## trouble) plugged into Net like ENet is, so the co-op code is the same. During development the game runs as
## Spacewar (App ID 480, Valve's test app that every Steam account owns); BuildEnv's `steam_app_id` takes over once
## Ashen Crown has its own. Without Steam (no client running, the web build, servers) `ok` is false and nothing
## here does anything. Plugin: addons/godotsteam (GodotSteam 4.23.2 GDExtension for Godot 4.4+, its
## SteamMultiplayerPeer built in: one plugin, one Steam library; on 4.3 two plugins couldn't share Steam in a release
## macOS export).

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
	var r: Dictionary = steam.steamInitEx(int(app), false)
	ok = int(r.get("status", 1)) == 0
	if not ok:
		print("[STEAM] not available: ", r.get("verbal", ""))
		return
	print("[STEAM] ready as app %s, %s" % [app, steam.getPersonaName()])
	if OS.get_cmdline_user_args().has("--steam-selftest"):
		# (an exported build's check that both Steam plugins share one Steam library: a host peer opens and closes)
		var sp: MultiplayerPeer = ClassDB.instantiate("SteamMultiplayerPeer")
		var e: int = sp.call("create_host", 0)
		printerr("[STEAM] selftest: app %s, host peer %s" % [app, "OK" if e == OK else "failed (%d)" % e])
		sp.close()
		get_tree().quit(0 if e == OK else 1)
	steam.lobby_created.connect(_on_lobby_created)
	steam.lobby_joined.connect(_on_lobby_joined)
	steam.join_requested.connect(_on_join_requested)
	game.net.multiplayer.peer_connected.connect(_on_peer_connected)
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
	elif lobby == 0:
		steam.createLobby(steam.LOBBY_TYPE_FRIENDS_ONLY, Net.MAX_CLIENTS + 1)     # (the last try failed: again)
	if lobby != 0:
		pick_friend()

## Who to invite: Steam's own dialog when its overlay runs (a game started from Steam), else our window
## (a game started from the itch app has no overlay: Blaine, 2026-11-06, "it didn't let me pick a person").
func pick_friend() -> void:
	if lobby == 0:
		return
	if steam.isOverlayEnabled():
		steam.activateGameOverlayInviteDialog(lobby)
	else:
		_open_picker()

func _on_lobby_created(result: int, id: int) -> void:
	if result != 1 or not hosting:
		if hosting:
			print("[STEAM] lobby not created (Steam result %d)" % result)
			game.ui.message("Steam couldn't open your world to friends right now. Try Invite Friends again.", Color(1, 0.6, 0.45))
		return
	lobby = id
	steam.setLobbyData(lobby, "game", LOBBY_TAG)
	steam.setLobbyData(lobby, "host", str(game.char_name))
	steam.setLobbyData(lobby, "act", ["Act I", "Act II", "Act III"][clampi(int(game.difficulty), 0, 2)])
	steam.setRichPresence("connect", "+connect_lobby %d" % lobby)
	steam.setRichPresence("status", "Playing %s" % str(game.char_name))
	pick_friend()

## Our world closes (back to the title, or the network shut down): friends see it gone.
func close_world() -> void:
	if not ok:
		return
	if lobby != 0:
		steam.leaveLobby(lobby)
	lobby = 0
	hosting = false
	steam.clearRichPresence()
	if _picker != null and is_instance_valid(_picker):
		_picker.hide()

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

## Steam friends who are online: [{name, id, here, recent}]: those in Ashen Crown now first, then the ones you played
## with most recently (Steam's "recently played with", fed by setPlayedWith when someone joins), then by name.
func online_friends() -> Array:
	var out: Array = []
	if not ok:
		return out
	var flag: int = steam.FRIEND_FLAG_IMMEDIATE
	var app := int(OS.get_environment("SteamAppId"))
	for i in steam.getFriendCount(flag):
		var f: int = steam.getFriendByIndex(i, flag)
		if int(steam.getFriendPersonaState(f)) == 0:
			continue          # offline
		var played: Dictionary = steam.getFriendGamePlayed(f)
		out.append({"name": steam.getFriendPersonaName(f), "id": f, "here": int(played.get("id", 0)) == app,
			"recent": int(steam.getFriendCoplayTime(f))})
	out.sort_custom(func(x, y):
		if x["here"] != y["here"]:
			return x["here"]
		if x["recent"] != y["recent"]:
			return x["recent"] > y["recent"]
		return str(x["name"]).nocasecmp_to(str(y["name"])) < 0)
	return out

## Someone joined our world, or we joined theirs, over Steam: tell Steam we played together (its "recently played
## with", which orders the invite list).
func _on_peer_connected(pid: int) -> void:
	var p: MultiplayerPeer = game.net.peer
	if not ok or p == null or not p.has_method("get_steam64_from_peer_id") or not steam.has_method("setPlayedWith"):
		return
	var sid: int = int(p.call("get_steam64_from_peer_id", pid))
	if sid != 0:
		steam.setPlayedWith(sid)

## Invite one friend to our open world: Steam sends them the invite (a Join Game in their Steam chat).
func invite_friend(id: int) -> bool:
	return ok and lobby != 0 and bool(steam.inviteUserToLobby(lobby, id))

var _picker: PanelContainer
var _picker_rows: VBoxContainer

## Our Invite a Friend window: the online friends, Ashen Crown players first, an Invite button each.
func _open_picker() -> void:
	var ui = game.ui
	if _picker == null or not is_instance_valid(_picker):
		_picker = PanelContainer.new()
		_picker.name = "steam_invite"
		ui._ornate(_picker, 0.22, 14)
		ui.menus.add_child(_picker)
		var vb := VBoxContainer.new()
		vb.add_theme_constant_override("separation", 10)
		_picker.add_child(vb)
		vb.add_child(ui._label("INVITE A FRIEND", 26, ui.GOLD, true))
		vb.add_child(ui._label("Your Steam friends who are online. They get a Join Game invite in Steam;\nthey need Ashen Crown running to come in.", 15, ui.DIM))
		var sc := ScrollContainer.new()
		sc.custom_minimum_size = Vector2(560, 360)
		sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		vb.add_child(sc)
		_picker_rows = VBoxContainer.new()
		_picker_rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_picker_rows.add_theme_constant_override("separation", 6)
		sc.add_child(_picker_rows)
		var close: Button = ui._iron_button("Close", 180, 44, 18)
		close.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		close.pressed.connect(func(): _picker.hide())
		vb.add_child(close)
	for c in _picker_rows.get_children():
		c.queue_free()
	var friends := online_friends()
	for f in friends:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		var n: Label = ui._label(str(f["name"]), 18, Color(0.95, 0.9, 0.8))
		n.custom_minimum_size.x = 260
		n.clip_text = true
		row.add_child(n)
		var st: Label = ui._label("in Ashen Crown" if f["here"] else ("played recently" if int(f["recent"]) > 0 else "online"), 14, ui.GOLD if f["here"] else ui.DIM)
		st.custom_minimum_size.x = 140
		row.add_child(st)
		var b: Button = ui._iron_button("Invite", 130, 40, 17)
		var fid: int = int(f["id"])
		b.pressed.connect(func():
			if invite_friend(fid):
				b.text = "Invited"
				b.disabled = true
			else:
				game.ui.message("Steam couldn't send that invite.", Color(1, 0.6, 0.45)))
		row.add_child(b)
		_picker_rows.add_child(row)
	if friends.is_empty():
		_picker_rows.add_child(ui._label("No Steam friends online right now.", 17, ui.DIM))
	_picker.reset_size()
	var vp: Vector2 = _picker.get_viewport_rect().size
	_picker.position = (vp - _picker.get_combined_minimum_size()) * 0.5
	_picker.show()
