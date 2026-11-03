class_name Gauntlet
extends Node
## The Gauntlet of Kings (zone "gauntlet", nightly mode 2026-11-02): a co-op boss rush. A sunken throne hall under
## the Act I camp where four of the game's kings come through the Throne Gate one after another (Gorehide the
## Tyrant, Cinderhide the Burning Sloth, Old Mossbeard, Hrimgar the Frostbound), each with its own fight (their
## brains are the ones they have elsewhere: Enemy's bear AI, sloth.gd, bg_boss.gd). One clock runs from the first
## gong to the last king, the party shares a few lives (each fall spends one; a fall with none left ends the run),
## and between kings the party picks ONE of three offerings: Mercy (everyone healed, a life back), Wrath (the next
## king comes in wounded) or Greed (the next king is stronger, but drops a hoard). Beat the hall's record time.
##
## Host-authoritative (the player host, or the online co-op server, coop_server.gd): this node runs the gauntlet on
## the host and only shows it on the others. State -> Net.gauntlet_state (cl_gauntlet), events -> Net.gauntlet_event
## (cl_gauntlet_fx), a partner's gong / offering -> Net.request_gauntlet (sv_gauntlet, with his level). Entered from
## the camp's Gauntlet Gate (forest_camp.gd, Inter "gauntlet_gate" -> Game._interact -> travel: the ready check).
## Tests: tools/nightly_gauntlet_test.gd (solo host), tools/gauntlet_coop_test.gd (the co-op server and two players).

const ZONE := "gauntlet"
const TITLE := "The Gauntlet of Kings"
const CENTER := Vector3(0, 0, -8)
const START := Vector3(0, 0, 15)
const GATE := Vector3(0, 0, -22)          # the Throne Gate the kings come through
const GONG := Vector3(0, 0, 6)
const EXIT := Vector3(0, 0, 19.5)
const COUNT_SECS := 5.0                   # gong struck / offering taken: the next king comes after this
const BOON_SECS := 25.0                   # time to pick an offering (none = the next king comes anyway)
const END_SECS := 14.0                    # won or lost: then the gong can be struck again
const NUDGE_SECS := 4.0                   # a king that hasn't noticed anyone by then is woken
const LIVES := 3                          # the party's lives (one more per extra player)
const LEVEL_UNDER := 1                    # the kings come this many levels under the party's average
const PER_PLAYER := 0.6                   # each extra player: the kings' life x this much more
## The kings, in order. "life": their life x this (on top of the level), so each fight is about as long as the last.
const KINGS := [
	{"kind": "trex", "life": 0.75},
	{"kind": "sloth_fire", "life": 2.2},
	{"kind": "hermit", "life": 0.85},
	{"kind": "ice_troll", "life": 0.85},
]
## The offerings between kings: [name, what it does, colour]
const BOONS := [
	["Mercy", "Everyone is healed, and the party gets a life back", Color(0.55, 1.0, 0.75)],
	["Wrath", "The next king comes in wounded (-30% life)", Color(1.0, 0.3, 0.2)],
	["Greed", "The next king is stronger (+35% life, +15% damage) but drops a hoard", Color(1.0, 0.8, 0.25)],
]
const DMG := 0.7                          # the kings' blows x this (four bosses in a row, no rest between)
const WRATH := 0.7
const GREED_LIFE := 1.35
const GREED_DMG := 1.15
const TROPHY_X := [-12.0, -4.5, 4.5, 12.0]   # the trophy braziers on the north wall, lit as each king falls

var game: Node
var world: World
var state := "idle"             # idle | count | fight | boon | won | lost
var king := 0                   # the king under way or next (0..3)
var t := 0.0                    # seconds left in count / boon / won / lost
var run_t := 0.0                # the run's clock
var lives := LIVES
var boon := -1                  # the offering taken for the next king (-1 none)
var greed := 0                  # offerings of Greed taken this run (the record shows it)
var splits: Array = []          # the run's time when each king fell
var record := 0.0               # the hall's best time (0 = none yet), and who set it
var record_by := ""
var levels := {}                # host: peer id -> that player's level (Net.request_gauntlet)
var boss: Enemy = null          # host (and, from the "king" event, everyone): the king on the floor
var _greedy_king := false       # host: this king was made greedy
var _alive_t := 0.0
var _was_dead := {}             # host: hero instance id -> dead last frame (a fall spends a life)
var _sync_t := 0.0
var _said_hi := false
var _record_loaded := false
var _trophies: Array = []       # the four trophy fires (every peer)
var _orbs: Array = []           # the three offerings' orbs and lights
var _gong: Node3D
var _hud: Control
var _hud_lbl: Label
var _hud_sub: Label

func host() -> bool:
	return game != null and not game.net.is_client()

# ---------------------------------------------------------------- the map (every peer builds it)
static func build(w: World) -> void:
	w.flat_floor = true
	w.theme = {"name": "gauntlet"}
	var hall := Rect2(-18, -26, 36, 36)
	w.floor_rects.append(hall)
	w.floor_rects.append(Rect2(-3, 10, 6, 3))          # the way in
	w.floor_rects.append(Rect2(-6, 12.5, 12, 9))        # the vestibule, with the way back to the camp
	var bb: Rect2 = w.floor_rects[0]
	for r in w.floor_rects:
		bb = bb.merge(r)
	w.bounds = bb.grow(3.0)
	w.dirt_blobs = [[w.bounds.get_center(), 9999.0, 1.0]]
	w.dirt_lines = []
	var c := CENTER
	# a ring of pillars round the fighting floor, torches on the walls, sarcophagi of the fallen challengers
	for i in 8:
		var a := TAU * (i + 0.5) / 8.0
		w._pillar(Vector3(c.x + cos(a) * 14.5, 0, c.z + sin(a) * 14.5), 5.5)
	for k in 4:
		w._wall_torch(Vector3(-17.85, 0, lerpf(-22.0, 6.0, k / 3.0)), k == 1)
		w._wall_torch(Vector3(17.85, 0, lerpf(-22.0, 6.0, k / 3.0)), k == 2)
	for sx in [-15.5, 15.5]:
		w._sarcophagus(Vector3(sx, 0, -12.0), PI * 0.5)
		w._sarcophagus(Vector3(sx, 0, 1.0), PI * 0.5)
	for k in 12:
		var bp := Vector3(w.rng.randf_range(hall.position.x + 1.5, hall.end.x - 1.5), 0, w.rng.randf_range(hall.position.y + 1.5, hall.end.y - 1.5))
		if bp.distance_to(c) > 6.0 and bp.distance_to(GONG) > 3.0:
			w._bones(bp)
	w._wall_torch(Vector3(-3.5, 0, 12.65), false)
	w._wall_torch(Vector3(3.5, 0, 12.65), false)
	# the Throne Gate: a great red portal in the north wall, an empty throne either side
	var pm := Fx.portal_model(Color(1.0, 0.2, 0.08))
	pm.name = "throne_gate"
	w.props_root.add_child(pm)
	pm.position = GATE + Vector3(0, 0, -2.5)
	pm.scale = Vector3.ONE * 1.9
	var gl := OmniLight3D.new()
	gl.light_color = Color(1.0, 0.3, 0.15)
	gl.light_energy = 2.2
	gl.omni_range = 10.0
	gl.position = GATE + Vector3(0, 2.2, -1.5)
	w.props_root.add_child(gl)
	var g := Gauntlet.new()
	g.name = "Gauntlet"
	g.world = w
	w.add_child(g)
	w.set_meta("gauntlet", g)
	# the trophy braziers: dark until their king falls
	for i in TROPHY_X.size():
		var tp := Vector3(TROPHY_X[i], 0, -24.6)
		var br := _pedestal(w, tp, Color(0.25, 0.22, 0.2))
		var f := Props.fire(br, Vector3(0, 1.45, 0), 0.9, Color(1.0, 0.5, 0.2), true, false, true, "brazier")
		f.visible = false
		g._trophies.append(f)
	w.crypt_shell()
	# the gong that starts a run
	var gm := Models.N(null, "gong")
	var wood := Props.iron()
	Models.seg(gm, Vector3(-1.4, 0, 0), Vector3(-1.4, 3.1, 0), 0.09, 0.1, wood, 6)
	Models.seg(gm, Vector3(1.4, 0, 0), Vector3(1.4, 3.1, 0), 0.09, 0.1, wood, 6)
	Models.seg(gm, Vector3(-1.55, 3.05, 0), Vector3(1.55, 3.05, 0), 0.08, 0.08, wood, 6)
	var disc := Models.P(gm, Geo.cyl(1.05, 1.05, 0.08, 28), Mats.world(Color(0.72, 0.5, 0.22), Color(0.5, 0.33, 0.14), 0.35, 2.0, 0.0, Props.MOSS, true, 0.85), Vector3(0, 1.75, 0), Vector3(90, 0, 0))
	disc.name = "disc"
	Models.P(gm, Geo.torus(0.25, 0.34, 24, 4), Mats.glow(Color(1.0, 0.55, 0.2), 1.6), Vector3(0, 1.75, 0.06), Vector3(90, 0, 0))
	var gi: Inter = w._inter("gauntlet", "The Gong of Challenge", GONG, 1.8, gm)
	g._gong = gi
	w.add_circle(GONG + Vector3(-1.4, 0, 0), 0.2)
	w.add_circle(GONG + Vector3(1.4, 0, 0), 0.2)
	# the three offerings between kings, in an arc south of the floor
	for k in BOONS.size():
		var a2: float = (float(k) - 1.0) * 0.62
		var op := c + Vector3(sin(a2), 0, cos(a2)) * 9.5
		var om := Models.N(null, "offering")
		var orb := Models.P(om, Geo.sph(0.32, 14), Mats.glow(BOONS[k][2], 2.6), Vector3(0, 1.55, 0))
		Models.P(om, Geo.cyl(0.42, 0.55, 1.2, 10), Props.stone(), Vector3(0, 0.6, 0))
		Models.P(om, Geo.cyl(0.5, 0.4, 0.14, 10), Props.iron(), Vector3(0, 1.25, 0))
		var it: Inter = w._inter("gauntlet_boon", "Offering of %s" % BOONS[k][0], op, 1.4, om, {"i": k})
		it.rotation.y = atan2(c.x - op.x, c.z - op.z)
		var ol := OmniLight3D.new()
		ol.light_color = BOONS[k][2]
		ol.light_energy = 1.4
		ol.omni_range = 4.5
		ol.position = Vector3(0, 1.8, 0)
		om.add_child(ol)
		g._orbs.append([orb, ol])
		w.add_circle(op, 0.5)
	# the way back to the camp
	w._inter("gauntlet_exit", "Back to the camp", EXIT, 1.6, Fx.portal_model(Color(0.45, 0.75, 1.0)))
	w.spawns["start"] = START
	w.spawns["portal"] = START
	w.set_meta("bg_spawns", [START])

static func _pedestal(w: World, p: Vector3, _col: Color) -> Node3D:
	var b := Models.N(null, "trophy")
	Models.P(b, Geo.cyl(0.55, 0.7, 0.9, 10), Props.stone(), Vector3(0, 0.45, 0))
	for k in 3:
		var a := TAU * k / 3.0
		Models.seg(b, Vector3(cos(a) * 0.32, 0.9, sin(a) * 0.32), Vector3(cos(a) * 0.22, 1.35, sin(a) * 0.22), 0.04, 0.05, Props.iron(), 6)
	Models.P(b, Geo.cyl(0.5, 0.3, 0.25, 12), Props.iron(), Vector3(0, 1.4, 0))
	w._place(b, p)
	w.add_circle(p, 0.6)
	return b

static func respawn_at(w: World) -> Vector3:
	return w.free_spot_near(START, 2.0)

static func king_name(i: int) -> String:
	return str(Data.ENEMIES[KINGS[clampi(i, 0, KINGS.size() - 1)]["kind"]]["name"])

static func clock(s: float) -> String:
	return "%d:%02d" % [int(s) / 60, int(s) % 60]

# ---------------------------------------------------------------- every peer
func _ready() -> void:
	game = world.get_parent()

func _exit_tree() -> void:
	if _hud != null and is_instance_valid(_hud):
		_hud.queue_free()
	if host():
		_clear_floor()

func _process(delta: float) -> void:
	if game == null or game.world != world or game._busy:
		return
	if host():
		if not _record_loaded:
			_record_loaded = true
			_load_record()
		_host_tick(delta)
	else:
		if state in ["count", "boon", "won", "lost"]:
			t = maxf(0.0, t - delta)
		if state in ["count", "fight", "boon"]:
			run_t += delta
	if not _said_hi and game.net.is_client() and game.net.active:
		_said_hi = true
		game.net.request_gauntlet("hi", 0, int(game.hero.level))
	_show()
	if not game.net.server:
		_draw_hud()

## The offerings glow while one can be taken; the gong while a run can begin.
func _show() -> void:
	var pick := state == "boon"
	for k in _orbs.size():
		var o: Array = _orbs[k]
		var lit := pick or (boon == k and state == "count")
		(o[0] as Node3D).visible = lit
		(o[1] as OmniLight3D).visible = lit
		if lit:
			(o[0] as Node3D).position.y = 1.55 + sin(Time.get_ticks_msec() * 0.003 + k) * 0.08
	for i in _trophies.size():
		(_trophies[i] as Node3D).visible = i < splits.size()

## Host -> everyone: the run's state (also the late joiner's catch-up, it is sent twice a second).
func _state_args() -> Array:
	return [state, king, t, run_t, lives, boon, greed, splits.duplicate(), record, record_by]

func apply(a: Array) -> void:
	if a.size() < 10:
		return
	state = str(a[0])
	king = int(a[1])
	t = float(a[2])
	run_t = float(a[3])
	lives = int(a[4])
	boon = int(a[5])
	greed = int(a[6])
	splits = (a[7] as Array).duplicate()
	record = float(a[8])
	record_by = str(a[9])
	if state == "fight" and (boss == null or not is_instance_valid(boss) or boss.dead):
		# (a partner who arrived mid-fight: find the king on the floor for his life bar)
		var want: String = str(KINGS[clampi(king, 0, KINGS.size() - 1)]["kind"])
		for e in game.net.enemies.values():
			if is_instance_valid(e) and not e.dead and e.kind == want:
				boss = e
				game.ui.set_boss(e)
				break

## Something everyone sees and hears (the host plays it at once and sends it).
func fx(ev: String) -> void:
	var p := ev.split(":")
	var root: Node3D = world.fx_root
	match p[0]:
		"gong":
			Sfx.play("gauntlet_gong", 0.0, 1.0)
			Sfx.play("arena_horn", -8.0, 0.7)
			Fx.ring(root, GONG + Vector3(0, 0.2, 0), 6.0, Color(1.0, 0.65, 0.3), 0.7)
			Fx.burst(root, GONG + Vector3(0, 1.75, 0.1), Color(1.0, 0.7, 0.3), 26, 4.0, 0.1, 0.6)
			game.ui.big_message("The Gauntlet begins")
			game.add_shake(0.3)
		"king":
			# king:<net id>:<index>:<max life>: its life bar on every screen
			var i := clampi(int(p[2]) if p.size() > 2 else 0, 0, KINGS.size() - 1)
			Sfx.play("gauntlet_gong", -4.0, 0.8)
			Sfx.play_at("portcullis", GATE, 0.0, 0.8)
			Fx.pillar(root, GATE, Color(1.0, 0.3, 0.15), 1.6)
			Fx.burst(root, GATE + Vector3(0, 1.2, 0), Color(1.0, 0.35, 0.1), 40, 5.0, 0.14, 0.8)
			game.ui.message("King %d of %d: %s" % [i + 1, KINGS.size(), king_name(i)], Color(1.0, 0.6, 0.35), 4.0)
			var ke = boss if host() else game.net.enemies.get(int(p[1]) if p.size() > 1 else -1)
			if ke != null and is_instance_valid(ke) and not ke.dead:
				if not host() and p.size() > 3:
					ke.max_life = float(p[3])
				boss = ke
				game.ui.set_boss(ke)
			game.add_shake(0.35)
		"down":
			var i2 := int(p[1]) if p.size() > 1 else 0
			var at: Vector3 = Vector3(TROPHY_X[clampi(i2, 0, TROPHY_X.size() - 1)], 1.6, -24.6)
			Fx.pillar(root, at, Color(1.0, 0.75, 0.35), 1.6)
			Sfx.play("levelup", -4.0, 0.85)
			if game.ui.boss_ref != null and (not is_instance_valid(game.ui.boss_ref) or game.ui.boss_ref.dead):
				game.ui.set_boss(null)
			if i2 + 1 < KINGS.size():
				game.ui.big_message("%s falls  ·  %s" % [king_name(i2).split(",")[0].split(" the ")[0], clock(float(p[2]) if p.size() > 2 else run_t)])
				game.ui.message("Choose an offering before the next king (click one of the three lights)", Color(1.0, 0.85, 0.55), 5.0)
		"boon":
			var k := clampi(int(p[1]) if p.size() > 1 else 0, 0, BOONS.size() - 1)
			var who: String = p[2] if p.size() > 2 else ""
			var col: Color = BOONS[k][2]
			game.ui.big_message("Offering of %s" % BOONS[k][0])
			game.ui.message(("%s chose: " % who if who != "" else "") + str(BOONS[k][1]), col, 4.5)
			Sfx.play("bonfire_open", -4.0, 1.1 if k == 0 else (0.7 if k == 1 else 0.9))
			if k < _orbs.size():
				var op: Vector3 = (_orbs[k][0] as Node3D).global_position
				Fx.pillar(root, op - Vector3(0, 1.5, 0), col, 1.2)
				Fx.burst(root, op, col, 30, 4.0, 0.12, 0.7)
			if k == 0 and not game.net.server and is_instance_valid(game.hero) and not game.hero.dead:
				# Mercy: every player's own hero is healed on his own game
				game.hero.life = game.hero.max_life
				game.hero.mana = game.hero.max_mana
				Fx.holy_slam(root, game.hero.global_position, 3.0)
		"fall":
			var left := int(p[1]) if p.size() > 1 else 0
			Sfx.play("boss_die", -12.0, 1.3)
			if left > 0:
				game.ui.message("A life is spent: %d left" % left, Color(1.0, 0.45, 0.35), 3.0)
			else:
				game.ui.message("No lives left: the next fall ends the run!", Color(1.0, 0.3, 0.25), 4.0)
		"won":
			var secs := float(p[1]) if p.size() > 1 else run_t
			var rec: bool = p.size() > 2 and p[2] == "1"
			Sfx.play("levelup", 0.0, 0.75)
			Sfx.play("crowd_cheer", -8.0, 0.9)
			Fx.holy_slam(root, CENTER, 10.0)
			game.ui.big_message("All four kings have fallen  ·  %s" % clock(secs))
			if rec:
				game.ui.message("A NEW RECORD for the hall!", Color(1.0, 0.85, 0.3), 6.0)
			game.ui.set_boss(null)
			game.add_shake(0.5)
		"lost":
			Sfx.play("boss_die", -4.0, 0.7)
			game.ui.big_message("The Gauntlet is lost")
			game.ui.set_boss(null)
			game.add_shake(0.5)
		"ready":
			game.ui.message("The gong can be struck again", Color(1.0, 0.75, 0.45), 4.0)

func _event(ev: String) -> void:
	fx(ev)
	if game.net.active and game.net.is_host:
		game.net.gauntlet_event(ev)

func _sync() -> void:
	_sync_t = 0.5
	if game.net.active and game.net.is_host:
		game.net.gauntlet_state(_state_args())

# ---------------------------------------------------------------- host
## A player struck the gong (begin), took an offering (boon k) or said hello (his level). `who` = his name.
func request(action: String, arg: int, who: String) -> void:
	if not host():
		return
	match action:
		"begin": begin()
		"boon": choose(arg, who)

## The gong: a run begins (only when none is under way).
func begin() -> void:
	if not host() or state != "idle":
		return
	lives = LIVES + maxi(0, _players().size() - 1)
	king = 0
	boon = -1
	greed = 0
	splits = []
	run_t = 0.0
	state = "count"
	t = COUNT_SECS
	_was_dead.clear()
	_event("gong")
	_sync()

## An offering taken between kings (the first one clicked counts).
func choose(k: int, who := "") -> void:
	if not host() or state != "boon" or k < 0 or k >= BOONS.size():
		return
	boon = k
	if k == 0:
		lives += 1
	elif k == 2:
		greed += 1
	state = "count"
	t = COUNT_SECS
	_event("boon:%d:%s" % [k, who.replace(":", "")])
	_sync()

## The heroes taking part: everyone in the zone but a dedicated server's own (parked) hero.
func _players() -> Array:
	return game.all_heroes().filter(func(h) -> bool: return is_instance_valid(h) and h is Hero and not (game.net.server and h == game.hero))

func _names() -> String:
	var out: Array = []
	if not game.net.server:
		out.append(game.char_name if game.char_name != "" else Data.CLASSES.get(game.hero.cls, {}).get("name", "A hero"))
	for pid in game.net.players:
		out.append(str(game.net.players[pid]["name"]))
	return " & ".join(out)

func _party_level() -> int:
	var tot := 0
	var n := 0
	if not game.net.server:
		tot += int(game.hero.level)
		n += 1
	for pid in levels:
		if game.net.players.has(pid):
			tot += int(levels[pid])
			n += 1
	return maxi(maxi(1, world.level), int(round(float(tot) / maxf(1.0, n)))) if n > 0 else maxi(1, world.level)

func _host_tick(delta: float) -> void:
	_sync_t -= delta
	if _sync_t <= 0.0:
		_sync()
	if state in ["count", "fight", "boon"]:
		run_t += delta
		if _players().is_empty():
			# everyone left mid-run: the hall resets
			_clear_floor()
			state = "idle"
			_sync()
			return
		_watch_falls()
	match state:
		"count":
			t -= delta
			if t <= 0.0:
				_spawn_king()
		"boon":
			t -= delta
			if t <= 0.0:
				boon = -1
				state = "count"
				t = 0.5
				_sync()
		"fight":
			_alive_t += delta
			# a king's minions (Mossbeard's mushrooms) hit as softly as the kings do here
			for m in world.enemies_root.get_children():
				if is_instance_valid(m) and "pvp_pid" in m and m != boss and not m.dead and not m.has_meta("gauntlet_k"):
					m.set_meta("gauntlet_k", true)
					m.dmg = [float(m.dmg[0]) * DMG, float(m.dmg[1]) * DMG]
			if boss == null or not is_instance_valid(boss) or boss.dead:
				_king_down()
			elif not boss.aggro and _alive_t > NUDGE_SECS:
				# a king that hasn't noticed anyone yet (out of its sight): it does now
				boss.aggro = true
				if boss.boss:
					game.on_boss_aggro(boss)
				if boss.brain != null:
					boss._fx("bear_roar")
		"won", "lost":
			t -= delta
			if t <= 0.0:
				state = "idle"
				_event("ready")
				_sync()

## A fall spends a life; a fall with none left ends the run.
func _watch_falls() -> void:
	for h in _players():
		var id: int = h.get_instance_id()
		var was: bool = _was_dead.get(id, false)
		_was_dead[id] = h.dead
		if h.dead and not was:
			if lives <= 0:
				_lose()
				return
			lives -= 1
			_event("fall:%d" % lives)
			_sync()

func _spawn_king() -> void:
	var def: Dictionary = KINGS[king]
	var lvl := maxi(1, _party_level() - LEVEL_UNDER)
	var e: Enemy = game.spawn_enemy(str(def["kind"]), world.free_spot_near(GATE, 2.0), lvl, false, "", 700 + king)
	if e == null:
		return
	var k: float = float(def["life"]) * (1.0 + PER_PLAYER * (_players().size() - 1))
	_greedy_king = boon == 2
	var dk := DMG
	if boon == 2:
		k *= GREED_LIFE
		dk *= GREED_DMG
	e.dmg = [float(e.dmg[0]) * dk, float(e.dmg[1]) * dk]
	e.max_life *= k
	# Wrath: it comes in wounded (its bar shows the wound)
	e.life = e.max_life * (WRATH if boon == 1 else 1.0)
	e.home = CENTER
	e.rig.rotation.y = PI
	boss = e
	_alive_t = 0.0
	state = "fight"
	if e.sloth != null:
		e.aggro = true                       # (the Sloth wakes at once: its lair is the whole hall)
	_event("king:%d:%d:%.1f" % [e.net_id, king, e.max_life])
	_sync()

func _king_down() -> void:
	var at: Vector3 = boss.global_position if boss != null and is_instance_valid(boss) else CENTER
	boss = null
	splits.append(snappedf(run_t, 0.1))
	var lvl := _party_level()
	var n := maxi(1, _players().size())
	# the minions of a king (Mossbeard's mushrooms) wither with him
	_clear_floor()
	if _greedy_king:
		for i in n * 3:
			game.drop_item(Items.gold(int(randf_range(40, 70) * (1.0 + lvl * 0.6))), at)
		for i in n * 2:
			game._drop_loot_roll(at, lvl + 1, true)
	_event("down:%d:%.1f" % [king, run_t])
	if king + 1 >= KINGS.size():
		_win(lvl, n)
	else:
		king += 1
		state = "boon"
		t = BOON_SECS
		boon = -1
	_sync()

func _win(lvl: int, n: int) -> void:
	state = "won"
	t = END_SECS
	var secs := run_t
	var rec := record <= 0.0 or secs < record
	if rec:
		record = snappedf(secs, 0.1)
		record_by = _names() + (" (greedy x%d)" % greed if greed > 0 else "")
		_save_record()
	var cands := Data.UNIQUES.keys().filter(func(u): return int(Data.UNIQUES[u]["lvl"]) <= lvl + 3 and not Data.UNIQUES[u].get("boss_only", false))
	var at := CENTER + Vector3(0, 0, 4.0)
	for i in n:
		if not cands.is_empty():
			game.drop_item(Items.make_unique(cands[randi() % cands.size()]), at)
		game.drop_item(Items.gold(int(randf_range(80, 120) * (1.0 + lvl * 0.6))), at)
	_event("won:%.1f:%s" % [secs, "1" if rec else "0"])

func _lose() -> void:
	state = "lost"
	t = END_SECS
	if boss != null and is_instance_valid(boss) and not boss.dead:
		# the king withdraws: it crumbles (no loot or experience for it)
		boss._by_rival = true
		boss.dmg_tint = Color(0.55, 0.52, 0.5)
		boss.take_damage(1e9, 0.0, boss.global_position, 0.0, false)
		boss._by_rival = false
	boss = null
	_clear_floor()
	_event("lost")
	_sync()

## Whatever is left on the floor (a king's mushrooms, a crumbled king) goes, with no loot.
func _clear_floor() -> void:
	if world == null or world.enemies_root == null:
		return
	for e in world.enemies_root.get_children():
		if is_instance_valid(e) and "pvp_pid" in e and not e.dead and e.pvp_pid == 0 and e != boss:
			e._by_rival = true
			e.take_damage(1e9, 0.0, e.global_position, 0.0, false)
			e._by_rival = false

func _record_path() -> String:
	return "user://gauntlet_record_test.json" if game._testing() else "user://gauntlet_record.json"

func _load_record() -> void:
	var f := FileAccess.open(_record_path(), FileAccess.READ)
	if f == null:
		return
	var d = JSON.parse_string(f.get_as_text())
	if d is Dictionary:
		record = float(d.get("secs", 0.0))
		record_by = str(d.get("by", ""))

func _save_record() -> void:
	var f := FileAccess.open(_record_path(), FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify({"secs": record, "by": record_by}))

# ---------------------------------------------------------------- the HUD (players)
func _draw_hud() -> void:
	if _hud == null:
		_hud = Control.new()
		_hud.name = "gauntlet_hud"
		_hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_hud.set_anchors_preset(Control.PRESET_CENTER_TOP)
		_hud.offset_top = 48
		game.ui.hud.add_child(_hud)
		_hud_lbl = _label(20, 0)
		_hud_sub = _label(15, 28)
	var txt := TITLE.to_upper() + "  ·  "
	var hearts := "♥".repeat(maxi(0, lives)) if lives > 0 else "no lives left"
	match state:
		"idle": txt += "strike the gong to challenge the four kings"
		"count": txt += "%s comes in %d" % [king_name(king), ceili(t)]
		"fight": txt += "KING %d/%d  ·  %s  ·  %s" % [king + 1, KINGS.size(), clock(run_t), hearts]
		"boon": txt += "choose an offering  ·  %d  ·  %s  ·  %s" % [ceili(t), clock(run_t), hearts]
		"won": txt += "ALL FOUR KINGS FALLEN  ·  %s" % clock(splits[-1] if not splits.is_empty() else run_t)
		"lost": txt += "the gauntlet is lost  ·  %d of %d kings" % [splits.size(), KINGS.size()]
	_hud_lbl.text = txt
	_hud_lbl.add_theme_color_override("font_color", Color(1.0, 0.8, 0.55) if state != "lost" else Color(0.75, 0.7, 0.68))
	var sub := "record: " + ("%s by %s" % [clock(record), record_by] if record > 0.0 else "none yet")
	if not splits.is_empty():
		var sp: Array = []
		for s in splits:
			sp.append(clock(float(s)))
		sub = "splits " + " / ".join(sp) + "   ·   " + sub
	if state in ["count", "fight"] and boon >= 0:
		sub = "Offering of %s  ·  " % BOONS[boon][0] + sub
	_hud_sub.text = sub
	_hud.visible = game.playing
	# under the king's life bar while it is up
	var bb: Control = game.ui.boss_bar_box
	_hud.offset_top = (bb.get_global_rect().end.y + 12.0) if bb != null and bb.is_visible_in_tree() else 48.0

func _label(size: int, y: float) -> Label:
	var l := Label.new()
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.position = Vector2(-420, y)
	l.size = Vector2(840, 26)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	l.add_theme_constant_override("outline_size", 6)
	l.add_theme_color_override("font_color", Color(0.9, 0.82, 0.7))
	_hud.add_child(l)
	return l
