class_name Net
extends Node
## LAN co-op. The host runs the monsters, loot, chests and the boss. Every player runs their
## own knight and streams its pose to the others, who show it as a puppet. The party always
## shares one area: whoever walks through an exit or portal takes everyone along.

const PORT := 24567
const DISCO_PORT := 24568
const MAX_CLIENTS := 3
const STYLES := ["over", "back", "side", "thrust", "bow", "cast", "claw", "slam", "bite", "smash", "lob", "scoop", "burst", "cackle", "swipe1", "swipe2", "swipe3", "cleave", "feral_lunge", "feral_swipe", "perch", "descend", "skirm_lunge", "reaver_cleave", "stalk_hook", "bear_roar", "bear_maul", "sloth_walk", "sloth_run", "sloth_rise", "sloth_look", "sloth_stare", "sloth_roar", "sloth_drop", "sloth_sniff", "sloth_sweep", "sloth_slam", "sloth_pounce",
	"rend", "siphon", "wstep", "grasp", "phantom", "night_rise", "night_scream", "night_hold", "night_fall",
	"pd_flask", "pd_volatile", "pd_trap", "pd_slam", "pd_dome", "pd_inspect",
	"fists", "icharge", "cslam", "hurl", "grip", "wrath_roar", "wrath_stomp", "chop",
	"pd_swarm", "pd_bloom", "pd_fog", "pd_transfuse", "pd_crank",
	"pie", "peels", "slide", "doppel", "juggle", "bounce", "car",
	"icharge_wind", "icharge_skid", "hurl2", "grip_throw", "grip_haul", "crucible", "breath", "dive"]
const SEND_RATE := 0.05
const ALLY_COLORS := [Color(0.45, 0.8, 1.0), Color(0.5, 1.0, 0.5), Color(1.0, 0.6, 0.9)]

var game: Node
var peer: MultiplayerPeer            # ENet (LAN, dedicated servers) or Steam (SteamLink)
var active := false
var is_host := false
## A dedicated server (Battlegrounds, `-- --server`): the host has no player of its own, so it never streams its
## hero, isn't in the roster partners see, and refuses party travel (Battlegrounds.gd).
var server := false

## A dedicated server takes no party travel (each player comes and goes on their own); a player's own host does.
func refuses_travel() -> bool:
	return server
var my_name := "Crusader"
var players := {}          # peer id -> {"name": String, "hero": Hero}
var enemies := {}          # net id -> Enemy
var items := {}            # net id -> GroundItem
var next_id := 1
var loading := false
var pending_ready: Array = []
var travel_cool := 0.0
var _send_t := 0.0
var _disco_t := 0.0
var disco: PacketPeerUDP
var listening := false
var found := {}            # ip -> {"name": String, "zone": String, "t": float}
var _clock := 0.0
var party_box: VBoxContainer
var status_lbl: Label

func setup(g: Node) -> void:
	game = g
	name = "Net"
	my_name = OS.get_environment("USERNAME")
	if my_name == "":
		my_name = OS.get_environment("USER")
	if my_name == "":
		my_name = "Crusader"
	my_name = my_name.capitalize().substr(0, 16)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected)
	multiplayer.connection_failed.connect(_on_connect_failed)
	multiplayer.server_disconnected.connect(_on_server_gone)
	_build_party_ui()

func is_client() -> bool:
	return active and not is_host

# ---------------------------------------------------------------- hosting / joining
func host(port := PORT, max_clients := MAX_CLIENTS) -> int:
	shutdown()
	var e := ENetMultiplayerPeer.new()
	var err := e.create_server(port, max_clients)
	if err != OK:
		return err
	peer = e
	multiplayer.multiplayer_peer = peer
	active = true
	is_host = true
	disco = PacketPeerUDP.new()
	disco.set_broadcast_enabled(true)
	disco.set_dest_address("255.255.255.255", DISCO_PORT)
	_update_status()
	return OK

## A join that reached the server (`reached`) but was never welcomed (`welcomed`): the server runs a different
## version of the game. Its RPCs don't match ours (Godot drops every call with "rpc node checksum failed" and the
## connection just hangs), so the message says to update rather than "no answer".
var reached := false
var welcomed := false

func join_failure(fallback: String) -> String:
	if game.bg_wait_until > Time.get_ticks_msec():
		return "The raid is closing. The next opens in %s." % game.bg_wait_text()
	if game.bg_refusal == "boosted":
		return "Only admins can raid in \"Go to level 20\" gear. Take it off, or pick another character."
	if game.bg_refusal != "":
		return "The raid server couldn't confirm your account. Try again in a moment."
	if reached and not welcomed:
		return "That server runs a different version of the game than yours (%s · %s). Update the game (in the itch app: Update), then try again." % [BuildEnv.env(), BuildEnv.value("rev")]
	return fallback

## Host through a peer made elsewhere (SteamLink's Steam peer): the same as host() from here on, no LAN broadcast.
func host_with(p: MultiplayerPeer) -> int:
	shutdown()
	peer = p
	multiplayer.multiplayer_peer = peer
	active = true
	is_host = true
	_update_status()
	return OK

## Join through a peer made elsewhere (SteamLink: a friend's world through Steam).
func join_with(p: MultiplayerPeer) -> int:
	shutdown()
	reached = false
	welcomed = false
	peer = p
	multiplayer.multiplayer_peer = peer
	active = true
	is_host = false
	loading = true
	return OK

func join(ip: String, port := PORT) -> int:
	shutdown()
	reached = false
	welcomed = false
	var e := ENetMultiplayerPeer.new()
	var err := e.create_client(ip, port)
	if err != OK:
		return err
	peer = e
	multiplayer.multiplayer_peer = peer
	active = true
	is_host = false
	loading = true
	return OK

func shutdown(retiring := false) -> void:
	if retiring:
		# This dedicated worker is exiting; polling a closed peer would clear its
		# RPC cache before tree-exit notifications can remove the tracked nodes.
		get_tree().multiplayer_poll = false
	for pid in players.keys():
		_remove_player(pid)
	players.clear()
	enemies.clear()
	items.clear()
	if peer:
		peer.close()
	# A retiring match frees its RPC nodes next. Let their tree-exit notifications clear
	# the cache first: Godot 4.3 release exports otherwise disconnect an unbound
	# tree_exited callback in SceneCacheInterface.clear(). No new peer is needed.
	if not retiring:
		multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	peer = null
	active = false
	is_host = false
	loading = false
	vote = {}
	if game and game.ui:
		game.ui.party_vote_end()
	if disco and not listening:
		disco.close()
		disco = null
	_update_status()

## Joiner side: listen for host announcements on the local network.
func start_listening() -> void:
	if listening:
		return
	disco = PacketPeerUDP.new()
	if disco.bind(DISCO_PORT) != OK:
		disco = null
		return
	listening = true
	found.clear()

func stop_listening() -> void:
	if listening and disco:
		disco.close()
	disco = null
	listening = false

func local_ips() -> Array:
	var out := []
	for a in IP.get_local_addresses():
		if a.begins_with("192.168.") or a.begins_with("10.") or (a.begins_with("172.") and a.split(".").size() == 4 and int(a.split(".")[1]) >= 16 and int(a.split(".")[1]) <= 31):
			out.append(a)
	return out

func _on_connected() -> void:
	reached = true
	# the character the lobby admitted: a run's hero ("run_<class>") has no saved character id (Game._start_run_raid
	# clears it), and the match turned away every Battlegrounds join while the empty id was sent (2026-11-06)
	var admitted_as: String = game.char_id
	if game.lobby_client != null and game.lobby_client.match_id != "":
		admitted_as = str(game.lobby_client.character)
	rpc_id(1, "sv_hello", my_name, game.hero.net_gear(), game.hero.level, game.party_join_ticket, admitted_as)
	game.party_join_ticket = ""
	if game.bg_mode and (game.lobby_client == null or game.lobby_client.match_id == ""):
		# with accounts on: a one-time join ticket from Nakama (over HTTPS), never the session itself
		var ticket := ""
		if game.cloud != null and game.cloud.signed_in:
			var link := peer
			var r: Dictionary = await game.cloud.nk.user_rpc("bg_ticket", {})
			ticket = str(r.get("ticket", ""))
			if not still_joined(link):
				return
		rpc_id(1, "sv_bg_hello", Battlegrounds.client_id(), ticket)

func _on_connect_failed() -> void:
	shutdown()
	game.on_net_failed("Could not connect to that game.")

func _on_server_gone() -> void:
	var why := join_failure("The host left the game.")
	shutdown()
	game.on_net_failed(why)

func _on_peer_disconnected(pid: int) -> void:
	if not players.has(pid):
		return
	if game.match_instance != null: game.match_instance.left(pid)
	var n: String = players[pid]["name"]
	if server and game.bg != null and is_instance_valid(players[pid]["hero"]):
		game.bg.player_left(pid, players[pid]["hero"].global_position)
	_remove_player(pid)
	if server:
		print("[BG] %s left (%d playing)" % [n, players.size()])
	# a trip waiting on them: theirs is called off, otherwise it goes on without their answer
	if is_host and not vote.is_empty():
		if int(vote["from"]) == pid:
			_end_vote()
		else:
			(vote["yes"] as Dictionary).erase(pid)
			_vote_check()
	game.ui.message(n + " left the game", Color(1.0, 0.8, 0.4))
	_update_status()

# ---------------------------------------------------------------- players
func _add_player(pid: int, nm: String, gear: Dictionary) -> void:
	if players.has(pid) or pid == multiplayer.get_unique_id():
		return
	var h := Hero.new()
	h.puppet = true
	h.peer_id = pid
	h.name = "Ally%d" % pid
	game.add_child(h)
	h.setup(game)
	h.light.light_energy = 0.5
	h.visible = false
	var tag := Label3D.new()
	tag.text = nm
	tag.font_size = 40
	tag.outline_size = 10
	tag.pixel_size = 0.006
	tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	tag.no_depth_test = true
	tag.modulate = ALLY_COLORS[players.size() % ALLY_COLORS.size()]
	tag.position = Vector3(0, 2.55, 0)
	h.add_child(tag)
	h.ally_color = tag.modulate
	players[pid] = {"name": nm, "hero": h}
	h.apply_net_gear(gear)
	_rebuild_party_ui()

func _remove_player(pid: int) -> void:
	if not players.has(pid):
		return
	var h = players[pid]["hero"]
	if is_instance_valid(h):
		h.queue_free()
	players.erase(pid)
	_rebuild_party_ui()

func puppets() -> Array:
	var out := []
	for pid in players:
		var h = players[pid]["hero"]
		if is_instance_valid(h):
			out.append(h)
	return out

func alive_ally() -> Node3D:
	for h in puppets():
		if not h.dead and h.visible:
			return h
	return null

# ---------------------------------------------------------------- per-frame
func _process(delta: float) -> void:
	_clock += delta
	travel_cool = maxf(0.0, travel_cool - delta)
	_trip_cool = maxf(0.0, _trip_cool - delta)
	if listening and disco:
		while disco.get_available_packet_count() > 0:
			var txt := disco.get_packet().get_string_from_utf8()
			var ip := disco.get_packet_ip()
			var parts := txt.split("|")
			if parts.size() >= 3 and parts[0] == "ASHENCROWN":
				found[ip] = {"name": parts[1], "zone": parts[2], "t": _clock}
		for ip in found.keys():
			if _clock - found[ip]["t"] > 4.0:
				found.erase(ip)
	if not active:
		return
	if (game.match_instance != null and game.match_instance.ending) or (game.lobby_client != null and game.lobby_client._returning):
		return # Results are final; stop snapshots while the match closes its transport.
	if is_host and disco:
		_disco_t -= delta
		if _disco_t <= 0.0:
			_disco_t = 1.0
			disco.put_packet(("ASHENCROWN|%s|%s" % [my_name, game.zone_title(game.cur_act, game.cur_zone)]).to_utf8_buffer())
	_send_t -= delta
	if _send_t > 0.0:
		_update_party_ui()
		return
	_send_t = SEND_RATE
	# (a client of a dedicated server has no partners listed yet, but the server still needs its position)
	if (players.is_empty() and not (is_client() and (game.bg_mode or (game.lobby_client != null and game.lobby_client.match_id != "")))) or game.world == null or game._busy or loading:
		_update_party_ui()
		return
	if not server:
		rpc("pl_state", _hero_packet(game.hero))
	if is_host:
		var arr := PackedFloat32Array()
		for id in enemies.keys():
			var e = enemies[id]
			if not is_instance_valid(e) or e.dead:
				if not is_instance_valid(e):
					enemies.erase(id)
				continue
			arr.append_array([float(id), e.global_position.x, e.global_position.z, e.rig.rotation.y, e.move_amt, e.phase,
				(e.atk_t / e.atk_dur) if e.atk_t >= 0.0 else -1.0, float(maxi(0, STYLES.find(e.atk_style))), e.hit_t, e.life])
		# Keep unreliable snapshots below ENet's MTU; each enemy is ten floats.
		for offset in range(0, arr.size(), 240):
			rpc("cl_enemy_states", arr.slice(offset, mini(offset + 240, arr.size())))
	_update_party_ui()

func _hero_packet(h: Hero) -> PackedFloat32Array:
	var st: Dictionary = h.last_pose
	return PackedFloat32Array([h.global_position.x, h.global_position.y, h.global_position.z, h.rig.rotation.y,
		h.phase, st.get("move", 0.0), st.get("atk", -1.0), float(maxi(0, STYLES.find(st.get("style", "over")))),
		st.get("block", 0.0), st.get("hit", 0.0), 1.0 if h.dead else 0.0, h.dead_t, h.life, h.max_life,
		_flags(h)])

## p[14] of the state: bit 1 his battle buff, 2 unseen (Hero.invis_t), then the PvP statuses on him (PvpStatusFx bits
## << 2: rooted, harried, slowed, revealed) and his Blight stacks (<< 6), so his puppet shows them on every screen
## (Hero.apply_net_state). A float holds these small integers exactly.
func _flags(h: Hero) -> float:
	return float((1 if h.buff_t > 0.0 else 0) | (2 if h.invis_t > 0.0 else 0) | (PvpStatusFx.bits_of(h) << 2) | (PvpStatusFx.blight_of(h) << 6))     # (bit 10: the antechamber stash's slow)

@rpc("any_peer", "call_remote", "unreliable_ordered")
func pl_state(p: PackedFloat32Array) -> void:
	var pid := multiplayer.get_remote_sender_id()
	if not players.has(pid) or loading:
		return
	var h = players[pid]["hero"]
	if is_instance_valid(h):
		h.apply_net_state(p)

func send_gear() -> void:
	if active:
		rpc("pl_gear", game.hero.net_gear())

@rpc("any_peer", "call_remote", "reliable")
func pl_gear(gear: Dictionary) -> void:
	var pid := multiplayer.get_remote_sender_id()
	if players.has(pid) and is_instance_valid(players[pid]["hero"]):
		players[pid]["hero"].apply_net_gear(gear)

# ---------------------------------------------------------------- skill effects (SkillFx)
## Every skill effect the local hero shows (Hero.fx) goes out as one small event; each partner plays it on
## this player's puppet, visuals only. Enemies in it travel as net ids (SkillFx.encode/decode).
var fx_tap: Callable      # tests: handed every event as it would go on the wire
var pd_tap: Callable      # tools: handed every Plague Doctor event (Plague._send) as it would go on the wire
var fx_sent := 0          # events sent to partners and played from them (mp_test counts both)
var fx_got := 0

func skill_fx(ev: Dictionary) -> void:
	var w := SkillFx.encode(self, ev)
	if fx_tap.is_valid():
		fx_tap.call(w)
	if active and not players.is_empty() and not loading:
		fx_sent += 1
		rpc("pl_fx", w)

@rpc("any_peer", "call_remote", "reliable")
func pl_fx(w: Dictionary) -> void:
	var pid := multiplayer.get_remote_sender_id()
	if not players.has(pid) or loading or game.world == null:
		return
	var h = players[pid]["hero"]
	if is_instance_valid(h) and h.net_has:
		fx_got += 1
		SkillFx.play(h, SkillFx.decode(self, w))

# ---------------------------------------------------------------- handshake
@rpc("any_peer", "call_remote", "reliable")
func sv_hello(nm: String, gear: Dictionary, _lvl: int, queue_ticket := "", character := "") -> void:
	if not is_host:
		return
	var pid := multiplayer.get_remote_sender_id()
	if players.has(pid): return
	if game.match_instance != null:
		if not await game.match_instance.admit(pid, queue_ticket):
			rpc_id(pid, "cl_party_refused")
			return
		if not active or not multiplayer.get_peers().has(pid): return
		var want := str(game.match_instance.members[pid].character)
		# (a run's hero has no saved character: builds before 2026-11-06 sent "" for it; the ticket already proved who it is)
		if want != character and not (want.begins_with("run_") and character == ""):
			rpc_id(pid, "cl_party_refused")
			return
	var roster := [] if server else [[1, my_name, game.hero.net_gear()]]
	for op in players:
		roster.append([op, players[op]["name"], players[op]["hero"].net_gear()])
		rpc_id(op, "cl_player_join", pid, nm, gear)
	_add_player(pid, nm, gear)
	if players.has(pid) and is_instance_valid(players[pid]["hero"]):
		players[pid]["hero"].level = clampi(_lvl, 1, 99)      # (the raid's PvP class balance is by level, Data.pvp_scale)
	var at: Vector3 = game.hero.global_position
	if game.match_instance != null:
		at = game.match_instance.spawn(pid)
	elif server:
		at = game.bg.spawn_point(pid) if game.bg != null else at
	rpc_id(pid, "cl_welcome", game.cur_act, game.cur_zone, at, game.tp_link, game.boss_killed, roster)
	if server:
		print("[BG] %s joined (%d playing)" % [nm, players.size()])
	game.ui.message(nm + " joined the game", Color(0.5, 1.0, 0.5))
	Sfx.play("portal")
	_update_status()

@rpc("authority", "call_remote", "reliable")
func cl_party_refused() -> void:
	shutdown()
	game.on_net_failed("The party is full or your reservation expired. Please queue again.")

@rpc("authority", "call_remote", "reliable")
func cl_welcome(act: int, zone: String, pos: Vector3, tp: Dictionary, bk: bool, roster: Array) -> void:
	welcomed = true
	if game.lobby_client != null and game.lobby_client.match_id != "":
		game.lobby_client.admitted = true
		if game.bg_mode: game.save_game()
	game.party_join_pending = false
	game.net_joining = false
	for r in roster:
		_add_player(int(r[0]), str(r[1]), r[2])
	game.tp_link = tp
	game.boss_killed = bk
	if game.bg_mode:
		game.ui.message("Joined the Battlegrounds", Color(0.5, 1.0, 0.5))
		game.give_raid_phials()
	elif game.arena_mode:
		game.ui.message("Joined Sandbox" if game.sandbox != null else "Joined the arena", Color(1.0, 0.85, 0.5))
	elif not players.has(1):
		game.ui.message("Joined the online co-op server", Color(0.5, 1.0, 0.5))
	else:
		game.ui.message("Joined %s's game" % players.get(1, {"name": "the host"})["name"], Color(0.5, 1.0, 0.5))
	_update_status()
	_client_goto(act, zone, "start", pos)

@rpc("authority", "call_remote", "reliable")
func cl_player_join(pid: int, nm: String, gear: Dictionary) -> void:
	_add_player(pid, nm, gear)
	game.ui.message(nm + " joined the game", Color(0.5, 1.0, 0.5))

# ---------------------------------------------------------------- party travel
## Host: called at the start of every zone load so the whole party follows.
func broadcast_goto(act: int, zone: String, spawn: String, at) -> void:
	if not is_host or players.is_empty():
		return
	enemies.clear()
	items.clear()
	for h in puppets():
		h.net_zone_reset()
	rpc("cl_goto", act, zone, spawn, at if at != null else Vector3.INF, game.tp_link, game.boss_killed)

@rpc("authority", "call_remote", "reliable")
func cl_goto(act: int, zone: String, spawn: String, at: Vector3, tp: Dictionary, bk: bool) -> void:
	game.tp_link = tp
	game.boss_killed = bk
	_client_goto(act, zone, spawn, null if at == Vector3.INF else at)

func _client_goto(act: int, zone: String, spawn: String, at) -> void:
	var link := peer   # (the connection this trip belongs to: it can close while the zone loads)
	loading = true
	enemies.clear()
	items.clear()
	for h in puppets():
		h.net_zone_reset()
	while game._busy:
		await get_tree().process_frame
	await game.load_zone(act, zone, spawn, at)
	var p: Vector3 = game.hero.global_position + Vector3(1.4, 0, 1.0)
	game.hero.global_position = game.world.free_spot_near(p, 1.5)
	game.hero.global_position.y = game.world.height_at(game.hero.global_position.x, game.hero.global_position.z)
	# turned away or cut off while the zone loaded (a raid join refused): nobody is left to tell, and the game is
	# already taking the hero home (`Game.on_net_failed`)
	if not still_joined(link):
		return
	loading = false
	rpc_id(1, "sv_zone_ready")

## Client: still connected through the same link as before an await (not shut down, nor joined elsewhere since).
func still_joined(link: MultiplayerPeer) -> bool:
	return active and not is_host and link != null and peer == link \
		and link.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED

func request_travel(act: int, zone: String, spawn: String, at, clear_tp := false) -> void:
	if travel_cool > 0.0:
		return
	travel_cool = 2.0
	rpc_id(1, "sv_travel", act, zone, spawn, at if at != null else Vector3.INF, clear_tp)
	game.ui.message("Travelling...", Color(0.6, 0.75, 1.0))

@rpc("any_peer", "call_remote", "reliable")
func sv_travel(act: int, zone: String, spawn: String, at: Vector3, clear_tp: bool) -> void:
	if not is_host or refuses_travel() or game._busy:
		return
	var pid := multiplayer.get_remote_sender_id()
	if players.has(pid):
		game.ui.message("%s leads the party onward" % players[pid]["name"], Color(0.6, 0.75, 1.0))
	if clear_tp:
		game.tp_link = {}
	game.load_zone(act, zone, spawn, null if at == Vector3.INF else at)

@rpc("any_peer", "call_remote", "reliable")
func sv_zone_ready() -> void:
	if not is_host:
		return
	var pid := multiplayer.get_remote_sender_id()
	if game._busy:
		if not pending_ready.has(pid):
			pending_ready.append(pid)
		return
	_send_snapshot(pid)

## Host: called when its own zone load finishes.
func host_zone_loaded() -> void:
	if not is_host:
		return
	for pid in pending_ready:
		_send_snapshot(pid)
	pending_ready.clear()

func _send_snapshot(pid: int) -> void:
	for id in enemies.keys():
		var e = enemies[id]
		if is_instance_valid(e) and not e.dead:
			rpc_id(pid, "cl_spawn", id, e.kind, e.global_position, e.level, e.champion, e.display_name, e.pack_id, e.rig.rotation.y, e.life)
	for id in items.keys():
		var g = items[id]
		if is_instance_valid(g) and not g.is_queued_for_deletion():
			rpc_id(pid, "cl_drop", id, g.item, g._to, g._to, true)
	for i in game.world.interactables.size():
		var t = game.world.interactables[i]
		if not is_instance_valid(t):
			continue
		if t.kind in ["chest", "shrine", "flower"] and t.used:
			rpc_id(pid, "cl_inter", i)
		elif t.kind == "portal" and t.has_meta("dyn"):
			rpc_id(pid, "cl_portal", t.global_position, t.data.get("dir", "town"), t.label, game.tp_link)
	for id in enemies.keys():
		var e = enemies[id]
		if is_instance_valid(e) and e.boss and e.aggro and not e.dead:
			rpc_id(pid, "cl_boss_aggro", id)
	# the felled and the wounded trees (Harvest)
	var hv := Harvest.of(game.world)
	if hv != null:
		var snap := hv.snapshot()
		if not snap.is_empty():
			rpc_id(pid, "cl_trees", snap)

# ---------------------------------------------------------------- enemies
func on_spawn(e: Enemy) -> void:
	e.net_id = next_id
	next_id += 1
	enemies[e.net_id] = e
	if not players.is_empty():
		rpc("cl_spawn", e.net_id, e.kind, e.global_position, e.level, e.champion, e.display_name, e.pack_id, e.rig.rotation.y, e.life)

@rpc("authority", "call_remote", "reliable")
func cl_spawn(id: int, kind: String, pos: Vector3, lvl: int, champ: bool, dname: String, pack: int, yaw: float, life: float) -> void:
	if loading or game.world == null or enemies.has(id):
		return
	var e: Enemy = game.spawn_enemy(kind, pos, lvl, champ, dname if champ else "", pack, true)
	e.remote = true
	e.net_id = id
	e.rig.rotation.y = yaw
	e.net_yaw = yaw
	e.net_pos = e.global_position
	e.life = life
	enemies[id] = e

@rpc("authority", "call_remote", "unreliable_ordered")
func cl_enemy_states(arr: PackedFloat32Array) -> void:
	if loading:
		return
	var n := arr.size() / 10
	for i in n:
		var o := i * 10
		var id := int(arr[o])
		if not enemies.has(id):
			continue
		var e = enemies[id]
		if not is_instance_valid(e) or e.dead:
			continue
		e.apply_net_state(arr[o + 1], arr[o + 2], arr[o + 3], arr[o + 4], arr[o + 5], arr[o + 6], STYLES[clampi(int(arr[o + 7]), 0, STYLES.size() - 1)], arr[o + 8], arr[o + 9])

## A partner's hit on a monster, for the host to apply. A quiet damage tick (Enemy.soft_hit: the plague doctor's
## poison) travels as knock -1: no flash, no flinch, a green number.
func send_enemy_hit(e: Enemy, phys: float, fire: float, from: Vector3, knock: float, crit: bool) -> void:
	# Remote effects can outlive their transport while the world retires.
	if not still_joined(peer):
		return
	rpc_id(1, "sv_enemy_hit", e.net_id, phys, fire, from, -1.0 if e.soft_hit else knock, crit)

@rpc("any_peer", "call_remote", "reliable")
func sv_enemy_hit(id: int, phys: float, fire: float, from: Vector3, knock: float, crit: bool) -> void:
	if not is_host or not enemies.has(id):
		return
	var e = enemies[id]
	if is_instance_valid(e) and not e.dead:
		if knock < 0.0:
			e.soft_hit = true
			e.dmg_tint = Plague.POISON_TINT
			e.take_damage(phys, fire, from, 0.0, crit)
			e.soft_hit = false
			e.dmg_tint = Color(0, 0, 0, 0)
		else:
			e.take_damage(phys, fire, from, knock, crit)

func send_enemy_chill(e: Enemy, k: float, t: float) -> void:
	# Remote effects can outlive their transport while the world retires.
	if not still_joined(peer):
		return
	rpc_id(1, "sv_enemy_chill", e.net_id, k, t)

@rpc("any_peer", "call_remote", "reliable")
func sv_enemy_chill(id: int, k: float, t: float) -> void:
	if is_host and enemies.has(id) and is_instance_valid(enemies[id]):
		(enemies[id] as Enemy).chill(clampf(k, 0.0, 0.8), clampf(t, 0.0, 6.0))

func send_enemy_stun(e: Enemy, t: float) -> void:
	# Remote effects can outlive their transport while the world retires.
	if not still_joined(peer):
		return
	rpc_id(1, "sv_enemy_stun", e.net_id, t)

@rpc("any_peer", "call_remote", "reliable")
func sv_enemy_stun(id: int, t: float) -> void:
	if is_host and enemies.has(id) and is_instance_valid(enemies[id]):
		enemies[id].stun(t)

func enemy_died(e: Enemy) -> void:
	if is_host and not players.is_empty():
		rpc("cl_enemy_die", e.net_id)

@rpc("authority", "call_remote", "reliable")
func cl_enemy_die(id: int) -> void:
	if not enemies.has(id):
		return
	var e = enemies[id]
	enemies.erase(id)
	if is_instance_valid(e) and not e.dead:
		e.die_visual()
		if not game.bg_mode:
			game.quests.on_kill(e)       # a partner's quests count the party's kills (a raid's don't: no story there)
		if e.boss:
			game.boss_down_remote(e)

## A hero's visible moment (the plague doctor's flasks, traps and dome: Plague._send), for every other player to
## replay on their puppet of him (Plague.remote: visuals only). A partner sends it to the host, who replays it and
## passes it on.
func hero_fx(ev: String) -> void:
	if not active:
		return
	if is_host:
		if not players.is_empty():
			rpc("cl_hero_fx", multiplayer.get_unique_id(), ev)
	else:
		rpc_id(1, "sv_hero_fx", ev)

@rpc("any_peer", "call_remote", "reliable")
func sv_hero_fx(ev: String) -> void:
	if not is_host or ev.length() > 200:
		return
	var pid := multiplayer.get_remote_sender_id()
	_play_hero_fx(pid, ev)
	rpc("cl_hero_fx", pid, ev)

@rpc("authority", "call_remote", "reliable")
func cl_hero_fx(pid: int, ev: String) -> void:
	if pid != multiplayer.get_unique_id():
		_play_hero_fx(pid, ev)

func _play_hero_fx(pid: int, ev: String) -> void:
	if not players.has(pid) or not is_instance_valid(players[pid]["hero"]):
		return
	var h: Hero = players[pid]["hero"]
	if h.is_plague():
		if h.pd == null:
			h.pd = Plague.new(h)
		h.pd.remote(ev)

func enemy_fx(e: Enemy, ev: String) -> void:
	if is_host and not players.is_empty():
		rpc("cl_enemy_fx", e.net_id, ev)

@rpc("authority", "call_remote", "reliable")
func cl_enemy_fx(id: int, ev: String) -> void:
	if enemies.has(id) and is_instance_valid(enemies[id]):
		enemies[id].special_fx(ev)

@rpc("authority", "call_remote", "reliable")
func cl_boss_aggro(id: int) -> void:
	if enemies.has(id) and is_instance_valid(enemies[id]):
		enemies[id].aggro = true
		game.on_boss_aggro(enemies[id])

func boss_aggro(e: Enemy) -> void:
	if is_host and not players.is_empty():
		rpc("cl_boss_aggro", e.net_id)

func share_xp(xp: int, lvl: int) -> void:
	if is_host and not players.is_empty():
		rpc("cl_xp", xp, lvl)

@rpc("authority", "call_remote", "reliable")
func cl_xp(xp: int, lvl: int) -> void:
	game.gain_kill_xp(xp, lvl)

## Host: gold straight into a partner's purse (a pile of King Grubb's gold they stepped on).
func give_gold(pid: int, amount: int) -> void:
	rpc_id(pid, "cl_gold", amount)

@rpc("authority", "call_remote", "reliable")
func cl_gold(amount: int) -> void:
	game.hero.add_to_inventory(Items.gold(amount))
	Sfx.play("gold", 0.0, 0.9)

## Host: a monster struck a partner's knight; that player's game works out blocking.
func hit_player(pid: int, dmg: float, from: Vector3, kind: String, element: String) -> void:
	rpc_id(pid, "cl_take_hit", dmg, from, kind, element)

@rpc("authority", "call_remote", "reliable")
func cl_take_hit(dmg: float, from: Vector3, kind: String, element: String) -> void:
	if not loading:
		game.hero.take_hit(dmg, from, kind, element)

func projectile(kind: String, from: Vector3, to: Vector3) -> void:
	if is_host and not players.is_empty():
		rpc("cl_proj", kind, from, to)

@rpc("authority", "call_remote", "reliable")
func cl_proj(kind: String, from: Vector3, to: Vector3) -> void:
	if loading or game.world == null:
		return
	var pr := Projectile.new()
	pr.visual_only = true
	game.world.fx_root.add_child(pr)
	pr.launch(game, kind, from, to, 0.0)
	Sfx.play("bow" if kind in ["arrow", "dart"] else "fireball", -6.0, randf_range(0.9, 1.1))

# ---------------------------------------------------------------- loot
func on_item_dropped(g: GroundItem, it: Dictionary, at: Vector3, to: Vector3) -> void:
	var id := next_id
	next_id += 1
	g.set_meta("net_id", id)
	items[id] = g
	if not players.is_empty():
		rpc("cl_drop", id, it, at, to, false)

@rpc("authority", "call_remote", "reliable")
func cl_drop(id: int, it: Dictionary, at: Vector3, to: Vector3, landed: bool) -> void:
	if loading or game.world == null or items.has(id):
		return
	var g := GroundItem.new()
	game.world.items_root.add_child(g)
	g.setup(it, at + Vector3(0, 1.0, 0), to)
	if landed:
		g._toss = 1.0
		g.global_position = to
	g.set_meta("net_id", id)
	items[id] = g

func request_drop(it: Dictionary, at: Vector3) -> void:
	rpc_id(1, "sv_drop", it, at)

@rpc("any_peer", "call_remote", "reliable")
func sv_drop(it: Dictionary, at: Vector3) -> void:
	if is_host and game.world:
		game.drop_item(it, at)

func request_pickup(g: GroundItem) -> void:
	rpc_id(1, "sv_pickup", int(g.get_meta("net_id", -1)))

@rpc("any_peer", "call_remote", "reliable")
func sv_pickup(id: int) -> void:
	if not is_host or not items.has(id):
		return
	var g = items[id]
	if not is_instance_valid(g) or g.is_queued_for_deletion():
		items.erase(id)
		return
	var pid := multiplayer.get_remote_sender_id()
	var it: Dictionary = g.item
	var pos: Vector3 = g.global_position
	if server and game.bg != null:
		game.bg.picked(pid, it)
	item_gone(g)
	if game.hovered == g:
		game.hovered = null
	g.queue_free()
	rpc_id(pid, "cl_grant", it, pos)

## Host: an item left the ground (picked up by anyone).
func item_gone(g: GroundItem) -> void:
	var id := int(g.get_meta("net_id", -1))
	items.erase(id)
	if is_host and not players.is_empty() and id >= 0:
		rpc("cl_remove_item", id)

@rpc("authority", "call_remote", "reliable")
func cl_remove_item(id: int) -> void:
	if not items.has(id):
		return
	var g = items[id]
	items.erase(id)
	if is_instance_valid(g):
		if game.hovered == g:
			game.hovered = null
		g.queue_free()

@rpc("authority", "call_remote", "reliable")
func cl_grant(it: Dictionary, pos: Vector3) -> void:
	game.receive_item(it, pos)

# ---------------------------------------------------------------- Battlegrounds (battlegrounds.gd)
## Client -> server: who this player is (a one-time Nakama join ticket, else the per-PC id). The server answers with
## the round's state, or turns them away (the round is closing, the ticket was refused).
@rpc("any_peer", "call_remote", "reliable")
func sv_bg_hello(uid: String, ticket: String) -> void:
	if game.match_instance != null: return # Identity already came from the lobby admission ticket.
	if not server or game.bg == null:
		return
	var pid := multiplayer.get_remote_sender_id()
	var r = await game.bg.player_hello(pid, uid.substr(0, 64), ticket)
	if r != "ok":
		# turned away: say why, and when the next raid lets players in (the client counts down and rejoins)
		rpc_id(pid, "cl_bg_refused", r, game.bg.secs_to_next() if r == "closed" else 0.0)
		await get_tree().create_timer(0.5).timeout
		drop_peer(pid)
		return
	game.bg.broadcast(pid)

## Host or server: cut one peer off now. A graceful `disconnect_peer` empties the ENet peer's channels at once
## but leaves it listed until the other end answers, which a client busy building a zone can't do for seconds:
## every broadcast meanwhile logged "Unable to send packet on channel 1, max channels: 0" (triage 2026-11-04,
## fd6796612eee4c16). Disconnecting now makes it inactive; the next poll drops it and still emits
## peer_disconnected, so the usual leaving (`_on_peer_disconnected`) runs as before.
func drop_peer(pid: int) -> void:
	if peer == null or peer.get_connection_status() != MultiplayerPeer.CONNECTION_CONNECTED:
		return
	var pp: ENetPacketPeer = peer.get_peer(pid)
	if pp != null and pp.is_active():
		pp.peer_disconnect_now(0)

## Server: turn a player away now (why: "boosted" = admin gear without the admin role).
func bg_refuse(pid: int, why: String) -> void:
	if not server:
		return
	rpc_id(pid, "cl_bg_refused", why, 0.0)
	# (time for it to land: a client still building the crypt can be busy for a second or more)
	await get_tree().create_timer(2.0).timeout
	if players.has(pid):
		drop_peer(pid)

## The matchup: every raider's class and level (Battlegrounds.roster), shown by BgMatchup.
@rpc("authority", "call_remote", "reliable")
func cl_bg_roster(r: Array) -> void:
	game.bg_roster = r

## Every raider's team (Battlegrounds.teams): a duo's pair is no target and shows on its teammate's map.
@rpc("authority", "call_remote", "reliable")
func cl_bg_teams(t: Dictionary) -> void:
	game.set_meta("bg_teams", t)

## The round: "raid" or "reset", seconds into it, the open portals, its length, when the portals open.
@rpc("authority", "call_remote", "reliable")
func cl_bg_raid(state: String, t: float, open: Array, length: float, portals_at: float) -> void:
	var was := str(game.bg_raid.get("state", ""))
	var wait := float(state.get_slice(":", 1)) if state.contains(":") else 0.0
	game.bg_raid = {"state": state, "t": t, "open": open, "len": length, "portals_at": portals_at, "wait": wait}
	if state.begins_with("prep") and not was.begins_with("prep"):
		game.ui.big_message("The raid starts in %d" % int(ceilf(wait)))
		Sfx.play("arena_horn", -4.0)
	if game.world != null:
		var ps := Battlegrounds.portal_list(game.world)
		for i in ps.size():
			var on := open.has(i)
			ps[i].data["open"] = on
			var m = ps[i].get_node_or_null("Model")
			if m:
				m.visible = on

## PvP: the local hero struck another player's stand-in (Battlegrounds.sync_proxies); the server deals it. On the
## server itself (a player's skills running there, ServerRules) it's dealt at once, from the player who struck.
func send_pvp_hit(target_pid: int, amount: float, from: Vector3) -> void:
	if server:
		if game.bg != null:
			game.bg.pvp_hit(_striker_pid(), target_pid, amount, from)
		return
	rpc_id(1, "sv_pvp_hit", target_pid, amount, from)

## Server: the player whose skill is acting now (Hero.striker is the server's copy of them).
func _striker_pid() -> int:
	var s = Hero.striker
	return int(s.peer_id) if s != null and is_instance_valid(s) else 0

# ---------------------------------------------------------------- skills that run on the server (ServerRules)
## A player's game: one of its skills made something its rules act on; the server's copy of the player makes it.
func send_skill_make(id: String, kind: String, data: Dictionary) -> void:
	if active and not server:
		rpc_id(1, "sv_skill_make", id, kind, data)

@rpc("any_peer", "call_remote", "reliable")
func sv_skill_make(id: String, kind: String, data: Dictionary) -> void:
	if server:
		ServerRules.received(game, multiplayer.get_remote_sender_id(), id, kind, data)

## A player's game: its build (level, attributes, the run's skills, rites and gems) for the server's copy of it.
func send_build(d: Dictionary) -> void:
	if active and not server:
		rpc_id(1, "sv_build", d)

@rpc("any_peer", "call_remote", "reliable")
func sv_build(d: Dictionary) -> void:
	var pid := multiplayer.get_remote_sender_id()
	if server and players.has(pid):
		ServerRules.apply_build(players[pid]["hero"], d)

## Server: what a player's skills did here (a sigil blowing, a mark landing) is shown on every game, the player's
## own included: on their own hero there, on their puppet everywhere else.
func server_fx(h: Hero, ev: Dictionary) -> void:
	if server and active and not players.is_empty():
		rpc("cl_server_fx", int(h.peer_id), SkillFx.encode(self, ev))

@rpc("authority", "call_remote", "reliable")
func cl_server_fx(pid: int, w: Dictionary) -> void:
	if loading or game.world == null:
		return
	var h = game.hero if pid == multiplayer.get_unique_id() else players.get(pid, {}).get("hero")
	if h != null and is_instance_valid(h):
		SkillFx.play(h, SkillFx.decode(self, w))

## Server: the blow a player's skill landed here, for the number over the foe on their screen.
func tell_dealt(h: Hero, at: Vector3, amount: float, crit: bool) -> void:
	if server and active and int(h.peer_id) > 0 and multiplayer.get_peers().has(int(h.peer_id)):
		rpc_id(int(h.peer_id), "cl_dealt", at, amount, crit)

@rpc("authority", "call_remote", "unreliable")
func cl_dealt(at: Vector3, amount: float, crit: bool) -> void:
	if not loading and game.world != null and amount > 0.0:
		Fx.number(game.world.fx_root, at + Vector3(0, 2.2, 0), str(int(amount)) + ("!" if crit else ""), Color(1.0, 0.85, 0.4), crit)

## Server: what a player's own blows did to them here (life leeched, a rite's buff, a cooldown back, Hunger, what a
## skill's rules gave them: "give", Skill.give), for their game, which keeps their life, cooldowns and run
## (Hero.gain_life, RunTalents._tell_owner, ServerRules.got).
func tell_self(h: Hero, d: Dictionary) -> void:
	if server and active and int(h.peer_id) > 0 and multiplayer.get_peers().has(int(h.peer_id)):
		rpc_id(int(h.peer_id), "cl_self", d)

@rpc("authority", "call_remote", "reliable")
func cl_self(d: Dictionary) -> void:
	var h = game.hero
	if loading or h == null or h.dead:
		return
	h.gain_life(float(d.get("life", 0.0)))
	if d.get("give") is Array and (d["give"] as Array).size() == 3 and d["give"][2] is Dictionary:
		ServerRules.got(game, str(d["give"][0]), str(d["give"][1]), d["give"][2])
	if d.has("cd"):
		h.cds[str(d["cd"])] = 0.0
	if h.run != null:
		if d.get("buff") is Array and (d["buff"] as Array).size() == 3:
			RunTalents.buff(h, str(d["buff"][0]), d["buff"][1] if d["buff"][1] is Dictionary else {}, float(d["buff"][2]))
		if d.get("hunger") is Array and (d["hunger"] as Array).size() == 2:
			h.run.hunger = minf(float(d["hunger"][1]), h.run.hunger + float(d["hunger"][0]))

@rpc("any_peer", "call_remote", "unreliable_ordered")
func sv_pvp_hit(target_pid: int, amount: float, from: Vector3) -> void:
	if server and game.bg != null:
		game.bg.pvp_hit(multiplayer.get_remote_sender_id(), target_pid, amount, from)

## PvP: the local hero struck another player's thing (PvpObjects: a stand-in with `pvp_obj`); the server checks it
## and its owner's game counts the blow.
func send_pvp_obj_hit(owner_pid: int, oid: int, from: Vector3) -> void:
	if active:
		rpc_id(1, "sv_pvp_obj_hit", owner_pid, oid, from)

@rpc("any_peer", "call_remote", "reliable")
func sv_pvp_obj_hit(owner_pid: int, oid: int, from: Vector3) -> void:
	if server and game.bg != null:
		game.bg.pvp_obj_hit(multiplayer.get_remote_sender_id(), owner_pid, oid, from)

func obj_hit_player(owner_pid: int, oid: int, attacker: int) -> void:
	rpc_id(owner_pid, "cl_pvp_obj_hit", oid, attacker)

@rpc("authority", "call_remote", "reliable")
func cl_pvp_obj_hit(oid: int, attacker: int) -> void:
	if not loading and game.hero != null and game.hero.pd != null:
		game.hero.pd.obj_hit(oid, attacker)

## PvP crowd control (PvpStatus): the local hero's skill did more than hurt another player's stand-in.
func send_pvp_status(target_pid: int, kind: String, secs: float, data: Dictionary) -> void:
	if server:
		if game.bg != null:
			game.bg.pvp_status(_striker_pid(), target_pid, kind, secs, data)
		return
	if active:
		rpc_id(1, "sv_pvp_status", target_pid, kind, secs, data)

@rpc("any_peer", "call_remote", "reliable")
func sv_pvp_status(target_pid: int, kind: String, secs: float, data: Dictionary) -> void:
	if server and game.bg != null:
		game.bg.pvp_status(multiplayer.get_remote_sender_id(), target_pid, kind, secs, data)

@rpc("authority", "call_remote", "reliable")
func cl_pvp_status(kind: String, secs: float, data: Dictionary) -> void:
	if not loading:
		PvpStatus.apply(game.hero, kind, secs, data)

## PvP crowd control (Doug's slips, pies and launches): the local hero's skill caught another player's stand-in;
## the server checks the raid is on and both are playing, then hands it to that player as a zero-damage hit of
## that kind (Hero.take_hit "slip", "pied", "quake", "sweep").
const PVP_EFFECTS := ["slip", "pied", "quake", "sweep", "chill"]

func send_pvp_effect(target_pid: int, kind: String, from: Vector3) -> void:
	if server:
		if game.bg != null and game.bg.state == "raid" and PVP_EFFECTS.has(kind):
			game.bg.pvp_effect(_striker_pid(), target_pid, kind, from)
		return
	if active and not is_host and PVP_EFFECTS.has(kind):
		rpc_id(1, "sv_pvp_effect", target_pid, kind, from)

@rpc("any_peer", "call_remote", "reliable")
func sv_pvp_effect(target_pid: int, kind: String, from: Vector3) -> void:
	var by := multiplayer.get_remote_sender_id()
	if not server or game.bg == null or game.bg.state != "raid" or not PVP_EFFECTS.has(kind):
		return
	game.bg.pvp_effect(by, target_pid, kind, from)

## PvP burning (a Fire Arrow, magma, a unique's burn on another player's stand-in, Enemy.ignite): the attacker's own
## `dps`; the server checks it like a blow and scales it (Battlegrounds.pvp_burn), a "burn" hit for Hero.BURN_SECS.
func send_pvp_dot(target_pid: int, dps: float, from: Vector3) -> void:
	if server:
		if game.bg != null:
			game.bg.pvp_burn(_striker_pid(), target_pid, dps, from)
		return
	if active and not is_host:
		rpc_id(1, "sv_pvp_dot", target_pid, dps, from)

@rpc("any_peer", "call_remote", "reliable")
func sv_pvp_dot(target_pid: int, dps: float, from: Vector3) -> void:
	var by := multiplayer.get_remote_sender_id()
	if not server or game.bg == null:
		return
	game.bg.pvp_burn(by, target_pid, dps, from)

## War Cry (SharedSkills): the battle buff for the teammates near the one who roared: co-op partners, the Arena's
## team, a Battlegrounds duo's pair (never another raider).
func send_team_buff(secs: float, at: Vector3) -> void:
	if active and not players.is_empty():
		rpc("cl_team_buff", secs, at)

@rpc("any_peer", "call_remote", "reliable")
func cl_team_buff(secs: float, at: Vector3) -> void:
	if server or game.world == null or game.hero == null or game.hero.dead or loading:
		return
	if game.bg_mode and not Battlegrounds.is_teammate(game, multiplayer.get_remote_sender_id()):
		return
	if game.arena_mode:
		var teams: Dictionary = game.arena_state.get("teams", {})
		if teams.get(str(multiplayer.get_remote_sender_id()), -1) != teams.get(str(multiplayer.get_unique_id()), -2): return
	if game.hero.global_position.distance_to(at) <= SharedSkills.CRY_R:
		game.hero.buff_t = maxf(game.hero.buff_t, secs)
		game.ui.message("%s's War Cry: +40%% damage" % _name_of(multiplayer.get_remote_sender_id()), Color(1.0, 0.5, 0.35))

## The local hero fell in a raid: everything they had, for the server to drop where they fell.
func send_bg_died(items: Array) -> void:
	rpc_id(1, "sv_bg_died", items)

@rpc("any_peer", "call_remote", "reliable")
func sv_bg_died(items: Array) -> void:
	if not server or game.bg == null:
		return
	var pid := multiplayer.get_remote_sender_id()
	if players.has(pid) and is_instance_valid(players[pid]["hero"]):
		game.bg.died(pid, items.slice(0, 80), players[pid]["hero"].global_position)

## An admin's raid control ("restart", "gates", "portals"; Battlegrounds.admin_cmd checks the role).
func send_bg_admin(cmd: String) -> void:
	if active and not server:
		rpc_id(1, "sv_bg_admin", cmd)

@rpc("any_peer", "call_remote", "reliable")
func sv_bg_admin(cmd: String) -> void:
	if server and game.bg != null:
		game.bg.admin_cmd(multiplayer.get_remote_sender_id(), cmd)

func request_extract() -> void:
	rpc_id(1, "sv_extract")

## The server checks the player stands at an open Extraction Portal and lets them out.
@rpc("any_peer", "call_remote", "reliable")
func sv_extract() -> void:
	if not server or game.bg == null:
		return
	var pid := multiplayer.get_remote_sender_id()
	if not game.bg.near_open_extract(pid):
		rpc_id(pid, "cl_bg_note", "The portal isn't open yet" if game.bg.open.is_empty() else "Stand in an open Extraction Portal to leave")
		return
	var gained: Array = game.bg.extract(pid)
	print("[BG] %s extracted with %d item(s) picked up" % [_name_of(pid), gained.size()])
	rpc_id(pid, "cl_extracted", gained)

@rpc("authority", "call_remote", "reliable")
func cl_extracted(gained: Array) -> void:
	game.bg_extracted(gained)

## The raid server turned us away: "closed" (too late into the round: `secs` until the next one lets players in;
## Game.bg_refused shows a countdown and rejoins then) or "refused" (the account couldn't be confirmed).
@rpc("authority", "call_remote", "reliable")
func cl_bg_refused(why: String, secs: float) -> void:
	game.bg_refused(why, secs)

@rpc("authority", "call_remote", "reliable")
func cl_bg_note(txt: String) -> void:
	game.ui.message(txt, Color(1.0, 0.8, 0.4))

# ---------------------------------------------------------------- chests, shrines, portals
func inter_used(t: Inter) -> void:
	var idx: int = game.world.interactables.find(t)
	if idx < 0:
		return
	if is_host:
		if not players.is_empty():
			rpc("cl_inter", idx)
	else:
		rpc_id(1, "sv_inter", idx)

@rpc("any_peer", "call_remote", "reliable")
func sv_inter(idx: int) -> void:
	if not is_host or game.world == null or idx >= game.world.interactables.size():
		return
	var t = game.world.interactables[idx]
	if not is_instance_valid(t) or t.used:
		return
	if t.kind == "chest" and game.chest_sealed(t):
		return          # (a boss's chest, its boss alive here: the server's word, whatever the client thought)
	game.use_inter_remote(t)
	var pid := multiplayer.get_remote_sender_id()
	for op in players:
		if op != pid:
			rpc_id(op, "cl_inter", idx)

@rpc("authority", "call_remote", "reliable")
func cl_inter(idx: int) -> void:
	if loading or game.world == null or idx >= game.world.interactables.size():
		return
	var t = game.world.interactables[idx]
	if is_instance_valid(t) and not t.used:
		game.use_inter_remote(t)

# ---------------------------------------------------------------- woodcutting (Harvest; the host owns the trees)
func request_chop(id: int, power: float) -> void:
	rpc_id(1, "sv_chop", id, power)

## Host: a partner's axe blow. The host checks it (Harvest.strike: the tree stands, the partner is by it, not
## too quick), applies it and tells everyone.
@rpc("any_peer", "call_remote", "reliable")
func sv_chop(id: int, power: float) -> void:
	# a dedicated server hosting the story game owns the trees just like a player host
	if not is_host or game.world == null:
		return
	var pid := multiplayer.get_remote_sender_id()
	var h := Harvest.of(game.world)
	var ph = players.get(pid, {}).get("hero")
	if h == null or not is_instance_valid(ph):
		return
	h.strike(id, pid, ph.global_position, power)

## Host -> everyone: what happened to a tree ("hit", "fell", "heal", "regrow").
func send_tree(id: int, ev: String, data: Dictionary) -> void:
	if players.is_empty():
		return
	rpc("cl_tree", id, ev, data)

@rpc("authority", "call_remote", "reliable")
func cl_tree(id: int, ev: String, data: Dictionary) -> void:
	if loading or game.world == null:
		return
	var h := Harvest.of(game.world)
	if h != null:
		h.play_event(id, ev, data)

@rpc("authority", "call_remote", "reliable")
func cl_trees(d: Dictionary) -> void:
	if loading or game.world == null:
		return
	var h := Harvest.of(game.world)
	if h != null:
		h.apply_snapshot(d)

func request_portal(pos: Vector3) -> void:
	rpc_id(1, "sv_portal", pos)

@rpc("any_peer", "call_remote", "reliable")
func sv_portal(pos: Vector3) -> void:
	if is_host and not refuses_travel() and game.world and game.cur_zone != "town":
		game.open_town_portal_at(pos)

func portal_created(t: Inter) -> void:
	t.set_meta("dyn", true)
	if is_host and not players.is_empty():
		rpc("cl_portal", t.global_position, t.data.get("dir", "town"), t.label, game.tp_link)

@rpc("authority", "call_remote", "reliable")
func cl_portal(pos: Vector3, dir: String, label: String, tp: Dictionary) -> void:
	if loading or game.world == null:
		return
	game.tp_link = tp
	var t: Inter = game._make_portal(pos, dir)
	t.label = label
	t.set_meta("dyn", true)
	Sfx.play("portal")
	Fx.burst(game.world.fx_root, pos + Vector3(0, 1.4, 0), Color(0.4, 0.6, 1.0), 40, 3.0, 0.12, 1.0, true, 0.0)

# ---------------------------------------------------------------- the ready check: the party travels only together
## Someone wants to go elsewhere (an exit, a waypoint, a portal; Game.travel): everyone is asked (UI.party_vote,
## Join / Not yet) and the host takes the party there once all have said Join. One trip at a time; the one who
## asked can call it off. The host keeps the vote: {"trip": [act, zone, spawn, at, clear_tp], "from": pid,
## "name", "dest", "yes": {pid: bool}}.
var vote := {}
var _trip_cool := 0.0

## Everyone in the game, this player included.
func party_size() -> int:
	return (players.size() + 1) if active else 1

func ask_trip(act: int, zone: String, spawn: String, at, clear_tp := false) -> void:
	if _trip_cool > 0.0 or (game.ui.vote_panel != null and game.ui.vote_panel.visible):
		return
	_trip_cool = 1.0
	if is_host:
		_start_vote(1, act, zone, spawn, Vector3.INF if at == null else at, clear_tp)
	else:
		rpc_id(1, "sv_trip", act, zone, spawn, at if at != null else Vector3.INF, clear_tp)

@rpc("any_peer", "call_remote", "reliable")
func sv_trip(act: int, zone: String, spawn: String, at: Vector3, clear_tp: bool) -> void:
	if is_host and not refuses_travel() and not game._busy:
		_start_vote(multiplayer.get_remote_sender_id(), act, zone, spawn, at, clear_tp)

func _name_of(pid: int) -> String:
	if pid == 1 and is_host:
		return my_name
	return str(players[pid]["name"]) if players.has(pid) else "?"

func _start_vote(pid: int, act: int, zone: String, spawn: String, at: Vector3, clear_tp: bool) -> void:
	if not vote.is_empty():
		return
	vote = {"trip": [act, zone, spawn, at, clear_tp], "from": pid, "name": _name_of(pid), "dest": game.zone_title(act, zone), "yes": {pid: true}}
	if server:
		vote["yes"][1] = true      # a dedicated server has no player of its own to ask
	game.ui.party_vote(vote["name"], vote["dest"], pid == 1)
	rpc("cl_vote", pid, vote["name"], vote["dest"])
	_vote_check()

@rpc("authority", "call_remote", "reliable")
func cl_vote(from_pid: int, nm: String, dest: String) -> void:
	game.ui.party_vote(nm, dest, from_pid == multiplayer.get_unique_id())

## This player's answer (the popup's Join / Not yet).
func answer_vote(yes: bool) -> void:
	if is_host:
		_vote_answer(1, yes)
	else:
		rpc_id(1, "sv_vote", yes)

@rpc("any_peer", "call_remote", "reliable")
func sv_vote(yes: bool) -> void:
	if is_host:
		_vote_answer(multiplayer.get_remote_sender_id(), yes)

func _vote_answer(pid: int, yes: bool) -> void:
	if vote.is_empty():
		return
	vote["yes"][pid] = yes
	_vote_check()

## The one who asked calls the trip off.
func cancel_vote() -> void:
	if is_host:
		_end_vote()
	else:
		rpc_id(1, "sv_vote_cancel")

@rpc("any_peer", "call_remote", "reliable")
func sv_vote_cancel() -> void:
	if is_host and not vote.is_empty() and int(vote["from"]) == multiplayer.get_remote_sender_id():
		_end_vote()

func _vote_check() -> void:
	var waiting := []
	for pid in [1] + players.keys():
		if not bool(vote["yes"].get(pid, false)):
			waiting.append(_name_of(pid))
	if waiting.is_empty():
		var t: Array = vote["trip"]
		_end_vote()
		game.travel_now(int(t[0]), str(t[1]), str(t[2]), null if t[3] == Vector3.INF else t[3], bool(t[4]))
		return
	game.ui.party_vote_wait(waiting)
	rpc("cl_vote_wait", waiting)

@rpc("authority", "call_remote", "reliable")
func cl_vote_wait(waiting: Array) -> void:
	game.ui.party_vote_wait(waiting)

func _end_vote() -> void:
	vote = {}
	game.ui.party_vote_end()
	if not players.is_empty():
		rpc("cl_vote_end")

@rpc("authority", "call_remote", "reliable")
func cl_vote_end() -> void:
	game.ui.party_vote_end()

# ---------------------------------------------------------------- the party leader (the host) removes a member
func kick(pid: int) -> void:
	if not is_host or not players.has(pid):
		return
	var nm := _name_of(pid)
	rpc_id(pid, "cl_kicked")
	await get_tree().create_timer(0.3).timeout
	if players.has(pid):
		drop_peer(pid)
	game.ui.message("%s was removed from the party" % nm, Color(1.0, 0.8, 0.4))

@rpc("authority", "call_remote", "reliable")
func cl_kicked() -> void:
	shutdown()
	game.on_net_failed("The party leader removed you from the game.")

# ---------------------------------------------------------------- party panel
func _build_party_ui() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 5
	add_child(layer)
	party_box = VBoxContainer.new()
	party_box.position = Vector2(20, 64)
	party_box.add_theme_constant_override("separation", 6)
	layer.add_child(party_box)
	status_lbl = Label.new()
	status_lbl.add_theme_font_size_override("font_size", 14)
	status_lbl.add_theme_color_override("font_color", Color(0.7, 0.85, 1.0))
	status_lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	status_lbl.add_theme_constant_override("outline_size", 6)
	party_box.add_child(status_lbl)

func _update_status() -> void:
	if status_lbl == null:
		return
	if not active:
		status_lbl.text = ""
	elif is_host:
		var ips := local_ips()
		status_lbl.text = "♛ Party leader  ·  %d joined%s" % [players.size(), ("  ·  " + ips[0]) if ips.size() > 0 else ""]
	else:
		status_lbl.text = "Sandbox" if game.sandbox != null else "Arena" if game.arena_mode else ("Battlegrounds" if game.bg_mode else "Co-op")

func _rebuild_party_ui() -> void:
	for c in party_box.get_children():
		if c != status_lbl:
			c.queue_free()
	for pid in players:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		row.set_meta("pid", pid)
		var nm := Label.new()
		# the party leader (the host) wears the crown
		nm.text = ("♛ " if pid == 1 else "") + str(players[pid]["name"])
		nm.custom_minimum_size = Vector2(110, 0)
		nm.add_theme_font_size_override("font_size", 15)
		var h = players[pid]["hero"]
		nm.add_theme_color_override("font_color", h.ally_color if is_instance_valid(h) else Color.WHITE)
		nm.add_theme_color_override("font_outline_color", Color(0, 0, 0))
		nm.add_theme_constant_override("outline_size", 6)
		row.add_child(nm)
		var bg := ColorRect.new()
		bg.color = Color(0.08, 0.02, 0.02, 0.85)
		bg.custom_minimum_size = Vector2(140, 12)
		bg.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(bg)
		var fill := ColorRect.new()
		fill.name = "fill"
		fill.color = Color(0.75, 0.1, 0.08)
		fill.size = Vector2(140, 12)
		bg.add_child(fill)
		if is_host:
			var k := Button.new()
			k.text = "✕"
			k.tooltip_text = "Remove %s from the party" % players[pid]["name"]
			k.custom_minimum_size = Vector2(26, 22)
			k.add_theme_font_size_override("font_size", 13)
			k.add_theme_color_override("font_color", Color(0.85, 0.7, 0.42))
			k.add_theme_color_override("font_hover_color", Color(1.0, 0.45, 0.35))
			var sb := StyleBoxFlat.new()
			sb.bg_color = Color(0.07, 0.065, 0.06, 0.92)
			sb.border_color = Color(0.55, 0.43, 0.24)
			sb.set_border_width_all(1)
			sb.set_corner_radius_all(3)
			k.add_theme_stylebox_override("normal", sb)
			var sbh := sb.duplicate() as StyleBoxFlat
			sbh.border_color = Color(1.0, 0.6, 0.4)
			k.add_theme_stylebox_override("hover", sbh)
			k.add_theme_stylebox_override("pressed", sbh)
			var kp: int = pid
			k.pressed.connect(func(): game.ui.confirm_kick(kp, str(players[kp]["name"]) if players.has(kp) else ""))
			row.add_child(k)
		party_box.add_child(row)
	_update_status()

func _update_party_ui() -> void:
	if party_box == null:
		return
	party_box.visible = game.playing and not game.ui.any_panel_open()
	for row in party_box.get_children():
		if not row.has_meta("pid"):
			continue
		var pid: int = row.get_meta("pid")
		if not players.has(pid):
			continue
		var h = players[pid]["hero"]
		if game.arena_mode and game.sandbox == null:
			var team := int(game.arena_state.get("teams", {}).get(str(pid), -1))
			row.get_child(0).text = str(players[pid]["name"]) + (" · Ember" if team == 0 else " · Frost")
			row.get_child(0).add_theme_color_override("font_color", Color(1,0.55,0.3) if team == 0 else Color(0.45,0.75,1))
		var fill := row.get_child(1).get_node("fill") as ColorRect
		if is_instance_valid(h):
			var f: float = clampf(h.life / maxf(h.max_life, 1.0), 0.0, 1.0)
			fill.size.x = 140.0 * f
			fill.color = Color(0.3, 0.3, 0.3) if h.dead else Color(0.75, 0.1, 0.08)

@rpc("authority", "call_remote", "reliable")
func cl_arena_reset(at: Vector3) -> void:
	if not game.arena_mode:return
	ClassSkills.clear(game.hero)
	SkillFx.clear(game.hero)
	game.hero.respawn(at)
	game.hero.cds.clear()
	for sk in game.hero.skill_list() + Data.shared_skills(): game.hero.cds[sk.id] = 0.0
	game.hero.buff_t = 0
	game.hero.burn_t = 0
	game.hero.mana_pool = 0
	game.hero.knock_v = Vector3.ZERO
	game.hero.shove = Vector3.ZERO
	game.hero.atk_t = -1
	game.hero.charge_t = -1
	game.hero.channel_t = -1
	game.hero.direct_dir = Vector3.ZERO
	game.hero.life=game.hero.max_life
	game.hero.mana=game.hero.max_mana
	game.hero.stamina=game.hero.max_stamina
	game.death_t=-1
	game.ui.death_panel.visible=false

@rpc("authority", "call_remote", "reliable")
func cl_arena_state(data: Dictionary) -> void:
	if game.arena_mode:
		game.arena_state=data
		_update_status()

@rpc("authority", "call_remote", "reliable")
func cl_match_end(reason: String) -> void:
	if game.lobby_client!=null:game.lobby_client.finished(reason)
