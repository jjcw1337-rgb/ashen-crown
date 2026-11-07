class_name Archer
extends RefCounted
## The archer (the bow class, Jace's; its name is still his to choose). With a bow in his hands his attack
## shoots: Hero.swipe_attack and free_attack come here (`shoot`), he stops at RANGE from a clicked foe
## (Hero.reach) and keeps shooting while the button is held. His skills (Data.SKILLS "cls": "archer"):
##   Piercing Shot: a heavy arrow through every enemy in a line;
##   Volley: arrows into the sky that rain on the cursor, hitting all within reach again and again;
##   Thunderstep (id "snare", kept for old saves' bindings and talents; jj's pick, in place of Storm Snare): he
##     backflips away from the pointer, driving a thunderstone into a gold storm sigil where he stood, which a moment
##     later detonates: everything on it stunned and hurt, lightning chaining on into the nearest others;
##   Spirit Beast: a spectral beast (the lion's body, ghostly) that hunts with him for 30 s, and the
##     class's 12 s battle buff (+40% damage).
## His skills that are objects (Hero.kit, skills/) keep their own state: arrows in flight, the rains, the sigils.
## What is still here lives on the hero (his beasts, the mark), updated
## by `update` and cleared by `clear`. What is seen is raised by fx events (Hero.fx -> ArcherFx), so a
## partner's copy of him (Hero.puppet) shoots, rains, sets traps and runs his wolf too; only his own game
## deals the damage (Enemy.take_damage routes to the host in co-op).
## Body: until the Meshy archer exists, the knight's procedural body dressed as a hooded hunter.

const RANGE := 13.0
const ARROW_SPEED := 34.0
const FLIGHT := RANGE + 5.0     # how far an arrow flies before it falls
const HUNTER := Color(0.62, 0.85, 0.75)     # the class's colour: pale spirit-green

## The ranger (game/heroes/archer/body/archer_ranger.glb, game/heroes/archer/build/prep_ranger_mocap.py): the Meshy northern ranger
## (wolf-fur cowl, dark leather, quiver on his back) on the knight's mocap system (Knight.build_mocap,
## knight_mocap_rig.gd): motion capture for idle, walk and run (bow raised and aimed when it's out: "combat_idle",
## "walk_aim"), the shot as a whole-body clip (`SHOT`: nock, draw, loose on the attack's release frame, follow
## through), his casts (Spirit Beast) as the game's own moves laid over the upper body. The bow is the
## game's (whatever is equipped), held in his LEFT hand like the clips (J "grip_bow", `BOW_HOLD`).
const RANGER_GLB := "res://game/heroes/archer/body/archer_ranger.glb"
const SHOT := {"style": "bow", "clip": "shoot_quick",
	# Meshy's "Archery Shot 1" + "Archery Shot 3" joined (1.67 s, game/heroes/archer/build/prep_ranger_mocap.py), at close
	# to its own pace: from the ready stance the right hand reaches over the shoulder (0.38 s at the quiver), pulls
	# the arrow (0.47), nocks it (0.6), draws to the cheek (0.98), holds, looses on Anim's impact frame 0.72 (1.03:
	# the string hand flies back, the bow arm drops) and comes back to the ready stance (1.67). The old 7.8 s
	# "Draw and Shoot from Back" ("shoot_back") stays in the glb.
	"keys": [[0.0, 0.04], [0.18, 0.38], [0.25, 0.47], [0.34, 0.6], [0.62, 0.98], [0.72, 1.03], [1.0, 1.667]],
	# the clip's full draw is side-on like the aiming stand ("combat_idle" is the same stance)
	"yaw": -90.0, "stand_yaw": -90.0, "idle_side": true, "body": true,
	# the clip has its own loose, recoil and follow-through: the procedural ones only go over the aimed walk
	"body_stand": {"fling": 0.0, "recoil": 0.0, "follow": 0.0},
	"walk_clip": "walk_aim", "walk_speed": 0.82,
	# on the move: only his right arm reaches back for the arrow (over the aimed walk), then draws to his cheek
	# (Meshy's "Walk Forward While Shooting" was tried: it holds a half draw throughout and never looses)
	"reach_clip": "shoot_quick", "reach_bones": ["RightShoulder", "RightArm", "RightForeArm", "RightHand"],
	"reach_keys": [[0.0, 0.06], [0.16, 0.38], [0.26, 0.47], [0.36, 0.58], [1.0, 0.58]],
	"reach": [[0.0, 0.0], [0.07, 1.0], [0.3, 1.0], [0.44, 0.0]]}
## when the hand closes on an arrow in the quiver, when the arrow leaves it, and when it's on the string (of the
## shot's progress), standing and moving
const GRAB := 0.17
const DRAWN := 0.24
const NOCK := 0.34
const NOCK_MOVING := 0.42
const QUIVER := Vector3(0.25, 1.0, -0.24)     # the quiver's bottom on his back, in his body's frame (the glb faces +z)
## how fast he steps while he looses arrows (of his normal pace): slowed to a careful, aimed walk
const SHOOT_MOVE := 0.36
## where the drawing fingers are on his right hand (its frame), and the bow's cant off upright (degrees, the way
## archers tip it)
const FINGERS := Vector3(0, -0.06, 0)
const CANT := 8.0
## the bow in his left fist, per bow kind: [position, rotation in degrees] in the hand follower's frame
## (solved so the bow stands upright, its back toward the mark, at the full draw of the shot clip)
## and the grip's spot on the bow model (the short bow's wood bulges 0.18 out from its string; the longbow is centred)
const BOW_HOLD := {"ranger": [Vector3(0.0, -0.06, 0.0), Vector3(-66, 98, -80), Vector3.ZERO],
	"ranger_long": [Vector3(0.0, -0.06, 0.0), Vector3(-66, 98, -80), Vector3.ZERO],
	"bow": [Vector3(0.0, -0.06, 0.0), Vector3(-4, -162, -66), Vector3(-0.18, 0, 0)],
	"longbow": [Vector3(0.0, -0.06, 0.0), Vector3(-66, 98, -80), Vector3(0, 0, 0.11)]}
## Each bow model's shape (Models.enemy_weapon, in the bow's own frame): its string's two tips, the string's
## middle at rest (where the arrow nocks), the way the string pulls (toward the archer), how far it can be drawn,
## the grip (where the arrow rests on the bow), and how it hangs in a relaxed hand (the hand follower's frame:
## the arm hanging, -y down to the fingers, -z ahead), as [x, y, z] columns.
const BOW_SPEC := {
	# the ranger's carved recurve (game/heroes/archer/weapon/ranger_bow.glb, measured by prep_bow.py: limbs up +y, the string on
	# the +z side, the grip on the origin); "ranger_long" is the same model at 1.15x (the longbow)
	"ranger": {"tips": [Vector3(0.0166, 0.6915, 0.1802), Vector3(0.0133, -0.7211, 0.1983)], "rest": Vector3(0.0, 0.035, 0.1873), "pull": Vector3(0, 0, 1),
		"max": 0.66, "grip": Vector3.ZERO, "limb": Vector3(0, 1, 0),
		"hang": [Vector3(1, 0, 0), Vector3(0, 1, 0), Vector3(0, 0, 1)]},
	"ranger_long": {"tips": [Vector3(0.0191, 0.7952, 0.2072), Vector3(0.0153, -0.8293, 0.228)], "rest": Vector3(0.0, 0.0403, 0.2154), "pull": Vector3(0, 0, 1),
		"max": 0.7, "grip": Vector3.ZERO, "limb": Vector3(0, 1, 0),
		"hang": [Vector3(1, 0, 0), Vector3(0, 1, 0), Vector3(0, 0, 1)]},
	"bow": {"tips": [Vector3(0, 0, -0.55), Vector3(0, 0, 0.55)], "rest": Vector3.ZERO, "pull": Vector3(-1, 0, 0),
		"max": 0.62, "grip": Vector3(0.18, 0, 0), "limb": Vector3(0, 0, 1),
		"hang": [Vector3(0, 0, -1), Vector3(-1, 0, 0), Vector3(0, 1, 0)]},
	"longbow": {"tips": [Vector3(0, -0.82, 0.038), Vector3(0, 0.86, 0.063)], "rest": Vector3(0, 0.02, 0.05),
		"pull": Vector3(0, 0, 1), "max": 0.7, "grip": Vector3(0, 0, -0.11), "limb": Vector3(0, 1, 0),
		"hang": [Vector3(1, 0, 0), Vector3(0, 1, 0), Vector3(0, 0, 1)]},
}

## Which BOW_HOLD / BOW_SPEC entry a bow of this kind uses: the ranger's recurve when its model is in the game.
static func bow_key(kind: String) -> String:
	if ResourceLoader.exists(Models.RANGER_BOW):
		return "ranger_long" if kind == "longbow" else "ranger"
	return kind

static func ranger_ok() -> bool:
	return ResourceLoader.exists(RANGER_GLB)

static func build_body() -> Node3D:
	if ranger_ok():
		var r := Knight.build_mocap(RANGER_GLB, {
			"relaxed": ["idle", 0.0, "walk", 0.5, "run", 3.86],
			"combat": ["combat_idle", 0.0, "walk_aim", 0.82, "run", 3.86],
			"shot": SHOT, "meta": "ranger"})
		var J: Dictionary = r.get_meta("j")
		J["grip_bow"] = Models.N(J["at_hand_l"], "grip_bow")
		J["grip_bow_at"] = Models.N(J["grip_bow"], "grip_bow_at")   # the bow hangs from here, by its grip
		r.set_meta("archer", true)
		r.remove_meta("knight")
		dye(r, COLORS)
		return r
	return build_placeholder()

## His colours (game/heroes/archer/build/archer_colors.py recolours the Meshy texture: hood, tunic, coat and trousers dyed, the fur,
## leather straps, hands and face left as they are), so he stands out against the moor: "crimson" (default),
## "teal", "verdant", "royal" (game/heroes/archer/body/dyes/ranger_<name>.jpg). "" keeps Meshy's black and grey.
const COLORS := "crimson"

static func dye(r: Node3D, scheme: String) -> void:
	var path := "res://game/heroes/archer/body/dyes/ranger_%s.jpg" % scheme
	if scheme == "" or not ResourceLoader.exists(path):
		return
	var tex: Texture2D = load(path)
	for mi in r.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		if m.mesh == null or not (m.mesh is ArrayMesh) or m.get_parent() is BoneAttachment3D:
			continue
		for si in m.mesh.get_surface_count():
			var mat := m.mesh.surface_get_material(si) as StandardMaterial3D
			if mat != null and mat.albedo_texture != null and mat.albedo_texture.get_width() >= 1024:
				var dm := mat.duplicate() as StandardMaterial3D
				dm.albedo_texture = tex
				m.set_surface_override_material(si, dm)

## The placeholder body (without the glb): the knight's skeleton and procedural body in a hunter's green and leather.
static func build_placeholder() -> Node3D:
	var r := Knight.build(body_gear(Knight.default_gear()))
	r.set_meta("archer", true)
	return r

## The hunter's colours laid over the knight's gear description (his armour's shape stays; Hero.refresh_gear
## rebuilds the placeholder body with this whenever his gear changes, so the knight's red never comes back).
static func body_gear(g: Dictionary) -> Dictionary:
	g = g.duplicate()
	g["cloth"] = Color(0.13, 0.17, 0.11)
	g["cape"] = Color(0.09, 0.1, 0.09)
	g["quilt"] = Color(0.27, 0.22, 0.16)
	g["leather"] = Color(0.24, 0.16, 0.1)
	g["emblem"] = Color(0.5, 0.42, 0.3)
	g["steel"] = Color(0.32, 0.31, 0.3)
	g["trim"] = Color(0.45, 0.36, 0.22)
	g["hair"] = Color(0.12, 0.09, 0.07)
	g["coif"] = true
	return g

# ---------------------------------------------------------------- his kit
## The skills that have their own object (docs/content/skills.md): one per hero, made the first time it's needed,
## kept in Hero.kit. The rest are still the functions below, until each moves to its folder.
static func skill(h: Hero, id: String) -> Skill:
	if not h.kit.has(id):
		var s := _make(h, id)
		if s == null:
			return null
		h.kit[id] = s
	return h.kit[id]

static func _make(h: Hero, id: String) -> Skill:
	match id:
		"attack": return ArcherShot.new(h, id)
		"pierce": return FireArrow.new(h, id)
		"a_multishot": return ScatterShot.new(h, id)
		"a_explosive": return BlastArrow.new(h, id)
		"a_glacial": return GlacialShard.new(h, id)
		"a_stormshot": return StormShot.new(h, id)
		"volley": return FrostVolley.new(h, id)
		"a_barrage": return ArrowStorm.new(h, id)
		"snare": return Thunderstep.new(h, id)
		"beast": return BeastCommand.new(h, id)
		"a_mark": return HuntersMark.new(h, id)
	return null

# ---------------------------------------------------------------- the bow
## Loose an arrow toward aim (an attack: the draw, the release on the pose's impact frame).
static func shoot(h: Hero, aim: Vector3, keep_target: bool) -> void:
	if h.atk_t >= 0.0:
		return
	if not keep_target:
		h.target = null
	else:
		# a shot at the foe he walked up to: he stands his ground
		h.moving = false
		h.path = PackedVector3Array()
	h.atk_aim = assist(h, aim)
	h.atk_target = null
	h._face(h.atk_aim - h.global_position)
	h._start_attack("bow")

## Aim help: an enemy near the point aimed at is the one aimed at.
static func assist(h: Hero, aim: Vector3) -> Vector3:
	var best = null
	var bd := 2.6
	for e in h.game.enemies_near(aim, 2.6):
		var d: float = Vector2(e.global_position.x - aim.x, e.global_position.z - aim.z).length()
		if not e.dead and d < bd:
			bd = d
			best = e
	return best.global_position if best != null else aim

static func cast(h: Hero, id: String, aim: Vector3) -> void:
	var s := skill(h, id)
	if s != null:
		s.cast(aim)

## ClassSkills: nothing to check before a shot.
static func can_cast(_h: Hero, _id: String, _aim: Vector3) -> bool:
	return true

## One of his skills holds him in place (mid-Thunderstep his feet are the vault's).
static func rooted(h: Hero) -> bool:
	for sk in h.kit.values():
		if sk.rooted():
			return true
	return false

## His wolf and arrows stay through death (the wolf rises again on its own, SpiritBeast.keep).
static func died(_h: Hero) -> void:
	pass

## The string's twang on the release (Volley's flight a little lower); `at` = seconds to the impact frame.
static func sound(h: Hero, skill: String, at: float) -> bool:
	if h.atk_style != "bow":
		return false
	# (the Fire Arrow's whoosh of flame goes with it: ArrowFx "release" layers land with the arrow's "loose" event)
	Sfx.play_synced("bow", at, -3.0, 0.85 if skill == "volley" else (0.92 if skill == "pierce" else 1.0))
	return true

## The release (Hero._impact): true when it was the archer's.
static func impact(h: Hero) -> bool:
	if not h.is_archer():
		return false
	if h.atk_skill == "" and h.atk_style != "bow":
		return false
	var s := skill(h, h.atk_skill if h.atk_skill != "" else "attack")
	if s == null:
		return false
	s.impact()
	return true

## An arrow of one of his arrow skills, loosed from elsewhere (a rite's: Phoenix Quiver's free Fire Arrow).
static func _loose(h: Hero, at: Vector3, pierce: bool, mult: float, src: String, yaw: float) -> void:
	var s := skill(h, src) as ArrowSkill
	if s != null:
		s.shoot(at, pierce, mult, yaw)

## The arrows are Meshy models (tools/blender/prep_arrow.py, head toward -Z): "war" (black-shafted, barbed: his
## plain shots), "fire" (red-fletched: Fire Arrow, burning in flight), "frost" (the glacier arrow: an ice
## head and ice-blade fletching on a rimed shaft, Frost Volley's, FrostVolleyFx). A faint streak behind each so it reads from the high camera. Without the files, a shaft and head.
const ARROW_GLB := "res://game/heroes/archer/weapon/arrows/%s.glb"
const FIRE := Color(1.0, 0.45, 0.12)
const FROST := Color(0.55, 0.8, 1.0)
const STORM := Color(0.6, 0.75, 1.0)

static func _arrow_mesh(kind: String, bare := false) -> Node3D:
	var root := Node3D.new()
	var path := ARROW_GLB % kind
	if ResourceLoader.exists(path):
		var m: Node3D = ResCache.inst(path)
		root.add_child(m)
	else:
		var shaft := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.014
		cm.bottom_radius = cm.top_radius
		cm.height = 0.72
		shaft.mesh = cm
		shaft.rotation_degrees = Vector3(90, 0, 0)
		shaft.material_override = Mats.mat(Color(0.28, 0.2, 0.12), 0.8)
		root.add_child(shaft)
		var head := MeshInstance3D.new()
		var hm := CylinderMesh.new()
		hm.top_radius = 0.0
		hm.bottom_radius = 0.035
		hm.height = 0.09
		head.mesh = hm
		head.rotation_degrees = Vector3(-90, 0, 0)
		head.position = Vector3(0, 0, -0.4)
		head.material_override = Mats.mat(Color(0.5, 0.5, 0.52), 0.35, 0.9)
		root.add_child(head)
	if bare:
		return root       # ArrowFx lays its own layers on it
	var col: Color = {"fire": FIRE, "frost": FROST}.get(kind, Color(0.9, 0.85, 0.7))
	var glow := MeshInstance3D.new()
	var gm := CylinderMesh.new()
	gm.top_radius = 0.04 if kind != "war" else 0.022
	gm.bottom_radius = 0.0
	gm.height = 1.6 if kind != "war" else 1.1
	glow.mesh = gm
	glow.rotation_degrees = Vector3(90, 0, 0)
	glow.position = Vector3(0, 0, 0.75)
	glow.material_override = Mats.glow(col, 1.3 if kind != "war" else 0.5, 0.0, 0.0)
	glow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(glow)
	if kind == "fire":
		Fx.aura(root, FIRE, 18, 0.5, 0.09, 0.35, 0.8, 0.06, 30.0, Vector3(0, 0, -0.3))
	return root

## Shatter (Frost): the chilled take 20% more from his arrows.
static func shatter(h: Hero, e) -> float:
	return 1.2 if h.talent("frost_shatter") > 0.0 and e.chill_t > 0.0 else 1.0

# ---------------------------------------------------------------- every frame
static func update(h: Hero, delta: float) -> void:
	SpiritBeast.keep(h, delta)
	# his skills that are objects (Hero.kit): arrows in flight, the rains, the sigils; on his own game only, since a partner's
	# copy of him only shows them
	if not h.puppet:
		for sk in h.kit.values():
			sk.update(delta)

static func clear(h: Hero) -> void:
	for sk in h.kit.values():
		sk.clear()
	h.kit.clear()
	ArcherArrowFx.clear(h)
	ArrowFx.end_draw(h)
	FrostVolleyRainFx.clear(h)
	FrostVolleyFx.clear(h)
	ThunderstepFx.clear(h)
	for b in h.beasts:
		if is_instance_valid(b):
			b.dismiss()
	h.beasts.clear()

# ---------------------------------------------------------------- the bow in his hands
## Every frame after the pose (Hero._process and the co-op puppet's): the bow turns from hanging in his relaxed hand
## to upright on the line of the shot as he takes his stance (the rig's side-on weight), and its string is drawn by
## his right hand: from the nock, back with his fingers to the anchor at his cheek, a nocked arrow lying on the bow;
## on the release the arrow is gone and the string snaps back and shivers.
static func pose_bow(h: Hero, st: Dictionary) -> void:
	var w: Node3D = h.weapon_node
	if w == null or not is_instance_valid(w) or h.rig == null or not h.has_bow():
		return
	pose_bow_on(h.rig, w, Data.BASES[h.equipment["weapon"]["base"]]["kind"], st)

## The same for any ranger rig holding bow model w of this kind (the hero, previews).
static func pose_bow_on(rig: Node3D, w: Node3D, kind: String, st: Dictionary) -> void:
	var J: Dictionary = rig.get_meta("j")
	if not J.has("grip_bow_at"):
		return
	if w.has_meta("ranger_bow") and not kind.begins_with("ranger"):
		kind = "ranger_long" if kind == "longbow" else "ranger"
	if not BOW_SPEC.has(kind):
		return
	var sp: Dictionary = BOW_SPEC[kind]
	if not w.has_meta("bow_rig"):
		_rig_bow(w)
	var in_hand: bool = w.get_parent() == J["grip_bow_at"]
	# how it sits in the hand: relaxed (hanging) .. on the line of the shot (BOW_HOLD), by the stance
	var side := 0.0
	var aim_w = rig.get("w_side")
	if aim_w != null:
		side = float(aim_w)
	# stepping while he shoots: the aimed walk holds the bow up on the line too
	var walk_w = rig.get("w_aimwalk")
	var stepping := 0.0
	if walk_w != null:
		stepping = float(walk_w)
		side = maxf(side, stepping)
	var g: Node3D = J["grip_bow"]
	var hang: Array = sp["hang"]
	var hq := Basis(hang[0], hang[1], hang[2]).get_rotation_quaternion()
	var aq := Basis.from_euler((BOW_HOLD[kind][1] as Vector3) * (PI / 180.0)).get_rotation_quaternion()
	g.basis = Basis(hq.slerp(aq, smoothstep(0.0, 1.0, side)))
	# the draw: his right hand's fingers, along the string's pull
	var a: float = st.get("atk", -1.0)
	var drawing: bool = in_hand and a >= 0.0 and str(st.get("style", "")) == "bow"
	var imp := Anim.impact_at("bow")
	var dt := clampf(float(st.get("time", 0.0)) - float(w.get_meta("draw_t", 0.0)), 0.0, 0.1)
	w.set_meta("draw_t", float(st.get("time", 0.0)))
	var rest: Vector3 = sp["rest"]
	var fingers: Vector3 = (J["at_hand_r"] as Node3D).global_transform * FINGERS
	# every shot: his right hand reaches over his shoulder and pulls an arrow from the quiver (GRAB), brings it to
	# the bow and nocks it (NOCK), draws it to his cheek and looses it on the impact frame
	var nock_at := NOCK_MOVING if stepping > 0.5 else NOCK
	var nocked := drawing and a >= nock_at and a < imp
	var carrying := drawing and a >= GRAB and a < nock_at
	# while he draws, the bow is solved onto his hands: its grip in his left fist, its draw line pointing at his right
	# fingers, its limbs upright (canted a little), so the string always meets the hand that draws it
	# (before the arrow is on the string the line points back at his chest: the bow comes up upright, ready)
	var solve := 0.0
	var on_string := 0.0
	if drawing:
		# after the loose the string hand flies back (the clip's follow-through): the bow keeps upright on a line
		# back to his chest and eases into his hand's own hold by the end of the attack, never swinging flat
		solve = _curve([[0.0, 0.0], [0.08, 1.0], [imp + 0.05, 1.0], [1.0, 0.0]], a)
		on_string = _curve([[nock_at - 0.06, 0.0], [nock_at, 1.0], [imp + 0.02, 1.0], [imp + 0.1, 0.0]], a)
	if not w.has_meta("base_xf"):
		w.set_meta("base_xf", w.transform)
	var base_xf: Transform3D = w.get_meta("base_xf")
	w.transform = base_xf
	if solve > 0.001:
		var palm: Vector3 = g.global_position
		var chest: Vector3 = rig.global_transform * Vector3(0, 1.42, 0)
		var pull_w := chest.lerp(fingers, on_string) - palm
		if pull_w.length() > 0.15:
			pull_w = pull_w.normalized()
			var up_w := (Vector3.UP - pull_w * Vector3.UP.dot(pull_w)).normalized()
			up_w = up_w.rotated(pull_w, deg_to_rad(CANT) * (1.0 if kind == "bow" else 0.6))
			var e1: Vector3 = (sp["pull"] as Vector3).normalized()
			var lb: Vector3 = sp["limb"]
			var e2 := (lb - e1 * lb.dot(e1)).normalized()
			var local_b := Basis(e1, e2, e1.cross(e2))
			var world_b := Basis(pull_w, up_w, pull_w.cross(up_w))
			var m := world_b * local_b.inverse()
			# the arrow rests on his fist: the bow's grip sits just on the far side of the draw line
			var aimed := Transform3D(m, palm - m * (sp["grip"] as Vector3))
			var held: Transform3D = w.global_transform
			var k := smoothstep(0.0, 1.0, solve)
			w.global_transform = Transform3D(held.basis.get_rotation_quaternion().slerp(aimed.basis.get_rotation_quaternion(), k), held.origin.lerp(aimed.origin, k)).scaled_local(held.basis.get_scale())
	_hand_arrow(rig, w, fingers, (J["grip_bow"] as Node3D).global_position, carrying, _curve([[DRAWN, 0.0], [nock_at, 1.0]], a))
	# the nock: on his fingers while drawn, else a spring (a vector, so it settles back from any side)
	var off: Vector3 = w.get_meta("draw_off", Vector3.ZERO)
	var vel: Vector3 = w.get_meta("draw_vel", Vector3.ZERO)
	if nocked:
		var ease := 1.0
		var want := w.to_local(fingers) - rest
		if want.length() > float(sp["max"]):
			want = want.normalized() * float(sp["max"])
		off = want * ease
		vel = Vector3.ZERO
	else:
		var relaxed := relax_bow_string(off, vel, dt, sp["pull"])
		off = relaxed[0]
		vel = relaxed[1]
	w.set_meta("draw_off", off)
	w.set_meta("draw_vel", vel)
	w.set_meta("draw_s", off.dot(sp["pull"]))
	var nock := rest + off
	var strands: Array = w.get_meta("strands")
	_strand(strands[0], sp["tips"][0], nock)
	_strand(strands[1], sp["tips"][1], nock)
	var arrow: Node3D = w.get_meta("nocked")
	arrow.visible = nocked
	if nocked:
		var dir := ((sp["grip"] as Vector3) - nock).normalized()
		arrow.transform = Transform3D(Basis.looking_at(dir, sp["limb"]), nock + dir * 0.36)

## Bound the stiff string spring's integration step independently of render FPS.
## A 100 ms frame made the old single Euler step gain energy until the bow became NaN.
static func relax_bow_string(off: Vector3, vel: Vector3, dt: float, pull: Vector3) -> Array[Vector3]:
	if not off.is_finite() or not vel.is_finite(): return [Vector3.ZERO, Vector3.ZERO]
	var remaining := clampf(dt, 0.0, 0.1)
	while remaining > 0.0:
		var step := minf(remaining, 1.0 / 120.0)
		vel += (-off * 1500.0 - vel * 34.0) * step
		off += vel * step
		var along := off.dot(pull)
		if along < -0.04:
			off -= pull * (along + 0.04)
		remaining -= step
	if off.length() < 0.0005 and vel.length() < 0.01:
		return [Vector3.ZERO, Vector3.ZERO]
	return [off, vel]

static func _curve(pts: Array, a: float) -> float:
	if pts.is_empty() or a < float(pts[0][0]):
		return 0.0
	for i in range(1, pts.size()):
		if a <= float(pts[i][0]):
			return lerpf(float(pts[i - 1][1]), float(pts[i][1]), smoothstep(float(pts[i - 1][0]), float(pts[i][0]), a))
	return float(pts[pts.size() - 1][1])

## The arrow in his right hand, from the quiver to the string (made once, beside the bow): pinched by its nock at his
## fingers, its point first down into the quiver on his back, then swung round onto the bow as he brings it forward.
static func _hand_arrow(rig: Node3D, w: Node3D, fingers: Vector3, palm: Vector3, show: bool, k: float) -> void:
	var ar: Node3D = w.get_node_or_null("HandArrow")
	if ar == null:
		if not show:
			return
		ar = (w.get_meta("nocked") as Node3D).duplicate()
		ar.name = "HandArrow"
		w.add_child(ar)
	ar.visible = show
	if not show:
		return
	# the quiver turns with his body (the shot turns him side-on)
	var br = rig.get("body_root")
	var bb: Basis = (br as Node3D).global_transform.basis.orthonormalized() if br is Node3D else rig.global_transform.basis.orthonormalized() * Basis(Vector3.UP, PI)
	var quiver: Vector3 = rig.global_position + bb * QUIVER
	var d := (quiver - fingers).normalized().slerp((palm - fingers).normalized(), smoothstep(0.0, 1.0, k))
	var upv := Vector3.UP if absf(d.y) < 0.95 else Vector3.BACK
	var sc := w.global_transform.basis.get_scale()
	ar.global_transform = Transform3D(Basis.looking_at(d, upv).scaled(sc), fingers + d * 0.36 * sc.x)

## The bow's straight string swapped for two strands that can be drawn back, and an arrow to nock.
static func _rig_bow(w: Node3D) -> void:
	var old := w.find_child("string", true, false) as MeshInstance3D
	var mat: Material = old.material_override if old != null and old.material_override != null else Mats.mat(Color(0.85, 0.8, 0.7), 0.6)
	if old != null:
		old.visible = false
	var strands := []
	for k in 2:
		var mi := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.0035
		cm.bottom_radius = 0.0035
		cm.height = 1.0
		cm.radial_segments = 4
		cm.rings = 1
		mi.mesh = cm
		mi.material_override = mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		w.add_child(mi)
		strands.append(mi)
	var arrow := Node3D.new()
	var shaft := MeshInstance3D.new()
	var sm := CylinderMesh.new()
	sm.top_radius = 0.006
	sm.bottom_radius = 0.006
	sm.height = 0.72
	shaft.mesh = sm
	shaft.rotation_degrees = Vector3(90, 0, 0)
	shaft.material_override = Mats.mat(Color(0.32, 0.23, 0.14), 0.8)
	arrow.add_child(shaft)
	var head := MeshInstance3D.new()
	var hm := CylinderMesh.new()
	hm.top_radius = 0.0
	hm.bottom_radius = 0.016
	hm.height = 0.06
	head.mesh = hm
	head.rotation_degrees = Vector3(-90, 0, 0)
	head.position = Vector3(0, 0, -0.39)
	head.material_override = Mats.mat(Color(0.5, 0.5, 0.52), 0.35, 0.9)
	arrow.add_child(head)
	for k in 3:
		var f := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.002, 0.03, 0.09)
		f.mesh = bm
		f.position = Vector3(0, 0, 0.29)
		f.rotation = Vector3(0, 0, TAU * k / 3.0)
		f.material_override = Mats.mat(Color(0.75, 0.72, 0.65), 0.9)
		var off := Node3D.new()
		off.rotation = Vector3(0, 0, TAU * k / 3.0)
		arrow.add_child(off)
		f.rotation = Vector3.ZERO
		f.position = Vector3(0, 0.016, 0.29)
		off.add_child(f)
	arrow.visible = false
	w.add_child(arrow)
	w.set_meta("strands", strands)
	w.set_meta("nocked", arrow)
	w.set_meta("bow_rig", true)

static func _strand(mi: MeshInstance3D, a: Vector3, b: Vector3) -> void:
	var d := b - a
	var L := d.length()
	if L < 0.001:
		return
	var y := d / L
	var x := y.cross(Vector3.UP if absf(y.dot(Vector3.UP)) < 0.95 else Vector3.RIGHT).normalized()
	var z := x.cross(y)
	mi.transform = Transform3D(Basis(x, y * L, z), (a + b) * 0.5)
