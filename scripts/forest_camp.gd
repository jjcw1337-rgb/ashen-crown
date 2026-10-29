class_name ForestCamp
extends RefCounted
## Act I's camp, the Forsaken Wilds, as an encampment deep in an old misty forest (World._build_town hands over
## to this when World.oak_forest and act 0; A2/A3 keep the old camp). A ring palisade of sharpened
## logs with a gatehouse to the north, glowing rune stones in the trees outside it, a bonfire at the
## heart, tents and huge oaks hung with lanterns inside, and the shops round the ring, each with its
## shopkeeper at work: Meshy-made and Meshy-rigged, animated with Meshy's clip library (Inter._animate).
## Models: assets/models/camp/*.glb, assets/models/npc/*.glb, prepared in Blender (tools/blender/
## prep_prop.py, prep_npc.py, prep_tree.py). Without the files it falls back to the old camp.

const CENTER := Vector2(0, -2)
const RADIUS := 25.0
const GATE_HALF := 0.23         # half the gap in the ring for the gatehouse (radians)
const DIR := "res://assets/models/camp/"
const STALL_SCALE := 1.45     # the stalls, tents and gatehouse read small from the game's camera at true size
const NPC_DIR := "res://assets/models/npc/"
# shopkeepers: model, role, the stall they keep, its spot, and their clips (idle, work, talk)
const SHOPS := [
	{"role": "alch", "npc": "maeve", "stall": "alchemy", "at": Vector2(-12, -11.5), "half": Vector2(1.45, 1.3),
		"clips": {"idle": "Idle_02", "work": ["Stand_and_Drink", "mage_soell_cast"], "talk": "Talk_with_Left_Hand_Raised"},
		"hold": {"bone": "RightHand", "potion": Color(0.35, 1.0, 0.3), "pos": Vector3(0.0, 0.07, 0.03)}},
	# the smith works inside his forge, behind the anvil ("inside": his spot in the stall's own frame, facing out)
	{"role": "smith", "npc": "grisold", "stall": "forge", "at": Vector2(12, -11.5), "half": Vector2(2.2, 1.65), "inside": Vector2(0.05, 0.35),
		"clips": {"idle": "Idle", "work": ["Heavy_Hammer_Swing"], "talk": "Talk_with_Hands_Open", "stay": true},
		"hold": {"bone": "RightHand", "item": "war_hammer", "rot": Vector3(0, 0, 90), "pos": Vector3(0.0, 0.08, 0.0)}},
	{"role": "armor", "npc": "hedda", "stall": "armory", "at": Vector2(16, 5), "half": Vector2(1.95, 1.62),
		"clips": {"idle": "Idle_3", "work": ["Axe_Breathe_and_Look_Around"], "talk": "Talk_with_Left_Hand_on_Hip"},
		"hold": {"bone": "RightHand", "item": "hand_axe", "rot": Vector3(0, 0, 90), "pos": Vector3(0.0, 0.08, 0.0)}},
	{"role": "gamble", "npc": "tarrow", "stall": "wagon", "at": Vector2(-15.5, 7), "half": Vector2(1.7, 1.35),
		"clips": {"idle": "Idle_5", "work": ["Stand_and_Chat", "Happy_Sway_Standing"], "talk": "Talk_with_Right_Hand_Open"}},
]

static func ok() -> bool:
	for f in ["palisade", "gate", "forge", "alchemy", "armory", "wagon", "bonfire", "tent", "runestone", "lantern"]:
		if not ResourceLoader.exists(DIR + f + ".glb"):
			return false
	for f in ["maeve", "grisold", "hedda", "tarrow", "roth"]:
		if not ResourceLoader.exists(NPC_DIR + f + ".glb"):
			return false
	return true

static var _meshes := {}
## A model's meshes merged into one (for MultiMesh): the palisade logs, rune stones, trees.
static func mesh(path: String) -> Mesh:
	if _meshes.has(path):
		return _meshes[path]
	var sc: Node = (load(path) as PackedScene).instantiate()
	var out := ArrayMesh.new()
	for n in sc.find_children("*", "MeshInstance3D", true, false):
		var mi: MeshInstance3D = n
		for si in mi.mesh.get_surface_count():
			out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, mi.mesh.surface_get_arrays(si))
			out.surface_set_material(out.get_surface_count() - 1, mi.mesh.surface_get_material(si))
	sc.free()
	_meshes[path] = out
	return out

static func model(name: String) -> Node3D:
	return (load(DIR + name + ".glb") as PackedScene).instantiate()

## Yaw that turns a model's front (+z) toward a point.
static func face(from: Vector2, to: Vector2) -> float:
	var d := to - from
	return atan2(d.x, d.y)

static func ring_pt(a: float, r: float) -> Vector2:
	return CENTER + Vector2(sin(a), -cos(a)) * r

static func build(w: World) -> void:
	w.bounds = Rect2(-38, -42, 76, 80)
	w.theme = {"name": "town", "forest_camp": true}
	var V: Dictionary = Data.VENDORS[w.act]
	var rng := w.rng
	var gate_z := CENTER.y - RADIUS
	# --- ground: a trodden clearing, paths to each shop and out of the gate
	w.dirt_blobs = [[CENTER, 11.0, 1.0], [Vector2(0, gate_z + 3), 5.0, 0.95], [Vector2(-8, 6), 3.5, 0.9]]
	w.dirt_lines = [[Vector2(0, 0), Vector2(0, gate_z - 9), 3.2]]
	for s in SHOPS:
		var p: Vector2 = s["at"]
		w.dirt_blobs.append([p, 5.2, 1.0])
		w.dirt_blobs.append([p.lerp(CENTER, 0.3), 4.2, 0.95])
		w.dirt_lines.append([CENTER, p, 2.4])
	w.cobble_blobs = [[CENTER, 4.2, 0.85], [Vector2(0, gate_z + 1.5), 3.0, 0.8], [Vector2(-8, 6), 2.6, 0.7]]

	# --- the palisade: sharpened logs all round, a gap for the gatehouse to the north
	var pal_x := []
	var step := 3.9 / RADIUS
	var a := GATE_HALF + step * 0.5
	while a < TAU - GATE_HALF - step * 0.3:
		var p := ring_pt(a, RADIUS + rng.randf_range(-0.15, 0.15))
		var yaw := face(p, CENTER) + rng.randf_range(-0.03, 0.03)
		var sc := rng.randf_range(0.93, 1.08)
		pal_x.append(Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3(1.0, sc, 1.0)), Vector3(p.x, w.height_at(p.x, p.y) - 0.1, p.y)))
		w.add_box(Vector3(p.x, 0, p.y), Vector2(2.1, 0.55), yaw)
		a += step
	Props.multimesh(w.props_root, mesh(DIR + "palisade.glb"), pal_x)
	var gate := model("gate")
	w._place(gate, Vector3(0, 0, gate_z))
	gate.scale = Vector3.ONE * 1.15
	for gx in [-4.1, 4.1]:
		w.add_box(Vector3(gx, 0, gate_z), Vector2(1.15, 2.2), 0.0)
	_lantern(w, Vector3(0, w.height_at(0, gate_z) + 4.7, gate_z + 0.4), true)
	w.exits.append({"pos": Vector3(0, 0, gate_z - 3.5), "radius": 3.5, "to": "wild", "label": w.act_name("wild")})

	# --- rune stones standing in the trees outside the wall, glowing faintly
	var rs := []
	var rune_mat := _rune_material()
	for i in 11:
		var ra := TAU * (i + 0.5) / 11.0
		if absf(wrapf(ra, -PI, PI)) < 0.45:
			continue
		var p := ring_pt(ra + rng.randf_range(-0.08, 0.08), RADIUS + rng.randf_range(4.5, 7.0))
		rs.append(Transform3D(Basis(Vector3.UP, face(p, CENTER)).scaled(Vector3.ONE * rng.randf_range(0.85, 1.2)), Vector3(p.x, w.height_at(p.x, p.y) - 0.15, p.y)))
	var rmm := Props.multimesh(w.props_root, mesh(DIR + "runestone.glb"), rs)
	rmm.material_override = rune_mat

	# --- the heart of the camp: the bonfire, seats, stash and waypoint
	var bf := model("bonfire")
	w._place(bf, Vector3(CENTER.x, 0, CENTER.y))
	Props.fire(bf, Vector3(0, 0.3, 0), 1.15, Color(1.0, 0.5, 0.18), true, true)
	w.add_circle(Vector3(CENTER.x, 0, CENTER.y), 1.4)
	for i in 4:
		var la := TAU * i / 4.0 + 0.6
		var lg := Props.footprint(Models.N(null, "seat"), Vector2(0.25, 0.8))
		Models.P(lg, Geo.cyl(0.22, 0.24, 1.6, 10), Props.wood(), Vector3(0, 0.2, 0), Vector3(90, 0, 0))
		w._place(lg, Vector3(CENTER.x + cos(la) * 3.6, 0, CENTER.y + sin(la) * 3.6))
		lg.rotation.y = -la
		w.solid(lg)
	var chest := Props.stash_chest(null, Vector3.ZERO, -15.0)
	w._inter("stash", "Stash", Vector3(4.2, 0, 3.2), 1.6, chest)
	w.solid(chest)
	var wp := Props.waypoint(null, Vector3.ZERO)
	w._inter("waypoint", "Waypoint", Vector3(-8, 0, 6), 2.4, wp)
	for i in 4:
		var pa := TAU * i / 4.0 + PI * 0.25
		w.add_circle(Vector3(-8 + cos(pa) * 1.85, 0, 6 + sin(pa) * 1.85), 0.3)

	# --- the shops round the ring, each keeper in front of their stall
	for s in SHOPS:
		var p: Vector2 = s["at"]
		var yaw := face(p, CENTER)
		var stall := model(s["stall"])
		w._place(stall, Vector3(p.x, 0, p.y))
		stall.rotation.y = yaw
		stall.scale = Vector3.ONE * STALL_SCALE
		var half: Vector2 = (s["half"] as Vector2) * STALL_SCALE
		w.add_box(Vector3(p.x, 0, p.y), half * 0.92, yaw)
		var fwd := Vector2(sin(yaw), cos(yaw))
		var np := p + fwd * (half.y + 0.9)
		var lp: Vector2 = s.get("inside", Vector2.ZERO) * STALL_SCALE
		if s.has("inside"):
			np = p + Vector2(cos(yaw), -sin(yaw)) * lp.x + fwd * lp.y
		var kp := _keeper(w, s["npc"], V[s["role"]], s["role"], np, yaw, s["clips"])
		if s.has("inside"):
			kp.radius = half.y - lp.y + 1.3      # talked to from in front of the stall

		if s.has("hold"):
			hold(kp.model, s["hold"])
			kp.set_meta("hold", s["hold"])
	# the stalls' own light: the forge's coals, the alchemist's cauldron, a lantern on the others
	_glow(w, SHOPS[1]["at"], Vector3(0.9, 1.4, -0.6), Color(1.0, 0.45, 0.12), 2.6, 7.0)
	_glow(w, SHOPS[0]["at"], Vector3(-1.3, 0.9, 0.4), Color(0.4, 1.0, 0.35), 1.6, 6.0)
	_lantern(w, _local(w, SHOPS[2]["at"], Vector3(2.4, 4.0, 1.9)), true)
	_lantern(w, _local(w, SHOPS[3]["at"], Vector3(-2.0, 3.6, 2.0)), true)
	# Captain Roth keeps the gate
	_keeper(w, "roth", V["elder"], "elder", Vector2(5.0, gate_z + 5.0), face(Vector2(5.0, gate_z + 5.0), CENTER),
		{"idle": "Idle", "work": ["Short_Breathe_and_Look_Around", "Long_Breathe_and_Look_Around"], "talk": "Talk_Passionately"})
	for bx in [-5.5, 5.5]:
		w.solid(Props.banner(w.props_root, Vector3(bx, w.height_at(bx, gate_z + 2.2), gate_z + 2.2), Color(0.42, 0.06, 0.05), Color(0.6, 0.5, 0.25)))

	# --- tents round the inside of the wall
	for t in [[-0.75, 19.5], [-1.45, 19.0], [-2.35, 19.0], [2.35, 19.0], [2.85, 18.5], [-2.9, 18.5], [0.8, 19.5], [3.4, 19.5], [-3.45, 19.5], [1.45, 19.5]]:
		var tp := ring_pt(t[0], t[1])
		if _near_shop(tp, 6.0):
			continue
		var tent := model("tent")
		w._place(tent, Vector3(tp.x, 0, tp.y))
		tent.rotation.y = face(tp, CENTER) + rng.randf_range(-0.25, 0.25)
		tent.scale = Vector3.ONE * 1.25
		w.add_box(Vector3(tp.x, 0, tp.y), Vector2(2.2, 1.9), tent.rotation.y)
	# clutter by the stalls
	for c in [["crate", Vector2(-9.5, -15.5)], ["barrel", Vector2(-15.8, -8.8)], ["barrel", Vector2(15.6, -8.6)], ["logs", Vector2(9.0, -15.5)],
			["crate", Vector2(18.8, 1.4)], ["crate", Vector2(19.4, 2.2)], ["barrel", Vector2(-18.4, 4.0)], ["crate", Vector2(-3.5, gate_z + 4.5)],
			["barrel", Vector2(-4.6, gate_z + 4.0)], ["logs", Vector2(6, 13)], ["crate", Vector2(-6.5, 13.5)], ["barrel", Vector2(-1.5, 16)]]:
		var cp: Vector2 = c[1]
		var p3 := Vector3(cp.x, w.height_at(cp.x, cp.y), cp.y)
		match c[0]:
			"crate": w.solid(Props.crate(w.props_root, p3, rng.randf_range(0.85, 1.15)))
			"barrel": w.solid(Props.barrel(w.props_root, p3))
			"logs": w.solid(Props.log_pile(w.props_root, p3))

	# --- lantern posts along the paths
	for lp in [Vector2(-2.6, -9), Vector2(2.6, -15), Vector2(-6.5, -4.5), Vector2(7, -4.5), Vector2(9, 3.5), Vector2(-9.5, 2.5), Vector2(-2.6, gate_z + 7)]:
		var post := Props.footprint(Models.N(null, "lpost"), 0.15)
		Models.seg(post, Vector3.ZERO, Vector3(0, 2.7, 0), 0.08, 0.06, Props.wood_dark(), 6)
		Models.seg(post, Vector3(0, 2.6, 0), Vector3(0.55, 2.62, 0), 0.04, 0.035, Props.wood_dark(), 5)
		w._place(post, Vector3(lp.x, 0, lp.y))
		post.rotation.y = rng.randf() * TAU
		w.solid(post)
		var tip := post.global_transform * Vector3(0.5, 2.6, 0) if post.is_inside_tree() else post.position + Basis(Vector3.UP, post.rotation.y) * Vector3(0.5, 2.6, 0)
		_lantern(w, tip, lp.y < -8.0 or absf(lp.x) > 8.0)

	# --- great oaks inside the camp, lanterns hung from their branches
	var oaks := [[], [], []]
	var k := 0
	for op in [Vector2(-7.5, -18.5), Vector2(8.5, -19), Vector2(-18.5, -3), Vector2(19.5, -4), Vector2(-9, 15.5), Vector2(10, 14.5)]:
		if _near_shop(op, 4.5):
			continue
		oaks[k % 3].append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * rng.randf_range(1.15, 1.35)), Vector3(op.x, w.height_at(op.x, op.y), op.y)))
		w.add_circle(Vector3(op.x, 0, op.y), 0.8)
		var la := rng.randf() * TAU
		_lantern(w, Vector3(op.x + cos(la) * 1.8, w.height_at(op.x, op.y) + 3.4, op.y + sin(la) * 1.8), k % 2 == 0)
		k += 1
	for i in 3:
		if not oaks[i].is_empty():
			Props.multimesh(w.props_root, Flora.oak_model(i + 1), oaks[i])

	# --- the old forest outside the wall: oaks, dark pines, dead trees, boulders
	var outer := [[], [], []]
	var pines := [[], [], []]
	var dead := []
	var pine_meshes := [Flora.pine(1), Flora.pine(2), Flora.pine(3)]
	var has_dead := ResourceLoader.exists("res://assets/models/trees/deadtree.glb")
	for i in 420:
		var x := rng.randf_range(w.bounds.position.x - World.MARGIN + 4, w.bounds.end.x + World.MARGIN - 4)
		var z := rng.randf_range(w.bounds.position.y - World.MARGIN + 4, w.bounds.end.y + World.MARGIN - 4)
		var d := Vector2(x, z).distance_to(CENTER)
		if d < RADIUS + 3.0:
			continue
		if absf(x) < 5.5 and z < gate_z and z > gate_z - 40:
			continue                     # the road out of the gate
		var xf := Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * rng.randf_range(0.9, 1.5)), Vector3(x, w.height_at(x, z) - 0.1, z))
		var r := rng.randf()
		if has_dead and r < 0.07:
			dead.append(xf)
		elif r < 0.55:
			outer[i % 3].append(xf)
		else:
			pines[i % 3].append(xf)
	for i in 3:
		Props.multimesh(w.props_root, Flora.oak_model(i + 1), outer[i])
		Props.multimesh(w.props_root, pine_meshes[i], pines[i])
	if has_dead and not dead.is_empty():
		Props.multimesh(w.props_root, mesh("res://assets/models/trees/deadtree.glb"), dead)
	for i in 60:
		var x := rng.randf_range(w.bounds.position.x - 20, w.bounds.end.x + 20)
		var z := rng.randf_range(w.bounds.position.y - 20, w.bounds.end.y + 10)
		if Vector2(x, z).distance_to(CENTER) < RADIUS + 2.0:
			continue
		w._rock(Vector3(x, 0, z), rng.randf_range(0.8, 2.4), false)
	for i in 22:
		var p := Vector3(rng.randf_range(-24, 24), 0, rng.randf_range(-26, 22))
		if Vector2(p.x, p.z).distance_to(CENTER) > RADIUS - 3.0 or w.dirt_at(p.x, p.z) > 0.3 or w.is_near_obstacle(p, 2.0):
			continue
		w._rock(p, rng.randf_range(0.25, 0.6), false)

	w._rasterize()
	w._flush_stones(Props.stone())
	w._build_terrain(FOREST_FLOOR)
	w._scatter_grass(24000, FOREST_GRASS, 0.26)
	w._scatter_ferns(380)
	w.spawns["start"] = Vector3(0, 0, 5)
	w.spawns["from_wild"] = Vector3(0, 0, gate_z + 4.5)
	w.spawns["waypoint"] = Vector3(-8, 0, 9)
	w.spawns["portal"] = Vector3(4, 0, 8)
	w.spawns["alch"] = Vector3(-11.5, 0, -9)
	w.spawns["forge"] = Vector3(11.5, 0, -9)

const FOREST_FLOOR := {
	"col_a": Color(0.11, 0.14, 0.07), "col_b": Color(0.17, 0.15, 0.09), "col_accent": Color(0.22, 0.24, 0.11),
	"col_path": Color(0.22, 0.18, 0.13), "col_cliff": Color(0.28, 0.28, 0.26), "wet": 0.45,
}
const FOREST_GRASS := {"base_col": Color(0.08, 0.12, 0.05), "tip_col": Color(0.2, 0.26, 0.1), "dry_col": Color(0.3, 0.28, 0.15), "wind": 0.7}

static func _near_shop(p: Vector2, r: float) -> bool:
	for s in SHOPS:
		if p.distance_to(s["at"]) < r:
			return true
	return p.distance_to(Vector2(-8, 6)) < r * 0.7 or p.distance_to(Vector2(0, CENTER.y - RADIUS)) < r

## A point given in a stall's own frame (x right, z toward the camp's centre), in world space.
static func _local(w: World, at: Vector2, off: Vector3) -> Vector3:
	var yaw := face(at, CENTER)
	var b := Basis(Vector3.UP, yaw)
	var p := Vector3(at.x, w.height_at(at.x, at.y), at.y) + b * off
	return p

static func _glow(w: World, at: Vector2, off: Vector3, col: Color, energy: float, rng_m: float) -> void:
	var l := OmniLight3D.new()
	l.light_color = col
	l.light_energy = energy
	l.omni_range = rng_m
	w.props_root.add_child(l)
	l.position = _local(w, at, off)

## A hanging iron lantern (Meshy) with a candle's light; `lit` gives it a real light (they're costly).
static func _lantern(w: World, pos: Vector3, lit: bool) -> void:
	var ln := model("lantern")
	w.props_root.add_child(ln)
	ln.position = pos - Vector3(0, 0.55, 0)
	for n in ln.find_children("*", "MeshInstance3D", true, false):
		var mi: MeshInstance3D = n
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var core := MeshInstance3D.new()
	core.mesh = Geo.sph(0.06, 8)
	core.material_override = Mats.glow_unique(Color(1.0, 0.75, 0.4), 4.0)
	ln.add_child(core)
	core.position = Vector3(0, 0.24, 0)
	if lit:
		var l := OmniLight3D.new()
		l.light_color = Color(1.0, 0.7, 0.4)
		l.light_energy = 1.4
		l.omni_range = 6.5
		l.omni_attenuation = 1.4
		ln.add_child(l)
		l.position = Vector3(0, 0.25, 0)

## Something in a shopkeeper's hand (the smith's hammer, the alchemist's potion, the armourer's axe),
## carried by the hand bone so it follows the animation. spec: {"bone", "item" (a Data.BASES weapon) or
## "potion": Color, "rot": degrees, "pos": metres in the hand's frame}.
static func hold(m: Node3D, spec: Dictionary) -> void:
	var sk: Skeleton3D = m.find_child("Skeleton3D", true, false)
	if sk == null or sk.find_bone(spec["bone"]) < 0:
		return
	var ba := BoneAttachment3D.new()
	ba.bone_name = spec["bone"]
	sk.add_child(ba)
	var it: Node3D
	if spec.has("potion"):
		it = Models.N(null, "potion")
		var glass := Mats.mat(Color(0.75, 0.85, 0.8), 0.05, 0.2)
		Models.P(it, Geo.sph(0.055, 10), glass, Vector3(0, 0.05, 0))
		Models.P(it, Geo.cyl(0.018, 0.022, 0.07, 8), glass, Vector3(0, 0.12, 0))
		Models.P(it, Geo.sph(0.045, 10), Mats.glow_unique(spec["potion"], 2.2), Vector3(0, 0.045, 0))
	else:
		it = Models.item_model({"base": spec["item"], "rarity": 0})
	ba.add_child(it)
	# Meshy's armature works in centimetres (its node is scaled 0.01): undo that for the held thing
	var k := 1.0 / maxf((sk.get_parent() as Node3D).scale.x if sk.get_parent() is Node3D else 1.0, 0.0001)
	it.scale = Vector3.ONE * k
	it.rotation_degrees = spec.get("rot", Vector3.ZERO)
	it.position = (spec.get("pos", Vector3.ZERO) as Vector3) * k

## A shopkeeper: the rigged Meshy model in an Inter, playing its clips (Inter._animate).
static func _keeper(w: World, file: String, label: String, role: String, p: Vector2, yaw: float, clips: Dictionary) -> Inter:
	var it := w._inter("vendor", label, Vector3(p.x, 0, p.y), 1.5, null, {"role": role})
	var m: Node3D = (load(NPC_DIR + file + ".glb") as PackedScene).instantiate()
	m.name = "Keeper"
	it.set_meta("npc_file", NPC_DIR + file + ".glb")    # the trade window's portrait builds its own copy
	it.add_child(m)
	m.rotation.y = yaw
	it.model = m
	it.home_yaw = yaw
	var ap: AnimationPlayer = m.find_child("AnimationPlayer", true, false)
	if ap:
		for an in ap.get_animation_list():
			ap.get_animation(an).loop_mode = Animation.LOOP_LINEAR
			_pin_root(ap.get_animation(an))
		it.anim = ap
		it.clips = clips
		ap.play(clips.get("idle", ""))
		ap.seek(randf() * 2.0, true)
	w.add_circle(Vector3(p.x, 0, p.y), 0.45)
	return it

## Meshy's library clips walk the hips about (Catching_Breath strides 4.6 m and snaps back): pin them
## over the keeper's spot, keeping only the up and down.
static func _pin_root(a: Animation) -> void:
	for t in a.get_track_count():
		if a.track_get_type(t) != Animation.TYPE_POSITION_3D or not str(a.track_get_path(t)).ends_with(":Hips"):
			continue
		if a.track_get_key_count(t) == 0:
			continue
		var p0: Vector3 = a.track_get_key_value(t, 0)
		for k in a.track_get_key_count(t):
			var v: Vector3 = a.track_get_key_value(t, k)
			a.track_set_key_value(t, k, Vector3(p0.x, v.y, p0.z))

## Rune stones: their carved runes glow cyan, and the glow breathes.
static func _rune_material() -> ShaderMaterial:
	var sh := Shader.new()
	sh.code = RUNE_SHADER
	var m := ShaderMaterial.new()
	m.shader = sh
	var src: Mesh = mesh(DIR + "runestone.glb")
	var sm: Material = src.surface_get_material(0)
	if sm is BaseMaterial3D:
		m.set_shader_parameter("albedo_tex", (sm as BaseMaterial3D).albedo_texture)
	return m

const RUNE_SHADER := """
shader_type spatial;
uniform sampler2D albedo_tex : source_color, filter_linear_mipmap;
void fragment() {
	vec3 c = texture(albedo_tex, UV).rgb;
	ALBEDO = c;
	ROUGHNESS = 0.9;
	// the runes are the cyan-green strokes: bright, and greener/bluer than red
	float rune = smoothstep(0.08, 0.25, (c.g + c.b) * 0.5 - c.r) * smoothstep(0.18, 0.35, c.g);
	float pulse = 0.75 + 0.25 * sin(TIME * 1.3 + NODE_POSITION_WORLD.x * 0.7);
	EMISSION = vec3(0.25, 1.0, 0.85) * rune * 2.6 * pulse;
}
"""
