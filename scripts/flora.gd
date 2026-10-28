class_name Flora
extends RefCounted
## Detailed vegetation: pines with branch whorls and needle sprays, gnarled dead trees with
## root flare, broadleaf moor oaks with leaf clusters, bushes, ferns, grass clumps with
## wildflowers. Everything is generated: bark and foliage detail comes from shaders, and
## trees sway in the wind. Each builder returns one ArrayMesh (bark + foliage surfaces) ready
## for MultiMesh instancing.

const NEEDLES := 0
const LEAVES := 1
const FERN := 2

static var _mats := {}
static var _shaders := {}
static var _cache := {}

# ---------------------------------------------------------------- materials
static func _shader(key: String, code: String) -> Shader:
	if not _shaders.has(key):
		var s := Shader.new()
		s.code = code
		_shaders[key] = s
	return _shaders[key]

static func bark_mat(col: Color, col2: Color, moss := 0.5) -> ShaderMaterial:
	var key := "bark%s%s%.2f" % [col.to_html(), col2.to_html(), moss]
	if not _mats.has(key):
		var m := ShaderMaterial.new()
		m.shader = _shader("bark", BARK_SHADER)
		m.set_shader_parameter("col", col)
		m.set_shader_parameter("col2", col2)
		m.set_shader_parameter("moss", moss)
		_mats[key] = m
	return _mats[key]

static func leaf_mat(kind: int, col: Color, col2: Color, dry: Color) -> ShaderMaterial:
	var key := "leaf%d%s%s" % [kind, col.to_html(), col2.to_html()]
	if not _mats.has(key):
		var m := ShaderMaterial.new()
		m.shader = _shader("leaf", FOLIAGE_SHADER)
		m.set_shader_parameter("kind", kind)
		m.set_shader_parameter("col", col)
		m.set_shader_parameter("col2", col2)
		m.set_shader_parameter("dry", dry)
		_mats[key] = m
	return _mats[key]

static func grass_mat(colors: Dictionary) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = _shader("grass2", GRASS_SHADER)
	for k in colors.keys():
		m.set_shader_parameter(k, colors[k])
	return m

# ---------------------------------------------------------------- geometry helpers
## A bent, tapered tube along pts. UV.x wraps around, UV.y runs along (in metres).
## COLOR.a carries how much the wind moves each vertex.
static func _tube(st: SurfaceTool, pts: Array, radii: Array, sides: int, sway: Array, tint := Color.WHITE) -> void:
	var n := pts.size()
	var rings := []
	var vlen := 0.0
	var vs := []
	var prev_nrm := Vector3.ZERO
	for i in n:
		var p: Vector3 = pts[i]
		var t: Vector3
		if i == 0:
			t = (pts[1] - pts[0]).normalized()
		elif i == n - 1:
			t = (pts[n - 1] - pts[n - 2]).normalized()
		else:
			t = (pts[i + 1] - pts[i - 1]).normalized()
		var nrm: Vector3
		if prev_nrm == Vector3.ZERO:
			nrm = t.cross(Vector3.FORWARD if absf(t.y) > 0.9 else Vector3.UP).normalized()
		else:
			nrm = (prev_nrm - t * prev_nrm.dot(t)).normalized()
		prev_nrm = nrm
		var bin := t.cross(nrm).normalized()
		var ring := []
		for k in sides + 1:
			var a := TAU * k / sides
			var d := nrm * cos(a) + bin * sin(a)
			ring.append([p + d * float(radii[i]), d])
		rings.append(ring)
		if i > 0:
			vlen += p.distance_to(pts[i - 1])
		vs.append(vlen)
	for i in n - 1:
		for k in sides:
			var q := [[i, k], [i, k + 1], [i + 1, k + 1], [i, k], [i + 1, k + 1], [i + 1, k]]
			for c in q:
				var r = rings[c[0]][c[1]]
				st.set_color(Color(tint.r, tint.g, tint.b, float(sway[c[0]])))
				st.set_uv(Vector2(float(c[1]) / sides, vs[c[0]]))
				st.set_normal(r[1])
				st.add_vertex(r[0])

## A foliage card: a quad from `base` along `along` (length) and `across` (width).
## UV.x runs along the spray, UV.y across. Normals point away from `center` for soft,
## rounded crown lighting.
static func _card(st: SurfaceTool, base: Vector3, along: Vector3, across: Vector3, center: Vector3, sway0: float, sway1: float, tint: Color) -> void:
	var p := [base - across * 0.5, base + across * 0.5, base + along + across * 0.5, base + along - across * 0.5]
	var uv := [Vector2(0, 0), Vector2(0, 1), Vector2(1, 1), Vector2(1, 0)]
	var sw := [sway0, sway0, sway1, sway1]
	for idx in [0, 1, 2, 0, 2, 3]:
		var v: Vector3 = p[idx]
		var nrm := ((v - center).normalized() * 0.75 + Vector3.UP * 0.45).normalized()
		st.set_color(Color(tint.r, tint.g, tint.b, sw[idx]))
		st.set_uv(uv[idx])
		st.set_normal(nrm)
		st.add_vertex(v)

static func _commit(bark: SurfaceTool, bark_m: Material, leaf: SurfaceTool, leaf_m: Material) -> ArrayMesh:
	var m := ArrayMesh.new()
	if bark:
		bark.commit(m)
		m.surface_set_material(m.get_surface_count() - 1, bark_m)
	if leaf:
		leaf.commit(m)
		m.surface_set_material(m.get_surface_count() - 1, leaf_m)
	return m

static func _st() -> SurfaceTool:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	return st

# ---------------------------------------------------------------- pine
## Scots-pine style conifer: a slightly crooked trunk, whorls of drooping branches that shorten
## toward the top, and crossed needle sprays along every branch.
static func pine(seed_v: int) -> ArrayMesh:
	var key := "pine%d" % seed_v
	if _cache.has(key):
		return _cache[key]
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_v * 7919 + 13
	var bark := _st()
	var leaf := _st()
	var h := rng.randf_range(5.6, 7.2)
	var lean := Vector3(rng.randf_range(-0.25, 0.25), 0, rng.randf_range(-0.25, 0.25))
	var trunk := []
	var tr := []
	var tsw := []
	for i in 9:
		var t := i / 8.0
		trunk.append(Vector3(sin(t * 5.0 + seed_v) * 0.05, h * t, cos(t * 4.0 + seed_v) * 0.05) + lean * t * t)
		tr.append(lerpf(0.21, 0.025, pow(t, 0.8)) * (1.25 if i == 0 else 1.0))
		tsw.append(t * t * 0.35)
	_tube(bark, trunk, tr, 9, tsw)
	var trunk_at := func(y: float) -> Vector3:
		var t := clampf(y / h, 0.0, 1.0)
		return Vector3(sin(t * 5.0 + seed_v) * 0.05, y, cos(t * 4.0 + seed_v) * 0.05) + lean * t * t
	var y := rng.randf_range(1.4, 1.9)
	var whorl := 0
	while y < h - 0.25:
		var t := (y - 1.4) / (h - 1.4)
		var nb := rng.randi_range(5, 7)
		var a0 := rng.randf() * TAU
		for b in nb:
			var a := a0 + TAU * b / nb + rng.randf_range(-0.3, 0.3)
			var L := (pow(1.0 - t, 0.85) * 1.9 + 0.25) * rng.randf_range(0.8, 1.15)
			var dir := Vector3(cos(a), -0.12 + t * 0.4 + rng.randf_range(-0.1, 0.1), sin(a)).normalized()
			var root: Vector3 = trunk_at.call(y)
			var mid := root + dir * L * 0.5 + Vector3(0, 0.04 * L, 0)
			var tip := root + dir * L + Vector3(0, -0.14 * L, 0)
			var swy := y / h * 0.6
			_tube(bark, [root, mid, tip], [0.035 * L + 0.012, 0.022 * L + 0.006, 0.006], 4, [swy, swy + 0.3, swy + 0.6])
			# needle sprays along the branch, denser toward the tip
			var ncards := 2 + int(L * 3.2)
			for c in ncards:
				var f := lerpf(0.22, 1.0, float(c) / maxf(ncards - 1, 1))
				var p := root.lerp(mid, minf(f * 2.0, 1.0)) if f < 0.5 else mid.lerp(tip, (f - 0.5) * 2.0)
				var along := (dir + Vector3(rng.randf_range(-0.25, 0.25), rng.randf_range(-0.15, 0.1), rng.randf_range(-0.25, 0.25))).normalized()
				var clen := lerpf(0.72, 0.5, f) * rng.randf_range(0.85, 1.15)
				var side := along.cross(Vector3.UP).normalized()
				var w := clen * 0.78
				var tint := Color.WHITE * (0.62 + 0.38 * f) * rng.randf_range(0.88, 1.12)
				tint.a = 1.0
				var cen := Vector3(0, y, 0)
				_card(leaf, p - along * clen * 0.15, along * clen, side * w, cen, swy + 0.3 * f, swy + 0.3 * f + 0.25, tint)
				var up2 := side.rotated(along, deg_to_rad(rng.randf_range(55, 80)))
				_card(leaf, p - along * clen * 0.15, along * clen, up2 * w * 0.85, cen, swy + 0.3 * f, swy + 0.3 * f + 0.25, tint * 0.92)
				var up3 := side.rotated(along, deg_to_rad(-rng.randf_range(40, 65)))
				_card(leaf, p - along * clen * 0.1, along * clen * 0.9, up3 * w * 0.8, cen, swy + 0.3 * f, swy + 0.3 * f + 0.25, tint * 0.85)
		y += rng.randf_range(0.3, 0.42)
		whorl += 1
	# leader at the crown
	var top: Vector3 = trunk_at.call(h)
	for k in 3:
		var side2 := Vector3(cos(k * PI / 3.0), 0, sin(k * PI / 3.0))
		_card(leaf, top - Vector3(0, 0.55, 0), Vector3(0, 0.75, 0), side2 * 0.4, top - Vector3(0, 1, 0), 0.6, 0.85, Color(1.05, 1.08, 1.0))
	# a few dead stubs low on the trunk
	for k in rng.randi_range(2, 4):
		var yy := rng.randf_range(0.7, 1.5)
		var aa := rng.randf() * TAU
		var r0: Vector3 = trunk_at.call(yy)
		_tube(bark, [r0, r0 + Vector3(cos(aa), -0.1, sin(aa)) * rng.randf_range(0.2, 0.45)], [0.025, 0.008], 4, [0.0, 0.05])
	var m := _commit(bark, bark_mat(Color(0.36, 0.24, 0.16), Color(0.16, 0.1, 0.07), 0.35), leaf,
		leaf_mat(NEEDLES, Color(0.12, 0.2, 0.1), Color(0.25, 0.34, 0.15), Color(0.34, 0.32, 0.17)))
	_cache[key] = m
	return m

# ---------------------------------------------------------------- dead tree
static func dead_tree(seed_v: int) -> ArrayMesh:
	var key := "dead%d" % seed_v
	if _cache.has(key):
		return _cache[key]
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_v * 104729 + 7
	var bark := _st()
	var h := rng.randf_range(3.9, 4.9)
	# root flare
	for k in rng.randi_range(4, 6):
		var a := TAU * k / 5.0 + rng.randf_range(-0.3, 0.3)
		var d := Vector3(cos(a), 0, sin(a))
		_tube(bark, [Vector3(0, 0.35, 0) + d * 0.1, Vector3(0, 0.08, 0) + d * 0.45, d * rng.randf_range(0.8, 1.2) + Vector3(0, -0.12, 0)], [0.13, 0.07, 0.025], 6, [0.0, 0.0, 0.0])
	var dir := Vector3(rng.randf_range(-0.2, 0.2), 1, rng.randf_range(-0.2, 0.2)).normalized()
	_dead_branch(bark, Vector3.ZERO, dir, h * 0.62, 0.27, 0, rng, h)
	var m := _commit(bark, bark_mat(Color(0.3, 0.27, 0.23), Color(0.12, 0.1, 0.09), 0.7), null, null)
	_cache[key] = m
	return m

static func _dead_branch(st: SurfaceTool, from: Vector3, dir: Vector3, length: float, r: float, depth: int, rng: RandomNumberGenerator, h: float) -> void:
	var pts := [from]
	var radii := [r]
	var sw := [clampf(from.y / h, 0.0, 1.0) * 0.25]
	var p := from
	var d := dir
	var segs := 4
	var wander := 0.12 if depth == 0 else 0.35
	for i in segs:
		d = (d + Vector3(rng.randf_range(-wander, wander), rng.randf_range(-0.05, 0.15), rng.randf_range(-wander, wander))).normalized()
		p += d * length / segs
		pts.append(p)
		radii.append(r * lerpf(1.0, 0.6, float(i + 1) / segs))
		sw.append(clampf(p.y / h, 0.0, 1.0) * 0.25 + depth * 0.08)
	_tube(st, pts, radii, 7 if depth == 0 else (5 if depth < 3 else 3), sw)
	var end_r: float = radii[radii.size() - 1]
	if depth >= 4 or end_r < 0.012:
		return
	if depth >= 1 and rng.randf() < 0.18:
		return  # snapped-off limb
	var kids := rng.randi_range(2, 3)
	for k in kids:
		var nd := (d * 1.2 + Vector3(rng.randf_range(-1.0, 1.0), rng.randf_range(0.15, 0.7), rng.randf_range(-1.0, 1.0))).normalized()
		_dead_branch(st, p, nd, length * rng.randf_range(0.5, 0.72), end_r * rng.randf_range(0.7, 0.9), depth + 1, rng, h)
	# a side limb partway up the main trunk
	if depth == 0:
		var mid: Vector3 = pts[2]
		var sd := Vector3(rng.randf_range(-1, 1), 0.35, rng.randf_range(-1, 1)).normalized()
		_dead_branch(st, mid, sd, length * 0.6, r * 0.45, 2, rng, h)

# ---------------------------------------------------------------- broadleaf (moor oak)
static func oak(seed_v: int) -> ArrayMesh:
	var key := "oak%d" % seed_v
	if _cache.has(key):
		return _cache[key]
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_v * 6271 + 3
	var bark := _st()
	var leaf := _st()
	var crown := Vector3(0, 3.4, 0)
	var tips := []
	_oak_branch(bark, Vector3.ZERO, Vector3(rng.randf_range(-0.15, 0.15), 1, rng.randf_range(-0.15, 0.15)).normalized(), 1.8, 0.36, 0, rng, tips)
	for k in 4:
		var a := TAU * k / 4.0 + rng.randf()
		var d := Vector3(cos(a), 0, sin(a))
		_tube(bark, [Vector3(0, 0.4, 0) + d * 0.12, d * 0.5 + Vector3(0, 0.05, 0), d * 0.9 + Vector3(0, -0.1, 0)], [0.17, 0.08, 0.03], 6, [0.0, 0.0, 0.0])
	# leaf clusters at every outer tip, plus a few filling the crown
	for tp in tips:
		_leaf_cluster(leaf, tp, crown, rng, rng.randi_range(10, 13), 1.25)
	for i in 14:
		var c := crown + Vector3(rng.randf_range(-1.6, 1.6), rng.randf_range(-0.1, 1.4), rng.randf_range(-1.6, 1.6))
		_leaf_cluster(leaf, c, crown, rng, 7, 1.15)
	var m := _commit(bark, bark_mat(Color(0.33, 0.27, 0.2), Color(0.14, 0.11, 0.08), 0.6), leaf,
		leaf_mat(LEAVES, Color(0.16, 0.22, 0.08), Color(0.3, 0.36, 0.12), Color(0.5, 0.36, 0.12)))
	_cache[key] = m
	return m

static func _oak_branch(st: SurfaceTool, from: Vector3, dir: Vector3, length: float, r: float, depth: int, rng: RandomNumberGenerator, tips: Array) -> void:
	var pts := [from]
	var radii := [r]
	var sw := [depth * 0.12]
	var p := from
	var d := dir
	for i in 3:
		d = (d + Vector3(rng.randf_range(-0.3, 0.3), rng.randf_range(-0.05, 0.2), rng.randf_range(-0.3, 0.3))).normalized()
		p += d * length / 3.0
		pts.append(p)
		radii.append(r * lerpf(1.0, 0.62, (i + 1) / 3.0))
		sw.append(depth * 0.12 + (i + 1) * 0.04)
	_tube(st, pts, radii, 8 if depth == 0 else (6 if depth < 2 else 4), sw)
	if depth >= 3:
		tips.append(p)
		return
	var kids := 3 if depth == 0 else rng.randi_range(2, 3)
	for k in kids:
		var a := TAU * k / kids + rng.randf_range(-0.5, 0.5)
		var spread := 0.85 if depth == 0 else 0.6
		var nd := (d * 0.6 + Vector3(cos(a) * spread, 0.35, sin(a) * spread)).normalized()
		_oak_branch(st, p, nd, length * rng.randf_range(0.62, 0.78), radii[radii.size() - 1] * 0.72, depth + 1, rng, tips)

static func _leaf_cluster(st: SurfaceTool, at: Vector3, center: Vector3, rng: RandomNumberGenerator, n: int, size: float) -> void:
	for i in n:
		var a := Vector3(rng.randf_range(-1, 1), rng.randf_range(-0.4, 0.9), rng.randf_range(-1, 1)).normalized()
		var b := a.cross(Vector3(rng.randf_range(-1, 1), rng.randf_range(-1, 1), rng.randf_range(-1, 1)).normalized()).normalized()
		var s := size * rng.randf_range(0.75, 1.2)
		var tint := Color.WHITE * rng.randf_range(0.8, 1.15) * clampf(0.7 + (at.y - center.y) * 0.18, 0.55, 1.1)
		tint.a = 1.0
		var sw := clampf(0.35 + (at - center).length() * 0.18, 0.3, 1.0)
		_card(st, at - a * s * 0.5, a * s, b * s, center, sw, sw + 0.15, tint)

# ---------------------------------------------------------------- Meshy oaks
## The three big old oaks generated with Meshy (assets/models/trees/oakN.glb, prepared by
## tools/blender/prep_tree.py: trunk on the origin, ~6 m tall). The model's own textured trunk,
## branches and leaves get a wind-sway shader (sway grows with height and distance from the trunk,
## same wind as the procedural trees, snow/ash and see-through-near-the-player like the bark), and
## the canopy is filled out with the game's own swaying leaf clusters. Falls back to Flora.oak.
const OAK_GLB := "res://assets/models/trees/oak%d.glb"
## per oak: leaf colours (col, col2, dry), how many leaf clusters, cluster size, texture brightness
const OAK_LEAVES := [
	[Color(0.17, 0.27, 0.09), Color(0.32, 0.42, 0.14), Color(0.42, 0.38, 0.14), 70, 1.15, 1.45],
	[Color(0.16, 0.2, 0.07), Color(0.42, 0.3, 0.1), Color(0.55, 0.3, 0.08), 70, 1.15, 1.1],
	[Color(0.15, 0.18, 0.08), Color(0.26, 0.28, 0.12), Color(0.36, 0.32, 0.14), 45, 1.0, 1.0],
]

static func oak_model(k: int) -> ArrayMesh:
	var key := "moak%d" % k
	if _cache.has(key):
		return _cache[key]
	var path := OAK_GLB % k
	if not ResourceLoader.exists(path):
		return oak(9 + k * 3)
	var scene: Node = (load(path) as PackedScene).instantiate()
	var out := ArrayMesh.new()
	var verts := PackedVector3Array()
	var h := 1.0
	for n in scene.find_children("*", "MeshInstance3D", true, false):
		var src: MeshInstance3D = n
		for si in src.mesh.get_surface_count():
			var arr: Array = src.mesh.surface_get_arrays(si)
			var vs: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			var xf := src.global_transform if src.is_inside_tree() else src.transform
			for i in vs.size():
				vs[i] = xf * vs[i]
				h = maxf(h, vs[i].y)
			arr[Mesh.ARRAY_VERTEX] = vs
			verts.append_array(vs)
			out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
			var sm: Material = src.mesh.surface_get_material(si)
			var m := ShaderMaterial.new()
			m.shader = _shader("meshy_tree", MESHY_TREE_SHADER)
			if sm is BaseMaterial3D:
				m.set_shader_parameter("albedo_tex", (sm as BaseMaterial3D).albedo_texture)
				if (sm as BaseMaterial3D).normal_texture != null:
					m.set_shader_parameter("normal_tex", (sm as BaseMaterial3D).normal_texture)
					m.set_shader_parameter("use_normal", true)
			m.set_shader_parameter("height", h)
			m.set_shader_parameter("tint", float(OAK_LEAVES[k - 1][5]))
			out.surface_set_material(out.get_surface_count() - 1, m)
	scene.free()
	# fill the canopy: leaf clusters on well-spread points of the crown
	var spec: Array = OAK_LEAVES[k - 1]
	var rng := RandomNumberGenerator.new()
	rng.seed = 4242 + k * 77
	var leaf := _st()
	var crown := Vector3(0, h * 0.62, 0)
	var picks: Array[Vector3] = []
	var tries := 0
	while picks.size() < int(spec[3]) and tries < 6000:
		tries += 1
		var v: Vector3 = verts[rng.randi() % verts.size()]
		if v.y < h * 0.42 or Vector2(v.x, v.z).length() < 0.8:
			continue
		var ok := true
		for q in picks:
			if q.distance_to(v) < 0.75:
				ok = false
				break
		if ok:
			picks.append(v)
	for c in picks:
		_leaf_cluster(leaf, c + (c - crown).normalized() * 0.15, crown, rng, rng.randi_range(8, 11), float(spec[4]))
	leaf.commit(out)
	out.surface_set_material(out.get_surface_count() - 1, leaf_mat(LEAVES, spec[0], spec[1], spec[2]))
	_cache[key] = out
	return out

# ---------------------------------------------------------------- undergrowth
static func bush(seed_v: int) -> ArrayMesh:
	var key := "bush%d" % seed_v
	if _cache.has(key):
		return _cache[key]
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_v * 3571
	var bark := _st()
	var leaf := _st()
	var center := Vector3(0, 0.35, 0)
	for i in 5:
		var a := rng.randf() * TAU
		var tip := Vector3(cos(a) * 0.45, rng.randf_range(0.45, 0.8), sin(a) * 0.45)
		_tube(bark, [Vector3.ZERO, tip * 0.5 + Vector3(0, 0.05, 0), tip], [0.03, 0.02, 0.008], 4, [0.0, 0.15, 0.3])
		_leaf_cluster(leaf, tip, center, rng, 6, 0.6)
	for i in 6:
		_leaf_cluster(leaf, center + Vector3(rng.randf_range(-0.5, 0.5), rng.randf_range(0.0, 0.35), rng.randf_range(-0.5, 0.5)), center, rng, 4, 0.55)
	var m := _commit(bark, bark_mat(Color(0.3, 0.24, 0.18), Color(0.15, 0.11, 0.08), 0.3), leaf,
		leaf_mat(LEAVES, Color(0.13, 0.19, 0.07), Color(0.24, 0.3, 0.1), Color(0.42, 0.3, 0.12)))
	_cache[key] = m
	return m

static func fern(seed_v: int) -> ArrayMesh:
	var key := "fern%d" % seed_v
	if _cache.has(key):
		return _cache[key]
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_v * 17
	var leaf := _st()
	var n := rng.randi_range(7, 10)
	for i in n:
		var a := TAU * i / n + rng.randf_range(-0.2, 0.2)
		var out := Vector3(cos(a), 0, sin(a))
		var L := rng.randf_range(0.55, 0.85)
		# each frond arches: two cards, rising then drooping
		var p0 := out * 0.03
		var p1 := p0 + out * L * 0.5 + Vector3(0, L * 0.45, 0)
		var p2 := p1 + out * L * 0.5 + Vector3(0, -L * 0.12, 0)
		var side := out.cross(Vector3.UP).normalized()
		var tint := Color.WHITE * rng.randf_range(0.85, 1.12)
		tint.a = 1.0
		_fern_card(leaf, p0, p1, side * L * 0.42, 0.0, 0.5, 0.1, 0.5, tint)
		_fern_card(leaf, p1, p2, side * L * 0.42, 0.5, 1.0, 0.5, 1.0, tint)
	var m := _commit(null, null, leaf, leaf_mat(FERN, Color(0.11, 0.2, 0.07), Color(0.24, 0.34, 0.11), Color(0.45, 0.33, 0.12)))
	_cache[key] = m
	return m

static func _fern_card(st: SurfaceTool, a: Vector3, b: Vector3, across: Vector3, u0: float, u1: float, s0: float, s1: float, tint: Color) -> void:
	var p := [a - across * 0.5, a + across * 0.5, b + across * 0.5, b - across * 0.5]
	var uv := [Vector2(u0, 0), Vector2(u0, 1), Vector2(u1, 1), Vector2(u1, 0)]
	var sw := [s0, s0, s1, s1]
	var nrm := (b - a).cross(across).normalized()
	if nrm.y < 0.0:
		nrm = -nrm
	for idx in [0, 1, 2, 0, 2, 3]:
		st.set_color(Color(tint.r, tint.g, tint.b, sw[idx]))
		st.set_uv(uv[idx])
		st.set_normal((nrm + Vector3.UP * 0.6).normalized())
		st.add_vertex(p[idx])

## A grass clump: curved, tapered blades with their own tint. flowers > 0 adds wildflower
## heads on stems (heather pink, tormentil yellow, harebell blue, cotton-grass white).
## Act I grass: photographic clumps (Meshy-painted cut-outs, assets/textures/grass/gN.png) on three
## crossed cards each, with the same wind, snow and ash handling as the blade grass.
const GRASS_TEX := "res://assets/textures/grass/g%d.png"
## per texture: card width, height (metres), tint
const GRASS_CARDS := [[0.66, 0.44, Color(0.86, 0.92, 0.82)], [0.58, 0.46, Color(0.88, 0.93, 0.85)], [0.6, 0.62, Color(0.78, 0.8, 0.7)]]

static func grass_tex_ok() -> bool:
	return ResourceLoader.exists(GRASS_TEX % 1)

static func grass_cards(k: int, seed_v: int, colors: Dictionary) -> ArrayMesh:
	var key := "gcard%d_%d" % [k, seed_v]
	if _cache.has(key):
		return _cache[key]
	var spec: Array = GRASS_CARDS[k - 1]
	var w: float = spec[0]
	var h: float = spec[1]
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_v * 97 + k
	var st := _st()
	var a0 := rng.randf() * PI
	for c in 3:
		var a := a0 + c * PI / 3.0 + rng.randf_range(-0.2, 0.2)
		var d := Vector3(cos(a), 0, sin(a)) * w * 0.5
		var off := Vector3(rng.randf_range(-0.05, 0.05), 0, rng.randf_range(-0.05, 0.05))
		var hh := h * rng.randf_range(0.9, 1.1)
		# lean each card outward a little so the clump covers more ground seen from above
		var outv := Vector3(-sin(a), 0, cos(a)) * (1.0 if c % 2 == 0 else -1.0)
		var lean := outv * hh * 0.28 + Vector3(rng.randf_range(-0.04, 0.04), 0, rng.randf_range(-0.04, 0.04))
		var flip := rng.randf() < 0.5
		var u0 := 1.0 if flip else 0.0
		var u1 := 0.0 if flip else 1.0
		var q := [[off - d, Vector2(u0, 0)], [off + d, Vector2(u1, 0)], [off + d + lean + Vector3(0, hh, 0), Vector2(u1, 1)],
			[off - d, Vector2(u0, 0)], [off + d + lean + Vector3(0, hh, 0), Vector2(u1, 1)], [off - d + lean + Vector3(0, hh, 0), Vector2(u0, 1)]]
		for v in q:
			var p: Vector3 = v[0]
			st.set_color(spec[2])
			st.set_uv(v[1])
			st.set_normal((Vector3(p.x, 0, p.z).normalized() * 0.35 + Vector3.UP).normalized())
			st.add_vertex(p)
	var m := ArrayMesh.new()
	st.commit(m)
	var mat := ShaderMaterial.new()
	mat.shader = _shader("grass_cards", GRASS_CARD_SHADER)
	mat.set_shader_parameter("tex", load(GRASS_TEX % k))
	for ck in colors.keys():
		if ck in ["dry_col"]:
			mat.set_shader_parameter(ck, colors[ck])
	m.surface_set_material(0, mat)
	_cache[key] = m
	return m

static func grass_clump(seed_v: int, blades: int = 13, height: float = 0.34, flowers: int = 0) -> ArrayMesh:
	var key := "grass%d_%d_%.2f_%d" % [seed_v, blades, height, flowers]
	if _cache.has(key):
		return _cache[key]
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_v * 31 + blades
	var st := _st()
	for i in blades:
		var a := rng.randf() * TAU
		var r := sqrt(rng.randf()) * 0.24
		var base := Vector3(cos(a) * r, 0, sin(a) * r)
		var face := rng.randf() * TAU
		var hgt := height * rng.randf_range(0.55, 1.25)
		var lean_dir := (base.normalized() if r > 0.02 else Vector3(cos(face), 0, sin(face)))
		var lean := lean_dir * rng.randf_range(0.06, 0.22) * hgt / height
		var wd := rng.randf_range(0.018, 0.03)
		var side := Vector3(cos(face), 0, sin(face)) * wd
		var hue := rng.randf()
		var tint := Color(rng.randf_range(0.85, 1.12), rng.randf_range(0.88, 1.12), rng.randf_range(0.8, 1.05), 1.0)
		if hue < 0.12:
			tint = Color(1.35, 1.2, 0.85, 1.0)   # sun-dried blade
		var segs := 4
		var nrm := (lean_dir * 0.6 + Vector3.UP).normalized()
		for s in segs:
			var t0 := float(s) / segs
			var t1 := float(s + 1) / segs
			var q0 := base + lean * t0 * t0 + Vector3(0, hgt * t0, 0)
			var q1 := base + lean * t1 * t1 + Vector3(0, hgt * t1, 0)
			var w0 := side * (1.0 - t0 * 0.92)
			var w1 := side * (1.0 - t1 * 0.92)
			var quad := [[q0 - w0, Vector2(0, t0)], [q0 + w0, Vector2(1, t0)], [q1 + w1, Vector2(1, t1)], [q0 - w0, Vector2(0, t0)], [q1 + w1, Vector2(1, t1)], [q1 - w1, Vector2(0, t1)]]
			for v in quad:
				st.set_color(tint)
				st.set_uv(v[1])
				st.set_normal(nrm)
				st.add_vertex(v[0])
	var fcols := [Color(0.85, 0.42, 0.72), Color(1.0, 0.85, 0.25), Color(0.5, 0.55, 1.0), Color(0.95, 0.95, 0.9)]
	for i in flowers:
		var a := rng.randf() * TAU
		var base := Vector3(cos(a), 0, sin(a)) * rng.randf_range(0.02, 0.12)
		var top := base + Vector3(rng.randf_range(-0.04, 0.04), height * rng.randf_range(1.0, 1.4), rng.randf_range(-0.04, 0.04))
		var stem := Vector3(0.006, 0, 0)
		for v in [[base - stem, 0.0], [base + stem, 0.0], [top + stem, 1.0], [base - stem, 0.0], [top + stem, 1.0], [top - stem, 1.0]]:
			st.set_color(Color(0.8, 0.95, 0.7, 1.0))
			st.set_uv(Vector2(0.5, v[1]))
			st.set_normal(Vector3.UP)
			st.add_vertex(v[0])
		# flower head: a small 5-petal fan, flagged with alpha 0 so the shader uses its colour as-is
		var fc: Color = fcols[(seed_v + i) % fcols.size()]
		var pr := rng.randf_range(0.03, 0.045)
		for k in 5:
			var a0 := TAU * k / 5.0
			var a1 := TAU * (k + 0.5) / 5.0
			var a2 := TAU * (k + 1) / 5.0
			var tip := top + Vector3(cos(a1), 0.25, sin(a1)) * pr
			for v in [top + Vector3(0, 0.01, 0), top + Vector3(cos(a0), 0.15, sin(a0)) * pr * 0.55, tip, top + Vector3(0, 0.01, 0), tip, top + Vector3(cos(a2), 0.15, sin(a2)) * pr * 0.55]:
				st.set_color(Color(fc.r, fc.g, fc.b, 0.0))
				st.set_uv(Vector2(0.5, 1.0))
				st.set_normal(Vector3.UP)
				st.add_vertex(v)
	var m := st.commit()
	_cache[key] = m
	return m

# ---------------------------------------------------------------- shaders
const BARK_SHADER := """
shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;
uniform vec3 col : source_color = vec3(0.35, 0.25, 0.17);
uniform vec3 col2 : source_color = vec3(0.15, 0.1, 0.07);
uniform float moss = 0.4;
global uniform float snow_amt;
global uniform float ash_amt;
global uniform vec3 player_pos;
global uniform float occlude_k;
varying vec3 bwp;
varying float smoulder;
varying float sway;
varying vec3 wn;
varying float wy;
float h21(vec2 p){ p = fract(p * vec2(123.34, 456.21)); p += dot(p, p + 45.32); return fract(p.x * p.y); }
float vn(vec2 p){ vec2 i = floor(p); vec2 f = fract(p); vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(h21(i), h21(i + vec2(1.0, 0.0)), u.x), mix(h21(i + vec2(0.0, 1.0)), h21(i + vec2(1.0, 1.0)), u.x), u.y); }
void vertex(){
	sway = COLOR.a;
	vec3 o = MODEL_MATRIX[3].xyz;
	float ph = o.x * 0.21 + o.z * 0.17;
	float w = sin(TIME * 0.9 + ph) * 0.6 + sin(TIME * 2.1 + ph * 1.7) * 0.25;
	VERTEX.x += w * 0.12 * sway;
	VERTEX.z += w * 0.07 * sway;
	wn = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	bwp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wy = bwp.y - o.y;
	smoulder = step(0.55, h21(o.xz * 0.37));
}
void fragment(){
	{
		vec3 d = bwp - player_pos;
		float hh = bwp.y - player_pos.y;
		float along = d.z - occlude_k * (hh - 1.0);
		float cover = (1.0 - smoothstep(1.6, 3.2, abs(along))) * (1.0 - smoothstep(2.2, 3.6, abs(d.x)));
		cover *= step(0.9, hh) * step(0.2, d.z);
		if (cover * 0.9 > h21(floor(FRAGCOORD.xy))) { discard; }
	}
	// vertical fissures that wander, plates between them
	vec2 uv = vec2(UV.x * 7.0, UV.y * 1.6);
	float wob = vn(vec2(UV.x * 3.0, UV.y * 0.8)) * 1.6;
	float ridge = abs(fract(uv.x + wob) - 0.5) * 2.0;
	float fis = smoothstep(0.75, 0.95, ridge);
	float plates = vn(uv * vec2(1.0, 2.5) + 3.0);
	vec3 c = mix(col, col2, fis * 0.85);
	c *= 0.82 + plates * 0.3;
	c = mix(c, col * 1.25, smoothstep(0.7, 0.95, vn(uv * 2.3)) * 0.25);
	float m = moss * smoothstep(0.15, 0.7, wn.y + vn(UV * vec2(4.0, 2.0)) * 0.6 - 0.2);
	m = max(m, moss * smoothstep(0.6, 0.0, wy) * smoothstep(0.3, 0.6, vn(UV * vec2(6.0, 3.0))));
	c = mix(c, vec3(0.16, 0.22, 0.07) * (0.8 + plates * 0.4), clamp(m, 0.0, 0.85));
	if (snow_amt > 0.0) {
		float sn = snow_amt * smoothstep(0.2, 0.6, wn.y + (vn(UV * vec2(5.0, 2.0)) - 0.5) * 0.5);
		sn = max(sn, snow_amt * smoothstep(0.35, 0.0, wy) * 0.8);
		c = mix(c, vec3(0.85, 0.9, 0.97) * (0.9 + plates * 0.1), sn);
	}
	vec3 em = vec3(0.0);
	if (ash_amt > 0.0) {
		c = mix(c, vec3(0.045, 0.04, 0.035) * (0.8 + plates * 0.6), ash_amt * 0.92);
		c = mix(c, vec3(0.3, 0.28, 0.26), ash_amt * smoothstep(0.55, 0.9, wn.y) * 0.4);
		float pulse = 0.6 + 0.4 * sin(TIME * 2.0 + bwp.y * 3.0 + bwp.x);
		em = vec3(1.0, 0.32, 0.06) * fis * smoothstep(0.3, 0.7, vn(uv * 0.7 + 5.0)) * smoulder * pulse * 2.2 * ash_amt;
	}
	ALBEDO = c;
	EMISSION = em;
	ROUGHNESS = 0.92;
	NORMAL_MAP = normalize(vec3(0.5 + (plates - 0.5) * 0.3, 0.5 + (fis - 0.5) * 0.6, 1.0));
	AO = mix(0.65, 1.0, 1.0 - fis * 0.6);
	AO_LIGHT_AFFECT = 0.3;
}
"""

const MESHY_TREE_SHADER := """
shader_type spatial;
render_mode cull_disabled, diffuse_burley, specular_schlick_ggx;
uniform sampler2D albedo_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap, repeat_enable;
uniform bool use_normal = false;
uniform float height = 6.0;
uniform float tint = 1.0;
global uniform float snow_amt;
global uniform float ash_amt;
global uniform vec3 player_pos;
global uniform float occlude_k;
varying vec3 bwp;
varying vec3 wn;
float h21(vec2 p){ p = fract(p * vec2(123.34, 456.21)); p += dot(p, p + 45.32); return fract(p.x * p.y); }
void vertex(){
	vec3 o = MODEL_MATRIX[3].xyz;
	float ph = o.x * 0.21 + o.z * 0.17;
	float hy = clamp(VERTEX.y / height, 0.0, 1.0);
	float s = hy * hy * clamp(length(VERTEX.xz) * 0.5 + 0.4, 0.0, 1.4);
	float w = sin(TIME * 0.9 + ph) * 0.6 + sin(TIME * 2.1 + ph * 1.7) * 0.25;
	float flutter = sin(TIME * 5.0 + VERTEX.x * 3.0 + VERTEX.z * 2.0 + ph * 3.0) * 0.015;
	VERTEX.x += (w * 0.12 + flutter) * s;
	VERTEX.z += (w * 0.07 + flutter) * s;
	wn = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	bwp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}
void fragment(){
	{
		vec3 d = bwp - player_pos;
		float hh = bwp.y - player_pos.y;
		float along = d.z - occlude_k * (hh - 1.0);
		float cover = (1.0 - smoothstep(1.6, 3.2, abs(along))) * (1.0 - smoothstep(2.2, 3.6, abs(d.x)));
		cover *= step(0.9, hh) * step(0.2, d.z);
		if (cover * 0.9 > h21(floor(FRAGCOORD.xy))) { discard; }
	}
	vec3 c = texture(albedo_tex, UV).rgb;
	// Meshy bakes the trees quite grey: lift the greens a touch and deepen the bark
	float g = c.g - max(c.r, c.b);
	c = mix(c, c * vec3(0.9, 1.12, 0.85), clamp(g * 8.0 + 0.2, 0.0, 1.0));
	c *= 0.95 * tint;
	if (snow_amt > 0.0) {
		c = mix(c, vec3(0.85, 0.88, 0.92), snow_amt * smoothstep(0.45, 0.85, wn.y));
	}
	if (ash_amt > 0.0) {
		c = mix(c, vec3(0.05, 0.045, 0.04), ash_amt * 0.85);
	}
	ALBEDO = c;
	ROUGHNESS = 0.88;
	SPECULAR = 0.25;
	if (use_normal) { NORMAL_MAP = texture(normal_tex, UV).rgb; }
	if (!FRONT_FACING) { NORMAL = -NORMAL; }
}
"""

const FOLIAGE_SHADER := """
shader_type spatial;
render_mode cull_disabled, diffuse_burley, specular_schlick_ggx;
uniform int kind = 0;
uniform vec3 col : source_color = vec3(0.1, 0.17, 0.09);
uniform vec3 col2 : source_color = vec3(0.2, 0.28, 0.13);
uniform vec3 dry : source_color = vec3(0.32, 0.3, 0.16);
global uniform float snow_amt;
global uniform float ash_amt;
global uniform vec3 player_pos;
global uniform float occlude_k;
varying vec4 vc;
varying vec3 wp;
varying float wny;
float h21(vec2 p){ p = fract(p * vec2(123.34, 456.21)); p += dot(p, p + 45.32); return fract(p.x * p.y); }
float vn(vec2 p){ vec2 i = floor(p); vec2 f = fract(p); vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(h21(i), h21(i + vec2(1.0, 0.0)), u.x), mix(h21(i + vec2(0.0, 1.0)), h21(i + vec2(1.0, 1.0)), u.x), u.y); }
void vertex(){
	vc = COLOR;
	vec3 o = MODEL_MATRIX[3].xyz;
	float ph = o.x * 0.21 + o.z * 0.17;
	float s = COLOR.a;
	float w = sin(TIME * 0.9 + ph) * 0.6 + sin(TIME * 2.1 + ph * 1.7) * 0.25;
	float flutter = sin(TIME * 6.0 + VERTEX.x * 9.0 + VERTEX.z * 7.0 + ph * 3.0) * 0.02;
	VERTEX.x += (w * 0.12 + flutter) * s;
	VERTEX.z += (w * 0.07 + flutter) * s;
	VERTEX.y += flutter * s * 0.5;
	wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wny = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz).y;
}
float needles(vec2 uv){
	// a spray: a twig down the middle, needles angled out from it, tapering to the tip
	float x = uv.x;
	float y = uv.y - 0.5;
	float env = 1.0 - smoothstep(0.42 * (1.0 - x * 0.55), 0.48 * (1.0 - x * 0.5), abs(y));
	env *= smoothstep(0.0, 0.06, x) * (1.0 - smoothstep(0.92, 1.0, x));
	float t = x * 24.0 - abs(y) * 9.0 + h21(vec2(floor(x * 24.0), sign(y))) * 0.4;
	float nd = 1.0 - smoothstep(0.12, 0.3, abs(fract(t) - 0.5));
	float twig = 1.0 - smoothstep(0.015, 0.03, abs(y));
	return max(nd * env, twig * step(x, 0.95));
}
float leaves(vec2 uv){
	// a cluster of overlapping leaves inside a rounded silhouette
	vec2 p = uv * 3.4;
	float a = 0.0;
	for (int j = -1; j <= 1; j++) {
		for (int i = -1; i <= 1; i++) {
			vec2 cell = floor(p) + vec2(float(i), float(j));
			vec2 c = cell + vec2(h21(cell), h21(cell + 7.1)) * 0.8 + 0.1;
			float ang = h21(cell + 3.3) * 6.2831;
			vec2 d = p - c;
			d = vec2(d.x * cos(ang) - d.y * sin(ang), d.x * sin(ang) + d.y * cos(ang));
			float e = length(d * vec2(1.0, 2.1));
			a = max(a, 1.0 - smoothstep(0.42, 0.5, e));
		}
	}
	float r = length(uv - 0.5);
	return a * (1.0 - smoothstep(0.38, 0.5, r + vn(uv * 6.0) * 0.12));
}
float fern(vec2 uv){
	float x = uv.x;
	float y = uv.y - 0.5;
	float width = 0.46 * sin(clamp(x, 0.0, 1.0) * 3.14159) * (1.0 - x * 0.35);
	float rib = 1.0 - smoothstep(0.01, 0.025, abs(y));
	float pinna = fract(x * 16.0 - abs(y) * 2.5);
	float leaflet = (1.0 - smoothstep(0.32, 0.46, abs(pinna - 0.5))) * (1.0 - smoothstep(width * 0.85, width, abs(y)));
	return max(rib * step(x, 0.98), leaflet);
}
void fragment(){
	float a = kind == 0 ? needles(UV) : (kind == 1 ? leaves(UV) : fern(UV));
	if (a < 0.5) { discard; }
	float singe = 0.0;
	if (ash_amt > 0.0) {
		float keep = vn(wp.xz * 1.1 + wp.y * 0.9 + 3.0);
		if (keep < 0.72 * ash_amt) { discard; }
		singe = smoothstep(0.72, 0.9, keep);
	}
	{
		vec3 d = wp - player_pos;
		float hh = wp.y - player_pos.y;
		float along = d.z - occlude_k * (hh - 1.0);
		float cover = (1.0 - smoothstep(1.6, 3.2, abs(along))) * (1.0 - smoothstep(2.2, 3.6, abs(d.x)));
		cover *= step(0.9, hh) * step(0.2, d.z);
		if (cover * 0.9 > h21(floor(FRAGCOORD.xy))) { discard; }
	}
	float n = vn(wp.xz * 0.35 + wp.y * 0.2);
	vec3 c = mix(col, col2, smoothstep(0.2, 0.9, UV.x * 0.6 + n * 0.6));
	c = mix(c, dry, smoothstep(0.62, 0.85, vn(wp.xz * 0.9 + 11.0)) * 0.45);
	c *= vc.rgb;
	if (snow_amt > 0.0) {
		// snow settles on the upper side of every spray, clumping in patches
		float lump = vn(UV * vec2(5.0, 3.0) + wp.xz * 0.7);
		float sn = snow_amt * smoothstep(0.35, 0.75, wny + (lump - 0.5) * 0.7) * clamp(vc.r * 1.1, 0.4, 1.0);
		sn *= 1.0 - smoothstep(0.75, 1.0, UV.x) * 0.5;
		c = mix(c, vec3(0.8, 0.84, 0.91) * (0.88 + lump * 0.14), sn);
	}
	vec3 fem = vec3(0.0);
	if (ash_amt > 0.0) {
		c = mix(vec3(0.05, 0.035, 0.025), vec3(0.32, 0.14, 0.05), singe) * (0.8 + vn(UV * 6.0) * 0.4);
		fem = vec3(1.0, 0.35, 0.06) * smoothstep(0.92, 1.0, vn(UV * 9.0 + wp.xz)) * 1.5 * ash_amt;
	}
	ALBEDO = c;
	EMISSION = fem;
	ROUGHNESS = 0.8;
	SPECULAR = 0.25;
	BACKLIGHT = c * 0.6;
	AO = clamp(vc.r * 0.9 + 0.1, 0.4, 1.0);
	AO_LIGHT_AFFECT = 0.25;
}
"""

const GRASS_CARD_SHADER := """
shader_type spatial;
render_mode cull_disabled, diffuse_burley, specular_schlick_ggx;
uniform sampler2D tex : source_color, filter_linear_mipmap, repeat_disable;
uniform vec3 dry_col : source_color = vec3(0.42, 0.38, 0.18);
uniform float wind = 1.0;
global uniform float snow_amt;
global uniform float ash_amt;
varying float hgt;
varying vec3 wpos;
varying vec4 vc;
varying float gust;
float h21(vec2 p){ p = fract(p * vec2(123.34, 456.21)); p += dot(p, p + 45.32); return fract(p.x * p.y); }
float vn(vec2 p){ vec2 i = floor(p); vec2 f = fract(p); vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(h21(i), h21(i + vec2(1.0, 0.0)), u.x), mix(h21(i + vec2(0.0, 1.0)), h21(i + vec2(1.0, 1.0)), u.x), u.y); }
void vertex(){
	hgt = UV.y;
	vc = COLOR;
	vec3 o = MODEL_MATRIX[3].xyz;
	gust = vn(o.xz * 0.07 - vec2(TIME * 0.55, TIME * 0.3));
	float w = sin(TIME * 1.7 + o.x * 0.35 + o.z * 0.22) * 0.5 + gust * 1.3;
	float flick = sin(TIME * 5.0 + o.x * 3.0 + VERTEX.x * 20.0) * 0.012;
	VERTEX.x += (w * 0.1 + flick) * hgt * hgt * wind * (1.0 - snow_amt * 0.5);
	VERTEX.z += (w * 0.06 + flick) * hgt * hgt * wind * (1.0 - snow_amt * 0.5);
	VERTEX.y -= snow_amt * 0.16;
	VERTEX.y *= 1.0 - ash_amt * 0.4;
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}
void fragment(){
	vec4 t = texture(tex, vec2(UV.x, 1.0 - UV.y));
	if (t.a < 0.45) { discard; }
	if (snow_amt > 0.0 && hgt < snow_amt * 0.5) { discard; }
	float patch = vn(wpos.xz * 0.13);
	vec3 c = t.rgb * vc.rgb;
	// patches of drier grass across the field, and a little variation per clump
	c = mix(c, c * dry_col / max(dot(dry_col, vec3(0.33)), 0.05) * 0.45, smoothstep(0.6, 0.95, patch) * 0.2);
	c *= 0.82 + h21(floor(MODEL_MATRIX[3].xz * 3.0)) * 0.3;
	c *= 1.0 + (gust - 0.5) * 0.2 * hgt;
	if (ash_amt > 0.0) {
		c = mix(c, mix(vec3(0.06, 0.05, 0.04), vec3(0.3, 0.27, 0.23), hgt), ash_amt * 0.92);
	}
	if (snow_amt > 0.0) {
		c = mix(c, vec3(0.42, 0.38, 0.26), snow_amt * 0.6);
		c = mix(c, vec3(0.86, 0.9, 0.96), snow_amt * smoothstep(0.75, 1.0, hgt) * 0.75);
	}
	ALBEDO = c;
	ROUGHNESS = 0.75;
	SPECULAR = 0.25;
	BACKLIGHT = c * 0.35 * hgt;
	AO = mix(0.5, 1.0, hgt);
	AO_LIGHT_AFFECT = 0.4;
}
"""

const GRASS_SHADER := """
shader_type spatial;
render_mode cull_disabled, diffuse_burley, specular_schlick_ggx;
uniform vec3 base_col : source_color = vec3(0.1, 0.14, 0.05);
uniform vec3 tip_col : source_color = vec3(0.3, 0.36, 0.14);
uniform vec3 dry_col : source_color = vec3(0.42, 0.38, 0.18);
uniform float wind = 1.0;
global uniform float snow_amt;
global uniform float ash_amt;
varying float hgt;
varying vec3 wpos;
varying vec4 vc;
varying float gust;
float h21(vec2 p){ p = fract(p * vec2(123.34, 456.21)); p += dot(p, p + 45.32); return fract(p.x * p.y); }
float vn(vec2 p){ vec2 i = floor(p); vec2 f = fract(p); vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(h21(i), h21(i + vec2(1.0, 0.0)), u.x), mix(h21(i + vec2(0.0, 1.0)), h21(i + vec2(1.0, 1.0)), u.x), u.y); }
void vertex(){
	hgt = UV.y;
	vc = COLOR;
	vec3 o = MODEL_MATRIX[3].xyz;
	// gusts roll across the field as broad waves
	gust = vn(o.xz * 0.07 - vec2(TIME * 0.55, TIME * 0.3));
	float w = sin(TIME * 1.7 + o.x * 0.35 + o.z * 0.22) * 0.5 + gust * 1.3;
	float flick = sin(TIME * 5.0 + o.x * 3.0 + VERTEX.x * 20.0) * 0.015;
	VERTEX.x += (w * 0.13 + flick) * hgt * hgt * wind * (1.0 - snow_amt * 0.5);
	VERTEX.z += (w * 0.07 + flick) * hgt * hgt * wind * (1.0 - snow_amt * 0.5);
	// half buried: sink the clump so only the upper blades show above the snow
	VERTEX.y -= snow_amt * 0.16;
	VERTEX.y *= 1.0 - ash_amt * 0.4;
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}
void fragment(){
	if (snow_amt > 0.0 && hgt < snow_amt * 0.5) { discard; }
	if (vc.a < 0.5) {
		if (snow_amt > 0.5 || ash_amt > 0.5) { discard; }
		// wildflower petals
		ALBEDO = vc.rgb;
		ROUGHNESS = 0.6;
		BACKLIGHT = vc.rgb * 0.5;
	} else {
		float patch = vn(wpos.xz * 0.13);
		float fine = vn(wpos.xz * 1.7);
		vec3 tip = mix(tip_col, dry_col, smoothstep(0.45, 0.85, patch * 0.8 + fine * 0.3));
		vec3 c = mix(base_col, tip, smoothstep(0.0, 0.9, hgt)) * vc.rgb;
		c *= 1.0 + (gust - 0.5) * 0.25 * hgt;
		if (ash_amt > 0.0) {
			// burned grass: charred stubble with grey ash, the odd ember at a tip
			c = mix(c, mix(vec3(0.06, 0.05, 0.04), vec3(0.3, 0.27, 0.23), hgt) * vc.rgb, ash_amt * 0.92);
			float tipglow = step(0.965, h21(floor(wpos.xz * 4.0))) * smoothstep(0.7, 1.0, hgt);
			EMISSION = vec3(1.0, 0.35, 0.05) * tipglow * (0.6 + 0.4 * sin(TIME * 4.0 + wpos.x * 5.0)) * 2.0 * ash_amt;
		}
		if (snow_amt > 0.0) {
			// winter-dried blades with frost on the tips
			c = mix(c, vec3(0.42, 0.38, 0.26) * vc.rgb, snow_amt * 0.6);
			c = mix(c, vec3(0.86, 0.9, 0.96), snow_amt * smoothstep(0.75, 1.0, hgt) * 0.75);
		}
		ALBEDO = c;
		ROUGHNESS = 0.7;
		SPECULAR = 0.3;
		BACKLIGHT = c * 0.7 * hgt;
		AO = mix(0.45, 1.0, hgt);
		AO_LIGHT_AFFECT = 0.5;
	}
}
"""
