class_name Archer
extends RefCounted
## The archer (the bow class, Jace's; its name is still his to choose). With a bow in his hands his attack
## shoots: Hero.swipe_attack and free_attack come here (`shoot`), he stops at RANGE from a clicked foe
## (Hero.reach) and keeps shooting while the button is held. His skills (Data.SKILLS "cls": "archer"):
##   Piercing Shot: a heavy arrow through every enemy in a line;
##   Volley: arrows into the sky that rain on the cursor, hitting all within reach again and again;
##   Snare Trap: an iron trap thrown to the cursor that holds fast (stuns) the first enemies on it;
##   Spirit Beast: a spectral beast (the lion's body, ghostly) that hunts with him for 30 s, and the
##     class's 12 s battle buff (+40% damage).
## Everything in flight or lying in wait lives on the hero (arrows, volleys, snares, beasts), updated
## by `update` and cleared by `clear`. Local only, like every class's skill effects (damage to monsters
## goes through Enemy.take_damage, which routes to the host in co-op).
## Body: until the Meshy archer exists, the knight's procedural body dressed as a hooded hunter.

const RANGE := 13.0
const ARROW_SPEED := 34.0
const VOLLEY_R := 4.0
const SNARE_R := 2.2
const BEAST_TIME := 30.0
const HUNTER := Color(0.62, 0.85, 0.75)     # the class's colour: pale spirit-green

## The ranger (assets/models/archer_ranger.glb, tools/blender/archer/prep_ranger_mocap.py): the Meshy northern ranger
## (wolf-fur cowl, dark leather, quiver on his back) on the knight's mocap system (Knight.build_mocap,
## knight_mocap_rig.gd): motion capture for idle, walk and run (bow raised and aimed when it's out: "combat_idle",
## "walk_aim"), the shot as a whole-body clip (`SHOT`: nock, draw, loose on the attack's release frame, follow
## through), his casts (Snare Trap, Spirit Beast) as the game's own moves laid over the upper body. The bow is the
## game's (whatever is equipped), held in his LEFT hand like the clips (J "grip_bow", `BOW_HOLD`).
const RANGER_GLB := "res://assets/models/archer_ranger.glb"
const SHOT := {"style": "bow", "clip": "shoot_back",
	# "Draw and Shoot from Back" (7.8 s) squeezed into the attack, by its phases: reach over the shoulder (0.2 s),
	# the hand at the quiver (0.8), the arrow out (1.6), at the bow and nocked (2.2), the bow raised (3.1),
	# full draw (5.0), the release (6.8, on Anim's impact frame 0.72), the arms coming down (7.35)
	"keys": [[0.0, 0.2], [0.16, 0.8], [0.28, 1.6], [0.38, 2.2], [0.46, 3.1], [0.62, 5.0], [0.72, 6.8], [1.0, 7.35]],
	"yaw": -56.0, "stand_yaw": -90.0, "idle_side": true,
	"walk_clip": "walk_aim", "walk_speed": 0.82,
	# on the move: only his right arm reaches back for the arrow (over the aimed walk), then draws to his cheek
	"reach_clip": "shoot_back", "reach_bones": ["RightShoulder", "RightArm", "RightForeArm", "RightHand"],
	"reach_keys": [[0.0, 0.2], [0.16, 0.8], [0.3, 1.6], [1.0, 1.6]],
	"reach": [[0.0, 0.0], [0.07, 1.0], [0.3, 1.0], [0.44, 0.0]]}
## when the hand closes on an arrow in the quiver and when it's on the string (of the shot's progress), standing and moving
const GRAB := 0.15
const NOCK := 0.38
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
	# the ranger's carved recurve (assets/models/ranger_bow.glb, measured by prep_bow.py: limbs up +y, the string on
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

## His colours (tools/archer_colors.py recolours the Meshy texture: hood, tunic, coat and trousers dyed, the fur,
## leather straps, hands and face left as they are), so he stands out against the moor: "crimson" (default),
## "teal", "verdant", "royal" (assets/textures/ranger/ranger_<name>.jpg). "" keeps Meshy's black and grey.
const COLORS := "crimson"

static func dye(r: Node3D, scheme: String) -> void:
	var path := "res://assets/textures/ranger/ranger_%s.jpg" % scheme
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
	var g := Knight.default_gear()
	g["cloth"] = Color(0.13, 0.17, 0.11)
	g["cape"] = Color(0.09, 0.1, 0.09)
	g["quilt"] = Color(0.27, 0.22, 0.16)
	g["leather"] = Color(0.24, 0.16, 0.1)
	g["emblem"] = Color(0.5, 0.42, 0.3)
	g["steel"] = Color(0.32, 0.31, 0.3)
	g["trim"] = Color(0.45, 0.36, 0.22)
	g["hair"] = Color(0.12, 0.09, 0.07)
	g["coif"] = true
	var r := Knight.build(g)
	r.set_meta("archer", true)
	return r

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
	h.atk_aim = _assist(h, aim)
	h.atk_target = null
	h._face(h.atk_aim - h.global_position)
	h._start_attack("bow")

## Aim help: an enemy near the point aimed at is the one aimed at.
static func _assist(h: Hero, aim: Vector3) -> Vector3:
	var best = null
	var bd := 2.6
	for e in h.game.enemies_near(aim, 2.6):
		var d: float = Vector2(e.global_position.x - aim.x, e.global_position.z - aim.z).length()
		if not e.dead and d < bd:
			bd = d
			best = e
	return best.global_position if best != null else aim

static func cast(h: Hero, id: String, aim: Vector3) -> void:
	match id:
		"pierce":
			h.atk_aim = _assist(h, aim)
			h._face(h.atk_aim - h.global_position)
			h._start_attack("bow", "pierce")
			h.atk_dur *= 1.15
		"volley":
			var to := (aim - h.global_position) * Vector3(1, 0, 1)
			h.atk_aim = h.global_position + to.limit_length(14.0)
			h._start_attack("bow", "volley")
		"snare":
			var to2 := (aim - h.global_position) * Vector3(1, 0, 1)
			h.atk_aim = h.global_position + to2.limit_length(10.0)
			h._start_attack("cast", "snare")
			h.atk_dur = 0.4
		"beast":
			h._start_attack("cast", "beast")
			h.atk_dur = 0.6

## The release (Hero._impact): true when it was the archer's.
static func impact(h: Hero) -> bool:
	if not h.is_archer():
		return false
	match h.atk_skill:
		"":
			if h.atk_style != "bow":
				return false
			var n := 3 if h.talent("arrow_split") > 0.0 else 1
			for k in n:
				var spread := (float(k) - (n - 1) * 0.5) * 0.16
				_loose(h, h.atk_aim, false, 1.0 if k == (n - 1) / 2 else 0.5, "attack", spread)
		"pierce":
			_loose(h, h.atk_aim, true, 1.3, "pierce", 0.0)
		"volley":
			_volley(h, h.atk_aim)
		"snare":
			_set_snare(h, h.atk_aim)
		"beast":
			_call_beast(h)
		_:
			return false
	return true

## An arrow from the bow toward at (turned by yaw radians), flying flat at chest height.
static func _loose(h: Hero, at: Vector3, pierce: bool, mult: float, src: String, yaw: float) -> void:
	var from: Vector3 = h.global_position + Vector3(0, 1.35, 0)
	var dir := (at - h.global_position) * Vector3(1, 0, 1)
	dir = dir.normalized() if dir.length() > 0.1 else -h.rig.global_transform.basis.z
	dir = dir.rotated(Vector3.UP, yaw)
	from += dir * 0.6
	# off the bow in his hand, where the nocked arrow lay
	var J: Dictionary = h.rig.get_meta("j")
	if J.has("at_hand_l") and h.weapon_node != null and is_instance_valid(h.weapon_node) and h.weapon_node.get_parent() == J.get("grip_bow_at"):
		from = (J["at_hand_l"] as Node3D).global_position + dir * 0.15
	var n := _arrow_mesh(pierce)
	h.game.world.fx_root.add_child(n)
	n.global_position = from
	n.look_at(from + dir, Vector3.UP)
	h.arrows.append({"node": n, "dir": dir, "left": RANGE + 5.0, "pierce": pierce, "hit": {}, "mult": mult, "src": src})

static func _arrow_mesh(heavy: bool) -> Node3D:
	var root := Node3D.new()
	var shaft := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.012 if not heavy else 0.018
	cm.bottom_radius = cm.top_radius
	cm.height = 0.72
	shaft.mesh = cm
	shaft.rotation_degrees = Vector3(90, 0, 0)
	shaft.material_override = Mats.mat(Color(0.28, 0.2, 0.12), 0.8)
	root.add_child(shaft)
	var head := MeshInstance3D.new()
	var hm := CylinderMesh.new()
	hm.top_radius = 0.0
	hm.bottom_radius = 0.03 if not heavy else 0.045
	hm.height = 0.09
	head.mesh = hm
	head.rotation_degrees = Vector3(-90, 0, 0)
	head.position = Vector3(0, 0, -0.4)
	head.material_override = Mats.mat(Color(0.5, 0.5, 0.52), 0.35, 0.9)
	root.add_child(head)
	# a faint streak behind it so it reads in flight from the high camera
	var glow := MeshInstance3D.new()
	var gm := CylinderMesh.new()
	gm.top_radius = 0.025 if not heavy else 0.05
	gm.bottom_radius = 0.0
	gm.height = 1.2 if not heavy else 1.8
	glow.mesh = gm
	glow.rotation_degrees = Vector3(90, 0, 0)
	glow.position = Vector3(0, 0, 0.7)
	glow.material_override = Mats.glow(HUNTER if heavy else Color(0.9, 0.85, 0.7), 1.2 if heavy else 0.6, 0.0, 0.0)
	glow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(glow)
	return root

# ---------------------------------------------------------------- Volley
static func _volley(h: Hero, at: Vector3) -> void:
	var g := Vector3(at.x, h.game.world.height_at(at.x, at.z), at.z)
	var r := VOLLEY_R * (1.0 + h.talent("volley_size") / 100.0)
	h.volleys.append({"pos": g, "t": 1.3, "tick": 0.25, "r": r})
	Fx.telegraph(h.game.world.fx_root, g, r, 0.25, HUNTER)
	# the flight going up
	for k in 5:
		var up := _arrow_mesh(false)
		h.game.world.fx_root.add_child(up)
		var p0: Vector3 = h.global_position + Vector3(randf_range(-0.3, 0.3), 1.6, randf_range(-0.3, 0.3))
		up.global_position = p0
		up.look_at(p0 + Vector3(randf_range(-0.2, 0.2), 1.0, randf_range(-0.2, 0.2)), Vector3.FORWARD)
		var tw := up.create_tween()
		tw.tween_property(up, "global_position", p0 + Vector3(0, 9.0, 0), 0.3)
		tw.tween_callback(up.queue_free)

## Arrows falling on the volley's ground: a hit on everything in reach every 0.2 s, arrows sticking in.
static func _rain(h: Hero, v: Dictionary) -> void:
	var root: Node3D = h.game.world.fx_root
	var pos: Vector3 = v["pos"]
	var r: float = v["r"]
	for k in 6:
		var a := randf() * TAU
		var d := sqrt(randf()) * r
		var p := pos + Vector3(cos(a) * d, 0, sin(a) * d)
		p.y = h.game.world.height_at(p.x, p.z)
		var ar := _arrow_mesh(false)
		root.add_child(ar)
		ar.global_position = p + Vector3(randf_range(-0.6, 0.6), 7.0, randf_range(-0.6, 0.6))
		ar.look_at(p, Vector3.FORWARD)
		var tw := ar.create_tween()
		tw.tween_property(ar, "global_position", p + Vector3(0, 0.25, 0), 0.18)
		tw.tween_callback(func(): Fx.burst(root, p + Vector3(0, 0.1, 0), Color(0.4, 0.35, 0.28, 0.7), 4, 1.0, 0.12, 0.4, false, -3.0, 70.0))
		tw.tween_interval(1.4)
		tw.tween_callback(ar.queue_free)
	for e in h.game.enemies_near(pos, r):
		if not e.dead:
			h._hit_enemy(e, 0.35, 0.0, "volley")
	Sfx.play_at("bow", pos, -10.0, randf_range(0.8, 0.95))

# ---------------------------------------------------------------- Snare Trap
static func _set_snare(h: Hero, at: Vector3) -> void:
	var g := Vector3(at.x, h.game.world.height_at(at.x, at.z), at.z)
	var mx := 2 + int(h.talent("snare_max"))
	while h.snares.size() >= mx:
		var old: Dictionary = h.snares.pop_front()
		if is_instance_valid(old["node"]):
			(old["node"] as Node3D).queue_free()
	var n := _snare_mesh()
	h.game.world.fx_root.add_child(n)
	n.global_position = g + Vector3(0, 0.03, 0)
	h.snares.append({"node": n, "pos": g, "t": 20.0})
	Fx.ring(h.game.world.fx_root, g, 0.9, HUNTER, 0.4)
	Sfx.play_at("impact_metal", g, -8.0, 1.3)

## An iron jaw trap: two toothed half-rings open on a plate, a faint glow round it.
static func _snare_mesh() -> Node3D:
	var root := Node3D.new()
	var iron := Mats.mat(Color(0.25, 0.24, 0.23), 0.5, 0.8)
	var plate := MeshInstance3D.new()
	var pm := CylinderMesh.new()
	pm.top_radius = 0.16
	pm.bottom_radius = 0.18
	pm.height = 0.04
	plate.mesh = pm
	plate.material_override = iron
	root.add_child(plate)
	for side in [-1.0, 1.0]:
		var jaw := Node3D.new()
		jaw.name = "jaw_l" if side < 0.0 else "jaw_r"
		jaw.rotation.z = side * 1.25
		root.add_child(jaw)
		var arc := MeshInstance3D.new()
		var tm := TorusMesh.new()
		tm.inner_radius = 0.33
		tm.outer_radius = 0.37
		arc.mesh = tm
		arc.scale = Vector3(1, 1, 0.5)
		arc.position = Vector3(side * 0.0, 0.0, 0)
		arc.material_override = iron
		jaw.add_child(arc)
		for k in 6:
			var tooth := MeshInstance3D.new()
			var tc := CylinderMesh.new()
			tc.top_radius = 0.0
			tc.bottom_radius = 0.02
			tc.height = 0.07
			tooth.mesh = tc
			var a := (float(k) + 0.5) / 6.0 * PI
			tooth.position = Vector3(cos(a) * 0.35, 0.04, sin(a) * 0.35 * side)
			tooth.material_override = iron
			jaw.add_child(tooth)
	var glow := OmniLight3D.new()
	glow.light_color = HUNTER
	glow.light_energy = 0.5
	glow.omni_range = 1.6
	glow.position = Vector3(0, 0.4, 0)
	root.add_child(glow)
	return root

static func _spring(h: Hero, s: Dictionary) -> void:
	var pos: Vector3 = s["pos"]
	var r := SNARE_R if h.talent("snare_wide") <= 0.0 else 4.0
	var hold := 3.0 + h.talent("snare_dur")
	for e in h.game.enemies_near(pos, r):
		if not e.dead:
			e.stun(hold)
			h._hit_enemy(e, 1.2, 0.0, "snare")
	var n: Node3D = s["node"]
	if is_instance_valid(n):
		var tw := n.create_tween().set_parallel(true)
		for j in ["jaw_l", "jaw_r"]:
			tw.tween_property(n.get_node(j), "rotation:z", 0.0, 0.08)
		tw.chain().tween_interval(0.8)
		tw.chain().tween_callback(n.queue_free)
	Fx.sparks(h.game.world.fx_root, pos + Vector3(0, 0.3, 0), Color(0.9, 0.85, 0.7))
	Fx.ring(h.game.world.fx_root, pos, r, HUNTER, 0.35)
	Sfx.play_at("impact_metal", pos, 0.0, 0.8)
	h.game.add_shake(0.1)

# ---------------------------------------------------------------- Spirit Beast
static func _call_beast(h: Hero) -> void:
	for b in h.beasts:
		if is_instance_valid(b):
			b.dismiss()
	h.beasts.clear()
	var n := 2 if h.talent("beast_two") > 0.0 else 1
	var fwd: Vector3 = -h.rig.global_transform.basis.z
	for k in n:
		var side := Vector3(fwd.z, 0, -fwd.x) * (1.2 if k == 0 else -1.2)
		var pos: Vector3 = h.game.world.move(h.global_position, fwd * 1.6 + side * (1.0 if n > 1 else 0.0))
		pos.y = h.game.world.height_at(pos.x, pos.z)
		var b := SpiritBeast.new()
		h.game.add_child(b)
		b.setup(h, h.game, k)
		b.global_position = pos
		h.beasts.append(b)
		Fx.burst(h.game.world.fx_root, pos + Vector3(0, 0.6, 0), HUNTER, 30, 3.0, 0.14, 0.8, true, 1.0)
	h.buff_t = 12.0 + h.talent("buff_dur")
	Sfx.play("lion_roar", -4.0, 1.25)
	Sfx.play("summon", -6.0, 1.1)
	h.game.add_shake(0.2)

# ---------------------------------------------------------------- every frame
static func update(h: Hero, delta: float) -> void:
	if h.arrows.is_empty() and h.volleys.is_empty() and h.snares.is_empty():
		return
	var w = h.game.world
	for a in h.arrows.duplicate():
		var n = a["node"]
		if not is_instance_valid(n):
			h.arrows.erase(a)
			continue
		var step := ARROW_SPEED * delta
		var p: Vector3 = n.global_position
		var np: Vector3 = w.move(p, (a["dir"] as Vector3) * step, 0.05)
		var moved := np - p
		moved.y = 0
		np.y = w.height_at(np.x, np.z) + 1.3
		n.global_position = np
		a["left"] -= step
		var stop: bool = a["left"] <= 0.0 or moved.length() < step * 0.4
		for e in h.game.enemies_near(np, 1.6):
			if e.dead or (a["hit"] as Dictionary).has(e):
				continue
			var d := _seg_dist(Vector2(e.global_position.x, e.global_position.z), Vector2(p.x, p.z), Vector2(np.x, np.z))
			if d < e.radius + 0.35:
				a["hit"][e] = true
				h._hit_enemy(e, a["mult"], 0.25 if not a["pierce"] else 0.5, a["src"])
				Fx.sparks(w.fx_root, e.global_position + Vector3(0, e.height, 0), Color(0.9, 0.85, 0.7))
				if not a["pierce"]:
					stop = true
					break
		if stop:
			n.queue_free()
			h.arrows.erase(a)
	for v in h.volleys.duplicate():
		v["t"] -= delta
		v["tick"] -= delta
		if v["tick"] <= 0.0:
			v["tick"] = 0.2
			_rain(h, v)
		if v["t"] <= 0.0:
			h.volleys.erase(v)
	for s in h.snares.duplicate():
		s["t"] -= delta
		var n2 = s["node"]
		if s["t"] <= 0.0 or not is_instance_valid(n2):
			if is_instance_valid(n2):
				n2.queue_free()
			h.snares.erase(s)
			continue
		for e in h.game.enemies_near(s["pos"], 1.1):
			if not e.dead:
				h.snares.erase(s)
				_spring(h, s)
				break

static func _seg_dist(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var t := clampf((p - a).dot(ab) / maxf(ab.length_squared(), 0.0001), 0.0, 1.0)
	return (a + ab * t).distance_to(p)

static func clear(h: Hero) -> void:
	for a in h.arrows:
		if is_instance_valid(a["node"]):
			(a["node"] as Node3D).queue_free()
	h.arrows.clear()
	h.volleys.clear()
	for s in h.snares:
		if is_instance_valid(s["node"]):
			(s["node"] as Node3D).queue_free()
	h.snares.clear()
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
		solve = _curve([[0.0, 0.0], [0.08, 1.0], [imp + 0.05, 1.0], [imp + 0.22, 0.0]], a)
		on_string = _curve([[nock_at - 0.06, 0.0], [nock_at, 1.0]], a)
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
	_hand_arrow(rig, w, fingers, (J["grip_bow"] as Node3D).global_position, carrying, _curve([[0.27, 0.0], [nock_at, 1.0]], a))
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
		# loosed (or never drawn): the string flies home and shivers
		vel += (-off * 1500.0 - vel * 34.0) * dt
		off += vel * dt
		var along := off.dot(sp["pull"])
		if along < -0.04:
			off -= (sp["pull"] as Vector3) * (along + 0.04)      # a little past straight, no further
		if off.length() < 0.0005 and vel.length() < 0.01:
			off = Vector3.ZERO
			vel = Vector3.ZERO
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
