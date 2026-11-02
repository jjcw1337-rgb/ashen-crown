class_name Battlegrounds
extends Node
## Battlegrounds: the Hollow Crypt, a hardcore extraction raid in the Dark and Darker mould, on a dedicated server
## (`-- --server [--port N]`; Game._ready -> start_server; Net.server, host-authoritative monsters and loot).
##
## The raid: a dungeon of rooms and corridors (build: a 4x4 grid of rooms round a great central hall, a ring of
## corridors with a few gaps, chokepoints into the hall, dark but for torches and candles). Raids run in rounds of
## RAID_SECS: players spawn in the corner rooms, monsters are few but tough (MON_LIFE, MON_DMG), the best loot is in
## the central hall with its champion; the Extraction Portals (two of four, picked at random) open after PORTALS_AT;
## at the end the crypt collapses and whoever is still inside dies. Then the dungeon resets for the next round.
## Joining closes JOIN_CLOSE into a round.
##
## Attacks, skills, damage and cooldowns are the same as everywhere else (one standard for every scenario); the crypt
## only slows walking (MOVE_MULT) and stops life regeneration (client side, Hero, while Game.bg_mode). PvP is on: every other player is an invisible stand-in target on each
## client (sync_proxies: an Enemy with `pvp_pid`, following that player's puppet), so every skill, swing, arrow and
## burn that can hit a monster can hit a player; its take_damage sends Net.sv_pvp_hit, the server scales it (PVP_MULT)
## and deals it to that player.
##
## Characters are the player's real characters (the Battlegrounds screen picks one): what they carry in is what they
## risk, and what they extract stays in their normal inventory. Death costs everything they wore and carried, and
## their gold (Game.bg_strip: they keep levels, stats, talents and the camp's stash, and get a plain weapon back); it
## all drops where they fell for anyone to take (Net.sv_bg_died). A save written while in a raid says so ("in_raid");
## a character whose game closed in a raid has died there the next time the game starts (Game._bury_lost_raiders).
## Tests: tools/bg_test.gd (server + client), tools/bg_pvp_test.gd (server + two players); servers started with
## `--raid-fast` run the round eight times faster.
##
## Several raids at once (Blaine, 2026-11-01): RAIDS servers, one per raid (`--server --raid N`: port RAID_PORTS[N]),
## each running its rounds on the wall clock, raid N's starting N/RAIDS of a PERIOD after raid 0's (`phase`), so a
## fresh raid opens about every 7 minutes and one is always open; a restarted server falls back into its slot. A client
## needs no lobby server for it: `schedule()` works out every raid's state from the clock, `best_raid()` picks the one
## with the most time left that still takes joiners (or the next to open, whose server then counts the wait down).
## LIVE_RAIDS is how many are deployed (the rest wait for their servers and ports).
##
## A round (Blaine: "clear queue/lobby flow, player-triggered wave starts with a preparation state and countdown"):
## "lobby": the players who come wait in the corner rooms behind iron gates (gate_doors), each room with a bell;
## the first who rings it (Inter "bell", through Net.sv_inter: no new RPC) starts "prep", a PREP_SECS countdown
## everyone sees; at LOBBY_MAX nobody has rung, it starts by itself. Then "raid": the gates rise and the crypt is
## open; the Extraction Portals open PORTALS_AT into the round; joining closes at JOIN_CLOSE (a late joiner arrives
## in a corner room, its gate already up); at RAID_SECS the crypt collapses ("reset") and the next round begins on
## the clock. The round's 20 minutes include the lobby, so every raid's clock stays aligned. The state reaches
## players in Net.cl_bg_raid ("lobby:<secs left>", "prep:<secs left>", "raid", "reset").

const ZONE := "bg"
const TITLE := "The Hollow Crypt"
const MAX_PLAYERS := 16
const RAID_SECS := 1200.0       # a round: 20 minutes
const PORTALS_AT := 300.0       # the Extraction Portals open 5 minutes in
const JOIN_CLOSE := 900.0       # nobody new joins in the last 5 minutes
const RESET_SECS := 20.0        # after the collapse, before the next round
const LOBBY_MAX := 75.0         # the antechamber: at most this long before the prep countdown starts by itself
const PREP_SECS := 15.0         # the bell has rung: the countdown to the gates opening
const RAIDS := 3                # raids run side by side, staggered on the clock (phase)
const RAID_PORTS := [24567, 24571, 24572]
const LIVE_RAIDS := 1           # deployed so far (staging: one until its servers and firewall ports are up)
const PERIOD := RAID_SECS + RESET_SECS
const RAID_NAMES := ["I", "II", "III"]
const EXTRACT_R := 4.0          # how close to an open portal the server accepts an extraction
const OPEN_PORTALS := 2         # of the four candidate portals
const PVP_MULT := 0.6           # a player's damage to another player
const MOVE_MULT := 0.85         # walking and running
const MON_LIFE := 2.2           # monsters' life and damage in the crypt (server)
const MON_DMG := 1.4
const MON_LEVEL := 6
const GRID := 24.0              # room grid spacing
const ID_PATH := "user://bg_id.txt"
static var id_path := ID_PATH   # tests point it elsewhere
static var fast := false        # tests: `--raid-fast` = rounds in seconds

var game: Node
var raid_t := 0.0               # server: seconds into the round
var raid_idx := -1              # server: which of the RAIDS this is (`--raid N`), -1 = a lone raid on its own time
var prep_left := 0.0            # server: seconds of the prep countdown left
var state := "lobby"            # server: "lobby" | "prep" | "raid" | "reset"
var reset_t := 0.0
var open: Array = []            # server: indices (in the portal list) of the open Extraction Portals
var carried := {}               # server: peer id -> Array of items picked up this raid (dropped if they vanish)
var died_items := {}            # server: peer id -> true once their death drop was handled
var dead_wait := {}             # server: peer id -> seconds since they fell, waiting for their death drop
var last_hit := {}              # server: peer id -> [attacker peer id, raid_t]
var uids := {}                  # server: peer id -> who they are (Nakama user, or the per-PC id)
var nk: NakamaClient            # server: Nakama, to confirm join tickets (staging, production)
var nk_key := ""
## The admins among the players (Nakama's admin role, ashen.lua admin_check; without Nakama the per-PC ids in
## user://bg_server/admins.json): only they may raid in "Go to level 20" gear (items marked "boost",
## Game.go_level_20); anyone else wearing it is turned away (gear_ok, checked every GEAR_CHECK seconds).
var admins := {}
var _gear_t := 0.0
const GEAR_CHECK := 2.0
var _sync_t := 0.0

static func secs(n: float) -> float:
	return n / 8.0 if fast else n       # (tests: a 150 s round, portals at 37.5 s, joining closes at 112.5 s)

## Seconds into raid i's current period (0 .. PERIOD: a round, then its reset) at unix time `now`.
static func phase(i: int, now: float) -> float:
	return fposmod(now - float(i) * PERIOD / float(RAIDS), PERIOD)

## Every live raid's state now, from the clock: {i, name, port, state ("raid"/"reset"), left (s of the round),
## open (takes joiners), opens_in (s until it next does)}.
static func schedule(now: float, n := LIVE_RAIDS) -> Array:
	var out := []
	for i in mini(n, RAIDS):
		var ph := phase(i, now)
		var raid := ph < RAID_SECS
		out.append({"i": i, "name": RAID_NAMES[i], "port": RAID_PORTS[i], "state": "raid" if raid else "reset",
			"left": maxf(0.0, RAID_SECS - ph), "open": raid and ph < JOIN_CLOSE,
			"opens_in": 0.0 if raid and ph < JOIN_CLOSE else PERIOD - ph})
	return out

## The raid to send a player to: the open one with the most time left, else the one that opens soonest.
static func best_raid(now: float, n := LIVE_RAIDS) -> Dictionary:
	var best := {}
	for r in schedule(now, n):
		if r["open"] and (best.is_empty() or not best["open"] or float(r["left"]) > float(best["left"])):
			best = r
		elif not r["open"] and (best.is_empty() or (not best["open"] and float(r["opens_in"]) < float(best["opens_in"]))):
			best = r
	return best

# ---------------------------------------------------------------- the map
## The Hollow Crypt. Cell (i, j) of a 4x4 grid; the middle 2x2 is the great hall.
static func build(w: World) -> void:
	w.flat_floor = true
	w.theme = {"name": "bg"}
	var rooms := {}                 # Vector2i -> Rect2
	var kinds := {}                 # Vector2i -> "spawn" | "portal" | "crypt" | "treasure" | "hall"
	for j in 4:
		for i in 4:
			var cell := Vector2i(i, j)
			if (i == 1 or i == 2) and (j == 1 or j == 2):
				continue
			var c := Vector2((i - 1.5) * GRID, (j - 1.5) * GRID)
			var sx := w.rng.randf_range(11.0, 15.0)
			var sz := w.rng.randf_range(11.0, 15.0)
			rooms[cell] = Rect2(c.x - sx * 0.5, c.y - sz * 0.5, sx, sz)
			var corner := (i == 0 or i == 3) and (j == 0 or j == 3)
			kinds[cell] = "spawn" if corner else ""
	# the four sides' middle rooms: one portal room per side, the other a treasure room
	var sides := [[Vector2i(1, 0), Vector2i(2, 0)], [Vector2i(3, 1), Vector2i(3, 2)], [Vector2i(1, 3), Vector2i(2, 3)], [Vector2i(0, 1), Vector2i(0, 2)]]
	for pair in sides:
		var k := w.rng.randi() % 2
		kinds[pair[k]] = "portal"
		kinds[pair[1 - k]] = "treasure"
	var hall := Rect2(-17.0, -17.0, 34.0, 34.0)
	for cell in rooms:
		w.floor_rects.append(rooms[cell])
	w.floor_rects.append(hall)
	# corridors: the ring of the twelve outer rooms, one link left out (a longer way round; never cuts a room off)
	var ring := [Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0), Vector2i(3, 0), Vector2i(3, 1), Vector2i(3, 2), Vector2i(3, 3),
		Vector2i(2, 3), Vector2i(1, 3), Vector2i(0, 3), Vector2i(0, 2), Vector2i(0, 1)]
	var skip := w.rng.randi() % 12
	for k in 12:
		if k == skip:
			continue
		_corridor(w, rooms[ring[k]], rooms[ring[(k + 1) % 12]])
	# into the hall: one way in from each side, through the side's treasure room (a chokepoint each)
	for cell in rooms:
		if kinds[cell] == "treasure":
			var c: Vector2 = (rooms[cell] as Rect2).get_center()
			if cell.y == 0 or cell.y == 3:
				w.floor_rects.append(Rect2(c.x - 1.5, minf(c.y, 0.0), 3.0, absf(c.y)))      # straight down/up into the hall
			else:
				w.floor_rects.append(Rect2(minf(c.x, 0.0), c.y - 1.5, absf(c.x), 3.0))      # straight across
	# the floors below (bg_floors.gd): the stairs down from the great hall, and from one crypt room off the ring
	var down := [Vector3(6.0, 0, -8.0)]
	var crypts := rooms.keys().filter(func(c) -> bool: return kinds[c] == "" or kinds[c] == "treasure")
	if not crypts.is_empty():
		var cr: Rect2 = rooms[crypts[w.rng.randi() % crypts.size()]]
		down.append(Vector3(cr.get_center().x + 3.0, 0, cr.get_center().y - 2.5))
	BgFloors.build(w, down)
	var bb: Rect2 = w.floor_rects[0]
	for r in w.floor_rects:
		bb = bb.merge(r)
	w.bounds = bb.grow(3.0)
	w.dirt_blobs = [[w.bounds.get_center(), 9999.0, 1.0]]
	w.dirt_lines = []
	# dressing, monsters, chests, portals
	var spawns := []
	var portals := []
	var foes := ["zombie", "skel_archer", "fallen_reaver", "fallen_skirmisher", "fallen_stalker"]
	var pack := 700
	for cell in rooms:
		var r: Rect2 = rooms[cell]
		var c := r.get_center()
		var kind: String = kinds[cell]
		for k in 2:
			var tx := lerpf(r.position.x + 2.0, r.end.x - 2.0, 0.25 + k * 0.5)
			w._wall_torch(Vector3(tx, 0, r.position.y + 0.15), false)
		w._candles(Vector3(r.position.x + 1.0, 0, c.y), true)
		# a warm fill over each room (the torches alone left the Ossuary too dark to read from the game camera)
		var fill := OmniLight3D.new()
		fill.light_color = Color(1.0, 0.72, 0.45)
		fill.light_energy = 0.75
		fill.omni_range = maxf(r.size.x, r.size.y) * 0.8
		fill.shadow_enabled = false
		fill.position = Vector3(c.x, 3.4, c.y)
		w.props_root.add_child(fill)
		for k in w.rng.randi_range(1, 3):
			w._bones(Vector3(w.rng.randf_range(r.position.x + 1, r.end.x - 1), 0, w.rng.randf_range(r.position.y + 1, r.end.y - 1)))
		match kind:
			"spawn":
				spawns.append(Vector3(c.x, 0, c.y))
			"portal":
				portals.append(Vector3(c.x, 0, c.y))
				w._candles(Vector3(r.end.x - 1.0, 0, c.y), true)
			"treasure":
				w._chest(Vector3(c.x + w.rng.randf_range(-2, 2), 0, c.y + w.rng.randf_range(-2, 2)))
				w.enemy_spawns.append({"kind": foes[w.rng.randi() % foes.size()], "pos": Vector3(c.x, 0, c.y), "count": w.rng.randi_range(1, 2),
					"champ": false, "pack": pack, "level": MON_LEVEL})
				pack += 1
			_:
				# a crypt room: sarcophagi, a monster or two, sometimes a chest
				for k in w.rng.randi_range(1, 2):
					var sp := Vector3(w.rng.randf_range(r.position.x + 2.5, r.end.x - 2.5), 0, w.rng.randf_range(r.position.y + 2, r.end.y - 2))
					if not w.is_near_obstacle(sp, 1.5):
						w._sarcophagus(sp, w.rng.randf_range(-15, 15) + (90.0 if w.rng.randf() < 0.5 else 0.0))
				if w.rng.randf() < 0.35:
					w._chest(Vector3(c.x + w.rng.randf_range(-3, 3), 0, r.position.y + 2.0))
				w.enemy_spawns.append({"kind": foes[w.rng.randi() % foes.size()], "pos": Vector3(c.x, 0, c.y), "count": w.rng.randi_range(1, 2),
					"champ": false, "pack": pack, "level": MON_LEVEL})
				pack += 1
	# the great hall: a ring of pillars, braziers, three chests and its champion with bowmen
	var hc := hall.get_center()
	for i in 12:
		var a := TAU * i / 12.0
		w._pillar(Vector3(hc.x + cos(a) * 11.5, 0, hc.y + sin(a) * 11.5), 4.5)
	for k in 3:
		var a2 := TAU * k / 3.0 + 0.4
		w._chest(Vector3(hc.x + cos(a2) * 4.5, 0, hc.y + sin(a2) * 4.5))
	for k in 4:
		w._wall_torch(Vector3(lerpf(hall.position.x + 4.0, hall.end.x - 4.0, k / 3.0), 0, hall.position.y + 0.15), k % 2 == 0)
	w._candles(Vector3(hc.x, 0, hc.y), true)
	for k in 3:
		var hl := OmniLight3D.new()
		hl.light_color = Color(1.0, 0.7, 0.42)
		hl.light_energy = 0.9
		hl.omni_range = 13.0
		hl.shadow_enabled = false
		hl.position = Vector3(hc.x + cos(TAU * k / 3.0) * 7.0, 3.6, hc.y + sin(TAU * k / 3.0) * 7.0)
		w.props_root.add_child(hl)
	w.enemy_spawns.append({"kind": "fallen_reaver", "pos": Vector3(hc.x, 0, hc.y), "count": 1, "champ": true, "pack": 690, "level": MON_LEVEL + 2})
	w.enemy_spawns.append({"kind": "skel_archer", "pos": Vector3(hc.x, 0, hc.y + 6.0), "count": 2, "champ": false, "pack": 690, "level": MON_LEVEL})
	w.crypt_shell(BgFloors.themes())
	# the antechamber gates and bells (after the walls, so the path grid never counts the gates: they rise later)
	var gates := []
	for cell in rooms:
		if kinds[cell] != "spawn":
			continue
		var r: Rect2 = rooms[cell]
		for f in w.floor_rects:
			var fr: Rect2 = f
			if fr == r or rooms.values().has(fr) or not fr.intersects(r) or r.encloses(fr):
				continue
			var horiz := fr.size.x > fr.size.y
			var door: Vector2
			var half: Vector2
			if horiz:
				door = Vector2(r.end.x if fr.end.x > r.end.x + 0.1 else r.position.x, fr.get_center().y)
				half = Vector2(0.3, fr.size.y * 0.5 + 0.2)
			else:
				door = Vector2(fr.get_center().x, r.end.y if fr.end.y > r.end.y + 0.1 else r.position.y)
				half = Vector2(fr.size.x * 0.5 + 0.2, 0.3)
			gates.append(_gate(w, door, half))
		var c := r.get_center()
		_bell(w, Vector3(c.x + 2.2, 0, c.y - 2.2))
	w.set_meta("bg_gates", gates)
	for p in portals:
		var it: Inter = w._inter("extract", "Extraction Portal", p, 1.8, Fx.portal_model(), {"open": false})
		var m := it.get_node_or_null("Model")
		if m:
			m.visible = false
	w.spawns["start"] = spawns[0] if not spawns.is_empty() else Vector3.ZERO
	w.set_meta("bg_spawns", spawns)

## An antechamber's iron gate across a doorway (closed: a footprint; Battlegrounds.open_gates lifts it).
static func _gate(w: World, door: Vector2, half: Vector2) -> Dictionary:
	var g := Node3D.new()
	g.name = "gate"
	var iron := Props.iron()
	var across := half.x > half.y
	var width := (half.x if across else half.y) * 2.0
	var n := int(width / 0.28)
	for i in n + 1:
		var o := -width * 0.5 + width * float(i) / float(n)
		Models.P(g, Geo.box(0.07, 3.0, 0.07), iron, Vector3(o, 1.5, 0) if across else Vector3(0, 1.5, o))
	for hgt in [0.5, 1.7, 2.9]:
		Models.P(g, Geo.box(width, 0.08, 0.1) if across else Geo.box(0.1, 0.08, width), iron, Vector3(0, hgt, 0))
	w._place(g, Vector3(door.x, 0, door.y))
	w.add_box(Vector3(door.x, 0, door.y), half, 0.0)
	return {"node": g, "box": w.obstacles.size() - 1, "at": door, "up": false}

## The antechamber's bell: ring it to start the raid's countdown (Game._interact "bell").
static func _bell(w: World, p: Vector3) -> void:
	var g := Node3D.new()
	g.name = "bell"
	var wood := Props.wood_dark()
	var brass := Mats.mat(Color(0.75, 0.55, 0.25), 0.35, 0.9)
	for sx in [-0.55, 0.55]:
		Models.P(g, Geo.box(0.14, 2.3, 0.14), wood, Vector3(sx, 1.15, 0))
	Models.P(g, Geo.box(1.3, 0.16, 0.18), wood, Vector3(0, 2.3, 0))
	Models.P(g, Geo.cyl(0.18, 0.36, 0.5, 14), brass, Vector3(0, 1.95, 0))
	Models.P(g, Geo.sph(0.07, 8), brass, Vector3(0, 1.62, 0))
	var it: Inter = w._inter("bell", "Ring the bell (start the raid)", p, 1.6, g, {})
	Props.footprint(it, 0.5)
	w.solid(it)

## The gates up (the round's "raid" began): the bars rise, the footprints go (moved far off; World's can't be removed).
static func open_gates(w: World, animate := true) -> void:
	if w == null or not w.has_meta("bg_gates"):
		return
	for gt in w.get_meta("bg_gates"):
		if gt["up"]:
			continue
		gt["up"] = true
		(w.obstacles[gt["box"]] as Array)[0] = (gt["at"] as Vector2) + Vector2(0, 5000)
		var node: Node3D = gt["node"]
		if not is_instance_valid(node):
			continue
		if animate and node.is_inside_tree():
			node.create_tween().tween_property(node, "position:y", 3.1, 1.6).set_trans(Tween.TRANS_SINE)
		else:
			node.position.y = 3.1

## A corridor 3 m wide from room a to room b: straight when they line up, else an L.
static func _corridor(w: World, a: Rect2, b: Rect2) -> void:
	var ca := a.get_center()
	var cb := b.get_center()
	var hw := 1.5
	if absf(ca.y - cb.y) < 1.0:
		w.floor_rects.append(Rect2(minf(ca.x, cb.x), ca.y - hw, absf(cb.x - ca.x), hw * 2.0))
	elif absf(ca.x - cb.x) < 1.0:
		w.floor_rects.append(Rect2(ca.x - hw, minf(ca.y, cb.y), hw * 2.0, absf(cb.y - ca.y)))
	else:
		w.floor_rects.append(Rect2(minf(ca.x, cb.x) - hw, ca.y - hw, absf(cb.x - ca.x) + hw * 2.0, hw * 2.0))
		w.floor_rects.append(Rect2(cb.x - hw, minf(ca.y, cb.y) - hw, hw * 2.0, absf(cb.y - ca.y) + hw * 2.0))

static func portal_list(w: World) -> Array:
	return w.interactables.filter(func(t) -> bool: return is_instance_valid(t) and t.kind == "extract")

# ---------------------------------------------------------------- server
## Game._ready with `-- --server [--port N]`: the dedicated server. No title, no player of its own.
static func start_server(g: Node, port: int) -> void:
	var args := OS.get_cmdline_user_args()
	fast = args.has("--raid-fast")
	var bg := Battlegrounds.new()
	var ri := args.find("--raid")
	if ri >= 0 and ri + 1 < args.size():
		bg.raid_idx = clampi(int(args[ri + 1]), 0, RAIDS - 1)
		if not args.has("--port"):
			port = RAID_PORTS[bg.raid_idx]
	bg.name = "Battlegrounds"
	bg.game = g
	g.add_child(bg)
	g.bg = bg
	var nurl := OS.get_environment("ASHEN_NAKAMA_URL")
	bg.nk_key = OS.get_environment("ASHEN_NAKAMA_HTTP_KEY")
	if nurl != "" and bg.nk_key != "":
		bg.nk = NakamaClient.new(nurl, "-")
		bg.add_child(bg.nk)
	g.net.server = true
	Engine.max_fps = 60             # headless, the loop would otherwise spin a whole core
	g.ui.hide_title()
	g.playing = true
	g.difficulty = 0
	g.test_immortal = true
	bg.park_hero()
	# hosting first, so the zone's monsters are registered with the network as they spawn
	var err: int = g.net.host(port, MAX_PLAYERS)
	await bg.new_round()
	if bg.aligned():
		print("[BG] raid %s on the clock: %d s into its period" % [RAID_NAMES[bg.raid_idx], int(bg.raid_t)])
	print("[BG] accounts through ", "Nakama at " + nurl if bg.nk != null else "the per-PC id (no Nakama)")
	print("[BG] server ", "up on UDP port %d" % port if err == OK else "FAILED to open port %d (error %d)" % [port, err])
	# a new deploy waits for a quiet moment: nobody in, or between rounds (the crypt has just collapsed)
	ServerUpdate.watch(g, "[BG]", func() -> bool: return g.net.players.is_empty() or bg.state == "reset")

## How long the antechamber waits for a bell (tests' fast rounds keep a lobby long enough for a client to join).
static func lobby_max() -> float:
	return 40.0 if fast else LOBBY_MAX

## A raid of several (`--raid N`, real time): its rounds follow the clock.
func aligned() -> bool:
	return raid_idx >= 0 and not fast

func new_round() -> void:
	state = "lobby"
	raid_t = 0.0
	prep_left = 0.0
	if aligned():
		var ph := phase(raid_idx, Time.get_unix_time_from_system())
		if ph >= RAID_SECS:
			# (started in its reset: wait it out, then the round begins on time)
			state = "reset"
			reset_t = PERIOD - ph
		else:
			raid_t = ph
			if ph > LOBBY_MAX + PREP_SECS:
				state = "raid"         # (a server restarted mid-round: the crypt is already open)
	open = []
	carried.clear()
	died_items.clear()
	dead_wait.clear()
	last_hit.clear()
	await game.load_zone(0, ZONE, "start")
	for e in game.world.enemies_root.get_children():
		if e is Enemy:
			e.max_life *= MON_LIFE
			e.life = e.max_life
			e.dmg = [int(round(e.dmg[0] * MON_DMG)), int(round(e.dmg[1] * MON_DMG))]
	park_hero()
	if state == "raid":
		open_gates(game.world, false)
	broadcast()
	print("[BG] a new raid begins (%s)" % state)

## The server's own hero: hidden, off the map and phased, so monsters never see it (kept so every frame).
func park_hero() -> void:
	var b: Rect2 = game.world.bounds if game.world != null else Rect2(-60, -60, 120, 120)
	game.hero.global_position = Vector3(b.position.x - 60.0, 0, b.position.y - 60.0)
	game.hero.visible = false
	game.hero.phased = true

## A spot for a player arriving: the corner room farthest from everyone already in.
func spawn_point() -> Vector3:
	var pts: Array = game.world.get_meta("bg_spawns", [Vector3.ZERO])
	var best: Vector3 = pts[randi() % pts.size()]
	var bd := -1.0
	for p in pts:
		var d := 1e6
		for h in game.net.puppets():
			d = minf(d, (h.global_position - p).length())
		d += randf() * 4.0
		if d > bd:
			bd = d
			best = p
	return game.world.free_spot_near(best, 2.0)

## What every player needs to know about the round: state, seconds into it, the open portals.
func broadcast(pid := 0) -> void:
	var st := state
	if state == "lobby":
		st = "lobby:%.1f" % maxf(0.0, lobby_max() - raid_t)
	elif state == "prep":
		st = "prep:%.1f" % prep_left
	var args := [st, raid_t, open, secs(RAID_SECS), secs(PORTALS_AT)]
	if pid > 0:
		game.net.rpc_id(pid, "cl_bg_raid", args[0], args[1], args[2], args[3], args[4])
	elif not game.net.players.is_empty():
		game.net.rpc("cl_bg_raid", args[0], args[1], args[2], args[3], args[4])

func _process(delta: float) -> void:
	if game == null or not game.net.server or game.world == null or game._busy:
		return
	park_hero()
	if state == "reset":
		reset_t -= delta
		if reset_t <= 0.0:
			await new_round()
		return
	raid_t += delta
	_gear_t -= delta
	if _gear_t <= 0.0:
		_gear_t = GEAR_CHECK
		for pid in game.net.players.keys():
			if uids.has(pid) and not gear_ok(pid):
				print("[BG] %s wears admin gear without the admin role: turned away" % str(game.net.players[pid]["name"]))
				game.net.bg_refuse(pid, "boosted")
	_sync_t -= delta
	if _sync_t <= 0.0:
		_sync_t = 10.0 if state == "raid" else 2.0
		broadcast()
	if state == "lobby" and raid_t >= lobby_max():
		start_prep("")
	if state == "prep":
		prep_left -= delta
		if prep_left <= 0.0:
			state = "raid"
			open_gates(game.world)
			_announce("The gates are open. Good hunting.")
			broadcast()
		return
	if state == "raid" and open.is_empty() and raid_t >= secs(PORTALS_AT):
		# OPEN_PORTALS on the Ossuary, one on each floor below
		var pl := portal_list(game.world)
		var by_floor := {}
		for i in pl.size():
			var f := int(pl[i].data.get("floor", 1))
			if not by_floor.has(f):
				by_floor[f] = []
			by_floor[f].append(i)
		open = []
		for f in by_floor:
			var ids: Array = by_floor[f]
			ids.shuffle()
			open.append_array(ids.slice(0, OPEN_PORTALS if f == 1 else 1))
		_announce("The Extraction Portals are open")
		broadcast()
	if raid_t >= secs(RAID_SECS):
		_announce("The crypt collapses")
		for pid in game.net.players.keys():
			var h = game.net.players[pid]["hero"]
			if is_instance_valid(h) and not h.dead:
				game.net.hit_player(pid, 999999.0, h.global_position, "collapse", "phys")
		state = "reset"
		reset_t = secs(RESET_SECS)
		if aligned():
			reset_t = PERIOD - phase(raid_idx, Time.get_unix_time_from_system())
			if reset_t > PERIOD * 0.5:
				reset_t = 0.5        # (the clock is a hair behind the round: start the next one now)
		broadcast()
		return
	# a player who fell: their client sends what they had (sv_bg_died); if it never comes, what they picked up drops
	for pid in game.net.players.keys():
		var h = game.net.players[pid]["hero"]
		if not is_instance_valid(h):
			continue
		if h.dead and not died_items.has(pid):
			if not dead_wait.has(pid):
				dead_wait[pid] = 0.0
				var by: Array = last_hit.get(pid, [])
				var killer := ""
				if not by.is_empty() and raid_t - float(by[1]) < 10.0 and game.net.players.has(int(by[0])):
					killer = game.net.players[int(by[0])]["name"]
				_announce("%s fell%s" % [game.net.players[pid]["name"], (" to " + killer) if killer != "" else ""])
			dead_wait[pid] = float(dead_wait[pid]) + delta
			if float(dead_wait[pid]) > 5.0:
				died(pid, carried.get(pid, []), h.global_position)

## Someone rang an antechamber's bell (or the lobby ran out): the countdown to the gates, for everyone.
func start_prep(who: String) -> void:
	if state != "lobby":
		return
	state = "prep"
	prep_left = secs(PREP_SECS)
	_announce(("%s rang the bell: the gates open in %d seconds" % [who, int(PREP_SECS)]) if who != "" else "The gates open in %d seconds" % int(PREP_SECS))
	broadcast()

func _announce(txt: String) -> void:
	print("[BG] ", txt)
	if not game.net.players.is_empty():
		game.net.rpc("cl_bg_note", txt)

func player_hello(pid: int, uid: String, ticket := ""):
	carried[pid] = []
	if state == "reset" or raid_t > secs(JOIN_CLOSE):
		return "closed"
	if nk == null:
		uids[pid] = uid
		admins[pid] = _local_admin(uid)
		return "ok"
	# `ticket` is a one-time join ticket (bg_ticket), never the player's Nakama session: this connection isn't encrypted
	var t: Dictionary = await nk.server_rpc("bg_ticket_redeem", {"ticket": ticket}, nk_key) if ticket != "" else {}
	var user: String = str(t.get("user_id", ""))
	if user == "":
		print("[BG] a player's join ticket was refused ", nk.last_error)
		return "refused"
	uids[pid] = "nk:" + user
	var a: Dictionary = await nk.server_rpc("admin_check", {"user_id": user}, nk_key)
	admins[pid] = bool(a.get("admin", false))
	return "ok"

static func _local_admin(uid: String) -> bool:
	var f := FileAccess.open("user://bg_server/admins.json", FileAccess.READ)
	if f == null:
		return false
	var d = JSON.parse_string(f.get_as_text())
	return d is Array and (d as Array).has(uid)

## May this player wear what they wear? "Go to level 20" gear (marked "boost") is for admins only.
func gear_ok(pid: int) -> bool:
	if bool(admins.get(pid, false)) or not game.net.players.has(pid):
		return true
	var h = game.net.players[pid]["hero"]
	if not is_instance_valid(h):
		return true
	for slot in Items.EQUIP_SLOTS:
		var it = h.equipment.get(slot)
		if it is Dictionary and bool(it.get("boost", false)):
			return false
	return true

func picked(pid: int, it: Dictionary) -> void:
	if not carried.has(pid):
		carried[pid] = []
	(carried[pid] as Array).append(it)

## A player hit another: the attacker's client sends it, the server checks and deals it (scaled) to the target.
func pvp_hit(attacker: int, target: int, amount: float, from: Vector3) -> void:
	if state != "raid" or attacker == target or not game.net.players.has(attacker) or not game.net.players.has(target):
		return
	var a = game.net.players[attacker]["hero"]
	var t = game.net.players[target]["hero"]
	if not is_instance_valid(a) or not is_instance_valid(t) or a.dead or t.dead:
		return
	if a.global_position.distance_to(t.global_position) > 30.0:
		return
	last_hit[target] = [attacker, raid_t]
	game.net.hit_player(target, clampf(amount, 0.0, 5000.0) * PVP_MULT * Data.pvp_scale(a.cls, t.cls, a.level, t.level), from, "pvp", "phys")

## A player fell: everything they had lies where they fell.
func died(pid: int, items: Array, at: Vector3) -> void:
	if died_items.has(pid):
		return
	died_items[pid] = true
	var n := 0
	for it in items:
		if it is Dictionary and it.has("base"):
			game.drop_item(it, at)
			n += 1
	carried[pid] = []
	print("[BG] %s's body dropped %d item(s)" % [game.net.players[pid]["name"] if game.net.players.has(pid) else "someone", n])

## Leaving without extracting (quit, crash, lost connection): what they picked up stays behind.
func player_left(pid: int, at: Vector3) -> void:
	if not died_items.has(pid):
		for it in carried.get(pid, []):
			game.drop_item(it, at)
	carried.erase(pid)
	uids.erase(pid)
	died_items.erase(pid)
	dead_wait.erase(pid)

## Seconds until a new player can get in again: what is left of this round (if joining has closed) and the reset.
func secs_to_next() -> float:
	if state == "reset":
		return maxf(0.0, reset_t)
	return maxf(0.0, secs(RAID_SECS) - raid_t) + secs(RESET_SECS)

func near_open_extract(pid: int) -> bool:
	if not game.net.players.has(pid) or state != "raid":
		return false
	var h = game.net.players[pid]["hero"]
	if not is_instance_valid(h) or h.dead:
		return false
	var ps := portal_list(game.world)
	for i in open:
		if i < ps.size() and (ps[i].global_position - h.global_position).length() < EXTRACT_R:
			return true
	return false

## The player made it out with what they carry (it is in their own inventory already). Returns what they picked up.
func extract(pid: int) -> Array:
	var gained: Array = carried.get(pid, [])
	carried[pid] = []
	died_items[pid] = true          # (gone from the raid: nothing of theirs drops any more)
	return gained

# ---------------------------------------------------------------- client
## This PC's id: made once at random; without Nakama the server knows the player by it.
static func client_id() -> String:
	if FileAccess.file_exists(id_path):
		var s := FileAccess.get_file_as_string(id_path).strip_edges()
		if s.length() >= 16:
			return s
	var id := Crypto.new().generate_random_bytes(16).hex_encode()
	var f := FileAccess.open(id_path, FileAccess.WRITE)
	if f:
		f.store_string(id)
	return id

## "host" or "host:port" -> [host, port]
static func parse_address(txt: String) -> Array:
	txt = txt.strip_edges()
	var port := Net.PORT
	var i := txt.rfind(":")
	if i > 0 and txt.substr(i + 1).is_valid_int():
		port = int(txt.substr(i + 1))
		txt = txt.substr(0, i)
	return [txt if txt != "" else "127.0.0.1", port]

## Client: every other player is an invisible target the local hero's attacks can hit (PvP), kept on their puppet.
static func sync_proxies(g: Node) -> void:
	if g.world == null or g._busy:
		return
	var want := {}
	for pid in g.net.players:
		var h = g.net.players[pid]["hero"]
		if is_instance_valid(h) and h.net_has and not h.dead:
			want[pid] = h
	for e in g.world.enemies_root.get_children():
		if e is Enemy and e.pvp_pid > 0:
			if not want.has(e.pvp_pid):
				e.queue_free()
			else:
				var h = want[e.pvp_pid]
				e.global_position = h.global_position
				want.erase(e.pvp_pid)
	for pid in want:
		var e := Enemy.new()
		e.pvp_pid = int(pid)
		g.world.enemies_root.add_child(e)
		e.global_position = want[pid].global_position
		e.setup(g, "zombie", 1)
		e.display_name = str(g.net.players[pid]["name"])
		e.max_life = 1e9
		e.life = 1e9
		e.rig.visible = false

## Client: the raid's clock and portals, top of the screen.
static func hud(g: Node, delta: float) -> void:
	var r: Dictionary = g.bg_raid
	if r.is_empty():
		return
	r["t"] = float(r["t"]) + delta
	var lbl: Label = g.ui.hud.get_node_or_null("bg_hud")
	if lbl == null:
		lbl = Label.new()
		lbl.name = "bg_hud"
		lbl.set_anchors_preset(Control.PRESET_CENTER_TOP)
		lbl.offset_top = 52
		lbl.grow_horizontal = Control.GROW_DIRECTION_BOTH
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lbl.add_theme_font_size_override("font_size", 20)
		lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0))
		lbl.add_theme_constant_override("outline_size", 6)
		g.ui.hud.add_child(lbl)
	lbl.visible = g.bg_mode
	var left := maxf(0.0, float(r["len"]) - float(r["t"]))
	var st := str(r["state"])
	if st.begins_with("lobby") or st.begins_with("prep"):
		r["wait"] = maxf(0.0, float(r.get("wait", 0.0)) - delta)
		var w := int(ceilf(float(r["wait"])))
		if st.begins_with("lobby"):
			lbl.text = "THE ANTECHAMBER  ·  ring the bell to begin  ·  the gates open by themselves in %d:%02d" % [(w + int(PREP_SECS)) / 60, (w + int(PREP_SECS)) % 60]
			lbl.add_theme_color_override("font_color", Color(0.95, 0.85, 0.6))
		else:
			lbl.text = "THE GATES OPEN IN %d" % w
			lbl.add_theme_color_override("font_color", Color(1.0, 0.65, 0.3))
		return
	var txt := "%s  ·  %d:%02d" % [TITLE.to_upper(), int(left) / 60, int(left) % 60]
	if (r["open"] as Array).is_empty():
		var p := maxf(0.0, float(r["portals_at"]) - float(r["t"]))
		txt += "  ·  portals open in %d:%02d" % [int(p) / 60, int(p) % 60]
		lbl.add_theme_color_override("font_color", Color(0.85, 0.8, 0.7))
	else:
		txt += "  ·  PORTALS OPEN"
		lbl.add_theme_color_override("font_color", Color(0.55, 0.85, 1.0) if left > 60.0 else Color(1.0, 0.45, 0.35))
	lbl.text = txt
