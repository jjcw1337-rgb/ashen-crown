class_name SkeletonModel
extends RefCounted
## High-detail skeleton archer (Crypt Warden) with fire and ice colorways.
## Joints match Models.humanoid so Anim drives it unchanged. Each joint's parts are baked
## into one mesh per variant, and every surface uses an object-space detail shader so the
## texturing stays locked to the bones while they animate.

const VARIANTS := {
	"archer": {"name": "Crypt Warden Archer", "bone": Color(0.74, 0.68, 0.54), "grime": Color(0.36, 0.28, 0.18), "eyes": Color(0.3, 0.95, 1.0),
		"cloak": Color(0.34, 0.25, 0.17), "cloak2": Color(0.2, 0.14, 0.09), "steel": Color(0.66, 0.66, 0.68), "rust": Color(0.36, 0.2, 0.1),
		"gold": Color(0.86, 0.66, 0.3), "leather": Color(0.3, 0.19, 0.11)},
	"archer_fire": {"name": "Ember Archer", "bone": Color(0.55, 0.45, 0.36), "grime": Color(0.08, 0.05, 0.03), "eyes": Color(1.0, 0.5, 0.08), "ember": Color(1.0, 0.42, 0.06),
		"cloak": Color(0.3, 0.06, 0.03), "cloak2": Color(0.08, 0.02, 0.01), "steel": Color(0.3, 0.27, 0.25), "rust": Color(0.12, 0.06, 0.03),
		"gold": Color(0.95, 0.5, 0.16), "leather": Color(0.16, 0.09, 0.05)},
	"archer_ice": {"name": "Frost Archer", "bone": Color(0.72, 0.78, 0.84), "grime": Color(0.45, 0.55, 0.65), "eyes": Color(0.55, 0.9, 1.0), "frost": Color(0.75, 0.92, 1.0),
		"cloak": Color(0.2, 0.27, 0.35), "cloak2": Color(0.1, 0.15, 0.22), "steel": Color(0.76, 0.84, 0.92), "rust": Color(0.55, 0.7, 0.85),
		"gold": Color(0.66, 0.82, 1.0), "leather": Color(0.2, 0.22, 0.28)},
	"king": {"name": "The Ashen King", "bone": Color(0.42, 0.36, 0.3), "grime": Color(0.06, 0.04, 0.03), "eyes": Color(1.0, 0.35, 0.05), "ember": Color(1.0, 0.38, 0.05),
		"cloak": Color(0.34, 0.03, 0.05), "cloak2": Color(0.1, 0.01, 0.02), "steel": Color(0.24, 0.22, 0.23), "rust": Color(0.1, 0.05, 0.03),
		"gold": Color(1.0, 0.72, 0.3), "leather": Color(0.12, 0.07, 0.04), "king": true, "weapon": "cinderbrand"},
}
const BONE := 0
const STEEL := 1
const GOLD := 2
const LEATHER := 3
const CLOTH := 4

static var _baked := {}
static var _mats := {}
static var _meshes := {}
static var _shader: Shader
static var _cloak_shader: Shader
static var thick := 1.45

# ---------------------------------------------------------------- materials
static func dm(mode: int, col: Color, col2: Color, v: Dictionary) -> ShaderMaterial:
	var glow: Color = v.get("ember", Color.BLACK)
	var frost := 0.75 if v.has("frost") else 0.0
	var key := "%d|%s|%s|%s|%.2f" % [mode, col.to_html(), col2.to_html(), glow.to_html(), frost]
	if _mats.has(key):
		return _mats[key]
	if _shader == null:
		_shader = Shader.new()
		_shader.code = DETAIL_SHADER
	var m := ShaderMaterial.new()
	m.shader = _shader
	m.set_shader_parameter("mode", mode)
	m.set_shader_parameter("col", col)
	m.set_shader_parameter("col2", col2)
	m.set_shader_parameter("glow", glow)
	m.set_shader_parameter("glow_amt", 1.0 if v.has("ember") and mode == BONE else 0.0)
	m.set_shader_parameter("frost", frost)
	_mats[key] = m
	return m

static func _bone_m(v: Dictionary) -> Material: return dm(BONE, v["bone"], v["grime"], v)
static func _teeth_m(v: Dictionary) -> Material: return dm(BONE, (v["bone"] as Color).lerp(Color(0.85, 0.78, 0.55), 0.3), v["grime"], v)
static func _steel_m(v: Dictionary) -> Material: return dm(STEEL, v["steel"], v["rust"], v)
static func _gold_m(v: Dictionary) -> Material: return dm(GOLD, v["gold"], (v["gold"] as Color).darkened(0.6), v)
static func _leather_m(v: Dictionary) -> Material: return dm(LEATHER, v["leather"], (v["leather"] as Color).darkened(0.4), v)
static func _dark() -> Material: return Mats.mat(Color(0.015, 0.012, 0.01), 1.0)

static func cloak_mat(v: Dictionary, wave: float, darken := 0.0) -> ShaderMaterial:
	var c: Color = (v["cloak"] as Color).darkened(darken)
	var key := "cloak%s%.2f" % [c.to_html(), wave]
	if _mats.has(key):
		return _mats[key]
	if _cloak_shader == null:
		_cloak_shader = Shader.new()
		_cloak_shader.code = CLOAK_SHADER
	var m := ShaderMaterial.new()
	m.shader = _cloak_shader
	m.set_shader_parameter("col", c)
	m.set_shader_parameter("col2", v["cloak2"])
	m.set_shader_parameter("wave", wave)
	m.set_shader_parameter("ember", v.get("ember", Color.BLACK))
	m.set_shader_parameter("frost", 0.4 if v.has("frost") else 0.0)
	_mats[key] = m
	return m

# ---------------------------------------------------------------- rig
static func build(variant: String, _weapon := "") -> Node3D:
	if not VARIANTS.has(variant):
		variant = "archer"
	var v: Dictionary = VARIANTS[variant]
	var root := Node3D.new()
	root.name = "Rig"
	var J := {}
	var hips := Models.N(root, "hips", Vector3(0, 0.95, 0))
	J["hips"] = hips
	J["hips_y"] = 0.95
	var torso := Models.N(hips, "torso", Vector3(0, 0.08, 0))
	J["torso"] = torso
	var head := Models.N(torso, "head", Vector3(0, 0.62, 0))
	head.scale = Vector3.ONE * 1.16
	J["head"] = head
	for side in [1, -1]:
		var sn := "r" if side == 1 else "l"
		var sh := Models.N(torso, "sh_" + sn, Vector3(side * 0.185, 0.47, -0.005))
		var el := Models.N(sh, "el_" + sn, Vector3(0, -0.29, 0))
		var hand := Models.N(el, "hand_" + sn, Vector3(0, -0.27, 0))
		J["sh_" + sn] = sh
		J["el_" + sn] = el
		J["hand_" + sn] = hand
		var leg := Models.N(hips, "leg_" + sn, Vector3(side * 0.098, -0.04, 0))
		var knee := Models.N(leg, "knee_" + sn, Vector3(0, -0.45, 0))
		J["leg_" + sn] = leg
		J["knee_" + sn] = knee
	J["grip_r"] = Models.N(J["hand_r"], "grip_r", Vector3(0, -0.05, 0), Vector3(-28, 0, 0))
	J["grip_l"] = Models.N(J["hand_l"], "grip_l", Vector3(0, -0.055, 0))
	J["mount_l"] = Models.N(J["el_l"], "mount_l", Vector3(-0.06, -0.14, 0), Vector3(0, 70, 0))
	J["jaw"] = Models.N(head, "jaw", Vector3(0, 0.04, -0.02))
	for part in ["hips", "torso", "head", "jaw", "sh_r", "sh_l", "el_r", "el_l", "hand_r", "hand_l", "leg_r", "leg_l", "knee_r", "knee_l"]:
		var mi := MeshInstance3D.new()
		mi.mesh = _part_mesh(variant, part)
		(J[part] as Node3D).add_child(mi)
	_cloth_and_fx(J, v)
	if v.has("weapon"):
		var w := Models.item_model(Items.make_unique(v["weapon"]))
		(J["grip_r"] as Node3D).add_child(w)
		J["weapon"] = w
		Props.fire(w, Vector3(0, 0, -0.55), 0.4, v["ember"], false, false, false)
	else:
		var lb := longbow(v)
		(J["grip_l"] as Node3D).add_child(lb)
		J["bow_l"] = lb
	root.set_meta("j", J)
	root.set_meta("h", 1.0)
	root.set_meta("pers", "skeleton")
	root.set_meta("skel_variant", variant)
	return root

static func _part_mesh(variant: String, part: String) -> Mesh:
	var key := variant + "|" + part
	if _baked.has(key):
		return _baked[key]
	var v: Dictionary = VARIANTS[variant]
	var n := Node3D.new()
	var side := 1.0 if part.ends_with("_r") else -1.0
	match part:
		"head":
			_skull(n, v)
			if v.get("king", false):
				_crown(n, v)
			else:
				_helm(n, v)
		"jaw": _jaw(n, v)
		"torso":
			_spine_ribs(n, v)
			if not v.get("king", false):
				_quiver(n, v)
		"hips":
			_pelvis(n, v)
			_belt_faulds(n, v)
		"sh_r", "sh_l":
			_humerus(n, v, side)
			_pauldron(n, v, side)
		"el_r", "el_l":
			_forearm(n, v)
			_bracer(n, v)
		"hand_r", "hand_l": _hand(n, v, side)
		"leg_r", "leg_l":
			_femur(n, v, side)
			_cuisse(n, v)
		"knee_r", "knee_l":
			_shin_foot(n, v)
			_greave_sabaton(n, v)
	var m := Props.bake(n, true)
	_baked[key] = m
	return m

# ---------------------------------------------------------------- mesh helpers
## Smooth long bone along +Y with flared ends (proximal/distal epiphyses).
static func long_mesh(L: float, r: float, prox: float, dist: float) -> Mesh:
	var key := "long%.3f_%.4f_%.2f_%.2f" % [L, r, prox, dist]
	if _meshes.has(key):
		return _meshes[key]
	var pts := [Vector2(0.0, 0.0)]
	var steps := 18
	for i in steps + 1:
		var t := float(i) / steps
		var rr := r * (1.0 + prox * exp(-t * 8.0) + dist * exp(-(1.0 - t) * 8.0)) * (1.0 + 0.05 * sin(t * PI))
		if i == 0 or i == steps:
			rr *= 0.8
		pts.append(Vector2(rr, t * L))
	pts.append(Vector2(0.0, L))
	var m := Geo.lathe(pts, 12, key)
	_meshes[key] = m
	return m

static func _long(n: Node3D, a: Vector3, b: Vector3, r: float, prox: float, dist: float, m: Material) -> MeshInstance3D:
	var mi := Models.P(n, long_mesh(a.distance_to(b), r * thick, prox, dist), m, a)
	Models.orient_y(mi, b - a)
	return mi

static func _sg(n: Node3D, a: Vector3, b: Vector3, r0: float, r1: float, m: Material, sides := 8) -> MeshInstance3D:
	return Models.seg(n, a, b, r0 * thick, r1 * thick, m, sides)

static func _ball(n: Node3D, p: Vector3, r: float, m: Material, scl := Vector3.ONE, seg := 12) -> MeshInstance3D:
	return Models.P(n, Geo.sph(r * (1.0 + (thick - 1.0) * 0.55), seg), m, p, Vector3.ZERO, scl)

## Curved armour band (fauld lames, sabaton lames). Centred on -Z, hanging down from y=0.
static func arc_plate(R: float, span: float, hgt: float, flare: float) -> Mesh:
	var key := "arc%.3f_%.2f_%.3f_%.3f" % [R, span, hgt, flare]
	if _meshes.has(key):
		return _meshes[key]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var cols := 14
	var grid := []
	for r in 3:
		var t := r / 2.0
		var row := []
		for c in cols + 1:
			var a := (float(c) / cols - 0.5) * span
			var rad := R + flare * t
			row.append(Vector3(rad * sin(a), -hgt * t, -rad * cos(a)))
		grid.append(row)
	for r in 2:
		for c in cols:
			var p00: Vector3 = grid[r][c]
			var p01: Vector3 = grid[r][c + 1]
			var p10: Vector3 = grid[r + 1][c]
			var p11: Vector3 = grid[r + 1][c + 1]
			var n0 := Vector3(p00.x, 0, p00.z).normalized()
			var n1 := Vector3(p01.x, 0, p01.z).normalized()
			Geo.tri(st, p00, p01, p11, n0, n1, n1)
			Geo.tri(st, p00, p11, p10, n0, n1, n0)
	var m := st.commit()
	_meshes[key] = m
	return m

## Draped cloth sheet with folds, a ragged hem and torn holes. Hangs down from y=0
## and wraps around radius R so the side edges curve toward -Z.
static func cloak_mesh(w: float, h: float, R: float, folds: float, seed_v: int, flare := 0.25) -> Mesh:
	var key := "cloak%.2f_%.2f_%.2f_%.1f_%d_%.2f" % [w, h, R, folds, seed_v, flare]
	if _meshes.has(key):
		return _meshes[key]
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_v
	var cols := 22
	var rows := 18
	var lens := []
	var ph := rng.randf() * TAU
	for c in cols + 1:
		lens.append(h * (0.8 + 0.2 * (0.5 + 0.5 * sin(c * 1.7 + ph)) * rng.randf_range(0.7, 1.0)))
	var P := []
	for r in rows + 1:
		var v := float(r) / rows
		var row := []
		for c in cols + 1:
			var u := float(c) / cols
			var a := (u - 0.5) * w / R
			var rad := R * (1.0 + v * flare)
			var p := Vector3(rad * sin(a), -v * lens[c], rad * (cos(a) - 1.0))
			p.z += sin(u * folds * TAU + ph) * 0.016 * (0.25 + v)
			p.z += sin(u * folds * 2.3 * TAU + ph * 2.0) * 0.006 * v
			row.append(p)
		P.append(row)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for r in rows + 1:
		for c in cols + 1:
			var pr: Vector3 = P[r][mini(c + 1, cols)] - P[r][maxi(c - 1, 0)]
			var pd: Vector3 = P[mini(r + 1, rows)][c] - P[maxi(r - 1, 0)][c]
			var nrm := pd.cross(pr).normalized()
			if nrm.z < 0.0:
				nrm = -nrm
			st.set_normal(nrm)
			st.set_uv(Vector2(float(c) / cols, float(r) / rows))
			st.add_vertex(P[r][c])
	for r in rows:
		var v := float(r) / rows
		for c in cols:
			if v > 0.5 and rng.randf() < (v - 0.5) * 0.14:
				continue
			var a := r * (cols + 1) + c
			var b := a + 1
			var cc := a + cols + 1
			var d := cc + 1
			for i in [a, b, d, a, d, cc]:
				st.add_index(i)
	var m := st.commit()
	_meshes[key] = m
	return m

# ---------------------------------------------------------------- anatomy
static func _skull(n: Node3D, v: Dictionary) -> void:
	var bm := _bone_m(v)
	var dk := _dark()
	Models.P(n, Geo.sph(0.094, 28), bm, Vector3(0, 0.1, 0.016), Vector3.ZERO, Vector3(0.86, 1.0, 1.12))
	Models.P(n, Geo.sph(0.068, 16), bm, Vector3(0, 0.085, 0.072))
	for s in [1, -1]:
		# brow ridge, socket rim, eye glow, cheekbone, zygomatic arch
		Models.P(n, Geo.cap(0.009, 0.058, 10), bm, Vector3(s * 0.034, 0.1, -0.08), Vector3(0, 0, 90 - s * 12))
		Models.P(n, Geo.torus(0.021, 0.027, 18, 6), bm, Vector3(s * 0.034, 0.078, -0.08), Vector3(90, 0, 0), Vector3(1.0, 0.6, 0.85))
		Models.P(n, Geo.sph(0.024, 12), dk, Vector3(s * 0.034, 0.078, -0.07), Vector3.ZERO, Vector3(1.0, 0.9, 0.6))
		Models.P(n, Geo.sph(0.0075, 8), Mats.glow(v["eyes"], 2.2), Vector3(s * 0.034, 0.077, -0.088))
		Models.P(n, Geo.sph(0.017, 10), bm, Vector3(s * 0.05, 0.058, -0.068), Vector3.ZERO, Vector3(1.2, 0.7, 0.9))
		Models.seg(n, Vector3(s * 0.058, 0.058, -0.064), Vector3(s * 0.085, 0.062, -0.006), 0.009, 0.008, bm, 8)
		Models.P(n, Geo.sph(0.013, 8), bm, Vector3(s * 0.082, 0.045, 0.012))
	# maxilla
	Models.P(n, Geo.sph(0.045, 16), bm, Vector3(0, 0.038, -0.06), Vector3.ZERO, Vector3(1.0, 0.55, 0.78))
	# nasal aperture (inverted heart)
	for s in [1, -1]:
		Models.P(n, Geo.sph(0.009, 8), dk, Vector3(s * 0.007, 0.056, -0.091), Vector3.ZERO, Vector3(0.8, 1.3, 0.6))
	Models.P(n, Geo.prism(0.016, 0.02, 0.01), dk, Vector3(0, 0.062, -0.092))
	# upper teeth along the arch
	var tm := _teeth_m(v)
	for i in 10:
		var a := lerpf(-0.95, 0.95, i / 9.0)
		Models.P(n, Geo.cap(0.0048, 0.017, 6), tm, Vector3(sin(a) * 0.04, 0.012, -0.05 - cos(a) * 0.04), Vector3(0, -rad_to_deg(a), 0), Vector3(1.0, 1.0, 0.8))
	# neck vertebrae
	for i in 3:
		var y := -0.02 - i * 0.03
		Models.P(n, Geo.cyl(0.016, 0.018, 0.022, 10), bm, Vector3(0, y, 0.02))
		Models.P(n, Geo.box(0.06, 0.008, 0.012), bm, Vector3(0, y, 0.025))

static func _jaw(n: Node3D, v: Dictionary) -> void:
	var bm := _bone_m(v)
	var pts := []
	for i in 13:
		var a := lerpf(-1.25, 1.25, i / 12.0)
		pts.append(Vector3(sin(a) * 0.046, -0.012 - cos(a) * 0.004, 0.02 - cos(a) * 0.066))
	for i in pts.size() - 1:
		Models.seg(n, pts[i], pts[i + 1], 0.011, 0.011, bm, 8)
	Models.P(n, Geo.sph(0.014, 8), bm, Vector3(0, -0.018, -0.047), Vector3.ZERO, Vector3(1.3, 0.8, 0.8))
	for s in [1, -1]:
		Models.seg(n, Vector3(s * 0.046, -0.012, 0.0), Vector3(s * 0.048, 0.03, 0.014), 0.01, 0.008, bm, 8)
		Models.P(n, Geo.sph(0.009, 8), bm, Vector3(s * 0.048, 0.032, 0.014))
	var tm := _teeth_m(v)
	for i in 9:
		var a := lerpf(-0.9, 0.9, i / 8.0)
		Models.P(n, Geo.cap(0.0045, 0.015, 6), tm, Vector3(sin(a) * 0.037, 0.0, 0.02 - cos(a) * 0.058), Vector3(0, -rad_to_deg(a), 0), Vector3(1.0, 1.0, 0.8))

static func _spine_ribs(n: Node3D, v: Dictionary) -> void:
	var bm := _bone_m(v)
	var cart := dm(BONE, (v["bone"] as Color).darkened(0.12), v["grime"], v)
	for i in 14:
		var y := 0.0 + i * 0.04
		Models.P(n, Geo.cyl(0.02, 0.022, 0.026, 10), bm, Vector3(0, y, 0.045), Vector3.ZERO, Vector3(thick * 0.8, 1.0, thick * 0.8))
		Models.P(n, Geo.box(0.011, 0.016, 0.034), bm, Vector3(0, y - 0.004, 0.074), Vector3(-28, 0, 0))
		Models.P(n, Geo.box(0.07, 0.008, 0.01), bm, Vector3(0, y, 0.05))
	for i in 7:
		var y := 0.46 - i * 0.046
		var w := 0.125 - absf(i - 2.5) * 0.008
		var reach := 1.0 if i < 5 else 0.62
		for s in [1, -1]:
			var prev := Vector3(s * 0.025, y, 0.05)
			for k in 12:
				var a := float(k + 1) / 12.0 * PI * reach
				var p := Vector3(s * w * sin(a), y - (1.0 - cos(a)) * 0.05, 0.05 - (1.0 - cos(a)) * 0.077)
				_sg(n, prev, p, 0.0068, 0.0068, cart if (k >= 10 and i < 5) else bm, 7)
				prev = p
	Models.P(n, Geo.box(0.034, 0.21, 0.014), bm, Vector3(0, 0.37, -0.1), Vector3(-6, 0, 0))
	Models.P(n, Geo.box(0.05, 0.05, 0.014), bm, Vector3(0, 0.48, -0.098))
	for s in [1, -1]:
		_sg(n, Vector3(s * 0.025, 0.475, -0.095), Vector3(s * 0.17, 0.49, -0.01), 0.0075, 0.0065, bm, 8)
		var sc := Models.P(n, Geo.extrude(PackedVector2Array([Vector2(0, 0), Vector2(0.08, 0.02), Vector2(0.06, -0.04), Vector2(0.02, -0.13)]), 0.01, "scap2"), bm, Vector3(s * 0.065, 0.47, 0.085))
		sc.scale = Vector3(s, 1, 1)
		sc.rotation_degrees = Vector3(10, s * 18, 0)

static func _pelvis(n: Node3D, v: Dictionary) -> void:
	var bm := _bone_m(v)
	for s in [1, -1]:
		var wing := Models.P(n, Geo.extrude(PackedVector2Array([Vector2(0, -0.06), Vector2(0.06, -0.02), Vector2(0.12, 0.05), Vector2(0.11, 0.1), Vector2(0.05, 0.09), Vector2(0.0, 0.03)]), 0.012, "ilium"), bm, Vector3(s * 0.02, -0.03, 0.03))
		wing.scale = Vector3(s * 0.8, 0.8, 1)
		wing.rotation_degrees = Vector3(0, s * 45, 0)
		Models.P(n, Geo.sph(0.03, 12), bm, Vector3(s * 0.098, -0.05, 0.0))
		_sg(n, Vector3(s * 0.085, -0.07, -0.01), Vector3(0.0, -0.085, -0.055), 0.009, 0.009, bm, 8)
	Models.P(n, Geo.extrude(PackedVector2Array([Vector2(-0.045, 0.05), Vector2(0.045, 0.05), Vector2(0.0, -0.09)]), 0.025, "sacrum"), bm, Vector3(0, 0.0, 0.055), Vector3(-15, 0, 0))
	for i in 3:
		Models.P(n, Geo.cyl(0.02, 0.022, 0.026, 10), bm, Vector3(0, 0.055 + i * 0.03, 0.045), Vector3.ZERO, Vector3(thick * 0.8, 1.0, thick * 0.8))

static func _humerus(n: Node3D, v: Dictionary, side: float) -> void:
	var bm := _bone_m(v)
	_ball(n, Vector3(side * 0.006, 0.0, 0.0), 0.028, bm)
	_long(n, Vector3(0, -0.01, 0), Vector3(0, -0.28, 0), 0.0115, 0.7, 0.9, bm)
	for k in [-1, 1]:
		_ball(n, Vector3(k * 0.012, -0.285, 0.0), 0.012, bm)

static func _forearm(n: Node3D, v: Dictionary) -> void:
	var bm := _bone_m(v)
	_ball(n, Vector3(0, -0.005, 0.014), 0.015, bm)
	_long(n, Vector3(0.009, -0.01, 0.0), Vector3(0.013, -0.26, -0.004), 0.0065, 0.6, 1.0, bm)
	_long(n, Vector3(-0.009, -0.01, 0.009), Vector3(-0.013, -0.26, 0.006), 0.0065, 1.0, 0.5, bm)

static func _hand(n: Node3D, v: Dictionary, side: float) -> void:
	var bm := _bone_m(v)
	_ball(n, Vector3(0, -0.012, 0), 0.015, bm, Vector3(1.0, 0.8, 1.4))
	for f in 4:
		var z := -0.023 + f * 0.0155
		var base := Vector3(0, -0.02, z * 0.8)
		var mid := Vector3(-side * 0.004, -0.066, z)
		var j1 := Vector3(-side * 0.014, -0.09, z - 0.004)
		var j2 := Vector3(-side * 0.026, -0.1, z - 0.006)
		var j3 := Vector3(-side * 0.034, -0.103, z - 0.007)
		_sg(n, base, mid, 0.0042, 0.0038, bm, 6)
		_sg(n, mid, j1, 0.0038, 0.0034, bm, 6)
		_sg(n, j1, j2, 0.0034, 0.003, bm, 6)
		_sg(n, j2, j3, 0.003, 0.0025, bm, 6)
		for p in [mid, j1, j2]:
			_ball(n, p, 0.0045, bm, Vector3.ONE, 6)
	_sg(n, Vector3(0, -0.02, -0.026), Vector3(-side * 0.02, -0.05, -0.042), 0.0048, 0.004, bm, 6)
	_sg(n, Vector3(-side * 0.02, -0.05, -0.042), Vector3(-side * 0.03, -0.072, -0.048), 0.004, 0.0034, bm, 6)

static func _femur(n: Node3D, v: Dictionary, side: float) -> void:
	var bm := _bone_m(v)
	_ball(n, Vector3(-side * 0.022, 0.006, 0.0), 0.028, bm)
	_sg(n, Vector3(-side * 0.02, 0.003, 0.0), Vector3(0.0, -0.035, 0.0), 0.01, 0.012, bm, 8)
	_ball(n, Vector3(side * 0.012, -0.02, 0.006), 0.014, bm)
	_long(n, Vector3(0, -0.02, 0), Vector3(0, -0.42, 0.004), 0.013, 0.6, 1.1, bm)
	for k in [-1, 1]:
		_ball(n, Vector3(k * 0.015, -0.44, 0.005), 0.016, bm)

static func _shin_foot(n: Node3D, v: Dictionary) -> void:
	var bm := _bone_m(v)
	_ball(n, Vector3(0, 0.0, -0.03), 0.014, bm, Vector3(1.0, 1.1, 0.6))
	_long(n, Vector3(0.0, -0.012, -0.004), Vector3(0.0, -0.4, -0.002), 0.011, 1.1, 0.7, bm)
	_long(n, Vector3(0.02, -0.025, 0.01), Vector3(0.019, -0.4, 0.007), 0.005, 0.8, 0.8, bm)

# ---------------------------------------------------------------- armour
static func _helm(n: Node3D, v: Dictionary) -> void:
	var st := _steel_m(v)
	var gd := _gold_m(v)
	Models.P(n, Geo.lathe([Vector2(0.104, 0.068), Vector2(0.107, 0.085), Vector2(0.108, 0.105), Vector2(0.104, 0.135), Vector2(0.092, 0.162), Vector2(0.072, 0.185), Vector2(0.045, 0.2), Vector2(0.018, 0.206), Vector2(0.0, 0.207)], 32, "helm_hd"), st, Vector3(0, 0.004, 0.014), Vector3.ZERO, Vector3(0.9, 1.0, 1.04))
	Models.P(n, Geo.torus(0.102, 0.114, 36, 6), gd, Vector3(0, 0.082, 0.014), Vector3.ZERO, Vector3(0.9, 1.25, 1.04))
	# crest and brow plate
	Models.P(n, Geo.box(0.008, 0.012, 0.19), st, Vector3(0, 0.208, 0.014), Vector3(-3, 0, 0))
	# nasal guard with gold edging and rivets
	var nasal := PackedVector2Array([Vector2(-0.011, 0.0), Vector2(0.011, 0.0), Vector2(0.008, -0.075), Vector2(0.0, -0.085), Vector2(-0.008, -0.075)])
	Models.P(n, Geo.extrude(nasal, 0.008, "nasal"), st, Vector3(0, 0.11, -0.103), Vector3(4, 0, 0))
	Models.P(n, Geo.extrude(nasal, 0.005, "nasal_g"), gd, Vector3(0, 0.112, -0.1), Vector3(4, 0, 0), Vector3(1.3, 1.05, 1.0))
	for k in 3:
		Models.P(n, Geo.sph(0.004, 6), gd, Vector3(0, 0.1 - k * 0.022, -0.108))
	# cheek guards
	var cheek := PackedVector2Array([Vector2(0, 0), Vector2(0.05, 0.0), Vector2(0.055, -0.04), Vector2(0.035, -0.075), Vector2(0.005, -0.06)])
	for s in [1, -1]:
		var cg := Models.P(n, Geo.extrude(cheek, 0.006, "cheek"), st, Vector3(s * 0.084, 0.088, -0.015), Vector3(0, s * 96, 0))
		cg.scale = Vector3(s, 1, 1)
		Models.P(n, Geo.sph(0.004, 6), gd, Vector3(s * 0.093, 0.07, -0.045))
	for i in 16:
		var a := TAU * i / 16.0
		Models.P(n, Geo.sph(0.0045, 6), gd, Vector3(cos(a) * 0.104, 0.082, 0.014 + sin(a) * 0.12))
	if v.has("frost"):
		var ice := Mats.mat(v["frost"], 0.05, 0.1, v["frost"], 0.5)
		for k in 5:
			Models.P(n, Geo.prism(0.012, 0.05, 0.012), ice, Vector3(-0.06 + k * 0.03, 0.17 - absf(k - 2) * 0.02, 0.05), Vector3(-20, 0, (k - 2) * 15))

## The Ashen King's crown: a spiked gold circlet set with burning gems.
static func _crown(n: Node3D, v: Dictionary) -> void:
	var gd := _gold_m(v)
	var gem := Mats.glow(v["eyes"], 3.0)
	Models.P(n, Geo.torus(0.084, 0.1, 40, 8), gd, Vector3(0, 0.15, 0.016), Vector3.ZERO, Vector3(0.92, 1.6, 1.08))
	Models.P(n, Geo.torus(0.086, 0.094, 40, 5), gd, Vector3(0, 0.128, 0.016), Vector3.ZERO, Vector3(0.94, 1.0, 1.1))
	for i in 10:
		var a := TAU * i / 10.0
		var p := Vector3(sin(a) * 0.088, 0.16, 0.016 - cos(a) * 0.098)
		var tall := 0.075 if i % 2 == 0 else 0.048
		if i == 0:
			tall = 0.1
		var sp := Models.P(n, Geo.cone(0.016, tall, 6), gd, p + Vector3(0, tall * 0.5, 0))
		sp.rotation = Vector3(cos(a) * 0.18, 0, sin(a) * 0.18)
		Models.P(n, Geo.sph(0.006, 6), gd, p + Vector3(0, tall + 0.002, 0))
		if i % 2 == 0:
			Models.P(n, Geo.sph(0.011, 8), gem, p + Vector3(sin(a) * 0.006, -0.01, -cos(a) * 0.006))

static func _pauldron(n: Node3D, v: Dictionary, side: float) -> void:
	var st := _steel_m(v)
	var gd := _gold_m(v)
	for k in 3:
		var dy := 0.03 - k * 0.032
		var dx := side * (0.012 + k * 0.014)
		var tilt := -side * (22 + k * 12)
		var sc := Vector3(1.0 - k * 0.06, 0.82 - k * 0.12, 1.1 - k * 0.04)
		Models.P(n, Geo.sph(0.078, 22, 0.5), st, Vector3(dx, dy, 0), Vector3(0, 0, tilt), sc)
		Models.P(n, Geo.torus(0.07, 0.081, 26, 5), gd, Vector3(dx, dy - 0.002, 0), Vector3(0, 0, tilt), Vector3(sc.x, 1.0, sc.z))
		for r in 5:
			var a := lerpf(-1.2, 1.2, r / 4.0)
			Models.P(n, Geo.sph(0.004, 5), gd, Vector3(dx + side * cos(a) * 0.012, dy + 0.01, sin(a) * 0.07))
	# embossed ridge on the top lame
	Models.P(n, Geo.torus(0.05, 0.056, 20, 4), st, Vector3(side * 0.012, 0.058, 0), Vector3(90, 0, -side * 22), Vector3(1.0, 1.0, 0.5))
	if v.has("frost"):
		var ice := Mats.mat(v["frost"], 0.05, 0.1, v["frost"], 0.5)
		for k in 4:
			Models.P(n, Geo.prism(0.016, 0.07, 0.016), ice, Vector3(side * (0.01 + k * 0.022), 0.08 - k * 0.012, -0.03 + k * 0.02), Vector3(0, 0, -side * (10 + k * 14)))

static func _bracer(n: Node3D, v: Dictionary) -> void:
	var st := _steel_m(v)
	var gd := _gold_m(v)
	var lt := _leather_m(v)
	Models.P(n, Geo.lathe([Vector2(0.0, -0.075), Vector2(0.026, -0.075), Vector2(0.029, -0.04), Vector2(0.032, 0.0), Vector2(0.033, 0.05), Vector2(0.032, 0.075), Vector2(0.0, 0.075)], 18, "bracer"), st, Vector3(0, -0.155, 0))
	Models.P(n, Geo.torus(0.03, 0.037, 20, 5), gd, Vector3(0, -0.082, 0))
	Models.P(n, Geo.torus(0.025, 0.032, 20, 5), gd, Vector3(0, -0.228, 0))
	for y in [-0.12, -0.19]:
		Models.P(n, Geo.torus(0.031, 0.036, 20, 4), lt, Vector3(0, y, 0), Vector3.ZERO, Vector3(1.0, 1.6, 1.0))
		Models.P(n, Geo.box(0.014, 0.014, 0.008), gd, Vector3(0.0, y, -0.036))

static func _cuisse(n: Node3D, v: Dictionary) -> void:
	var st := _steel_m(v)
	var gd := _gold_m(v)
	Models.P(n, Geo.lathe([Vector2(0.0, -0.37), Vector2(0.038, -0.37), Vector2(0.046, -0.3), Vector2(0.052, -0.2), Vector2(0.052, -0.14), Vector2(0.046, -0.11), Vector2(0.0, -0.11)], 18, "cuisse"), st, Vector3(0, 0, -0.006), Vector3.ZERO, Vector3(1.0, 1.0, 0.85))
	Models.P(n, Geo.torus(0.045, 0.053, 20, 4), gd, Vector3(0, -0.115, -0.006), Vector3.ZERO, Vector3(1.0, 1.0, 0.85))
	Models.P(n, Geo.torus(0.035, 0.043, 20, 4), gd, Vector3(0, -0.365, -0.006), Vector3.ZERO, Vector3(1.0, 1.0, 0.85))

static func _greave_sabaton(n: Node3D, v: Dictionary) -> void:
	var st := _steel_m(v)
	var gd := _gold_m(v)
	# poleyn (knee cop) with a side fan
	Models.P(n, Geo.sph(0.042, 18, 0.5), st, Vector3(0, 0.0, -0.032), Vector3(-90, 0, 0), Vector3(1.1, 1.0, 1.15))
	Models.P(n, Geo.torus(0.038, 0.046, 22, 5), gd, Vector3(0, 0.0, -0.034), Vector3(90, 0, 0), Vector3(1.1, 1.0, 1.15))
	var fan := PackedVector2Array([Vector2(0, 0.03), Vector2(0.03, 0.0), Vector2(0.035, -0.03), Vector2(0.0, -0.05), Vector2(-0.01, 0.0)])
	Models.P(n, Geo.extrude(fan, 0.006, "kneefan"), st, Vector3(0.045, 0.0, -0.012), Vector3(0, 90, 0))
	Models.P(n, Geo.sph(0.005, 6), gd, Vector3(0, 0.0, -0.078))
	# shaped greave
	Models.P(n, Geo.lathe([Vector2(0.0, -0.38), Vector2(0.035, -0.38), Vector2(0.04, -0.3), Vector2(0.047, -0.2), Vector2(0.046, -0.12), Vector2(0.041, -0.06), Vector2(0.0, -0.06)], 18, "greave_hd"), st)
	Models.P(n, Geo.box(0.008, 0.3, 0.006), gd, Vector3(0, -0.22, -0.047))
	Models.P(n, Geo.torus(0.04, 0.047, 20, 4), gd, Vector3(0, -0.065, 0.0))
	Models.P(n, Geo.torus(0.033, 0.04, 20, 4), gd, Vector3(0, -0.375, 0.0))
	# segmented sabaton
	Models.P(n, Geo.box(0.07, 0.04, 0.08), st, Vector3(0, -0.425, 0.005))
	for k in 4:
		Models.P(n, arc_plate(0.035, 2.4, 0.03, 0.006), st, Vector3(0, -0.405 - k * 0.006, -0.04 - k * 0.022), Vector3(-70, 0, 0))
	Models.P(n, Geo.sph(0.03, 12, 0.5), st, Vector3(0, -0.43, -0.12), Vector3(-90, 0, 0), Vector3(1.15, 1.0, 0.7))
	Models.P(n, Geo.box(0.072, 0.012, 0.012), gd, Vector3(0, -0.41, -0.035))

static func _belt_faulds(n: Node3D, v: Dictionary) -> void:
	var st := _steel_m(v)
	var gd := _gold_m(v)
	var lt := _leather_m(v)
	var bm := _bone_m(v)
	Models.P(n, Geo.torus(0.112, 0.132, 30, 6), lt, Vector3(0, 0.03, 0), Vector3.ZERO, Vector3(1.0, 1.4, 0.76))
	for i in 10:
		var a := TAU * i / 10.0
		Models.P(n, Geo.sph(0.006, 5), gd, Vector3(sin(a) * 0.131, 0.03, -cos(a) * 0.1))
	# skull buckle
	var b := Vector3(0, 0.028, -0.106)
	Models.P(n, Geo.sph(0.034, 14), bm, b, Vector3.ZERO, Vector3(0.9, 1.0, 0.8))
	for s in [1, -1]:
		Models.P(n, Geo.sph(0.009, 6), _dark(), b + Vector3(s * 0.012, 0.004, -0.024))
	Models.P(n, Geo.box(0.032, 0.012, 0.018), bm, b + Vector3(0, -0.028, -0.008))
	for i in 5:
		Models.P(n, Geo.box(0.004, 0.006, 0.004), _teeth_m(v), b + Vector3(-0.01 + i * 0.005, -0.02, -0.02))
	# three overlapping fauld lames across the front, plus side plates
	for k in 3:
		var y := 0.005 - k * 0.042
		Models.P(n, arc_plate(0.128 + k * 0.008, 1.15 - k * 0.12, 0.05, 0.012), st, Vector3(0, y, 0.01), Vector3(8 + k * 4, 0, 0))
		Models.P(n, arc_plate(0.131 + k * 0.008, 1.15 - k * 0.12, 0.006, 0.0), gd, Vector3(0, y - 0.046, 0.01), Vector3(8 + k * 4, 0, 0))
	for s in [1, -1]:
		Models.P(n, arc_plate(0.13, 0.55, 0.1, 0.03), st, Vector3(0, -0.005, 0), Vector3(8, s * 80, 0))
		Models.P(n, arc_plate(0.133, 0.55, 0.006, 0.0), gd, Vector3(0, -0.095, 0), Vector3(8, s * 80, 0))

static func _quiver(n: Node3D, v: Dictionary) -> void:
	var lt := _leather_m(v)
	var gd := _gold_m(v)
	var q := Models.N(n, "quiver", Vector3(0.075, 0.3, 0.12), Vector3(0, 0, -24))
	Models.P(q, Geo.lathe([Vector2(0.0, -0.21), Vector2(0.032, -0.21), Vector2(0.038, -0.1), Vector2(0.042, 0.1), Vector2(0.045, 0.2), Vector2(0.04, 0.21)], 14, "quiver"), lt)
	Models.P(q, Geo.torus(0.04, 0.049, 16, 4), gd, Vector3(0, 0.2, 0))
	Models.P(q, Geo.torus(0.034, 0.042, 16, 4), gd, Vector3(0, -0.18, 0))
	var shaft := Mats.mat(Color(0.42, 0.3, 0.18), 0.8)
	var vane := Mats.mat(Color(0.7, 0.66, 0.58), 0.9)
	for i in 7:
		var a := TAU * i / 7.0
		var p := Vector3(cos(a) * 0.022, 0.18, sin(a) * 0.022)
		var top := p + Vector3(cos(a) * 0.01, 0.15, sin(a) * 0.01)
		Models.seg(q, p, top, 0.0035, 0.0035, shaft, 5)
		for f in 2:
			Models.P(q, Geo.box(0.022, 0.05, 0.0015), vane, top - Vector3(0, 0.03, 0), Vector3(0, rad_to_deg(a) + f * 90, 0))
	Models.seg(n, Vector3(-0.13, 0.45, -0.088), Vector3(0.12, 0.1, -0.095), 0.011, 0.011, lt, 6)
	Models.seg(n, Vector3(0.12, 0.1, -0.095), Vector3(0.12, 0.12, 0.1), 0.011, 0.011, lt, 6)
	Models.P(n, Geo.box(0.022, 0.026, 0.008), gd, Vector3(0.0, 0.28, -0.1), Vector3(0, 0, 50))

## The longbow: tall tapered limbs, horn tips, wrapped grip, string. Limbs along local Y.
static func longbow(v: Dictionary) -> Node3D:
	var root := Node3D.new()
	var wood := dm(LEATHER, Color(0.36, 0.22, 0.12), Color(0.2, 0.12, 0.06), v)
	var wrap := _leather_m(v)
	var horn := Mats.mat(Color(0.82, 0.76, 0.62), 0.45)
	var pts := []
	for i in 21:
		var t := float(i) / 20.0
		var y := lerpf(-0.84, 0.88, t)
		var u := y / 0.86
		var z := -0.115 * (1.0 - u * u) + 0.055 * pow(absf(u), 7.0)
		pts.append(Vector3(0, y, z))
	for i in pts.size() - 1:
		var tt := float(i) / (pts.size() - 1)
		var r := lerpf(0.017, 0.009, absf(tt - 0.5) * 2.0)
		Models.seg(root, pts[i], pts[i + 1], r * 1.08, r, wood, 8)
	for k in 8:
		Models.P(root, Geo.torus(0.016, 0.022, 12, 4), wrap, Vector3(0, -0.07 + k * 0.02, -0.114))
	for e in [pts[0], pts[pts.size() - 1]]:
		Models.P(root, Geo.cone(0.012, 0.05, 8), horn, e + Vector3(0, signf(e.y) * 0.02, 0), Vector3(0 if e.y > 0 else 180, 0, 0))
	var s := Models.seg(root, pts[1], pts[pts.size() - 2], 0.0028, 0.0028, Mats.mat(Color(0.82, 0.78, 0.66), 0.7), 4)
	s.name = "string"
	root.position = Vector3(0, 0.0, 0.115)
	return root

# ---------------------------------------------------------------- cloth and effects
static func _cloth_and_fx(J: Dictionary, v: Dictionary) -> void:
	var torso: Node3D = J["torso"]
	var hips: Node3D = J["hips"]
	var head: Node3D = J["head"]
	var cm := cloak_mat(v, 0.7)
	var solid := dm(CLOTH, v["cloak"], v["cloak2"], v)
	# cowl: a draped capelet wrapped round the neck, a soft collar roll and the hood folded down the back
	Models.P(torso, Geo.torus(0.06, 0.105, 24, 8), solid, Vector3(0, 0.585, 0.015), Vector3(-12, 0, 0), Vector3(1.1, 0.55, 1.0))
	Models.P(torso, cloak_mesh(0.84, 0.19, 0.13, 7.0, 5, 0.45), cloak_mat(v, 0.15), Vector3(0, 0.6, -0.11), Vector3(4, 180, 0))
	Models.P(torso, Geo.sph(0.1, 16), solid, Vector3(0, 0.575, 0.12), Vector3(25, 0, 0), Vector3(1.1, 0.62, 0.55))
	for k in 3:
		Models.P(torso, Geo.torus(0.085 - k * 0.006, 0.1 - k * 0.006, 24, 5), solid, Vector3(0, 0.57 - k * 0.025, 0.14 + k * 0.012), Vector3(75, 0, 0), Vector3(0.95, 1.0, 0.45))
	# cloak from the shoulders down the back, with side panels; open at the front
	Models.P(torso, cloak_mesh(0.52, 1.1, 0.24, 4.0, 11, 0.3), cm, Vector3(0, 0.56, 0.155), Vector3(-7, 180, 0))
	for side in [1, -1]:
		Models.P(torso, cloak_mesh(0.2, 0.92, 0.3, 2.0, 20 + side, 0.15), cm, Vector3(side * 0.2, 0.55, 0.05), Vector3(-4, side * 65 + 180, side * 3))
	Models.P(torso, cloak_mesh(0.14, 0.44, 0.35, 2.0, 31, 0.2), cm, Vector3(-0.12, 0.54, -0.11), Vector3(6, -14, 0))
	# ragged loincloth under the faulds
	var rag := cloak_mat(v, 0.4, 0.12)
	Models.P(hips, cloak_mesh(0.22, 0.4, 0.4, 2.0, 41, 0.1), rag, Vector3(0, -0.12, -0.105), Vector3(4, 0, 0))
	Models.P(hips, cloak_mesh(0.26, 0.38, 0.4, 2.0, 42, 0.1), rag, Vector3(0, -0.03, 0.1), Vector3(-6, 180, 0))
	if v.has("ember"):
		var l := OmniLight3D.new()
		l.light_color = v["ember"]
		l.light_energy = 0.8
		l.omni_range = 2.6
		l.position = Vector3(0, 0.08, -0.16)
		head.add_child(l)
		if not v.get("king", false):
			Props.fire(head, Vector3(0, 0.21, 0.02), 0.24, v["ember"], false, false, true)
		var em := GPUParticles3D.new()
		em.amount = 16
		em.lifetime = 1.8
		em.local_coords = false
		var pm := ParticleProcessMaterial.new()
		pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
		pm.emission_box_extents = Vector3(0.15, 0.35, 0.1)
		pm.direction = Vector3(0, 1, 0)
		pm.spread = 20.0
		pm.initial_velocity_min = 0.1
		pm.initial_velocity_max = 0.4
		pm.gravity = Vector3(0, 0.5, 0)
		var g := Gradient.new()
		g.set_color(0, Color(1.0, 0.6, 0.2, 1.0))
		g.set_color(1, Color(1.0, 0.2, 0.0, 0.0))
		var gt := GradientTexture1D.new()
		gt.gradient = g
		pm.color_ramp = gt
		em.process_material = pm
		var q := QuadMesh.new()
		q.size = Vector2(0.03, 0.03)
		q.material = Mats.particle_mat(true, Color(3, 3, 3))
		em.draw_pass_1 = q
		em.position = Vector3(0, 0.3, 0)
		torso.add_child(em)
	if v.has("frost"):
		var l2 := OmniLight3D.new()
		l2.light_color = v["frost"]
		l2.light_energy = 0.6
		l2.omni_range = 2.4
		l2.position = Vector3(0, 0.08, -0.16)
		head.add_child(l2)

# ---------------------------------------------------------------- shaders
const DETAIL_SHADER := """
shader_type spatial;
render_mode cull_disabled, diffuse_burley, specular_schlick_ggx;
uniform int mode = 0;
uniform vec3 col : source_color = vec3(0.85, 0.8, 0.65);
uniform vec3 col2 : source_color = vec3(0.35, 0.28, 0.18);
uniform vec3 glow : source_color = vec3(0.0);
uniform float glow_amt = 0.0;
uniform float frost = 0.0;
varying vec3 lp;
varying vec3 ln;
float h31(vec3 p){ p = fract(p * 0.3183099 + 0.1); p *= 17.0; return fract(p.x * p.y * p.z * (p.x + p.y + p.z)); }
float vn3(vec3 x){ vec3 i = floor(x); vec3 f = fract(x); f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(h31(i), h31(i + vec3(1,0,0)), f.x), mix(h31(i + vec3(0,1,0)), h31(i + vec3(1,1,0)), f.x), f.y),
		mix(mix(h31(i + vec3(0,0,1)), h31(i + vec3(1,0,1)), f.x), mix(h31(i + vec3(0,1,1)), h31(i + vec3(1,1,1)), f.x), f.y), f.z); }
float fb3(vec3 p){ float v = 0.0; float a = 0.5; for (int i = 0; i < 4; i++){ v += a * vn3(p); p = p * 2.03 + 1.7; a *= 0.5; } return v; }
void vertex(){ lp = VERTEX; ln = NORMAL; }
void fragment(){
	vec3 p = lp;
	float n1 = fb3(p * 9.0);
	float n2 = vn3(p * 55.0);
	vec3 alb = col;
	float rough = 0.7;
	float metal = 0.0;
	float h = 0.0;
	vec3 em = vec3(0.0);
	if (mode == 0) {
		float pits = smoothstep(0.8, 0.9, vn3(p * 260.0));
		float crackn = abs(fb3(p * 14.0) - 0.5);
		float crack = (1.0 - smoothstep(0.0, 0.018, crackn)) * step(0.5, vn3(p * 4.0 + 7.0));
		alb = col * (0.84 + n1 * 0.24) * (0.94 + n2 * 0.1);
		alb = mix(alb, col * vec3(0.86, 0.76, 0.56), smoothstep(0.5, 0.78, fb3(p * 4.0)) * 0.45);
		alb = mix(alb, col2, smoothstep(0.58, 0.82, n1) * 0.4);
		alb *= 1.0 - pits * 0.25 - crack * 0.55;
		rough = 0.62 + n1 * 0.2;
		h = -pits * 0.7 - crack * 0.9 + n2 * 0.2;
		em = glow * glow_amt * (crack * 4.0 + pits * 0.6 + smoothstep(0.7, 0.9, n1) * 0.5);
		float fr = frost * smoothstep(0.25, 0.85, ln.y + (n1 - 0.5) * 0.9);
		alb = mix(alb, vec3(0.86, 0.95, 1.0), fr * 0.7);
		rough = mix(rough, 0.25, fr);
	} else if (mode == 1) {
		float brushed = vn3(vec3(p.x * 5.0, p.y * 300.0, p.z * 5.0));
		float scratch = smoothstep(0.93, 1.0, vn3(vec3(p.x * 380.0 + p.y * 40.0, p.y * 6.0, p.z * 380.0))) * step(0.5, vn3(p * 10.0));
		float rust = smoothstep(0.6, 0.82, fb3(p * 7.0 + 3.0)) * smoothstep(0.4, 0.7, vn3(p * 2.0));
		float dent = vn3(p * 18.0);
		alb = col * (0.74 + brushed * 0.1 + n1 * 0.24);
		alb = mix(alb, col * 1.3 + 0.05, scratch * 0.6);
		alb = mix(alb, col2 * (0.7 + n2 * 0.5), rust * 0.75);
		metal = mix(0.85, 0.15, rust);
		rough = mix(0.3 + n1 * 0.2, 0.85, rust);
		h = dent * 0.5 - scratch * 0.2 + rust * n2 * 0.4;
		float fr = frost * smoothstep(0.3, 0.9, ln.y + (n1 - 0.5) * 0.8);
		alb = mix(alb, vec3(0.88, 0.96, 1.0), fr * 0.6);
	} else if (mode == 2) {
		float eng = sin((p.x + p.z) * 220.0 + sin(p.y * 160.0 + p.x * 40.0) * 2.5);
		float fil = smoothstep(0.55, 0.95, eng);
		float tarn = smoothstep(0.55, 0.8, fb3(p * 8.0));
		alb = col * (0.68 + fil * 0.38) * (0.86 + n1 * 0.2);
		alb = mix(alb, col2, tarn * 0.45);
		metal = 0.95;
		rough = 0.24 + tarn * 0.3;
		h = fil * 0.6;
	} else if (mode == 3) {
		float grain = vn3(p * 180.0);
		float scuff = smoothstep(0.7, 0.9, vn3(p * 14.0));
		float crease = smoothstep(0.55, 0.75, vn3(vec3(p.x * 30.0, p.y * 90.0, p.z * 30.0)));
		alb = col * (0.7 + n1 * 0.36) * (0.9 + grain * 0.15);
		alb = mix(alb, col * 1.4, scuff * 0.35);
		alb = mix(alb, col2, crease * 0.3);
		rough = 0.62 + n1 * 0.2;
		h = grain * 0.35 - scuff * 0.2 - crease * 0.25;
	} else {
		float weave = sin(p.x * 1200.0 + p.z * 600.0) * sin(p.y * 1200.0);
		alb = col * (0.72 + n1 * 0.36);
		alb = mix(alb, col2, smoothstep(0.55, 0.8, fb3(p * 5.0)) * 0.5);
		rough = 0.95;
		h = weave * 0.15 + n2 * 0.2;
	}
	float hk = h * 0.0006;
	vec3 dpdx = dFdx(VERTEX);
	vec3 dpdy = dFdy(VERTEX);
	vec3 r1 = cross(dpdy, NORMAL);
	vec3 r2 = cross(NORMAL, dpdx);
	float det = dot(dpdx, r1);
	vec3 grad = sign(det) * (dFdx(hk) * r1 + dFdy(hk) * r2);
	if (abs(det) > 1e-12) { NORMAL = normalize(abs(det) * NORMAL - grad); }
	ALBEDO = alb;
	ROUGHNESS = rough;
	METALLIC = metal;
	EMISSION = em;
	RIM = 0.2;
	RIM_TINT = 0.6;
}
"""

const CLOAK_SHADER := """
shader_type spatial;
render_mode cull_disabled, diffuse_burley, specular_disabled;
uniform vec3 col : source_color = vec3(0.34, 0.25, 0.17);
uniform vec3 col2 : source_color = vec3(0.2, 0.14, 0.09);
uniform vec3 ember : source_color = vec3(0.0);
uniform float wave = 0.7;
uniform float frost = 0.0;
float h21(vec2 p){ p = fract(p * vec2(123.34, 456.21)); p += dot(p, p + 45.32); return fract(p.x * p.y); }
float vn(vec2 p){ vec2 i = floor(p); vec2 f = fract(p); vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(h21(i), h21(i + vec2(1.0, 0.0)), u.x), mix(h21(i + vec2(0.0, 1.0)), h21(i + vec2(1.0, 1.0)), u.x), u.y); }
float fb(vec2 p){ float v = 0.0; float a = 0.5; for (int i = 0; i < 4; i++){ v += a * vn(p); p = p * 2.05 + 3.1; a *= 0.5; } return v; }
void vertex(){
	float w = sin(TIME * 1.9 + VERTEX.x * 4.0 + VERTEX.y * 2.0) * 0.05 + sin(TIME * 3.3 + VERTEX.x * 9.0) * 0.015;
	VERTEX.z += w * wave * UV.y * UV.y;
	VERTEX.x += sin(TIME * 1.4 + VERTEX.y * 3.0) * 0.012 * wave * UV.y;
}
void fragment(){
	vec2 uv = UV;
	float n1 = fb(uv * vec2(6.0, 9.0));
	float weave = sin(uv.x * 900.0) * sin(uv.y * 1100.0);
	vec3 c = col * (0.7 + n1 * 0.4);
	c = mix(c, col2, smoothstep(0.55, 0.8, fb(uv * 3.0 + 5.0)) * 0.55);
	float hem = smoothstep(0.6, 1.0, uv.y);
	c = mix(c, col2 * 0.6, hem * (0.4 + n1 * 0.4));
	float fold = 0.5 + 0.5 * sin(uv.x * 25.0 + n1 * 3.0);
	c *= 0.82 + fold * 0.22;
	c *= 0.95 + weave * 0.05;
	float fr = frost * smoothstep(0.4, 0.8, fb(uv * 8.0)) * (0.4 + uv.y * 0.6);
	c = mix(c, vec3(0.86, 0.94, 1.0), fr * 0.6);
	ALBEDO = c;
	ROUGHNESS = 0.96;
	BACKLIGHT = c * 0.35;
	EMISSION = ember * smoothstep(0.85, 1.0, uv.y) * smoothstep(0.6, 0.9, n1) * 2.5;
}
"""
