class_name Battlegrounds
extends Node
## Battlegrounds (prototype, phase 1): an extraction raid on a dedicated server. The server is the game run headless
## with `-- --server` (Game._ready -> start_server): it hosts the "bg" zone through the usual co-op layer (Net), with
## no player of its own (Net.server: its hero is hidden, parked off the map and phased, so monsters never see it).
## Players pick Battlegrounds on the title screen, connect to its address and spawn at a random point; they kill
## zombies, loot chests and step into an Extraction Portal to leave with what they picked up. The server keeps the
## record: every item a player picks up is `carried` for them; extracting moves it into their stash (saved on the
## server by the player's id, `client_id`), dying or leaving drops it on the floor for anyone. Not hack-proof (the
## id is just a random file on the player's PC); Nakama takes over accounts and the stash later.
## Tests: tools/bg_test.gd (server + client: `-- server` and `-- client`).

const ZONE := "bg"
const TITLE := "The Battlegrounds"
const MAX_PLAYERS := 16
const HALF := 30.0              # the map is 60 x 60 m
const ZOMBIES := 9              # kept alive on the map (server)
const RESPAWN_T := 5.0          # seconds between respawns while below ZOMBIES
const EXTRACT_R := 4.5          # how close to a portal the server accepts an extraction
const STASH_PATH := "user://bg_server/stash.json"
const ID_PATH := "user://bg_id.txt"
const CACHE_PATH := "user://bg_stash_cache.json"
const TEST_STASH := "user://bg_server/test_stash.json"   # the server's stash under a test tool
static var id_path := ID_PATH         # tests point these elsewhere, so a run never touches the real ones
static var cache_path := CACHE_PATH

var game: Node
var stash := {}                 # server: player id (client_id) -> Array of items
var carried := {}               # server: peer id -> Array of items picked up this raid
var uids := {}                  # server: peer id -> player id
var dead_seen := {}             # server: peer id -> true once their death has dropped their loot
var stash_path := STASH_PATH
var _spawn_t := 0.0

# ---------------------------------------------------------------- the map
## The simplest raid map: a walled ruin in the moor, a crossroads of trodden paths, broken walls and graves for
## cover, two chests and an Extraction Portal at each end. Same seed on every peer, like any zone.
static func build(w: World) -> void:
	w.bounds = Rect2(-HALF, -HALF, HALF * 2.0, HALF * 2.0)
	w.theme = {"name": "bg"}
	w.dirt_lines = [[Vector2(0, -HALF), Vector2(0, HALF), 3.0], [Vector2(-HALF, 0), Vector2(HALF, 0), 2.6],
		[Vector2(-18, -18), Vector2(18, 18), 1.8]]
	w.dirt_blobs = [[Vector2(0, 0), 7.0, 1.0], [Vector2(0, -24), 4.5, 0.9], [Vector2(0, 24), 4.5, 0.9],
		[Vector2(-20, 10), 4.0, 0.8], [Vector2(19, -11), 4.0, 0.8]]
	w.cobble_blobs = [[Vector2(0, 0), 4.5, 0.9], [Vector2(0, -24), 2.6, 0.8], [Vector2(0, 24), 2.6, 0.8]]
	# the ruin's broken walls round the middle (gaps on every side) and a few loose stretches for cover
	for seg in [[Vector2(-9, -9), Vector2(-3, -9)], [Vector2(3, -9), Vector2(9, -9)], [Vector2(9, -9), Vector2(9, -3)],
			[Vector2(9, 3), Vector2(9, 9)], [Vector2(9, 9), Vector2(3, 9)], [Vector2(-3, 9), Vector2(-9, 9)],
			[Vector2(-9, 9), Vector2(-9, 3)], [Vector2(-9, -3), Vector2(-9, -9)],
			[Vector2(-22, -20), Vector2(-14, -20)], [Vector2(15, 18), Vector2(22, 18)], [Vector2(-21, 15), Vector2(-21, 22)],
			[Vector2(21, -22), Vector2(21, -15)]]:
		w._wall(Vector3(seg[0].x, 0, seg[0].y), Vector3(seg[1].x, 0, seg[1].y), 1.3)
	for g in [Vector2(-15, 4), Vector2(-16, 6), Vector2(-14, 7.5), Vector2(14, -5), Vector2(15.5, -6.5), Vector2(13, -8)]:
		w._gravestone(Vector3(g.x, 0, g.y), w.rng.randf() < 0.4)
	for s in [Vector2(-25, -6), Vector2(25, 6), Vector2(-6, 26), Vector2(6, -26)]:
		w._standing_stone(Vector3(s.x, 0, s.y), w.rng.randf_range(1.6, 2.4))
	for i in 34:
		var p := Vector3(w.rng.randf_range(-HALF + 2, HALF - 2), 0, w.rng.randf_range(-HALF + 2, HALF - 2))
		if w.dirt_at(p.x, p.z) > 0.3 or w.is_near_obstacle(p, 2.0):
			continue
		w._rock(p, w.rng.randf_range(0.3, 1.1), w.rng.randf() < 0.5)
	w._chest(Vector3(-5.5, 0, -5.5))
	w._chest(Vector3(22, 0, 22))
	# extraction: a portal at the north and the south end
	for e in [Vector3(0, 0, -HALF + 4.0), Vector3(0, 0, HALF - 4.0)]:
		w._inter("extract", "Extraction Portal", e, 1.8, Fx.portal_model(), {})
	# the moor's forest beyond the edge
	var pines := [[], [], []]
	for i in 160:
		var x := w.rng.randf_range(-HALF - 22, HALF + 22)
		var z := w.rng.randf_range(-HALF - 22, HALF + 22)
		if w.bounds.grow(-1.0).has_point(Vector2(x, z)):
			continue
		pines[i % 3].append(Transform3D(Basis(Vector3.UP, w.rng.randf() * TAU).scaled(Vector3.ONE * w.rng.randf_range(0.8, 1.4)), Vector3(x, w.height_at(x, z) - 0.2, z)))
	for k in 3:
		Props.multimesh(w.props_root, Flora.pine(k + 1), pines[k])
	w._rasterize()
	w._flush_stones(Props.stone())
	w._build_terrain(World.MOOR_TERRAIN)
	w._scatter_grass(16000, World.MOOR_GRASS, 0.3)
	w._scatter_ferns(40)
	# where players arrive (spread round the map) and where zombies rise (away from the portals)
	w.spawns["start"] = Vector3(0, 0, 0)
	w.set_meta("bg_spawns", [Vector3(-22, 0, -4), Vector3(22, 0, 4), Vector3(-4, 0, 20), Vector3(4, 0, -20),
		Vector3(-24, 0, 24), Vector3(24, 0, -24), Vector3(-24, 0, -24), Vector3(24, 0, 24)])
	var spots := [Vector3(-3, 0, 3), Vector3(5, 0, -4), Vector3(-17, 0, 6), Vector3(15, 0, -7), Vector3(-12, 0, -17),
		Vector3(12, 0, 15), Vector3(-26, 0, 12), Vector3(26, 0, -12), Vector3(-8, 0, 14), Vector3(8, 0, -13)]
	w.set_meta("bg_zombie_spots", spots)
	for i in ZOMBIES:
		w.enemy_spawns.append({"kind": "zombie", "pos": spots[i % spots.size()], "count": 1, "champ": false,
			"pack": 700 + i, "level": w.level + 1})

# ---------------------------------------------------------------- server
## Game._ready with `-- --server [--port N]`: the dedicated server. No title, no player of its own.
static func start_server(g: Node, port: int) -> void:
	var bg := Battlegrounds.new()
	bg.name = "Battlegrounds"
	bg.game = g
	g.add_child(bg)
	g.bg = bg
	if g._testing():
		bg.stash_path = TEST_STASH
	bg.load_stash()
	g.net.server = true
	g.ui.hide_title()
	g.playing = true
	g.difficulty = 0
	g.test_immortal = true
	# hosting first, so the zone's monsters are registered with the network as they spawn
	var err: int = g.net.host(port, MAX_PLAYERS)
	await g.load_zone(0, ZONE, "start")
	bg.park_hero()
	print("[BG] server ", "up on UDP port %d" % port if err == OK else "FAILED to open port %d (error %d)" % [port, err])

## The server's own hero: hidden, off the map and phased, so monsters never see it (kept so every frame).
func park_hero() -> void:
	game.hero.global_position = Vector3(0, 0, -HALF - 40.0)
	game.hero.visible = false
	game.hero.phased = true

## A spot for a player arriving: the arrival point farthest from everyone already there and the monsters.
func spawn_point() -> Vector3:
	var pts: Array = game.world.get_meta("bg_spawns", [Vector3.ZERO])
	var best: Vector3 = pts[randi() % pts.size()]
	var bd := -1.0
	for p in pts:
		var d := INF
		for h in game.net.puppets():
			d = minf(d, (h.global_position - p).length())
		for e in game.enemies_near(p, 14.0):
			d = minf(d, (e.global_position - p).length() * 2.0)
		d += randf() * 4.0
		if d > bd:
			bd = d
			best = p
	return game.world.free_spot_near(best, 2.0)

func _process(delta: float) -> void:
	if game == null or not game.net.server or game.world == null or game._busy:
		return
	park_hero()
	# zombies rise again, away from the players
	_spawn_t -= delta
	if _spawn_t <= 0.0:
		_spawn_t = RESPAWN_T
		var alive := 0
		for e in game.world.enemies_root.get_children():
			if e is Enemy and not e.dead:
				alive += 1
		if alive < ZOMBIES:
			var spots: Array = game.world.get_meta("bg_zombie_spots", [])
			spots = spots.duplicate()
			spots.shuffle()
			for p in spots:
				var near := false
				for h in game.net.puppets():
					if (h.global_position - p).length() < 12.0:
						near = true
				if not near:
					game.spawn_enemy("zombie", game.world.free_spot_near(p, 2.0), game.world.level + 1, false, "", 700 + randi() % 1000)
					break
	# a player who fell drops everything they picked up this raid, for anyone to take
	for pid in game.net.players.keys():
		var h = game.net.players[pid]["hero"]
		if not is_instance_valid(h):
			continue
		if h.dead and not dead_seen.has(pid):
			dead_seen[pid] = true
			print("[BG] %s fell, dropping %d item(s)" % [game.net.players[pid]["name"], (carried.get(pid, []) as Array).size()])
			_drop_carried(pid, h.global_position)
		elif not h.dead:
			dead_seen.erase(pid)

func player_hello(pid: int, uid: String) -> Array:
	uids[pid] = uid
	carried[pid] = []
	dead_seen.erase(pid)
	return stash.get(uid, [])

func picked(pid: int, it: Dictionary) -> void:
	if not carried.has(pid):
		carried[pid] = []
	(carried[pid] as Array).append(it)

## Leaving without extracting (quit, crash, lost connection) is the same as dying: the loot stays behind.
func player_left(pid: int, at: Vector3) -> void:
	_drop_carried(pid, at)
	carried.erase(pid)
	uids.erase(pid)
	dead_seen.erase(pid)

func near_extract(pid: int) -> bool:
	if not game.net.players.has(pid):
		return false
	var h = game.net.players[pid]["hero"]
	if not is_instance_valid(h) or h.dead:
		return false
	for t in game.world.interactables:
		if is_instance_valid(t) and t.kind == "extract" and (t.global_position - h.global_position).length() < EXTRACT_R:
			return true
	return false

## The player made it out: what they carried joins their stash. Returns [gained, whole stash].
func extract(pid: int) -> Array:
	var uid: String = uids.get(pid, "")
	var gained: Array = carried.get(pid, [])
	carried[pid] = []
	if uid == "":
		return [[], []]
	var s: Array = stash.get(uid, [])
	s.append_array(gained)
	stash[uid] = s
	save_stash()
	return [gained, s]

func _drop_carried(pid: int, at: Vector3) -> void:
	var c: Array = carried.get(pid, [])
	for it in c:
		game.drop_item(it, at)
	carried[pid] = []

func load_stash() -> void:
	if not FileAccess.file_exists(stash_path):
		return
	var d = JSON.parse_string(FileAccess.get_file_as_string(stash_path))
	if d is Dictionary:
		stash = d

func save_stash() -> void:
	DirAccess.make_dir_recursive_absolute(stash_path.get_base_dir())
	var f := FileAccess.open(stash_path, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(stash))

# ---------------------------------------------------------------- client
## This PC's Battlegrounds id: made once at random, sent to the server, which files the stash under it.
static func client_id() -> String:
	if FileAccess.file_exists(id_path):
		var s := FileAccess.get_file_as_string(id_path).strip_edges()
		if s.length() >= 16:
			return s
	var c := Crypto.new()
	var id := c.generate_random_bytes(16).hex_encode()
	var f := FileAccess.open(id_path, FileAccess.WRITE)
	if f:
		f.store_string(id)
	return id

## The stash as the server last reported it (shown on the Battlegrounds screen while not connected).
static func cached_stash() -> Array:
	if not FileAccess.file_exists(cache_path):
		return []
	var d = JSON.parse_string(FileAccess.get_file_as_string(cache_path))
	return d if d is Array else []

static func cache_stash(s: Array) -> void:
	var f := FileAccess.open(cache_path, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(s))

## "host" or "host:port" -> [host, port]
static func parse_address(txt: String) -> Array:
	txt = txt.strip_edges()
	var port := Net.PORT
	var i := txt.rfind(":")
	if i > 0 and txt.substr(i + 1).is_valid_int():
		port = int(txt.substr(i + 1))
		txt = txt.substr(0, i)
	return [txt if txt != "" else "127.0.0.1", port]
