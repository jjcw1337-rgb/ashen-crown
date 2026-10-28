class_name Goblin
extends RefCounted
## King Grubb the Gilded and his Gold Grabbers: sculpted goblin bodies on the humanoid joint
## layout (so Anim drives them), with their own secondary motion on top (after_pose): flopping
## ears, a chattering jaw, a wobbling stack of stolen crowns, a swinging medallion, a jiggling
## belly and bouncing gold sacks, plus the king's coin-biting idle and the grabbers' scurry
## and loot-carrying poses.
##
## Shapes are built from two helpers: blob (a sphere pushed in and out by a function) and tube
## (a smooth swept tube, optionally flattened, for limbs, ears, noses, fingers and straps).
## Each joint's parts are baked into one mesh per kind, like SkeletonModel.

const KINDS := {
	"king": {"scale": 1.5, "girth": 1.0, "belly": 1.0, "head": 1.0, "ear": 1.0, "nose": 1.0, "hand": 1.35, "arm": 1.3,
		"skin": Color(0.25, 0.29, 0.15), "skin2": Color(0.09, 0.11, 0.05), "skin3": Color(0.42, 0.37, 0.22),
		"eyes": Color(1.0, 0.72, 0.08), "cloth": Color(0.3, 0.07, 0.3), "cloth2": Color(0.1, 0.02, 0.09),
		"crowns": 3, "sacks": 3, "weapon": "key", "mantle": true},
	"grabber": {"scale": 0.74, "girth": 0.45, "belly": 0.1, "head": 1.15, "ear": 1.15, "nose": 1.15, "hand": 1.1, "arm": 0.8,
		"skin": Color(0.28, 0.31, 0.16), "skin2": Color(0.1, 0.12, 0.05), "skin3": Color(0.4, 0.36, 0.22),
		"eyes": Color(1.0, 0.6, 0.1), "cloth": Color(0.33, 0.24, 0.15), "cloth2": Color(0.17, 0.12, 0.07),
		"crowns": 0, "sacks": 1, "weapon": "knife", "hood": true},
}
## King Grubb the mutant: a model generated with Meshy from a Meshy concept image, rigged in
## Blender (tools/blender/grubb_mutant.py) on this joint layout. Positions are the joints in the
## model's own space (Godot axes, 2.2 m tall before "scale"); each joint's parent is listed so the
## skeleton matches the Blender rig.
const MUTANT := {"scale": 1.59, "glb": "res://assets/models/grubb_mutant.glb", "eyes": Color(1.0, 0.8, 0.3), "layout": {
	"hips": ["", Vector3(0, 0.62, 0)], "torso": ["hips", Vector3(0, 0.8, 0)], "belly": ["torso", Vector3(0, 0.8, -0.3)],
	"head": ["torso", Vector3(-0.08, 1.48, -0.16)], "crowns": ["head", Vector3(-0.13, 1.84, -0.23)],
	"sh_r": ["torso", Vector3(0.4, 1.42, -0.08)], "el_r": ["sh_r", Vector3(0.58, 0.98, -0.12)], "hand_r": ["el_r", Vector3(0.69, 0.62, -0.17)],
	"sh_l": ["torso", Vector3(-0.4, 1.42, -0.08)], "el_l": ["sh_l", Vector3(-0.58, 0.98, -0.12)], "hand_l": ["el_l", Vector3(-0.69, 0.62, -0.17)],
	"leg_r": ["hips", Vector3(0.22, 0.6, -0.12)], "knee_r": ["leg_r", Vector3(0.3, 0.32, -0.15)],
	"leg_l": ["hips", Vector3(-0.22, 0.6, -0.12)], "knee_l": ["leg_l", Vector3(-0.3, 0.32, -0.15)],
	"sack0": ["torso", Vector3(0.32, 1.45, 0.3)], "sack1": ["torso", Vector3(0.18, 1.66, 0.32)], "sack2": ["torso", Vector3(0.42, 1.66, 0.28)],
}}
const GOLD := Color(1.0, 0.74, 0.28)
const HIPS_Y := 0.62

static var _baked := {}
static var _meshes := {}
static var _mats := {}
static var _skin_shader: Shader
static var _coin_shader: Shader

# ---------------------------------------------------------------- materials
## rest_uv: the mesh is skinned and carries its rest position in UV/UV2 (Sculpt), so the
## detail is textured there instead of in the (moving) vertex space.
static func skin_mat(c: Color, c2: Color, c3: Color, warts := 1.0, rest_uv := false) -> ShaderMaterial:
	var key := "skin%s%s%s%.1f%s" % [c.to_html(), c2.to_html(), c3.to_html(), warts, rest_uv]
	if _mats.has(key):
		return _mats[key]
	if _skin_shader == null:
		_skin_shader = Shader.new()
		_skin_shader.code = SKIN_SHADER
	var m := ShaderMaterial.new()
	m.shader = _skin_shader
	m.set_shader_parameter("col", c)
	m.set_shader_parameter("col2", c2)
	m.set_shader_parameter("col3", c3)
	m.set_shader_parameter("warts", warts)
	m.set_shader_parameter("rest_uv", rest_uv)
	_mats[key] = m
	return m

## Heaped coins: a twinkling field of tilted gold discs (mounds, piles, the inside of sacks).
static func coin_mat(col := GOLD, glint := 1.0) -> ShaderMaterial:
	var key := "coin%s%.2f" % [col.to_html(), glint]
	if _mats.has(key):
		return _mats[key]
	if _coin_shader == null:
		_coin_shader = Shader.new()
		_coin_shader.code = COIN_SHADER
	var m := ShaderMaterial.new()
	m.shader = _coin_shader
	m.set_shader_parameter("col", col)
	m.set_shader_parameter("glint", glint)
	_mats[key] = m
	return m

static func gold_m(col := GOLD) -> Material:
	return SkeletonModel.dm(SkeletonModel.GOLD, col, col.darkened(0.6), {})

static func leather_m(col: Color) -> Material:
	return SkeletonModel.dm(SkeletonModel.LEATHER, col, col.darkened(0.45), {})

static func cloth_m(col: Color, col2: Color) -> Material:
	return SkeletonModel.dm(SkeletonModel.CLOTH, col, col2, {})

static func _dark() -> Material:
	return Mats.mat(Color(0.02, 0.012, 0.01), 1.0)

static func _claw() -> Material:
	return SkeletonModel.dm(SkeletonModel.BONE, Color(0.2, 0.17, 0.12), Color(0.06, 0.05, 0.03), {})

static func _tooth() -> Material:
	return SkeletonModel.dm(SkeletonModel.BONE, Color(0.78, 0.7, 0.48), Color(0.4, 0.3, 0.15), {})

# ---------------------------------------------------------------- mesh helpers
## A sphere of radii rad, pushed in or out along each direction by fn(dir) -> scale.
static func blob(key: String, rad: Vector3, fn: Callable, rings := 18, segs := 26) -> Mesh:
	if _meshes.has(key):
		return _meshes[key]
	var pts := []
	for r in rings + 1:
		var th := PI * r / rings
		var row := []
		for s in segs:
			var ph := TAU * s / segs
			var d := Vector3(sin(th) * cos(ph), cos(th), sin(th) * sin(ph))
			var k: float = fn.call(d)
			row.append(Vector3(d.x * rad.x, d.y * rad.y, d.z * rad.z) * k)
		pts.append(row)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for r in rings:
		for s in segs:
			var s2 := (s + 1) % segs
			var a: Vector3 = pts[r][s]
			var b: Vector3 = pts[r][s2]
			var c: Vector3 = pts[r + 1][s]
			var d2: Vector3 = pts[r + 1][s2]
			_tri(st, a, b, d2, (a + b + d2) / 3.0)
			_tri(st, a, d2, c, (a + d2 + c) / 3.0)
	st.generate_normals()
	var m := st.commit()
	_meshes[key] = m
	return m

## Adds a triangle facing away from `out` (a point inside the shape, here the origin-relative
## centroid direction).
static func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, out: Vector3) -> void:
	if (b - a).cross(c - a).length_squared() < 1e-14:
		return
	if (b - a).cross(c - a).dot(out) > 0.0:
		var t := b
		b = c
		c = t
	st.add_vertex(a)
	st.add_vertex(b)
	st.add_vertex(c)

static func _cr(p0: Vector3, p1: Vector3, p2: Vector3, p3: Vector3, t: float) -> Vector3:
	var t2 := t * t
	var t3 := t2 * t
	return 0.5 * ((2.0 * p1) + (-p0 + p2) * t + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t2 + (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * t3)

## A smooth tube through pts (Catmull-Rom) with a radius per point. flat < 1 squashes the
## cross-section along the axis closest to `thin` (for ears, straps, claws).
static func tube(key: String, pts: Array, radii: Array, sides := 10, flat := 1.0, thin := Vector3.FORWARD) -> Mesh:
	if _meshes.has(key):
		return _meshes[key]
	var P: Array = []
	var R: Array = []
	var n := pts.size()
	for i in n - 1:
		for s in 4:
			var t := s / 4.0
			P.append(_cr(pts[maxi(i - 1, 0)], pts[i], pts[i + 1], pts[mini(i + 2, n - 1)], t))
			R.append(lerpf(radii[i], radii[i + 1], t))
	P.append(pts[n - 1])
	R.append(radii[n - 1])
	var m := P.size()
	var rings := []
	for i in m:
		var tan: Vector3 = (P[mini(i + 1, m - 1)] - P[maxi(i - 1, 0)]).normalized()
		var side := tan.cross(thin)
		if side.length() < 0.01:
			side = tan.cross(Vector3.RIGHT if absf(tan.x) < 0.9 else Vector3.UP)
		side = side.normalized()
		var up := side.cross(tan).normalized()
		var ring := []
		for s in sides:
			var a := TAU * s / sides
			ring.append(P[i] + side * cos(a) * R[i] + up * sin(a) * R[i] * flat)
		rings.append(ring)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in m - 1:
		var mid: Vector3 = (P[i] + P[i + 1]) * 0.5
		for s in sides:
			var s2 := (s + 1) % sides
			var a: Vector3 = rings[i][s]
			var b: Vector3 = rings[i][s2]
			var c: Vector3 = rings[i + 1][s]
			var d: Vector3 = rings[i + 1][s2]
			_tri(st, a, b, d, (a + b + d) / 3.0 - mid)
			_tri(st, a, d, c, (a + d + c) / 3.0 - mid)
	# caps
	for e in [0, m - 1]:
		var ctr: Vector3 = P[e]
		var dir: Vector3 = (P[e] - P[1]) if e == 0 else (P[e] - P[m - 2])
		for s in sides:
			var s2 := (s + 1) % sides
			_tri(st, ctr, rings[e][s], rings[e][s2], dir)
	st.generate_normals()
	var mesh := st.commit()
	_meshes[key] = mesh
	return mesh

## Smooth bump in [0, 1] where d points near c (w: width as 1 - cos of the radius).
static func bump(d: Vector3, c: Vector3, w: float) -> float:
	var k := (d.dot(c.normalized()) - (1.0 - w)) / w
	return 0.0 if k <= 0.0 else k * k * (3.0 - 2.0 * k)

static func _P(n: Node3D, mesh: Mesh, m: Material, pos := Vector3.ZERO, rot := Vector3.ZERO, scl := Vector3.ONE) -> MeshInstance3D:
	return Models.P(n, mesh, m, pos, rot, scl)

# ---------------------------------------------------------------- rig
static func build(kind: String) -> Node3D:
	if kind == "mutant":
		var mr := _build_mutant()
		if mr != null:
			return mr
		kind = "king"
	if not KINDS.has(kind):
		kind = "grabber"
	var k: Dictionary = KINDS[kind]
	var gw: float = lerpf(0.72, 1.0, k["girth"])
	var root := Node3D.new()
	root.name = "Rig"
	root.set_script(load("res://scripts/knight_rig.gd"))
	var J := {}
	var hips := Models.N(root, "hips", Vector3(0, HIPS_Y, 0))
	J["hips"] = hips
	J["hips_y"] = HIPS_Y
	var torso := Models.N(hips, "torso", Vector3(0, 0.05, 0))
	J["torso"] = torso
	var head := Models.N(torso, "head", Vector3(0, 0.56, -0.2))
	head.scale = Vector3.ONE * float(k["head"])
	J["head"] = head
	J["jaw"] = Models.N(head, "jaw", Vector3(0, 0.02, -0.05))
	J["belly"] = Models.N(torso, "belly", Vector3(0, 0.16, -0.05))
	for side in [1, -1]:
		var sn := "r" if side == 1 else "l"
		var sh := Models.N(torso, "sh_" + sn, Vector3(side * 0.29 * gw, 0.48, 0.04))
		var el := Models.N(sh, "el_" + sn, Vector3(0, -0.36, 0))
		var hand := Models.N(el, "hand_" + sn, Vector3(0, -0.33, 0))
		J["sh_" + sn] = sh
		J["el_" + sn] = el
		J["hand_" + sn] = hand
		var leg := Models.N(hips, "leg_" + sn, Vector3(side * 0.15 * gw, -0.03, 0))
		var knee := Models.N(leg, "knee_" + sn, Vector3(side * 0.05, -0.27, -0.02))
		J["leg_" + sn] = leg
		J["knee_" + sn] = knee
		J["ear_" + sn] = Models.N(head, "ear_" + sn, Vector3(side * 0.15, 0.14, 0.01))
	J["grip_r"] = Models.N(J["hand_r"], "grip_r", Vector3(0, -0.08, -0.01), Vector3(-28, 0, 0))
	J["grip_l"] = Models.N(J["hand_l"], "grip_l", Vector3(0, -0.08, -0.01))
	J["mount_l"] = Models.N(J["el_l"], "mount_l", Vector3(-0.06, -0.14, 0), Vector3(0, 70, 0))
	# the Blender model brings everything (body, face, gear, crowns, sacks, the key); the code
	# build adds its accessories to the joints
	var made := blender(kind)
	var parts := ["hips", "torso", "head", "jaw", "ear_r", "ear_l", "sh_r", "el_r", "el_l", "hand_r", "hand_l", "leg_r", "leg_l", "knee_r", "knee_l"]
	if int(k["crowns"]) > 0:
		J["crowns"] = Models.N(head, "crowns", Vector3(0, 0.26, 0.02))
		parts.append("crowns")
	if k.get("mantle", false):
		J["medal"] = Models.N(torso, "medal", Vector3(0, 0.55, -0.13))
		parts.append("medal")
	var sacks := []
	var sack_at := [Vector3(0, 0.36, 0.32), Vector3(-0.2, 0.72, 0.24), Vector3(0.22, 0.7, 0.26)]
	for i in int(k["sacks"]):
		var sk := Models.N(torso, "sack%d" % i, sack_at[i] * Vector3(gw, 1.0, gw))
		J["sack%d" % i] = sk
		sacks.append(sk)
		parts.append("sack%d" % i)
	J["sacks"] = sacks
	_skin_body(root, J, kind)
	if made:
		parts.clear()
	for part in parts:
		var mi := MeshInstance3D.new()
		mi.mesh = _part_mesh(kind, part)
		(J[part] as Node3D).add_child(mi)
	# the cape and loincloth move in the wind (cloak shader), so they stay separate meshes
	var cv := {"cloak": k["cloth"], "cloak2": k["cloth2"]}
	if k.get("mantle", false) and not made:
		_P(torso, SkeletonModel.cloak_mesh(0.95, 0.5, 0.34, 5.0, 7, 0.55), SkeletonModel.cloak_mat(cv, 0.35), Vector3(0, 0.6, 0.1), Vector3(-14, 180, 0))
	if not made:
		_P(hips, SkeletonModel.cloak_mesh(0.3 * gw, 0.36, 0.4, 2.0, 41, 0.2), SkeletonModel.cloak_mat(cv, 0.5, 0.1), Vector3(0, 0.0, -0.21 * gw - 0.02), Vector3(6, 0, 0))
		_P(hips, SkeletonModel.cloak_mesh(0.34 * gw, 0.3, 0.4, 2.0, 42, 0.2), SkeletonModel.cloak_mat(cv, 0.5, 0.1), Vector3(0, 0.02, 0.2 * gw), Vector3(-8, 180, 0))
	# weapon
	if made:
		J["weapon"] = Models.N(J["grip_r"], "weapon")
	elif k["weapon"] == "key":
		var w := hoardkey()
		w.scale = Vector3.ONE * 1.3
		(J["grip_r"] as Node3D).add_child(w)
		J["weapon"] = w
	else:
		var kn := Models.enemy_weapon("scimitar")
		kn.scale = Vector3.ONE * 0.6
		(J["grip_r"] as Node3D).add_child(kn)
		J["weapon"] = kn
	# the coin he bites (king) and the loot sack a grabber hauls over its head
	var coin := _P(J["hand_l"], Geo.cyl(0.045, 0.045, 0.012, 16), gold_m(), Vector3(0.0, -0.13, -0.05), Vector3(80, 0, 20))
	coin.visible = false
	J["coin"] = coin
	if kind == "grabber":
		var loot := Models.N(torso, "loot", Vector3(0, 0.98, -0.12))
		_P(loot, blob("loot_sack", Vector3(0.2, 0.17, 0.17), func(d: Vector3) -> float: return 1.0 + 0.06 * sin(d.x * 9.0) * sin(d.z * 7.0) - 0.25 * bump(d, Vector3.UP, 0.4)), cloth_m(Color(0.5, 0.38, 0.22), Color(0.28, 0.19, 0.1)))
		_P(loot, blob("loot_coins", Vector3(0.12, 0.06, 0.1), func(_d: Vector3) -> float: return 1.0), coin_mat(GOLD, 2.0), Vector3(0, 0.14, 0))
		var gl := OmniLight3D.new()
		gl.light_color = GOLD
		gl.light_energy = 1.4
		gl.omni_range = 2.4
		gl.position = Vector3(0, 0.3, 0)
		loot.add_child(gl)
		loot.visible = false
		J["loot"] = loot
	# eye glow
	var l := OmniLight3D.new()
	l.light_color = k["eyes"]
	l.light_energy = 0.5 if kind == "grabber" else 0.9
	l.omni_range = 1.4 if kind == "grabber" else 2.2
	l.position = Vector3(0, 0.11, -0.3)
	head.add_child(l)
	root.scale = Vector3.ONE * float(k["scale"])
	root.set_meta("j", J)
	root.set_meta("h", 0.7)
	root.set_meta("goblin", kind)
	root.set_meta("pers", "boss" if kind == "king" else "goblin")
	return root

## The mutant king from MUTANT's layout and glb; null if the model isn't in the project.
static func _build_mutant() -> Node3D:
	if not ResourceLoader.exists(MUTANT["glb"]):
		return null
	var root := imported_rig(MUTANT["layout"], MUTANT["glb"], "mutant")
	var J: Dictionary = root.get_meta("j")
	J["grip_r"] = Models.N(J["hand_r"], "grip_r", Vector3(0, -0.1, -0.02), Vector3(-28, 0, 0))
	J["grip_l"] = Models.N(J["hand_l"], "grip_l", Vector3(0, -0.1, -0.02))
	J["mount_l"] = Models.N(J["el_l"], "mount_l", Vector3(-0.06, -0.14, 0), Vector3(0, 70, 0))
	J["weapon"] = Models.N(J["grip_r"], "weapon")
	J["sacks"] = [J["sack0"], J["sack1"], J["sack2"]]
	var coin := _P(J["hand_l"], Geo.cyl(0.06, 0.06, 0.015, 16), gold_m(), Vector3(0.0, -0.16, -0.06), Vector3(80, 0, 20))
	coin.visible = false
	J["coin"] = coin
	var l := OmniLight3D.new()
	l.light_color = MUTANT["eyes"]
	l.light_energy = 0.7
	l.omni_range = 1.6
	l.position = Vector3(0, 0.12, -0.3)
	(J["head"] as Node3D).add_child(l)
	root.scale = Vector3.ONE * float(MUTANT["scale"])
	root.set_meta("h", 0.7)
	root.set_meta("goblin", "king")
	root.set_meta("pers", "boss")
	# the key is part of his mesh, held low and forward: no raised "ready" carry
	root.set_meta("held", true)
	return root

## A rig for an imported, skinned model (a .glb rigged in Blender with bones named like our joints):
## joint nodes from a layout {joint: [parent, model-space position (Godot axes)]}, a Skeleton3D that
## mirrors them (knight_rig.gd copies the joints onto the bones each frame) and the glb's mesh re-bound
## to it by bone name. aim {joint: other joint}: the joint's rest turns its -Y toward the other (an
## A-pose arm), so Anim's zero pose hangs that limb straight down; "=joint" copies that joint's rest
## orientation (a hand lined up with its forearm). key caches the mesh and skin.
static func imported_rig(layout: Dictionary, glb: String, key: String, aim := {}) -> Node3D:
	var root := Node3D.new()
	root.name = "Rig"
	root.set_script(load("res://scripts/knight_rig.gd"))
	var J := {}
	var G := {}
	for n in layout.keys():
		var at: Vector3 = layout[n][1]
		var b := Basis()
		if aim.has(n) and String(aim[n]).begins_with("="):
			b = (G[String(aim[n]).substr(1)] as Transform3D).basis
		elif aim.has(n):
			var y := -((layout[aim[n]][1] as Vector3) - at).normalized()
			var x := (Vector3.RIGHT - y * Vector3.RIGHT.dot(y)).normalized()
			b = Basis(x, y, x.cross(y))
		G[n] = Transform3D(b, at)
	for n in layout.keys():
		var par: String = layout[n][0]
		var nd := Node3D.new()
		nd.name = n
		nd.transform = G[n] if par == "" else (G[par] as Transform3D).affine_inverse() * (G[n] as Transform3D)
		(J[par] if par != "" else root).add_child(nd)
		J[n] = nd
	J["hips_y"] = (layout["hips"][1] as Vector3).y
	var skel := Skeleton3D.new()
	skel.name = "Skeleton"
	root.add_child(skel)
	var bones: Array = layout.keys()
	var bi := {}
	for i in bones.size():
		skel.add_bone(bones[i])
		bi[bones[i]] = i
	var proxies := {}
	for i in bones.size():
		var n: Node3D = J[bones[i]]
		var par := n.get_parent()
		if par != root:
			skel.set_bone_parent(i, bi[String(par.name)])
		skel.set_bone_rest(i, n.transform)
		skel.set_bone_pose_position(i, n.position)
		skel.set_bone_pose_rotation(i, n.quaternion)
		proxies[i] = n
	if not _bodies.has(key):
		_bodies[key] = _imported(glb, bi)
		_skins[key] = skel.create_skin_from_rest_transforms()
	var mi := MeshInstance3D.new()
	mi.name = "Body"
	mi.mesh = _bodies[key]
	skel.add_child(mi)
	mi.skeleton = NodePath("..")
	mi.skin = _skins[key]
	root.set("skel", skel)
	root.set("proxy_of", proxies)
	root.set_meta("j", J)
	return root

## The bones of the sculpted skin, parents first; each mirrors the joint of the same name.
const BONES := ["hips", "torso", "belly", "head", "jaw", "ear_r", "ear_l", "sh_r", "el_r", "hand_r", "sh_l", "el_l", "hand_l", "leg_r", "knee_r", "leg_l", "knee_l",
	"crowns", "sack0", "sack1", "sack2"]
static var _bodies := {}
static var _skins := {}

## One continuous, skinned body on a Skeleton3D that mirrors the joints (knight_rig.gd copies
## the joints onto the bones every frame, like the hero's rig).
static func _skin_body(root: Node3D, J: Dictionary, kind: String) -> void:
	var skel := Skeleton3D.new()
	skel.name = "Skeleton"
	root.add_child(skel)
	var bones: Array = BONES.filter(func(b): return J.has(b))
	var bi := {}
	for i in bones.size():
		skel.add_bone(bones[i])
		bi[bones[i]] = i
	var proxies := {}
	for i in bones.size():
		var n: Node3D = J[bones[i]]
		var par := n.get_parent()
		if par != root:
			skel.set_bone_parent(i, bi[String(par.name)])
		skel.set_bone_rest(i, n.transform)
		skel.set_bone_pose_position(i, n.position)
		skel.set_bone_pose_rotation(i, n.quaternion)
		skel.set_bone_pose_scale(i, n.scale)
		proxies[i] = n
	var key := kind + ("|b" if blender(kind) else "|c")
	if not _bodies.has(key):
		var xf := {}
		for b in bones:
			var t: Transform3D = (J[b] as Node3D).transform
			var n: Node = (J[b] as Node3D).get_parent()
			while n != root:
				t = (n as Node3D).transform * t
				n = n.get_parent()
			xf[b] = t
		_bodies[key] = _imported(KINDS[kind]["glb"], bi) if blender(kind) else _sculpt(KINDS[kind], xf, bi)
		_skins[key] = skel.create_skin_from_rest_transforms()
	var mi := MeshInstance3D.new()
	mi.name = "Body"
	mi.mesh = _bodies[key]
	if not _bodies[key].has_meta("imported"):
		mi.material_override = skin_mat(KINDS[kind]["skin"], KINDS[kind]["skin2"], KINDS[kind]["skin3"], 1.0, true)
	skel.add_child(mi)
	mi.skeleton = NodePath("..")
	mi.skin = _skins[key]
	root.set("skel", skel)
	root.set("proxy_of", proxies)

## Off: build every goblin in code even where a Blender export exists (for comparisons).
static var use_blender := true

## True when this kind's body comes from a Blender export that exists in the project.
static func blender(kind: String) -> bool:
	if not use_blender:
		return false
	var glb: String = KINDS[kind].get("glb", "")
	return glb != "" and ResourceLoader.exists(glb)

## A body modelled in Blender (tools/blender/grubb.py): its skinned mesh, re-bound to our skeleton
## by bone name. The Blender rig sits on the same joints, so the rest pose matches ours.
static func _imported(path: String, bi: Dictionary) -> ArrayMesh:
	var scene: Node = (load(path) as PackedScene).instantiate()
	var out := ArrayMesh.new()
	for n in scene.find_children("*", "MeshInstance3D", true, false):
		var src: MeshInstance3D = n
		var skin: Skin = src.skin
		var skel := src.get_node_or_null(src.skeleton) as Skeleton3D
		var remap := {}
		if skin != null:
			for b in skin.get_bind_count():
				var nm := String(skin.get_bind_name(b))
				if nm == "" and skel != null:
					nm = skel.get_bone_name(skin.get_bind_bone(b))
				remap[b] = bi.get(nm, 0)
		for si in src.mesh.get_surface_count():
			var arr: Array = src.mesh.surface_get_arrays(si)
			if arr.is_empty() or arr[Mesh.ARRAY_VERTEX] == null:
				continue
			if arr[Mesh.ARRAY_BONES] != null:
				var bones: PackedInt32Array = arr[Mesh.ARRAY_BONES]
				for i in bones.size():
					bones[i] = remap.get(bones[i], 0)
				arr[Mesh.ARRAY_BONES] = bones
			out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
			var mat: Material = src.mesh.surface_get_material(si)
			if mat is StandardMaterial3D:
				# a touch of rim light so his silhouette reads against the dark
				mat = mat.duplicate()
				(mat as StandardMaterial3D).rim_enabled = true
				(mat as StandardMaterial3D).rim = 0.35
				(mat as StandardMaterial3D).rim_tint = 0.6
			out.surface_set_material(out.get_surface_count() - 1, mat)
	scene.free()
	out.set_meta("imported", true)
	return out

## Sculpts the body: every shape is placed in its joint's space and melted into the rest.
static func _sculpt(k: Dictionary, xf: Dictionary, bi: Dictionary) -> ArrayMesh:
	var S := Sculpt.new()
	var g: float = k["girth"]
	var gw: float = lerpf(0.72, 1.0, g)
	var b: float = k["belly"]
	var aw: float = gw * float(k["arm"])
	var hs: float = k["hand"]
	var nose: float = k["nose"]
	var E := func(j: String, c: Vector3, r: Vector3, kk: float) -> void:
		var t: Transform3D = xf[j]
		S.ellipsoid(bi[j], t * c, r * t.basis.get_scale().x, kk)
	var C := func(j: String, pts: Array, radii: Array, kk: float) -> void:
		var t: Transform3D = xf[j]
		var sc := t.basis.get_scale().x
		var w := []
		var rr := []
		for i in pts.size():
			w.append(t * (pts[i] as Vector3))
			rr.append(float(radii[i]) * sc)
		S.chain(bi[j], w, rr, kk)
	var X := func(j: String, c: Vector3, r: Vector3, kk: float) -> void:
		var t: Transform3D = xf[j]
		S.carve(bi[j], t * c, r * t.basis.get_scale().x, kk)
	# pelvis, chest, the hunch, shoulder knots, a thick neck thrust forward, sagging pecs
	E.call("hips", Vector3(0, -0.02, 0.01), Vector3(0.25 * gw, 0.13, 0.2 * gw), 0.05)
	E.call("torso", Vector3(0, 0.38, 0.03), Vector3(0.27 * gw, 0.21, 0.2 * gw), 0.06)
	E.call("torso", Vector3(0, 0.47, 0.12 * gw), Vector3(0.2 * gw, 0.16, 0.15 * gw), 0.06)
	for s in [1.0, -1.0]:
		E.call("torso", Vector3(s * 0.19 * gw, 0.5, 0.05), Vector3(0.12, 0.08, 0.1) * gw, 0.05)
		E.call("torso", Vector3(s * 0.1 * gw, 0.33, -0.13 * gw), Vector3(0.1, 0.08, 0.06) * gw, 0.04)
	C.call("torso", [Vector3(0, 0.44, 0.02), Vector3(0, 0.52, -0.08), Vector3(0, 0.56, -0.19)], [0.11 * gw, 0.1 * gw, 0.085 * gw], 0.05)
	# the belly (its own bone, so it can jiggle) with a sag and a navel
	var rad := Vector3(0.17 + 0.11 * g + 0.05 * b, 0.19 + 0.06 * g + 0.03 * b, 0.12 + 0.07 * g + 0.12 * b)
	E.call("belly", Vector3(0, 0.0, -0.04 * b), rad, 0.07)
	E.call("belly", Vector3(0, -0.08, -0.06 - 0.06 * b), Vector3(rad.x * 0.8, rad.y * 0.6, rad.z * 0.8), 0.08)
	X.call("belly", Vector3(0, -0.03, -0.04 * b - rad.z * 1.02), Vector3(0.016, 0.02, 0.025), 0.01)
	# head: skull, heavy brow, cheeks, snout, the long hooked nose, sockets, lids, lips, ear roots
	E.call("head", Vector3(0, 0.13, 0.02), Vector3(0.165, 0.15, 0.18), 0.04)
	E.call("head", Vector3(0, 0.15, 0.1), Vector3(0.13, 0.12, 0.1), 0.05)
	E.call("head", Vector3(0, 0.04, -0.1), Vector3(0.13, 0.085, 0.12), 0.04)
	for s in [1.0, -1.0]:
		C.call("head", [Vector3(s * 0.12, 0.155, -0.14), Vector3(s * 0.065, 0.145, -0.18), Vector3(s * 0.015, 0.12, -0.195)], [0.026, 0.03, 0.016], 0.025)
		E.call("head", Vector3(s * 0.085, 0.065, -0.14), Vector3(0.05, 0.04, 0.045), 0.03)
		X.call("head", Vector3(s * 0.062, 0.108, -0.172), Vector3(0.034, 0.026, 0.03), 0.012)
		E.call("head", Vector3(s * 0.062, 0.13, -0.168), Vector3(0.032, 0.012, 0.026), 0.012)
		X.call("head", Vector3(s * 0.02, 0.004 * nose, -0.292 * nose), Vector3(0.009, 0.008, 0.01), 0.006)
		E.call("head", Vector3(s * 0.15, 0.14, 0.01), Vector3(0.04, 0.05, 0.035), 0.03)
	C.call("head", [Vector3(0, 0.12, -0.19), Vector3(0, 0.09, -0.245 * nose), Vector3(0, 0.045, -0.305 * nose), Vector3(0, 0.005, -0.315 * nose), Vector3(0, -0.02, -0.29 * nose)], [0.03, 0.037, 0.034, 0.024, 0.012], 0.03)
	E.call("head", Vector3(0.022, 0.075, -0.27 * nose), Vector3.ONE * 0.014, 0.008)
	E.call("head", Vector3(0.08, 0.25, 0.0), Vector3.ONE * 0.012, 0.008)
	E.call("head", Vector3(-0.05, 0.24, 0.08), Vector3.ONE * 0.014, 0.008)
	E.call("head", Vector3(0, -0.005, -0.17), Vector3(0.1, 0.025, 0.05), 0.02)
	X.call("head", Vector3(0, -0.035, -0.17), Vector3(0.085, 0.022, 0.07), 0.01)
	# the underbite jaw
	E.call("jaw", Vector3(0, -0.06, -0.07), Vector3(0.125, 0.055, 0.115), 0.03)
	E.call("jaw", Vector3(0, -0.065, -0.16), Vector3(0.065, 0.045, 0.045), 0.03)
	# arms: long and heavy; legs: short and bowed; big flat feet. Each limb is its own group
	# (so a hanging arm doesn't melt into the belly); the shoulder and hip balls are in both.
	for s in [1.0, -1.0]:
		var sn := "r" if s > 0.0 else "l"
		E.call("sh_" + sn, Vector3.ZERO, Vector3.ONE * 0.085 * aw, 0.05)
		E.call("leg_" + sn, Vector3.ZERO, Vector3.ONE * 0.1 * gw, 0.05)
		S.group = 1 if s > 0.0 else 2
		E.call("sh_" + sn, Vector3.ZERO, Vector3.ONE * 0.085 * aw, 0.05)
		C.call("sh_" + sn, [Vector3.ZERO, Vector3(0, -0.12, -0.015), Vector3(0, -0.25, 0.0), Vector3(0, -0.36, 0.0)], [0.08 * aw, 0.086 * aw, 0.066 * aw, 0.058 * aw], 0.04)
		E.call("el_" + sn, Vector3.ZERO, Vector3.ONE * 0.06 * aw, 0.035)
		C.call("el_" + sn, [Vector3.ZERO, Vector3(0, -0.14, -0.02), Vector3(0, -0.33, 0.0)], [0.058 * aw, 0.066 * aw, 0.045 * aw], 0.035)
		E.call("hand_" + sn, Vector3(0, -0.05, 0) * hs, Vector3(0.05, 0.06, 0.03) * hs, 0.025)
		E.call("hand_" + sn, Vector3(0, -0.095, -0.005) * hs, Vector3(0.045, 0.02, 0.022) * hs, 0.02)
		C.call("hand_" + sn, [Vector3(-s * 0.035, -0.035, -0.015) * hs, Vector3(-s * 0.055, -0.08, -0.045) * hs, Vector3(-s * 0.05, -0.11, -0.05) * hs], [0.018 * hs, 0.015 * hs, 0.011 * hs], 0.015)
		S.group = 3 if s > 0.0 else 4
		E.call("leg_" + sn, Vector3.ZERO, Vector3.ONE * 0.1 * gw, 0.05)
		C.call("leg_" + sn, [Vector3.ZERO, Vector3(s * 0.03, -0.14, -0.02), Vector3(s * 0.05, -0.27, -0.02)], [0.105 * gw, 0.095 * gw, 0.07 * gw], 0.04)
		E.call("knee_" + sn, Vector3.ZERO, Vector3.ONE * 0.07 * gw, 0.03)
		C.call("knee_" + sn, [Vector3.ZERO, Vector3(-s * 0.02, -0.13, 0.0), Vector3(-s * 0.04, -0.25, 0.03)], [0.07 * gw, 0.062 * gw, 0.045 * gw], 0.035)
		E.call("knee_" + sn, Vector3(-s * 0.015, -0.08, 0.03), Vector3(0.06, 0.08, 0.06) * gw, 0.03)
		E.call("knee_" + sn, Vector3(-s * 0.045, -0.29, -0.05), Vector3(0.07 * gw, 0.045, 0.15), 0.03)
		S.group = 0
	return S.build(0.012)

static func _part_mesh(kind: String, part: String) -> Mesh:
	var key := kind + "|" + part
	if _baked.has(key):
		return _baked[key]
	var k: Dictionary = KINDS[kind]
	var n := Node3D.new()
	var side := 1.0 if part.ends_with("_r") else -1.0
	match part:
		"hips": _pelvis(n, k)
		"torso": _torso(n, k)
		"head": _head(n, k)
		"jaw": _jaw(n, k)
		"ear_r", "ear_l": _ear(n, k, side)
		"sh_r", "sh_l": _upper_arm(n, k, side)
		"el_r", "el_l": _forearm(n, k, side)
		"hand_r", "hand_l": _hand(n, k, side)
		"leg_r", "leg_l": _thigh(n, k, side)
		"knee_r", "knee_l": _shin_foot(n, k, side)
		"crowns": _crowns(n, k)
		"medal": _medal(n, k)
		_:
			if part.begins_with("sack"):
				_sack(n, k, int(part.substr(4)))
	var m := Props.bake(n, true)
	_baked[key] = m
	return m

static func _skin(k: Dictionary) -> Material:
	return skin_mat(k["skin"], k["skin2"], k["skin3"])

# ---------------------------------------------------------------- anatomy
static func _pelvis(n: Node3D, k: Dictionary) -> void:
	var gw: float = lerpf(0.72, 1.0, k["girth"])
	var br := leather_m(Color(0.22, 0.14, 0.09))
	_P(n, blob("pelvis%.2f" % gw, Vector3(0.26 * gw, 0.14, 0.22 * gw), func(d: Vector3) -> float: return 1.0 - 0.2 * maxf(0.0, d.y)), br, Vector3(0, -0.02, 0.01))

static func _torso(n: Node3D, k: Dictionary) -> void:
	var g: float = k["girth"]
	var gw: float = lerpf(0.72, 1.0, g)
	var kk := "%.2f" % g
	# belt with a fat gold buckle under the belly
	var bw := 0.25 * gw + 0.06 * float(k["belly"]) + 0.01
	_P(n, Geo.torus(bw - 0.03, bw + 0.012, 28, 6), leather_m(Color(0.25, 0.15, 0.08)), Vector3(0, 0.0, -0.04 * k["belly"]), Vector3.ZERO, Vector3(1.0, 1.8, 0.95))
	_P(n, Geo.box(0.13, 0.1, 0.04), gold_m(), Vector3(0, 0.0, -0.04 * k["belly"] - bw * 0.95), Vector3(-10, 0, 0))
	_P(n, Geo.sph(0.022, 10), Mats.glow(Color(1.0, 0.15, 0.1), 1.6), Vector3(0, 0.0, -0.04 * k["belly"] - bw * 0.95 - 0.025))
	# straps over the shoulders to the sacks
	if int(k["sacks"]) > 0:
		var strap := leather_m(Color(0.3, 0.19, 0.1))
		for s in [1, -1]:
			_P(n, tube("strap%s%d" % [kk, s], [Vector3(s * 0.15 * gw, 0.3, -0.19 * gw), Vector3(s * 0.2 * gw, 0.53, -0.12 * gw), Vector3(s * 0.21 * gw, 0.6, 0.04), Vector3(s * 0.16 * gw, 0.46, 0.25 * gw)], [0.022, 0.024, 0.024, 0.022], 6, 0.35, Vector3(0, 0, 1)), strap)
	if k.get("mantle", false):
		# stolen ermine collar
		_P(n, Geo.torus(0.13, 0.25, 30, 10), cloth_m(Color(0.86, 0.83, 0.76), Color(0.12, 0.1, 0.09)), Vector3(0, 0.55, 0.0), Vector3(-14, 0, 0), Vector3(1.0, 0.5, 0.95))
		for i in 9:
			var a := TAU * i / 9.0
			_P(n, Geo.sph(0.016, 6), _dark(), Vector3(cos(a) * 0.19, 0.57 + sin(a) * 0.04, sin(a) * 0.18), Vector3.ZERO, Vector3(0.6, 1.4, 0.6))
	if k.get("hood", false):
		_P(n, Geo.torus(0.09, 0.17, 20, 8), cloth_m(k["cloth"], k["cloth2"]), Vector3(0, 0.53, -0.02), Vector3(-20, 0, 0), Vector3(1.0, 0.6, 1.0))

static func _head(n: Node3D, k: Dictionary) -> void:
	# burning eyes with slit pupils, set in the sculpted sockets
	for s in [1, -1]:
		_P(n, Geo.sph(0.024, 12), Mats.glow(k["eyes"], 5.0), Vector3(s * 0.062, 0.108, -0.178), Vector3.ZERO, Vector3(1.15, 0.85, 1.0))
		_P(n, Geo.box(0.007, 0.03, 0.006), _dark(), Vector3(s * 0.062, 0.108, -0.2))
	# dark mouth behind the teeth (shows when the jaw drops), crooked upper teeth, two of gold
	_P(n, blob("mouth", Vector3(0.1, 0.05, 0.09), func(_d: Vector3) -> float: return 1.0), Mats.mat(Color(0.12, 0.02, 0.02), 0.6), Vector3(0, -0.02, -0.12))
	for i in 8:
		var a := lerpf(-0.95, 0.95, i / 7.0)
		var tm: Material = gold_m() if i in [2, 6] else _tooth()
		var th := 0.03 + 0.012 * sin(i * 2.7)
		_P(n, Geo.cone(0.011, th, 6), tm, Vector3(sin(a) * 0.1, -0.01 - th * 0.5, -0.1 - cos(a) * 0.105), Vector3(180 + sin(i * 1.9) * 12.0, 0, sin(i * 3.1) * 12.0))
	if k.get("hood", false):
		# a battered leather cap
		_P(n, Geo.sph(0.178, 20, 0.5), leather_m(Color(0.32, 0.2, 0.11)), Vector3(0, 0.16, 0.03), Vector3(-10, 0, 0), Vector3(1.0, 0.85, 1.05))
		_P(n, Geo.torus(0.165, 0.185, 24, 5), leather_m(Color(0.22, 0.13, 0.07)), Vector3(0, 0.165, 0.02), Vector3(-10, 0, 0))

static func _jaw(n: Node3D, k: Dictionary) -> void:
	# two tusks jutting up from the underbite
	for s in [1, -1]:
		var tusk := _P(n, tube("tusk", [Vector3.ZERO, Vector3(0, 0.035, -0.005), Vector3(s * 0.006, 0.065, 0.006)], [0.016, 0.012, 0.002], 8), _tooth(), Vector3(s * 0.065, -0.04, -0.16))
		tusk.rotation_degrees = Vector3(0, 0, -s * 12)
	for i in 4:
		var a := lerpf(-0.5, 0.5, i / 3.0)
		_P(n, Geo.cone(0.009, 0.022, 5), _tooth(), Vector3(sin(a) * 0.08, -0.02, -0.11 - cos(a) * 0.075))
	if k.get("mantle", false):
		_P(n, Geo.torus(0.012, 0.02, 12, 5), gold_m(), Vector3(0.045, -0.08, -0.175), Vector3(0, 30, 90))

static func _ear(n: Node3D, k: Dictionary, s: float) -> void:
	var e: float = k["ear"]
	var pts := [Vector3.ZERO, Vector3(s * 0.1, 0.03, 0.03), Vector3(s * 0.22, 0.08, 0.07), Vector3(s * 0.34, 0.13, 0.1), Vector3(s * 0.45 * e, 0.19 * e, 0.12 * e)]
	_P(n, tube("ear%.2f%d" % [e, s], pts, [0.05, 0.075, 0.068, 0.04, 0.004], 12, 0.26, Vector3(0, 0, 1)), _skin(k))
	var inner := []
	for p in pts:
		inner.append(p * 0.9 + Vector3(s * 0.015, -0.004, -0.018))
	_P(n, tube("ear_in%.2f%d" % [e, s], inner, [0.03, 0.05, 0.045, 0.024, 0.003], 10, 0.2, Vector3(0, 0, 1)), skin_mat(Color(0.3, 0.14, 0.11), Color(0.14, 0.05, 0.04), Color(0.45, 0.22, 0.16), 0.2))
	# gold hoops through the lobe
	for i in (2 if k.get("mantle", false) else 1):
		_P(n, Geo.torus(0.024, 0.032, 16, 5), gold_m(), Vector3(s * (0.07 + i * 0.05), -0.035 + i * 0.012, 0.03), Vector3(0, 0, 90))

static func _upper_arm(n: Node3D, k: Dictionary, s: float) -> void:
	if k.get("mantle", false) and s > 0.0:
		# one stolen gilded pauldron, too big for him
		var gm := gold_m()
		_P(n, Geo.sph(0.15, 18, 0.5), gm, Vector3(0.02, 0.02, 0), Vector3(0, 0, -28), Vector3(1.1, 0.75, 1.15))
		_P(n, Geo.torus(0.135, 0.16, 24, 5), gm, Vector3(0.02, 0.02, 0), Vector3(0, 0, -28), Vector3(1.1, 1.0, 1.15))
		for i in 3:
			var sp := _P(n, Geo.cone(0.022, 0.12, 6), Props.iron(), Vector3(0.06 + i * 0.01, 0.1 - i * 0.03, -0.06 + i * 0.06))
			sp.rotation_degrees = Vector3(0, 0, -40 - i * 10)
		_P(n, Geo.sph(0.03, 10), Mats.glow(Color(0.3, 0.6, 1.0), 1.6), Vector3(0.1, 0.06, -0.08))

static func _forearm(n: Node3D, k: Dictionary, _s: float) -> void:
	var gw: float = lerpf(0.72, 1.0, k["girth"]) * float(k["arm"])
	var bands := 3 if k.get("mantle", false) else 1
	var bm: Material = gold_m() if k.get("mantle", false) else leather_m(Color(0.3, 0.2, 0.1))
	for i in bands:
		_P(n, Geo.torus(0.044 * gw, 0.058 * gw, 16, 5), bm, Vector3(0, -0.24 - i * 0.03, 0))

static func _hand(n: Node3D, k: Dictionary, _s: float) -> void:
	var hs: float = k["hand"]
	var sk := _skin(k)
	var cm := _claw()
	for i in 4:
		var x := lerpf(-0.034, 0.034, i / 3.0) * hs
		var L := (1.0 - absf(i - 1.5) * 0.12) * hs
		var pts := [Vector3(x, -0.095 * hs, -0.005), Vector3(x, -0.135 * L, -0.03), Vector3(x, -0.165 * L, -0.015), Vector3(x, -0.175 * L, 0.02)]
		_P(n, tube("finger%d%.2f" % [i, hs], pts, [0.014 * hs, 0.013 * hs, 0.011 * hs, 0.008 * hs], 7), sk)
		var cl := _P(n, Geo.cone(0.008 * hs, 0.03 * hs, 6), cm, pts[3] + Vector3(0, 0.0, 0.012 * hs))
		cl.rotation_degrees = Vector3(-110, 0, 0)
		if k.get("mantle", false) and i in [1, 3]:
			_P(n, Geo.torus(0.013 * hs, 0.02 * hs, 12, 4), gold_m(), pts[1])
			_P(n, Geo.sph(0.01 * hs, 8), Mats.glow(Color(0.2, 1.0, 0.4) if i == 1 else Color(1.0, 0.2, 0.15), 1.8), pts[1] + Vector3(0, 0, -0.018 * hs))

static func _thigh(n: Node3D, k: Dictionary, s: float) -> void:
	var gw: float = lerpf(0.72, 1.0, k["girth"])
	# ragged short breeches
	_P(n, tube("breech%.2f%d" % [gw, s], [Vector3(0, 0.02, 0), Vector3(s * 0.02, -0.08, -0.01), Vector3(s * 0.035, -0.17, -0.02)], [0.12 * gw, 0.115 * gw, 0.105 * gw], 12), cloth_m((k["cloth2"] as Color).lightened(0.15), k["cloth2"]))

static func _shin_foot(n: Node3D, k: Dictionary, s: float) -> void:
	var gw: float = lerpf(0.72, 1.0, k["girth"])
	var sk := _skin(k)
	# shin wraps, and clawed toes on the sculpted foot
	var wrap := cloth_m(Color(0.5, 0.45, 0.36), Color(0.28, 0.24, 0.18))
	for i in 3:
		_P(n, Geo.torus(0.052 * gw, 0.066 * gw, 14, 4), wrap, Vector3(-s * (0.025 + i * 0.006), -0.15 - i * 0.03, 0.01), Vector3(8 - i * 6, 0, s * 5))
	var ft := Vector3(-s * 0.045, -0.29, -0.05)
	var cm := _claw()
	for i in 3:
		var x := ft.x + (i - 1) * 0.04 * gw
		var pts := [Vector3(x, -0.3, -0.15), Vector3(x + (i - 1) * 0.01, -0.305, -0.21), Vector3(x + (i - 1) * 0.015, -0.32, -0.25)]
		_P(n, tube("toe%d%.2f%d" % [i, gw, s], pts, [0.022 * gw, 0.017 * gw, 0.012 * gw], 7), sk)
		var cl := _P(n, Geo.cone(0.01, 0.035, 6), cm, pts[2] + Vector3(0, -0.005, -0.015))
		cl.rotation_degrees = Vector3(-100, 0, 0)

## The stack of stolen crowns: none of them fit, all of them his.
static func _crowns(n: Node3D, _k: Dictionary) -> void:
	var specs := [
		{"r": 0.165, "h": 0.06, "y": 0.0, "rot": Vector3(-6, 0, 7), "spikes": 6, "sh": 0.09, "gem": Color(1.0, 0.15, 0.1), "col": GOLD},
		{"r": 0.125, "h": 0.05, "y": 0.075, "rot": Vector3(9, 35, -13), "spikes": 5, "sh": 0.07, "gem": Color(0.2, 0.45, 1.0), "col": Color(0.85, 0.85, 0.82)},
		{"r": 0.082, "h": 0.04, "y": 0.145, "rot": Vector3(16, 70, 24), "spikes": 4, "sh": 0.075, "gem": Color(0.25, 1.0, 0.35), "col": Color(1.0, 0.6, 0.35)},
	]
	var off := Vector3.ZERO
	for i in specs.size():
		var c: Dictionary = specs[i]
		var g := Models.N(n, "crown%d" % i, off + Vector3(0, c["y"], 0), c["rot"])
		var r: float = c["r"]
		var h: float = c["h"]
		var gm := gold_m(c["col"])
		_P(g, Geo.lathe([Vector2(r - 0.012, 0.0), Vector2(r + 0.006, 0.0), Vector2(r + 0.014, h * 0.5), Vector2(r + 0.008, h), Vector2(r - 0.012, h), Vector2(r - 0.012, 0.0)], 28, "crownband%d" % i), gm)
		for j in int(c["spikes"]):
			var a := TAU * j / float(c["spikes"])
			var sp := _P(g, Geo.cone(0.022 * r / 0.165 + 0.006, c["sh"], 6), gm, Vector3(cos(a) * r, h + float(c["sh"]) * 0.45, sin(a) * r))
			sp.rotation_degrees = Vector3(sin(a) * -8, 0, cos(a) * 8)
			_P(g, Geo.sph(0.012, 6), gm, Vector3(cos(a) * r * 1.04, h + float(c["sh"]) * 0.95, sin(a) * r * 1.04))
			_P(g, Geo.sph(0.016, 8), Mats.glow(c["gem"], 1.8), Vector3(cos(a + PI / float(c["spikes"])) * (r + 0.014), h * 0.5, sin(a + PI / float(c["spikes"])) * (r + 0.014)), Vector3.ZERO, Vector3(1.0, 1.0, 0.6))
		if i == specs.size() - 1:
			_P(g, Geo.sph(0.032, 12), Mats.glow(c["gem"], 2.2), Vector3(0, h + 0.04, 0))
		off.x += 0.012 * (1 if i % 2 == 0 else -1)

## A fat gold medallion on a heavy chain (swings from the neck).
static func _medal(n: Node3D, _k: Dictionary) -> void:
	var gm := gold_m()
	for s in [1, -1]:
		for i in 9:
			var t := i / 8.0
			var p := Vector3(s * 0.16 * (1.0 - t), -0.25 * t * t - 0.02 * t, -0.09 * t)
			p.z -= sin(t * PI) * 0.06
			var lk := _P(n, Geo.torus(0.009, 0.017, 10, 4), gm, p, Vector3(0, 0, 90 if i % 2 == 0 else 0))
			lk.rotation_degrees.y = s * 30.0
	_P(n, Geo.cyl(0.075, 0.075, 0.022, 24), gm, Vector3(0, -0.29, -0.12), Vector3(80, 0, 0))
	_P(n, Geo.torus(0.06, 0.08, 24, 5), gm, Vector3(0, -0.29, -0.13), Vector3(80, 0, 0))
	_P(n, Geo.sph(0.03, 12), Mats.glow(Color(1.0, 0.12, 0.08), 2.0), Vector3(0, -0.29, -0.135), Vector3.ZERO, Vector3(1.0, 1.0, 0.55))

## A lumpy sack of gold, tied off at the neck, coins showing.
static func _sack(n: Node3D, k: Dictionary, i: int) -> void:
	var sz: float = [1.15, 0.85, 0.78][i] * (1.0 if int(k["sacks"]) > 1 else 0.5)
	var burlap := cloth_m(Color(0.3, 0.21, 0.12), Color(0.14, 0.09, 0.05))
	var rad := Vector3(0.24, 0.25, 0.19) * sz
	_P(n, blob("sack%.2f" % sz, rad, func(d: Vector3) -> float: return 1.0 + 0.07 * sin(d.x * 9.0 + 1.0) * sin(d.y * 7.0) + 0.05 * sin(d.z * 11.0) - 0.35 * bump(d, Vector3.UP, 0.35)), burlap, Vector3(0, 0, 0.04 * sz))
	_P(n, tube("sackneck%.2f" % sz, [Vector3(0, rad.y * 0.75, 0.04 * sz), Vector3(0, rad.y * 1.05, 0.03 * sz), Vector3(0, rad.y * 1.3, 0.0)], [0.07 * sz, 0.055 * sz, 0.09 * sz], 10), burlap)
	_P(n, Geo.torus(0.05 * sz, 0.068 * sz, 14, 5), leather_m(Color(0.3, 0.19, 0.1)), Vector3(0, rad.y * 1.02, 0.035 * sz))
	_P(n, blob("sackcoins%.2f" % sz, Vector3(0.07, 0.03, 0.07) * sz, func(_d: Vector3) -> float: return 1.0), coin_mat(), Vector3(0, rad.y * 1.32, 0.0))
	var gm := gold_m()
	for j in 3:
		_P(n, Geo.cyl(0.03 * sz + 0.01, 0.03 * sz + 0.01, 0.008, 12), gm, Vector3((j - 1) * 0.04 * sz, rad.y * 1.36 + j * 0.006, (j % 2) * 0.02), Vector3(30 + j * 25, j * 40, 15))

# ---------------------------------------------------------------- weapon
## The Hoardkey: a vault key the size of a club, the king's sceptre and his favourite weapon.
static func hoardkey() -> Node3D:
	var root := Node3D.new()
	var w := Models.N(root, "w", Vector3.ZERO, Vector3(-90, 0, 0))
	var mi := MeshInstance3D.new()
	if not _baked.has("hoardkey"):
		var n := Node3D.new()
		var gm := gold_m()
		var bronze := SkeletonModel.dm(SkeletonModel.STEEL, Color(0.56, 0.42, 0.22), Color(0.2, 0.12, 0.05), {})
		var lt := leather_m(Color(0.25, 0.14, 0.08))
		# grip and the ornate bow (the ring end)
		_P(n, Geo.cyl(0.032, 0.035, 0.3, 10), lt, Vector3(0, 0.03, 0))
		_P(n, Geo.torus(0.07, 0.11, 28, 8), gm, Vector3(0, -0.22, 0), Vector3(90, 0, 0))
		for j in 3:
			var a := TAU * j / 3.0 + PI / 2.0
			_P(n, Geo.torus(0.022, 0.034, 14, 5), gm, Vector3(cos(a) * 0.035, -0.22 + sin(a) * 0.035, 0), Vector3(90, 0, 0))
		_P(n, Geo.sph(0.03, 10), Mats.glow(Color(1.0, 0.15, 0.1), 2.0), Vector3(0, -0.22, 0))
		# shaft with collars
		_P(n, Geo.cyl(0.042, 0.048, 0.86, 12), bronze, Vector3(0, 0.62, 0))
		for y in [0.2, 0.55, 0.98]:
			_P(n, Geo.torus(0.04, 0.064, 18, 5), gm, Vector3(0, y, 0))
		# the bit: heavy wards studded with nails
		_P(n, Geo.box(0.24, 0.07, 0.07), bronze, Vector3(0.12, 0.9, 0))
		_P(n, Geo.box(0.18, 0.06, 0.07), bronze, Vector3(0.09, 1.0, 0))
		_P(n, Geo.box(0.06, 0.2, 0.07), bronze, Vector3(0.21, 0.95, 0))
		_P(n, Geo.box(0.05, 0.08, 0.075), gm, Vector3(0.15, 0.95, 0))
		for j in 5:
			var nl := _P(n, Geo.cone(0.014, 0.08, 5), Props.iron(), Vector3(0.24 + (j % 2) * 0.01, 0.86 + j * 0.035, (j % 2 - 0.5) * 0.04))
			nl.rotation_degrees = Vector3(0, 0, -90)
		_P(n, Geo.cone(0.05, 0.1, 10), gm, Vector3(0, 1.1, 0))
		_baked["hoardkey"] = Props.bake(n, true)
	mi.mesh = _baked["hoardkey"]
	w.add_child(mi)
	return root

# ---------------------------------------------------------------- the hoard (room props, piles)
static func mound_mesh(r: float, h: float) -> Mesh:
	return Geo.lathe([Vector2(r, 0.0), Vector2(r * 0.95, h * 0.08), Vector2(r * 0.8, h * 0.35), Vector2(r * 0.55, h * 0.75), Vector2(r * 0.25, h * 0.97), Vector2(0.0, h)], 22, "mound%.2f_%.2f" % [r, h])

## A heap of coins on the floor with its own glint.
static func pile(amount: int) -> Node3D:
	var root := Node3D.new()
	var s := clampf(0.55 + amount * 0.004, 0.55, 0.8)
	_P(root, mound_mesh(s, s * 0.45), coin_mat(GOLD, 2.2))
	var gm := gold_m()
	for i in 7:
		var a := i * 2.4
		_P(root, Geo.cyl(0.045, 0.045, 0.01, 12), gm, Vector3(cos(a) * s * (0.8 + (i % 3) * 0.15), 0.01 + (i % 2) * 0.03, sin(a) * s * (0.8 + (i % 3) * 0.15)), Vector3(10 + i * 9, i * 30, 20))
	var l := OmniLight3D.new()
	l.light_color = Color(1.0, 0.75, 0.3)
	l.light_energy = 2.0
	l.omni_range = 3.5
	l.position = Vector3(0, 0.8, 0)
	root.add_child(l)
	var ring := _P(root, Geo.torus(s + 0.15, s + 0.22, 32, 4), Mats.glow(Color(1.0, 0.7, 0.2), 1.4), Vector3(0, 0.02, 0), Vector3.ZERO, Vector3(1.0, 0.2, 1.0))
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# a soft beam of light so a pile is easy to spot from the camera
	var beam := _P(root, Geo.cyl(0.1, s * 0.6, 2.4, 14), Mats.glow(Color(1.0, 0.75, 0.25), 1.2, 1.2, 0.6), Vector3(0, 1.2, 0))
	beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	sparkle(root, Vector3(0, 0.25, 0), Color(1.0, 0.85, 0.4), 8, Vector3(s, 0.1, s), 0.4)
	return root

## A lit gold-banded bomb (King Grubb's Gilded Bombs).
static func bomb() -> Node3D:
	var root := Node3D.new()
	_P(root, Geo.sph(0.2, 16), Props.iron())
	_P(root, Geo.torus(0.19, 0.22, 24, 5), gold_m())
	_P(root, Geo.torus(0.19, 0.22, 24, 5), gold_m(), Vector3.ZERO, Vector3(90, 0, 0))
	_P(root, Geo.cyl(0.04, 0.05, 0.08, 8), Props.iron(), Vector3(0, 0.22, 0))
	_P(root, Geo.cyl(0.01, 0.01, 0.12, 5), Mats.mat(Color(0.3, 0.25, 0.2), 0.9), Vector3(0, 0.3, 0), Vector3(0, 0, 20))
	sparkle(root, Vector3(-0.02, 0.37, 0), Color(1.0, 0.7, 0.2), 24, Vector3(0.01, 0.01, 0.01), 1.5, 0.3, -3.0)
	var l := OmniLight3D.new()
	l.light_color = Color(1.0, 0.6, 0.2)
	l.light_energy = 1.5
	l.omni_range = 2.5
	l.position = Vector3(0, 0.4, 0)
	root.add_child(l)
	return root

## Looping glitter / fuse sparks (safe to build before the node is in the tree).
static func sparkle(parent: Node3D, pos: Vector3, col: Color, amount: int, box: Vector3, speed: float, life := 0.9, grav := 0.4) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = amount
	p.lifetime = life
	p.position = pos
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = box
	pm.direction = Vector3.UP
	pm.spread = 60.0
	pm.initial_velocity_min = speed * 0.3
	pm.initial_velocity_max = speed
	pm.gravity = Vector3(0, grav, 0)
	pm.scale_min = 0.5
	pm.scale_max = 1.0
	var g := Gradient.new()
	g.set_color(0, Color(col.r, col.g, col.b, 1.0))
	g.set_color(1, Color(col.r, col.g * 0.6, col.b * 0.3, 0.0))
	var gt := GradientTexture1D.new()
	gt.gradient = g
	pm.color_ramp = gt
	p.process_material = pm
	var q := QuadMesh.new()
	q.size = Vector2(0.04, 0.04)
	q.material = Mats.particle_mat(true, Color(2.5, 2.2, 1.6))
	p.draw_pass_1 = q
	parent.add_child(p)
	return p

# ---------------------------------------------------------------- secondary motion
## Runs at the end of Anim.pose for goblin rigs: everything that makes them goblins.
static func after_pose(rig: Node3D, J: Dictionary, D: Dictionary, st: Dictionary, dt: float) -> void:
	var kind: String = rig.get_meta("goblin")
	var t: float = st.get("time", 0.0)
	var ph: float = st.get("phase", 0.0)
	var m: float = clampf(st.get("move", 0.0), 0.0, 1.4)
	var a: float = st.get("atk", -1.0)
	var style: String = st.get("style", "")
	var hit: float = st.get("hit", 0.0)
	var calm: bool = not st.get("aggro", true)
	var sd: float = D["seed"]
	var hips: Node3D = J["hips"]
	var torso: Node3D = J["torso"]
	var head: Node3D = J["head"]
	var king := kind == "king"
	var carry: float = spring(D, "carry", 1.0 if rig.has_meta("carry") else 0.0, 60.0, 0.8, dt)

	# --- gait: the king waddles side to side; grabbers scurry hunched, looking up
	if king:
		hips.rotation.z += cos(ph) * 0.11 * m
		torso.rotation.z -= cos(ph) * 0.16 * m
		hips.position.x += cos(ph) * 0.03 * m
		# a predatory hunch: shoulders rolled forward, head thrust out and looking up from under the brow
		torso.rotation.x -= 0.2
		head.rotation.x += 0.14
		for sn in ["sh_l", "sh_r"]:
			(J[sn] as Node3D).rotation.x += 0.12
	else:
		var hunch := (0.42 * minf(m, 1.0) + 0.18) * (1.0 - carry)
		torso.rotation.x -= hunch
		head.rotation.x += hunch * 0.8
		hips.position.y += absf(sin(ph)) * 0.025 * m
		for sn in ["sh_l", "sh_r"]:
			(J[sn] as Node3D).rotation.x += 0.35 * minf(m, 1.0) * (1.0 - carry)

	# --- the king holds the Hoardkey up at the ready between swings
	if king and J.has("weapon") and not rig.has_meta("held"):
		var ready := spring(D, "ready", 1.0 if a < 0.0 and calm_ready(st) else 0.0, 40.0, 0.8, dt)
		if ready > 0.01:
			var er: Node3D = J["el_r"]
			er.rotation.x = lerpf(er.rotation.x, 1.35 + sin(t * 1.1) * 0.05, ready)
			var sr: Node3D = J["sh_r"]
			sr.rotation.x = lerpf(sr.rotation.x, 0.25 + sin(ph) * 0.15 * m, ready)
			sr.rotation.z = lerpf(sr.rotation.z, 0.15, ready)

	# --- a heavy body (the mutant): arms can't swing past the gut and shoulders, so the swings are
	# carried by the torso and hips instead
	if rig.has_meta("held"):
		var sw := 0.0
		for sn in ["sh_l", "sh_r"]:
			var sh: Node3D = J[sn]
			sw = maxf(sw, absf(sh.rotation.x) - 0.6)
			sh.rotation = Vector3(clampf(sh.rotation.x * 0.55, -0.7, 1.5), sh.rotation.y * 0.5, sh.rotation.z * 0.5)
		torso.rotation.x += sw * 0.12 if a >= 0.0 else 0.0

	# --- carrying loot overhead (grabbers)
	if J.has("loot"):
		(J["loot"] as Node3D).visible = carry > 0.5
		if carry > 0.01:
			var bob := sin(ph * 2.0) * 0.08 * m
			_blend(J["sh_l"], Vector3(2.75 + bob, 0, 0.3), carry)
			_blend(J["sh_r"], Vector3(2.75 + bob, 0, -0.3), carry)
			_blend(J["el_l"], Vector3(0.5, 0, 0), carry)
			_blend(J["el_r"], Vector3(0.5, 0, 0), carry)
			(J["loot"] as Node3D).position.y = 0.98 + bob * 0.3

	# --- the king's idle before he notices you: hunched over, biting a coin
	var calm_w := spring(D, "calm", 1.0 if (king and calm and m < 0.2 and a < 0.0) else 0.0, 30.0, 0.9, dt)
	var bite := 0.0
	if J.has("coin"):
		(J["coin"] as Node3D).visible = calm_w > 0.5
	if calm_w > 0.01:
		var cyc := fmod(t * 0.45 + sd * 3.0, 1.0)
		var lift := Anim.kf(cyc, [[0.0, 0.0], [0.2, 1.0], [0.55, 1.0], [0.7, 0.35], [0.85, 0.35], [1.0, 0.0]])
		bite = maxf(0.0, sin(t * 16.0)) * (1.0 if cyc > 0.25 and cyc < 0.55 else 0.0)
		_blend(J["sh_l"], Vector3(lerpf(0.9, 1.75, lift), 0.0, lerpf(0.1, 0.55, lift)), calm_w)
		_blend(J["el_l"], Vector3(lerpf(1.1, 2.3, lift), 0, 0), calm_w)
		_blend(J["sh_r"], Vector3(0.35, 0, -0.1), calm_w)
		torso.rotation.x -= 0.2 * calm_w
		head.rotation.x += (lerpf(-0.2, 0.15, lift) - (bite * 0.06)) * calm_w
		head.rotation.y += sin(t * 0.7) * 0.15 * calm_w * (1.0 - lift)

	# --- jaw: roars on the wind-up, chatters when he cackles, chomps the coin
	if J.has("jaw"):
		var open := 0.04 + sin(t * 1.3 + sd * 5.0) * 0.02
		if a >= 0.0:
			match style:
				"cackle":
					open = 0.22 + absf(sin(t * 26.0)) * 0.22
				"burst":
					open = Anim.kf(a, [[0, 0.1], [0.15, 0.55], [0.7, 0.45], [1, 0.1]])
				"lob", "scoop":
					open = Anim.kf(a, [[0, 0.05], [0.4, 0.3], [0.6, 0.15], [1, 0.05]])
				_:
					open = Anim.kf(a, [[0, 0.05], [0.35, 0.42], [0.55, 0.1], [1, 0.05]])
		open = maxf(open, hit * 0.35)
		open = lerpf(open, 0.04 + bite * 0.22, calm_w)
		(J["jaw"] as Node3D).rotation.x = spring(D, "jaw", open, 400.0, 0.5, dt)

	# --- ears: flop with the steps and turns, twitch now and then, pin back to attack
	var yaw: float = rig.rotation.y
	var yv: float = wrapf(yaw - D.get("gy", yaw), -PI, PI) / maxf(dt, 0.001) if dt > 0.0 else 0.0
	D["gy"] = yaw
	var hy: float = hips.position.y - HIPS_Y
	var vy: float = (hy - D.get("ghy", hy)) / maxf(dt, 0.001) if dt > 0.0 else 0.0
	D["ghy"] = hy
	var pin := 0.0
	if a >= 0.0 and style != "cackle":
		pin = Anim.kf(a, [[0, 0.0], [0.3, 1.0], [0.7, 1.0], [1, 0.0]])
	pin = maxf(pin, hit)
	for s in [1.0, -1.0]:
		var sn := "r" if s > 0.0 else "l"
		if not J.has("ear_" + sn):
			continue
		var ear: Node3D = J["ear_" + sn]
		var twitch := 0.0
		var tw := fmod(t * (0.31 if king else 0.6) + sd * 7.0 + (0.37 if s > 0.0 else 0.0), 1.0)
		if tw < 0.05:
			twitch = sin(tw / 0.05 * PI) * 0.5
		var flop := spring(D, "earf" + sn, clampf(-vy * 0.25, -0.6, 0.6), 70.0, 0.18, dt)
		var swing := spring(D, "ears" + sn, clampf(yv * 0.07, -0.5, 0.5), 60.0, 0.22, dt)
		ear.rotation = Vector3(-swing * 0.4 - pin * 0.25, s * (0.15 + pin * 0.65 + twitch * 0.3) + swing, s * (-0.12 + flop + twitch))

	# --- weight: a blow landing or a hit taken jolts the belly and the crowns
	var prev_a: float = D.get("ga", -1.0)
	D["ga"] = a
	var jolt := 0.0
	if a >= 0.0 and prev_a >= 0.0 and prev_a < Anim.impact_at(style) and a >= Anim.impact_at(style):
		jolt = 1.0
	var prev_hit: float = D.get("ghit", 0.0)
	D["ghit"] = hit
	if hit > prev_hit + 0.2:
		jolt = maxf(jolt, 0.7)
	if jolt > 0.0:
		Anim.kick(D, "jig", -3.0 * jolt)
		Anim.kick(D, "crx", 6.0 * jolt * (1.0 if randf() < 0.5 else -1.0))
		Anim.kick(D, "crz", 5.0 * jolt * (1.0 if randf() < 0.5 else -1.0))
		Anim.kick(D, "mdx", 4.0 * jolt)

	# --- the stack of crowns wobbles on his head
	if J.has("crowns"):
		var cr: Node3D = J["crowns"]
		var hx: float = head.rotation.x + torso.rotation.x
		var hz: float = head.rotation.z + torso.rotation.z
		var phx: float = D.get("ghx", hx)
		var phz: float = D.get("ghz", hz)
		if dt > 0.0:
			Anim.kick(D, "crx", -(hx - phx) * 14.0 - vy * 1.2)
			Anim.kick(D, "crz", -(hz - phz) * 14.0 + yv * 0.08)
		D["ghx"] = hx
		D["ghz"] = hz
		cr.rotation = Vector3(spring(D, "crx", 0.0, 55.0, 0.12, dt), sin(t * 0.4) * 0.05, spring(D, "crz", 0.0, 55.0, 0.12, dt))

	# --- medallion swings like a pendulum, belly jiggles, sacks bounce
	if J.has("medal"):
		var md: Node3D = J["medal"]
		var tilt: float = torso.rotation.x
		if dt > 0.0:
			Anim.kick(D, "mdx", -vy * 0.4)
			Anim.kick(D, "mdz", yv * 0.05)
		md.rotation = Vector3(spring(D, "mdx", -tilt * 0.8, 35.0, 0.15, dt), 0.0, spring(D, "mdz", -torso.rotation.z, 35.0, 0.15, dt))
	if J.has("belly"):
		var bl: Node3D = J["belly"]
		var jig := spring(D, "jig", clampf(-vy * 0.12, -0.12, 0.12), 180.0, 0.12, dt)
		var breathe := sin(t * (1.6 if king else 3.0) + sd * 10.0) * 0.025
		bl.scale = Vector3(1.0 - jig * 0.5 + breathe * 0.5, 1.0 + jig + breathe, 1.0 - jig * 0.4 + breathe)
	var shown: int = rig.get_meta("sacks") if rig.has_meta("sacks") else 99
	var i := 0
	for sk in J["sacks"]:
		var sn: Node3D = sk
		# hidden by scale, so it works for a skinned sack (its bone) as well as a mesh on the joint
		sn.scale = Vector3.ONE if i < shown else Vector3.ONE * 0.001
		sn.rotation.x = spring(D, "sk%d" % i, clampf(vy * 0.35, -0.4, 0.4) - torso.rotation.x * 0.3, 90.0, 0.2, dt)
		sn.rotation.z = spring(D, "skz%d" % i, clampf(-yv * 0.04, -0.3, 0.3), 70.0, 0.25, dt)
		i += 1

## True unless he is sitting in his coin-biting idle (then the key hangs at his side).
static func calm_ready(st: Dictionary) -> bool:
	return st.get("aggro", true) or st.get("move", 0.0) > 0.2

static func spring(D: Dictionary, key: String, target: float, k: float, z: float, dt: float) -> float:
	return Anim.spring(D, key, target, k, z, dt)

static func _blend(n: Node3D, r: Vector3, w: float) -> void:
	n.rotation = n.rotation.lerp(r, clampf(w, 0.0, 1.0))

# ---------------------------------------------------------------- shaders
const SKIN_SHADER := """
shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;
uniform vec3 col : source_color = vec3(0.4, 0.47, 0.25);
uniform vec3 col2 : source_color = vec3(0.17, 0.22, 0.1);
uniform vec3 col3 : source_color = vec3(0.66, 0.6, 0.38);
uniform float warts = 1.0;
uniform bool rest_uv = false;
varying vec3 lp;
float h31(vec3 p){ p = fract(p * 0.3183099 + 0.1); p *= 17.0; return fract(p.x * p.y * p.z * (p.x + p.y + p.z)); }
float vn3(vec3 x){ vec3 i = floor(x); vec3 f = fract(x); f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(h31(i), h31(i + vec3(1,0,0)), f.x), mix(h31(i + vec3(0,1,0)), h31(i + vec3(1,1,0)), f.x), f.y),
		mix(mix(h31(i + vec3(0,0,1)), h31(i + vec3(1,0,1)), f.x), mix(h31(i + vec3(0,1,1)), h31(i + vec3(1,1,1)), f.x), f.y), f.z); }
float fb3(vec3 p){ float v = 0.0; float a = 0.5; for (int i = 0; i < 4; i++){ v += a * vn3(p); p = p * 2.03 + 1.7; a *= 0.5; } return v; }
void vertex(){ lp = rest_uv ? vec3(UV, UV2.x) : VERTEX; }
void fragment(){
	vec3 p = lp;
	float n1 = fb3(p * 8.0);
	float n2 = vn3(p * 46.0);
	vec3 alb = col * (0.82 + n1 * 0.3);
	alb = mix(alb, col2, smoothstep(0.5, 0.78, fb3(p * 5.0 + 3.0)) * 0.7);
	alb = mix(alb, col3, smoothstep(0.55, 0.85, fb3(p * 3.0 + 9.0)) * 0.3);
	float wart = smoothstep(0.8, 0.93, vn3(p * 60.0)) * warts;
	float spot = smoothstep(0.72, 0.8, vn3(p * 20.0 + 5.0)) * 0.6;
	float vein = (1.0 - smoothstep(0.0, 0.035, abs(fb3(p * 11.0) - 0.5))) * 0.6;
	alb = mix(alb, col2 * 0.75, wart * 0.45 + spot * 0.35 + vein * 0.3);
	float hgt = wart * 1.0 + n2 * 0.25 - vein * 0.4 + n1 * 0.2;
	float hk = hgt * 0.0005;
	vec3 dpdx = dFdx(VERTEX);
	vec3 dpdy = dFdy(VERTEX);
	vec3 r1 = cross(dpdy, NORMAL);
	vec3 r2 = cross(NORMAL, dpdx);
	float det = dot(dpdx, r1);
	vec3 grad = sign(det) * (dFdx(hk) * r1 + dFdy(hk) * r2);
	if (abs(det) > 1e-12) { NORMAL = normalize(abs(det) * NORMAL - grad); }
	ALBEDO = alb;
	ROUGHNESS = 0.42 + n1 * 0.3 + wart * 0.2;
	SPECULAR = 0.45;
	BACKLIGHT = col3 * 0.12;
	RIM = 0.3;
	RIM_TINT = 0.4;
}
"""

const COIN_SHADER := """
shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;
uniform vec3 col : source_color = vec3(1.0, 0.74, 0.28);
uniform float glint = 1.0;
varying vec3 wp;
vec2 h22(vec2 p){ p = vec2(dot(p, vec2(127.1, 311.7)), dot(p, vec2(269.5, 183.3))); return fract(sin(p) * 43758.5453); }
void vertex(){ wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }
void fragment(){
	vec2 p = (wp.xz + vec2(wp.y * 0.6, -wp.y * 0.4)) * 11.0;
	vec2 i = floor(p);
	vec2 f = fract(p);
	float best = 9.0;
	vec2 bid = vec2(0.0);
	for (int y = -1; y <= 1; y++) {
		for (int x = -1; x <= 1; x++) {
			vec2 g = vec2(float(x), float(y));
			vec2 o = h22(i + g);
			vec2 r = g + o - f;
			float d = dot(r, r);
			if (d < best) { best = d; bid = i + g; }
		}
	}
	float d = sqrt(best);
	vec2 rnd = h22(bid * 1.7 + 3.1);
	float face = 1.0 - smoothstep(0.36, 0.44, d);
	float rim = smoothstep(0.3, 0.36, d) * face;
	vec3 alb = col * (0.55 + rnd.x * 0.45);
	alb = mix(col * 0.22, alb, face);
	alb *= 1.0 - rim * 0.25;
	vec3 tilt = normalize(vec3((rnd.x - 0.5) * 1.1, 1.0, (rnd.y - 0.5) * 1.1));
	NORMAL = normalize(mix(NORMAL, (VIEW_MATRIX * vec4(tilt, 0.0)).xyz, face * 0.55));
	ALBEDO = alb;
	METALLIC = 0.85;
	ROUGHNESS = mix(0.7, 0.22 + rnd.y * 0.15, face);
	float tw = pow(rnd.y, 14.0) * (0.5 + 0.5 * sin(TIME * 2.5 + rnd.x * 40.0));
	EMISSION = col * glint * (0.07 + tw * 3.0) * face;
}
"""
