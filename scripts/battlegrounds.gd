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

const ZONE := "bg"
const TITLE := "The Hollow Crypt"
const MAX_PLAYERS := 16
const RAID_SECS := 1200.0       # a round: 20 minutes
const PORTALS_AT := 300.0       # the Extraction Portals open 5 minutes in
const JOIN_CLOSE := 900.0       # nobody new joins in the last 5 minutes
const RESET_SECS := 20.0        # after the collapse, before the next round
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
var state := "raid"             # server: "raid" | "reset"
var reset_t := 0.0
var open: Array = []            # server: indices (in the portal list) of the open Extraction Portals
var carried := {}               # server: peer id -> Array of items picked up this raid (dropped if they vanish)
var died_items := {}            # server: peer id -> true once their death drop was handled
var dead_wait := {}             # server: peer id -> seconds since they fell, waiting for their death drop
var last_hit := {}              # server: peer id -> [attacker peer id, raid_t]
var uids := {}                  # server: peer id -> who they are (Nakama user, or the per-PC id)
var nk: NakamaClient            # server: Nakama, to confirm join tickets (staging, production)
var nk_key := ""
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
	w.enemy_spawns.append({"kind": "fallen_reaver", "pos": Vector3(hc.x, 0, hc.y), "count": 1, "champ": true, "pack": 690, "level": MON_LEVEL + 2})
	w.enemy_spawns.append({"kind": "skel_archer", "pos": Vector3(hc.x, 0, hc.y + 6.0), "count": 2, "champ": false, "pack": 690, "level": MON_LEVEL})
	w.crypt_shell()
	for p in portals:
		var it: Inter = w._inter("extract", "Extraction Portal", p, 1.8, Fx.portal_model(), {"open": false})
		var m := it.get_node_or_null("Model")
		if m:
			m.visible = false
	w.spawns["start"] = spawns[0] if not spawns.is_empty() else Vector3.ZERO
	w.set_meta("bg_spawns", spawns)

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

## A raid of several (`--raid N`, real time): its rounds follow the clock.
func aligned() -> bool:
	return raid_idx >= 0 and not fast

func new_round() -> void:
	state = "raid"
	raid_t = 0.0
	if aligned():
		var ph := phase(raid_idx, Time.get_unix_time_from_system())
		if ph >= RAID_SECS:
			# (started in its reset: wait it out, then the round begins on time)
			state = "reset"
			reset_t = PERIOD - ph
		else:
			raid_t = ph
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
	broadcast()
	print("[BG] a new raid begins")

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
	var args := [state, raid_t, open, secs(RAID_SECS), secs(PORTALS_AT)]
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
	_sync_t -= delta
	if _sync_t <= 0.0:
		_sync_t = 10.0
		broadcast()
	if open.is_empty() and raid_t >= secs(PORTALS_AT):
		var idx := range(portal_list(game.world).size())
		idx.shuffle()
		open = idx.slice(0, OPEN_PORTALS)
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

func _announce(txt: String) -> void:
	print("[BG] ", txt)
	if not game.net.players.is_empty():
		game.net.rpc("cl_bg_note", txt)

func player_hello(pid: int, uid: String, ticket := ""):
	carried[pid] = []
	if state != "raid" or raid_t > secs(JOIN_CLOSE):
		return "closed"
	if nk == null:
		uids[pid] = uid
		return "ok"
	# `ticket` is a one-time join ticket (bg_ticket), never the player's Nakama session: this connection isn't encrypted
	var t: Dictionary = await nk.server_rpc("bg_ticket_redeem", {"ticket": ticket}, nk_key) if ticket != "" else {}
	var user: String = str(t.get("user_id", ""))
	if user == "":
		print("[BG] a player's join ticket was refused ", nk.last_error)
		return "refused"
	uids[pid] = "nk:" + user
	return "ok"

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
	game.net.hit_player(target, clampf(amount, 0.0, 5000.0) * PVP_MULT, from, "pvp", "phys")

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
	var txt := "%s  ·  %d:%02d" % [TITLE.to_upper(), int(left) / 60, int(left) % 60]
	if (r["open"] as Array).is_empty():
		var p := maxf(0.0, float(r["portals_at"]) - float(r["t"]))
		txt += "  ·  portals open in %d:%02d" % [int(p) / 60, int(p) % 60]
		lbl.add_theme_color_override("font_color", Color(0.85, 0.8, 0.7))
	else:
		txt += "  ·  PORTALS OPEN"
		lbl.add_theme_color_override("font_color", Color(0.55, 0.85, 1.0) if left > 60.0 else Color(1.0, 0.45, 0.35))
	lbl.text = txt
