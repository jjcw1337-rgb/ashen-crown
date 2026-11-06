class_name Vigil
extends Node
## The Last Flame (zone "vigil"): a co-op horde defence. A sunken sanctum under the Act I camp, its heart a great
## fire on a stone altar; the dark pours in through three breaches (north, east, west) in ten waves, and the party
## holds the flame. Monsters go for the flame (Enemy.taunt = the Flame below) unless a hero stands closer, so
## players intercept, kite and peel; archers shoot it from range (projectile.gd checks the "objective" group).
## Wave 5 brings a champion, wave 8 the Forsaken Bear, wave 10 both. Each wave held: the flame mends a little and
## gold (and every other wave an item) is laid by it. It is endless (Blaine, 2026-11-03): after the ten authored
## waves the dark keeps coming, bigger and stronger every wave (`wave_def`, `wave_level`), a unique each every
## MILESTONE waves held, until the flame goes out; the waves held are the party's score, each player's best goes to
## the leaderboard (FlameBoard; the title's Hall of the Last Flame). Then the flame relights and the party can try
## again. Nothing is lost: it's the story game's co-op, the players' own characters, deaths rise by the flame.
##
## Host-authoritative (the player host, or the online co-op server, coop_server.gd): this node runs the waves on
## the host and only shows them on the others. State -> Net.vigil_state (cl_vigil), events -> Net.vigil_event
## (cl_vigil_fx), a partner's kindling -> Net.request_vigil (sv_vigil), partners' levels -> Net.vigil_hi.
## Entered from the camp's Vigil Gate (forest_camp.gd, Inter "vigil_gate" -> Game._interact -> travel, so the
## party's ready check takes everyone). Retired (MpMode.WAVES = false); its tests were deleted 2026-11-06.

const ZONE := "vigil"
const TITLE := "The Last Flame"
const CENTER := Vector3(0, 0, -2)
const START := Vector3(0, 0, 9)
## the breaches the dark comes through (centres of their rooms)
const GATES := [Vector3(0, 0, -36), Vector3(32, 0, -2), Vector3(-32, 0, -2)]
const GATE_NAMES := ["north", "east", "west"]
const FLAME_LIFE := 1100.0       # at level 1 for one player (scaled by level like monster damage, and by players)
const COUNT_SECS := 6.0          # kindled: the first wave comes after this
const BREAK_SECS := 12.0         # between waves
const END_SECS := 14.0           # lost: then the flame relights
const MEND := 0.15               # of its life the flame regains per wave held
const SPAWN_GAP := 0.55          # seconds between monsters coming out of the breaches
const MAX_ALIVE := 18            # at most this many of a wave on the floor at once (the rest wait in the dark)
const PER_PLAYER := 0.55         # each extra player: this many more monsters, and the flame's life
## The first ten waves: [kind, count] (counts for one player), "champ": a named champion of that kind joins it.
const WAVES := [
	{"foes": [["zombie", 6]]},
	{"foes": [["zombie", 5], ["fallen_skirmisher", 3]]},
	{"foes": [["fallen_skirmisher", 4], ["skel_archer", 2], ["zombie", 4]]},
	{"foes": [["fallen_stalker", 4], ["fallen_reaver", 2], ["zombie", 4]]},
	{"foes": [["fallen_skirmisher", 5], ["skel_archer", 3]], "champ": "fallen_reaver"},
	{"foes": [["zombie", 8], ["fallen_stalker", 5]]},
	{"foes": [["fallen_reaver", 3], ["skel_archer", 4], ["fallen_skirmisher", 5]]},
	{"foes": [["bear", 1], ["fallen_stalker", 5], ["zombie", 5]]},
	{"foes": [["fallen_reaver", 4], ["fallen_skirmisher", 6], ["skel_archer", 4], ["zombie", 4]]},
	{"foes": [["bear", 1], ["fallen_reaver", 3], ["fallen_stalker", 5], ["skel_archer", 4]], "champ": "fallen_reaver"},
]
## Past the tenth wave (`wave_def`): its foes drawn from POOL, GROW more of them per wave, their level up LEVEL_PER a
## wave on top of the +1 every three; a champion every fifth wave (two from the 20th...), the Bear every fourth; more
## on the floor at once (up to MAX_ALIVE_CAP) and coming out faster.
const POOL := ["zombie", "fallen_skirmisher", "skel_archer", "fallen_stalker", "fallen_reaver"]
const BASE_COUNT := 24.0         # wave 11's foes for one player
const GROW := 0.08
const LEVEL_PER := 0.5
const MAX_ALIVE_CAP := 26
const MILESTONE := 5             # every this many waves held from the tenth: a unique each
## Logs from the moor (woodcutting) feed the flame: the share of its life each one gives back (Game._interact)
const FUEL := {"heartwood": 0.25, "oak_log": 0.08, "pine_log": 0.05}
const CHAMP_NAMES := ["Emberwarden", "Ashmaw", "the Cinder Tyrant"]

var game: Node
var world: World
var flame: Flame
var flame_fx: Node3D            # the fire on the altar (every peer)
var flame_light: OmniLight3D
var state := "idle"             # idle | count | wave | break | lost
var wave := 0                   # the wave under way or last held
var t := 0.0                    # seconds left in count / break / lost
var life := FLAME_LIFE
var max_life := FLAME_LIFE
var left := 0                   # monsters of this wave still to kill (shown)
var best := 0                   # the best wave reached this vigil
var held := 0                   # the waves held when the flame went out (the score)
var level := 1                  # host: the waves' base level
var levels := {}                # host: peer id -> that player's level (Net.vigil_hi)
var queue: Array = []           # host: [kind, champion name or ""] still to come out
var alive: Array = []           # host: this wave's monsters on the floor
var _spawn_t := 0.0
var _gate_i := 0
var _sync_t := 0.0
var _hit_fx_t := 0.0
var _said_hi := false
var _champ: Enemy = null         # host: the champion just come out (solo has no net ids)
var _hud: Control
var _hud_lbl: Label
var _hud_fill: ColorRect

## The flame as a target the monsters' AI understands (what Enemy reads of a hero: position, dead, radius, take_hit).
class Flame extends Node3D:
	var vigil: Vigil
	var dead := false
	var radius := 1.3
	func take_hit(dmg: float, from: Vector3, _kind := "melee", _element := "phys") -> void:
		if vigil != null:
			vigil.flame_hit(dmg, from)

func host() -> bool:
	return game != null and not game.net.is_client()

# ---------------------------------------------------------------- the map (every peer builds it)
static func build(w: World) -> void:
	w.flat_floor = true
	w.theme = {"name": "vigil"}
	var hall := Rect2(-16, -18, 32, 32)
	var rooms := [Rect2(-5, -41, 10, 9), Rect2(28, -7, 9, 10), Rect2(-37, -7, 9, 10)]
	w.floor_rects.append(hall)
	for r in rooms:
		w.floor_rects.append(r)
	w.floor_rects.append(Rect2(-2, -33, 4, 16))       # north corridor
	w.floor_rects.append(Rect2(15, -4, 14, 4))        # east
	w.floor_rects.append(Rect2(-29, -4, 14, 4))       # west
	w.floor_rects.append(Rect2(-2.5, 13, 5, 7))       # the way in, from the south
	w.floor_rects.append(Rect2(-5, 19, 10, 7))        # the vestibule with the way back to the camp
	var bb: Rect2 = w.floor_rects[0]
	for r in w.floor_rects:
		bb = bb.merge(r)
	w.bounds = bb.grow(3.0)
	w.dirt_blobs = [[w.bounds.get_center(), 9999.0, 1.0]]
	w.dirt_lines = []
	var c := CENTER
	# a ring of pillars round the altar, braziers in the corners, torches on the walls, bones of the fallen
	for i in 8:
		var a := TAU * (i + 0.5) / 8.0
		w._pillar(Vector3(c.x + cos(a) * 10.5, 0, c.z + sin(a) * 10.5), 5.0)
	for k in 4:
		w._wall_torch(Vector3(lerpf(hall.position.x + 3.0, hall.end.x - 3.0, [0.0, 0.3, 0.7, 1.0][k]), 0, hall.position.y + 0.15), k == 1 or k == 2)
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			_brazier(w, Vector3(c.x + sx * 13.0, 0, c.z + sz * 13.0))
	for i in 6:
		var a2 := TAU * i / 6.0 + 0.3
		w._candles(Vector3(c.x + cos(a2) * 4.2, 0, c.z + sin(a2) * 4.2), true)
	for k in 14:
		var bp := Vector3(w.rng.randf_range(hall.position.x + 1.5, hall.end.x - 1.5), 0, w.rng.randf_range(hall.position.y + 1.5, hall.end.y - 1.5))
		if bp.distance_to(c) > 5.0:
			w._bones(bp)
	for sz in [-9.0, 5.0]:
		for sx in [-14.2, 14.2]:
			w._sarcophagus(Vector3(sx, 0, c.z + sz), 0.0)
	# the breaches: a torn red portal at the far end of each room, torches, bones
	var gi := 0
	for r in rooms:
		var g: Vector3 = GATES[gi]
		var far := g + (g - c).normalized() * 3.0
		var pm := Fx.portal_model(Color(1.0, 0.25, 0.1))
		pm.name = "breach%d" % gi
		w.props_root.add_child(pm)
		pm.position = far
		pm.rotation.y = atan2(g.x - c.x, g.z - c.z)
		pm.scale = Vector3.ONE * 1.4
		var bl := OmniLight3D.new()
		bl.light_color = Color(1.0, 0.3, 0.15)
		bl.light_energy = 1.6
		bl.omni_range = 7.0
		bl.position = far + Vector3(0, 1.6, 0)
		w.props_root.add_child(bl)
		for k in 2:
			w._bones(Vector3(w.rng.randf_range(r.position.x + 1, r.end.x - 1), 0, w.rng.randf_range(r.position.y + 1, r.end.y - 1)))
		gi += 1
	w._wall_torch(Vector3(-3.0, 0, 19.15), false)
	w._wall_torch(Vector3(3.0, 0, 19.15), false)
	w.crypt_shell()
	# the way back to the camp
	w._inter("vigil_exit", "Back to the camp", Vector3(0, 0, 23.5), 1.6, Fx.portal_model(Color(0.45, 0.75, 1.0)))
	# the altar of the Last Flame
	var altar := Models.N(null, "altar")
	var sm := Props.stone_clean()
	Models.P(altar, Geo.cyl(1.7, 1.9, 0.35, 16), sm, Vector3(0, 0.17, 0))
	Models.P(altar, Geo.cyl(1.2, 1.45, 0.5, 14), Props.stone(), Vector3(0, 0.6, 0))
	Models.P(altar, Geo.cyl(1.1, 0.75, 0.45, 14), Props.iron(), Vector3(0, 1.07, 0))
	var rune := Models.P(altar, Geo.torus(1.75, 1.92, 40, 4), Mats.glow(Color(1.0, 0.45, 0.12), 2.2), Vector3(0, 0.37, 0))
	rune.name = "rune_ring"
	var it: Inter = w._inter("vigil", "The Last Flame", c, 2.4, altar)
	var v := Vigil.new()
	v.name = "Vigil"
	v.world = w
	w.add_child(v)
	w.set_meta("vigil", v)
	v.flame_fx = Props.fire(it.get_node("Model"), Vector3(0, 1.25, 0), 1.7, Color(1.0, 0.5, 0.16), true, true, true, "bonfire")
	for n in v.flame_fx.find_children("*", "OmniLight3D", true, false):
		v.flame_light = n
		v.flame_light.light_energy *= 2.0
		v.flame_light.set_meta("base", v.flame_light.light_energy)
		v.flame_light.set_meta("full", v.flame_light.light_energy)
		v.flame_light.omni_range = 20.0
		break
	v.flame = Flame.new()
	v.flame.name = "FlameTarget"
	v.flame.vigil = v
	w.add_child(v.flame)
	v.flame.position = c
	v.flame.add_to_group("objective")
	w.spawns["start"] = START
	w.spawns["portal"] = START
	w.set_meta("bg_spawns", [START])

static func _brazier(w: World, p: Vector3) -> void:
	var g := Models.N(null, "brazier")
	for k in 3:
		var a := TAU * k / 3.0
		Models.seg(g, Vector3(cos(a) * 0.35, 0, sin(a) * 0.35), Vector3(cos(a) * 0.22, 0.85, sin(a) * 0.22), 0.04, 0.05, Props.iron(), 6)
	Models.P(g, Geo.cyl(0.5, 0.3, 0.28, 12), Props.iron(), Vector3(0, 0.95, 0))
	w._place(g, p)
	Props.fire(g, Vector3(0, 1.05, 0), 0.85, Color(1.0, 0.5, 0.2), true, false, true, "brazier")
	w.add_circle(p, 0.5)

static func respawn_at(w: World) -> Vector3:
	return w.free_spot_near(START, 2.0)

# ---------------------------------------------------------------- every peer
func _ready() -> void:
	game = world.get_parent()

func _exit_tree() -> void:
	if _hud != null and is_instance_valid(_hud):
		_hud.queue_free()

func _process(delta: float) -> void:
	if game == null or game.world != world or game._busy:
		return
	if host():
		_host_tick(delta)
	elif state in ["count", "break", "lost"]:
		t = maxf(0.0, t - delta)
	if not _said_hi and game.net.is_client() and game.net.active:
		_said_hi = true
		game.net.vigil_hi(int(game.hero.level))
	_hit_fx_t = maxf(0.0, _hit_fx_t - delta)
	_show_flame()
	if not game.net.server:
		_draw_hud()

## The flame burns lower as it is hurt, and is out while lost.
func _show_flame() -> void:
	var f := clampf(life / maxf(max_life, 1.0), 0.0, 1.0)
	var out := state == "lost"
	if flame_fx != null:
		flame_fx.visible = not out
		var s := 0.55 + 0.45 * f
		flame_fx.scale = Vector3.ONE * s
	if flame_light != null:
		flame_light.set_meta("base", float(flame_light.get_meta("full")) * (0.0 if out else 0.35 + 0.65 * f))

## Host -> everyone: the round's state (also the late joiner's catch-up, it is sent twice a second).
func _state_args() -> Array:
	return [state, wave, t, life, max_life, left, best, held]

func apply(a: Array) -> void:
	if a.size() < 7:
		return
	state = str(a[0])
	wave = int(a[1])
	t = float(a[2])
	life = float(a[3])
	max_life = float(a[4])
	left = int(a[5])
	best = int(a[6])
	held = int(a[7]) if a.size() > 7 else held
	flame.dead = state == "lost"

## Something everyone sees and hears (the host plays it at once and sends it).
func fx(ev: String) -> void:
	var parts := ev.split(":")
	var at: Vector3 = flame.global_position if flame != null else CENTER
	match parts[0]:
		"kindle":
			Sfx.play("bonfire_open", -2.0, 0.8)
			Fx.pillar(world.fx_root, at, Color(1.0, 0.6, 0.25), 1.6)
			Fx.ring(world.fx_root, at, 9.0, Color(1.0, 0.5, 0.2), 0.8)
			game.ui.big_message("The vigil begins")
			game.add_shake(0.25)
		"wave":
			var n := int(parts[1]) if parts.size() > 1 else 1
			Sfx.play("arena_horn", -4.0, 0.85)
			game.ui.big_message("Wave %d" % n if n <= WAVES.size() else "Wave %d  ·  the dark grows" % n)
			game.add_shake(0.2)
		"breach":
			var gi := clampi(int(parts[1]) if parts.size() > 1 else 0, 0, GATES.size() - 1)
			var g: Vector3 = GATES[gi]
			Fx.burst(world.fx_root, g + Vector3(0, 1.0, 0), Color(1.0, 0.3, 0.1), 18, 4.0, 0.12, 0.6)
			Sfx.play_at("portal", g, -8.0)
		"champ":
			# champ:<net id>:<breach>:<name>: its life bar on every screen
			Sfx.play("roar", -2.0, 0.9)
			var nm: String = parts[3] if parts.size() > 3 else "A champion"
			var side: String = GATE_NAMES[clampi(int(parts[2]), 0, GATE_NAMES.size() - 1)] if parts.size() > 2 else "dark"
			game.ui.message("%s comes for the flame from the %s!" % [nm, side], Color(1.0, 0.55, 0.3), 3.5)
			var ce = _champ if host() else game.net.enemies.get(int(parts[1]) if parts.size() > 1 else -1)
			if ce != null and is_instance_valid(ce) and not ce.dead:
				game.ui.set_boss(ce)
			game.add_shake(0.4)
		"hit":
			Fx.burst(world.fx_root, at + Vector3(0, 1.4, 0), Color(1.0, 0.55, 0.2), 10, 3.0, 0.08, 0.4)
			if life < max_life * 0.3:
				game.ui.message("The flame is failing!", Color(1.0, 0.4, 0.3), 1.2)
		"fed":
			Sfx.play_at("burn_item", at, -4.0)
			Fx.burst(world.fx_root, at + Vector3(0, 1.3, 0), Color(1.0, 0.65, 0.2), 30, 4.5, 0.12, 0.8, true, 2.0)
			Fx.flash(world.fx_root, at + Vector3(0, 1.5, 0), Color(1.0, 0.6, 0.25), 4.0, 0.4, 8.0)
		"held":
			var n2 := int(parts[1]) if parts.size() > 1 else 1
			Sfx.play("levelup", -4.0, 0.9)
			Fx.ring(world.fx_root, at, 6.0, Color(1.0, 0.8, 0.4), 0.6)
			game.ui.big_message("Wave %d held" % n2)
		"milestone":
			# milestone:<waves held>: a unique for everyone
			Sfx.play("levelup", 0.0, 0.75)
			Sfx.play("crowd_cheer", -10.0, 0.9)
			Fx.pillar(world.fx_root, at, Color(1.0, 0.9, 0.5), 3.0)
			Fx.holy_slam(world.fx_root, at, 10.0)
			game.ui.big_message("%d waves held!" % (int(parts[1]) if parts.size() > 1 else wave))
			game.add_shake(0.5)
		"lost":
			# lost:<waves held>:<players>: the vigil's score, each player's best to the leaderboard
			var h := int(parts[1]) if parts.size() > 1 else maxi(0, wave - 1)
			var np := int(parts[2]) if parts.size() > 2 else 1
			Sfx.play("boss_die", -4.0, 0.7)
			Fx.burst(world.fx_root, at + Vector3(0, 1.2, 0), Color(0.25, 0.22, 0.2, 0.8), 60, 3.0, 0.35, 1.6, false, 1.5)
			game.add_shake(0.5)
			if not game.net.server:
				var rec := FlameBoard.record(game, h, np)
				game.ui.big_message("The Last Flame has gone out  ·  %d wave%s held%s" % [h, "" if h == 1 else "s", "  ·  NEW BEST" if rec else ""])
		"relit":
			Sfx.play("bonfire_open", -8.0, 1.1)
			game.ui.message("The flame burns again. Click it to begin a new vigil.", Color(1.0, 0.75, 0.45), 4.0)

func _event(ev: String) -> void:
	fx(ev)
	if game.net.active and game.net.is_host:
		game.net.vigil_event(ev)

func _sync() -> void:
	_sync_t = 0.5
	if game.net.active and game.net.is_host:
		game.net.vigil_state(_state_args())

# ---------------------------------------------------------------- host
## Someone clicked the flame: kindle a vigil (only when none is under way).
func begin() -> void:
	if not host() or state != "idle":
		return
	var n := _players().size()
	level = _party_level()
	max_life = FLAME_LIFE * (1.0 + 0.17 * (level - 1)) * (1.0 + PER_PLAYER * (n - 1))
	life = max_life
	wave = 0
	best = 0
	held = 0
	state = "count"
	t = COUNT_SECS
	flame.dead = false
	_event("kindle")
	_sync()

## The heroes taking part: everyone in the zone but a dedicated server's own (parked) hero.
func _players() -> Array:
	return game.all_heroes().filter(func(h) -> bool: return is_instance_valid(h) and not (game.net.server and h == game.hero))

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
	# (two under the party's average: the first waves warm up, the later ones climb past it, +1 every three)
	return maxi(world.level, int(round(float(tot) / maxf(1.0, n))) - 2 if n > 0 else world.level)

func _host_tick(delta: float) -> void:
	_sync_t -= delta
	if _sync_t <= 0.0:
		_sync()
	match state:
		"count", "break":
			t -= delta
			if t <= 0.0:
				_start_wave(wave + 1)
		"wave":
			_spawn_t -= delta
			alive = alive.filter(func(e) -> bool: return is_instance_valid(e) and not e.dead)
			var past := maxi(0, wave - WAVES.size())
			if _spawn_t <= 0.0 and not queue.is_empty() and alive.size() < mini(MAX_ALIVE_CAP, MAX_ALIVE + past / 2):
				_spawn_t = maxf(0.3, SPAWN_GAP - 0.012 * past)
				_spawn_next()
			for e in alive:
				if e.taunt == null:          # (a bite from the Spirit Beast drew it off: back to the flame after)
					e.taunt = flame
					e.taunt_t = 9999.0
			var was := left
			left = alive.size() + queue.size()
			if left != was:
				_sync()
			if left == 0:
				_wave_held()
		"lost":
			t -= delta
			if t <= 0.0:
				state = "idle"
				life = max_life
				flame.dead = false
				_event("relit")
				_sync()

func _start_wave(n: int) -> void:
	wave = n
	best = maxi(best, n)
	state = "wave"
	var w: Dictionary = wave_def(n)
	var k := 1.0 + PER_PLAYER * (_players().size() - 1)
	queue = []
	for f in w["foes"]:
		for i in maxi(1, int(round(float(f[1]) * (k if str(f[0]) != "bear" else 1.0)))):
			queue.append([f[0], ""])
	queue.shuffle()
	var champs: Array = w.get("champs", [w["champ"]] if w.has("champ") else [])
	for ci in champs.size():
		var nm := "%s, %s" % [CHAMP_NAMES[(n / 5 - 1 + ci) % CHAMP_NAMES.size()], Data.ENEMIES[champs[ci]]["name"]]
		queue.insert(mini(3 + ci * 6, queue.size()), [champs[ci], nm])
	alive = []
	left = queue.size()
	_spawn_t = 1.0
	_event("wave:%d" % n)
	_sync()

## Wave n: the authored ten, then the endless ones (POOL, GROW, champions and the Bear; see the constants).
static func wave_def(n: int) -> Dictionary:
	if n <= WAVES.size():
		return WAVES[n - 1]
	var x := n - WAVES.size()
	var total := BASE_COUNT * (1.0 + GROW * (x - 1))
	# the mix turns over the waves: two kinds lead each wave, the rest fill in
	var lead := [POOL[n % POOL.size()], POOL[(n * 3 + 1) % POOL.size()]]
	var foes := []
	for kind in POOL:
		var share := 0.3 if kind in lead else (0.4 / (POOL.size() - 2))
		var c := int(round(total * share))
		if c > 0:
			foes.append([kind, c])
	if n % 4 == 0:
		foes.append(["bear", 1 + x / 12])
	var d := {"foes": foes}
	if n % 5 == 0:
		var champs := []
		for i in 1 + x / 10:
			champs.append(["fallen_reaver", "fallen_stalker", "bear"][(n / 5 + i) % 3])
		d["champs"] = champs
	return d

## Its monsters' level: the party's base, +1 every three waves, and past the tenth LEVEL_PER more a wave.
func wave_level(n: int) -> int:
	return level + (n - 1) / 3 + int(ceil(maxi(0, n - WAVES.size()) * LEVEL_PER))

func _spawn_next() -> void:
	var q: Array = queue.pop_front()
	var gi := _gate_i % GATES.size()
	_gate_i += 1
	var g: Vector3 = GATES[gi]
	var lvl := wave_level(wave)
	var champ: bool = str(q[1]) != ""
	var e: Enemy = game.spawn_enemy(str(q[0]), world.free_spot_near(g + Vector3(randf_range(-2, 2), 0, randf_range(-2, 2)), 1.5), lvl, champ, str(q[1]), 800 + wave)
	if e == null:
		return
	e.aggro = true
	e.home = flame.global_position
	e.taunt = flame
	e.taunt_t = 9999.0
	alive.append(e)
	_event("breach:%d" % gi)
	if champ:
		_champ = e
		_event("champ:%d:%d:%s" % [e.net_id, gi, str(q[1]).split(",")[0]])

func _wave_held() -> void:
	var lvl := wave_level(wave)
	var n := _players().size()
	var at := flame.global_position + Vector3(0, 0, 3.0)
	for i in maxi(1, n):
		game.drop_item(Items.gold(int(randf_range(14, 26) * (1.0 + lvl * 0.6) * (1.0 + mini(wave, 30) * 0.15))), at)
	if wave % 2 == 0 or wave == 5:
		game._drop_loot_roll(at, lvl + 1, wave == 5)
	held = wave
	if wave >= WAVES.size() and wave % MILESTONE == 0:
		# every fifth wave held from the tenth: a unique and a heap of gold each
		var cands := Data.UNIQUES.keys().filter(func(u): return int(Data.UNIQUES[u]["lvl"]) <= lvl + 3 and not Data.UNIQUES[u].get("boss_only", false))
		for i in maxi(1, n):
			if not cands.is_empty():
				game.drop_item(Items.make_unique(cands[randi() % cands.size()]), at)
			game.drop_item(Items.gold(int(randf_range(60, 90) * (1.0 + lvl * 0.6))), at)
		_event("milestone:%d" % wave)
	else:
		_event("held:%d" % wave)
	state = "break"
	t = BREAK_SECS
	life = minf(max_life, life + max_life * MEND)
	_sync()

## A hero fed the flame a log (on the host; a partner's comes through Net.vigil_feed).
func feed(frac: float) -> void:
	if not host() or state not in ["count", "wave", "break"]:
		return
	life = minf(max_life, life + max_life * clampf(frac, 0.0, 0.25))
	_event("fed")
	_sync()

## A monster struck the flame (Flame.take_hit, on the host: monsters' AI runs there).
func flame_hit(dmg: float, _from: Vector3) -> void:
	if not host() or state != "wave":
		return
	life -= dmg
	if _hit_fx_t <= 0.0:
		_hit_fx_t = 0.3
		_event("hit")
	if life <= 0.0:
		life = 0.0
		_lose()
	elif _sync_t > 0.15:
		_sync_t = 0.15

func _lose() -> void:
	state = "lost"
	t = END_SECS
	flame.dead = true
	queue = []
	# the wave crumbles to ash with its flame (no loot or experience for it)
	for e in alive:
		if is_instance_valid(e) and not e.dead:
			e._by_rival = true             # (counts as no one's kill)
			e.dmg_tint = Color(0.55, 0.52, 0.5)
			e.take_damage(1e8, 0.0, e.global_position, 0.0, false)
			e._by_rival = false
	alive = []
	left = 0
	held = maxi(0, wave - 1)
	_event("lost:%d:%d" % [held, maxi(1, _players().size())])
	_sync()

# ---------------------------------------------------------------- the HUD (players)
func _draw_hud() -> void:
	if _hud == null:
		_hud = Control.new()
		_hud.name = "vigil_hud"
		_hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_hud.set_anchors_preset(Control.PRESET_CENTER_TOP)
		_hud.offset_top = 48
		game.ui.hud.add_child(_hud)
		_hud_lbl = Label.new()
		_hud_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_hud_lbl.position = Vector2(-360, 0)
		_hud_lbl.size = Vector2(720, 28)
		_hud_lbl.add_theme_font_size_override("font_size", 20)
		_hud_lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0))
		_hud_lbl.add_theme_constant_override("outline_size", 6)
		_hud.add_child(_hud_lbl)
		var back := ColorRect.new()
		back.color = Color(0.06, 0.03, 0.02, 0.85)
		back.position = Vector2(-170, 32)
		back.size = Vector2(340, 12)
		back.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_hud.add_child(back)
		_hud_fill = ColorRect.new()
		_hud_fill.position = Vector2(2, 2)
		_hud_fill.size = Vector2(336, 8)
		_hud_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
		back.add_child(_hud_fill)
	var f := clampf(life / maxf(max_life, 1.0), 0.0, 1.0)
	_hud_fill.size.x = 336.0 * f
	_hud_fill.color = Color(1.0, 0.62, 0.2).lerp(Color(1.0, 0.18, 0.1), clampf(1.0 - f * 2.0, 0.0, 1.0))
	var txt := TITLE.to_upper() + "  ·  "
	match state:
		"idle": txt += "click the flame to begin  ·  endless waves  ·  your best: %d" % FlameBoard.best(game)
		"count": txt += "the dark stirs... %d" % ceili(t)
		"wave": txt += "WAVE %d  ·  %d foe%s left" % [wave, left, "" if left == 1 else "s"]
		"break": txt += "wave %d held  ·  the next in %d  ·  feed it logs" % [wave, ceili(t)]
		"lost": txt += "the flame is out  ·  %d wave%s held" % [held, "" if held == 1 else "s"]
	_hud_lbl.text = txt
	_hud_lbl.add_theme_color_override("font_color", Color(1.0, 0.8, 0.55) if state != "lost" else Color(0.75, 0.7, 0.68))
	_hud.visible = game.playing
