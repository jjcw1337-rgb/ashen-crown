class_name Battlegrounds
extends Node
## Battlegrounds: the raid in the Verdant Reach (BgForest), a PvPvE forest of monster camps, run on a match server
## the lobby service starts (match_instance.gd; Net.server, host-authoritative monsters and loot).
##
## A round: players arrive at the forest's edges (spawn_point) as run characters (RunBuild: level 0, a basic attack),
## clear camps (Camps) for skills, rites, gear and gems, and the Extraction Portals (OPEN_PORTALS of the candidates)
## open PORTALS_AT in; reach one to keep your hero as a survivor (extract). At RAID_SECS the raid is over and whoever
## is still in the forest dies. States reach players in Net.cl_bg_raid ("lobby:<secs left>", "raid", "reset").
##
## Attacks, skills, damage and cooldowns are the same as everywhere else; the raid only slows walking (MOVE_MULT) and
## stops life regeneration (client side, Hero, while Game.bg_mode). PvP is on: every other player is an invisible
## stand-in target on each client (sync_proxies: an Enemy with `pvp_pid`, following that player's puppet), so every
## skill, swing, arrow and burn that can hit a monster can hit a player; its take_damage sends Net.sv_pvp_hit, the
## server scales it (PVP_MULT) and deals it to that player. A death drops what they carried where they fell
## (Net.sv_bg_died).
## Tests: tools/bg_test.gd (server + client), tools/bg_pvp_test.gd (server + two players); `--raid-fast` runs the round
## eight times faster.

const ZONE := "bg"
const MAX_PLAYERS := 16
const RAID_SECS := 1200.0       # a round: 20 minutes
const PORTALS_AT := 300.0       # the Extraction Portals open 5 minutes in
const JOIN_CLOSE := 900.0       # nobody new joins in the last 5 minutes
const RESET_SECS := 20.0        # after the collapse, before the next round
const LOBBY_MAX := 75.0         # the lobby: at most this long before the raid starts by itself
const ADMIN_RESTART := 3.0      # an admin's "restart": seconds until the new round
const PREP_SECS := 20.0         # (a "prep" countdown with the matchup shown: start_prep goes straight to the raid today)
const EXTRACT_R := 4.0          # how close to an open portal the server accepts an extraction
const OPEN_PORTALS := 2         # of the four candidate portals
const PVP_MULT := 0.6           # a player's damage to another player
const PVP_RANGE := 30.0         # the server drops a player-on-player blow, burn or control from further away
const PVP_EFFECT_GAP := 0.8     # the same crowd control from one player on one other, at most this often (s)
const PVP_BURN_CAP := 140.0     # a burn's damage a second, before PVP_MULT
const MOVE_MULT := 0.85         # walking and running

static func map_title() -> String:
	return BgForest.TITLE
const ID_PATH := "user://bg_id.txt"
static var id_path := ID_PATH   # tests point it elsewhere
static var fast := false        # tests: `--raid-fast` = rounds in seconds

var game: Node
var raid_t := 0.0               # server: seconds into the round
var prep_left := 0.0            # server: seconds of the prep countdown left
var state := "lobby"            # server: "lobby" | "prep" | "raid" | "reset"
var reset_t := 0.0
var forced := false             # server: an admin restarted the round (until it ends)
var open: Array = []            # server: indices (in the portal list) of the open Extraction Portals
var carried := {}               # server: peer id -> Array of items picked up this raid (dropped if they vanish)
var died_items := {}            # server: peer id -> true once their death drop was handled
var dead_wait := {}             # server: peer id -> seconds since they fell, waiting for their death drop
var last_hit := {}              # server: peer id -> [attacker peer id, raid_t]
var pvp_effect_t := {}          # server: "attacker:target:kind" -> raid_t of the last control let through
var cc_dr := {}                 # server: peer id -> PvpStatus.diminish's window (crowd control's diminishing returns)
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

## A dedicated server's frame rate: 30 like the lobby's match workers (60 was about twice the CPU for nothing a
## player sees: physics still ticks at 60), or `-- --tick N`.
static func server_tick() -> int:
	var a := OS.get_cmdline_user_args()
	return int(a[a.find("--tick") + 1]) if a.has("--tick") else 30

static func secs(n: float) -> float:
	return n / 8.0 if fast else n       # (tests: a 150 s round, portals at 37.5 s, joining closes at 112.5 s)

# ---------------------------------------------------------------- the map
## The Hollow Crypt. Cell (i, j) of a 4x4 grid; the middle 2x2 is the great hall.
## The raid's map: the Verdant Reach (BgForest).
static func build(w: World) -> void:
	BgForest.build(w)

static func portal_list(w: World) -> Array:
	return w.interactables.filter(func(t) -> bool: return is_instance_valid(t) and t.kind == "extract")

# ---------------------------------------------------------------- server
## Game._ready with `-- --server [--port N]`: the dedicated server. No title, no player of its own.
static func start_server(g: Node, port: int) -> void:
	var args := OS.get_cmdline_user_args()
	fast = args.has("--raid-fast")
	var bg := Battlegrounds.new()
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
	Engine.max_fps = Battlegrounds.server_tick()     # headless, the loop would otherwise spin a whole core
	g.ui.hide_title()
	g.playing = true
	g.difficulty = 0
	g.test_immortal = true
	bg.park_hero()
	# hosting first, so the zone's monsters are registered with the network as they spawn
	var err: int = g.net.host(port, MAX_PLAYERS)
	await bg.new_round()
	print("[BG] accounts through ", "Nakama at " + nurl if bg.nk != null else "the per-PC id (no Nakama)")
	print("[BG] server ", "up on UDP port %d" % port if err == OK else "FAILED to open port %d (error %d)" % [port, err])

## How long the antechamber waits for a bell (tests' fast rounds keep a lobby long enough for a client to join).
static func lobby_max() -> float:
	return 40.0 if fast else LOBBY_MAX

func new_round() -> void:
	state = "lobby"
	raid_t = 0.0
	prep_left = 0.0
	open = []
	carried.clear()
	cc_dr.clear()
	died_items.clear()
	dead_wait.clear()
	last_hit.clear()
	pvp_obj_last.clear()
	pvp_effect_t.clear()
	await game.load_zone(0, ZONE, "start")
	park_hero()
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
	if game.match_instance != null and not game.match_instance.begun:
		return
	if state == "reset":
		if game.match_instance != null: return
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
		if state == "lobby" or state == "prep":
			send_roster()
	if game.match_instance == null and state == "lobby" and (raid_t >= lobby_max() or game.net.players.size() >= 1):
		start_prep("")
	if state == "prep":
		prep_left -= delta
		if prep_left <= 0.0:
			state = "raid"
			broadcast()
		return
	if state == "raid" and open.is_empty() and raid_t >= secs(PORTALS_AT):
		open_portals()
	if raid_t >= secs(RAID_SECS):
		_announce("The raid is over")
		collapse()
		forced = false
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

## The Extraction Portals open: OPEN_PORTALS of the forest's candidates, picked at random.
func open_portals() -> void:
	var ids: Array = range(portal_list(game.world).size())
	ids.shuffle()
	open = ids.slice(0, OPEN_PORTALS)
	_announce("The Extraction Portals are open")
	broadcast()

## The raid is over: whoever is still in the forest dies, and the reset begins.
func collapse() -> void:
	for pid in game.net.players.keys():
		var h = game.net.players[pid]["hero"]
		if is_instance_valid(h) and not h.dead:
			game.net.hit_player(pid, 999999.0, h.global_position, "collapse", "phys")
	state = "reset"
	reset_t = secs(RESET_SECS)

## An admin's raid controls (Escape → Admin in a raid, Net.sv_bg_admin; refused for anyone without the admin role),
## for testing without waiting on the clock:
##   "restart"  the raid ends now and a new round begins in ADMIN_RESTART s
##   "gates"    the wait and countdown skipped: the raid starts now
##   "portals"  the Extraction Portals open now
func admin_cmd(pid: int, cmd: String) -> void:
	if not bool(admins.get(pid, false)) or not game.net.players.has(pid):
		return
	var who := str(game.net.players[pid]["name"])
	match cmd:
		"restart":
			if state == "reset":
				return
			_announce("%s restarted the round" % who)
			collapse()
			forced = true
			reset_t = ADMIN_RESTART
			broadcast()
		"gates":
			if state == "lobby" or state == "prep":
				state = "raid"
				_announce("%s started the raid" % who)
				broadcast()
		"portals":
			if state == "raid" and open.is_empty():
				open_portals()

## The matchup (jj: "you see the classes that you're going against"): every raider's class and level, never a
## name, to everyone in the antechamber (Net.cl_bg_roster; the client leaves itself out, BgMatchup shows the rest).
func roster() -> Array:
	var out := []
	for pid in game.net.players.keys():
		var h = game.net.players[pid]["hero"]
		if is_instance_valid(h) and h.net_has:
			out.append({"pid": int(pid), "cls": str(h.cls), "lvl": int(h.level)})
	return out

func send_roster() -> void:
	if not game.net.players.is_empty():
		game.net.rpc("cl_bg_roster", roster())

## The lobby is over (everyone's in, or it ran out): the raid begins.
func start_prep(who: String) -> void:
	if state != "lobby":
		return
	state = "raid"
	prep_left = 0.0
	print("[BG] the raid begins", (" (%s)" % who) if who != "" else "")
	broadcast()

func _announce(txt: String) -> void:
	print("[BG] ", txt)
	if not game.net.players.is_empty():
		game.net.rpc("cl_bg_note", txt)

func player_hello(pid: int, uid: String, ticket := ""):
	carried[pid] = []
	if state == "reset":
		return "closed"
	if nk == null:
		uids[pid] = uid
		admins[pid] = _local_admin(uid)
		return "closed" if raid_t > secs(JOIN_CLOSE) and not admins[pid] else "ok"
	# `ticket` is a one-time join ticket (bg_ticket), never the player's Nakama session: this connection isn't encrypted
	var t: Dictionary = await nk.server_rpc("bg_ticket_redeem", {"ticket": ticket}, nk_key) if ticket != "" else {}
	var user: String = str(t.get("user_id", ""))
	if user == "":
		print("[BG] a player's join ticket was refused ", nk.last_error)
		return "refused"
	uids[pid] = "nk:" + user
	var a: Dictionary = await nk.server_rpc("admin_check", {"user_id": user}, nk_key)
	admins[pid] = bool(a.get("admin", false))
	# joining closes late in a round, but not for an admin (testing)
	return "closed" if raid_t > secs(JOIN_CLOSE) and not admins[pid] else "ok"

static func _local_admin(uid: String) -> bool:
	var f := FileAccess.open("user://bg_server/admins.json", FileAccess.READ)
	if f == null:
		return false
	var d = JSON.parse_string(f.get_as_text())
	return d is Array and (d as Array).has(uid)

## May this player raid as they are? A character "Go to level 20" made (Hero.boosted, sent with its gear) and its
## gear (marked "boost") are for admins only.
func gear_ok(pid: int) -> bool:
	if bool(admins.get(pid, false)) or not game.net.players.has(pid):
		return true
	var h = game.net.players[pid]["hero"]
	if not is_instance_valid(h):
		return true
	if h.boosted:
		return false          # a character "Go to level 20" made, whatever it wears now
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
## The checks every player-on-player message passes on the server (pvp_hit, Net.sv_pvp_effect, Net.sv_pvp_dot): a raid
## on, two different players, both alive, within PVP_RANGE of each other. [attacker's hero, target's hero], or [].
func pvp_pair(attacker: int, target: int) -> Array:
	if state != "raid" or attacker == target or not game.net.players.has(attacker) or not game.net.players.has(target):
		return []
	var a = game.net.players[attacker]["hero"]
	var t = game.net.players[target]["hero"]
	if not is_instance_valid(a) or not is_instance_valid(t) or a.dead or t.dead:
		return []
	if a.global_position.distance_to(t.global_position) > PVP_RANGE:
		return []
	return [a, t]

func pvp_hit(attacker: int, target: int, amount: float, from: Vector3) -> void:
	var pr := pvp_pair(attacker, target)
	if pr.is_empty():
		return
	var a: Hero = pr[0]
	var t: Hero = pr[1]
	last_hit[target] = [attacker, raid_t]
	game.net.hit_player(target, clampf(amount, 0.0, 5000.0) * PVP_MULT * Data.pvp_scale(a.cls, t.cls, a.level, t.level), from, "pvp", "phys")

## A player struck something another player made (PvpObjects: a Corpse Bloom, a vat, a creature): checked like a hit
## (both in the raid, the attacker alive and within reach of it where the server's own ghost of the owner has it), then
## counted by the owner's game.
var pvp_obj_last := {}           # server: "attacker:owner:id" -> when his last blow on it counted (PvpObjects.allow)
func pvp_obj_hit(attacker: int, owner_pid: int, oid: int, _from: Vector3) -> void:
	if state != "raid" or attacker == owner_pid or not game.net.players.has(attacker) or not game.net.players.has(owner_pid):
		return
	var a = game.net.players[attacker]["hero"]
	var o = game.net.players[owner_pid]["hero"]
	if not is_instance_valid(a) or not is_instance_valid(o) or a.dead:
		return
	var at = PvpObjects.where(o, oid)
	if not (at is Vector3) or a.global_position.distance_to(at) > PvpObjects.REACH:
		return
	if not PvpObjects.allow(pvp_obj_last, attacker, owner_pid, oid, Time.get_ticks_msec() / 1000.0):
		return
	game.net.obj_hit_player(owner_pid, oid, attacker)

## Crowd control on another player (Net.PVP_EFFECTS): the same kind from one player on one other at most every
## PVP_EFFECT_GAP seconds, so a client sending them in a stream can't keep someone stunned.
func pvp_effect(attacker: int, target: int, kind: String, from: Vector3) -> void:
	if pvp_pair(attacker, target).is_empty():
		return
	var key := "%d:%d:%s" % [attacker, target, kind]
	if pvp_effect_t.has(key) and raid_t - float(pvp_effect_t[key]) < PVP_EFFECT_GAP:
		return
	pvp_effect_t[key] = raid_t
	last_hit[target] = [attacker, raid_t]
	game.net.hit_player(target, 0.0, from, kind, "phys")

## Burning another player (a Fire Arrow, magma, a unique's burn): `dps` as the attacker dealt it, capped, then
## scaled like any PvP blow (PVP_MULT and the class pairing); the kill counts for the one who set it.
func pvp_burn(attacker: int, target: int, dps: float, from: Vector3) -> void:
	var pr := pvp_pair(attacker, target)
	if pr.is_empty():
		return
	var a: Hero = pr[0]
	var t: Hero = pr[1]
	last_hit[target] = [attacker, raid_t]
	game.net.hit_player(target, clampf(dps, 0.0, PVP_BURN_CAP) * PVP_MULT * Data.pvp_scale(a.cls, t.cls, a.level, t.level), from, "burn", "fire")

## Server: a player's skill put a status on another (PvpStatus): the same checks as damage, then the diminishing
## returns on hard crowd control, then to the victim alone.
func pvp_status(attacker: int, target: int, kind: String, secs: float, data: Dictionary) -> void:
	var pr := pvp_pair(attacker, target)
	if pr.is_empty():
		return
	secs = PvpStatus.clamp_status(kind, secs, data)    # (the Plague Doctor's kinds: their ceilings)
	var a: Hero = pr[0]
	var t: Hero = pr[1]
	if kind == "pull":
		# dragged no further than to the attacker's reach
		var to: Vector3 = (t.global_position - a.global_position) * Vector3(1, 0, 1)
		data = {"p": a.global_position + (to.normalized() if to.length() > 0.1 else Vector3.FORWARD) * 1.5,
			"m": clampf(float(data.get("m", secs)), 0.1, secs)}
	elif kind == "fear":
		data = {"p": a.global_position}
	elif kind == "burn":
		# (scaled like a hit: PVP_MULT and the class against class balance, Data.pvp_scale)
		data = {"dps": clampf(float(data.get("dps", 0.0)), 0.0, 400.0) * PVP_MULT * Data.pvp_scale(a.cls, t.cls, a.level, t.level)}
	var s := PvpStatus.diminish(cc_dr, target, kind, secs, raid_t)
	if s <= 0.0:
		return
	last_hit[target] = [attacker, raid_t]
	game.net.rpc_id(target, "cl_pvp_status", kind, s, data)

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
			if g.arena_mode and g.arena_state.get("teams", {}).get(str(pid), -1) == g.arena_state.get("teams", {}).get(str(g.net.multiplayer.get_unique_id()), -2): continue
			want[pid] = h
	PvpObjects.prune(g, want)
	for e in g.world.enemies_root.get_children():
		if e is Enemy and e.pvp_pid > 0:
			if not want.has(e.pvp_pid):
				e.queue_free()
			else:
				var h = want[e.pvp_pid]
				e.global_position = h.global_position
				e.pvp_hidden = bool(h.fog_hidden)
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
	# the matchup under the clock while the gates are down and the countdown runs (BgMatchup)
	var mu: BgMatchup = g.ui.hud.get_node_or_null("bg_matchup")
	if mu == null:
		mu = BgMatchup.new(g.ui)
		g.ui.hud.add_child(mu)
	mu.visible = g.bg_mode and st.begins_with("prep") and not g.bg_roster.is_empty()
	if mu.visible:
		mu.set_roster(g.bg_roster, g.multiplayer.get_unique_id())
	if st.begins_with("lobby") or st.begins_with("prep"):
		r["wait"] = maxf(0.0, float(r.get("wait", 0.0)) - delta)
		var w := int(ceilf(float(r["wait"])))
		if st.begins_with("lobby"):
			lbl.text = "%s  ·  waiting for the other players" % map_title().to_upper()
			lbl.add_theme_color_override("font_color", Color(0.95, 0.85, 0.6))
		else:
			lbl.text = "RAID STARTS IN %d  ·  clear camps for skills and gear" % w
			lbl.add_theme_color_override("font_color", Color(1.0, 0.65, 0.3))
		return
	var txt := "%s  ·  %s in %d:%02d" % [map_title().to_upper(), "raid ends", int(left) / 60, int(left) % 60]
	if (r["open"] as Array).is_empty():
		var p := maxf(0.0, float(r["portals_at"]) - float(r["t"]))
		txt += "\nPortals open in %d:%02d" % [int(p) / 60, int(p) % 60]
		lbl.add_theme_color_override("font_color", Color(0.85, 0.8, 0.7))
	else:
		txt += "\nPORTALS OPEN  ·  reach an open portal before time runs out"
		lbl.add_theme_color_override("font_color", Color(0.55, 0.85, 1.0) if left > 60.0 else Color(1.0, 0.45, 0.35))
	lbl.text = txt
