class_name Knight
extends RefCounted
## Skinned, shader-textured warrior. One smooth mesh on a Skeleton3D whose bones mirror
## the procedural-animation joints, so Anim.pose drives it unchanged.

## [name, parent index, rest position in model space]
const BONE_DEF := [
	["hips", -1, Vector3(0, 0.95, 0)],
	["torso", 0, Vector3(0, 1.03, 0)],
	["head", 1, Vector3(0, 1.66, 0)],
	["sh_r", 1, Vector3(0.235, 1.5, 0)],
	["el_r", 3, Vector3(0.235, 1.205, 0)],
	["hand_r", 4, Vector3(0.235, 0.955, 0)],
	["sh_l", 1, Vector3(-0.235, 1.5, 0)],
	["el_l", 6, Vector3(-0.235, 1.205, 0)],
	["hand_l", 7, Vector3(-0.235, 0.955, 0)],
	["leg_r", 0, Vector3(0.1, 0.91, 0)],
	["knee_r", 9, Vector3(0.1, 0.47, 0)],
	["leg_l", 0, Vector3(-0.1, 0.91, 0)],
	["knee_l", 11, Vector3(-0.1, 0.47, 0)],
	["cape1", 1, Vector3(0, 1.52, 0.15)],
	["cape2", 13, Vector3(0, 1.16, 0.2)],
	["cape3", 14, Vector3(0, 0.82, 0.25)],
]
const SKIN := 0
const STEEL := 1
const CHAIN := 2
const LEATHER := 3
const CLOTH := 4
const GOLD := 5
const QUILT := 6
const HAIR := 7

static var _bi := {}
static var _shader: Shader

static func bi(nm: String) -> int:
	if _bi.is_empty():
		for i in BONE_DEF.size():
			_bi[BONE_DEF[i][0]] = i
	return _bi[nm]

static func default_gear() -> Dictionary:
	return {"armor": "quilted", "steel": Color(0.62, 0.62, 0.64), "trim": Color(0.85, 0.66, 0.3), "glow": null,
		"gloves": "", "boots": "", "belt": true, "cloth": Color(0.42, 0.06, 0.05), "emblem": Color(0.86, 0.82, 0.72),
		"cape": Color(0.3, 0.05, 0.04), "leather": Color(0.3, 0.19, 0.11), "skin": Color(0.66, 0.48, 0.38),
		"hair": Color(0.22, 0.14, 0.08), "quilt": Color(0.4, 0.34, 0.25), "coif": false}

# ---------------------------------------------------------------- rig
static func build(gear: Dictionary) -> Node3D:
	var root := Node3D.new()
	root.name = "Rig"
	root.set_script(load("res://scripts/knight_rig.gd"))
	var skel := Skeleton3D.new()
	skel.name = "Skeleton"
	root.add_child(skel)
	for i in BONE_DEF.size():
		skel.add_bone(BONE_DEF[i][0])
	for i in BONE_DEF.size():
		var par: int = BONE_DEF[i][1]
		var local: Vector3 = BONE_DEF[i][2] - (BONE_DEF[par][2] if par >= 0 else Vector3.ZERO)
		if par >= 0:
			skel.set_bone_parent(i, par)
		skel.set_bone_rest(i, Transform3D(Basis(), local))
		skel.set_bone_pose_position(i, local)
	# animation proxies mirroring the bones
	var J := {}
	var proxies := {}
	for i in 13:
		var par: int = BONE_DEF[i][1]
		var n := Node3D.new()
		n.name = BONE_DEF[i][0]
		n.position = BONE_DEF[i][2] - (BONE_DEF[par][2] if par >= 0 else Vector3.ZERO)
		if par >= 0:
			(proxies[par] as Node3D).add_child(n)
		else:
			root.add_child(n)
		proxies[i] = n
		J[BONE_DEF[i][0]] = n
	J["hips_y"] = 0.95
	var grip := Models.N(J["hand_r"], "grip_r", Vector3(0, -0.055, -0.005), Vector3(-28, 0, 0))
	J["grip_r"] = grip
	J["grip_l"] = Models.N(J["hand_l"], "grip_l", Vector3(0, -0.055, 0))
	J["mount_l"] = Models.N(J["el_l"], "mount_l", Vector3(-0.075, -0.14, 0), Vector3(0, 70, 0))
	root.set("skel", skel)
	root.set("proxy_of", proxies)
	root.set("cape_bones", [bi("cape1"), bi("cape2"), bi("cape3")])
	root.set("cape_rest", [BONE_DEF[13][2] - BONE_DEF[1][2], BONE_DEF[14][2] - BONE_DEF[13][2], BONE_DEF[15][2] - BONE_DEF[14][2]])
	root.set_meta("j", J)
	root.set_meta("h", 1.0)
	root.set_meta("knight", true)
	rebuild_body(root, gear)
	return root

static func rebuild_body(root: Node3D, gear: Dictionary) -> void:
	var skel: Skeleton3D = root.get_node("Skeleton")
	var old := skel.get_node_or_null("Body")
	if old:
		old.name = "OldBody"
		old.queue_free()
	var mi := MeshInstance3D.new()
	mi.name = "Body"
	mi.mesh = build_mesh(gear)
	mi.material_override = material(gear)
	skel.add_child(mi)
	mi.skeleton = NodePath("..")

static func material(g: Dictionary) -> ShaderMaterial:
	if _shader == null:
		_shader = Shader.new()
		_shader.code = SHADER
	var m := ShaderMaterial.new()
	m.shader = _shader
	m.set_shader_parameter("steel", g["steel"])
	m.set_shader_parameter("gold", g["trim"])
	m.set_shader_parameter("leather", g["leather"])
	m.set_shader_parameter("cloth", g["cloth"])
	m.set_shader_parameter("cape", g["cape"] if g["cape"] != null else g["cloth"])
	m.set_shader_parameter("emblem", g["emblem"])
	m.set_shader_parameter("skin", g["skin"])
	m.set_shader_parameter("hair", g["hair"])
	m.set_shader_parameter("quilt", g["quilt"])
	m.set_shader_parameter("glow", g["glow"] if g["glow"] != null else Color.BLACK)
	m.set_shader_parameter("glow_amt", 1.0 if g["glow"] != null else 0.0)
	return m

# ---------------------------------------------------------------- mesh builder
class Body:
	var st := SurfaceTool.new()
	var n := 0

	func _init() -> void:
		st.begin(Mesh.PRIMITIVE_TRIANGLES)

	func vert(p: Vector3, nrm: Vector3, uv: Vector2, uv2: Vector2, col: Color, bw: Dictionary) -> int:
		var keys := bw.keys()
		keys.sort_custom(func(a, b): return bw[a] > bw[b])
		var bones := PackedInt32Array([0, 0, 0, 0])
		var ws := PackedFloat32Array([0.0, 0.0, 0.0, 0.0])
		var tot := 0.0
		for i in mini(4, keys.size()):
			bones[i] = keys[i]
			ws[i] = bw[keys[i]]
			tot += ws[i]
		if tot <= 0.0:
			ws[0] = 1.0
			tot = 1.0
		for i in 4:
			ws[i] /= tot
		st.set_normal(nrm)
		st.set_uv(uv)
		st.set_uv2(uv2)
		st.set_color(col)
		st.set_bones(bones)
		st.set_weights(ws)
		st.add_vertex(p)
		n += 1
		return n - 1

	## Sweeps elliptical rings along Y. ring: [y, cx, cz, rx, rz, ridge, sharpness]
	func sweep(rings: Array, seg: int, a0: float, a1: float, mat: int, flags: float, emb: float, wfn: Callable, xf := Transform3D.IDENTITY) -> void:
		var full := (a1 - a0) >= TAU - 0.001
		var cols := seg if full else seg + 1
		var nr := rings.size()
		var P := []
		var C := []
		var vacc := [0.0]
		for i in nr:
			var r: Array = rings[i]
			var y: float = r[0]
			var cx: float = r[1]
			var cz: float = r[2]
			var rx: float = r[3]
			var rz: float = r[4]
			var ridge: float = r[5] if r.size() > 5 else 0.0
			var sharp: float = r[6] if r.size() > 6 else 6.0
			var row := []
			for s in cols:
				var th := a0 + (a1 - a0) * float(s) / seg
				var m := 1.0 + ridge * pow(maxf(0.0, -sin(th)), sharp)
				row.append(xf * Vector3(cx + rx * cos(th) * m, y, cz + rz * sin(th) * m))
			P.append(row)
			C.append(xf * Vector3(cx, y, cz))
			if i > 0:
				var pr: Array = rings[i - 1]
				vacc.append(vacc[i - 1] + Vector2(y - pr[0], (rx + rz) * 0.5 - (pr[3] + pr[4]) * 0.5).length())
		var y0: float = rings[0][0]
		var y1: float = rings[nr - 1][0]
		var span := y1 - y0 if absf(y1 - y0) > 0.0001 else 1.0
		var idx := []
		for i in nr:
			var row_idx := []
			var r: Array = rings[i]
			var ravg: float = (r[3] + r[4]) * 0.5
			for s in cols:
				var sp: int = (s + 1) % cols if full else mini(s + 1, cols - 1)
				var sm: int = (s - 1 + cols) % cols if full else maxi(s - 1, 0)
				var dth: Vector3 = P[i][sp] - P[i][sm]
				var dy: Vector3 = P[mini(i + 1, nr - 1)][s] - P[maxi(i - 1, 0)][s]
				var nrm := dth.cross(dy)
				var p: Vector3 = P[i][s]
				var out: Vector3 = p - C[i]
				if nrm.length() < 0.000001:
					nrm = out if out.length() > 0.00001 else xf.basis * Vector3(0, 1 if i == nr - 1 else -1, 0)
					if out.length() < 0.00001 and (i == 0) and y1 < y0:
						nrm = -nrm
				nrm = nrm.normalized()
				if out.length() > 0.00001 and nrm.dot(out) < 0.0:
					nrm = -nrm
				var th := a0 + (a1 - a0) * float(s) / seg
				var uv := Vector2((th - a0) * ravg, vacc[i])
				var uv2 := Vector2(float(s) / seg, (r[0] - y0) / span)
				var col := Color((mat + 0.5) / 8.0, flags, emb, 1.0)
				row_idx.append(vert(p, nrm, uv, uv2, col, wfn.call(p, uv2.y)))
			idx.append(row_idx)
		for i in nr - 1:
			for s in seg:
				var s2: int = (s + 1) % cols if full else s + 1
				var a: int = idx[i][s]
				var b: int = idx[i][s2]
				var c: int = idx[i + 1][s]
				var d: int = idx[i + 1][s2]
				_tri(P[i][s], P[i][s2], P[i + 1][s], a, b, c, (P[i][s] - C[i]))
				_tri(P[i][s2], P[i + 1][s2], P[i + 1][s], b, d, c, (P[i][s2] - C[i]))

	var _pending := []
	func _tri(pa: Vector3, pb: Vector3, pc: Vector3, a: int, b: int, c: int, outward: Vector3) -> void:
		var face := (pb - pa).cross(pc - pa)
		if face.length() < 1e-10:
			return
		# Godot front faces are clockwise: face normal must point away from the outward side.
		if face.dot(outward) > 0.0:
			_pending.append_array([a, c, b])
		else:
			_pending.append_array([a, b, c])

	func commit() -> ArrayMesh:
		for i in _pending:
			st.add_index(i)
		return st.commit()

# weight helpers
static func _w(b: String) -> Callable:
	var i := bi(b)
	return func(_p, _t): return {i: 1.0}

static func _wy(lo_bone: String, hi_bone: String, y0: float, y1: float) -> Callable:
	var a := bi(lo_bone)
	var b := bi(hi_bone)
	return func(p: Vector3, _t):
		var k := smoothstep(y0, y1, p.y)
		return {a: 1.0 - k, b: k}

# ---------------------------------------------------------------- body parts
static func build_mesh(g: Dictionary) -> ArrayMesh:
	var b := Body.new()
	var armor: String = g["armor"]
	var heavy := armor in ["plate", "ornate"]
	var base_mat := QUILT
	match armor:
		"leather": base_mat = LEATHER
		"chain", "plate", "ornate": base_mat = CHAIN
	_torso(b, base_mat)
	_neck_head(b, g)
	for side in [1, -1]:
		_leg(b, side, g, base_mat, heavy)
		_arm(b, side, g, base_mat, heavy)
	match armor:
		"quilted":
			_skirt(b, QUILT, 0.74)
		"leather":
			_jerkin(b)
			_skirt(b, LEATHER, 0.76)
		"chain":
			_skirt(b, CHAIN, 0.7)
			_tabard(b)
		"plate", "ornate":
			_skirt(b, CHAIN, 0.74)
			_cuirass(b, armor == "ornate")
			_faulds(b)
			_tabard(b, true)
	if g.get("belt", true):
		_belt(b, g)
	if g["cape"] != null:
		_cape(b)
	return b.commit()

static func _torso(b: Body, mat: int) -> void:
	var rings := [
		[0.8, 0.0, 0.005, 0.1, 0.085], [0.86, 0.0, 0.0, 0.15, 0.11], [0.95, 0.0, 0.0, 0.172, 0.123],
		[1.05, 0.0, -0.004, 0.162, 0.116], [1.15, 0.0, -0.008, 0.16, 0.114], [1.27, 0.0, -0.012, 0.183, 0.124],
		[1.38, 0.0, -0.012, 0.2, 0.128], [1.46, 0.0, -0.004, 0.195, 0.122], [1.53, 0.0, 0.002, 0.155, 0.108],
		[1.58, 0.0, 0.006, 0.075, 0.068], [1.63, 0.0, 0.01, 0.052, 0.052],
	]
	var hips := bi("hips")
	var torso := bi("torso")
	var shr := bi("sh_r")
	var shl := bi("sh_l")
	var head := bi("head")
	b.sweep(rings, 28, -PI * 1.5, PI * 0.5, mat, 0.0, 0.0, func(p: Vector3, _t):
		var k := smoothstep(0.98, 1.13, p.y)
		var w := {hips: 1.0 - k, torso: k}
		if p.y > 1.38 and absf(p.x) > 0.12:
			var s := smoothstep(0.12, 0.2, absf(p.x)) * smoothstep(1.38, 1.5, p.y) * 0.45
			w[shr if p.x > 0 else shl] = s
			w[torso] = k * (1.0 - s)
		if p.y > 1.6:
			w[head] = smoothstep(1.6, 1.64, p.y) * 0.5
		return w)

static func _neck_head(b: Body, g: Dictionary) -> void:
	var torso := bi("torso")
	var head := bi("head")
	b.sweep([[1.57, 0.0, 0.008, 0.058, 0.056], [1.62, 0.0, 0.008, 0.052, 0.05], [1.67, 0.0, 0.006, 0.05, 0.05]], 14, -PI * 1.5, PI * 0.5, SKIN, 0.0, 0.0, _wy("torso", "head", 1.6, 1.66))
	var face := [
		[1.612, 0.0, -0.034, 0.03, 0.025], [1.63, 0.0, -0.028, 0.055, 0.05], [1.66, 0.0, -0.012, 0.072, 0.078],
		[1.70, 0.0, 0.0, 0.08, 0.094, 0.06, 26.0], [1.73, 0.0, 0.004, 0.084, 0.099, 0.14, 40.0], [1.755, 0.0, 0.006, 0.088, 0.1, 0.05, 30.0],
		[1.785, 0.0, 0.008, 0.092, 0.104], [1.82, 0.0, 0.01, 0.089, 0.1], [1.855, 0.0, 0.012, 0.072, 0.082],
		[1.878, 0.0, 0.012, 0.04, 0.046], [1.888, 0.0, 0.012, 0.006, 0.006],
	]
	b.sweep(face, 26, -PI * 1.5, PI * 0.5, SKIN, 1.0, 1.0, _w("head"))
	if g.get("coif", false):
		b.sweep([[1.57, 0.0, 0.01, 0.078, 0.076], [1.62, 0.0, 0.01, 0.082, 0.082], [1.655, 0.0, 0.0, 0.088, 0.098]], 20, -PI * 1.5, PI * 0.5, CHAIN, 0.0, 0.0, _wy("torso", "head", 1.6, 1.66))
		b.sweep([[1.655, 0.0, 0.0, 0.088, 0.098], [1.72, 0.0, 0.006, 0.094, 0.106], [1.8, 0.0, 0.01, 0.1, 0.112]], 20, -PI * 0.5 + 0.75, PI * 1.5 - 0.75, CHAIN, 0.0, 0.0, _w("head"))
		b.sweep([[1.8, 0.0, 0.01, 0.1, 0.112], [1.85, 0.0, 0.012, 0.085, 0.095], [1.885, 0.0, 0.012, 0.05, 0.056], [1.9, 0.0, 0.012, 0.004, 0.004]], 20, -PI * 1.5, PI * 0.5, CHAIN, 0.0, 0.0, _w("head"))
	else:
		# hair: covers the cranium and back of the head, leaving the face clear
		b.sweep([[1.7, 0.0, 0.014, 0.088, 0.102], [1.76, 0.0, 0.012, 0.094, 0.108], [1.8, 0.0, 0.012, 0.098, 0.11]], 20, -PI * 0.5 + 0.95, PI * 1.5 - 0.95, HAIR, 0.0, 0.0, _w("head"))
		b.sweep([[1.8, 0.0, 0.012, 0.098, 0.11], [1.835, 0.0, 0.012, 0.094, 0.106], [1.865, 0.0, 0.013, 0.076, 0.088], [1.888, 0.0, 0.013, 0.045, 0.05], [1.9, 0.0, 0.013, 0.004, 0.004]], 22, -PI * 1.5, PI * 0.5, HAIR, 0.0, 0.0, _w("head"))
	# beard around the jaw
	b.sweep([[1.598, 0.0, -0.046, 0.026, 0.024], [1.615, 0.0, -0.04, 0.05, 0.048], [1.64, 0.0, -0.026, 0.068, 0.066], [1.665, 0.0, -0.013, 0.077, 0.082], [1.685, 0.0, -0.006, 0.08, 0.088]], 18, -PI * 0.5 - 1.25, -PI * 0.5 + 1.25, HAIR, 0.0, 1.0, _w("head"))
	# moustache
	b.sweep([[1.672, 0.0, -0.006, 0.07, 0.096], [1.684, 0.0, -0.006, 0.072, 0.098]], 10, -PI * 0.5 - 0.42, -PI * 0.5 + 0.42, HAIR, 0.0, 1.0, _w("head"))

static func _leg(b: Body, side: int, g: Dictionary, mat: int, heavy: bool) -> void:
	var leg := bi("leg_r" if side == 1 else "leg_l")
	var knee := bi("knee_r" if side == 1 else "knee_l")
	var hips := bi("hips")
	var x0 := side * 0.1
	var thigh := []
	for r in [[0.95, 0.09, 0.096], [0.88, 0.089, 0.095], [0.76, 0.081, 0.088], [0.62, 0.07, 0.075], [0.52, 0.061, 0.064], [0.47, 0.057, 0.059]]:
		thigh.append([r[0], x0 - side * (0.95 - r[0]) * 0.02, 0.0, r[1], r[2]])
	b.sweep(thigh, 16, -PI * 1.5, PI * 0.5, mat, 0.0, 0.0, func(p: Vector3, _t):
		var top := smoothstep(0.86, 0.95, p.y) * 0.45
		var low := 1.0 - smoothstep(0.46, 0.54, p.y)
		return {hips: top, leg: (1.0 - top) * (1.0 - low * 0.5), knee: low * 0.5})
	var xk := x0 - side * 0.0096
	var shin := [[0.475, xk, 0.0, 0.057, 0.059], [0.41, xk, 0.009, 0.054, 0.063], [0.31, xk, 0.016, 0.056, 0.067], [0.21, xk, 0.006, 0.046, 0.051], [0.12, xk, 0.002, 0.04, 0.042], [0.08, xk, 0.0, 0.042, 0.046]]
	b.sweep(shin, 16, -PI * 1.5, PI * 0.5, mat, 0.0, 0.0, func(p: Vector3, _t):
		var top := smoothstep(0.42, 0.48, p.y) * 0.5
		return {leg: top, knee: 1.0 - top})
	var boots: String = g.get("boots", "")
	if boots == "":
		boots = "greaves" if heavy else "boots"
	var bmat := STEEL if boots == "greaves" else LEATHER
	var bflag := 1.0 if boots == "greaves" else 0.5
	var shaft := [[0.34 if boots == "greaves" else 0.3, xk, 0.012, 0.06, 0.068], [0.22, xk, 0.008, 0.052, 0.058], [0.12, xk, 0.002, 0.048, 0.05], [0.06, xk, 0.0, 0.05, 0.056]]
	if boots == "greaves":
		shaft.push_front([0.44, xk, 0.004, 0.058, 0.062])
	b.sweep(shaft, 16, -PI * 1.5, PI * 0.5, bmat, bflag, 0.0, _w("knee_r" if side == 1 else "knee_l"))
	# foot, swept from heel to toe
	var foot := [[-0.075, 0.0, 0.05, 0.02, 0.025], [-0.06, 0.0, 0.05, 0.045, 0.045], [0.0, 0.0, 0.048, 0.05, 0.048], [0.08, 0.0, 0.038, 0.052, 0.038], [0.15, 0.0, 0.03, 0.047, 0.03], [0.2, 0.0, 0.025, 0.035, 0.024], [0.215, 0.0, 0.024, 0.012, 0.01]]
	var fx := Transform3D(Basis(Vector3.RIGHT, -PI * 0.5), Vector3(xk, 0.0, 0.0))
	b.sweep(foot, 14, -PI * 1.5, PI * 0.5, bmat, bflag, 0.0, _w("knee_r" if side == 1 else "knee_l"), fx)
	if heavy:
		# poleyn (knee cop) and cuisse (thigh plate)
		b.sweep([[0.55, xk, -0.01, 0.045, 0.045], [0.5, xk, -0.012, 0.066, 0.07], [0.45, xk, -0.012, 0.064, 0.068], [0.41, xk, -0.008, 0.045, 0.046]], 12, -PI * 0.5 - 1.3, -PI * 0.5 + 1.3, STEEL, 1.0, 0.0, func(p: Vector3, _t): return {leg: 0.5, knee: 0.5})
		b.sweep([[0.88, x0 - side * 0.0, -0.002, 0.09, 0.094], [0.72, x0 - side * 0.0045, -0.002, 0.082, 0.087], [0.56, x0 - side * 0.0078, -0.004, 0.068, 0.072]], 12, -PI * 0.5 - 1.5, -PI * 0.5 + 1.5, STEEL, 1.0, 0.0, func(p: Vector3, _t):
			var top := smoothstep(0.84, 0.9, p.y) * 0.3
			return {hips: top, leg: 1.0 - top})

static func _arm(b: Body, side: int, g: Dictionary, mat: int, heavy: bool) -> void:
	var sh := bi("sh_r" if side == 1 else "sh_l")
	var el := bi("el_r" if side == 1 else "el_l")
	var hand := bi("hand_r" if side == 1 else "hand_l")
	var torso := bi("torso")
	var x := side * 0.235
	var upper := [[1.575, x, 0.0, 0.012, 0.012], [1.56, x, 0.0, 0.045, 0.045], [1.535, x, 0.0, 0.066, 0.066], [1.49, x, 0.0, 0.071, 0.069], [1.41, x, 0.0, 0.068, 0.065], [1.32, x, 0.0, 0.061, 0.059], [1.24, x, 0.0, 0.053, 0.053], [1.2, x, 0.0, 0.05, 0.05]]
	upper.reverse()
	b.sweep(upper, 14, -PI * 1.5, PI * 0.5, mat, 0.0, 0.0, func(p: Vector3, _t):
		var top := smoothstep(1.47, 1.57, p.y) * 0.35
		var low := 1.0 - smoothstep(1.19, 1.26, p.y)
		return {torso: top, sh: (1.0 - top) * (1.0 - low * 0.5), el: low * 0.5})
	var fore := [[0.955, x, 0.0, 0.034, 0.034], [0.99, x, 0.0, 0.037, 0.038], [1.06, x, 0.0, 0.048, 0.048], [1.15, x, 0.0, 0.053, 0.053], [1.215, x, 0.0, 0.051, 0.051]]
	b.sweep(fore, 14, -PI * 1.5, PI * 0.5, mat, 0.0, 0.0, func(p: Vector3, _t):
		var top := smoothstep(1.18, 1.23, p.y) * 0.5
		var low := 1.0 - smoothstep(0.95, 0.99, p.y)
		return {sh: top, el: (1.0 - top) * (1.0 - low * 0.6), hand: low * 0.6})
	var gloves: String = g.get("gloves", "")
	if gloves == "":
		gloves = "gauntlets" if heavy else "gloves"
	var gmat := STEEL if gloves == "gauntlets" else LEATHER
	var gflag := 1.0 if gloves == "gauntlets" else 0.5
	# cuff
	b.sweep([[0.95, x, 0.0, 0.04, 0.042], [0.985, x, 0.0, 0.046, 0.048], [1.04 if gloves == "gauntlets" else 1.01, x, 0.0, 0.052 if gloves == "gauntlets" else 0.046, 0.054 if gloves == "gauntlets" else 0.048]], 14, -PI * 1.5, PI * 0.5, gmat, gflag, 0.0, func(p: Vector3, _t):
		var low := 1.0 - smoothstep(0.95, 0.99, p.y)
		return {el: 1.0 - low * 0.6, hand: low * 0.6})
	# hand (palm faces the body: thin in X)
	var hx := x
	var hnd := [[0.83, hx, -0.004, 0.006, 0.01], [0.84, hx, -0.004, 0.019, 0.033], [0.865, hx, -0.002, 0.024, 0.044], [0.9, hx, 0.0, 0.026, 0.047], [0.93, hx, 0.002, 0.025, 0.043], [0.955, hx, 0.002, 0.03, 0.034]]
	b.sweep(hnd, 14, -PI * 1.5, PI * 0.5, gmat, gflag * 0.5, 0.0, _w("hand_r" if side == 1 else "hand_l"))
	var thumb := [[0.0, 0.0, 0.0, 0.013, 0.014], [0.03, 0.0, 0.0, 0.012, 0.012], [0.055, 0.0, 0.0, 0.009, 0.009], [0.062, 0.0, 0.0, 0.002, 0.002]]
	var tb := Basis(Vector3.RIGHT, -PI * 0.75)
	tb = Basis(Vector3.UP, side * 0.35) * tb
	b.sweep(thumb, 8, -PI * 1.5, PI * 0.5, gmat, 0.0, 0.0, _w("hand_r" if side == 1 else "hand_l"), Transform3D(tb, Vector3(hx - side * 0.012, 0.925, -0.03)))
	if heavy:
		b.sweep([[1.45, x, 0.0, 0.068, 0.067], [1.35, x, 0.0, 0.065, 0.064], [1.26, x, 0.0, 0.058, 0.058]], 14, -PI * 1.5, PI * 0.5, STEEL, 1.0, 0.0, _w("sh_r" if side == 1 else "sh_l"))
		b.sweep([[1.16, x, 0.0, 0.056, 0.056], [1.08, x, 0.0, 0.052, 0.052], [1.0, x, 0.0, 0.046, 0.046]], 14, -PI * 1.5, PI * 0.5, STEEL, 1.0, 0.0, _w("el_r" if side == 1 else "el_l"))
		# couter (elbow cop) points backwards (+Z)
		b.sweep([[1.25, x, 0.012, 0.03, 0.03], [1.225, x, 0.012, 0.062, 0.064], [1.19, x, 0.012, 0.06, 0.062], [1.165, x, 0.01, 0.035, 0.036]], 10, PI * 0.5 - 1.3, PI * 0.5 + 1.3, STEEL, 1.0, 0.0, func(p: Vector3, _t): return {sh: 0.5, el: 0.5})
	# pauldrons
	var outer := 0.0 if side == 1 else PI
	if heavy or g["armor"] == "leather" or g["armor"] == "chain":
		var lames := 3 if heavy else 1
		var pm := STEEL if heavy else (LEATHER if g["armor"] == "leather" else CHAIN)
		for k in lames:
			var dy := -k * 0.042
			var rr := 0.012 * k
			var big := 1.0 if heavy else 0.85
			var rings := [[1.595 + dy, x - side * 0.01, 0.0, 0.03 * big, 0.035 * big], [1.58 + dy, x - side * 0.004, 0.0, (0.07 + rr) * big, (0.08 + rr) * big], [1.54 + dy, x + side * 0.006, 0.0, (0.088 + rr) * big, (0.098 + rr) * big], [1.47 + dy, x + side * 0.014, 0.0, (0.094 + rr) * big, (0.104 + rr) * big]]
			rings.reverse()
			b.sweep(rings, 16, outer - 1.95, outer + 1.95, pm, 1.0 if heavy else 0.5, 0.0, func(p: Vector3, _t): return {sh: 0.7, torso: 0.3})

static func _skirt(b: Body, mat: int, bottom: float) -> void:
	var hips := bi("hips")
	var lr := bi("leg_r")
	var ll := bi("leg_l")
	var rings := [[bottom, 0.0, 0.025, 0.215, 0.175], [0.8, 0.0, 0.015, 0.195, 0.15], [0.9, 0.0, 0.005, 0.18, 0.13], [1.0, 0.0, 0.0, 0.17, 0.124]]
	b.sweep(rings, 30, -PI * 1.5, PI * 0.5, mat, 0.0, 0.0, func(p: Vector3, _t):
		var k := 1.0 - smoothstep(bottom, 0.9, p.y)
		var side := smoothstep(-0.06, 0.06, p.x)
		return {hips: 1.0 - k * 0.55, lr: k * 0.55 * side, ll: k * 0.55 * (1.0 - side)})

static func _jerkin(b: Body) -> void:
	var rings := [[1.0, 0.0, -0.002, 0.172, 0.126], [1.1, 0.0, -0.008, 0.168, 0.122], [1.27, 0.0, -0.012, 0.19, 0.131], [1.38, 0.0, -0.012, 0.207, 0.135], [1.47, 0.0, -0.004, 0.2, 0.128], [1.53, 0.0, 0.002, 0.16, 0.114]]
	b.sweep(rings, 28, -PI * 1.5, PI * 0.5, LEATHER, 0.5, 1.0, _wy("hips", "torso", 1.0, 1.12))

static func _cuirass(b: Body, ornate: bool) -> void:
	var rings := [[1.04, 0.0, -0.004, 0.176, 0.13], [1.12, 0.0, -0.01, 0.172, 0.128, 0.04, 8.0], [1.26, 0.0, -0.014, 0.195, 0.138, 0.07, 8.0], [1.37, 0.0, -0.014, 0.214, 0.144, 0.07, 8.0], [1.46, 0.0, -0.006, 0.208, 0.136, 0.04, 8.0], [1.525, 0.0, 0.0, 0.17, 0.122], [1.55, 0.0, 0.004, 0.11, 0.094]]
	b.sweep(rings, 32, -PI * 1.5, PI * 0.5, STEEL, 1.0, 0.0, _wy("hips", "torso", 1.02, 1.12))
	if ornate:
		for y in [1.2, 1.44]:
			b.sweep([[y - 0.012, 0.0, -0.012, 0.2 if y > 1.3 else 0.186, 0.142 if y > 1.3 else 0.136], [y + 0.012, 0.0, -0.012, 0.2 if y > 1.3 else 0.186, 0.142 if y > 1.3 else 0.136]], 32, -PI * 1.5, PI * 0.5, GOLD, 0.0, 0.0, _w("torso"))

static func _faulds(b: Body) -> void:
	for k in 3:
		var yt := 1.03 - k * 0.055
		b.sweep([[yt - 0.075, 0.0, 0.006, 0.19 + k * 0.012, 0.142 + k * 0.012], [yt, 0.0, 0.0, 0.178 + k * 0.01, 0.13 + k * 0.01]], 30, -PI * 1.5, PI * 0.5, STEEL, 1.0, 0.0, _w("hips"))

static func _tabard(b: Body, short := false) -> void:
	var hips := bi("hips")
	var torso := bi("torso")
	var lr := bi("leg_r")
	var ll := bi("leg_l")
	var bottom := 0.66 if not short else 0.7
	for panel in [0, 1]:
		var front: bool = panel == 0
		var cz := -1.0 if front else 1.0
		var extra := 0.022 if short else 0.0
		var rings := [[bottom, 0.0, 0.01 * cz, 0.225 + extra, 0.19 + extra], [0.86, 0.0, 0.004 * cz, 0.205 + extra, 0.16 + extra], [1.0, 0.0, 0.0, 0.19 + extra, 0.142 + extra], [1.15, 0.0, -0.006, 0.182 + extra, 0.14 + extra * 1.2], [1.3, 0.0, -0.012, 0.196 + extra, 0.138 + extra * 1.5], [1.42, 0.0, -0.01, 0.21 + extra, 0.142 + extra * 1.3], [1.5, 0.0, 0.0, 0.19 + extra, 0.13 + extra]]
		var c := -PI * 0.5 if front else PI * 0.5
		b.sweep(rings, 14, c - 0.72, c + 0.72, CLOTH, 0.0, 1.0 if front else 0.25, func(p: Vector3, _t):
			var top := smoothstep(1.05, 1.2, p.y)
			var low := 1.0 - smoothstep(bottom, 0.92, p.y)
			var side := smoothstep(-0.05, 0.05, p.x)
			var hw := (1.0 - top) * (1.0 - low * 0.6)
			return {torso: top, hips: hw, lr: (1.0 - top) * low * 0.6 * side, ll: (1.0 - top) * low * 0.6 * (1.0 - side)})

static func _belt(b: Body, g: Dictionary) -> void:
	var rings := [[0.985, 0.0, 0.0, 0.186, 0.14], [1.03, 0.0, -0.002, 0.184, 0.138]]
	if g["armor"] in ["plate", "ornate"]:
		rings = [[1.04, 0.0, -0.006, 0.188, 0.142], [1.075, 0.0, -0.008, 0.186, 0.14]]
	b.sweep(rings, 30, -PI * 1.5, PI * 0.5, LEATHER, 0.5, 0.0, _w("hips"))
	var yb: float = (rings[0][0] + rings[1][0]) * 0.5
	b.sweep([[yb - 0.028, 0.0, -0.148, 0.03, 0.01], [yb + 0.028, 0.0, -0.148, 0.03, 0.01]], 8, -PI * 1.5, PI * 0.5, GOLD, 0.0, 0.0, _w("hips"))

static func _cape(b: Body) -> void:
	var c1 := bi("cape1")
	var c2 := bi("cape2")
	var c3 := bi("cape3")
	var torso := bi("torso")
	var rings := [[0.42, 0.0, 0.1, 0.27, 0.2], [0.7, 0.0, 0.08, 0.25, 0.18], [1.0, 0.0, 0.05, 0.22, 0.16], [1.3, 0.0, 0.03, 0.215, 0.15], [1.47, 0.0, 0.02, 0.2, 0.14], [1.535, 0.0, 0.01, 0.15, 0.12]]
	b.sweep(rings, 18, PI * 0.5 - 1.25, PI * 0.5 + 1.25, CLOTH, 0.0, 0.5, func(p: Vector3, _t):
		var a := smoothstep(1.2, 1.5, p.y)
		var c := 1.0 - smoothstep(0.65, 1.0, p.y)
		var m := 1.0 - a - c
		return {torso: a * 0.6, c1: a * 0.4 + m * 0.5, c2: m * 0.5 + c * 0.4, c3: c * 0.6})

# ---------------------------------------------------------------- shader
const SHADER := """
shader_type spatial;
render_mode cull_disabled, diffuse_burley, specular_schlick_ggx;
uniform vec3 steel : source_color = vec3(0.62);
uniform vec3 gold : source_color = vec3(0.85, 0.66, 0.3);
uniform vec3 leather : source_color = vec3(0.3, 0.19, 0.11);
uniform vec3 cloth : source_color = vec3(0.42, 0.06, 0.05);
uniform vec3 cape : source_color = vec3(0.3, 0.05, 0.04);
uniform vec3 emblem : source_color = vec3(0.86, 0.82, 0.72);
uniform vec3 skin : source_color = vec3(0.78, 0.58, 0.47);
uniform vec3 hair : source_color = vec3(0.22, 0.14, 0.08);
uniform vec3 quilt : source_color = vec3(0.55, 0.47, 0.34);
uniform vec3 glow : source_color = vec3(0.0);
uniform float glow_amt = 0.0;
uniform float flash = 0.0;

float h21(vec2 p){ p = fract(p * vec2(123.34, 456.21)); p += dot(p, p + 45.32); return fract(p.x * p.y); }
float vn(vec2 p){ vec2 i = floor(p); vec2 f = fract(p); vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(h21(i), h21(i + vec2(1.0, 0.0)), u.x), mix(h21(i + vec2(0.0, 1.0)), h21(i + vec2(1.0, 1.0)), u.x), u.y); }
float fb(vec2 p){ float v = 0.0; float a = 0.5; for (int i = 0; i < 4; i++){ v += a * vn(p); p = p * 2.07 + 3.1; a *= 0.5; } return v; }

void fragment(){
	int id = int(floor(COLOR.r * 8.0));
	float flags = COLOR.g;
	float emb = COLOR.b;
	vec2 uv = UV;
	vec2 u2 = UV2;
	vec3 alb = vec3(0.5);
	float rough = 0.8;
	float metal = 0.0;
	float h = 0.0;
	float bump = 0.6;
	float n1 = fb(uv * 7.0);
	float n2 = vn(uv * 55.0);
	vec3 em = vec3(0.0);
	if (id == 1 || id == 5) {
		// steel plate (1) or gold trim (5)
		float brushed = vn(vec2(uv.x * 4.0, uv.y * 260.0));
		vec2 ru = vec2(uv.x * 0.8 + uv.y * 0.6, uv.y * 0.8 - uv.x * 0.6);
		float scratch = smoothstep(0.93, 1.0, vn(vec2(ru.x * 400.0, ru.y * 6.0))) * step(0.55, vn(uv * 9.0));
		float edge = flags > 0.75 ? max(1.0 - smoothstep(0.0, 0.12, u2.y), smoothstep(0.88, 1.0, u2.y)) : 0.0;
		float rivet = 0.0;
		if (edge > 0.2) {
			float band = u2.y < 0.5 ? 0.05 : 0.95;
			vec2 rc = vec2((fract(uv.x / 0.05) - 0.5) * 0.05, (u2.y - band) * 0.18);
			rivet = 1.0 - smoothstep(0.004, 0.0065, length(rc));
		}
		vec3 base = id == 1 ? steel : gold;
		alb = base * (0.68 + brushed * 0.22 + n1 * 0.22);
		alb = mix(alb, base * 1.25 + 0.05, edge * 0.45 + scratch * 0.5);
		alb *= mix(0.55, 1.0, smoothstep(0.25, 0.6, n1));
		rough = clamp(0.3 + n1 * 0.25 - edge * 0.12 - scratch * 0.1, 0.12, 0.8);
		metal = 0.92;
		h = rivet * 0.9 - scratch * 0.15 + (vn(uv * 18.0) - 0.5) * 0.12;
		if (id == 5) {
			float eng = sin(uv.x * 160.0 + sin(uv.y * 120.0) * 2.5);
			h += smoothstep(0.6, 1.0, eng) * 0.4;
			alb *= 0.85 + 0.25 * smoothstep(0.6, 1.0, eng);
			rough = 0.25;
		}
		em = glow * glow_amt * (edge * 1.6 + 0.15);
	} else if (id == 2) {
		// riveted chainmail
		vec2 c = uv * vec2(115.0, 140.0);
		c.x += step(1.0, mod(floor(c.y), 2.0)) * 0.5;
		vec2 f = fract(c) - 0.5;
		float d = length(f * vec2(1.0, 1.15));
		float ring = 1.0 - smoothstep(0.06, 0.16, abs(d - 0.3));
		float hole = 1.0 - smoothstep(0.16, 0.22, d);
		alb = steel * (0.35 + ring * 0.6) * (0.75 + n1 * 0.4);
		alb = mix(alb, vec3(0.02), hole * 0.85);
		rough = 0.42 + n1 * 0.2;
		metal = 0.85 * (1.0 - hole);
		h = ring * 0.8;
		bump = 0.45;
	} else if (id == 3) {
		// leather with stitching and studs
		alb = leather * (0.72 + n1 * 0.4) * (0.9 + n2 * 0.15);
		float creases = smoothstep(0.55, 0.75, vn(vec2(uv.x * 20.0, uv.y * 60.0)));
		alb *= 1.0 - creases * 0.25;
		float edge = max(1.0 - smoothstep(0.0, 0.08, u2.y), smoothstep(0.92, 1.0, u2.y));
		float stitch = step(0.5, fract(uv.x / 0.012)) * (1.0 - smoothstep(0.0, 0.012, abs(min(u2.y, 1.0 - u2.y) - 0.05)));
		alb = mix(alb, leather * 0.45, edge * 0.5 * step(0.4, flags));
		alb = mix(alb, vec3(0.75, 0.68, 0.52), stitch * step(0.4, flags) * 0.8);
		rough = 0.62 + n1 * 0.2;
		h = creases * 0.3 + stitch * 0.3;
		if (emb > 0.5) {
			vec2 sc = vec2((fract(uv.x / 0.06) - 0.5) * 0.06, (fract(uv.y / 0.06) - 0.5) * 0.06);
			float stud = 1.0 - smoothstep(0.005, 0.008, length(sc));
			alb = mix(alb, steel * 1.1, stud);
			metal = stud * 0.9;
			rough = mix(rough, 0.3, stud);
			h += stud;
		}
	} else if (id == 4) {
		// woven cloth: tabard (emb 1 front, 0.25 back) or cape (emb 0.5)
		float weave = sin(uv.x * 1100.0) * sin(uv.y * 1100.0);
		vec3 base = (emb > 0.4 && emb < 0.6) ? cape : cloth;
		alb = base * (0.75 + n1 * 0.35);
		float hem = smoothstep(0.0, 0.12, u2.y);
		float trim = (emb > 0.6 || emb < 0.4) ? max(1.0 - smoothstep(0.0, 0.05, u2.x), smoothstep(0.95, 1.0, u2.x)) : 0.0;
		trim = max(trim, (1.0 - smoothstep(0.03, 0.05, u2.y)) * step(0.1, emb) * step(emb, 0.4) * 0.0);
		alb = mix(alb, gold * 0.8, trim * 0.85);
		if (emb > 0.9) {
			// heraldic cross on the chest
			vec2 e = vec2(u2.x - 0.5, u2.y - 0.72);
			float cross = max(step(abs(e.x), 0.07) * step(abs(e.y), 0.2), step(abs(e.y - 0.05), 0.055) * step(abs(e.x), 0.2));
			float border = max(step(abs(e.x), 0.09) * step(abs(e.y), 0.22), step(abs(e.y - 0.05), 0.075) * step(abs(e.x), 0.22)) - cross;
			alb = mix(alb, emblem * (0.85 + n1 * 0.2), cross);
			alb = mix(alb, gold * 0.7, clamp(border, 0.0, 1.0));
		}
		alb *= mix(0.55, 1.0, hem);
		alb *= mix(1.0, 0.7, smoothstep(0.5, 0.8, fb(uv * 3.0)) * (1.0 - u2.y));
		rough = 0.92;
		h = weave * 0.15;
		bump = 0.3;
	} else if (id == 6) {
		// quilted gambeson
		float q = abs(fract((uv.x + uv.y) * 12.0) - 0.5) + abs(fract((uv.x - uv.y) * 12.0) - 0.5);
		float seam = 1.0 - smoothstep(0.0, 0.08, min(abs(fract((uv.x + uv.y) * 12.0) - 0.5), abs(fract((uv.x - uv.y) * 12.0) - 0.5)) - 0.0);
		seam = smoothstep(0.42, 0.5, max(abs(fract((uv.x + uv.y) * 12.0) - 0.5), abs(fract((uv.x - uv.y) * 12.0) - 0.5)));
		alb = quilt * (0.78 + n1 * 0.3) * (1.0 - seam * 0.35);
		rough = 0.92;
		h = (1.0 - seam) * 0.6;
	} else if (id == 7) {
		// hair and beard strands
		float s = vn(vec2(uv.x * 160.0, uv.y * 14.0));
		alb = hair * (0.55 + s * 0.7) * (0.85 + n1 * 0.3);
		rough = 0.55;
		h = s * 0.4;
		bump = 0.4;
	} else {
		// skin, with painted face features on the head (flags 1)
		alb = skin * (0.9 + n1 * 0.16);
		alb = mix(alb, skin * vec3(1.05, 0.82, 0.78), smoothstep(0.55, 0.8, vn(uv * 25.0)) * 0.25);
		rough = 0.55;
		if (flags > 0.5) {
			for (int k = 0; k < 2; k++) {
				float ex = 0.5 + (float(k) * 2.0 - 1.0) * 0.058;
				vec2 d = vec2((u2.x - ex) * 2.1, u2.y - 0.51);
				float socket = 1.0 - smoothstep(0.03, 0.06, length(d * vec2(1.0, 1.6)));
				float white = 1.0 - smoothstep(0.016, 0.022, length(d * vec2(1.0, 2.2)));
				float iris = 1.0 - smoothstep(0.007, 0.011, length(d));
				alb *= 1.0 - socket * 0.35;
				alb = mix(alb, vec3(0.85, 0.82, 0.78), white);
				alb = mix(alb, vec3(0.12, 0.09, 0.07), iris);
				vec2 bd = vec2((u2.x - ex) * 2.1, u2.y - 0.6 + abs(u2.x - ex) * 0.4);
				float brow = (1.0 - smoothstep(0.0, 0.012, abs(bd.y))) * step(abs(bd.x), 0.05);
				alb = mix(alb, hair * 0.8, brow);
				h += socket * -0.5 + white * 0.2;
			}
			float lips = (1.0 - smoothstep(0.0, 0.016, abs(u2.y - 0.2))) * step(abs(u2.x - 0.5), 0.035);
			alb = mix(alb, skin * vec3(0.8, 0.45, 0.42), lips * 0.6);
		}
		BACKLIGHT = skin * 0.15;
	}
	float hk = h * bump * 0.0025;
	vec3 dpdx = dFdx(VERTEX);
	vec3 dpdy = dFdy(VERTEX);
	float dhx = dFdx(hk);
	float dhy = dFdy(hk);
	vec3 r1 = cross(dpdy, NORMAL);
	vec3 r2 = cross(NORMAL, dpdx);
	float det = dot(dpdx, r1);
	vec3 grad = sign(det) * (dhx * r1 + dhy * r2);
	vec3 nb = normalize(abs(det) * NORMAL - grad);
	if (abs(det) > 1e-12) { NORMAL = nb; }
	ALBEDO = alb;
	ROUGHNESS = rough;
	METALLIC = metal;
	EMISSION = em + vec3(flash);
	RIM = 0.25;
	RIM_TINT = 0.6;
}
"""
