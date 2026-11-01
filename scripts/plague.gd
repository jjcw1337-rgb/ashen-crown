class_name Plague
extends RefCounted
## The Plague Doctor (class "plague"): a plague physician who fights through preparation, poison and fire.
##
## Body: the Meshy plague doctor (assets/models/plague_doctor.glb; tools/blender/plague/prep_plague_mocap.py) on the
## knight's mocap system (Knight.build_mocap, knight_mocap_rig.gd), like the archer's ranger. Every skill and his
## cane attack play their own whole-body library clip (`ACTS`, keyed by attack style), timed so its release lands
## on Anim.impact_at's frame at any attack speed.
##
## Skills (Data.SKILLS "cls": "plague"):
##  Q Toxic Flask (`toxic`): a lobbed green flask; it shatters into a poison cloud.
##  E Volatile Mixture (`volatile`): a red bottle with a lit fuse; a warning ring, then a fire blast.
##     Ignition: a blast that reaches one of his clouds burns it out at once for its remaining poison, as fire.
##  R Pestilent Trap (`trap`): a brass canister set on the ground (up to 2); the first foe over it vents a cloud.
##     Outbreak: an infected foe that springs it makes that cloud infect what it touches.
##  F The Last Epidemic (`epidemic`): smashes his censer (stage 1, "pd_slam"), raises a miasma dome
##     (stage 2, "pd_dome"); inside it foes are poisoned, slowed and infected; it collapses at the end.
##
## Statuses live here, on the caster (one Plague per plague-doctor Hero, `Hero.pd`), not on the enemies: they tick on
## a timer and deal their damage through Enemy.take_damage, which a partner's game forwards to the host. So nothing
## new crosses the network for damage. Guards: one poison per source per foe (refreshed, never stacked); one infection
## per foe, at most `INF_JUMPS` jumps from the cast, immunity `INF_IMMUNE` s after it ends; clouds tick every 0.5 s
## and two clouds of one skill on a foe count once.
##
## Co-op: what partners see. The caster's game sends each visible moment as a short event (`_send`, through
## Net.hero_fx: the host relays it); a partner's game replays it on its puppet of him (`remote`), which builds the
## same flasks, clouds, blasts, traps and dome but never deals damage or sets a status (`ghost`).

const GLB := "res://assets/models/plague_doctor.glb"
const CANE_GLB := "res://assets/models/plague/cane.glb"
const FLASK_GLB := "res://assets/models/plague/flask.glb"
const VOLATILE_GLB := "res://assets/models/plague/volatile.glb"
const TRAP_GLB := "res://assets/models/plague/trap.glb"

const TOXIC := Color(0.45, 0.95, 0.25)       # the poison's green
const MIASMA := Color(0.32, 0.6, 0.18)       # the dome's darker green
const EMBER := Color(1.0, 0.45, 0.12)        # Volatile Mixture's fire
const BRASS := Color(0.85, 0.65, 0.3)
const POISON_TINT := Color(0.55, 1.0, 0.35, 1.0)

## the whole-body clips, by attack style: [[attack progress, clip fraction], ...] (the release key at
## Anim.impact_at's frame for that style)
const ACTS := {
	# the cane: his own three-blow combo (Hero._swipe: swipe1, swipe2, swipe3; their impacts at 0.4 / 0.42 / 0.47), each
	# with its own clip and its own effect (`cane_blow`)
	# 1 Crow's Peck: down low, then the crow-skull handle hooked up into them; a short poison
	"swipe1": {"clip": "peck", "frac": true, "keys": [[0.0, 0.12], [0.4, 0.42], [1.0, 0.7]]},
	# 2 Vial Flick: the wide side-arm swing, flinging drops from a vial across the arc; everyone struck is poisoned
	"swipe2": {"clip": "flick", "frac": true, "keys": [[0.0, 0.15], [0.42, 0.6], [1.0, 0.9]]},
	# 3 Censer Slam: the cane raised in both hands and driven into the ground, cracking a vial: a small burst of miasma
	"swipe3": {"clip": "censer_slam", "frac": true, "keys": [[0.0, 0.3], [0.47, 0.85], [1.0, 1.0]]},
	# felling a tree (Harvest): the axe raised in both hands and driven into the trunk, from the censer slam
	"chop": {"clip": "censer_slam", "frac": true, "keys": [[0.0, 0.3], [0.55, 0.85], [1.0, 1.0]]},
	# the free swings (Hero.free_attack) use the same three
	"over": {"clip": "peck", "frac": true, "keys": [[0.0, 0.12], [0.5, 0.42], [1.0, 0.7]]},
	"back": {"clip": "flick", "frac": true, "keys": [[0.0, 0.15], [0.48, 0.6], [1.0, 0.9]]},
	"thrust": {"clip": "censer_slam", "frac": true, "keys": [[0.0, 0.3], [0.52, 0.85], [1.0, 1.0]]},
	# Toxic Flask: a hand to the belt, the arm back, the over-shoulder throw, recover
	"pd_flask": {"clip": "throw_flask", "frac": true, "keys": [[0.0, 0.05], [0.3, 0.25], [0.55, 0.42], [1.0, 0.6]]},
	# Volatile Mixture: down in a crouch shaking the bottle, the fuse lit, the long throw
	"pd_volatile": {"clip": "throw_volatile", "frac": true, "keys": [[0.0, 0.05], [0.4, 0.45], [0.6, 0.7], [1.0, 0.85]]},
	# Pestilent Trap: down on his haunches, the canister set, up again
	"pd_trap": {"clip": "place_trap", "frac": true, "keys": [[0.0, 0.03], [0.5, 0.27], [1.0, 0.5]]},
	# The Last Epidemic, stage 1: the censer swung up and smashed down
	"pd_slam": {"clip": "slam", "frac": true, "keys": [[0.0, 0.05], [0.6, 0.62], [1.0, 0.95]]},
	# stage 2: both arms raised, the dome rising
	"pd_dome": {"clip": "cast_charged", "frac": true, "keys": [[0.0, 0.3], [0.7, 0.78], [1.0, 0.98]]},
	# a moment's idle: a vial held up to the light (the class stage's fidget)
	"pd_inspect": {"clip": "inspect", "frac": true, "keys": [[0.0, 0.1], [1.0, 0.75]]},
}
## the bottle in his right hand while he winds up a throw (from these points of the move until the release), and the
## skills that need both hands: the cane is put away (hidden) while they play
const HELD := {"pd_flask": [0.08, 0.55, FLASK_GLB], "pd_volatile": [0.12, 0.6, VOLATILE_GLB], "pd_inspect": [0.1, 0.9, FLASK_GLB]}
const HANDS_FREE := ["pd_flask", "pd_volatile", "pd_trap", "pd_slam", "pd_dome", "pd_inspect"]
var held: Node3D = null       # the bottle in his hand
var held_path := ""
var hands_busy := false
## seconds each takes at normal pace (times Data.attack_pace)
const DUR := {"toxic": 0.85, "volatile": 1.25, "trap": 1.0, "epidemic": 1.2, "epidemic2": 1.1}

const CLOUD_R := 3.0
const CLOUD_T := 4.0
const VOLATILE_R := 4.0
const FUSE := 0.6
const TRAP_MAX := 2
const TRAP_LIFE := 30.0
const TRAP_ARM := 0.8
const TRAP_REACH := 1.4
const TRAP_CLOUD_R := 3.5
const TRAP_CLOUD_T := 5.0
const DOME_R := 9.0
const DOME_T := 8.0
const POISON_LINGER := 3.0         # poison keeps ticking this long after leaving a cloud
const INF_T := 6.0
const INF_JUMPS := 6
const INF_SPREAD_R := 5.0
const INF_IMMUNE := 4.0
const TICK := 0.5

var h: Hero
var flasks: Array = []        # in flight: {node, from, to, t, dur, kind}
var fuses: Array = []         # volatile on the ground: {node, pos, t}
var clouds: Array = []        # {node, pos, r, t, src, infect, tick}
var traps: Array = []         # {node, pos, t, armed}
var poison := {}              # enemy instance id -> {e, srcs: {src: [dps, t]}, tick}
var infected := {}            # enemy instance id -> {e, t, gen}
var immune := {}              # enemy instance id -> seconds
var jumps := 0                # infection jumps since the last Last Epidemic
var dome := {}                # {node, pos, t, tick}
var stage2 := false           # the ultimate's second stage waits for the first to end

func _init(hero: Hero) -> void:
	h = hero

## A partner's puppet of him only shows things: the damage and statuses are the caster's game's.
func ghost() -> bool:
	return h.puppet

func _send(ev: String) -> void:
	if not ghost() and h.game != null and h.game.net != null and h.game.net.active:
		h.game.net.hero_fx(ev)

static func _v(p: Vector3) -> String:
	return "%.2f,%.2f,%.2f" % [p.x, p.y, p.z]

static func _pv(t: String) -> Vector3:
	var a := t.split(",")
	return Vector3(float(a[0]), float(a[1]), float(a[2])) if a.size() == 3 else Vector3.ZERO

## A partner's event, replayed on this puppet: "throw|kind|from|to|r", "trap|at", "spring|at|r|outbreak", "dome|at|r|t", "pulse".
func remote(ev: String) -> void:
	var a := ev.split("|")
	match a[0]:
		"throw":
			if a.size() >= 5:
				_launch(a[1], _pv(a[2]), _pv(a[3]), float(a[4]))
		"trap":
			if a.size() >= 2:
				_place_trap(_pv(a[1]))
		"spring":
			if a.size() >= 4:
				var at := _pv(a[1])
				for tp in traps:
					if (tp["pos"] as Vector3).distance_to(at) < 0.6:
						_spring_at(tp, float(a[2]), a[3] == "1", null)
						break
		"dome":
			if a.size() >= 4:
				_dome_at(_pv(a[1]), float(a[2]), float(a[3]))
		"pulse":
			_dome_pulse()
		"cloud":
			if a.size() >= 5:
				_cloud(_pv(a[1]), float(a[2]), float(a[3]), a[4], false)

# ---------------------------------------------------------------- body
static func model_ok() -> bool:
	return ResourceLoader.exists(GLB)

static func build_body() -> Node3D:
	if not model_ok():
		var k := Knight.build(Knight.default_gear())
		k.set_meta("plague", true)
		return k
	var r := Knight.build_mocap(GLB, {
		"relaxed": ["idle", 0.0, "walk", 0.55, "run", 4.25],
		# battle-ready he stands and walks the same: the library's "Idle 2" stretches and yawns, its fight walk is a boxer's
		"combat": ["idle", 0.0, "walk", 0.55, "run", 4.25],
		"acts": ACTS, "meta": "plague"})
	r.set_meta("plague", true)
	r.remove_meta("knight")
	dye(r, COLORS)
	_censer_glow(r)
	return r

## His leather's colour (tools/plague_colors.py recolours the Meshy texture's dark leather by region: coat and cape,
## hat, gloves, boots; the straps, silver mask, brass and vials keep theirs): "oxblood2" = an oxblood coat with a black
## hat, gloves and boots (the default: it reads from the game camera and sets off his green poison), "oxblood" (all
## oxblood), "plague" (deep plague green all over), "plague2" (green coat, black ends), "ash2" (ash-grey coat, black
## ends), "" = Meshy's black.
const COLORS := "oxblood2"

static func dye(r: Node3D, scheme: String) -> void:
	var path := "res://assets/textures/plague/coat_%s.jpg" % scheme
	if scheme == "" or not ResourceLoader.exists(path):
		return
	var tex: Texture2D = load(path)
	for mi in r.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		if m.mesh == null or not (m.mesh is ArrayMesh):
			continue
		for si in m.mesh.get_surface_count():
			var mat := m.mesh.surface_get_material(si) as StandardMaterial3D
			if mat != null and mat.albedo_texture != null and mat.albedo_texture.get_width() >= 1024:
				var dm := mat.duplicate() as StandardMaterial3D
				dm.albedo_texture = tex
				m.set_surface_override_material(si, dm)

## The faint green in his goggles and the censer's leak: a small light at his head, smoke at his hip.
static func _censer_glow(r: Node3D) -> void:
	var J: Dictionary = r.get_meta("j")
	if J.has("at_head"):
		var eye := OmniLight3D.new()
		eye.name = "goggle_glow"
		eye.light_color = TOXIC
		eye.light_energy = 0.35
		eye.omni_range = 0.6
		eye.position = Vector3(0, 0.08, -0.14)
		(J["at_head"] as Node3D).add_child(eye)
	if J.has("at_torso"):
		var smoke := Fx.aura(J["at_torso"], Color(0.4, 0.7, 0.25, 0.5), 10, 0.25, 0.09, 1.6, 0.35, 0.05, 25.0, Vector3(-0.22, -0.55, -0.05), false)
		smoke.name = "censer_smoke"

## His cane (the class's weapon kind "cane"): the Meshy crow-skull cane, else a plain dark staff.
static func cane_model() -> Node3D:
	if ResourceLoader.exists(CANE_GLB):
		var root := Node3D.new()
		root.add_child((load(CANE_GLB) as PackedScene).instantiate())
		return root
	var w := Node3D.new()
	var m := MeshInstance3D.new()
	m.mesh = Geo.cyl(0.014, 0.018, 1.0, 8)
	m.position = Vector3(0, -0.3, 0)
	m.material_override = Mats.mat(Color(0.08, 0.07, 0.07), 0.6, 0.0)
	w.add_child(m)
	return w

static func _prop(path: String, scale := 1.0) -> Node3D:
	var root := Node3D.new()
	if ResourceLoader.exists(path):
		var n: Node3D = (load(path) as PackedScene).instantiate()
		n.scale = Vector3.ONE * scale
		root.add_child(n)
	else:
		var m := MeshInstance3D.new()
		m.mesh = Geo.sph(0.07, 10)
		m.material_override = Mats.mat(TOXIC, 0.2, 0.0)
		root.add_child(m)
	return root

# ---------------------------------------------------------------- casting
static func cast(hero: Hero, id: String, aim: Vector3) -> void:
	var to := (aim - hero.global_position) * Vector3(1, 0, 1)
	var pace := Data.attack_pace(hero.cls)
	match id:
		"toxic":
			hero.atk_aim = hero.global_position + to.limit_length(12.0)
			hero._start_attack("pd_flask", "toxic")
		"volatile":
			hero.atk_aim = hero.global_position + to.limit_length(11.0)
			hero._start_attack("pd_volatile", "volatile")
		"trap":
			hero.atk_aim = hero.global_position + to.limit_length(10.0)
			hero._start_attack("pd_trap", "trap")
		"epidemic":
			hero.atk_aim = hero.global_position
			hero._start_attack("pd_slam", "epidemic")
			if hero.pd != null:
				hero.pd.stage2 = true
	if DUR.has(id):
		hero.atk_dur = float(DUR[id]) * pace

## The release (Hero._impact): true when it was the plague doctor's.
static func impact(hero: Hero) -> bool:
	if hero.pd == null:
		return false
	var p: Plague = hero.pd
	match hero.atk_skill:
		"toxic":
			p._throw("toxic", hero.atk_aim)
		"volatile":
			p._throw("volatile", hero.atk_aim)
		"trap":
			p._set_trap(hero.atk_aim)
		"epidemic":
			p._raise_dome()
		"epidemic2":
			p._dome_pulse()
		_:
			return false
	return true

## Damage numbers, by the hero's level and weapon (the same shape as the warlock's Blight Bolt).
func _base(k_flat: float, k_lvl: float, k_wpn: float, src: String) -> float:
	return (k_flat + h.level * k_lvl + (h.dmg_min + h.dmg_max) * k_wpn) * h.buff_mult() * h.dmg_mult(src)

# ---------------------------------------------------------------- the cane
const PECK_POISON := 2.0
const FLICK_POISON := 3.0
const SLAM_CLOUD_R := 2.0
const SLAM_CLOUD_T := 2.5

## Each blow of his combo leaves its own mark (called by Hero._swipe_impact with the foes it struck):
## Crow's Peck a short poison, Vial Flick a fan of drops that poisons everyone struck, Censer Slam a vial cracked on
## the ground in a small cloud (it lands whether or not anything was struck).
func cane_blow(style: String, struck: Array) -> void:
	if ghost():
		return
	var root: Node3D = h.game.world.fx_root
	var fwd := h.aim_dir()      # the way the blow was aimed (the pointer), not the body's facing
	match style:
		"swipe1", "over":
			for e in struck:
				if not e.dead:
					_poison(e, "cane", PECK_POISON)
					Fx.burst(root, e.global_position + Vector3(0, 1.1 * e.height, 0), TOXIC, 6, 1.6, 0.06, 0.4, true, -2.0)
		"swipe2", "back":
			# the drops fan out across the swing, whether they find anyone or not
			for k in 5:
				var d := fwd.rotated(Vector3.UP, (k - 2) * 0.32)
				Fx.burst(root, h.global_position + Vector3(0, 1.2, 0) + d * 0.7, TOXIC, 5, 4.5, 0.05, 0.45, true, -9.0, 8.0, d + Vector3(0, 0.25, 0))
			Sfx.play_at("drip", h.global_position, -6.0, 1.3)
			for e in struck:
				if not e.dead:
					_poison(e, "cane", FLICK_POISON)
		"swipe3", "thrust":
			var at: Vector3 = h.global_position + fwd * 1.3
			at.y = h.game.world.height_at(at.x, at.z)
			Fx.burst(root, at + Vector3(0, 0.15, 0), Color(0.8, 1.0, 0.85), 10, 3.0, 0.04, 0.35, true, -9.0)   # glass
			Fx.burst(root, at + Vector3(0, 0.3, 0), TOXIC, 18, 2.5, 0.14, 0.6, true, 0.3, 70.0)
			Sfx.play_at("ice_shatter", at, -6.0, 1.5)
			_cloud(at, SLAM_CLOUD_R, SLAM_CLOUD_T, "cane", false)
			_send("cloud|%s|%.2f|%.2f|cane" % [_v(at), SLAM_CLOUD_R, SLAM_CLOUD_T])
			for e in struck:
				if not e.dead:
					_poison(e, "cane", PECK_POISON)

# ---------------------------------------------------------------- flasks
func _throw(kind: String, at: Vector3) -> void:
	var w: World = h.game.world
	var J: Dictionary = h.rig.get_meta("j")
	var from: Vector3 = (J["at_hand_r"] as Node3D).global_position if J.has("at_hand_r") else h.global_position + Vector3(0, 1.6, 0)
	var to := Vector3(at.x, w.height_at(at.x, at.z), at.z)
	var r := CLOUD_R * (1.0 + h.talent("cloud_size") / 100.0) if kind == "toxic" else VOLATILE_R * (1.0 + h.talent("blast_size") / 100.0)
	_launch(kind, from, to, r)
	_send("throw|%s|%s|%s|%.2f" % [kind, _v(from), _v(to), r])

func _launch(kind: String, from: Vector3, to: Vector3, r: float) -> void:
	var w: World = h.game.world
	var n := _prop(FLASK_GLB if kind == "toxic" else VOLATILE_GLB)
	w.fx_root.add_child(n)
	n.global_position = from
	var trail := Fx.aura(n, TOXIC if kind == "toxic" else EMBER, 12, 0.1, 0.05, 0.4, 0.2, 0.03, 30.0)
	trail.local_coords = false
	var dist := Vector2(to.x - from.x, to.z - from.z).length()
	flasks.append({"node": n, "from": from, "to": to, "t": 0.0, "dur": clampf(0.35 + dist * 0.045, 0.35, 0.9), "kind": kind, "r": r})
	Sfx.play("swing_light", -4.0, 0.8)

func _update_flasks(delta: float) -> void:
	for f in flasks.duplicate():
		var n: Node3D = f["node"]
		if not is_instance_valid(n):
			flasks.erase(f)
			continue
		f["t"] = float(f["t"]) + delta
		var a := clampf(float(f["t"]) / float(f["dur"]), 0.0, 1.0)
		var from: Vector3 = f["from"]
		var to: Vector3 = f["to"]
		var p := from.lerp(to, a)
		p.y += sin(a * PI) * (1.2 + from.distance_to(to) * 0.12)
		n.global_position = p
		n.rotation = Vector3(a * 9.0, a * 4.0, 0)
		if a >= 1.0:
			flasks.erase(f)
			n.queue_free()
			if f["kind"] == "toxic":
				_shatter(to, float(f["r"]))
			else:
				_land_volatile(to, float(f["r"]))

## Toxic Flask lands: glass, a splash, and the cloud.
func _shatter(at: Vector3, r: float) -> void:
	var root: Node3D = h.game.world.fx_root
	Fx.burst(root, at + Vector3(0, 0.2, 0), Color(0.8, 1.0, 0.85), 14, 3.5, 0.05, 0.4, true, -9.0)   # glass
	Sfx.play_at("ice_shatter", at, -3.0, 1.35)
	Sfx.play_at("blight_burst", at, -6.0, 1.2)
	if not ghost():
		var dmg := _base(12.0, 3.0, 0.24, "toxic")
		for e in h.game.enemies_near(at, r):
			_damage(e, dmg, at, true)
	_cloud(at, r, CLOUD_T + h.talent("cloud_dur"), "toxic", false)

## Volatile Mixture lands: the bottle rolls to a stop and its fuse burns down inside a warning ring.
func _land_volatile(at: Vector3, r: float) -> void:
	var root: Node3D = h.game.world.fx_root
	var n := _prop(VOLATILE_GLB)
	root.add_child(n)
	n.global_position = at + Vector3(0, 0.06, 0)
	n.rotation = Vector3(PI * 0.5, randf() * TAU, 0)
	var spark := Fx.aura(n, EMBER, 16, 0.6, 0.04, 0.35, 1.0, 0.02, 60.0, Vector3(0, 0.12, 0))
	spark.name = "fuse"
	Fx.telegraph(root, at, r, FUSE, EMBER)
	Sfx.play_at("fuse", at, -2.0)
	fuses.append({"node": n, "pos": at, "t": FUSE, "r": r})

func _update_fuses(delta: float) -> void:
	for f in fuses.duplicate():
		f["t"] = float(f["t"]) - delta
		if float(f["t"]) > 0.0:
			continue
		fuses.erase(f)
		if is_instance_valid(f["node"]):
			(f["node"] as Node3D).queue_free()
		_explode(f["pos"], float(f["r"]))

func _explode(at: Vector3, r: float) -> void:
	var root: Node3D = h.game.world.fx_root
	Fx.burst(root, at + Vector3(0, 0.4, 0), EMBER, 40, 7.0, 0.22, 0.7, true, -3.0)
	Fx.burst(root, at + Vector3(0, 0.6, 0), Color(0.25, 0.2, 0.18), 18, 2.5, 0.4, 1.4, false, 1.2)   # smoke
	Fx.flash(root, at + Vector3(0, 1.0, 0), EMBER, 8.0, 0.35, 9.0)
	Fx.ring(root, at, r, EMBER, 0.45)
	Sfx.play_at("boom", at, -1.0)
	Sfx.play_at("ice_shatter", at, -8.0, 0.9)
	h.game.add_shake(0.35)
	var fire := _base(24.0, 6.5, 0.62, "volatile") if not ghost() else 0.0
	for e in h.game.enemies_near(at, r):
		if e.dead or ghost():
			continue
		var dealt_from := at
		e.take_damage(0.0, fire, dealt_from, 1.2, false)
		e.ignite(fire * 0.12, 3.0)
	# Ignition: a cloud the blast reaches burns out at once, its remaining poison as fire on what stands in it
	for c in clouds.duplicate():
		var cp: Vector3 = c["pos"]
		if Vector2(cp.x - at.x, cp.z - at.z).length() > r + float(c["r"]) * 0.5:
			continue
		var left := float(c["t"]) / TICK
		var burn := _poison_dps(str(c["src"])) * TICK * left * (1.0 + h.talent("ignite_dmg") / 100.0)
		Fx.burst(root, cp + Vector3(0, 0.5, 0), EMBER, 30, 4.0, 0.25, 0.8, true, 1.5, 90.0)
		Fx.flash(root, cp + Vector3(0, 0.8, 0), Color(1.0, 0.7, 0.2), 5.0, 0.3, float(c["r"]) * 2.0)
		Sfx.play_at("fire_erupt", cp, -2.0)
		for e in h.game.enemies_near(cp, float(c["r"])):
			if not e.dead and not ghost():
				e.take_damage(0.0, burn, cp, 0.4, false)
				e.ignite(burn * 0.1, 3.0)
		_end_cloud(c)

# ---------------------------------------------------------------- clouds and poison
func _cloud(at: Vector3, r: float, dur: float, src: String, infect: bool) -> void:
	var node := _cloud_node(at, r, dur, TOXIC if src != "epidemic" else MIASMA)
	clouds.append({"node": node, "pos": at, "r": r, "t": dur, "src": src, "infect": infect, "tick": 0.0})

## A low drifting green fog: a ground ring of particles that hangs and churns, a faint light inside.
func _cloud_node(at: Vector3, r: float, dur: float, col: Color) -> Node3D:
	var root := Node3D.new()
	h.game.world.fx_root.add_child(root)
	root.global_position = at
	var p := GPUParticles3D.new()
	p.amount = int(clampf(r * r * 6.0, 32.0, 420.0))
	p.lifetime = 1.8
	p.preprocess = 0.6
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_RING
	pm.emission_ring_axis = Vector3.UP
	pm.emission_ring_radius = r * 0.85
	pm.emission_ring_inner_radius = 0.0
	pm.emission_ring_height = 0.4
	pm.direction = Vector3.UP
	pm.spread = 80.0
	pm.initial_velocity_min = 0.1
	pm.initial_velocity_max = 0.4
	pm.gravity = Vector3(0, 0.15, 0)
	pm.scale_min = 1.0
	pm.scale_max = 2.0
	var grad := Gradient.new()
	grad.set_color(0, Color(col.r, col.g, col.b, 0.0))
	var fog := Color(col.r * 0.6, col.g * 0.75, col.b * 0.45)
	grad.add_point(0.2, Color(fog.r, fog.g, fog.b, 0.7))
	grad.add_point(0.7, Color(fog.r * 0.8, fog.g * 0.8, fog.b * 0.8, 0.5))
	grad.set_color(grad.get_point_count() - 1, Color(fog.r * 0.6, fog.g * 0.7, fog.b * 0.5, 0.0))
	var gt := GradientTexture1D.new()
	gt.gradient = grad
	pm.color_ramp = gt
	p.process_material = pm
	var q := QuadMesh.new()
	q.size = Vector2(1.1, 1.1) * clampf(r / 3.0, 1.0, 1.8)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.vertex_color_use_as_albedo = true
	mat.albedo_texture = _soft_tex()
	q.material = mat
	p.draw_pass_1 = q
	p.position = Vector3(0, 0.35, 0)
	root.add_child(p)
	var l := OmniLight3D.new()
	l.light_color = col
	l.light_energy = 0.8
	l.omni_range = r * 1.3
	l.position = Vector3(0, 0.8, 0)
	root.add_child(l)
	Fx._free_later(root, dur + 2.0)
	var tw := root.create_tween()
	tw.tween_interval(maxf(dur - 0.6, 0.0))
	tw.tween_callback(func() -> void: p.emitting = false)
	tw.tween_property(l, "light_energy", 0.0, 0.6)
	return root

static var _soft: Texture2D
static func _soft_tex() -> Texture2D:
	if _soft != null:
		return _soft
	var img := Image.create(32, 32, false, Image.FORMAT_RGBA8)
	for y in 32:
		for x in 32:
			var d := Vector2(x - 15.5, y - 15.5).length() / 15.5
			img.set_pixel(x, y, Color(1, 1, 1, smoothstep(1.0, 0.25, d)))
	_soft = ImageTexture.create_from_image(img)
	return _soft

func _end_cloud(c: Dictionary) -> void:
	clouds.erase(c)
	var n = c["node"]
	if is_instance_valid(n):
		for ch in (n as Node3D).get_children():
			if ch is GPUParticles3D:
				(ch as GPUParticles3D).emitting = false
		Fx._free_later(n, 2.0)

func _update_clouds(delta: float) -> void:
	for c in clouds.duplicate():
		c["t"] = float(c["t"]) - delta
		if float(c["t"]) <= 0.0:
			_end_cloud(c)
			continue
		c["tick"] = float(c["tick"]) - delta
		if float(c["tick"]) > 0.0:
			continue
		c["tick"] = TICK
		if ghost():
			continue
		var src: String = c["src"]
		for e in h.game.enemies_near(c["pos"], float(c["r"])):
			if e.dead:
				continue
			_poison(e, src, POISON_LINGER)
			if bool(c["infect"]):
				_infect(e, 0)

## What a second of each source's poison does (Toxic Flask's cloud, the trap's, the dome's, the infection's).
func _poison_dps(src: String) -> float:
	match src:
		"toxic": return _base(9.0, 2.3, 0.16, "toxic")
		"trap": return _base(10.0, 2.5, 0.18, "trap")
		"epidemic": return _base(9.0, 2.3, 0.26, "epidemic")
		"infection": return _base(4.5, 1.3, 0.15, "epidemic")
		"cane": return _base(3.0, 1.0, 0.1, "attack")
	return 0.0

## Poisons a foe from one source: refreshed, never stacked (a second cloud of the same skill does nothing more).
func _poison(e: Enemy, src: String, t: float) -> void:
	if ghost():
		return
	var id := e.get_instance_id()
	if not poison.has(id):
		poison[id] = {"e": e, "srcs": {}, "tick": TICK}
		_tint(e, true)
	var srcs: Dictionary = poison[id]["srcs"]
	var dps := _poison_dps(src) * (1.0 + h.talent("poison_dmg") / 100.0)
	var cur: Array = srcs.get(src, [0.0, 0.0])
	srcs[src] = [maxf(float(cur[0]), dps), maxf(float(cur[1]), t + h.talent("poison_dur"))]

func _update_poison(delta: float) -> void:
	for id in poison.keys():
		var pz: Dictionary = poison[id]
		var e = pz["e"]
		if not is_instance_valid(e) or e.dead:
			poison.erase(id)
			continue
		var srcs: Dictionary = pz["srcs"]
		var total := 0.0
		for s in srcs.keys():
			var v: Array = srcs[s]
			v[1] = float(v[1]) - delta
			if float(v[1]) <= 0.0:
				srcs.erase(s)
			else:
				total += float(v[0])
		if srcs.is_empty():
			poison.erase(id)
			_tint(e, false)
			continue
		pz["tick"] = float(pz["tick"]) - delta
		if float(pz["tick"]) <= 0.0:
			pz["tick"] = TICK
			_damage(e, total * TICK, e.global_position, false)

## Poison and its kin hurt in green numbers, with no blood; armour doesn't stop them (the game's elemental channel).
func _damage(e: Enemy, amount: float, from: Vector3, knock: bool) -> void:
	if ghost() or e == null or e.dead or amount <= 0.0:
		return
	e.dmg_tint = POISON_TINT
	e.soft_hit = not knock          # a poison tick: no flash, no flinch
	e.take_damage(0.0, amount, from, 0.3 if knock else 0.0, false)
	e.soft_hit = false
	e.dmg_tint = Color(0, 0, 0, 0)

## A poisoned foe trails a thin green haze (their own child: it goes when they do).
func _tint(e: Enemy, on: bool) -> void:
	if not is_instance_valid(e):
		return
	var f := e.get_node_or_null("pd_poison")
	if on and f == null and not e.dead:
		var a := Fx.aura(e, TOXIC, 10, 0.35, 0.06, 0.9, 0.5, 0.25 * e.radius + 0.15, 50.0, Vector3(0, e.height * 0.9, 0))
		a.name = "pd_poison"
	elif not on and f != null:
		f.queue_free()

# ---------------------------------------------------------------- infection
## Infects a foe (the dome, an Outbreak cloud, a jump from a dead carrier). One at a time, never on a foe still immune,
## and at most INF_JUMPS jumps after the cast: it can't run through a crowd for ever.
func _infect(e: Enemy, gen: int) -> void:
	if ghost():
		return
	var id := e.get_instance_id()
	if e.dead or infected.has(id) or float(immune.get(id, 0.0)) > 0.0:
		return
	if gen > 0:
		if jumps >= INF_JUMPS + int(h.talent("inf_jumps")):
			return
		jumps += 1
	infected[id] = {"e": e, "t": INF_T + h.talent("inf_dur"), "gen": gen}
	var mark := Fx.aura(e, Color(0.7, 1.0, 0.3), 6, 0.2, 0.1, 0.7, 0.8, 0.1, 20.0, Vector3(0, e.height * 2.0 + 0.2, 0))
	mark.name = "pd_infected"
	var root: Node3D = h.game.world.fx_root
	Fx.burst(root, e.global_position + Vector3(0, e.height, 0), Color(0.7, 1.0, 0.3), 8, 1.5, 0.08, 0.6, true, 0.5)

func _cure(id: int, e) -> void:
	infected.erase(id)
	immune[id] = INF_IMMUNE
	if is_instance_valid(e):
		var m: Node = e.get_node_or_null("pd_infected")
		if m != null:
			m.queue_free()

func _update_infection(delta: float) -> void:
	for id in immune.keys():
		immune[id] = float(immune[id]) - delta
		if float(immune[id]) <= 0.0:
			immune.erase(id)
	for id in infected.keys():
		var inf: Dictionary = infected[id]
		var e = inf["e"]
		if not is_instance_valid(e):
			infected.erase(id)
			continue
		if e.dead:
			# a carrier dies: the disease jumps to the nearest two who aren't carrying it
			var from: Vector3 = e.global_position
			var gen: int = int(inf["gen"]) + 1
			_cure(id, e)
			var near: Array = h.game.enemies_near(from, INF_SPREAD_R).filter(func(o) -> bool: return not o.dead and not infected.has(o.get_instance_id()))
			near.sort_custom(func(a, b) -> bool: return a.global_position.distance_to(from) < b.global_position.distance_to(from))
			for o in near.slice(0, 2):
				_infect(o, gen)
				if infected.has(o.get_instance_id()):
					Fx.bolt(h.game.world.fx_root, from + Vector3(0, 0.8, 0), o.global_position + Vector3(0, o.height, 0), Color(0.6, 1.0, 0.3), 0.3)
			continue
		inf["t"] = float(inf["t"]) - delta
		if float(inf["t"]) <= 0.0:
			_cure(id, e)
			continue
		_poison(e, "infection", 1.0)

# ---------------------------------------------------------------- the trap
func _set_trap(at: Vector3) -> void:
	var w: World = h.game.world
	var g := Vector3(at.x, w.height_at(at.x, at.z), at.z)
	_place_trap(g)
	_send("trap|%s" % _v(g))

func _place_trap(g: Vector3) -> void:
	var w: World = h.game.world
	while traps.size() >= TRAP_MAX + int(h.talent("trap_max")):
		var old: Dictionary = traps.pop_front()
		if is_instance_valid(old["node"]):
			(old["node"] as Node3D).queue_free()
	var n := _prop(TRAP_GLB)
	w.fx_root.add_child(n)
	n.global_position = g
	n.rotation.y = randf() * TAU
	var l := OmniLight3D.new()
	l.light_color = TOXIC
	l.light_energy = 0.0
	l.omni_range = 1.4
	l.position = Vector3(0, 0.3, 0)
	l.name = "glow"
	n.add_child(l)
	n.create_tween().tween_property(l, "light_energy", 0.7, TRAP_ARM)
	traps.append({"node": n, "pos": g, "t": TRAP_LIFE, "arm": TRAP_ARM})
	Fx.ring(w.fx_root, g, 0.7, BRASS, 0.35)
	Sfx.play_at("impact_metal", g, -9.0, 1.2)

func _update_traps(delta: float) -> void:
	for tp in traps.duplicate():
		tp["t"] = float(tp["t"]) - delta
		tp["arm"] = float(tp["arm"]) - delta
		if float(tp["t"]) <= 0.0 or not is_instance_valid(tp["node"]):
			traps.erase(tp)
			if is_instance_valid(tp["node"]):
				(tp["node"] as Node3D).queue_free()
			continue
		if float(tp["arm"]) > 0.0 or ghost():
			continue
		var pos: Vector3 = tp["pos"]
		for e in h.game.enemies_near(pos, TRAP_REACH):
			if e.dead:
				continue
			_spring(tp, e)
			break

## Sprung: a hiss and a burst of green, a short stun, and the cloud. An infected foe makes it an Outbreak.
func _spring(tp: Dictionary, by: Enemy) -> void:
	var r := TRAP_CLOUD_R * (1.0 + h.talent("cloud_size") / 100.0)
	var outbreak := infected.has(by.get_instance_id())
	_send("spring|%s|%.2f|%s" % [_v(tp["pos"]), r, "1" if outbreak else "0"])
	_spring_at(tp, r, outbreak, by)

func _spring_at(tp: Dictionary, r: float, outbreak: bool, _by) -> void:
	traps.erase(tp)
	var pos: Vector3 = tp["pos"]
	var root: Node3D = h.game.world.fx_root
	Fx.burst(root, pos + Vector3(0, 0.3, 0), TOXIC, 30, 5.0, 0.12, 0.7, true, -2.0, 70.0)
	Fx.flash(root, pos + Vector3(0, 0.6, 0), TOXIC, 4.0, 0.3, 5.0)
	Sfx.play_at("blight_burst", pos, -1.0, 0.9)
	Sfx.play_at("impact_metal", pos, -5.0, 0.7)
	h.game.add_shake(0.15)
	for e in h.game.enemies_near(pos, r):
		if not e.dead and not ghost():
			_damage(e, _base(14.0, 3.5, 0.24, "trap"), pos, true)
			e.stun(0.8 + h.talent("trap_stun"))
	_cloud(pos, r, TRAP_CLOUD_T + h.talent("cloud_dur"), "trap", outbreak)
	if outbreak:
		Fx.ring(root, pos, r, Color(0.7, 1.0, 0.3), 0.6)
	var n: Node3D = tp["node"]
	if is_instance_valid(n):
		var tw := n.create_tween()
		tw.tween_property(n, "position:y", n.position.y + 0.25, 0.08)
		tw.tween_property(n, "position:y", n.position.y, 0.15)
		tw.tween_interval(0.6)
		tw.tween_property(n, "scale", Vector3(0.01, 0.01, 0.01), 0.25)
		tw.tween_callback(n.queue_free)

# ---------------------------------------------------------------- The Last Epidemic
## Stage 1's impact: the censer smashed on the ground, the dome rises from it.
func _raise_dome() -> void:
	var g := h.global_position
	jumps = 0
	var r := DOME_R * (1.0 + h.talent("dome_size") / 100.0)
	var dur := DOME_T + h.talent("dome_dur")
	_send("dome|%s|%.2f|%.2f" % [_v(g), r, dur])
	_dome_at(g, r, dur)

func _dome_at(g: Vector3, r: float, dur: float) -> void:
	if not dome.is_empty() and is_instance_valid(dome["node"]):
		(dome["node"] as Node3D).queue_free()
	var root: Node3D = h.game.world.fx_root
	var n := _dome_node(g, r, dur)
	dome = {"node": n, "pos": g, "r": r, "t": dur, "tick": 0.0}
	Fx.burst(root, g + Vector3(0, 0.3, 0), BRASS, 12, 4.0, 0.05, 0.5, true, -9.0)   # the censer's brass
	Fx.burst(root, g + Vector3(0, 0.4, 0), TOXIC, 50, 8.0, 0.2, 0.8, true, -1.0, 80.0)
	Fx.ring(root, g, r, MIASMA, 0.8, 0.5)
	Fx.flash(root, g + Vector3(0, 1.0, 0), TOXIC, 9.0, 0.5, r * 1.5)
	Sfx.play_at("slam", g, 0.0)
	Sfx.play_at("phase_erupt", g, -2.0, 0.8)
	Sfx.duck(-9.0, 1.6)
	h.game.add_shake(0.45 if not ghost() else 0.15)
	for e in h.game.enemies_near(g, r):
		if not e.dead:
			_damage(e, _base(18.0, 5.0, 0.4, "epidemic"), g, true)

## Stage 2's impact: arms raised, the dome swells and every foe inside is marked.
func _dome_pulse() -> void:
	if dome.is_empty():
		return
	_send("pulse")
	var g: Vector3 = dome["pos"]
	Fx.ring(h.game.world.fx_root, g, float(dome["r"]), Color(0.7, 1.0, 0.3), 0.6, 0.8)
	Sfx.play_at("covenant", g, -4.0, 0.7)
	for e in h.game.enemies_near(g, float(dome["r"])):
		_infect(e, 0)

## The dome: a translucent green shell (a sphere cap, rim brighter, slowly churning) over a ring of fog.
func _dome_node(at: Vector3, r: float, dur: float) -> Node3D:
	var root := _cloud_node(at, r * 0.95, dur, MIASMA)
	var m := MeshInstance3D.new()
	var s := SphereMesh.new()
	s.radius = r
	s.height = r * 1.1
	s.is_hemisphere = true
	s.radial_segments = 48
	s.rings = 16
	m.mesh = s
	var sh := ShaderMaterial.new()
	sh.shader = _dome_shader()
	sh.set_shader_parameter("col", MIASMA)
	sh.set_shader_parameter("amt", 0.0)
	m.material_override = sh
	m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	m.name = "shell"
	root.add_child(m)
	var edge := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = r - 0.12
	tm.outer_radius = r + 0.12
	tm.rings = 64
	edge.mesh = tm
	edge.scale = Vector3(1, 0.25, 1)
	edge.position = Vector3(0, 0.05, 0)
	var em := StandardMaterial3D.new()
	em.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	em.albedo_color = Color(0.55, 1.0, 0.25)
	edge.material_override = em
	edge.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	edge.name = "edge"
	root.add_child(edge)
	var tw := m.create_tween()
	tw.tween_method(func(v: float) -> void: sh.set_shader_parameter("amt", v), 0.0, 1.0, 0.5)
	return root

static var _dsh: Shader
static func _dome_shader() -> Shader:
	if _dsh != null:
		return _dsh
	_dsh = Shader.new()
	_dsh.code = """
shader_type spatial;
render_mode unshaded, blend_mix, cull_disabled, depth_draw_never;
uniform vec4 col : source_color;
uniform float amt = 1.0;
varying vec3 lp;
void vertex() { lp = VERTEX; }
float n3(vec3 p) { return fract(sin(dot(floor(p), vec3(12.9898, 78.233, 37.719))) * 43758.5453); }
float noise(vec3 p) {
	vec3 i = floor(p); vec3 f = fract(p); f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(n3(i), n3(i + vec3(1,0,0)), f.x), mix(n3(i + vec3(0,1,0)), n3(i + vec3(1,1,0)), f.x), f.y),
		mix(mix(n3(i + vec3(0,0,1)), n3(i + vec3(1,0,1)), f.x), mix(n3(i + vec3(0,1,1)), n3(i + vec3(1,1,1)), f.x), f.y), f.z);
}
void fragment() {
	float rim = pow(1.0 - abs(dot(NORMAL, VIEW)), 2.5);
	float churn = noise(lp * 1.3 + vec3(0.0, TIME * 0.6, TIME * 0.3)) * 0.6 + 0.4;
	float base = smoothstep(0.0, 0.6, lp.y) * 0.3 + 0.7;
	ALBEDO = mix(col.rgb * 0.55, col.rgb * 1.5 + vec3(0.08, 0.12, 0.0), rim);
	ALPHA = clamp((rim * 0.6 + 0.14) * churn * base * amt, 0.0, 0.85);
}
"""
	return _dsh

func _update_dome(delta: float) -> void:
	if dome.is_empty():
		return
	dome["t"] = float(dome["t"]) - delta
	var g: Vector3 = dome["pos"]
	var r: float = dome["r"]
	if float(dome["t"]) <= 0.0:
		# the collapse: everything inside takes one last blow
		var root: Node3D = h.game.world.fx_root
		Fx.burst(root, g + Vector3(0, 2.0, 0), TOXIC, 60, 9.0, 0.2, 0.7, true, -6.0)
		Fx.flash(root, g + Vector3(0, 1.0, 0), TOXIC, 7.0, 0.4, r * 1.4)
		Sfx.play_at("shade_implode", g, -1.0, 0.8)
		h.game.add_shake(0.3 if not ghost() else 0.1)
		for e in h.game.enemies_near(g, r):
			if not e.dead:
				_damage(e, _base(25.0, 7.0, 0.5, "epidemic"), g, true)
		var n = dome["node"]
		if is_instance_valid(n):
			for part in ["shell", "edge"]:
				var sn: Node = (n as Node3D).get_node_or_null(part)
				if sn != null:
					sn.queue_free()
		dome = {}
		return
	dome["tick"] = float(dome["tick"]) - delta
	if float(dome["tick"]) > 0.0:
		return
	dome["tick"] = TICK
	if ghost():
		return
	for e in h.game.enemies_near(g, r):
		if e.dead:
			continue
		_poison(e, "epidemic", POISON_LINGER)
		_infect(e, 0)
		# slowed in the miasma (the host's AI reads chill; a partner's goes there through Enemy.chill)
		if e.remote:
			e.chill(0.35, 0.7)
		else:
			e.chill_k = maxf(e.chill_k if e.chill_t > 0.0 else 0.0, 0.35)
			e.chill_t = maxf(e.chill_t, 0.7)

# ---------------------------------------------------------------- every frame
## Standing about with the cane away for a while, he takes out a vial and peers at it ("pd_inspect", 3.2 s), every
## IDLE_EVERY seconds or so. Only the pose: any step, attack or cast ends it at once.
const IDLE_EVERY := 10.0
const INSPECT_T := 3.2
var idle_t := 0.0
var fid_a := -1.0
func idle_fidget(st: Dictionary, delta: float) -> void:
	var still: bool = float(st.get("move", 0.0)) < 0.05 and float(st.get("atk", -1.0)) < 0.0 and float(st.get("draw", 0.0)) < 0.05 \
		and not h.dead and not h.moving and float(st.get("hit", 0.0)) < 0.1
	if not still:
		idle_t = 0.0
		fid_a = -1.0
		return
	idle_t += delta
	if idle_t < IDLE_EVERY:
		fid_a = -1.0
		return
	fid_a = (idle_t - IDLE_EVERY) / INSPECT_T
	if fid_a >= 1.0:
		idle_t = randf_range(-4.0, 2.0)
		fid_a = -1.0
		return
	st["style"] = "pd_inspect"
	st["atk"] = fid_a

## What his hands hold this frame: the bottle he's about to throw, and the cane only when no skill needs his hands
## (his own game from the attack, a partner's puppet from the pose it was sent).
func _hands() -> void:
	if h.rig == null or not h.rig.has_meta("j"):
		return
	var style: String = h.atk_style if not h.puppet else str(h.net_st.get("style", ""))
	var a: float = (h.atk_t / h.atk_dur if h.atk_t >= 0.0 else -1.0) if not h.puppet else float(h.net_st.get("atk", -1.0))
	if not h.puppet and fid_a >= 0.0:
		style = "pd_inspect"
		a = fid_a
	var want := ""
	if a >= 0.0 and HELD.has(style):
		var spec: Array = HELD[style]
		if a >= float(spec[0]) and a < float(spec[1]):
			want = spec[2]
	if want != held_path:
		if held != null and is_instance_valid(held):
			held.queue_free()
		held = null
		held_path = want
		var J: Dictionary = h.rig.get_meta("j")
		if want != "" and J.has("at_hand_r"):
			held = _prop(want, 0.9)
			held.position = Vector3(0, -0.1, -0.02)
			(J["at_hand_r"] as Node3D).add_child(held)
	hands_busy = a >= 0.0 and HANDS_FREE.has(style)    # Hero._carry_weapon hides the cane meanwhile
	if h.puppet and h.weapon_node != null and is_instance_valid(h.weapon_node):
		h.weapon_node.visible = not hands_busy           # a puppet has no weapon carry of its own

func update(delta: float) -> void:
	if h.game == null or h.game.world == null:
		return
	_hands()
	# the ultimate's second stage follows the first
	if ghost():
		stage2 = false
	if stage2 and h.atk_t < 0.0 and not h.dead:
		stage2 = false
		if not dome.is_empty():
			h._start_attack("pd_dome", "epidemic2")
			h.atk_dur = float(DUR["epidemic2"]) * Data.attack_pace(h.cls)
	elif stage2 and h.atk_skill != "epidemic":
		stage2 = false
	_update_flasks(delta)
	_update_fuses(delta)
	_update_clouds(delta)
	_update_traps(delta)
	_update_dome(delta)
	_update_infection(delta)
	_update_poison(delta)

## Everything on the ground goes (a zone change, a class change, death).
func clear() -> void:
	for arr in [flasks, fuses, clouds, traps]:
		for x in arr:
			if is_instance_valid(x["node"]):
				(x["node"] as Node3D).queue_free()
		arr.clear()
	if not dome.is_empty() and is_instance_valid(dome["node"]):
		(dome["node"] as Node3D).queue_free()
	dome = {}
	for id in poison.keys():
		_tint(poison[id]["e"], false)
	poison.clear()
	for id in infected.keys():
		var e = infected[id]["e"]
		if is_instance_valid(e):
			var m: Node = e.get_node_or_null("pd_infected")
			if m != null:
				m.queue_free()
	infected.clear()
	immune.clear()
	stage2 = false
