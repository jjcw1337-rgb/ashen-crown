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
## The raid maps: the Hollow Crypt (underground) and Peak Ruins (bg_peak.gd: a summit above the clouds, jj's). The
## lobby's host picks one (the match manifest's "map"); `--bg-map <id>` on a server or a client sets it for tests.
const MAPS := {"crypt": "The Hollow Crypt", "peak": "Peak Ruins"}
static var map_id := "crypt"

static func map_title() -> String:
	return str(MAPS.get(map_id, TITLE))

## Peak Ruins is under the sky (Game.indoor, _zone_env).
static func outdoor() -> bool:
	return map_id == "peak"
const MAX_PLAYERS := 16
const RAID_SECS := 1200.0       # a round: 20 minutes
const PORTALS_AT := 300.0       # the Extraction Portals open 5 minutes in
const JOIN_CLOSE := 900.0       # nobody new joins in the last 5 minutes
const RESET_SECS := 20.0        # after the collapse, before the next round
const LOBBY_MAX := 75.0         # the antechamber: at most this long before the prep countdown starts by itself
const ADMIN_RESTART := 3.0      # an admin's "restart": seconds until the new round
const PREP_SECS := 20.0         # the countdown to the gates opening: the matchup shown, the antechamber's stash open
const STASH_SLOW := 0.15        # (jj) opening the antechamber's stash: the opener alone is this much slower for the
                                # whole raid (Hero.stash_slowed, cleared when the raid ends for them)
const STASH_LOOP_DB := -4.0     # the open raid chest's fire loop at first (it sinks to 20% over 10 s)
const STASH_CHEST_HALF := Vector2(0.82, 0.64)   # the crypt chest's footprint (half-extents)
## The raid chest's fire (jj): "ember", chest #1's red fire; "spirit", #2, the same chest burning blue (the camp
## waypoint's spirit-fire); "void", #3, purple (both InfernalFx.recolor, palette "pal"). Every light, flash, spark and flame of the chest, its dais and its
## opening takes its colour from here (Inter meta "stash_theme"; `stash_col`).
const STASH_THEMES := {
	"ember": {"lid": Color(1.0, 0.5, 0.2), "spark": Color(0.95, 0.42, 0.08, 1.0), "flash": Color(1.0, 0.42, 0.1),
		"jet": [Color(1.0, 0.72, 0.3, 1.0), Color(0.95, 0.38, 0.06, 0.9), Color(0.35, 0.06, 0.02, 0.0)],
		"ring": Color(0.7, 0.2, 0.03), "burst": Color(0.9, 0.3, 0.04, 1.0), "fire": "brazier", "fire_col": Color(1.0, 0.5, 0.18), "pal": "",
		"seal": Color(1.0, 0.62, 0.18), "seal_light": Color(1.0, 0.68, 0.25), "seal_flash": Color(1.0, 0.62, 0.2),
		"seal_spark": Color(1.0, 0.75, 0.3, 1.0), "seal_trail": Color(0.95, 0.55, 0.12)},
	"spirit": {"lid": Color(0.4, 0.62, 1.0), "spark": Color(0.45, 0.7, 1.0, 1.0), "flash": Color(0.3, 0.55, 1.0),
		"jet": [Color(0.7, 0.9, 1.0, 1.0), Color(0.25, 0.55, 1.0, 0.9), Color(0.04, 0.1, 0.4, 0.0)],
		"ring": Color(0.08, 0.3, 0.95), "burst": Color(0.25, 0.5, 1.0, 1.0), "fire": "spirit", "fire_col": Color(0.4, 0.66, 1.0), "pal": "spirit",
		"seal": Color(0.35, 0.65, 1.0), "seal_light": Color(0.45, 0.68, 1.0), "seal_flash": Color(0.4, 0.66, 1.0),
		"seal_spark": Color(0.6, 0.82, 1.0, 1.0), "seal_trail": Color(0.3, 0.55, 1.0), "coals": Color(0.25, 0.55, 1.0)},
	"void": {"lid": Color(0.72, 0.38, 1.0), "spark": Color(0.78, 0.5, 1.0, 1.0), "flash": Color(0.62, 0.3, 1.0),
		"jet": [Color(0.9, 0.75, 1.0, 1.0), Color(0.6, 0.28, 1.0, 0.9), Color(0.16, 0.03, 0.35, 0.0)],
		"ring": Color(0.5, 0.12, 0.95), "burst": Color(0.62, 0.3, 1.0, 1.0), "fire": "spirit", "fire_col": Color(0.7, 0.4, 1.0), "pal": "void",
		"seal": Color(0.68, 0.36, 1.0), "seal_light": Color(0.72, 0.45, 1.0), "seal_flash": Color(0.7, 0.42, 1.0),
		"seal_spark": Color(0.85, 0.68, 1.0, 1.0), "seal_trail": Color(0.6, 0.3, 1.0), "coals": Color(0.62, 0.3, 1.0)},
}
const RAID_MIN := 2             # (jj) this many raiders in the antechamber start the countdown by themselves
const RAIDS := 3                # raids run side by side, staggered on the clock (phase)
const RAID_PORTS := [24567, 24571, 24572]
const LIVE_RAIDS := 1           # deployed so far (staging: one until its servers and firewall ports are up)
const PERIOD := RAID_SECS + RESET_SECS
const RAID_NAMES := ["I", "II", "III"]
const EXTRACT_R := 4.0          # how close to an open portal the server accepts an extraction
const OPEN_PORTALS := 2         # of the four candidate portals
const PVP_MULT := 0.6           # a player's damage to another player
const PVP_RANGE := 30.0         # the server drops a player-on-player blow, burn or control from further away
const PVP_EFFECT_GAP := 0.8     # the same crowd control from one player on one other, at most this often (s)
const PVP_BURN_CAP := 140.0     # a burn's damage a second, before PVP_MULT
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
var forced := false             # server: an admin restarted the round, which runs off the clock until it ends
var open: Array = []            # server: indices (in the portal list) of the open Extraction Portals
var carried := {}               # server: peer id -> Array of items picked up this raid (dropped if they vanish)
var died_items := {}            # server: peer id -> true once their death drop was handled
var dead_wait := {}             # server: peer id -> seconds since they fell, waiting for their death drop
var last_hit := {}              # server: peer id -> [attacker peer id, raid_t]
var pvp_effect_t := {}          # server: "attacker:target:kind" -> raid_t of the last control let through
var stash_user := {}            # server: antechamber stash chest (interactable index) -> the peer id using it
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

## Which chest this map's stash is (StashChests: jj's numbered chests; the Hollow Crypt has #2, the blue Spirit
## Chest). "--stash-chest N" on the command line previews another.
static func stash_chest_no() -> int:
	var a := OS.get_cmdline_user_args()
	var i := a.find("--stash-chest")
	if i >= 0 and i + 1 < a.size() and StashChests.CHESTS.has(int(a[i + 1])):
		return int(a[i + 1])
	return StashChests.for_map(ZONE)

## A colour of a chest's theme (its Inter's "stash_theme").
static func stash_col(t: Node, key: String):
	var th: String = str(t.get_meta("stash_theme")) if t.has_meta("stash_theme") else "ember"
	return STASH_THEMES.get(th, STASH_THEMES["ember"])[key]

# ---------------------------------------------------------------- the map
## The Hollow Crypt. Cell (i, j) of a 4x4 grid; the middle 2x2 is the great hall.
static func build(w: World) -> void:
	if map_id == "peak":
		BgPeak.build(w)
		return
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
	# the look (CryptProps): the Ossuary's wall cells become niches, tombs, statues and braziers from these rooms;
	# the rubble, cobwebs and the hall's seal after. Visual only: no footprint, no roll on w.rng, no interactable
	w.set_meta("bg_rooms", rooms)
	w.set_meta("bg_hall", hall)
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
		_stash_chest(w, Vector3(c.x - 1.9, 0, c.y - 1.9), stash_chest_no())
	w.set_meta("bg_gates", gates)
	for p in portals:
		var glow: Node3D = CryptProps.portal_glow() if CryptProps.has("archway") else Fx.portal_model()
		var it: Inter = w._inter("extract", "Extraction Portal", p, 1.8, glow, {"open": false})
		var m := it.get_node_or_null("Model")
		if m:
			m.visible = false
		var arch := CryptProps.archway()
		if arch != null:
			# the rune gate round the portal's light, there whether or not the portal is open (its runes light with it)
			arch.name = "Arch"
			it.add_child(arch)
	CryptProps.dress(w)
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

## The antechamber's stash chest (jj): the player's own shared stash (SharedStash, local to their game), open until
## the gates rise (Game.stash_allowed), to leave behind what they won't risk once they've seen the matchup.
static func _stash_chest(w: World, p: Vector3, no := 2) -> void:
	# every map its own chest (jj): its numbered chest (StashChests, assets/models/stash/chest/), else the camp's
	var theme := StashChests.theme(no)
	var chest: Node3D
	if StashChests.has(no):
		chest = Props.footprint(Models.N(null, "stash"), STASH_CHEST_HALF)
		var crm := StashChests.model(no)
		chest.add_child(crm)
		crm.rotation.y = deg_to_rad(20.0)
	elif ForestCamp.has_piece("stash_chest"):
		chest = Props.footprint(Models.N(null, "stash"), ForestCamp.SET_PIECES["stash_chest"] * 0.9)
		var cm := ForestCamp.model("stash_chest")
		chest.add_child(cm)
		cm.rotation.y = deg_to_rad(20.0)
	else:
		chest = Props.stash_chest(null, Vector3.ZERO, 20.0)
	# (jj: "make the stash a highlight of the area", "the waypoint's parameters") its dais, built like the camp's
	# grand waypoint (StashDais: Blender-modelled stone tiers and flagstones, ember runes in carved channels, fire
	# bowls); solid, the chest on its plinth in the middle, opened from the dais's edge
	var lift := 0.0
	var reach := 1.6
	var SD = load("res://scripts/stash_dais.gd")        # (at run time: tool scripts load this file before the autoloads)
	if SD.has_model(StashChests.path(no, "dais")):
		var dais: Node3D = SD.make(theme, StashChests.path(no, "dais"))
		dais.position = Vector3(p.x, 0.0, p.z)
		dais.rotation.y = deg_to_rad(20.0)
		w.add_child(dais)
		lift = SD.PLINTH_Y
		w.add_circle(Vector3(p.x, 0, p.z), SD.SOLID_R)
		reach = SD.SOLID_R + 0.5
	var it: Inter = w._inter("stash", "Stash (until the gates rise)", p, reach, chest, {"raid": true})
	chest.position.y = lift
	w.solid(chest)
	it.set_meta("pick_y", 0.6 + lift)
	it.set_meta("lift", lift)          # (the chest stands this high on its dais: Game.chest_lid, stash_fx follow it)
	it.set_meta("stash_theme", theme)
	it.set_meta("stash_chest", no)
	_dress_seals(it, chest, lift)
	if stash_col(it, "pal") != "":
		_spirit_coals(chest, stash_col(it, "coals"))

## The chest's gold wolf seals (jj's pick; the "seal_N" parts, assemble_chest.py): molten gold that breathes
## (gold_seal.gdshader) and a warm gold light just in front of the chest that casts real shadows (the hasp, the
## padlock and the straps over the wood), first in the shadow budget. Game.chest_lid blows them off on opening.
static func _dress_seals(it: Node3D, chest: Node3D, lift: float) -> void:
	var seals := chest.find_children("seal_*", "MeshInstance3D", true, false)
	if seals.is_empty():
		return
	var sh := load("res://scripts/gold_seal.gdshader") as Shader
	for s in seals:
		var mi: MeshInstance3D = s
		var src := mi.get_active_material(0) as StandardMaterial3D
		var sm := ShaderMaterial.new()
		sm.shader = sh
		if src != null:
			sm.set_shader_parameter("albedo_tex", src.albedo_texture)
			if src.normal_texture != null:
				sm.set_shader_parameter("normal_tex", src.normal_texture)
				sm.set_shader_parameter("has_normal", true)
		sm.set_shader_parameter("phase", randf() * TAU)
		sm.set_shader_parameter("glow_col", stash_col(it, "seal"))
		mi.material_override = sm
	var gl := OmniLight3D.new()
	gl.name = "seal_glow"
	gl.light_color = stash_col(it, "seal_light")
	gl.light_energy = 2.4
	gl.omni_range = 3.6
	gl.omni_attenuation = 1.4
	gl.shadow_enabled = true
	gl.shadow_blur = 1.0
	gl.position = Vector3(0.0, lift + 0.55, 0.95)
	gl.set_meta("shadow_pri", true)
	gl.add_to_group(Grade.SHADOW_GROUP)
	chest.add_child(gl)
	it.set_meta("pick", 1.4)


## Stash #2's and #3's coals burn in their fire's colour: Meshy's painted embers (the bright orange texels) glow
## blue or purple, the rest of them dark ash.
const SPIRIT_COALS := """
shader_type spatial;
uniform sampler2D tex : source_color, filter_linear_mipmap;
uniform vec3 glow : source_color = vec3(0.25, 0.55, 1.0);
void fragment() {
	vec4 a = texture(tex, UV);
	float hot = clamp((a.r - a.b) * 1.8 - 0.25, 0.0, 1.0);
	float l = dot(a.rgb, vec3(0.3, 0.5, 0.2));
	ALBEDO = mix(vec3(l * 0.55), glow * 0.16, hot);
	ROUGHNESS = 0.85;
	EMISSION = glow * hot * 2.4;
}
"""

static func _spirit_coals(chest: Node3D, glow: Color) -> void:
	var sh := Shader.new()
	sh.code = SPIRIT_COALS
	for n in chest.find_children("coals*", "MeshInstance3D", true, false):
		var mi: MeshInstance3D = n
		var src := mi.get_active_material(0) as StandardMaterial3D
		var sm := ShaderMaterial.new()
		sm.shader = sh
		if src != null:
			sm.set_shader_parameter("tex", src.albedo_texture)
		sm.set_shader_parameter("glow", glow)
		mi.material_override = sm

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
	Engine.max_fps = Battlegrounds.server_tick()     # headless, the loop would otherwise spin a whole core
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
	if g.match_instance == null:
		ServerUpdate.watch(g, "[BG]", func() -> bool: return g.net.players.is_empty() or bg.state == "reset")

## How long the antechamber waits for a bell (tests' fast rounds keep a lobby long enough for a client to join).
static func lobby_max() -> float:
	return 40.0 if fast else LOBBY_MAX

## A raid of several (`--raid N`, real time): its rounds follow the clock.
func aligned() -> bool:
	return raid_idx >= 0 and not fast and not forced

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
	cc_dr.clear()
	died_items.clear()
	dead_wait.clear()
	last_hit.clear()
	pvp_obj_last.clear()
	pvp_effect_t.clear()
	stash_user.clear()
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
	if game.match_instance == null and state == "lobby" and (raid_t >= lobby_max() or game.net.players.size() >= RAID_MIN):
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
		open_portals()
	if raid_t >= secs(RAID_SECS):
		_announce("The crypt collapses")
		collapse()
		forced = false               # (an admin's round is over: back on the clock)
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

## The Extraction Portals open: OPEN_PORTALS on the Ossuary, one on each floor below.
func open_portals() -> void:
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

## The crypt collapses: whoever is still inside dies, and the reset begins.
func collapse() -> void:
	for pid in game.net.players.keys():
		var h = game.net.players[pid]["hero"]
		if is_instance_valid(h) and not h.dead:
			game.net.hit_player(pid, 999999.0, h.global_position, "collapse", "phys")
	state = "reset"
	reset_t = secs(RESET_SECS)

## An admin's raid controls (Escape → Admin in a raid, Net.sv_bg_admin; refused for anyone without the admin role),
## for testing without waiting on the clock:
##   "restart"  the crypt collapses now and a new round begins in ADMIN_RESTART s, off the clock (`forced`) until it ends
##   "gates"    the antechamber's wait and countdown skipped: the gates open now
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
				open_gates(game.world)
				_announce("%s opened the gates" % who)
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

## Server: a player asks to open an antechamber's stash chest (Net.sv_bg_stash, from Game._interact; the chest's
## index in the interactables). One player at a time (jj: whoever clicks first; requests arrive here one after
## another, so the first one in wins): checked (the countdown, alive, standing at it, nobody else at it), then the
## chest is theirs (stash_user) until they close it, leave or the gates rise, and the price: STASH_SLOW for the
## rest of the raid on them alone (Net.cl_bg_stash_ok -> Hero.stash_slow) and the chest's fire and smoke for
## everyone (Net.cl_bg_stash_fx). Anyone else is told it's in use.
func stash_opened(pid: int, idx: int) -> void:
	if not (state == "lobby" or state == "prep") or not game.net.players.has(pid):
		return
	var h = game.net.players[pid]["hero"]
	if not is_instance_valid(h) or h.dead or idx < 0 or idx >= game.world.interactables.size():
		return
	var t = game.world.interactables[idx]
	if not is_instance_valid(t) or t.kind != "stash" or h.global_position.distance_to(t.global_position) > t.radius + 2.0:
		return
	var who := int(stash_user.get(idx, 0))
	if who != 0 and who != pid and game.net.players.has(who):
		game.net.rpc_id(pid, "cl_bg_note", "Someone is already at that stash")
		return
	stash_user[idx] = pid
	game.net.rpc_id(pid, "cl_bg_stash_ok", idx)
	game.net.rpc("cl_bg_stash_fx", idx)

## Server: they closed it (or left): the chest is free.
func stash_closed(pid: int) -> void:
	for idx in stash_user.keys():
		if int(stash_user[idx]) == pid:
			stash_user.erase(idx)

## The Sfx autoload, looked up at run time (a static reference would compile this script before the autoload exists
## in the tool scripts that load it, `-s`).
static func _sfx() -> Node:
	return (Engine.get_main_loop() as SceneTree).root.get_node_or_null("Sfx")

## Client: the chest blows out fire and smoke as it opens.
static func stash_fx(g: Node, idx: int) -> void:
	if g.world == null or idx < 0 or idx >= g.world.interactables.size():
		return
	var t = g.world.interactables[idx]
	if not is_instance_valid(t):
		return
	var lift: float = float(t.get_meta("lift", 0.0))
	var at: Vector3 = t.global_position + Vector3(0, 0.7 + lift, 0)
	var root: Node3D = g.world.fx_root
	if not bool(t.get_meta("lid_open", false)):
		g.chest_lid(t, true, false)
	# (jj) once opened it stays open, burning, its fire and mist looping on it until the gates rise (close_stashes)
	if t.get_node_or_null("stash_loop") == null and _sfx().bank.has("chest_raid_loop") and not _sfx().muted:
		var lp := AudioStreamPlayer3D.new()
		lp.name = "stash_loop"
		lp.bus = "SFX"
		lp.stream = _sfx()._pick("chest_raid_loop")
		lp.position = Vector3(0, 0.7 + lift, 0)
		lp.unit_size = 6.0
		lp.volume_db = STASH_LOOP_DB + _sfx().volume_db
		t.add_child(lp)
		# (jj) it comes in at full volume after the opening's own sound, then sinks to 20% over 10 s and stays there
		Fx.later(t, 1.6, func():
			if not is_instance_valid(lp):
				return
			lp.play()
			lp.create_tween().tween_property(lp, "volume_db", STASH_LOOP_DB + _sfx().volume_db + linear_to_db(0.2), 10.0))
		# the chest burning on: a brazier's fire in it (FireFx, the game's braziers), its light and smoke
		var fire := Node3D.new()
		fire.name = "stash_fire"
		t.add_child(fire)
		# (its light is the chest's own shadow-casting glow, Game.chest_lid: no second light here)
		Fx.later(t, 0.8, func():
			if is_instance_valid(fire):
				var ff := FireFx.make(fire, Vector3(0, 0.62 + lift, 0), stash_col(t, "fire"), 0.7, stash_col(t, "fire_col"), false, false, stash_col(t, "fire") != "spirit")
				if stash_col(t, "pal") == "void":
					InfernalFx.recolor(ff, "void"))

	# (jj: "opening the stash is a huge thing", "make it fire style"), timed to the lid (it lifts 0.26 s in):
	# the padlock's sparks, then the lid's heave lets the fire out: an orange flash, the spray (a jet of flame
	# streaks out of the open chest), a fireball, a ring of fire rolling over the floor, burning embers, then a
	# column of dark smoke. The chest keeps burning (stash_fire) until the gates rise.
	# The fire is the game's own: the Demon kit's living fire (InfernalFx.fire: simulated flipbook flame tongues)
	# for the spray, its lit smoke, and the braziers' fire (FireFx) for the chest burning on.
	var pal: String = stash_col(t, "pal")
	var jet: Array = stash_col(t, "jet")
	Fx.later(t, 0.28, func():
		Fx.flash(root, at + Vector3(0, 0.4, 0), stash_col(t, "flash"), 6.0, 0.7, 7.0)
		var spray: Node3D = InfernalFx.fire(root, at + Vector3(0, -0.2, 0), 3.2, 260.0, InfernalFx.tier(g))
		var spray2: Node3D = InfernalFx.fire(root, at + Vector3(0, -0.1, 0), 1.6, 140.0, InfernalFx.tier(g), false, true)
		if pal != "":
			InfernalFx.recolor(spray, pal)
			InfernalFx.recolor(spray2, pal)
		# the spray's jet: flame streaks thrown up and out of the open chest
		Fx.streaks(root, at, [[0.0, jet[0]], [0.4, jet[1]], [1.0, jet[2]]], 60, 6.5, 0.07, 2.6, 0.55, false, -3.0, 24.0)
		Fx.ring(root, t.global_position + Vector3(0, lift, 0), 1.9, stash_col(t, "ring"), 0.5)
		Fx.burst(root, at + Vector3(0, 0.5, 0), stash_col(t, "burst"), 26, 2.6, 0.03, 1.6, false, -1.2, 60.0)
		Fx.later(root, 1.2, func():
			InfernalFx.fire_on(spray, false)
			InfernalFx.fire_on(spray2, false))
		Fx.later(root, 2.6, func():
			for n in [spray, spray2]:
				if is_instance_valid(n):
					n.queue_free()))
	Fx.later(t, 0.7, func():
		var sm := InfernalFx.smoke(root, at + Vector3(0, 1.1, 0), 20, Vector3(0.45, 0.2, 0.35), Vector3.UP, 1.4, 3.0, 0.12, 0.75)
		if pal != "":
			InfernalFx.recolor(sm, pal)
		Fx.later(root, 4.0, func():
			if is_instance_valid(sm):
				sm.queue_free()))
	# the dais: everything flares and a ring of light runs out from the chest (StashDais.burst)
	for d in g.world.get_children():
		if d.has_method("burst") and (d as Node3D).global_position.distance_to(t.global_position) < 1.0:
			d.burst()
	if g.ui.trade_with == t:
		g.add_shake(0.45)
		g.ui.big_message("THE STASH IS OPEN")
	if not _sfx().bank.has("chest_raid_open"):
		_sfx().play_at("burn_item", at)        # (chest_lid plays the chest's own sound once it's built)

## Client: the gates rose: every antechamber chest shuts, its fire and its loop stop.
static func close_stashes(g: Node) -> void:
	if g.world == null:
		return
	for t in g.world.interactables:
		if is_instance_valid(t) and t.kind == "stash" and t.data.get("raid", false):
			for nm in ["stash_loop", "stash_fire"]:
				var n: Node = t.get_node_or_null(nm)
				if n != null:
					n.queue_free()
			if bool(t.get_meta("lid_open", false)):
				g.chest_lid(t, false)

func send_roster() -> void:
	if not game.net.players.is_empty():
		game.net.rpc("cl_bg_roster", roster())

## Someone rang an antechamber's bell (or the lobby ran out): the countdown to the gates, for everyone.
func start_prep(who: String) -> void:
	if state != "lobby":
		return
	state = "prep"
	prep_left = secs(PREP_SECS)
	send_roster()
	_announce(("%s rang the bell: the gates open in %d seconds" % [who, int(PREP_SECS)]) if who != "" else "The gates open in %d seconds" % int(PREP_SECS))
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
	stash_closed(pid)
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

## Client: an open portal's gate burns with its runes, a closed one stands dark (CryptProps.set_runes; the state
## comes with Net.cl_bg_raid, which shows and hides the portal's light).
static func sync_gates(g: Node) -> void:
	if g.world == null:
		return
	for p in portal_list(g.world):
		var arch: Node3D = p.get_node_or_null("Arch")
		if arch == null:
			continue
		var on: bool = bool(p.data.get("open", false))
		if not arch.has_meta("lit") or bool(arch.get_meta("lit")) != on:
			arch.set_meta("lit", on)
			CryptProps.set_runes(arch, 2.6 if on else 0.0)

## Client: the raid's clock and portals, top of the screen.
static func hud(g: Node, delta: float) -> void:
	sync_gates(g)
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
			lbl.text = "THE ANTECHAMBER  ·  ring the bell to begin  ·  the gates open by themselves in %d:%02d" % [(w + int(PREP_SECS)) / 60, (w + int(PREP_SECS)) % 60]
			lbl.add_theme_color_override("font_color", Color(0.95, 0.85, 0.6))
		else:
			lbl.text = "THE GATES OPEN IN %d  ·  the stash chest is open until then" % w
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
