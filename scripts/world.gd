class_name World
extends Node3D
## A playable zone: terrain, props, collision grid, pathfinding and spawn data.

const CELL := 1.0
const MARGIN := 30.0

var act := 0
var kind := "town"
var level := 1
var rng := RandomNumberGenerator.new()
## Graphics setting (0 Low .. 3 Ultra), set by the game before each area is built.
static var detail := 2
const GRASS_DENSITY := [0.45, 0.7, 1.0, 1.7]
var bounds := Rect2(-40, -40, 80, 80)    # playable area in x/z
var origin := Vector2.ZERO
var gw := 0
var gh := 0
var blocked := PackedByteArray()
var astar: AStarGrid2D
var hnoise := FastNoiseLite.new()
var hill_noise := FastNoiseLite.new()
var flat_floor := false
var dirt_blobs: Array = []     # [Vector2 pos, radius, strength]
var cobble_blobs: Array = []
var dirt_lines: Array = []     # [Vector2 a, Vector2 b, width]
var obstacles: Array = []      # [Vector2 pos, radius]
var spawns := {}
## Places that burn in A3: [position, size]. Recorded while building; only used for looks.
var burn_points: Array = []
var enemy_spawns: Array = []
var boss_spawn := {}
var interactables: Array = []
var exits: Array = []          # [{pos: Vector3, radius, to: String, label}]
var props_root: Node3D
var enemies_root: Node3D
var items_root: Node3D
var fx_root: Node3D
var stone_xf: Array = []
var rock_xf := {}               # variant -> Array of transforms
var theme := {}

func _init() -> void:
	props_root = Models.N(self, "Props")
	enemies_root = Models.N(self, "Enemies")
	items_root = Models.N(self, "Items")
	fx_root = Models.N(self, "FX")

# ---------------------------------------------------------------- queries
func in_bounds(x: float, z: float) -> bool:
	return bounds.has_point(Vector2(x, z))

func height_at(x: float, z: float) -> float:
	if flat_floor:
		return 0.0
	var inner := hnoise.get_noise_2d(x, z) * 0.35
	var dx := maxf(bounds.position.x - x, x - bounds.end.x)
	var dz := maxf(bounds.position.y - z, z - bounds.end.y)
	var e := maxf(dx, dz)
	var hill := smoothstep(-4.0, 14.0, e) * (7.0 + hill_noise.get_noise_2d(x * 0.6, z * 0.6) * 5.0)
	# keep the camera side (south, +z) lower so it never blocks the view
	if z > bounds.end.y - 2.0:
		hill *= 0.35
	return inner + hill

var mask_o := Vector2.ZERO
var mask_w := 0
var mask_h := 0
var dirt_mask := PackedFloat32Array()
var cob_mask := PackedFloat32Array()
var masks_ready := false

func _bake_masks() -> void:
	mask_o = bounds.position - Vector2(MARGIN + 2, MARGIN + 2)
	mask_w = int(bounds.size.x + MARGIN * 2 + 5)
	mask_h = int(bounds.size.y + MARGIN * 2 + 5)
	dirt_mask.resize(mask_w * mask_h)
	dirt_mask.fill(0.0)
	cob_mask.resize(mask_w * mask_h)
	cob_mask.fill(0.0)
	_bake_blobs(dirt_blobs, dirt_mask, 0.55)
	_bake_blobs(cobble_blobs, cob_mask, 0.5)
	for l in dirt_lines:
		var a: Vector2 = l[0]
		var b: Vector2 = l[1]
		var wdt: float = l[2]
		var lo := Vector2(minf(a.x, b.x), minf(a.y, b.y)) - Vector2(wdt + 1, wdt + 1) - mask_o
		var hi := Vector2(maxf(a.x, b.x), maxf(a.y, b.y)) + Vector2(wdt + 1, wdt + 1) - mask_o
		for y in range(maxi(0, int(lo.y)), mini(mask_h, int(hi.y) + 1)):
			for x in range(maxi(0, int(lo.x)), mini(mask_w, int(hi.x) + 1)):
				var p := mask_o + Vector2(x, y)
				var cp := Geometry2D.get_closest_point_to_segment(p, a, b)
				var v := 1.0 - smoothstep(wdt * 0.4, wdt, p.distance_to(cp))
				var k := y * mask_w + x
				if v > dirt_mask[k]:
					dirt_mask[k] = v
	masks_ready = true

func _bake_blobs(list: Array, mask: PackedFloat32Array, inner: float) -> void:
	for bl in list:
		var c: Vector2 = bl[0]
		var r: float = bl[1]
		var st: float = bl[2]
		if r > 1000.0:
			mask.fill(st)
			continue
		var lo := c - Vector2(r + 1, r + 1) - mask_o
		var hi := c + Vector2(r + 1, r + 1) - mask_o
		for y in range(maxi(0, int(lo.y)), mini(mask_h, int(hi.y) + 1)):
			for x in range(maxi(0, int(lo.x)), mini(mask_w, int(hi.x) + 1)):
				var p := mask_o + Vector2(x, y)
				var v := (1.0 - smoothstep(r * inner, r, p.distance_to(c))) * st
				var k := y * mask_w + x
				if v > mask[k]:
					mask[k] = v

func _sample(mask: PackedFloat32Array, x: float, z: float) -> float:
	var fx := x - mask_o.x
	var fz := z - mask_o.y
	var ix := int(floor(fx))
	var iz := int(floor(fz))
	if ix < 0 or iz < 0 or ix >= mask_w - 1 or iz >= mask_h - 1:
		return 0.0
	var tx := fx - ix
	var tz := fz - iz
	var k := iz * mask_w + ix
	return lerpf(lerpf(mask[k], mask[k + 1], tx), lerpf(mask[k + mask_w], mask[k + mask_w + 1], tx), tz)

func dirt_at(x: float, z: float) -> float:
	if masks_ready:
		return _sample(dirt_mask, x, z)
	var v := 0.0
	var p := Vector2(x, z)
	for b in dirt_blobs:
		var d: float = p.distance_to(b[0])
		v = maxf(v, (1.0 - smoothstep(b[1] * 0.55, b[1], d)) * b[2])
	for l in dirt_lines:
		var a: Vector2 = l[0]
		var bb: Vector2 = l[1]
		var cp := Geometry2D.get_closest_point_to_segment(p, a, bb)
		var d2 := p.distance_to(cp)
		v = maxf(v, 1.0 - smoothstep(l[2] * 0.4, l[2], d2))
	return v

func cobble_at(x: float, z: float) -> float:
	if masks_ready:
		return _sample(cob_mask, x, z)
	var v := 0.0
	var p := Vector2(x, z)
	for b in cobble_blobs:
		var d: float = p.distance_to(b[0])
		v = maxf(v, (1.0 - smoothstep(b[1] * 0.5, b[1], d)) * b[2])
	return v

func _cell(x: float, z: float) -> Vector2i:
	return Vector2i(int(floor((x - origin.x) / CELL)), int(floor((z - origin.y) / CELL)))

func is_blocked(x: float, z: float) -> bool:
	var c := _cell(x, z)
	if c.x < 0 or c.y < 0 or c.x >= gw or c.y >= gh:
		return true
	return blocked[c.y * gw + c.x] != 0

func move(pos: Vector3, d: Vector3) -> Vector3:
	var np := pos + d
	if not is_blocked(np.x, np.z):
		pass
	elif not is_blocked(pos.x + d.x, pos.z):
		np = Vector3(pos.x + d.x, pos.y, pos.z)
	elif not is_blocked(pos.x, pos.z + d.z):
		np = Vector3(pos.x, pos.y, pos.z + d.z)
	else:
		np = pos
	np.y = height_at(np.x, np.z)
	return np

func los(a: Vector3, b: Vector3) -> bool:
	var d := Vector2(b.x - a.x, b.z - a.z)
	var n := int(d.length() / 0.4) + 1
	for i in range(1, n):
		var t := float(i) / n
		if is_blocked(a.x + d.x * t, a.z + d.y * t):
			return false
	return true

func nearest_free(x: float, z: float) -> Vector2i:
	var c := _cell(x, z)
	for r in range(0, 6):
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				var cc := c + Vector2i(dx, dy)
				if cc.x >= 0 and cc.y >= 0 and cc.x < gw and cc.y < gh and blocked[cc.y * gw + cc.x] == 0:
					return cc
	return c

func find_path(a: Vector3, b: Vector3) -> PackedVector3Array:
	var out := PackedVector3Array()
	if los(a, b):
		out.append(b)
		return out
	var ca := nearest_free(a.x, a.z)
	var cb := nearest_free(b.x, b.z)
	if not astar.is_in_boundsv(ca) or not astar.is_in_boundsv(cb):
		return out
	var pts := astar.get_point_path(ca, cb)
	if pts.is_empty():
		return out
	var raw := PackedVector3Array()
	for p in pts:
		raw.append(Vector3(p.x, 0, p.y))
	raw[raw.size() - 1] = Vector3(b.x, 0, b.z) if not is_blocked(b.x, b.z) else raw[raw.size() - 1]
	# string pulling
	var cur := a
	var i := 0
	while i < raw.size():
		var far := i
		for j in range(raw.size() - 1, i, -1):
			if los(cur, raw[j]):
				far = j
				break
		cur = raw[far]
		cur.y = height_at(cur.x, cur.z)
		out.append(cur)
		i = far + 1
	return out

# ---------------------------------------------------------------- obstacle registration
func add_circle(p: Vector3, r: float) -> void:
	obstacles.append([Vector2(p.x, p.z), r])

func add_box(p: Vector3, half: Vector2, yaw: float) -> void:
	# stored as a rotated rectangle
	obstacles.append([Vector2(p.x, p.z), -1.0, half, yaw])

func _rasterize() -> void:
	origin = bounds.position - Vector2(2, 2)
	gw = int(ceil((bounds.size.x + 4) / CELL))
	gh = int(ceil((bounds.size.y + 4) / CELL))
	blocked.resize(gw * gh)
	blocked.fill(0)
	for y in gh:
		for x in gw:
			var wx := origin.x + (x + 0.5) * CELL
			var wz := origin.y + (y + 0.5) * CELL
			if not bounds.grow(-1.0).has_point(Vector2(wx, wz)):
				blocked[y * gw + x] = 1
	var pad := 0.45
	for o in obstacles:
		var c: Vector2 = o[0]
		if o[1] > 0.0:
			var r: float = o[1] + pad
			var c0 := _cell(c.x - r, c.y - r)
			var c1 := _cell(c.x + r, c.y + r)
			for y in range(max(c0.y, 0), min(c1.y + 1, gh)):
				for x in range(max(c0.x, 0), min(c1.x + 1, gw)):
					var wp := origin + Vector2(x + 0.5, y + 0.5) * CELL
					if wp.distance_to(c) <= r:
						blocked[y * gw + x] = 1
		else:
			var half: Vector2 = o[2] + Vector2(pad, pad)
			var yaw: float = o[3]
			var ext := half.length()
			var c0 := _cell(c.x - ext, c.y - ext)
			var c1 := _cell(c.x + ext, c.y + ext)
			for y in range(max(c0.y, 0), min(c1.y + 1, gh)):
				for x in range(max(c0.x, 0), min(c1.x + 1, gw)):
					var wp := origin + Vector2(x + 0.5, y + 0.5) * CELL
					var lp := (wp - c).rotated(yaw)
					if absf(lp.x) <= half.x and absf(lp.y) <= half.y:
						blocked[y * gw + x] = 1
	astar = AStarGrid2D.new()
	astar.region = Rect2i(0, 0, gw, gh)
	astar.cell_size = Vector2(CELL, CELL)
	astar.offset = origin + Vector2(0.5, 0.5) * CELL
	astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	astar.default_compute_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	astar.default_estimate_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	astar.update()
	for y in gh:
		for x in gw:
			if blocked[y * gw + x] != 0:
				astar.set_point_solid(Vector2i(x, y), true)

func free_spot_near(p: Vector3, radius: float) -> Vector3:
	for i in 30:
		var a := rng.randf() * TAU
		var r := rng.randf() * radius
		var q := p + Vector3(cos(a) * r, 0, sin(a) * r)
		if not is_blocked(q.x, q.z):
			q.y = height_at(q.x, q.z)
			return q
	return p

## Splits instances into map chunks so culling and draw distance work per chunk.
func mm_chunked(mesh: Mesh, xforms: Array, shadows := true, chunk := 28.0, vis_end := 0.0, mat: Material = null) -> Array:
	var buckets := {}
	for t in xforms:
		var o: Vector3 = (t as Transform3D).origin
		var k := Vector2i(int(floor(o.x / chunk)), int(floor(o.z / chunk)))
		if not buckets.has(k):
			buckets[k] = []
		buckets[k].append(t)
	var out := []
	for k in buckets.keys():
		var mmi := Props.multimesh(props_root, mesh, buckets[k], shadows)
		if vis_end > 0.0:
			mmi.visibility_range_end = vis_end
			mmi.visibility_range_end_margin = 6.0
			mmi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_DISABLED
		if mat:
			mmi.material_override = mat
		out.append(mmi)
	return out

# ---------------------------------------------------------------- terrain
func _build_terrain(tcol: Dictionary) -> void:
	if not masks_ready:
		_bake_masks()
	var x0 := bounds.position.x - MARGIN
	var z0 := bounds.position.y - MARGIN
	var nx := int((bounds.size.x + MARGIN * 2.0) / 1.0)
	var nz := int((bounds.size.y + MARGIN * 2.0) / 1.0)
	var step := 1.0
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var cols := PackedColorArray()
	var idx := PackedInt32Array()
	verts.resize((nx + 1) * (nz + 1))
	norms.resize(verts.size())
	cols.resize(verts.size())
	var hs := PackedFloat32Array()
	hs.resize((nx + 3) * (nz + 3))
	for j in nz + 3:
		for i in nx + 3:
			hs[j * (nx + 3) + i] = height_at(x0 + (i - 1) * step, z0 + (j - 1) * step)
	for j in nz + 1:
		for i in nx + 1:
			var x := x0 + i * step
			var z := z0 + j * step
			var k := j * (nx + 1) + i
			var hc := hs[(j + 1) * (nx + 3) + (i + 1)]
			var hl := hs[(j + 1) * (nx + 3) + i]
			var hr := hs[(j + 1) * (nx + 3) + (i + 2)]
			var hd := hs[j * (nx + 3) + (i + 1)]
			var hu := hs[(j + 2) * (nx + 3) + (i + 1)]
			verts[k] = Vector3(x, hc, z)
			norms[k] = Vector3(hl - hr, 2.0 * step, hd - hu).normalized()
			var cliff := clampf((1.0 - norms[k].y) * 3.0, 0.0, 1.0)
			cols[k] = Color(dirt_at(x, z), cliff, cobble_at(x, z), 1.0)
	for j in nz:
		for i in nx:
			var a := j * (nx + 1) + i
			var b := a + 1
			var c := a + (nx + 1)
			var d := c + 1
			idx.append_array([a, b, d, a, d, c])
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_NORMAL] = norms
	arr[Mesh.ARRAY_COLOR] = cols
	arr[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	var mat := ShaderMaterial.new()
	mat.shader = Mats.shader("terrain")
	for k in tcol.keys():
		mat.set_shader_parameter(k, tcol[k])
	mesh.surface_set_material(0, mat)
	var mi := MeshInstance3D.new()
	mi.name = "Terrain"
	mi.mesh = mesh
	add_child(mi)
	# Godot culls clockwise as front; flip if our winding is inverted
	mi.set_meta("terrain", true)

## Grass, wildflowers and ferns use their own random numbers so a denser graphics setting
## never shifts anything gameplay-related (co-op players can use different settings).
func _scatter_grass(count: int, colors: Dictionary, height: float, outside := true) -> void:
	# The browser build (WebGL) shows no 3D at all once the grass blades are in the scene,
	# so it goes without them; ferns, trees and the painted ground still read as a meadow.
	if OS.has_feature("web"):
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = int(bounds.size.x * 1000.0) + count
	count = int(count * GRASS_DENSITY[clampi(detail, 0, 3)])
	var xf := []
	var area := bounds.grow(MARGIN * 0.6 if outside else 0.0)
	var tries := count * 3
	var n2 := FastNoiseLite.new()
	n2.seed = rng.randi()
	n2.frequency = 0.08
	while xf.size() < count and tries > 0:
		tries -= 1
		var x := rng.randf_range(area.position.x, area.end.x)
		var z := rng.randf_range(area.position.y, area.end.y)
		var dm := dirt_at(x, z) + cobble_at(x, z)
		if dm > 0.55 or rng.randf() < dm * 1.6:
			continue
		if n2.get_noise_2d(x, z) < -0.35 and rng.randf() < 0.7:
			continue
		if bounds.grow(-1.2).has_point(Vector2(x, z)) and is_blocked(x, z):
			continue
		var y := height_at(x, z)
		var s := rng.randf_range(0.7, 1.35) * (1.0 - dm * 0.6)
		xf.append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(s, s * rng.randf_range(0.8, 1.3), s)), Vector3(x, y - 0.02, z)))
	# five clump shapes; about one in fourteen carries wildflowers
	var m := Flora.grass_mat(colors)
	var h := height * 1.1
	var clumps := [Flora.grass_clump(1, 16, h), Flora.grass_clump(2, 18, h * 1.1), Flora.grass_clump(3, 14, h * 0.9), Flora.grass_clump(4, 15, h, 2), Flora.grass_clump(5, 15, h, 3)]
	var parts := [[], [], [], [], []]
	for i in xf.size():
		var k := i % 3
		if rng.randf() < 0.07:
			k = 3 + (i % 2)
		parts[k].append(xf[i])
	for k in parts.size():
		for mmi in mm_chunked(clumps[k], parts[k], detail >= 3, 20.0, 60.0, m):
			mmi.add_to_group("grass")

## Ferns gather in the shade along the forest edges and between trees.
func _scatter_ferns(count: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = int(bounds.size.y * 1000.0) + count
	count = int(count * GRASS_DENSITY[clampi(detail, 0, 3)])
	var xf := []
	var area := bounds.grow(MARGIN * 0.5)
	var tries := count * 6
	while xf.size() < count and tries > 0:
		tries -= 1
		var x := rng.randf_range(area.position.x, area.end.x)
		var z := rng.randf_range(area.position.y, area.end.y)
		if dirt_at(x, z) + cobble_at(x, z) > 0.2:
			continue
		var inside := bounds.grow(-1.5).has_point(Vector2(x, z))
		if inside and (is_blocked(x, z) or rng.randf() < 0.6):
			continue
		xf.append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * rng.randf_range(0.7, 1.35)), Vector3(x, height_at(x, z) - 0.03, z)))
	var parts := [[], []]
	for i in xf.size():
		parts[i % 2].append(xf[i])
	for k in 2:
		for mmi in mm_chunked(Flora.fern(k + 1), parts[k], true, 24.0, 60.0):
			mmi.add_to_group("grass")

func _flush_stones(mat: Material) -> void:
	if stone_xf.size() > 0:
		for v in 4:
			var part := []
			for i in range(v, stone_xf.size(), 4):
				part.append(stone_xf[i])
			mm_chunked(Props.rock_mesh(40 + v, 0.22), part, true, 32.0, 0.0, mat)
	for v in rock_xf.keys():
		mm_chunked(Props.rock_mesh(v, 0.38), rock_xf[v], true, 32.0, 0.0, Props.stone())

func _rock(p: Vector3, s: float, collide := true) -> void:
	var v := rng.randi_range(0, 7)
	if not rock_xf.has(v):
		rock_xf[v] = []
	var y := height_at(p.x, p.z)
	rock_xf[v].append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(s * rng.randf_range(0.9, 1.4), s * rng.randf_range(0.6, 1.0), s)), Vector3(p.x, y + s * 0.05, p.z)))
	if collide and s > 0.6:
		add_circle(p, s * 0.55)

func _wall(a: Vector3, b: Vector3, height: float = 1.1) -> void:
	a.y = 0.0
	b.y = 0.0
	var base := stone_xf.size()
	stone_xf.append_array(Props.wall_stones(a, b, height, rng))
	for i in range(base, stone_xf.size()):
		var t: Transform3D = stone_xf[i]
		t.origin.y += height_at(t.origin.x, t.origin.z)
		stone_xf[i] = t
	var d := b - a
	var mid := (a + b) * 0.5
	add_box(mid, Vector2(0.45, d.length() * 0.5), atan2(d.x, d.z))

func _place(node: Node3D, p: Vector3) -> Node3D:
	if node.get_parent() == null:
		props_root.add_child(node)
	node.position = Vector3(p.x, height_at(p.x, p.z), p.z)
	return node

func _inter(kind_s: String, label_s: String, p: Vector3, radius: float, model: Node3D = null, data := {}) -> Inter:
	var it := Inter.new()
	it.kind = kind_s
	it.label = label_s
	it.radius = radius
	it.data = data
	add_child(it)
	it.position = Vector3(p.x, height_at(p.x, p.z), p.z)
	if model:
		model.name = "Model"
		if model.get_parent():
			model.get_parent().remove_child(model)
		it.add_child(model)
		model.position = Vector3.ZERO
	interactables.append(it)
	return it

func _npc(label_s: String, look: Dictionary, p: Vector3, role: String, yaw := 0.0) -> Inter:
	var rig := Models.humanoid(look)
	var it := _inter("vendor", label_s, p, 1.4, null, {"role": role, "offset": rng.randf() * 9.0})
	it.add_child(rig)
	rig.rotation.y = yaw
	it.rig = rig
	add_circle(p, 0.45)
	return it

# ---------------------------------------------------------------- zone builders
func build(act_i: int, kind_s: String, seed_v: int) -> void:
	act = act_i
	kind = kind_s
	level = Data.zone_level(act, kind)
	rng.seed = seed_v
	hnoise.seed = seed_v
	hnoise.frequency = 0.035
	hill_noise.seed = seed_v + 11
	hill_noise.frequency = 0.03
	hill_noise.fractal_octaves = 4
	match kind:
		"town": _build_town()
		"wild": _build_wild()
		"lair": _build_lair()

const MOOR_TERRAIN := {
	"col_a": Color(0.15, 0.2, 0.08), "col_b": Color(0.21, 0.23, 0.11), "col_accent": Color(0.28, 0.3, 0.13),
	"col_path": Color(0.25, 0.21, 0.16), "col_cliff": Color(0.3, 0.3, 0.28), "wet": 0.3,
}
const MOOR_GRASS := {"base_col": Color(0.12, 0.16, 0.06), "tip_col": Color(0.27, 0.32, 0.13), "dry_col": Color(0.36, 0.35, 0.18), "wind": 1.0}

func _build_town() -> void:
	bounds = Rect2(-38, -42, 76, 80)
	theme = {"name": "town"}
	var V: Dictionary = Data.VENDORS[act]
	# --- worn ground
	dirt_blobs = [
		[Vector2(0, 0), 9.0, 1.0], [Vector2(-14, -11), 7.5, 1.0], [Vector2(13, -11), 7.5, 1.0],
		[Vector2(17, 7), 6.0, 0.95], [Vector2(-17, 9), 6.0, 0.95], [Vector2(-8, 6), 4.5, 0.9],
		[Vector2(0, -25), 5.0, 0.9], [Vector2(-25, -1), 4.0, 0.8], [Vector2(24, -21), 4.0, 0.8],
		[Vector2(6, 16), 3.5, 0.7], [Vector2(-5, 22), 3.0, 0.6],
	]
	dirt_lines = [
		[Vector2(0, 0), Vector2(0, -40), 3.0], [Vector2(0, 0), Vector2(-14, -11), 2.6], [Vector2(0, 0), Vector2(13, -11), 2.6],
		[Vector2(0, 0), Vector2(17, 7), 2.4], [Vector2(0, 0), Vector2(-17, 9), 2.4], [Vector2(0, 0), Vector2(4, 30), 2.2],
	]
	cobble_blobs = [
		[Vector2(1, -2), 4.5, 0.85], [Vector2(-1, -27), 3.0, 0.8], [Vector2(-12, -9), 2.2, 0.6],
		[Vector2(14, -8), 2.0, 0.55], [Vector2(0.5, -36), 2.6, 0.9],
	]
	var wy := -36.0
	var wx := 33.0
	# --- dry stone wall around camp with a north gate and a broken gap
	_wall(Vector3(-wx, 0, wy), Vector3(-3.5, 0, wy), 1.2)
	_wall(Vector3(3.5, 0, wy), Vector3(wx, 0, wy), 1.2)
	_wall(Vector3(-wx, 0, wy), Vector3(-wx, 0, -4), 1.1)
	_wall(Vector3(-wx, 0, 2), Vector3(-wx, 0, 30), 1.1)
	_wall(Vector3(wx, 0, wy), Vector3(wx, 0, 30), 1.1)
	_wall(Vector3(-wx, 0, 30), Vector3(-6, 0, 33), 0.9)
	_wall(Vector3(8, 0, 33), Vector3(wx, 0, 30), 0.9)
	# gate posts
	for gx in [-4.2, 4.2]:
		var post := Models.N(null, "gatepost")
		Models.seg(post, Vector3.ZERO, Vector3(0, 3.4, 0), 0.22, 0.18, Props.wood_dark(), 8)
		_place(post, Vector3(gx, 0, wy))
		add_circle(Vector3(gx, 0, wy), 0.3)
	var lintel := Models.N(null, "lintel")
	Models.seg(lintel, Vector3(-4.6, 3.2, 0), Vector3(4.6, 3.3, 0), 0.16, 0.16, Props.wood_dark(), 8)
	_place(lintel, Vector3(0, 0, wy))
	lintel.position.y = height_at(0, wy)
	Props.tripod_torch(props_root, Vector3(-5.5, height_at(-5.5, wy + 2.0), wy + 2.0))
	Props.tripod_torch(props_root, Vector3(5.5, height_at(5.5, wy + 2.0), wy + 2.0))
	exits.append({"pos": Vector3(0, 0, wy - 3.0), "radius": 3.5, "to": "wild", "label": Data.ACTS[act]["wild"]})

	# --- centre: campfire, stash, waypoint
	var cf := Props.campfire(props_root, Vector3(0, height_at(0, 0), 0))
	add_circle(Vector3.ZERO, 1.0)
	var chest := Props.stash_chest(null, Vector3.ZERO, -15.0)
	_inter("stash", "Stash", Vector3(3.6, 0, 2.6), 1.6, chest)
	add_box(Vector3(3.6, 0, 2.6), Vector2(0.7, 0.45), deg_to_rad(15.0))
	var wp := Props.waypoint(null, Vector3.ZERO)
	_inter("waypoint", "Waypoint", Vector3(-8, 0, 6), 2.4, wp)
	for i in 4:
		var a := TAU * i / 4.0 + PI * 0.25
		add_circle(Vector3(-8 + cos(a) * 1.85, 0, 6 + sin(a) * 1.85), 0.3)
	# log seats around fire
	for i in 3:
		var a := TAU * i / 3.0 + 0.4
		var lg := Models.N(null, "seat")
		Models.P(lg, Geo.cyl(0.22, 0.24, 1.6, 10), Props.wood(), Vector3(0, 0.2, 0), Vector3(90, 0, 0))
		_place(lg, Vector3(cos(a) * 3.2, 0, sin(a) * 3.2))
		lg.rotation.y = -a
		add_box(Vector3(cos(a) * 3.2, 0, sin(a) * 3.2), Vector2(0.25, 0.8), a)

	# --- alchemist's camp (reference: hide tent, pottery, tripod torches)
	var ac := Vector2(-14, -12)
	Props.hide_tent(props_root, Vector3(ac.x, height_at(ac.x, ac.y - 1.5), ac.y - 1.5), 6.0, 3.6, 4.0, 2.6)
	burn_points.append([Vector3(ac.x + 1.0, height_at(ac.x, ac.y - 1.5) + 1.6, ac.y - 1.5), 1.4])
	add_box(Vector3(ac.x, 0, ac.y - 1.5), Vector2(2.0, 2.2), deg_to_rad(-6.0))
	for tp in [Vector2(-6.0, 1.5), Vector2(6.5, 0.5), Vector2(-1.5, 6.0)]:
		var tpp := Vector3(ac.x + tp.x, 0, ac.y + tp.y)
		Props.tripod_torch(props_root, Vector3(tpp.x, height_at(tpp.x, tpp.z), tpp.z), tp.x < 0 and tp.y < 3.0)
		add_circle(tpp, 0.35)
	var pot_spots := [
		Vector2(-3.6, -0.6), Vector2(-3.1, 0.1), Vector2(-4.2, 0.4), Vector2(-3.5, 1.0), Vector2(-4.6, -0.3), Vector2(-2.6, 0.9),
		Vector2(3.0, -1.6), Vector2(3.6, -1.0), Vector2(4.3, -1.7), Vector2(3.4, -0.2), Vector2(4.8, -0.6), Vector2(2.6, -0.7), Vector2(5.2, -1.4),
		Vector2(1.4, 1.2), Vector2(-1.0, 1.6),
	]
	var pi := 0
	for ps in pot_spots:
		var pp := Vector3(ac.x + ps.x, 0, ac.y + ps.y)
		Props.pot(props_root, Vector3(pp.x, height_at(pp.x, pp.z), pp.z), pi, rng.randf_range(0.75, 1.25))
		pi += 1
	add_box(Vector3(ac.x - 3.6, 0, ac.y + 0.2), Vector2(1.2, 1.0), 0.0)
	add_box(Vector3(ac.x + 3.8, 0, ac.y - 1.0), Vector2(1.6, 0.9), 0.0)
	var cpos := Vector3(ac.x + 4.6, 0, ac.y + 1.4)
	Props.cauldron(props_root, Vector3(cpos.x, height_at(cpos.x, cpos.z), cpos.z), Color(0.35, 0.9, 0.25))
	add_circle(cpos, 0.5)
	# bowls of herbs / red berries, skull on a stake
	for i in 3:
		var bp := Vector3(ac.x + 2.2 + i * 0.6, 0, ac.y + 0.4 + (i % 2) * 0.4)
		var bowl := Props.pot(props_root, Vector3(bp.x, height_at(bp.x, bp.z), bp.z), 2, 0.9)
		var fill := Mats.world(Color(0.55, 0.08, 0.06) if i != 1 else Color(0.3, 0.42, 0.14), Color(0.35, 0.05, 0.04), 0.7, 6.0, 0.0, Props.MOSS, false)
		Models.P(bowl, Geo.sph(0.22, 10, 0.5), fill, Vector3(0, 0.06, 0), Vector3.ZERO, Vector3(1.0, 0.35, 1.0))
	var stake := Models.N(null, "stake")
	Models.seg(stake, Vector3.ZERO, Vector3(0, 1.5, 0), 0.04, 0.03, Props.wood_dark(), 6)
	Models.P(stake, Geo.sph(0.12, 10), Mats.world(Color(0.8, 0.76, 0.66), Color(0.6, 0.55, 0.45), 0.7, 3.0, 0.0, Props.MOSS, false), Vector3(0, 1.58, 0), Vector3.ZERO, Vector3(0.9, 1.0, 1.1))
	_place(stake, Vector3(ac.x + 0.8, 0, ac.y + 0.5))
	var lumber := Models.N(null, "lumber")
	for i in 4:
		Models.P(lumber, Geo.box(0.12, 0.08, 1.4), Props.wood(), Vector3(i * 0.05, 0.05 + i * 0.07, i * 0.1), Vector3(0, i * 9, 0))
	_place(lumber, Vector3(ac.x + 2.5, 0, ac.y - 3.6))
	var alch_look := {"skin": Color(0.72, 0.56, 0.46), "cloth": Color(0.32, 0.12, 0.42), "cloth2": Color(0.14, 0.05, 0.18), "head": "hood", "eyes": Color(0.8, 0.7, 1.0), "robe": true, "height": 0.98, "bulk": 0.9}
	alch_look.erase("eyes")
	_npc(V["alch"], alch_look, Vector3(ac.x - 1.2, 0, ac.y + 3.2), "alch", 0.4)

	# --- blacksmith's forge
	var fc := Vector3(14, 0, -12.5)
	Props.forge(props_root, Vector3(fc.x, height_at(fc.x, fc.z), fc.z), 0.0)
	burn_points.append([Vector3(fc.x - 1.2, height_at(fc.x, fc.z) + 2.4, fc.z - 0.6), 1.2])
	add_box(Vector3(fc.x, 0, fc.z - 1.5), Vector2(2.3, 0.6), 0.0)
	add_box(Vector3(fc.x - 1.0, 0, fc.z - 1.2), Vector2(0.9, 0.7), 0.0)
	add_circle(fc + Vector3(0.6, 0, 0.1), 0.45)
	add_circle(fc + Vector3(1.6, 0, -0.9), 0.4)
	add_circle(fc + Vector3(1.7, 0, 1.0), 0.45)
	add_box(fc + Vector3(-1.4, 0, 1.3), Vector2(0.9, 0.2), 0.0)
	for x in [-2.2, 2.2]:
		for z in [-1.6, 1.6]:
			add_circle(fc + Vector3(x, 0, z), 0.2)
	_npc(V["smith"], {"skin": Color(0.7, 0.5, 0.4), "cloth": Color(0.25, 0.2, 0.17), "cloth2": Color(0.32, 0.22, 0.14), "head": "human", "hair": Color(0.1, 0.08, 0.06), "beard": Color(0.12, 0.09, 0.07), "bulk": 1.25, "belly": true}, fc + Vector3(-0.2, 0, 1.6), "smith", 0.2)
	Props.barrel(props_root, Vector3(fc.x + 3.2, height_at(fc.x + 3.2, fc.z + 2.0), fc.z + 2.0))
	add_circle(fc + Vector3(3.2, 0, 2.0), 0.35)
	Props.log_pile(props_root, Vector3(fc.x - 3.8, height_at(fc.x - 3.8, fc.z), fc.z))
	add_box(fc + Vector3(-3.8, 0, 0), Vector2(0.6, 0.8), 0.0)

	# --- armorer's stall (east, facing the fire)
	var arm_c := Vector3(18.5, 0, 7)
	Props.armory(props_root, Vector3(arm_c.x, height_at(arm_c.x, arm_c.z), arm_c.z), -90.0)
	burn_points.append([Vector3(arm_c.x + 0.8, height_at(arm_c.x, arm_c.z) + 2.2, arm_c.z + 1.0), 1.1])
	add_box(arm_c + Vector3(0.6, 0, 0), Vector2(1.8, 2.1), PI * 0.5)
	add_circle(arm_c + Vector3(-1.5, 0, -2.7), 0.35)
	_npc(V["armor"], {"skin": Color(0.82, 0.66, 0.54), "cloth": Color(0.3, 0.32, 0.36), "cloth2": Color(0.22, 0.16, 0.12), "armor": Color(0.55, 0.56, 0.58), "head": "human", "hair": Color(0.75, 0.6, 0.35), "height": 0.97}, arm_c + Vector3(-2.2, 0, 0.0), "armor", -PI * 0.5)

	# --- gambler's tent (south-west)
	var gc := Vector3(-17, 0, 10)
	Props.gamble_tent(props_root, Vector3(gc.x, height_at(gc.x, gc.z), gc.z))
	burn_points.append([Vector3(gc.x - 0.8, height_at(gc.x, gc.z) + 2.0, gc.z - 0.8), 1.3])
	add_circle(gc + Vector3(0, 0, -0.6), 2.3)
	add_circle(gc + Vector3(0, 0, 1.2), 0.75)
	_npc(V["gamble"], {"skin": Color(0.68, 0.5, 0.38), "cloth": Color(0.45, 0.32, 0.08), "cloth2": Color(0.25, 0.08, 0.06), "head": "human", "hair": Color(0.05, 0.05, 0.05), "beard": Color(0.05, 0.05, 0.05), "cape": Color(0.3, 0.06, 0.08)}, gc + Vector3(1.1, 0, 2.0), "gamble", 0.6)

	# --- captain near the gate
	_npc(V["elder"], {"skin": Color(0.76, 0.58, 0.46), "cloth": Color(0.25, 0.18, 0.14), "armor": Color(0.5, 0.48, 0.45), "head": "human", "hair": Color(0.4, 0.38, 0.36), "beard": Color(0.45, 0.42, 0.4), "cape": Color(0.35, 0.06, 0.05), "spikes": false}, Vector3(3.5, 0, -27), "elder", 0.0)

	# --- tents, carts, crates, barrels, banners around the camp
	var tents := [[Vector2(-26, -4), 80.0], [Vector2(25, -22), -120.0], [Vector2(-5, -18), 15.0], [Vector2(26, 20), -150.0], [Vector2(-25, 22), 140.0]]
	for tdef in tents:
		var tp2: Vector2 = tdef[0]
		Props.hide_tent(props_root, Vector3(tp2.x, height_at(tp2.x, tp2.y), tp2.y), tdef[1], rng.randf_range(2.6, 3.2), rng.randf_range(3.0, 3.6), rng.randf_range(2.0, 2.4))
		burn_points.append([Vector3(tp2.x, height_at(tp2.x, tp2.y) + 1.4, tp2.y), 1.25])
		add_circle(Vector3(tp2.x, 0, tp2.y), 2.0)
	var clutter := [
		["crate", Vector2(-7.5, -16)], ["crate", Vector2(-8.3, -15.2)], ["barrel", Vector2(-3, -16.5)], ["barrel", Vector2(-2.4, -15.8)],
		["crate", Vector2(22, -18)], ["barrel", Vector2(22.6, -19)], ["logs", Vector2(-27, 3)], ["crate", Vector2(10, 18)],
		["barrel", Vector2(-10, 20)], ["crate", Vector2(28, 3)], ["logs", Vector2(9, -24)], ["barrel", Vector2(-21, -12)],
	]
	for c in clutter:
		var cp: Vector2 = c[1]
		var p3 := Vector3(cp.x, height_at(cp.x, cp.y), cp.y)
		match c[0]:
			"crate": Props.crate(props_root, p3, rng.randf_range(0.85, 1.15))
			"barrel": Props.barrel(props_root, p3)
			"logs": Props.log_pile(props_root, p3)
		add_circle(p3, 0.55 if c[0] != "logs" else 0.9)
	for bp2 in [Vector2(-5, -33), Vector2(5, -33), Vector2(-9, 2), Vector2(9, -3)]:
		Props.banner(props_root, Vector3(bp2.x, height_at(bp2.x, bp2.y), bp2.y), Color(0.42, 0.06, 0.05), Color(0.6, 0.5, 0.25))
		add_circle(Vector3(bp2.x, 0, bp2.y), 0.2)
	for tp3 in [Vector2(-6, -6), Vector2(7, -5), Vector2(5, 9), Vector2(-4, -22), Vector2(4, -20), Vector2(11, 3), Vector2(-11, 13)]:
		Props.tripod_torch(props_root, Vector3(tp3.x, height_at(tp3.x, tp3.y), tp3.y))
		add_circle(Vector3(tp3.x, 0, tp3.y), 0.35)

	# --- rocks, boulders and trees
	for i in 45:
		var p := Vector3(rng.randf_range(-31, 31), 0, rng.randf_range(-34, 30))
		if dirt_at(p.x, p.z) > 0.3 or is_near_obstacle(p, 2.0):
			continue
		_rock(p, rng.randf_range(0.25, 0.7), false)
	for p4 in [Vector3(-22, 0, 16), Vector3(27, 0, -6), Vector3(14, 0, 22), Vector3(-28, 0, -26), Vector3(20, 0, -30), Vector3(-12, 0, 27)]:
		_rock(p4, rng.randf_range(1.0, 1.6))
	var dt_mesh := Flora.dead_tree(5)
	var oak_mesh := Flora.oak(9)
	var pine_meshes := [Flora.pine(1), Flora.pine(2), Flora.pine(3)]
	var inner_trees := []
	for p5 in [Vector3(-29, 0, -15), Vector3(29, 0, 12), Vector3(-20, 0, 27), Vector3(10, 0, 27)]:
		inner_trees.append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * rng.randf_range(0.9, 1.2)), Vector3(p5.x, height_at(p5.x, p5.z), p5.z)))
		add_circle(p5, 0.45)
	Props.multimesh(props_root, oak_mesh, inner_trees)
	Props.multimesh(props_root, dt_mesh, [Transform3D(Basis(Vector3.UP, 1.0), Vector3(22, height_at(22, 13), 13)), Transform3D(Basis(Vector3.UP, 2.0), Vector3(-30, height_at(-30, 10), 10))])
	add_circle(Vector3(22, 0, 13), 0.35)
	add_circle(Vector3(-30, 0, 10), 0.35)
	# forest beyond the walls
	var pines := [[], [], []]
	for i in 260:
		var x := rng.randf_range(bounds.position.x - MARGIN + 4, bounds.end.x + MARGIN - 4)
		var z := rng.randf_range(bounds.position.y - MARGIN + 4, bounds.end.y + 6)
		if bounds.grow(-1.5).has_point(Vector2(x, z)):
			continue
		if absf(x) < 6 and z < bounds.position.y + 2:
			continue
		pines[i % 3].append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * rng.randf_range(0.8, 1.4)), Vector3(x, height_at(x, z) - 0.2, z)))
	for k in 3:
		Props.multimesh(props_root, pine_meshes[k], pines[k])
	for i in 70:
		var x := rng.randf_range(bounds.position.x - 20, bounds.end.x + 20)
		var z := rng.randf_range(bounds.position.y - 20, bounds.end.y + 10)
		if bounds.grow(-1.0).has_point(Vector2(x, z)):
			continue
		_rock(Vector3(x, 0, z), rng.randf_range(0.8, 2.6), false)

	_rasterize()
	_flush_stones(Props.stone())
	_build_terrain(MOOR_TERRAIN)
	_scatter_grass(60000, MOOR_GRASS, 0.3)
	_scatter_ferns(120)
	spawns["start"] = Vector3(0, 0, 6)
	spawns["from_wild"] = Vector3(0, 0, wy + 4.0)
	spawns["waypoint"] = Vector3(-8, 0, 9)
	spawns["portal"] = Vector3(4, 0, 9)
	spawns["alch"] = Vector3(-12.5, 0, -6.5)
	spawns["forge"] = Vector3(13, 0, -7)

func is_near_obstacle(p: Vector3, r: float) -> bool:
	for o in obstacles:
		if o[1] > 0.0:
			if Vector2(p.x, p.z).distance_to(o[0]) < o[1] + r:
				return true
		else:
			var lp: Vector2 = (Vector2(p.x, p.z) - o[0]).rotated(o[3])
			if absf(lp.x) < o[2].x + r and absf(lp.y) < o[2].y + r:
				return true
	return false

# ---------------------------------------------------------------- wilderness: Cairnfell Moor
var path_poly := PackedVector2Array()

func path_dist(x: float, z: float) -> float:
	var best := 1e9
	var p := Vector2(x, z)
	for i in path_poly.size() - 1:
		var cp := Geometry2D.get_closest_point_to_segment(p, path_poly[i], path_poly[i + 1])
		best = minf(best, p.distance_to(cp))
	return best

func _spline(ctrl: Array, steps: int) -> PackedVector2Array:
	var out := PackedVector2Array()
	for i in ctrl.size() - 1:
		var p0: Vector2 = ctrl[max(i - 1, 0)]
		var p1: Vector2 = ctrl[i]
		var p2: Vector2 = ctrl[i + 1]
		var p3: Vector2 = ctrl[min(i + 2, ctrl.size() - 1)]
		for s in steps:
			var t := float(s) / steps
			var t2 := t * t
			var t3 := t2 * t
			out.append(0.5 * ((2.0 * p1) + (-p0 + p2) * t + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t2 + (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * t3))
	out.append(ctrl[ctrl.size() - 1])
	return out

func _gravestone(p: Vector3, cross_ := false) -> void:
	var g := Models.N(null, "grave")
	var sm := Props.stone()
	if cross_:
		Models.P(g, Geo.box(0.16, 1.1, 0.14), sm, Vector3(0, 0.55, 0))
		Models.P(g, Geo.box(0.6, 0.14, 0.14), sm, Vector3(0, 0.78, 0))
	else:
		Models.P(g, Geo.box(0.55, 0.8, 0.16), sm, Vector3(0, 0.4, 0))
		Models.P(g, Geo.cyl(0.275, 0.275, 0.16, 10), sm, Vector3(0, 0.8, 0), Vector3(90, 0, 0))
	Models.P(g, Geo.box(0.7, 0.06, 1.5), Mats.world(Color(0.2, 0.17, 0.12), Color(0.15, 0.12, 0.08), 1.0, 2.0, 0.4, Props.MOSS), Vector3(0, 0.03, 0.8))
	_place(g, p)
	g.rotation = Vector3(rng.randf_range(-0.12, 0.12), rng.randf_range(-0.3, 0.3), rng.randf_range(-0.15, 0.15))
	add_circle(p, 0.35)

func _standing_stone(p: Vector3, h: float) -> void:
	var g := Models.N(null, "menhir")
	Models.P(g, Props.rock_mesh(rng.randi_range(0, 7), 0.25), Props.stone(), Vector3(0, h * 0.42, 0), Vector3.ZERO, Vector3(0.9, h, 0.6))
	_place(g, p)
	g.rotation = Vector3(rng.randf_range(-0.08, 0.08), rng.randf() * TAU, rng.randf_range(-0.08, 0.08))
	add_circle(p, 0.5)

func _shrine(p: Vector3, kind_s: String) -> void:
	var cols := {"healing": Color(1.0, 0.25, 0.2), "fury": Color(1.0, 0.6, 0.1), "armor": Color(0.4, 0.6, 1.0), "experience": Color(0.7, 0.4, 1.0)}
	var col: Color = cols[kind_s]
	var g := Node3D.new()
	var sm := Props.stone_clean()
	Models.P(g, Geo.cyl(0.9, 1.1, 0.3, 8), sm, Vector3(0, 0.15, 0))
	Models.P(g, Geo.cyl(0.35, 0.45, 1.2, 8), sm, Vector3(0, 0.9, 0))
	Models.P(g, Geo.lathe([Vector2(0.0, 0.0), Vector2(0.55, 0.05), Vector2(0.6, 0.18), Vector2(0.45, 0.22), Vector2(0.0, 0.15)], 12, "shrinebowl"), sm, Vector3(0, 1.5, 0))
	var orb := Models.P(g, Geo.sph(0.28, 14), Mats.glow(col, 3.0))
	orb.position = Vector3(0, 2.1, 0)
	orb.name = "orb"
	Models.P(g, Geo.sph(0.45, 14), Mats.glow(col, 0.8, 0.0, 1.0), Vector3(0, 2.1, 0))
	var l := OmniLight3D.new()
	l.light_color = col
	l.light_energy = 1.4
	l.omni_range = 6.0
	l.position = Vector3(0, 2.1, 0)
	l.name = "light"
	g.add_child(l)
	_inter("shrine", kind_s.capitalize() + " Shrine", p, 1.8, g, {"type": kind_s})
	add_circle(p, 0.9)

func _chest(p: Vector3) -> void:
	var c := Props.stash_chest(null, Vector3.ZERO, rng.randf_range(-40, 40))
	c.scale = Vector3.ONE * 0.75
	_inter("chest", "Chest", p, 1.4, c)
	add_circle(p, 0.5)

func _crypt_entrance(p: Vector3) -> void:
	var g := Models.N(null, "crypt")
	var sm := Props.stone()
	var sc := Props.stone_clean()
	Models.P(g, Geo.box(9.0, 0.5, 7.0), sc, Vector3(0, 0.25, -1.0))
	Models.P(g, Geo.box(7.0, 4.2, 4.5), sm, Vector3(0, 2.6, -2.2))
	Models.P(g, Geo.prism(8.0, 1.8, 5.2), sm, Vector3(0, 5.6, -2.2))
	Models.P(g, Geo.box(2.4, 3.0, 0.3), Mats.world(Color(0.01, 0.01, 0.01), Color(0.0, 0.0, 0.0), 1.0, 1.0, 0.0, Props.MOSS, false), Vector3(0, 2.0, 0.08))
	for i in 5:
		Models.P(g, Geo.box(3.2, 0.2, 0.6), sc, Vector3(0, 0.5 - i * 0.1, 0.4 + i * 0.6))
	for x in [-2.6, 2.6]:
		Models.P(g, Geo.cyl(0.4, 0.45, 4.6, 10), sc, Vector3(x, 2.8, 0.6))
		Models.P(g, Geo.box(1.1, 0.35, 1.1), sc, Vector3(x, 5.1, 0.6))
		Models.P(g, Geo.box(1.1, 0.35, 1.1), sc, Vector3(x, 0.65, 0.6))
	var rune := Mats.glow(Color(1.0, 0.15, 0.08), 2.5)
	for i in 5:
		Models.P(g, Geo.box(0.12, 0.35, 0.05), rune, Vector3(-0.9 + i * 0.45, 3.85, 0.1))
	_place(g, p)
	for x in [-4.0, 4.0]:
		var br := Models.N(null, "brazier")
		Models.P(br, Geo.cyl(0.08, 0.15, 1.0, 8), Props.iron(), Vector3(0, 0.5, 0))
		Models.P(br, Geo.lathe([Vector2(0.05, 0.0), Vector2(0.35, 0.1), Vector2(0.4, 0.3), Vector2(0.0, 0.2)], 12, "brazier"), Props.iron(), Vector3(0, 1.0, 0))
		_place(br, p + Vector3(x, 0, 2.2))
		Props.fire(br, Vector3(0, 1.3, 0), 1.0, Color(1.0, 0.45, 0.15), true, true)
		add_circle(p + Vector3(x, 0, 2.2), 0.5)
	add_box(p + Vector3(0, 0, -2.0), Vector2(4.6, 3.0), 0.0)
	exits.append({"pos": p + Vector3(0, 0, 1.2), "radius": 1.6, "to": "lair", "label": Data.ACTS[act]["lair"]})

func _build_wild() -> void:
	bounds = Rect2(-42, -214, 84, 216)
	theme = {"name": "wild"}
	var ctrl := [Vector2(0, 2), Vector2(0, -14)]
	var x := 0.0
	for i in 8:
		x = clampf(x + rng.randf_range(-18, 18), -26, 26)
		ctrl.append(Vector2(x, -36 - i * 21))
	ctrl.append(Vector2(clampf(x * 0.5, -15, 15), -202))
	path_poly = _spline(ctrl, 6)
	for i in path_poly.size() - 1:
		dirt_lines.append([path_poly[i], path_poly[i + 1], 4.2])
	for i in range(2, ctrl.size() - 1, 2):
		dirt_blobs.append([ctrl[i] + Vector2(rng.randf_range(-3, 3), rng.randf_range(-3, 3)), rng.randf_range(6, 9), 0.85])
	var end_p: Vector2 = ctrl[ctrl.size() - 1]
	dirt_blobs.append([end_p + Vector2(0, 3), 9.0, 1.0])
	cobble_blobs.append([end_p + Vector2(0, 4), 5.0, 0.9])
	exits.append({"pos": Vector3(0, 0, 0.5), "radius": 2.6, "to": "town", "label": Data.ACTS[act]["town"]})
	_crypt_entrance(Vector3(end_p.x, 0, end_p.y - 4.0))

	# landmarks
	var c3: Vector2 = ctrl[3]
	var circle_c := Vector2(clampf(c3.x + (12 if c3.x < 0 else -12), -34, 34), c3.y)
	cobble_blobs.append([circle_c, 4.0, 0.7])
	dirt_blobs.append([circle_c, 7.0, 0.7])
	for i in 8:
		var a := TAU * i / 8.0
		_standing_stone(Vector3(circle_c.x + cos(a) * 5.5, 0, circle_c.y + sin(a) * 5.5), rng.randf_range(2.2, 3.4))
	var c5: Vector2 = ctrl[5]
	var gy := Vector2(clampf(c5.x + (11 if c5.x < 0 else -11), -32, 32), c5.y + 4)
	for i in 14:
		var gp := gy + Vector2((i % 5) * 2.2 - 4.4 + rng.randf_range(-0.3, 0.3), (i / 5) * 2.8 + rng.randf_range(-0.3, 0.3))
		_gravestone(Vector3(gp.x, 0, gp.y), rng.randf() < 0.25)
	dirt_blobs.append([gy + Vector2(0, 2.5), 6.0, 0.5])
	var wpp: Vector2 = ctrl[4] + Vector2(6 if ctrl[4].x < 10 else -6, 0)
	_inter("waypoint", "Waypoint", Vector3(wpp.x, 0, wpp.y), 2.4, Props.waypoint(null, Vector3.ZERO), {"wp": "wild"})
	for i in 4:
		var a := TAU * i / 4.0 + PI * 0.25
		add_circle(Vector3(wpp.x + cos(a) * 1.85, 0, wpp.y + sin(a) * 1.85), 0.3)
	spawns["waypoint"] = Vector3(wpp.x, 0, wpp.y + 3.0)
	cobble_blobs.append([wpp, 3.0, 0.8])
	var kinds := ["healing", "fury", "armor", "experience"]
	kinds.shuffle()
	for i in 2:
		var cc: Vector2 = ctrl[2 + i * 4]
		var sp := Vector2(clampf(cc.x + (7 if i == 0 else -7), -34, 34), cc.y - 3)
		_shrine(Vector3(sp.x, 0, sp.y), kinds[i])
	for i in 4:
		var cc2: Vector2 = path_poly[int(path_poly.size() * (0.2 + i * 0.2))]
		var chp := Vector2(clampf(cc2.x + rng.randf_range(-9, 9), -36, 36), cc2.y + rng.randf_range(-4, 4))
		if path_dist(chp.x, chp.y) > 3.0:
			_chest(Vector3(chp.x, 0, chp.y))
	# ruined walls
	for i in 7:
		var cc3: Vector2 = path_poly[rng.randi_range(8, path_poly.size() - 10)]
		var off := Vector2(rng.randf_range(8, 14) * (1 if rng.randf() < 0.5 else -1), 0)
		var a3 := cc3 + off
		var b3 := a3 + Vector2(rng.randf_range(-1, 1), rng.randf_range(-1, 1)).normalized() * rng.randf_range(4, 8)
		if bounds.grow(-3).has_point(a3) and bounds.grow(-3).has_point(b3):
			_wall(Vector3(a3.x, 0, a3.y), Vector3(b3.x, 0, b3.y), rng.randf_range(0.6, 1.4))
	# broken cart and camp remains
	var c2: Vector2 = ctrl[2]
	var cart := Models.N(null, "cart")
	Models.P(cart, Geo.box(1.6, 0.12, 2.6), Props.wood(), Vector3(0, 0.6, 0), Vector3(0, 0, 8))
	Models.P(cart, Geo.box(0.1, 0.5, 2.6), Props.wood(), Vector3(0.78, 0.85, 0), Vector3(0, 0, 8))
	Models.P(cart, Geo.cyl(0.55, 0.55, 0.1, 14), Props.wood_dark(), Vector3(-0.9, 0.4, 0.8), Vector3(0, 0, 90))
	Models.P(cart, Geo.cyl(0.55, 0.55, 0.1, 14), Props.wood_dark(), Vector3(0.6, 0.05, -1.4), Vector3(90, 30, 0))
	_place(cart, Vector3(c2.x + 4.5, 0, c2.y + 2))
	add_circle(Vector3(c2.x + 4.5, 0, c2.y + 2), 1.2)

	# vegetation
	var dt_meshes := [Flora.dead_tree(11), Flora.dead_tree(23), Flora.dead_tree(37)]
	var pine_meshes := [Flora.pine(4), Flora.pine(5), Flora.pine(6)]
	var oak_meshes := [Flora.oak(12), Flora.oak(14)]
	var bush_mesh := Flora.bush(3)
	var groups := {}
	for i in 1700:
		var px := rng.randf_range(bounds.position.x - MARGIN + 3, bounds.end.x + MARGIN - 3)
		var pz := rng.randf_range(bounds.position.y - MARGIN + 3, bounds.end.y + 4)
		var inside := bounds.grow(-1.5).has_point(Vector2(px, pz))
		var pd := path_dist(px, pz) if inside else 99.0
		if inside and (pd < 6.5 or is_near_obstacle(Vector3(px, 0, pz), 2.5)):
			continue
		if inside and rng.randf() < 0.3:
			continue
		var r := rng.randf()
		var key := ""
		if r < 0.38:
			key = "pine%d" % (i % 3)
		elif r < 0.6:
			key = "dead%d" % (i % 3)
		elif r < 0.7:
			key = "oak%d" % (i % 2)
		else:
			key = "bush"
		if not groups.has(key):
			groups[key] = []
		var s := rng.randf_range(0.8, 1.35)
		groups[key].append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * s), Vector3(px, height_at(px, pz) - 0.15, pz)))
		if inside and key != "bush":
			add_circle(Vector3(px, 0, pz), 0.45 if key.begins_with("dead") else 0.55)
	# a share of the trees near the road burn in A3
	for key in groups.keys():
		if key.begins_with("pine") or key.begins_with("dead"):
			var arr: Array = groups[key]
			for ti in range(0, arr.size(), 7):
				var o: Vector3 = (arr[ti] as Transform3D).origin
				if bounds.grow(4.0).has_point(Vector2(o.x, o.z)):
					burn_points.append([o + Vector3(0, 2.6 if key.begins_with("pine") else 1.6, 0), 1.5 if key.begins_with("pine") else 1.0])
	for key in groups.keys():
		var mesh: Mesh
		if key.begins_with("pine"):
			mesh = pine_meshes[int(key.substr(4))]
		elif key.begins_with("dead"):
			mesh = dt_meshes[int(key.substr(4))]
		elif key.begins_with("oak"):
			mesh = oak_meshes[int(key.substr(3))]
		else:
			mesh = bush_mesh
		mm_chunked(mesh, groups[key], true, 32.0)
	for i in 160:
		var px := rng.randf_range(bounds.position.x + 1, bounds.end.x - 1)
		var pz := rng.randf_range(bounds.position.y + 1, bounds.end.y - 3)
		var pd := path_dist(px, pz)
		if pd < 2.0:
			continue
		var big := rng.randf() < 0.22 and pd > 5.0
		_rock(Vector3(px, 0, pz), rng.randf_range(1.0, 2.0) if big else rng.randf_range(0.25, 0.6), big)
	for i in 80:
		var px := rng.randf_range(bounds.position.x - 22, bounds.end.x + 22)
		var pz := rng.randf_range(bounds.position.y - 22, bounds.end.y)
		if bounds.grow(-1.0).has_point(Vector2(px, pz)):
			continue
		_rock(Vector3(px, 0, pz), rng.randf_range(1.0, 3.0), false)

	_rasterize()
	_flush_stones(Props.stone())
	_build_terrain(MOOR_TERRAIN)
	_scatter_grass(94000, MOOR_GRASS, 0.32)
	_scatter_ferns(700)

	# monster packs along the path
	var foes: Array = Data.ACTS[act]["foes"]
	var pid := 0
	var champ_done := false
	var t := 0.12
	while t < 0.95:
		var idx := int(path_poly.size() * t)
		var c: Vector2 = path_poly[idx]
		var side := rng.randf_range(-11, 11)
		var pc := Vector3(clampf(c.x + side, bounds.position.x + 3, bounds.end.x - 3), 0, c.y + rng.randf_range(-3, 3))
		if not is_blocked(pc.x, pc.z):
			var k: String = foes[rng.randi() % foes.size()]
			var n := rng.randi_range(3, 6) if k != "skel_archer" else rng.randi_range(2, 4)
			var champ := (rng.randf() < 0.12) or (not champ_done and t > 0.5)
			if champ:
				champ_done = true
				n = rng.randi_range(3, 4)
			enemy_spawns.append({"kind": k, "pos": pc, "count": n, "champ": champ, "pack": pid, "level": level + int(t * 3.0)})
			pid += 1
		t += rng.randf_range(0.045, 0.07)
	spawns["start"] = Vector3(0, 0, -6)
	spawns["from_town"] = Vector3(0, 0, -6)
	spawns["from_lair"] = Vector3(end_p.x, 0, end_p.y + 4.5)

# ---------------------------------------------------------------- dungeon: Crypt of the Matron
var floor_rects: Array = []

func is_floor(x: float, z: float) -> bool:
	for r in floor_rects:
		if (r as Rect2).has_point(Vector2(x, z)):
			return true
	return false

const CRYPT_TERRAIN := {
	"col_a": Color(0.08, 0.075, 0.07), "col_b": Color(0.1, 0.09, 0.08), "col_accent": Color(0.12, 0.13, 0.08),
	"col_path": Color(0.42, 0.4, 0.37), "col_cliff": Color(0.12, 0.11, 0.1), "tiles": 1.0, "wet": 0.5,
}

func _build_lair() -> void:
	flat_floor = true
	theme = {"name": "lair"}
	var rooms: Array = []
	var cur := Rect2(-7, -14, 14, 14)
	rooms.append(cur)
	floor_rects.append(cur)
	for i in 5:
		var boss_room := i == 4
		var w := 28.0 if boss_room else rng.randf_range(13, 19)
		var h := 28.0 if boss_room else rng.randf_range(13, 18)
		var cc := cur.get_center()
		var nx := clampf(cc.x + rng.randf_range(-16, 16), -30, 30)
		if boss_room:
			nx = cc.x * 0.5
		var gap := rng.randf_range(7, 11)
		var nr := Rect2(nx - w * 0.5, cur.position.y - gap - h, w, h)
		# corridor: down from cur, then across, then into the new room
		var midz := cur.position.y - gap * 0.5
		floor_rects.append(Rect2(cc.x - 2.0, midz - 2.0, 4.0, cur.position.y - midz + 2.5))
		floor_rects.append(Rect2(minf(cc.x, nx) - 2.0, midz - 2.0, absf(nx - cc.x) + 4.0, 4.0))
		floor_rects.append(Rect2(nx - 2.0, nr.end.y - 0.5, 4.0, midz - nr.end.y + 2.5))
		rooms.append(nr)
		floor_rects.append(nr)
		cur = nr
	var bb: Rect2 = floor_rects[0]
	for r in floor_rects:
		bb = bb.merge(r)
	bounds = bb.grow(3.0)
	dirt_blobs = [[bounds.get_center(), 9999.0, 1.0]]
	dirt_lines = []
	# decor before rasterising
	var sm := Props.stone_clean()
	var boss_r: Rect2 = rooms[rooms.size() - 1]
	for ri in rooms.size():
		var r: Rect2 = rooms[ri]
		var c := r.get_center()
		if ri == rooms.size() - 1:
			for i in 10:
				var a := TAU * i / 10.0
				var pp := Vector3(c.x + cos(a) * 10.5, 0, c.y + sin(a) * 10.5)
				_pillar(pp, 4.0)
			var pool := Models.N(null, "pool")
			var bm := StandardMaterial3D.new()
			bm.albedo_color = Color(0.18, 0.0, 0.01)
			bm.roughness = 0.05
			bm.metallic_specular = 1.0
			Models.P(pool, Geo.cyl(4.0, 4.0, 0.02, 32), bm, Vector3(0, 0.02, 0))
			Models.P(pool, Geo.torus(3.9, 4.4, 40, 6), sm, Vector3(0, 0.05, 0), Vector3.ZERO, Vector3(1, 0.3, 1))
			_place(pool, Vector3(c.x, 0, c.y + 2))
			var altar := Models.N(null, "altar")
			Models.P(altar, Geo.box(3.4, 1.0, 1.6), sm, Vector3(0, 0.5, 0))
			Models.P(altar, Geo.box(3.8, 0.15, 2.0), sm, Vector3(0, 1.05, 0))
			Models.P(altar, Geo.box(2.0, 0.3, 0.6), Mats.world(Color(0.25, 0.02, 0.02), Color(0.15, 0.01, 0.01), 0.5, 3.0, 0.0, Props.MOSS, true), Vector3(0, 1.25, 0))
			_place(altar, Vector3(c.x, 0, r.position.y + 2.5))
			add_box(Vector3(c.x, 0, r.position.y + 2.5), Vector2(1.9, 1.0), 0.0)
			for k in 8:
				_candles(Vector3(c.x - 1.5 + k * 0.43, 1.12, r.position.y + 2.5 + (0.3 if k % 2 == 0 else -0.3)), false)
			for corner in [Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 1), Vector2(1, 1)]:
				var bp := Vector3(c.x + corner.x * 11.0, 0, c.y + corner.y * 11.0)
				var br := Models.N(null, "brazier")
				Models.P(br, Geo.cyl(0.1, 0.2, 1.1, 8), Props.iron(), Vector3(0, 0.55, 0))
				Models.P(br, Geo.lathe([Vector2(0.05, 0.0), Vector2(0.4, 0.1), Vector2(0.45, 0.32), Vector2(0.0, 0.22)], 12, "brazier2"), Props.iron(), Vector3(0, 1.1, 0))
				_place(br, bp)
				Props.fire(br, Vector3(0, 1.45, 0), 1.1, Color(1.0, 0.42, 0.15), true, corner.y < 0)
				add_circle(bp, 0.5)
			boss_spawn = {"kind": Data.ACTS[act]["boss"], "pos": Vector3(c.x, 0, c.y - 3)}
			continue
		if r.size.x > 14 and r.size.y > 14 and ri > 0:
			for corner in [Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 1), Vector2(1, 1)]:
				_pillar(Vector3(c.x + corner.x * r.size.x * 0.27, 0, c.y + corner.y * r.size.y * 0.27), 3.6)
		var nsar := rng.randi_range(1, 3) if ri > 0 else 0
		for k in nsar:
			var sp := Vector3(rng.randf_range(r.position.x + 2.5, r.end.x - 2.5), 0, rng.randf_range(r.position.y + 2, r.end.y - 2))
			if not is_near_obstacle(sp, 1.5):
				_sarcophagus(sp, rng.randf_range(-15, 15) + (90.0 if rng.randf() < 0.5 else 0.0))
		for k in rng.randi_range(2, 4):
			var bp2 := Vector3(rng.randf_range(r.position.x + 1, r.end.x - 1), 0, rng.randf_range(r.position.y + 1, r.end.y - 1))
			_bones(bp2)
		for k in 2:
			var cp := Vector3(r.position.x + 1.0 if k == 0 else r.end.x - 1.0, 0, rng.randf_range(r.position.y + 2, r.end.y - 2))
			_candles(cp, true)
		# wall torches on the north wall
		for k in 2:
			var tx := lerpf(r.position.x + 2.0, r.end.x - 2.0, 0.25 + k * 0.5)
			_wall_torch(Vector3(tx, 0, r.position.y + 0.15), k == 0 and ri % 2 == 0)
		if ri > 0:
			var foes: Array = Data.ACTS[act]["foes"]
			for k in rng.randi_range(1, 2):
				var ep := Vector3(rng.randf_range(r.position.x + 2, r.end.x - 2), 0, rng.randf_range(r.position.y + 2, r.end.y - 2))
				var kk: String = foes[rng.randi() % foes.size()]
				enemy_spawns.append({"kind": kk, "pos": ep, "count": rng.randi_range(3, 5), "champ": rng.randf() < 0.15 + ri * 0.04, "pack": ri * 10 + k, "level": level + ri / 2})
	_rasterize()
	# everything that is not floor is solid rock
	for y in gh:
		for xx in gw:
			var wx := origin.x + (xx + 0.5) * CELL
			var wz := origin.y + (y + 0.5) * CELL
			if not is_floor(wx, wz):
				blocked[y * gw + xx] = 1
				astar.set_point_solid(Vector2i(xx, y), true)
	# wall blocks along floor edges
	var wall_xf := []
	var top_xf := []
	for y in gh:
		for xx in gw:
			var wx := origin.x + (xx + 0.5) * CELL
			var wz := origin.y + (y + 0.5) * CELL
			if is_floor(wx, wz):
				continue
			var edge := false
			for dy in range(-1, 2):
				for dx in range(-1, 2):
					if is_floor(wx + dx, wz + dy):
						edge = true
			if edge:
				var hh := rng.randf_range(2.8, 3.4)
				wall_xf.append(Transform3D(Basis(Vector3.UP, rng.randf_range(-0.04, 0.04)).scaled(Vector3(1.0, hh, 1.0)), Vector3(wx, hh * 0.5, wz)))
			else:
				top_xf.append(Transform3D(Basis().scaled(Vector3(1.0, 0.2, 1.0)), Vector3(wx, 3.0, wz)))
	var wm := Mats.world(Color(0.4, 0.38, 0.35), Color(0.28, 0.27, 0.25), 0.9, 2.2, 0.25, Color(0.14, 0.16, 0.09))
	Props.multimesh(props_root, Geo.box(1.02, 1.0, 1.02), wall_xf).material_override = wm
	Props.multimesh(props_root, Geo.box(1.0, 1.0, 1.0), top_xf, false).material_override = Mats.world(Color(0.05, 0.05, 0.05), Color(0.03, 0.03, 0.03), 1.0, 1.0, 0.0, Props.MOSS, true)
	_flush_stones(Props.stone())
	_build_terrain(CRYPT_TERRAIN)
	var r0: Rect2 = rooms[0]
	# stairs back up
	var st := Models.N(null, "stairs")
	for i in 6:
		Models.P(st, Geo.box(3.6, 0.25 + i * 0.25, 0.7), sm, Vector3(0, (0.25 + i * 0.25) * 0.5, -i * 0.7))
	_place(st, Vector3(r0.get_center().x, 0, r0.end.y - 0.6))
	st.rotation.y = PI
	var shaft := MeshInstance3D.new()
	shaft.mesh = Geo.cyl(1.4, 2.2, 7.0, 16)
	shaft.material_override = Mats.glow(Color(0.6, 0.7, 0.8), 0.25, 1.0, 0.5)
	shaft.position = Vector3(r0.get_center().x, 3.5, r0.end.y - 1.5)
	shaft.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	props_root.add_child(shaft)
	exits.append({"pos": Vector3(r0.get_center().x, 0, r0.end.y - 0.8), "radius": 1.8, "to": "wild", "label": Data.ACTS[act]["wild"]})
	spawns["start"] = Vector3(r0.get_center().x, 0, r0.end.y - 5.0)
	spawns["boss_room"] = Vector3(boss_r.get_center().x, 0, boss_r.end.y - 3)

func _pillar(p: Vector3, h: float) -> void:
	var g := Models.N(null, "pillar")
	var sm := Props.stone_clean()
	Models.P(g, Geo.box(1.0, 0.4, 1.0), sm, Vector3(0, 0.2, 0))
	Models.P(g, Geo.cyl(0.36, 0.4, h - 0.8, 12), sm, Vector3(0, h * 0.5, 0))
	Models.P(g, Geo.box(1.0, 0.4, 1.0), sm, Vector3(0, h - 0.2, 0))
	_place(g, p)
	add_circle(p, 0.55)

func _sarcophagus(p: Vector3, yaw: float) -> void:
	var g := Models.N(null, "sarc")
	var sm := Props.stone_clean()
	Models.P(g, Geo.box(1.1, 0.8, 2.3), sm, Vector3(0, 0.4, 0))
	var lid := Models.P(g, Geo.box(1.2, 0.2, 2.4), sm, Vector3(0.15, 0.9, 0.1), Vector3(0, 8, 4))
	Models.P(g, Geo.sph(0.12, 8), Mats.world(Color(0.75, 0.7, 0.6), Color(0.6, 0.55, 0.45), 0.7, 3.0, 0.0, Props.MOSS, true), Vector3(-0.3, 0.12, 1.4))
	_place(g, p)
	g.rotation_degrees.y = yaw
	add_box(p, Vector2(0.6, 1.2), deg_to_rad(-yaw))

func _bones(p: Vector3) -> void:
	var g := Models.N(null, "bones")
	var bm := Mats.world(Color(0.72, 0.68, 0.58), Color(0.55, 0.5, 0.4), 0.7, 3.0, 0.0, Props.MOSS, false)
	for i in 6:
		var b := Models.P(g, Geo.cyl(0.025, 0.025, rng.randf_range(0.3, 0.5), 5), bm, Vector3(rng.randf_range(-0.4, 0.4), 0.03, rng.randf_range(-0.4, 0.4)), Vector3(90, rng.randf() * 360.0, 0))
	if rng.randf() < 0.6:
		Models.P(g, Geo.sph(0.11, 8), bm, Vector3(0.1, 0.1, 0.0), Vector3.ZERO, Vector3(0.9, 1.0, 1.1))
	_place(g, p)

func _candles(p: Vector3, on_floor: bool) -> void:
	var g := Models.N(null, "candles")
	var wax := Mats.mat(Color(0.85, 0.8, 0.65), 0.6, 0.0, Color(1.0, 0.7, 0.3), 0.1)
	var n := 5 if on_floor else 1
	for i in n:
		var hh := rng.randf_range(0.12, 0.35)
		var cp := Vector3(rng.randf_range(-0.25, 0.25), 0, rng.randf_range(-0.25, 0.25)) if on_floor else Vector3.ZERO
		Models.P(g, Geo.cyl(0.03, 0.035, hh, 6), wax, cp + Vector3(0, hh * 0.5, 0))
		Models.P(g, Geo.sph(0.02, 5), Mats.glow(Color(1.0, 0.7, 0.3), 4.0), cp + Vector3(0, hh + 0.03, 0), Vector3.ZERO, Vector3(0.7, 1.5, 0.7))
	if on_floor:
		_place(g, p)
		var l := OmniLight3D.new()
		l.light_color = Color(1.0, 0.65, 0.3)
		l.light_energy = 0.7
		l.omni_range = 3.5
		l.position = Vector3(0, 0.6, 0)
		l.add_to_group("flicker")
		l.set_meta("base", 0.7)
		g.add_child(l)
	else:
		props_root.add_child(g)
		g.position = p

func _wall_torch(p: Vector3, shadow: bool) -> void:
	var g := Models.N(null, "sconce")
	Models.P(g, Geo.box(0.12, 0.3, 0.1), Props.iron(), Vector3(0, 2.2, 0.0))
	Models.seg(g, Vector3(0, 2.1, 0), Vector3(0, 2.5, 0.3), 0.03, 0.04, Props.wood_dark(), 6)
	_place(g, p)
	Props.fire(g, Vector3(0, 2.62, 0.34), 0.6, Color(1.0, 0.5, 0.2), true, shadow, false)
