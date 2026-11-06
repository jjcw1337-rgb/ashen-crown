class_name Plague
extends RefCounted
## The Plague Doctor (class "plague"): a plague physician who wins through disease, deception and position.
##
## Body: the Meshy plague doctor (assets/models/plague_doctor.glb; tools/blender/plague/prep_plague_mocap.py) on the
## knight's mocap system (Knight.build_mocap, knight_mocap_rig.gd), like the archer's ranger. Every skill and his
## cane attack play their own whole-body library clip (`ACTS`, keyed by attack style), timed so its release lands
## on Anim.impact_at's frame at any attack speed.
##
## Skills (Data.SKILLS "cls": "plague"; the PvP kit of 2026-11-01, see the project doc "plague kit overhaul plan"):
##  Q Pestilence Vial (`toxic`): a lobbed glass vial (landing ring for everyone); a small hit and a contaminated pool.
##  E Swarmcraft (`swarm`): a swarm of plague flies sent to a point (6 m/s, never homing), hovering 6 s; recast
##     twice to send it on. Inside: light damage, Harried (attacks and casts slower), revealed through fog. A dodge
##     roll through it scatters it. Its cooldown starts when it goes back to its reliquary.
##  R Corpse Bloom (`bloom`): a seed driven into the ground grows for 1 s, then breathes for 6 s: every 2 s a
##     contracting ring, then a spore pulse; anyone who hasn't moved since the ring began is snared by its roots.
##  F Fog of the Forgotten (`fog`): the censer dashed at his feet and a hop back; pale fog 6 m across for 6 s. Players
##     outside can't see anyone inside; inside, everyone within 3.5 m is seen. He moves faster in it; attacking from
##     it reveals him for a moment; Feverish or swarm-marked foes show through it.
##  G Transfusion (`transfusion`): the needle of his back apparatus in his arm: 2 s of 45% less damage, moving at 70%,
##     cleansed of slows, snares and Blight; damage soaked fills the tanks and heals him after (at most 15% of his
##     life). Attacking ends it early. No CC immunity.
##  V The Last Experiment (`experiment`): the vat slammed down (an 8 m warning ring at once), cranked for 2.5 s (a
##     stun or walking away interrupts it: it bursts at 5 m), then the homunculus bursts out and the ring becomes a
##     quarantine for 7 s: spore rain, Blight and a slow while inside, the creature lumbering at the nearest foe and
##     spewing cones (telegraphed). It collapses at the end.
## Blight: each DIFFERENT skill of his that touches a foe adds a stack (max 3, 6 s); at 3 the foe turns Feverish for
## 4 s: seen glowing by everyone, healing -40% (PvP), visible through his fog; no burst. Monsters take +20% from his
## poison while Feverish.
##
## Statuses live here, on the caster (one Plague per plague-doctor Hero, `Hero.pd`), not on the enemies: they tick on
## a timer and deal their damage through Enemy.take_damage, which a partner's game forwards to the host and a
## player's stand-in forwards to the Battlegrounds server; slows, snares, harrying and reveals on players go through
## PvpStatus.send (the server checks them, with diminishing returns).
##
## Co-op: what partners see. The caster's game sends each visible moment as a short event (`_send`, through
## Net.hero_fx: the host relays it); a partner's game replays it on its puppet of him (`remote`), which builds the
## same vials, pools, swarm, bloom, fog, apparatus and experiment but never deals damage or sets a status (`ghost`).

const GLB := "res://assets/models/plague_doctor.glb"
const CANE_GLB := "res://assets/models/plague/cane.glb"

const TOXIC := Color(0.45, 0.95, 0.25)       # the poison's green
const MIASMA := Color(0.32, 0.6, 0.18)
const BRASS := Color(0.85, 0.65, 0.3)
const POISON_TINT := Color(0.55, 1.0, 0.35, 1.0)
const FEVER := Color(0.95, 0.85, 0.35)

## Old saves' bindings of the retired skills become the new ones in their keys (Hero.from_save).
const OLD_IDS := {"volatile": "swarm", "trap": "bloom", "epidemic": "experiment"}

## the whole-body clips, by attack style: [[attack progress, clip fraction], ...] (the release key at
## Anim.impact_at's frame for that style)
const ACTS := {
	# the cane: his own three-blow combo (Hero._swipe: swipe1, swipe2, swipe3; their impacts at 0.4 / 0.42 / 0.47), each
	# with its own clip and its own effect (`cane_blow`)
	"swipe1": {"clip": "peck", "frac": true, "keys": [[0.0, 0.12], [0.4, 0.42], [1.0, 0.7]]},
	"swipe2": {"clip": "flick", "frac": true, "keys": [[0.0, 0.15], [0.42, 0.6], [1.0, 0.9]]},
	"swipe3": {"clip": "censer_slam", "frac": true, "keys": [[0.0, 0.3], [0.47, 0.85], [1.0, 1.0]]},
	# felling a tree (Harvest): the axe raised in both hands and driven into the trunk, from the censer slam
	"chop": {"clip": "censer_slam", "frac": true, "keys": [[0.0, 0.3], [0.55, 0.85], [1.0, 1.0]]},
	"over": {"clip": "peck", "frac": true, "keys": [[0.0, 0.12], [0.5, 0.42], [1.0, 0.7]]},
	"back": {"clip": "flick", "frac": true, "keys": [[0.0, 0.15], [0.48, 0.6], [1.0, 0.9]]},
	"thrust": {"clip": "censer_slam", "frac": true, "keys": [[0.0, 0.3], [0.52, 0.85], [1.0, 1.0]]},
	# Pestilence Vial: a hand to the bandolier, the arm back, the over-shoulder throw, recover
	"pd_flask": {"clip": "throw_flask", "frac": true, "keys": [[0.0, 0.05], [0.3, 0.25], [0.55, 0.42], [1.0, 0.6]]},
	# Swarmcraft: the reliquary held out, the flies pour from it
	"pd_swarm": {"clip": "cast", "frac": true, "keys": [[0.0, 0.08], [0.5, 0.45], [1.0, 0.8]]},
	# Corpse Bloom: down on one knee, the seed driven into the soil
	"pd_bloom": {"clip": "kneel", "frac": true, "keys": [[0.0, 0.05], [0.55, 0.4], [1.0, 0.75]]},
	# Fog of the Forgotten: the censer dashed down at his feet (the hop back is movement)
	"pd_fog": {"clip": "throw_down", "frac": true, "keys": [[0.0, 0.08], [0.45, 0.5], [1.0, 0.85]]},
	# Transfusion: he shudders as the needle goes in
	"pd_transfuse": {"clip": "stagger", "frac": true, "keys": [[0.0, 0.0], [0.45, 0.35], [1.0, 0.8]]},
	# The Last Experiment, stage 1: the vat slammed down; stage 2: cranking it, arms working
	"pd_slam": {"clip": "slam", "frac": true, "keys": [[0.0, 0.05], [0.6, 0.62], [1.0, 0.95]]},
	"pd_crank": {"clip": "cast_charged", "frac": true, "keys": [[0.0, 0.15], [0.25, 0.4], [0.5, 0.55], [0.75, 0.4], [0.97, 0.78], [1.0, 0.85]]},
	# a moment's idle: a vial held up to the light (the class stage's fidget)
	"pd_inspect": {"clip": "inspect", "frac": true, "keys": [[0.0, 0.1], [1.0, 0.75]]},
}
## what his right hand holds while a move plays (from these points until the release; "vial" = Pestilence Vial's glass
## vial with its sloshing liquid, PlagueVialFx.vial, in the next recipe's colour; "reliquary" = Swarmcraft's Meshy
## reliquary, "seed" = Corpse Bloom's Meshy seed-syringe, "censer" = Fog of the Forgotten's Meshy censer until he dashes
## it down), and the moves that need both hands (the cane is put away while they play)
const HELD := {"pd_flask": [0.08, 0.55, "vial"], "pd_inspect": [0.1, 0.9, "vial"], "pd_swarm": [0.05, 0.85, "reliquary"],
	"pd_bloom": [0.1, 0.6, "seed"], "pd_fog": [0.04, 0.45, "censer"]}
const HANDS_FREE := ["pd_flask", "pd_swarm", "pd_bloom", "pd_fog", "pd_transfuse", "pd_slam", "pd_crank", "pd_inspect"]
var held: Node3D = null
var held_path := ""
var held_slosh: PlagueVialFx.Slosh = null
var hands_busy := false
## seconds each takes at normal pace (times Data.attack_pace)
const DUR := {"toxic": 0.85, "swarm": 0.8, "bloom": 0.95, "fog": 0.6, "transfusion": 0.55, "experiment": 0.9, "crank": 2.5}

# Pestilence Vial
const CLOUD_R := 2.6
const CLOUD_T := 3.5
const VIAL_LINGER := 2.0
# Swarmcraft
const SWARM_R := 3.0
const SWARM_T := 6.0
const SWARM_SPEED := 6.0
const SWARM_RANGE := 13.0
const SWARM_REDIRECTS := 2
const SWARM_SCATTER := 1.5
const HARRIED := 0.25
# Corpse Bloom
const BLOOM_R := 3.5
const BLOOM_GROW := 1.0
const BLOOM_T := 6.0
const BLOOM_EVERY := 2.0
const BLOOM_WARN := 0.6
const BLOOM_SNARE := 0.6
const BLOOM_STILL := 0.3      # moved less than this since the ring began = standing still
# Fog of the Forgotten
const FOG_R := 6.0
const FOG_T := 6.0
const FOG_SEE := 3.5
const FOG_HOP := 4.0
const FOG_SPEED := 1.25
const FOG_REVEAL := 1.0
# Transfusion
const TRANS_T := 2.0
const TRANS_DR := 0.45
const TRANS_MOVE := 0.7
const TRANS_CAP := 0.15
const TRANS_HEAL_T := 4.0
# The Last Experiment
const EXP_R := 8.0
const EXP_R_SMALL := 5.0
const EXP_T := 7.0
const EXP_SLOW := 0.2
const EXP_EVERY := 2.0
const SPEW_EVERY := 2.4
const SPEW_WARN := 1.0
const SPEW_LEN := 4.0
const SPEW_HALF := 0.45       # radians each side
# Blight / Fever
const BLIGHT_T := 6.0
const FEVER_T := 4.0
const POISON_LINGER := 3.0
const TICK := 0.5

var h: Hero
var recipe := 0
var vial_flights: Array = []
var clouds: Array = []        # {node, pos, r, t, src, tick}
var poison := {}              # enemy instance id -> {e, srcs: {src: [dps, t]}, tick}
var blight := {}              # enemy instance id -> {e, srcs: {src: t}, fever: t}
var swarm := {}               # {node, pos, to, t, left, tick, scatter}
var blooms: Array = []        # {node, pos, r, t, pulse, warn, marks}
var fogs: Array = []          # {node, pos, r, t}
var reveal_t := 0.0           # he attacked from his fog: seen for this long
var trans := {}               # {t, soaked, node}
var lab := {}                 # {stage, node, pos, r, t, tick, start, creature}
var crank_from := Vector3.ZERO
## PvP: his bloom, vat and creature can be broken by other players (`PvpObjects`); each has an id here ("oid" in its
## entry, the creature's "coid" in `lab`), sent with the event that makes it, and its blows left ("left"/"cleft"); a
## ghost keeps a stand-in on each ("proxy"/"cproxy").
var next_oid := 0

func _init(hero: Hero) -> void:
	h = hero

## A partner's puppet of him only shows things: the damage and statuses are the caster's game's.
func ghost() -> bool:
	return h.puppet

func _send(ev: String) -> void:
	if not ghost() and h.game != null and h.game.net != null and h.game.net.pd_tap.is_valid():
		h.game.net.pd_tap.call(ev)
	if not ghost() and h.game != null and h.game.net != null and h.game.net.active:
		h.game.net.hero_fx(ev)

static func _v(p: Vector3) -> String:
	return "%.2f,%.2f,%.2f" % [p.x, p.y, p.z]

static func _pv(t: String) -> Vector3:
	var a := t.split(",")
	return Vector3(float(a[0]), float(a[1]), float(a[2])) if a.size() == 3 else Vector3.ZERO

## A partner's event, replayed on this puppet.
func remote(ev: String) -> void:
	var a := ev.split("|")
	match a[0]:
		"throw":
			if a.size() >= 6:
				recipe = int(a[5])
				_launch(_pv(a[2]), _pv(a[3]), float(a[4]))
		"curse":
			if a.size() >= 3:
				_curse_fx(_pv(a[1]), _pv(a[2]), null)
		"swarm":
			if a.size() >= 3:
				_swarm_start(_pv(a[1]), _pv(a[2]))
		"swarm_to":
			if a.size() >= 2 and not swarm.is_empty():
				swarm["to"] = _pv(a[1])
				PlagueSwarmFx.redirect(swarm["node"], _pv(a[1]))
		"swarm_scatter":
			if not swarm.is_empty():
				swarm["scatter"] = SWARM_SCATTER
				PlagueSwarmFx.scatter(swarm["node"])
		"swarm_end":
			_swarm_end(false)
		"bloom":
			if a.size() >= 3:
				_bloom_at(_pv(a[1]), float(a[2]), int(a[3]) if a.size() >= 4 else 0)
		"obj":
			if a.size() >= 3:
				_obj_left(int(a[1]), int(a[2]))
		"fog":
			if a.size() >= 3:
				_fog_at(_pv(a[1]), float(a[2]))
		"reveal":
			reveal_t = FOG_REVEAL
		"trans":
			_trans_start()
		"trans_end":
			if a.size() >= 2:
				_trans_end(float(a[1]))
		"vat":
			if a.size() >= 3:
				_vat_at(_pv(a[1]), float(a[2]), int(a[3]) if a.size() >= 4 else 0)
		"burst":
			if a.size() >= 2:
				_exp_burst(float(a[1]), int(a[2]) if a.size() >= 3 else 0)
		"spew":
			if a.size() >= 3 and not lab.is_empty():
				PlagueExperimentFx.spew(lab, _pv(a[1]), _pv(a[2]), SPEW_WARN, SPEW_LEN, SPEW_HALF)
		"exp_end":
			_exp_end()
		"cloud":
			if a.size() >= 5:
				_cloud(_pv(a[1]), float(a[2]), float(a[3]), a[4])

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
		"combat": ["idle", 0.0, "walk", 0.55, "run", 4.25],
		"acts": ACTS, "meta": "plague"})
	r.set_meta("plague", true)
	r.remove_meta("knight")
	dye(r, COLORS)
	_censer_glow(r)
	return r

## His leather's colour (tools/plague_colors.py recolours the Meshy texture's dark leather by region): "oxblood2" =
## an oxblood coat with a black hat, gloves and boots (the default), "oxblood", "plague", "plague2", "ash2", "" =
## Meshy's black.
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
		root.add_child(ResCache.inst(CANE_GLB))
		return root
	var w := Node3D.new()
	var m := MeshInstance3D.new()
	m.mesh = Geo.cyl(0.014, 0.018, 1.0, 8)
	m.position = Vector3(0, -0.3, 0)
	m.material_override = Mats.mat(Color(0.08, 0.07, 0.07), 0.6, 0.0)
	w.add_child(m)
	return w

# ---------------------------------------------------------------- casting
## Skill checks before anything is spent (ClassSkills.can_cast): Swarmcraft while the swarm is out is a recast
## (sends it on, free); nothing else is refused.
static func can_cast(hero: Hero, id: String, aim: Vector3) -> bool:
	if hero.pd == null:
		return true
	var p: Plague = hero.pd
	if id == "swarm" and not p.swarm.is_empty():
		p._swarm_redirect(aim)
		return false
	return true

static func cast(hero: Hero, id: String, aim: Vector3) -> void:
	var to := (aim - hero.global_position) * Vector3(1, 0, 1)
	var p: Plague = hero.pd
	if p != null and not p.trans.is_empty():
		p._trans_end_early()
	match id:
		"toxic":
			hero.atk_aim = hero.global_position + to.limit_length(12.0)
			hero._start_attack("pd_flask", "toxic")
		"swarm":
			hero.atk_aim = hero.global_position + to.limit_length(SWARM_RANGE)
			hero._start_attack("pd_swarm", "swarm")
			hero.cds["swarm"] = 0.0      # its cooldown starts when the swarm goes home (`_swarm_end`)
		"bloom":
			hero.atk_aim = hero.global_position + to.limit_length(9.0)
			hero._start_attack("pd_bloom", "bloom")
		"fog":
			hero.atk_aim = hero.global_position + (to.normalized() if to.length() > 0.1 else -hero.facing())
			hero._start_attack("pd_fog", "fog")
		"transfusion":
			hero.atk_aim = hero.global_position
			hero._start_attack("pd_transfuse", "transfusion")
		"experiment":
			hero.atk_aim = hero.global_position + to.limit_length(7.0)
			hero._start_attack("pd_slam", "experiment")
		# a run's skills (Data.RUN_SKILLS)
		"p_miasma":
			hero.atk_aim = hero.global_position
			hero._start_attack("pd_slam", "p_miasma")
		"p_spread":
			hero.atk_aim = hero.global_position + to.limit_length(14.0)
			hero._start_attack("pd_flask", "p_spread")
		"p_leech":
			hero.atk_aim = hero.global_position + to.limit_length(12.0)
			hero._start_attack("pd_flask", "p_leech")
	if DUR.has(id):
		hero.atk_dur = float(DUR[id]) * Data.attack_pace(hero.cls) * (PvpStatus.act_mult(hero) if not hero.pvs.is_empty() else 1.0)

## The release (Hero._impact): true when it was the plague doctor's.
static func impact(hero: Hero) -> bool:
	if hero.pd == null:
		return false
	var p: Plague = hero.pd
	match hero.atk_skill:
		"toxic":
			p._throw(hero.atk_aim)
		"swarm":
			p._swarm_cast(hero.atk_aim)
		"bloom":
			p._plant(hero.atk_aim)
		"fog":
			p._fog_cast(hero.atk_aim)
		"transfusion":
			p._trans_cast()
		"experiment":
			p._vat_cast(hero.atk_aim)
		"crank":
			p._exp_finish()
		"p_miasma":
			p._miasma()
		"p_spread":
			p._curse(hero.atk_aim)
		"p_leech":
			p._throw_leeches(hero.atk_aim)
		_:
			return false
	return true

## Damage numbers, by the hero's level and weapon (the same shape as the warlock's Blight Bolt).
func _base(k_flat: float, k_lvl: float, k_wpn: float, src: String) -> float:
	return (k_flat + h.level * k_lvl + (h.dmg_min + h.dmg_max) * k_wpn) * h.buff_mult() * h.dmg_mult(src)

## Foes his skills can touch round a point (monsters and, in the Battlegrounds, other players' stand-ins).
func _foes(at: Vector3, r: float) -> Array:
	if h.game == null:
		return []
	return h.game.enemies_near(at, r).filter(func(e) -> bool: return not e.dead)

# ---------------------------------------------------------------- the cane
const PECK_POISON := 2.0
const FLICK_POISON := 3.0
const SLAM_CLOUD_R := 2.0
const SLAM_CLOUD_T := 2.5

## Each blow of his combo leaves its own mark (called by Hero._swipe_impact with the foes it struck).
func cane_blow(style: String, struck: Array) -> void:
	if ghost():
		return
	var root: Node3D = h.game.world.fx_root
	var fwd := h.aim_dir()
	if fogs.size() > 0 and _in_fog(h.global_position):
		_reveal_self()
	match style:
		"swipe1", "over":
			for e in struck:
				if not e.dead:
					_poison(e, "cane", PECK_POISON)
					Fx.burst(root, e.global_position + Vector3(0, 1.1 * e.height, 0), TOXIC, 6, 1.6, 0.06, 0.4, true, -2.0)
		"swipe2", "back":
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
			Fx.burst(root, at + Vector3(0, 0.15, 0), Color(0.8, 1.0, 0.85), 10, 3.0, 0.04, 0.35, true, -9.0)
			Fx.burst(root, at + Vector3(0, 0.3, 0), TOXIC, 18, 2.5, 0.14, 0.6, true, 0.3, 70.0)
			Sfx.play_at("ice_shatter", at, -6.0, 1.5)
			_cloud(at, SLAM_CLOUD_R, SLAM_CLOUD_T, "cane")
			_send("cloud|%s|%.2f|%.2f|cane" % [_v(at), SLAM_CLOUD_R, SLAM_CLOUD_T])
			for e in struck:
				if not e.dead:
					_poison(e, "cane", PECK_POISON)

# ---------------------------------------------------------------- Q Pestilence Vial
func _throw(at: Vector3) -> void:
	var w: World = h.game.world
	var J: Dictionary = h.rig.get_meta("j")
	var from: Vector3 = (J["at_hand_r"] as Node3D).global_position if J.has("at_hand_r") else h.global_position + Vector3(0, 1.6, 0)
	var to := Vector3(at.x, w.height_at(at.x, at.z), at.z)
	var r := CLOUD_R * (1.0 + h.talent("cloud_size") / 100.0)
	_send("throw|toxic|%s|%s|%.2f|%d" % [_v(from), _v(to), r, recipe])
	_reveal_if_fogged()
	_launch(from, to, r)
	if h.talent("vial_twin") > 0.0:
		# Double Dose (a run's talent): a second vial beside the first
		var side := (to - from).cross(Vector3.UP).normalized() * (r * 1.3)
		var to2 := to + side
		to2.y = w.height_at(to2.x, to2.z)
		_send("throw|toxic|%s|%s|%.2f|%d" % [_v(from), _v(to2), r, recipe])
		_launch(from, to2, r)

func _launch(from: Vector3, to: Vector3, r: float) -> void:
	var w: World = h.game.world
	var dist := Vector2(to.x - from.x, to.z - from.z).length()
	var dur := clampf(0.45 + dist * 0.03, 0.45, 0.8)
	var ri := recipe
	recipe = (recipe + 1) % PlagueVialFx.RECIPES.size()
	var f := PlagueVialFx.Flight.new(w.fx_root, from, to, ri, dur)
	PlagueVialFx.landing_ring(w.fx_root, w, to, r, ri, dur)
	vial_flights.append({"f": f, "from": from, "to": to, "r": r, "ri": ri})
	Sfx.play_at("swing_light", from, -5.0, 0.75)

func _update_vials(delta: float) -> void:
	for v in vial_flights.duplicate():
		var f: PlagueVialFx.Flight = v["f"]
		if f.step(delta):
			vial_flights.erase(v)
			if is_instance_valid(f.node):
				f.node.queue_free()
			_shatter(v["to"], float(v["r"]), int(v["ri"]), (v["to"] as Vector3) - (v["from"] as Vector3))
			if v.has("leech"):
				_leech_pool(v["to"])

# ---------------------------------------------------------------- a run's skills (Data.RUN_SKILLS)
const MIASMA_R := 4.5
const MIASMA_T := 4.0
const CURSE_T := 6.0
const CURSE_R := 4.0
const CURSE_BURST := 5.0
const LEECH_R := 3.0
const LEECH_T := 5.0
const LEECH_HEAL := 1.5        # % of his life a second, for each foe in the pool (at most three count)
var curses := {}               # {instance id: {"e", "t", "tick"}}

## Miasma: the censer smashed at his feet, a wide cloud of plague (the cane slam's cloud, larger and longer).
func _miasma() -> void:
	var at := h.global_position
	at.y = h.game.world.height_at(at.x, at.z)
	var r := MIASMA_R * (1.0 + h.talent("miasma_r") / 100.0)
	_cloud(at, r, MIASMA_T, "toxic")
	if h.talent("miasma_slow") > 0.0 and not ghost():
		clouds[-1]["slow"] = true       # (Choking Miasma: its ticks slow, _update_clouds)
	_send("cloud|%s|%.2f|%.2f|toxic" % [_v(at), r, MIASMA_T])
	var root: Node3D = h.game.world.fx_root
	PlagueSmoke.puffs(root, at + Vector3(0, 0.3, 0), PlagueSmoke.FOG, Color(TOXIC.r, TOXIC.g, TOXIC.b, 0.7), 16, MIASMA_R * 0.7, 2.0, 2.2, MIASMA_R * 0.35, 0.3, 85.0, Vector3.UP, true)
	Fx.ring(root, at, MIASMA_R, TOXIC, 0.5)
	Sfx.play_at("ice_shatter", at, -4.0, 0.7)
	Sfx.play_at("blight_burst", at, -5.0, 0.9)
	if not ghost():
		h.game.add_shake(0.1)
		for e in _foes(at, r):
			_poison(e, "toxic", MIASMA_T)
			_add_blight(e, "p_miasma")

## Contagion: the foe nearest the pointer is cursed; its poison leaps to all near it every second, and bursts if it dies cursed.
func _curse(at: Vector3) -> void:
	var best: Enemy = null
	var bd := 4.0
	for e in _foes(at, 4.0):
		var d: float = Vector2(e.global_position.x - at.x, e.global_position.z - at.z).length()
		if d < bd:
			bd = d
			best = e
	var hand := h.global_position + Vector3(0, 1.5, 0)
	if best == null:
		_send("curse|%s|%s" % [_v(hand), _v(at)])
		_curse_fx(hand, at, null)
		return
	_send("curse|%s|%s" % [_v(hand), _v(best.global_position)])
	_curse_fx(hand, best.global_position, best)
	if ghost():
		return
	curses[best.get_instance_id()] = {"e": best, "t": CURSE_T, "tick": 1.0}
	_poison(best, "toxic", CURSE_T)
	_add_blight(best, "p_spread")

func _curse_fx(from: Vector3, to: Vector3, e) -> void:
	var root: Node3D = h.game.world.fx_root
	Fx.bolt(root, from, to + Vector3(0, 1.0, 0), TOXIC, 0.3)
	Fx.burst(root, to + Vector3(0, 1.0, 0), TOXIC, 16, 2.5, 0.1, 0.5, true, -2.0)
	if e != null and is_instance_valid(e) and not e.has_node("pd_curse"):
		var a := PlagueSmoke.vapour(e, Color(0.65, 1.0, 0.25, 0.55), 10, 0.7, 1.2, 0.6, 0.35 * e.radius + 0.2, Vector3(0, e.height * 1.2, 0), TOXIC * 0.35)
		a.name = "pd_curse"
		Fx._free_later(a, CURSE_T)
	Sfx.play_at("blight_burst", to, -6.0, 1.3)

func _update_curses(delta: float) -> void:
	for id in curses.keys():
		var c: Dictionary = curses[id]
		var e = c["e"]
		if not is_instance_valid(e):
			curses.erase(id)
			continue
		if e.dead:
			# it died cursed: the plague bursts out of it (Epidemic: the curse itself leaps to the nearest)
			curses.erase(id)
			_curse_spread(e, CURSE_BURST, 4.0)
			if h.talent("curse_jump") > 0.0:
				var next: Enemy = null
				var nd := 7.0
				for o in _foes(e.global_position, 7.0):
					var d: float = o.global_position.distance_to(e.global_position)
					if not curses.has(o.get_instance_id()) and d < nd:
						nd = d
						next = o
				if next != null:
					curses[next.get_instance_id()] = {"e": next, "t": CURSE_T, "tick": 1.0}
					_poison(next, "toxic", CURSE_T)
					_send("curse|%s|%s" % [_v(e.global_position + Vector3(0, 1.0, 0)), _v(next.global_position)])
					_curse_fx(e.global_position + Vector3(0, 1.0, 0), next.global_position, next)
			Fx.burst(h.game.world.fx_root, e.global_position + Vector3(0, 1.0, 0), TOXIC, 30, 4.0, 0.14, 0.7, true, -1.0)
			continue
		c["t"] = float(c["t"]) - delta
		c["tick"] = float(c["tick"]) - delta
		if float(c["tick"]) <= 0.0:
			c["tick"] = 1.0
			_curse_spread(e, CURSE_R, 2.5)
		if float(c["t"]) <= 0.0:
			curses.erase(id)

func _curse_spread(e, r: float, t: float) -> void:
	var root: Node3D = h.game.world.fx_root
	for o in _foes(e.global_position, r):
		if o == e:
			continue
		_poison(o, "toxic", t)
		Fx.bolt(root, e.global_position + Vector3(0, 1.0, 0), o.global_position + Vector3(0, 1.0, 0), TOXIC, 0.2)

## Leech Jar: a vial's flight (partners see the same throw), and where it lands a pool of leeches that poisons and heals him.
func _throw_leeches(at: Vector3) -> void:
	var w: World = h.game.world
	var J: Dictionary = h.rig.get_meta("j")
	var from: Vector3 = (J["at_hand_r"] as Node3D).global_position if J.has("at_hand_r") else h.global_position + Vector3(0, 1.6, 0)
	var to := Vector3(at.x, w.height_at(at.x, at.z), at.z)
	recipe = 2
	_send("throw|toxic|%s|%s|%.2f|%d" % [_v(from), _v(to), LEECH_R, recipe])
	_launch(from, to, LEECH_R)
	vial_flights[-1]["leech"] = true

func _leech_pool(at: Vector3) -> void:
	var root: Node3D = h.game.world.fx_root
	Fx.burst(root, at + Vector3(0, 0.4, 0), Color(0.55, 0.05, 0.08), 26, 2.5, 0.09, 0.6, false, -8.0)
	Fx.ring(root, at, LEECH_R, Color(0.75, 0.1, 0.12), 0.6)
	if ghost():
		return
	clouds[-1]["leech"] = true      # (the pool _shatter laid: its ticks heal him too, _update_clouds)
	clouds[-1]["t"] = LEECH_T + h.talent("leech_t")

## Pestilence Vial lands: the glass bursts, the liquid splashes up, a small hit, and the pool creeps out.
func _shatter(at: Vector3, r: float, ri: int, dir: Vector3) -> void:
	var w: World = h.game.world
	var root: Node3D = w.fx_root
	PlagueVialFx.shatter(root, w, at, r, ri, dir, true)
	Sfx.play_at("ice_shatter", at, -2.0, 1.45)
	Sfx.play_at("blight_burst", at, -7.0, 1.25)
	Sfx.play_at("drip", at, -4.0, 0.8)
	if not ghost():
		h.game.add_shake(0.06)
		var dmg := _base(12.0, 1.65, 0.24, "toxic")
		var burst := h.talent("vial_burst")
		if burst > 0.0:
			# Volatile Reagents (a run's talent): the vial bursts for a share of his weapon's blow across the whole pool
			dmg += (h.dmg_min + h.dmg_max) * 0.5 * h.buff_mult() * burst / 100.0 * h.dmg_mult("toxic")
			Fx.burst(root, at + Vector3(0, 0.6, 0), TOXIC, 30, r * 1.6, 0.16, 0.5, true, -4.0)
			Fx.flash(root, at + Vector3(0, 1.0, 0), TOXIC, 2.5, 0.25, r * 2.0)
		for e in _foes(at, r * (0.6 if burst <= 0.0 else 1.0)):
			_damage(e, dmg, at, true)
	var pool := PlagueVialFx.Pool.new()
	root.add_child(pool)
	pool.global_position = Vector3(at.x, w.height_at(at.x, at.z), at.z)
	pool.setup(w, pool.global_position, r, ri, true)
	clouds.append({"node": pool, "pos": at, "r": r, "t": CLOUD_T + h.talent("cloud_dur"), "src": "toxic", "tick": 0.0})

# ---------------------------------------------------------------- clouds and poison
## A small low cloud (the cane's Censer Slam): a ring of fog particles and a faint light.
func _cloud(at: Vector3, r: float, dur: float, src: String) -> void:
	var node := Node3D.new()
	h.game.world.fx_root.add_child(node)
	node.global_position = at
	var p := Fx.aura(node, Color(TOXIC.r * 0.6, TOXIC.g * 0.75, TOXIC.b * 0.45, 0.6), int(clampf(r * r * 6.0, 24.0, 120.0)), 0.3, 0.6, 1.6, 0.15, r * 0.8, 80.0, Vector3(0, 0.35, 0), false)
	p.name = "fog"
	Fx._free_later(node, dur + 2.0)
	clouds.append({"node": node, "pos": at, "r": r, "t": dur, "src": src, "tick": 0.0})

func _end_cloud(c: Dictionary) -> void:
	clouds.erase(c)
	var n = c["node"]
	if is_instance_valid(n) and n is PlagueVialFx.Pool:
		(n as PlagueVialFx.Pool).end()
		return
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
		var fed := 0
		for e in _foes(c["pos"], float(c["r"])):
			_poison(e, src, VIAL_LINGER if src == "toxic" else POISON_LINGER)
			if src == "toxic":
				_add_blight(e, "toxic")
			fed += 1
		if c.has("leech") and fed > 0:
			h.life = minf(h.max_life, h.life + h.max_life * LEECH_HEAL * (1.0 + h.talent("leech_heal") / 100.0) / 100.0 * TICK * mini(fed, 3))
		if c.has("slow"):
			for e in _foes(c["pos"], float(c["r"])):
				e.chill(0.3, 1.0)

## What a second of each source's poison does. The per-level parts of all his damage are 0.55 of what they were before
## the PvP pass of 2026-11-02 (they had grown to twice anyone's; the pass cut the old kit's, and the new kit's follow).
func _poison_dps(src: String) -> float:
	match src:
		"toxic": return _base(9.0, 1.26, 0.16, "toxic")
		"cane": return _base(3.0, 0.55, 0.1, "attack")
	return 0.0

## Poisons a foe from one source: refreshed, never stacked.
func _poison(e: Enemy, src: String, t: float) -> void:
	if ghost() or e.pvp_obj > 0:
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
			var fever := 1.2 if (_feverish(e) and e.pvp_pid == 0) else 1.0
			pz["age"] = float(pz.get("age", 0.0)) + TICK
			var grow := RunTalents.poison_mult(h, float(pz["age"])) if h.run != null and e.pvp_pid == 0 else 1.0
			_damage(e, total * TICK * fever * grow, e.global_position, false)
			if h.run != null:
				RunTalents.on_dot(h, e, total * TICK * fever * grow)

## Poison and its kin hurt in green numbers, with no blood; armour doesn't stop them (the game's elemental channel).
func _damage(e: Enemy, amount: float, from: Vector3, knock: bool) -> void:
	if ghost() or e == null or e.dead or amount <= 0.0:
		return
	e.dmg_tint = POISON_TINT
	e.soft_hit = not knock
	if h.run != null:
		RunTalents.mark(h, e)
	e.take_damage(0.0, amount, from, 0.3 if knock else 0.0, false)
	e.soft_hit = false
	e.dmg_tint = Color(0, 0, 0, 0)

## A poisoned foe trails a thin green haze (the Mantaflow vapour; their own child: it goes when they do).
func _tint(e, on: bool) -> void:
	if not is_instance_valid(e):
		return
	var f: Node = e.get_node_or_null("pd_poison")
	if on and f == null and not e.dead:
		var a := PlagueSmoke.vapour(e, Color(TOXIC.r, TOXIC.g, TOXIC.b, 0.4), 7, 0.55, 1.1, 0.45, 0.25 * e.radius + 0.12, Vector3(0, e.height * 0.9, 0), TOXIC * 0.15)
		a.name = "pd_poison"
	elif not on and f != null:
		e.remove_child(f)      # at once, so a haze put back this frame takes the name
		f.queue_free()

# ---------------------------------------------------------------- Blight and Fever
## One stack per DIFFERENT skill of his (refreshed by the same one); three = Feverish.
func _add_blight(e: Enemy, src: String) -> void:
	if ghost() or e == null or e.dead or e.pvp_obj > 0:
		return
	var id := e.get_instance_id()
	if not blight.has(id):
		blight[id] = {"e": e, "srcs": {}, "fever": 0.0}
	var b: Dictionary = blight[id]
	var srcs: Dictionary = b["srcs"]
	var had := srcs.size()
	srcs[src] = BLIGHT_T
	if srcs.size() != had:
		if e.pvp_pid > 0:
			# a player: his own game shows it (PvpStatusFx, after the server's say), on his puppet for everyone
			PvpStatus.send(h.game, e, "blight", BLIGHT_T, float(srcs.size()))
		else:
			PlagueFever.stacks(e, srcs.size())
	if srcs.size() >= 3 and float(b["fever"]) <= 0.0:
		b["fever"] = FEVER_T
		srcs.clear()
		if e.pvp_pid <= 0:
			PlagueFever.stacks(e, 0)      # the marks are spent: they burst into the Fever
			PlagueFever.fever(e, FEVER_T)
		Sfx.play_at("blight_burst", e.global_position, -6.0, 0.7)
		if e.pvp_pid > 0:
			PvpStatus.send(h.game, e, "blight", FEVER_T, 3.0)
			PvpStatus.send(h.game, e, "reveal", FEVER_T, 1.0)

func _feverish(e: Enemy) -> bool:
	var b: Dictionary = blight.get(e.get_instance_id(), {})
	return not b.is_empty() and float(b["fever"]) > 0.0

func _update_blight(delta: float) -> void:
	for id in blight.keys():
		var b: Dictionary = blight[id]
		var e = b["e"]
		if not is_instance_valid(e) or e.dead:
			blight.erase(id)
			continue
		b["fever"] = maxf(float(b["fever"]) - delta, 0.0)
		var srcs: Dictionary = b["srcs"]
		var n := srcs.size()
		for s in srcs.keys():
			srcs[s] = float(srcs[s]) - delta
			if float(srcs[s]) <= 0.0:
				srcs.erase(s)
		if srcs.size() != n and e.pvp_pid <= 0:
			PlagueFever.stacks(e, srcs.size())
		if srcs.is_empty() and float(b["fever"]) <= 0.0:
			blight.erase(id)

# ---------------------------------------------------------------- E Swarmcraft
func _swarm_cast(at: Vector3) -> void:
	var w: World = h.game.world
	var J: Dictionary = h.rig.get_meta("j")
	var from: Vector3 = (J["at_hand_r"] as Node3D).global_position if J.has("at_hand_r") else h.global_position + Vector3(0, 1.4, 0)
	var to := Vector3(at.x, w.height_at(at.x, at.z), at.z)
	_send("swarm|%s|%s" % [_v(from), _v(to)])
	_reveal_if_fogged()
	_swarm_start(from, to)

func _swarm_start(from: Vector3, to: Vector3) -> void:
	if not swarm.is_empty():
		_swarm_end(false)
	var w: World = h.game.world
	var node := PlagueSwarmFx.Swarm.new()
	w.fx_root.add_child(node)
	node.setup(w, from, to, SWARM_R * (1.0 + h.talent("swarm_size") / 100.0), _quality())
	swarm = {"node": node, "pos": from, "to": to, "t": SWARM_T + h.talent("swarm_dur"), "left": SWARM_REDIRECTS + int(h.talent("swarm_redirect")),
		"tick": 0.0, "scatter": 0.0, "r": SWARM_R * (1.0 + h.talent("swarm_size") / 100.0)}
	# any area blow (a nova, a slam, a shockwave ring) that reaches it scatters it: on the caster's game, which plays
	# every partner's and foe's effects too
	if not ghost():
		var cb := Callable(self, "_area_hit")
		if not Fx.area_listeners.has(cb):
			Fx.area_listeners.append(cb)
	Sfx.play_at("drip", from, -4.0, 0.6)

func _swarm_redirect(at: Vector3) -> void:
	if swarm.is_empty() or int(swarm["left"]) <= 0:
		h.game.ui.message("The swarm won't be turned again", Color(0.8, 0.8, 0.6))
		return
	var w: World = h.game.world
	var to := h.global_position + ((at - h.global_position) * Vector3(1, 0, 1)).limit_length(SWARM_RANGE)
	to.y = w.height_at(to.x, to.z)
	swarm["to"] = to
	swarm["left"] = int(swarm["left"]) - 1
	PlagueSwarmFx.redirect(swarm["node"], to)
	_send("swarm_to|%s" % _v(to))
	Sfx.play_at("swing_light", h.global_position, -9.0, 1.4)

func _update_swarm(delta: float) -> void:
	if swarm.is_empty():
		return
	var node: PlagueSwarmFx.Swarm = swarm["node"]
	if not is_instance_valid(node):
		swarm = {}
		return
	# it flies at its own speed toward its point (never chasing anyone) and hangs there
	var pos: Vector3 = swarm["pos"]
	var to: Vector3 = swarm["to"]
	var d := to - pos
	pos += d.limit_length(SWARM_SPEED * delta)
	swarm["pos"] = pos
	node.target = pos
	swarm["t"] = float(swarm["t"]) - delta
	swarm["scatter"] = maxf(float(swarm["scatter"]) - delta, 0.0)
	if float(swarm["t"]) <= 0.0:
		if not ghost():
			_swarm_end(true)
		return
	if ghost():
		return
	var r: float = swarm["r"]
	# a dodge roll through it scatters it for a moment (a player's puppet rolling, seen on this game)
	if float(swarm["scatter"]) <= 0.0 and h.game.net != null and h.game.net.active:
		for pid in h.game.net.players.keys():
			var ph = h.game.net.players[pid].get("hero")
			if ph != null and is_instance_valid(ph) and ph != h and Dodge.dodging(ph) and ph.global_position.distance_to(pos) < r:
				swarm["scatter"] = SWARM_SCATTER
				PlagueSwarmFx.scatter(node)
				_send("swarm_scatter")
				break
	swarm["tick"] = float(swarm["tick"]) - delta
	if float(swarm["tick"]) > 0.0 or float(swarm["scatter"]) > 0.0:
		return
	swarm["tick"] = TICK
	var dmg := _base(5.0, 0.77, 0.1, "swarm") * TICK * 2.0
	var heal := h.talent("swarm_heal")
	for e in _foes(pos, r):
		_damage(e, dmg, pos, false)
		if heal > 0.0 and not ghost():
			h.life = minf(h.max_life, h.life + h.max_life * heal / 100.0 * TICK)
		PvpStatus.send(h.game, e, "harried", 0.8, HARRIED)
		if e.pvp_pid > 0:
			PvpStatus.send(h.game, e, "reveal", 0.8, 1.0)
		_add_blight(e, "swarm")
		PlagueSwarmFx.bite(node, e)

## An area blow somewhere (Fx.area_hit): if it reaches the swarm, the swarm scatters for SWARM_SCATTER.
func _area_hit(pos: Vector3, radius: float) -> void:
	if ghost() or swarm.is_empty() or float(swarm["scatter"]) > 0.0:
		return
	var sp: Vector3 = swarm["pos"]
	if Vector2(sp.x - pos.x, sp.z - pos.z).length() > radius + float(swarm["r"]) * 0.6:
		return
	swarm["scatter"] = SWARM_SCATTER
	PlagueSwarmFx.scatter(swarm["node"])
	_send("swarm_scatter")

## The swarm goes home: back into the reliquary (or just thins away for a partner), and Swarmcraft's cooldown starts.
func _swarm_end(send: bool) -> void:
	if swarm.is_empty():
		return
	var node = swarm["node"]
	if is_instance_valid(node):
		PlagueSwarmFx.go_home(node, h)
	swarm = {}
	Fx.area_listeners.erase(Callable(self, "_area_hit"))
	if send:
		_send("swarm_end")
	if not ghost() and h.cds.has("swarm"):
		h.cds["swarm"] = h.skill_cd("swarm")

# ---------------------------------------------------------------- R Corpse Bloom
func _plant(at: Vector3) -> void:
	var w: World = h.game.world
	var g := Vector3(at.x, w.height_at(at.x, at.z), at.z)
	var r := BLOOM_R * (1.0 + h.talent("bloom_size") / 100.0)
	var oid := _new_oid()
	_send("bloom|%s|%.2f|%d" % [_v(g), r, oid])
	_reveal_if_fogged()
	_bloom_at(g, r, oid)

func _bloom_at(g: Vector3, r: float, oid := 0) -> void:
	var w: World = h.game.world
	var node := PlagueBloomFx.Bloom.new()
	w.fx_root.add_child(node)
	node.global_position = g
	var every := maxf(BLOOM_WARN + 0.3, BLOOM_EVERY / (1.0 + h.talent("bloom_rate") / 100.0))     # (Overgrowth: more often)
	node.setup(w, g, r, BLOOM_GROW, BLOOM_T + h.talent("bloom_dur"), every, BLOOM_WARN)
	var b := {"node": node, "pos": g, "r": r, "age": 0.0, "life": BLOOM_GROW + BLOOM_T + h.talent("bloom_dur"), "next": BLOOM_GROW + every - BLOOM_WARN, "marks": {}, "warned": false, "every": every,
		"oid": oid, "left": int(PvpObjects.HITS["bloom"])}
	if ghost():
		b["proxy"] = PvpObjects.proxy(h.game, h, oid, "bloom", int(b["left"]), g)
	blooms.append(b)
	Sfx.play_at("impact_metal", g, -10.0, 0.7)
	Sfx.play_at("drip", g, -6.0, 0.5)

func _update_blooms(delta: float) -> void:
	for b in blooms.duplicate():
		var node: PlagueBloomFx.Bloom = b["node"]
		b["age"] = float(b["age"]) + delta
		if float(b["age"]) >= float(b["life"]) or not is_instance_valid(node):
			blooms.erase(b)
			PvpObjects.drop(b.get("proxy"))
			if is_instance_valid(node):
				node.wither()
			continue
		PvpObjects.keep_on(b.get("proxy"), b["pos"])
		var age: float = b["age"]
		if not bool(b.get("warned", false)):
			if age >= float(b["next"]):
				# the ring begins (the Bloom draws it on its own clock): remember where everyone in reach stands
				b["warned"] = true
				var marks := {}
				if not ghost():
					for e in _foes(b["pos"], float(b["r"]) + 1.5):
						marks[e.get_instance_id()] = e.global_position
				b["marks"] = marks
			continue
		if age < float(b["next"]) + BLOOM_WARN:
			continue
		# the pulse
		b["warned"] = false
		b["next"] = float(b["next"]) + float(b.get("every", BLOOM_EVERY))
		var pos: Vector3 = b["pos"]
		Sfx.play_at("blight_burst", pos, -3.0, 0.8)
		if ghost():
			continue
		var was_at: Dictionary = b["marks"]
		var dmg := _base(14.0, 1.98, 0.26, "bloom")
		for e in _foes(pos, float(b["r"])):
			_damage(e, dmg, pos, false)
			_add_blight(e, "bloom")
			var was = was_at.get(e.get_instance_id(), null)
			if was is Vector3 and (was as Vector3).distance_to(e.global_position) < BLOOM_STILL:
				PvpStatus.send(h.game, e, "snare", BLOOM_SNARE + h.talent("bloom_snare"), 1.0)
				if e.pvp_pid <= 0 and e.pvp_obj <= 0:
					PlagueBloomFx.lash(node, e)     # (a player's roots are his own game's, PvpStatusFx)

# ---------------------------------------------------------------- F Fog of the Forgotten
func _fog_cast(away_from: Vector3) -> void:
	var w: World = h.game.world
	var g := h.global_position
	g.y = w.height_at(g.x, g.z)
	var r := FOG_R
	_send("fog|%s|%.2f" % [_v(g), r])
	_fog_at(g, r)
	# the hop back: away from the pointer
	var dir := ((h.global_position - away_from) * Vector3(1, 0, 1)).normalized()
	if dir.length() < 0.1:
		dir = -h.aim_dir()
	h.shove = dir * FOG_HOP * 6.0
	reveal_t = 0.0

func _fog_at(g: Vector3, r: float) -> void:
	var w: World = h.game.world
	var node := PlagueFogFx.Fog.new()
	w.fx_root.add_child(node)
	node.global_position = g
	node.setup(w, g, r, FOG_T + h.talent("fog_dur"), _quality())
	fogs.append({"node": node, "pos": g, "r": r, "t": FOG_T + h.talent("fog_dur")})
	Sfx.play_at("impact_metal", g, -6.0, 0.6)
	Sfx.play_at("phase_erupt", g, -9.0, 1.3)

func _update_fogs(delta: float) -> void:
	reveal_t = maxf(reveal_t - delta, 0.0)
	for f in fogs.duplicate():
		f["t"] = float(f["t"]) - delta
		if float(f["t"]) <= 0.0:
			fogs.erase(f)
			if is_instance_valid(f["node"]):
				(f["node"] as PlagueFogFx.Fog).end()

func _in_fog(p: Vector3) -> bool:
	for f in fogs:
		var c: Vector3 = f["pos"]
		if Vector2(p.x - c.x, p.z - c.z).length() < float(f["r"]) * 0.92:
			return true
	return false

## Walking in his own fog he's quicker (Hero._process).
func speed_mult() -> float:
	var m := 1.0
	if not fogs.is_empty() and _in_fog(h.global_position):
		m *= FOG_SPEED
	if not trans.is_empty():
		m *= TRANS_MOVE
	return m

func _reveal_self() -> void:
	reveal_t = FOG_REVEAL
	_send("reveal")

func _reveal_if_fogged() -> void:
	if fogs.size() > 0 and _in_fog(h.global_position):
		_reveal_self()

## For other players' games (a puppet's ghost): is he hidden from the one watching? Only in the Battlegrounds (in
## co-op his partners always see him, faded). Hidden while inside one of his fogs, unless the watcher is within
## FOG_SEE of him, he struck from it a moment ago, or he carries Fever or the swarm's mark.
func hidden_from(viewer: Hero) -> bool:
	if fogs.is_empty() or reveal_t > 0.0 or viewer == null or not _in_fog(h.global_position):
		return false
	if PvpStatus.has(h, "reveal"):
		return false
	return viewer.global_position.distance_to(h.global_position) > FOG_SEE

## For a monster at `at` (Enemy._process, on the game running the monsters): it can't see him in his fog and loses
## track of him, as of a Demon in the Underworld, unless it's within FOG_SEE, he struck from the fog a moment ago or
## he's marked (reveal). Bosses and the Hollow Sloths see through it (the Enemy decides).
func hidden_from_monster(at: Vector3) -> bool:
	if fogs.is_empty() or reveal_t > 0.0 or not _in_fog(h.global_position):
		return false
	if PvpStatus.has(h, "reveal"):
		return false
	return Vector2(at.x - h.global_position.x, at.z - h.global_position.z).length() > FOG_SEE

func _update_visibility() -> void:
	if not ghost() or h.rig == null or h.game == null:
		return
	var hide := false
	var fade := false
	if not fogs.is_empty() and _in_fog(h.global_position) and reveal_t <= 0.0:
		if h.game.bg_mode:
			hide = hidden_from(h.game.hero)
		else:
			fade = true
	h.fog_hidden = hide       # Hero._puppet_process: the whole puppet (body, name tag, minimap dot) goes
	if h.rig.has_meta("fog_fade") != fade:
		if fade:
			h.rig.set_meta("fog_fade", true)
		else:
			h.rig.remove_meta("fog_fade")
		PlagueFogFx.ghostly(h.rig, fade)

# ---------------------------------------------------------------- G Transfusion
func _trans_cast() -> void:
	var n := PvpStatus.cleanse(h)
	_send("trans")
	_trans_start()
	if n > 0:
		h.game.ui.message("Cleansed", Color(0.7, 1.0, 0.6))

func _trans_start() -> void:
	if not trans.is_empty() and is_instance_valid(trans.get("node")):
		(trans["node"] as Node3D).queue_free()
	var node := PlagueTransfusionFx.attach(h)
	trans = {"t": TRANS_T + h.talent("trans_dur"), "soaked": 0.0, "node": node}
	Sfx.play_at("drip", h.global_position, -3.0, 0.5)
	Sfx.play_at("impact_metal", h.global_position, -9.0, 1.6)

## Hero.take_hit asks: how much of this blow gets through? The rest fills the tanks.
func absorb(dmg: float) -> float:
	if trans.is_empty():
		return dmg
	var cut := dmg * (TRANS_DR + h.talent("trans_dr") / 100.0)
	trans["soaked"] = float(trans["soaked"]) + cut
	PlagueTransfusionFx.soak(trans["node"], float(trans["soaked"]) / maxf(h.max_life * (TRANS_CAP + h.talent("trans_cap") / 100.0), 1.0))
	return dmg - cut

func _update_trans(delta: float) -> void:
	if trans.is_empty():
		return
	trans["t"] = float(trans["t"]) - delta
	if float(trans["t"]) <= 0.0 and not ghost():
		var heal := minf(float(trans["soaked"]), h.max_life * (TRANS_CAP + h.talent("trans_cap") / 100.0))
		_send("trans_end|%.1f" % heal)
		_trans_end(heal)

## He swung or cast before the window ran out: it ends now (what was soaked still heals).
func _trans_end_early() -> void:
	if trans.is_empty() or ghost():
		return
	var heal := minf(float(trans["soaked"]), h.max_life * (TRANS_CAP + h.talent("trans_cap") / 100.0))
	_send("trans_end|%.1f" % heal)
	_trans_end(heal)

func _trans_end(heal: float) -> void:
	if trans.is_empty():
		return
	PlagueTransfusionFx.finish(trans["node"], heal > 0.5)
	trans = {}
	if not ghost() and heal > 0.0:
		h.heal_pool += heal
		Sfx.play("potion", -6.0, 0.8)

# ---------------------------------------------------------------- V The Last Experiment
func _vat_cast(at: Vector3) -> void:
	var w: World = h.game.world
	var g := Vector3(at.x, w.height_at(at.x, at.z), at.z)
	var r := EXP_R * (1.0 + h.talent("exp_size") / 100.0)
	var oid := _new_oid()
	_send("vat|%s|%.2f|%d" % [_v(g), r, oid])
	_reveal_if_fogged()
	_vat_at(g, r, oid)
	# stage 2: cranking it (an attack of its own, so a stun or another skill interrupts it)
	crank_from = h.global_position
	h._start_attack("pd_crank", "crank")
	h.atk_dur = float(DUR["crank"]) * (PvpStatus.act_mult(h) if not h.pvs.is_empty() else 1.0)

func _vat_at(g: Vector3, r: float, oid := 0) -> void:
	if not lab.is_empty():
		_exp_end()
	var w: World = h.game.world
	var node := PlagueExperimentFx.Vat.new()
	w.fx_root.add_child(node)
	node.global_position = g
	node.setup(w, g, r)
	lab = {"stage": 1, "node": node, "pos": g, "r": r, "t": 0.0, "tick": 0.0, "spew": SPEW_EVERY * 0.5,
		"oid": oid, "left": int(PvpObjects.HITS["vat"])}
	if ghost():
		lab["proxy"] = PvpObjects.proxy(h.game, h, oid, "vat", int(lab["left"]), g)
	h.game.add_shake(0.25 if not ghost() else 0.08)
	Sfx.play_at("slam", g, -2.0, 0.85)
	Sfx.play_at("impact_metal", g, -4.0, 0.6)

## The crank's last turn (its impact frame): the full experiment.
func _exp_finish() -> void:
	if lab.is_empty() or int(lab["stage"]) != 1:
		return
	_exp_burst_send(float(lab["r"]))

func _exp_burst_send(r: float) -> void:
	var coid := _new_oid()
	_send("burst|%.2f|%d" % [r, coid])
	_exp_burst(r, coid)

func _exp_burst(r: float, coid := 0) -> void:
	if lab.is_empty() or int(lab["stage"]) != 1:
		return
	lab["stage"] = 2
	lab["r"] = r
	lab["t"] = EXP_T + h.talent("exp_dur")
	lab["tick"] = 0.0
	# the vat is gone: the creature out of it is what can be struck now
	PvpObjects.drop(lab.get("proxy"))
	lab.erase("proxy")
	lab["coid"] = coid
	lab["cleft"] = int(PvpObjects.HITS["creature"])
	var node: PlagueExperimentFx.Vat = lab["node"]
	node.burst(r)
	if ghost():
		lab["cproxy"] = PvpObjects.proxy(h.game, h, coid, "creature", int(lab["cleft"]), node.c_pos)
	h.game.add_shake(0.45 if not ghost() else 0.12)
	Sfx.play_at("ice_shatter", lab["pos"], 0.0, 0.7)
	Sfx.play_at("phase_erupt", lab["pos"], -2.0, 0.6)
	Sfx.duck(-8.0, 1.4)
	if not ghost():
		var dmg := _base(20.0, 3.0, 0.4, "experiment")
		for e in _foes(lab["pos"], r):
			_damage(e, dmg, lab["pos"], true)
			_add_blight(e, "experiment")

func _update_exp(delta: float) -> void:
	if lab.is_empty():
		return
	var node: PlagueExperimentFx.Vat = lab["node"]
	if not is_instance_valid(node):
		lab = {}
		return
	if int(lab["stage"]) == 1:
		lab["t"] = float(lab["t"]) + delta
		node.charge(clampf(float(lab["t"]) / float(DUR["crank"]), 0.0, 1.0))
		if ghost():
			PvpObjects.keep_on(lab.get("proxy"), lab["pos"])
			return
		# interrupted: a stun, another move, or walking away from the vat
		var cranking: bool = h.atk_t >= 0.0 and h.atk_skill == "crank"
		if not cranking or h.daze_t > 0.0 or h.global_position.distance_to(crank_from) > 1.5:
			if h.atk_skill == "crank":
				h.atk_t = -1.0
			_exp_burst_send(EXP_R_SMALL)
		return
	lab["t"] = float(lab["t"]) - delta
	if float(lab["t"]) <= 0.0:
		if not ghost():
			_send("exp_end")
			_exp_end()
		return
	var pos: Vector3 = lab["pos"]
	var r: float = lab["r"]
	node.creature_step(delta, _creature_foes(pos, r), pos, r)
	if ghost():
		PvpObjects.keep_on(lab.get("cproxy"), node.c_pos)
		return
	lab["tick"] = float(lab["tick"]) - delta
	if float(lab["tick"]) <= 0.0:
		lab["tick"] = TICK
		for e in _foes(pos, r):
			PvpStatus.send(h.game, e, "slow", 0.7, EXP_SLOW)
			if fmod(float(lab["t"]), EXP_EVERY) < TICK:
				_damage(e, _base(8.0, 1.21, 0.16, "experiment"), pos, false)
				_add_blight(e, "experiment")
	# the creature spews at the nearest foe: a telegraphed cone, then the hit
	lab["spew"] = float(lab["spew"]) - delta
	if float(lab["spew"]) <= 0.0:
		lab["spew"] = SPEW_EVERY
		var foes := _creature_foes(pos, r)
		var from: Vector3 = node.creature_pos()
		if not foes.is_empty():
			foes.sort_custom(func(a, b) -> bool: return a.global_position.distance_to(from) < b.global_position.distance_to(from))
			var toward: Vector3 = foes[0].global_position
			_send("spew|%s|%s" % [_v(from), _v(toward)])
			PlagueExperimentFx.spew(lab, from, toward, SPEW_WARN, SPEW_LEN, SPEW_HALF)
			lab["spew_at"] = [from, toward, SPEW_WARN]
	if lab.has("spew_at"):
		var sp: Array = lab["spew_at"]
		sp[2] = float(sp[2]) - delta
		if float(sp[2]) <= 0.0:
			lab.erase("spew_at")
			var from2: Vector3 = sp[0]
			var dir := ((sp[1] as Vector3) - from2) * Vector3(1, 0, 1)
			dir = dir.normalized() if dir.length() > 0.01 else Vector3.FORWARD
			for e in _foes(from2, SPEW_LEN):
				var to_e: Vector3 = (e.global_position - from2) * Vector3(1, 0, 1)
				if to_e.length() < 0.3 or absf(dir.signed_angle_to(to_e.normalized(), Vector3.UP)) < SPEW_HALF:
					_damage(e, _base(16.0, 2.2, 0.3, "experiment"), from2, true)
					_poison(e, "toxic", 2.0)

func _exp_end() -> void:
	if lab.is_empty():
		return
	var node = lab["node"]
	PvpObjects.drop(lab.get("proxy"))
	PvpObjects.drop(lab.get("cproxy"))
	if is_instance_valid(node):
		(node as PlagueExperimentFx.Vat).collapse()
	lab = {}

## PvP: the vat broken while he cranks it: the experiment fails (no blast, no quarantine), the crank stops.
func _exp_fail() -> void:
	if lab.is_empty() or int(lab["stage"]) != 1:
		return
	if not ghost() and h.atk_t >= 0.0 and h.atk_skill == "crank":
		h.atk_t = -1.0
	var node = lab["node"]
	var at: Vector3 = lab["pos"]
	PvpObjects.drop(lab.get("proxy"))
	lab = {}
	if is_instance_valid(node):
		(node as PlagueExperimentFx.Vat).fail()
	Sfx.play_at("ice_shatter", at, -2.0, 0.9)

## What the creature lumbers after: the foes in the zone; on another player's screen (a ghost in the Battlegrounds)
## that player too, so it comes for him on his own screen as it does on its owner's (its spews come from there).
func _creature_foes(pos: Vector3, r: float) -> Array:
	var out := _foes(pos, r).filter(func(e) -> bool: return e.pvp_obj <= 0)
	if ghost() and h.game != null and bool(h.game.get("bg_mode")) and h.game.hero != null and is_instance_valid(h.game.hero) \
			and not h.game.hero.dead and h.game.hero.global_position.distance_to(pos) <= r:
		out.append(h.game.hero)
	return out

# ---------------------------------------------------------------- PvP: his things can be broken (PvpObjects)
func _new_oid() -> int:
	next_oid += 1
	return next_oid

## Where his thing `oid` is (the server checks a blow's reach against its own ghost of him), or null.
func obj_pos(oid: int) -> Variant:
	if oid <= 0:
		return null
	for b in blooms:
		if int(b.get("oid", 0)) == oid:
			return b["pos"]
	if not lab.is_empty() and is_instance_valid(lab.get("node")):
		if int(lab["stage"]) == 1 and int(lab.get("oid", 0)) == oid:
			return lab["pos"]
		if int(lab["stage"]) == 2 and int(lab.get("coid", 0)) == oid:
			return (lab["node"] as PlagueExperimentFx.Vat).c_pos
	return null

## Another player's blow on one of his things (through the server, `Net.cl_pvp_obj_hit`, which lets each player's
## blows through once per `PvpObjects.GAP`): everyone is told how many are left, and the last one breaks it on every
## game.
func obj_hit(oid: int, _attacker: int) -> void:
	if ghost() or not (obj_pos(oid) is Vector3):
		return
	var left := _obj_count(oid) - 1
	_send("obj|%d|%d" % [oid, left])
	_obj_left(oid, left)

func _obj_count(oid: int) -> int:
	for b in blooms:
		if int(b.get("oid", 0)) == oid:
			return int(b["left"])
	if not lab.is_empty():
		if int(lab["stage"]) == 1 and int(lab.get("oid", 0)) == oid:
			return int(lab["left"])
		if int(lab["stage"]) == 2 and int(lab.get("coid", 0)) == oid:
			return int(lab["cleft"])
	return 0

## A thing of his struck (`left` blows to go), on his game and on every ghost of him: it flinches, the stand-ins take
## the count, and at none left it breaks: the bloom dies, the vat bursts with the experiment failed, the creature
## collapses and the quarantine ends.
func _obj_left(oid: int, left: int) -> void:
	for b in blooms.duplicate():
		if int(b.get("oid", 0)) != oid:
			continue
		b["left"] = left
		PvpObjects.set_left(b.get("proxy"), left)
		var node = b["node"]
		if left > 0:
			if is_instance_valid(node):
				(node as PlagueBloomFx.Bloom).hurt()
		else:
			blooms.erase(b)
			if is_instance_valid(node):
				(node as PlagueBloomFx.Bloom).kill()
		return
	if lab.is_empty():
		return
	var vat = lab["node"]
	if int(lab["stage"]) == 1 and int(lab.get("oid", 0)) == oid:
		lab["left"] = left
		PvpObjects.set_left(lab.get("proxy"), left)
		if left > 0:
			if is_instance_valid(vat):
				(vat as PlagueExperimentFx.Vat).hurt_vat()
		else:
			_exp_fail()
	elif int(lab["stage"]) == 2 and int(lab.get("coid", 0)) == oid:
		lab["cleft"] = left
		PvpObjects.set_left(lab.get("cproxy"), left)
		if left > 0:
			if is_instance_valid(vat):
				(vat as PlagueExperimentFx.Vat).hurt_creature()
		else:
			_exp_end()

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

## What his hands hold this frame: the vial, reliquary or seed he's about to use, and the cane only when no skill
## needs his hands (his own game from the attack, a partner's puppet from the pose it was sent).
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
		held_slosh = null
		held_path = want
		var J: Dictionary = h.rig.get_meta("j")
		if want != "" and J.has("at_hand_r"):
			match want:
				"vial":
					held = PlagueVialFx.vial(recipe)
					held.scale = Vector3.ONE * PlagueVialFx.HAND_SCALE
					held.position = Vector3(0, -0.06, -0.03)
					held_slosh = PlagueVialFx.Slosh.new()
				"reliquary":
					held = PlagueSwarmFx.reliquary()
					held.position = Vector3(0, -0.07, -0.02)
				"seed":
					held = PlagueBloomFx.seed_syringe()
					held.position = Vector3(0, -0.05, -0.02)
				"censer":
					held = PlagueFogFx.censer_in_hand()
					held.position = Vector3(0, -0.05, -0.02)
			if held != null:
				(J["at_hand_r"] as Node3D).add_child(held)
	if held_slosh != null and held != null and is_instance_valid(held):
		held_slosh.step(held, h.get_process_delta_time())
	hands_busy = a >= 0.0 and HANDS_FREE.has(style)    # Hero._carry_weapon hides the cane meanwhile
	if h.puppet and h.weapon_node != null and is_instance_valid(h.weapon_node):
		h.weapon_node.visible = not hands_busy

func update(delta: float) -> void:
	if h.game == null or h.game.world == null:
		return
	_hands()
	_update_vials(delta)
	_update_clouds(delta)
	_update_swarm(delta)
	_update_blooms(delta)
	_update_fogs(delta)
	_update_trans(delta)
	_update_exp(delta)
	_update_blight(delta)
	_update_poison(delta)
	if not curses.is_empty():
		_update_curses(delta)
	_update_visibility()

## Everything on the ground goes (a zone change, a class change, death).
func clear() -> void:
	for v in vial_flights:
		var f: PlagueVialFx.Flight = v["f"]
		if is_instance_valid(f.node):
			f.node.queue_free()
	vial_flights.clear()
	for arr in [clouds, blooms, fogs]:
		for x in arr:
			if is_instance_valid(x["node"]):
				(x["node"] as Node3D).queue_free()
			PvpObjects.drop(x.get("proxy"))
		arr.clear()
	if not swarm.is_empty() and is_instance_valid(swarm["node"]):
		(swarm["node"] as Node3D).queue_free()
	swarm = {}
	Fx.area_listeners.erase(Callable(self, "_area_hit"))
	if not trans.is_empty() and is_instance_valid(trans.get("node")):
		PlagueTransfusionFx.finish(trans["node"], false)
	trans = {}
	if not lab.is_empty() and is_instance_valid(lab["node"]):
		(lab["node"] as Node3D).queue_free()
	if not lab.is_empty():
		PvpObjects.drop(lab.get("proxy"))
		PvpObjects.drop(lab.get("cproxy"))
	lab = {}
	for id in poison.keys():
		_tint(poison[id]["e"], false)
	poison.clear()
	for id in blight.keys():
		var e = blight[id]["e"]
		if is_instance_valid(e):
			PlagueFever.stacks(e, 0)
	blight.clear()
	reveal_t = 0.0
	h.fog_hidden = false

## The effect budget by the graphics preset (0 Low .. 3 Ultra; the browser build is capped at Medium).
func _quality() -> int:
	if h.game == null:
		return 1
	return int(h.game.get("quality")) if h.game.get("quality") != null else 1
