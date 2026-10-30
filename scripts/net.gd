class_name Net
extends Node
## LAN co-op. The host runs the monsters, loot, chests and the boss. Every player runs their
## own knight and streams its pose to the others, who show it as a puppet. The party always
## shares one area: whoever walks through an exit or portal takes everyone along.

const PORT := 24567
const DISCO_PORT := 24568
const MAX_CLIENTS := 3
const STYLES := ["over", "back", "side", "thrust", "bow", "cast", "claw", "slam", "bite", "smash", "lob", "scoop", "burst", "cackle", "swipe1", "swipe2", "swipe3", "cleave", "feral_lunge", "feral_swipe", "perch", "descend"]
const SEND_RATE := 0.05
const ALLY_COLORS := [Color(0.45, 0.8, 1.0), Color(0.5, 1.0, 0.5), Color(1.0, 0.6, 0.9)]

var game: Node
var peer: ENetMultiplayerPeer
var active := false
var is_host := false
var my_name := "Crusader"
var players := {}          # peer id -> {"name": String, "hero": Hero}
var enemies := {}          # net id -> Enemy
var items := {}            # net id -> GroundItem
var next_id := 1
var loading := false
var pending_ready: Array = []
var travel_cool := 0.0
var next_goto_new_run := false
var party_max_run := 0
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
func host() -> int:
	shutdown()
	peer = ENetMultiplayerPeer.new()
	var err := peer.create_server(PORT, MAX_CLIENTS)
	if err != OK:
		peer = null
		return err
	multiplayer.multiplayer_peer = peer
	active = true
	is_host = true
	disco = PacketPeerUDP.new()
	disco.set_broadcast_enabled(true)
	disco.set_dest_address("255.255.255.255", DISCO_PORT)
	_update_status()
	return OK

func join(ip: String) -> int:
	shutdown()
	peer = ENetMultiplayerPeer.new()
	var err := peer.create_client(ip, PORT)
	if err != OK:
		peer = null
		return err
	multiplayer.multiplayer_peer = peer
	active = true
	is_host = false
	loading = true
	return OK

func shutdown() -> void:
	for pid in players.keys():
		_remove_player(pid)
	players.clear()
	enemies.clear()
	items.clear()
	if peer:
		peer.close()
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
	rpc_id(1, "sv_hello", my_name, game.hero.net_gear(), game.hero.level)

func _on_connect_failed() -> void:
	shutdown()
	game.on_net_failed("Could not connect to that game.")

func _on_server_gone() -> void:
	shutdown()
	game.on_net_failed("The host left the game.")

func _on_peer_disconnected(pid: int) -> void:
	if not players.has(pid):
		return
	var n: String = players[pid]["name"]
	_remove_player(pid)
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
	if players.is_empty() or game.world == null or game._busy or loading:
		_update_party_ui()
		return
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
		rpc("cl_enemy_states", arr)
	_update_party_ui()

func _hero_packet(h: Hero) -> PackedFloat32Array:
	var st: Dictionary = h.last_pose
	return PackedFloat32Array([h.global_position.x, h.global_position.y, h.global_position.z, h.rig.rotation.y,
		h.phase, st.get("move", 0.0), st.get("atk", -1.0), float(maxi(0, STYLES.find(st.get("style", "over")))),
		st.get("block", 0.0), st.get("hit", 0.0), 1.0 if h.dead else 0.0, h.dead_t, h.life, h.max_life,
		1.0 if h.buff_t > 0.0 else 0.0])

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

# ---------------------------------------------------------------- handshake
@rpc("any_peer", "call_remote", "reliable")
func sv_hello(nm: String, gear: Dictionary, _lvl: int) -> void:
	if not is_host:
		return
	var pid := multiplayer.get_remote_sender_id()
	var roster := [[1, my_name, game.hero.net_gear()]]
	for op in players:
		roster.append([op, players[op]["name"], players[op]["hero"].net_gear()])
		rpc_id(op, "cl_player_join", pid, nm, gear)
	_add_player(pid, nm, gear)
	rpc_id(pid, "cl_welcome", game.cur_act, game.cur_zone, game.hero.global_position, game.tp_link, game.boss_killed, roster, game.difficulty)
	game.ui.message(nm + " joined the game", Color(0.5, 1.0, 0.5))
	Sfx.play("portal")
	_update_status()

@rpc("authority", "call_remote", "reliable")
func cl_welcome(act: int, zone: String, pos: Vector3, tp: Dictionary, bk: bool, roster: Array, diff: int) -> void:
	game.difficulty = diff
	for r in roster:
		_add_player(int(r[0]), str(r[1]), r[2])
	game.tp_link = tp
	game.boss_killed = bk
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
	var nr := next_goto_new_run
	next_goto_new_run = false
	if not is_host or players.is_empty():
		return
	enemies.clear()
	items.clear()
	rpc("cl_goto", act, zone, spawn, at if at != null else Vector3.INF, game.tp_link, game.boss_killed, game.difficulty, nr, game.max_run)

@rpc("authority", "call_remote", "reliable")
func cl_goto(act: int, zone: String, spawn: String, at: Vector3, tp: Dictionary, bk: bool, diff: int, new_run: bool, host_max: int) -> void:
	party_max_run = host_max
	if diff != game.difficulty and not new_run:
		# the host switched runs at the waypoint: swap our own waypoint progress to match
		game._store_progress()
		game._restore_progress(diff)
		game.difficulty = diff
		game.max_run = maxi(game.max_run, diff)
		game.run_switched_banner()
	game.tp_link = tp
	game.boss_killed = bk
	game.difficulty = diff
	game.max_run = maxi(game.max_run, diff)
	if new_run:
		game.waypoints_known = ["town"]
		game.ui.victory_panel.visible = false
		game.ui.set_boss(null)
		if game.hero.dead:
			game.hero.respawn(game.hero.global_position)
		game.hero.life = game.hero.max_life
		game.run_banner()
	_client_goto(act, zone, spawn, null if at == Vector3.INF else at)

func _client_goto(act: int, zone: String, spawn: String, at) -> void:
	loading = true
	enemies.clear()
	items.clear()
	for h in puppets():
		h.visible = false
		h.net_has = false
	while game._busy:
		await get_tree().process_frame
	await game.load_zone(act, zone, spawn, at)
	var p: Vector3 = game.hero.global_position + Vector3(1.4, 0, 1.0)
	game.hero.global_position = game.world.free_spot_near(p, 1.5)
	game.hero.global_position.y = game.world.height_at(game.hero.global_position.x, game.hero.global_position.z)
	loading = false
	rpc_id(1, "sv_zone_ready")

func request_switch(d: int) -> void:
	rpc_id(1, "sv_switch", d)

@rpc("any_peer", "call_remote", "reliable")
func sv_switch(d: int) -> void:
	if is_host and not game._busy:
		game.switch_run(d)

func request_a2() -> void:
	rpc_id(1, "sv_a2")

@rpc("any_peer", "call_remote", "reliable")
func sv_a2() -> void:
	if is_host and game.boss_killed and not game._busy:
		game.start_a2()

func request_travel(act: int, zone: String, spawn: String, at, clear_tp := false) -> void:
	if travel_cool > 0.0:
		return
	travel_cool = 2.0
	rpc_id(1, "sv_travel", act, zone, spawn, at if at != null else Vector3.INF, clear_tp)
	game.ui.message("Travelling...", Color(0.6, 0.75, 1.0))

@rpc("any_peer", "call_remote", "reliable")
func sv_travel(act: int, zone: String, spawn: String, at: Vector3, clear_tp: bool) -> void:
	if not is_host or game._busy:
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

func send_enemy_hit(e: Enemy, phys: float, fire: float, from: Vector3, knock: float, crit: bool) -> void:
	rpc_id(1, "sv_enemy_hit", e.net_id, phys, fire, from, knock, crit)

@rpc("any_peer", "call_remote", "reliable")
func sv_enemy_hit(id: int, phys: float, fire: float, from: Vector3, knock: float, crit: bool) -> void:
	if not is_host or not enemies.has(id):
		return
	var e = enemies[id]
	if is_instance_valid(e) and not e.dead:
		e.take_damage(phys, fire, from, knock, crit)

func send_enemy_chill(e: Enemy, k: float, t: float) -> void:
	rpc_id(1, "sv_enemy_chill", e.net_id, k, t)

@rpc("any_peer", "call_remote", "reliable")
func sv_enemy_chill(id: int, k: float, t: float) -> void:
	if is_host and enemies.has(id) and is_instance_valid(enemies[id]):
		(enemies[id] as Enemy).chill(clampf(k, 0.0, 0.8), clampf(t, 0.0, 6.0))

func send_enemy_stun(e: Enemy, t: float) -> void:
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
		if e.boss:
			game.boss_down_remote(e)

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

## Aurelia's arena (games.gd): the host's events (gates, announcements, the crowd) to everyone.
func games_event(ev: String) -> void:
	if is_host and not players.is_empty():
		rpc("cl_games", ev)

@rpc("authority", "call_remote", "reliable")
func cl_games(ev: String) -> void:
	if not loading and game.world != null and game.world.has_meta("games"):
		game.world.get_meta("games").fx(ev)

## A partner struck Varro's deal: the host starts the games.
func request_games() -> void:
	rpc_id(1, "sv_games")

@rpc("any_peer", "call_remote", "reliable")
func sv_games() -> void:
	if is_host and game.world != null and game.world.has_meta("games"):
		game.world.get_meta("games").begin()

## Host: put a partner's knight somewhere (onto the arena's sand when its gate drops).
func place_player(pid: int, pos: Vector3) -> void:
	rpc_id(pid, "cl_place", pos)

@rpc("authority", "call_remote", "reliable")
func cl_place(pos: Vector3) -> void:
	if not loading and game.world != null:
		game.hero.global_position = Vector3(pos.x, game.world.height_at(pos.x, pos.z), pos.z)
		game.hero.path = PackedVector3Array()
		game.hero.moving = false

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

func request_portal(pos: Vector3) -> void:
	rpc_id(1, "sv_portal", pos)

@rpc("any_peer", "call_remote", "reliable")
func sv_portal(pos: Vector3) -> void:
	if is_host and game.world and game.cur_zone != "town":
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
	if is_host and not game._busy:
		_start_vote(multiplayer.get_remote_sender_id(), act, zone, spawn, at, clear_tp)

func _name_of(pid: int) -> String:
	if pid == 1 and is_host:
		return my_name
	return str(players[pid]["name"]) if players.has(pid) else "?"

func _start_vote(pid: int, act: int, zone: String, spawn: String, at: Vector3, clear_tp: bool) -> void:
	if not vote.is_empty():
		return
	vote = {"trip": [act, zone, spawn, at, clear_tp], "from": pid, "name": _name_of(pid), "dest": game.zone_title(act, zone), "yes": {pid: true}}
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
	if peer != null and players.has(pid):
		peer.disconnect_peer(pid)
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
		status_lbl.text = "Co-op"

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
	party_box.visible = game.playing
	for row in party_box.get_children():
		if not row.has_meta("pid"):
			continue
		var pid: int = row.get_meta("pid")
		if not players.has(pid):
			continue
		var h = players[pid]["hero"]
		var fill := row.get_child(1).get_node("fill") as ColorRect
		if is_instance_valid(h):
			var f: float = clampf(h.life / maxf(h.max_life, 1.0), 0.0, 1.0)
			fill.size.x = 140.0 * f
			fill.color = Color(0.3, 0.3, 0.3) if h.dead else Color(0.75, 0.1, 0.08)
