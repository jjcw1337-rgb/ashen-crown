class_name World
extends Node3D
## A playable zone: terrain, props, collision grid, pathfinding and spawn data.

const CELL := 1.0
const MARGIN := 30.0

var act := 0
var oak_forest := false     # Act I moor: oak groves and an oak forest beyond the edges
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
## Extra ground shaping for a zone (Fort: the ditch and rampart): f(x, z) -> metres added to the height.
var ground_fn := Callable()
## Act I: the lair is King Grubb's goblin fort (fort.gd) and the moor's road ends at its trail.
var fort := false
## Which run (Game.difficulty) this zone is for: A2 (1) has its own wild zone (via.gd) and lair (aurelia.gd).
var run := 0
var dirt_blobs: Array = []     # [Vector2 pos, radius, strength]
var cobble_blobs: Array = []
var dirt_lines: Array = []     # [Vector2 a, Vector2 b, width]
var cobble_lines: Array = []   # [Vector2 a, Vector2 b, width] (paved roads)
## Side trails off the moor's road (to landmarks); path_dist counts them too.
var trails: Array = []         # PackedVector2Array each
var obstacles: Array = []      # [Vector2 pos, radius]
var spawns := {}
## Places that burn in A3: [position, size]. Recorded while building; only used for looks.
var burn_points: Array = []
var enemy_spawns: Array = []
## Act I: the Hollow Sloths' lairs (sloth_lair.gd), picked before the trees so they stay clear
var sloth_lairs: Array = []
var boss_spawn := {}
## Hidden enemies that appear when a hero comes near (Via's bandit ambush; Game._check_ambushes):
## [{pos: Vector3, radius, spawns: [spawn entries], done, land: Vector3}]
var ambushes: Array = []
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
	if ground_fn.is_valid():
		return inner + hill + float(ground_fn.call(x, z))
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
	_bake_lines(dirt_lines, dirt_mask)
	_bake_lines(cobble_lines, cob_mask)
	masks_ready = true

func _bake_lines(list: Array, mask: PackedFloat32Array) -> void:
	for l in list:
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
				if v > mask[k]:
					mask[k] = v

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
	for l in cobble_lines:
		var cp := Geometry2D.get_closest_point_to_segment(p, l[0], l[1])
		v = maxf(v, 1.0 - smoothstep(l[2] * 0.4, l[2], p.distance_to(cp)))
	return v

func _cell(x: float, z: float) -> Vector2i:
	return Vector2i(int(floor((x - origin.x) / CELL)), int(floor((z - origin.y) / CELL)))

func is_blocked(x: float, z: float) -> bool:
	var c := _cell(x, z)
	if c.x < 0 or c.y < 0 or c.x >= gw or c.y >= gh:
		return true
	return blocked[c.y * gw + c.x] != 0

## Line of sight / straight walkability: true if a body of radius r can go from a to b
## without touching a footprint or a wall.
func los(a: Vector3, b: Vector3, r := 0.0) -> bool:
	var d := Vector2(b.x - a.x, b.z - a.z)
	var n := int(d.length() / 0.4) + 1
	for i in range(1, n):
		var t := float(i) / n
		if solid_at(a.x + d.x * t, a.z + d.y * t, r):
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
	if los(a, b, BODY_R * 0.8):
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
			if los(cur, raw[j], BODY_R * 0.8):
				far = j
				break
		cur = raw[far]
		cur.y = height_at(cur.x, cur.z)
		out.append(cur)
		i = far + 1
	return out

# ---------------------------------------------------------------- collision
## One registry of solid footprints (circles and rotated boxes on the ground plane) drives
## everything that collides:
## - `move` slides a body (radius BODY_R) against the exact footprints, so you bump into
##   the barrel itself, not the grid square around it;
## - `los` / `solid_at` test the same footprints (sight, straight walks, missiles);
## - `blocked`, a padded 1 m grid rasterized from them, is only for A* pathfinding and spawn
##   spots.
## Hard terrain (the map edge, dungeon rock) is `_wall_at`. Props declare their own footprint
## (`Props.footprint`), and `solid(node)` registers it with the node's position, yaw and
## scale, so the mesh and its collision can't drift apart. Use add_circle/add_box directly
## only for things without a prop node (walls of stones, groups of pots).
const BODY_R := 0.32
const BUCKET := 4.0
var _buckets := {}   # Vector2i -> Array of obstacle indices overlapping that 4 m square
var rock := PackedByteArray()   # dungeons: 1 where a 1 m cell is solid rock

func add_circle(p: Vector3, r: float) -> void:
	obstacles.append([Vector2(p.x, p.z), r])
	_bucket(obstacles.size() - 1, Vector2(p.x, p.z), r)

## A rectangle of half-size `half` (x across, y along), turned by `yaw` like a node's rotation.y.
func add_box(p: Vector3, half: Vector2, yaw: float) -> void:
	obstacles.append([Vector2(p.x, p.z), -1.0, half, yaw])
	_bucket(obstacles.size() - 1, Vector2(p.x, p.z), half.length())

## Registers a prop's own footprint (see Props.footprint) where the prop stands.
func solid(node: Node3D) -> Node3D:
	if not node.has_meta("footprint"):
		push_warning("solid(): %s has no footprint" % node.name)
		return node
	var f: Dictionary = node.get_meta("footprint")
	# the node's transform relative to the zone (props may sit inside an interactable)
	var xf := Transform3D.IDENTITY
	var n: Node = node
	while n != null and n != self:
		if n is Node3D:
			xf = (n as Node3D).transform * xf
		n = n.get_parent()
	var c: Vector3 = xf * (f["at"] as Vector3)
	var sc := xf.basis.get_scale().x
	if f.has("r"):
		add_circle(c, float(f["r"]) * sc)
	else:
		add_box(c, (f["half"] as Vector2) * sc, xf.basis.get_euler().y)
	return node

## Files the obstacle under every 4 m square it can touch, padded by the widest body (1 m)
## so a query only needs the square the body's centre is in.
func _bucket(i: int, c: Vector2, ext: float) -> void:
	ext += 1.0
	var b0 := Vector2i(floori((c.x - ext) / BUCKET), floori((c.y - ext) / BUCKET))
	var b1 := Vector2i(floori((c.x + ext) / BUCKET), floori((c.y + ext) / BUCKET))
	for by in range(b0.y, b1.y + 1):
		for bx in range(b0.x, b1.x + 1):
			var k := Vector2i(bx, by)
			if not _buckets.has(k):
				_buckets[k] = []
			(_buckets[k] as Array).append(i)

## How far a body of radius r at q must move to clear obstacle o (ZERO if it doesn't touch).
## Pushes overshoot by a millimetre so a resolved body is clear, not exactly touching.
func _pen(o: Array, q: Vector2, r: float) -> Vector2:
	var c: Vector2 = o[0]
	if o[1] > 0.0:
		var v := q - c
		var need: float = o[1] + r
		var dl := v.length()
		if dl >= need - 0.0005:
			return Vector2.ZERO
		return (v / dl if dl > 0.0001 else Vector2(1, 0)) * (need - dl + 0.001)
	var half: Vector2 = o[2]
	var yaw: float = o[3]
	var lp := (q - c).rotated(yaw)
	var cl := Vector2(clampf(lp.x, -half.x, half.x), clampf(lp.y, -half.y, half.y))
	var dv := lp - cl
	var dl := dv.length()
	if dl >= r - 0.0005:
		return Vector2.ZERO
	var push: Vector2
	if dl > 0.0001:
		push = dv / dl * (r - dl + 0.001)
	else:
		# centre inside the box: out through the nearest side
		var ox := half.x - absf(lp.x)
		var oy := half.y - absf(lp.y)
		push = Vector2((ox + r + 0.001) * signf(lp.x + 0.0001), 0) if ox < oy else Vector2(0, (oy + r + 0.001) * signf(lp.y + 0.0001))
	return push.rotated(-yaw)

func _near(q: Vector2) -> Array:
	return _buckets.get(Vector2i(floori(q.x / BUCKET), floori(q.y / BUCKET)), [])

## True if a body of radius r at (x, z) overlaps a footprint or a wall.
func solid_at(x: float, z: float, r := 0.0) -> bool:
	if _wall_at(x, z, r):
		return true
	var q := Vector2(x, z)
	for i in _near(q):
		if _pen(obstacles[i], q, r + 0.001) != Vector2.ZERO:
			return true
	return false

## Map edge, or dungeon rock (the same cells the wall blocks are built on). Probes the
## body's four sides.
func _wall_at(x: float, z: float, r := 0.0) -> bool:
	if rock.is_empty():
		return not bounds.grow(-1.0 - r).has_point(Vector2(x, z))
	return _rock_at(x, z) or r > 0.0 and (_rock_at(x - r, z) or _rock_at(x + r, z) or _rock_at(x, z - r) or _rock_at(x, z + r))

func _rock_at(x: float, z: float) -> bool:
	var c := _cell(x, z)
	return c.x < 0 or c.y < 0 or c.x >= gw or c.y >= gh or rock[c.y * gw + c.x] != 0

## Moves a body by d, sliding along footprints and walls. Long moves go in short steps so
## nothing is skipped through.
func move(pos: Vector3, d: Vector3, r := BODY_R) -> Vector3:
	var flat := Vector2(d.x, d.z)
	var n := maxi(1, int(ceil(flat.length() / 0.25)))
	var step := flat / n
	var q := Vector2(pos.x, pos.z)
	for i in n:
		var nq := _slide(q, step, r)
		if nq == q:
			break
		q = nq
	return Vector3(q.x, height_at(q.x, q.y), q.y)

func _slide(q: Vector2, step: Vector2, r: float) -> Vector2:
	for cand in [step, Vector2(step.x, 0), Vector2(0, step.y)]:
		if cand == Vector2.ZERO:
			continue
		var p := _resolve(q + cand, r)
		if p.x != INF and not _wall_at(p.x, p.y, r):
			return p
	return q

## Pushes q out of any footprints it overlaps; INF if it can't be cleared (wedged).
func _resolve(q: Vector2, r: float) -> Vector2:
	for it in 3:
		var hit := false
		for i in _near(q):
			var pv := _pen(obstacles[i], q, r)
			if pv != Vector2.ZERO:
				q += pv
				hit = true
		if not hit:
			return q
	return Vector2(INF, INF)

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
		if _in_lair(x, z, 0.8):
			continue
		var y := height_at(x, z)
		var s := rng.randf_range(0.7, 1.35) * (1.0 - dm * 0.6)
		xf.append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(s, s * rng.randf_range(0.8, 1.3), s)), Vector3(x, y - 0.02, z)))
	# Act I: grass painted for the camera (Flora.GRASS_TOP: nine kinds of clump, from lush tufts to
	# dandelions), a clump on every spot and a smaller one beside most, over the blade grass on every
	# other spot, so the ground reads as one grassy carpet. The older upright photo cards are the fallback.
	if oak_forest and Flora.grass_top_ok():
		var gp := []
		for k in Flora.GRASS_TOP.size():
			gp.append([])
		for i in xf.size():
			var o: Vector3 = (xf[i] as Transform3D).origin
			var sc := (xf[i] as Transform3D).basis.get_scale()
			# no yaw: the cards must face the camera; mirrored at random instead
			var fl := -1.0 if rng.randf() < 0.5 else 1.0
			gp[Flora.grass_top_kind(rng) - 1].append(Transform3D(Basis.from_scale(Vector3(sc.x * fl, sc.y, sc.x)), o))
			if rng.randf() < 0.7:
				var o2 := o + Vector3(rng.randf_range(-0.7, 0.7), 0, rng.randf_range(-0.7, 0.7))
				o2.y = height_at(o2.x, o2.z) - 0.02
				var s2 := sc.x * rng.randf_range(0.6, 0.9)
				gp[Flora.grass_top_kind(rng) - 1].append(Transform3D(Basis.from_scale(Vector3(s2 * -fl, s2, s2)), o2))
		for k in gp.size():
			for mmi in mm_chunked(Flora.grass_top(k + 1, colors), gp[k], detail >= 3, 20.0, 60.0):
				mmi.add_to_group("grass")
		var keep := []
		for i in range(0, xf.size(), 2):
			keep.append(xf[i])
		xf = keep
	elif oak_forest and Flora.grass_tex_ok():
		var cparts := [[], [], [], [], [], []]
		var keep := []
		for i in xf.size():
			if i % 2 == 0:
				keep.append(xf[i])
			var r := rng.randf()
			var k := 0 if r < 0.68 else (1 if r < 0.88 else 2)
			cparts[k * 2 + (i % 2)].append(xf[i])
		for ci in cparts.size():
			var cm := Flora.grass_cards(int(ci / 2.0) + 1, ci % 2, colors)
			for mmi in mm_chunked(cm, cparts[ci], detail >= 3, 20.0, 60.0):
				mmi.add_to_group("grass")
		xf = keep
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

## Act I: packs of Ferals (feral.gd) clinging to oak trunks in the forest, well off the road: three
## packs of three or four, each Feral on its own oak, waiting head-down for someone to wander close.
## Their own seed, so the rest of the moor doesn't change around them.
func _feral_packs(groups: Dictionary, pid: int) -> void:
	var oaks := []
	for key in ["oak0", "oak1", "oak2"]:
		for t in groups.get(key, []):
			var o: Vector3 = (t as Transform3D).origin
			var d := path_dist(o.x, o.z)
			if bounds.grow(-3.0).has_point(Vector2(o.x, o.z)) and d > 11.0 and d < 34.0 and Vector2(o.x, o.z).distance_to(Vector2(0, -6)) > 30.0:
				oaks.append(t)
	var r := RandomNumberGenerator.new()
	r.seed = int(bounds.size.y * 1000.0) + 4242
	var centres := []
	for tries in 200:
		if centres.size() >= 3 or oaks.is_empty():
			break
		var c: Transform3D = oaks[r.randi() % oaks.size()]
		if centres.any(func(q: Vector3) -> bool: return q.distance_to(c.origin) < 35.0):
			continue
		centres.append(c.origin)
		var n := r.randi_range(3, 4)
		var near := oaks.filter(func(t: Transform3D) -> bool: return t.origin.distance_to(c.origin) < 14.0)
		near.shuffle()
		# a big oak can hold two of them
		while near.size() < n:
			near.append(near[r.randi() % near.size()])
		for t in near.slice(0, n):
			var o: Vector3 = (t as Transform3D).origin
			# on a random side of the trunk
			var a := r.randf() * TAU
			var out := Vector3(cos(a), 0, sin(a))
			var trunk := 0.45 * (t as Transform3D).basis.get_scale().x
			enemy_spawns.append({"kind": "feral", "pos": o + out * trunk, "count": 1, "champ": false, "pack": 500 + pid + centres.size(),
				"level": level + 1, "perch": [o.x, o.z]})

## Act I: the Forsaken Bears (bear.gd), each a lone wanderer 20-40 m off the road, well apart, clear of the
## camp's gate (the start) and the fort's end of the moor. Their own seed, so nothing else moves.
func _bear_dens(count: int, lair: Vector2) -> void:
	var r := RandomNumberGenerator.new()
	r.seed = int(bounds.size.y * 1000.0) + 9311
	var placed := []
	var start: Vector3 = Vector3(0, 0, -6)
	for tries in 600:
		if placed.size() >= count:
			break
		var x := r.randf_range(bounds.position.x + 6.0, bounds.end.x - 6.0)
		var z := r.randf_range(bounds.position.y + 6.0, bounds.end.y - 6.0)
		var d := path_dist(x, z)
		if d < 20.0 or d > 40.0 or is_blocked(x, z) or is_near_obstacle(Vector3(x, 0, z), 2.0):
			continue
		var p := Vector3(x, 0, z)
		if p.distance_to(start) < 45.0 or Vector2(x, z).distance_to(lair) < 40.0:
			continue
		if placed.any(func(q: Vector3) -> bool: return q.distance_to(p) < 60.0):
			continue
		placed.append(p)
		enemy_spawns.append({"kind": "bear", "pos": p, "count": 1, "champ": false, "pack": 900 + placed.size(), "level": level + 2})

## Act I: the three Hollow Sloths (sloth.gd: fire, ice, lightning), each in its own lair (sloth_lair.gd),
## a clearing far off the road dressed for its element, where it lives and wanders.
func _sloths() -> void:
	var kinds := ["sloth_fire", "sloth_ice", "sloth_storm"]
	for i in sloth_lairs.size():
		var p: Vector3 = sloth_lairs[i]
		SlothLair.make(self, p, Data.ENEMIES[kinds[i]]["element"])
		enemy_spawns.append({"kind": kinds[i], "pos": p, "count": 1, "champ": false, "pack": 800 + i, "level": level + 2, "lair": true})

## Inside a Hollow Sloth's clearing (no trees there; k shrinks it, so the grass thins in at its edge).
func _in_lair(x: float, z: float, k := 1.0) -> bool:
	for l in sloth_lairs:
		if Vector2(x, z).distance_to(Vector2(l.x, l.z)) < SlothLair.CLEAR * k:
			return true
	return false

## Act I: a few rare Sunstar Blooms off the road, in among the trees. Picking one gives +50% experience
## for 5 minutes (Game.use_inter). Their own seed, so the rest of the moor doesn't change around them.
func _rare_flowers(count: int) -> void:
	var r := RandomNumberGenerator.new()
	r.seed = int(bounds.size.y * 1000.0) + 7717
	var placed := []
	var tries := 400
	while placed.size() < count and tries > 0:
		tries -= 1
		var x := r.randf_range(bounds.position.x + 4.0, bounds.end.x - 4.0)
		var z := r.randf_range(bounds.position.y + 4.0, bounds.end.y - 4.0)
		var d := path_dist(x, z)
		if d < 14.0 or d > 34.0 or is_blocked(x, z) or is_near_obstacle(Vector3(x, 0, z), 1.2):
			continue
		var p := Vector3(x, 0, z)
		if p.distance_to(spawns.get("start", Vector3.ZERO)) < 25.0 or placed.any(func(q: Vector3) -> bool: return q.distance_to(p) < 40.0):
			continue
		placed.append(p)
		var g := Node3D.new()
		var card := MeshInstance3D.new()
		card.mesh = Flora.flower_card()
		card.name = "bloom"
		g.add_child(card)
		var l := OmniLight3D.new()
		l.light_color = Color(1.0, 0.78, 0.35)
		l.light_energy = 1.5
		l.omni_range = 4.5
		l.position = Vector3(0, 0.7, 0)
		l.name = "light"
		g.add_child(l)
		_inter("flower", "Sunstar Bloom", p, 1.2, g)

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
		if _in_lair(x, z, 0.85):
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

## A waypoint stone (Data.WAYPOINT_ACTS point `id`) at `p`: the stone, its four pillar colliders, and
## where travellers arrive by it ("waypoint_<id>", 3 m in front; the zone's first stone is also
## "waypoint"). Any zone builder can place several. `cobble` paves the ground round it.
func add_waypoint(id: String, p: Vector3, cobble := false) -> Inter:
	var it := _inter("waypoint", "Waypoint", Vector3(p.x, 0, p.z), 2.4, Props.waypoint(null, Vector3.ZERO), {"wp": id})
	for i in 4:
		var a := TAU * i / 4.0 + PI * 0.25
		add_circle(Vector3(p.x + cos(a) * 1.85, 0, p.z + sin(a) * 1.85), 0.3)
	var arrive := Vector3(p.x, 0, p.z + 3.0)
	spawns["waypoint_" + id] = arrive
	if not spawns.has("waypoint"):
		spawns["waypoint"] = arrive
	if cobble:
		cobble_blobs.append([Vector2(p.x, p.z), 3.0, 0.8])
	return it

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
	it.set_meta("look", look)
	it.add_child(rig)
	rig.rotation.y = yaw
	it.rig = rig
	add_circle(p, 0.45)
	return it

# ---------------------------------------------------------------- zone builders
## This act's names, boss and foes for this zone's run (Data.act_info).
func act_info() -> Dictionary:
	return Data.act_info(act, run)

func act_name(key: String) -> String:
	return str(act_info()[key])

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
		"wild": Via.build(self) if run == 1 else _build_wild()
		"lair":
			if run == 1:
				Aurelia.build(self)
			elif fort:
				Fort.build(self)
			else:
				_build_lair()

const MOOR_TERRAIN := {
	"col_a": Color(0.15, 0.2, 0.08), "col_b": Color(0.21, 0.23, 0.11), "col_accent": Color(0.28, 0.3, 0.13),
	"col_path": Color(0.25, 0.21, 0.16), "col_cliff": Color(0.3, 0.3, 0.28), "wet": 0.3,
}
const MOOR_GRASS := {"base_col": Color(0.12, 0.16, 0.06), "tip_col": Color(0.27, 0.32, 0.13), "dry_col": Color(0.36, 0.35, 0.18), "wind": 1.0}
## The moor's trails (road styles 1 and 3): lighter, sandier packed earth so a narrow path reads.
var MOOR_TRAIL: Dictionary = MOOR_TERRAIN.merged({"col_path": Color(0.4, 0.34, 0.25)}, true)
## The kingsroad: its flagstones a shade darker than the camp's, so they sit in the moor.
var MOOR_ROAD: Dictionary = MOOR_TERRAIN.merged({"cob_shade": 0.72}, true)

func _build_town() -> void:
	if oak_forest and act == 0 and ForestCamp.ok():
		ForestCamp.build(self)      # Act I: the camp in the old forest
		return
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
	solid(Props.tripod_torch(props_root, Vector3(-5.5, height_at(-5.5, wy + 2.0), wy + 2.0)))
	solid(Props.tripod_torch(props_root, Vector3(5.5, height_at(5.5, wy + 2.0), wy + 2.0)))
	exits.append({"pos": Vector3(0, 0, wy - 3.0), "radius": 3.5, "to": "wild", "label": act_name("wild")})

	# --- centre: campfire, stash, waypoint
	var cf := solid(Props.campfire(props_root, Vector3(0, height_at(0, 0), 0)))
	var chest := Props.stash_chest(null, Vector3.ZERO, -15.0)
	_inter("stash", "Stash", Vector3(3.6, 0, 2.6), 1.6, chest)
	solid(chest)
	add_waypoint("town", Vector3(-8, 0, 6))
	# log seats around fire
	for i in 3:
		var a := TAU * i / 3.0 + 0.4
		var lg := Props.footprint(Models.N(null, "seat"), Vector2(0.25, 0.8))
		Models.P(lg, Geo.cyl(0.22, 0.24, 1.6, 10), Props.wood(), Vector3(0, 0.2, 0), Vector3(90, 0, 0))
		_place(lg, Vector3(cos(a) * 3.2, 0, sin(a) * 3.2))
		lg.rotation.y = -a
		solid(lg)

	# --- alchemist's camp (reference: hide tent, pottery, tripod torches)
	var ac := Vector2(-14, -12)
	solid(Props.hide_tent(props_root, Vector3(ac.x, height_at(ac.x, ac.y - 1.5), ac.y - 1.5), 6.0, 3.6, 4.0, 2.6))
	burn_points.append([Vector3(ac.x + 1.0, height_at(ac.x, ac.y - 1.5) + 1.6, ac.y - 1.5), 1.4])
	for tp in [Vector2(-6.0, 1.5), Vector2(6.5, 0.5), Vector2(-1.5, 6.0)]:
		var tpp := Vector3(ac.x + tp.x, 0, ac.y + tp.y)
		solid(Props.tripod_torch(props_root, Vector3(tpp.x, height_at(tpp.x, tpp.z), tpp.z), tp.x < 0 and tp.y < 3.0))
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
	solid(Props.cauldron(props_root, Vector3(cpos.x, height_at(cpos.x, cpos.z), cpos.z), Color(0.35, 0.9, 0.25)))
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
	solid(Props.barrel(props_root, Vector3(fc.x + 3.2, height_at(fc.x + 3.2, fc.z + 2.0), fc.z + 2.0)))
	solid(Props.log_pile(props_root, Vector3(fc.x - 3.8, height_at(fc.x - 3.8, fc.z), fc.z)))

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
		solid(Props.hide_tent(props_root, Vector3(tp2.x, height_at(tp2.x, tp2.y), tp2.y), tdef[1], rng.randf_range(2.6, 3.2), rng.randf_range(3.0, 3.6), rng.randf_range(2.0, 2.4)))
		burn_points.append([Vector3(tp2.x, height_at(tp2.x, tp2.y) + 1.4, tp2.y), 1.25])
	var clutter := [
		["crate", Vector2(-7.5, -16)], ["crate", Vector2(-8.3, -15.2)], ["barrel", Vector2(-3, -16.5)], ["barrel", Vector2(-2.4, -15.8)],
		["crate", Vector2(22, -18)], ["barrel", Vector2(22.6, -19)], ["logs", Vector2(-27, 3)], ["crate", Vector2(10, 18)],
		["barrel", Vector2(-10, 20)], ["crate", Vector2(28, 3)], ["logs", Vector2(9, -24)], ["barrel", Vector2(-21, -12)],
	]
	for c in clutter:
		var cp: Vector2 = c[1]
		var p3 := Vector3(cp.x, height_at(cp.x, cp.y), cp.y)
		match c[0]:
			"crate": solid(Props.crate(props_root, p3, rng.randf_range(0.85, 1.15)))
			"barrel": solid(Props.barrel(props_root, p3))
			"logs": solid(Props.log_pile(props_root, p3))
	for bp2 in [Vector2(-5, -33), Vector2(5, -33), Vector2(-9, 2), Vector2(9, -3)]:
		solid(Props.banner(props_root, Vector3(bp2.x, height_at(bp2.x, bp2.y), bp2.y), Color(0.42, 0.06, 0.05), Color(0.6, 0.5, 0.25)))
	for tp3 in [Vector2(-6, -6), Vector2(7, -5), Vector2(5, 9), Vector2(-4, -22), Vector2(4, -20), Vector2(11, 3), Vector2(-11, 13)]:
		solid(Props.tripod_torch(props_root, Vector3(tp3.x, height_at(tp3.x, tp3.y), tp3.y)))

	# --- rocks, boulders and trees
	for i in 45:
		var p := Vector3(rng.randf_range(-31, 31), 0, rng.randf_range(-34, 30))
		if dirt_at(p.x, p.z) > 0.3 or is_near_obstacle(p, 2.0):
			continue
		_rock(p, rng.randf_range(0.25, 0.7), false)
	for p4 in [Vector3(-22, 0, 16), Vector3(27, 0, -6), Vector3(14, 0, 22), Vector3(-28, 0, -26), Vector3(20, 0, -30), Vector3(-12, 0, 27)]:
		_rock(p4, rng.randf_range(1.0, 1.6))
	var dt_mesh := Flora.dead_tree(5)
	var oak_meshes_town := [Flora.oak_model(1), Flora.oak_model(2), Flora.oak_model(3)]
	var pine_meshes := [Flora.pine(1), Flora.pine(2), Flora.pine(3)]
	var inner_trees := [[], [], []]
	var ti := 0
	for p5 in [Vector3(-29, 0, -15), Vector3(29, 0, 12), Vector3(-20, 0, 27), Vector3(10, 0, 27)]:
		inner_trees[ti % 3].append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * rng.randf_range(0.9, 1.15)), Vector3(p5.x, height_at(p5.x, p5.z), p5.z)))
		add_circle(p5, 0.65)
		ti += 1
	for k in 3:
		if not inner_trees[k].is_empty():
			Props.multimesh(props_root, oak_meshes_town[k], inner_trees[k])
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
	for tr in trails:
		var poly: PackedVector2Array = tr
		for i in poly.size() - 1:
			best = minf(best, p.distance_to(Geometry2D.get_closest_point_to_segment(p, poly[i], poly[i + 1])))
	return best

## Which road the moor gets: 2, the old paved kingsroad (broken flagstones, kerbs and milestones), is
## the game's. The others stay for comparison with `--road N`: 0 the old broad dirt road, 1 a winding
## wagon trail (two ruts, grass between), 3 a narrow trail with side paths to the landmarks and cairns.
func road_style() -> int:
	var args := OS.get_cmdline_user_args()
	var i := args.find("--road")
	return int(args[i + 1]) if i >= 0 and i + 1 < args.size() else 2

## A spline that wanders: a sideways kink between each pair of control points.
func _meander(ctrl: Array, amount: float) -> PackedVector2Array:
	var pts := [ctrl[0]]
	for i in ctrl.size() - 1:
		var a: Vector2 = ctrl[i]
		var b: Vector2 = ctrl[i + 1]
		var side := (b - a).orthogonal().normalized()
		if i > 0 and i < ctrl.size() - 2:
			pts.append((a + b) * 0.5 + side * rng.randf_range(0.5, 1.0) * amount * (1.0 if i % 2 == 0 else -1.0))
		pts.append(b)
	for i in pts.size():
		var q: Vector2 = pts[i]
		pts[i] = Vector2(clampf(q.x, -32, 32), q.y)
	return _spline(pts, 6)

func _lay_road(style: int) -> void:
	match style:
		1:
			# two wheel ruts with grass between, a worn shoulder only at the bends
			for i in path_poly.size() - 1:
				var a: Vector2 = path_poly[i]
				var b: Vector2 = path_poly[i + 1]
				var n := (b - a).orthogonal().normalized()
				for s in [-1.1, 1.1]:
					dirt_lines.append([a + n * s, b + n * s, 0.95])
			_edge_stones(path_poly, 2.3, 0.35)
		2:
			# flagstones down the middle, packed dirt shoulders, kerbs, a milestone now and then
			for i in path_poly.size() - 1:
				dirt_lines.append([path_poly[i], path_poly[i + 1], 4.2])
				cobble_lines.append([path_poly[i], path_poly[i + 1], 3.3])
			var dist := 0.0
			var next_mile := 12.0
			for i in path_poly.size() - 1:
				var a: Vector2 = path_poly[i]
				var b: Vector2 = path_poly[i + 1]
				var seg := a.distance_to(b)
				var dir := (b - a) / maxf(seg, 0.001)
				var n := dir.orthogonal()
				var u := 0.0
				while u < seg:
					var c := a + dir * u
					for s in [-1.0, 1.0]:
						if rng.randf() < 0.55:
							var kp: Vector2 = c + n * s * 2.95
							var v := rng.randi_range(0, 7)
							if not rock_xf.has(v):
								rock_xf[v] = []
							var kb := Basis(Vector3.UP, atan2(dir.x, dir.y) + rng.randf_range(-0.15, 0.15)).scaled(Vector3(0.5, rng.randf_range(0.25, 0.4), rng.randf_range(0.8, 1.1)))
							rock_xf[v].append(Transform3D(kb, Vector3(kp.x, height_at(kp.x, kp.y) + 0.02, kp.y)))
					u += 1.1
				dist += seg
				if dist > next_mile and i > 2 and i < path_poly.size() - 4:
					next_mile += rng.randf_range(22, 30)
					var mp := a + n * (3.8 if i % 2 == 0 else -3.8)
					var ms := Models.N(null, "milestone")
					Models.P(ms, Geo.box(0.5, 1.1, 0.35), Props.stone_clean(), Vector3(0, 0.5, 0))
					Models.P(ms, Geo.cyl(0.25, 0.25, 0.35, 10), Props.stone_clean(), Vector3(0, 1.05, 0), Vector3(90, 0, 0))
					Models.P(ms, Geo.box(0.06, 0.28, 0.02), Mats.glow(Color(0.9, 0.55, 0.2), 0.8), Vector3(0, 0.7, 0.18))
					_place(ms, Vector3(mp.x, 0, mp.y))
					ms.rotation = Vector3(rng.randf_range(-0.1, 0.1), atan2(dir.x, dir.y), rng.randf_range(-0.12, 0.12))
					add_circle(Vector3(mp.x, 0, mp.y), 0.4)
		3:
			for i in path_poly.size() - 1:
				dirt_lines.append([path_poly[i], path_poly[i + 1], 2.6])
			_edge_stones(path_poly, 1.9, 0.4)
		_:
			for i in path_poly.size() - 1:
				dirt_lines.append([path_poly[i], path_poly[i + 1], 4.2])

## Small stones half sunk along both edges of a trail, so it reads against the grass.
func _edge_stones(poly: PackedVector2Array, half: float, chance: float) -> void:
	for i in poly.size() - 1:
		var a: Vector2 = poly[i]
		var b: Vector2 = poly[i + 1]
		var seg := a.distance_to(b)
		var dir := (b - a) / maxf(seg, 0.001)
		var u := 0.0
		while u < seg:
			for s: float in [-1.0, 1.0]:
				if rng.randf() < chance:
					var sp: Vector2 = a + dir * u + dir.orthogonal() * s * (half + rng.randf_range(-0.25, 0.35))
					_rock(Vector3(sp.x, 0, sp.y), rng.randf_range(0.22, 0.42), false)
			u += 1.3

## Style 3: a footpath from the road out to a landmark, with a cairn where it forks off.
func _side_trail(to: Vector2) -> void:
	var best := 0
	for i in path_poly.size():
		if path_poly[i].distance_to(to) < path_poly[best].distance_to(to):
			best = i
	var from: Vector2 = path_poly[best]
	if from.distance_to(to) < 4.0:
		return
	var mid := (from + to) * 0.5 + (to - from).orthogonal().normalized() * rng.randf_range(-2.5, 2.5)
	var poly := _spline([from, mid, to], 6)
	trails.append(poly)
	for i in poly.size() - 1:
		dirt_lines.append([poly[i], poly[i + 1], 1.7])
	_edge_stones(poly, 1.3, 0.3)
	# a cairn beside the fork
	var off := (to - from).normalized()
	var cp := from + off * 3.2 + off.orthogonal() * 1.8
	var g := Models.N(null, "cairn")
	var sm := Props.stone()
	var y := 0.0
	for k in 4:
		var r := 0.42 - k * 0.08
		Models.P(g, Props.rock_mesh(rng.randi_range(0, 7), 0.2), sm, Vector3(rng.randf_range(-0.04, 0.04), y + r * 0.5, 0), Vector3(0, rng.randf() * 360.0, 0), Vector3(r * 2.0, r * 1.1, r * 1.8))
		y += r * 0.95
	_place(g, Vector3(cp.x, 0, cp.y))
	add_circle(Vector3(cp.x, 0, cp.y), 0.45)

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
	solid(c)

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
	exits.append({"pos": p + Vector3(0, 0, 1.2), "radius": 1.6, "to": "lair", "label": act_name("lair")})

func _build_wild() -> void:
	bounds = Rect2(-42, -214, 84, 216)
	theme = {"name": "wild"}
	var ctrl := [Vector2(0, 2), Vector2(0, -14)]
	var x := 0.0
	for i in 8:
		x = clampf(x + rng.randf_range(-18, 18), -26, 26)
		ctrl.append(Vector2(x, -36 - i * 21))
	ctrl.append(Vector2(clampf(x * 0.5, -15, 15), -202))
	var style := road_style()
	path_poly = _meander(ctrl, 7.0) if style == 1 or style == 3 else _spline(ctrl, 6)
	_lay_road(style)
	for i in range(2, ctrl.size() - 1, 2):
		dirt_blobs.append([ctrl[i] + Vector2(rng.randf_range(-3, 3), rng.randf_range(-3, 3)), rng.randf_range(6, 9), 0.85])
	var end_p: Vector2 = ctrl[ctrl.size() - 1]
	dirt_blobs.append([end_p + Vector2(0, 3), 9.0, 1.0])
	cobble_blobs.append([end_p + Vector2(0, 4), 5.0, 0.9])
	exits.append({"pos": Vector3(0, 0, 0.5), "radius": 2.6, "to": "town", "label": act_name("town")})
	if fort:
		Fort.trail_end(self, Vector3(end_p.x, 0, end_p.y - 4.0))
	else:
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
	add_waypoint("wild", Vector3(wpp.x, 0, wpp.y), true)
	var kinds := ["healing", "fury", "armor", "experience"]
	kinds.shuffle()
	var shrine_ps := []
	for i in 2:
		var cc: Vector2 = ctrl[2 + i * 4]
		var sp := Vector2(clampf(cc.x + (7 if i == 0 else -7), -34, 34), cc.y - 3)
		_shrine(Vector3(sp.x, 0, sp.y), kinds[i])
		shrine_ps.append(sp + Vector2(0, 1.6))
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
	var cart := Props.footprint(Models.N(null, "cart"), Vector2(0.85, 1.35))
	Models.P(cart, Geo.box(1.6, 0.12, 2.6), Props.wood(), Vector3(0, 0.6, 0), Vector3(0, 0, 8))
	Models.P(cart, Geo.box(0.1, 0.5, 2.6), Props.wood(), Vector3(0.78, 0.85, 0), Vector3(0, 0, 8))
	Models.P(cart, Geo.cyl(0.55, 0.55, 0.1, 14), Props.wood_dark(), Vector3(-0.9, 0.4, 0.8), Vector3(0, 0, 90))
	Models.P(cart, Geo.cyl(0.55, 0.55, 0.1, 14), Props.wood_dark(), Vector3(0.6, 0.05, -1.4), Vector3(90, 30, 0))
	solid(_place(cart, Vector3(c2.x + 4.5, 0, c2.y + 2)))
	if style == 3:
		for lm in [circle_c, gy + Vector2(0, 2.5), wpp] + shrine_ps:
			_side_trail(lm)

	if oak_forest:
		sloth_lairs = SlothLair.pick(self)
		# bare earth under each lair (its decal paints the element over it)
		for l in sloth_lairs:
			dirt_blobs.append([Vector2(l.x, l.z), SlothLair.CLEAR * 0.9, 0.9])
	# vegetation
	var dt_meshes := [Flora.dead_tree(11), Flora.dead_tree(23), Flora.dead_tree(37)]
	var pine_meshes := [Flora.pine(4), Flora.pine(5), Flora.pine(6)]
	var oak_meshes := [Flora.oak_model(1), Flora.oak_model(2), Flora.oak_model(3)]
	var bush_mesh := Flora.bush(3)
	var groups := {}
	for i in 1700:
		var px := rng.randf_range(bounds.position.x - MARGIN + 3, bounds.end.x + MARGIN - 3)
		var pz := rng.randf_range(bounds.position.y - MARGIN + 3, bounds.end.y + 4)
		var inside := bounds.grow(-1.5).has_point(Vector2(px, pz))
		var pd := path_dist(px, pz) if inside else 99.0
		if inside and (pd < (6.5 if style == 0 or style == 2 else 3.6) or is_near_obstacle(Vector3(px, 0, pz), 2.5)):
			continue
		if inside and rng.randf() < 0.3:
			continue
		if _in_lair(px, pz):
			continue
		var r := rng.randf()
		var key := ""
		# Act I is an old oak forest: mostly oaks, some pines, the odd dead tree; other acts as before
		var cut := [0.3, 0.38, 0.7] if oak_forest else [0.38, 0.6, 0.7]
		if oak_forest:
			if r < 0.4:
				key = "oak%d" % (i % 3)
			elif r < 0.66:
				key = "pine%d" % (i % 3)
			elif r < 0.72:
				key = "dead%d" % (i % 3)
			else:
				key = "bush"
		elif r < cut[0]:
			key = "pine%d" % (i % 3)
		elif r < cut[1]:
			key = "dead%d" % (i % 3)
		elif r < cut[2]:
			key = "oak%d" % (i % 3)
		else:
			key = "bush"
		if not groups.has(key):
			groups[key] = []
		var s := rng.randf_range(0.8, 1.35)
		groups[key].append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * s), Vector3(px, height_at(px, pz) - 0.15, pz)))
		if inside and key != "bush":
			add_circle(Vector3(px, 0, pz), 0.45 if key.begins_with("dead") else (0.7 * s if key.begins_with("oak") else 0.55))
	# Act I: groves of three to five oaks a little off the road, with bushes at their feet
	if oak_forest:
		for gi in 26:
			var t := rng.randf_range(0.04, 0.97)
			var c0: Vector2 = path_poly[int((path_poly.size() - 1) * t)]
			var side := -1.0 if rng.randf() < 0.5 else 1.0
			var cg := c0 + Vector2(side * rng.randf_range(10.0, 17.0), rng.randf_range(-4.0, 4.0))
			for ti in rng.randi_range(3, 5):
				var a := rng.randf() * TAU
				var pg := cg + Vector2(cos(a), sin(a)) * rng.randf_range(0.0, 5.5)
				if not bounds.grow(-1.5).has_point(pg) or path_dist(pg.x, pg.y) < 7.0 or is_near_obstacle(Vector3(pg.x, 0, pg.y), 3.2) or _in_lair(pg.x, pg.y):
					continue
				var key2 := "oak%d" % rng.randi_range(0, 2)
				if not groups.has(key2):
					groups[key2] = []
				var s2 := rng.randf_range(0.9, 1.3)
				groups[key2].append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * s2), Vector3(pg.x, height_at(pg.x, pg.y) - 0.1, pg.y)))
				add_circle(Vector3(pg.x, 0, pg.y), 0.7 * s2)
				if rng.randf() < 0.6:
					var pb := pg + Vector2(rng.randf_range(-2.5, 2.5), rng.randf_range(-2.5, 2.5))
					if path_dist(pb.x, pb.y) > 5.0:
						if not groups.has("bush"):
							groups["bush"] = []
						groups["bush"].append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * rng.randf_range(0.8, 1.2)), Vector3(pb.x, height_at(pb.x, pb.y) - 0.15, pb.y)))
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
		# the Act I forest has many big oaks: past ~90 m they're off any screen anyway
		mm_chunked(mesh, groups[key], true, 32.0, 90.0 if (oak_forest and key.begins_with("oak")) else 0.0)
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
	_build_terrain(MOOR_ROAD if road_style() == 2 else MOOR_TERRAIN if road_style() == 0 else MOOR_TRAIL)
	_scatter_grass(94000, MOOR_GRASS, 0.32)
	_scatter_ferns(700)
	if oak_forest:
		_rare_flowers(3)

	# monster packs along the path
	var foes: Array = act_info()["foes"]
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
	if oak_forest:
		_feral_packs(groups, pid)
		_bear_dens(2, end_p)
		_sloths()
	spawns["start"] = Vector3(0, 0, -6)
	for k in [["road", 0.22], ["road2", 0.5]]:
		var rp: Vector2 = path_poly[int(path_poly.size() * k[1])]
		spawns[k[0]] = Vector3(rp.x, 0, rp.y)
	spawns["from_town"] = Vector3(0, 0, -6)
	spawns["from_lair"] = Vector3(end_p.x, 0, end_p.y + 4.5)

# ---------------------------------------------------------------- dungeon: the crypt and Grubb's Hoard
var floor_rects: Array = []
## Goblin tunnels in the boss vault: where King Grubb's Gold Grabbers climb out (hoard.gd).
var hoard_holes: Array = []

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
			_hoard_room(r, c)
			for corner in [Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 1), Vector2(1, 1)]:
				var bp := Vector3(c.x + corner.x * 11.0, 0, c.y + corner.y * 11.0)
				var br := Models.N(null, "brazier")
				Models.P(br, Geo.cyl(0.1, 0.2, 1.1, 8), Props.iron(), Vector3(0, 0.55, 0))
				Models.P(br, Geo.lathe([Vector2(0.05, 0.0), Vector2(0.4, 0.1), Vector2(0.45, 0.32), Vector2(0.0, 0.22)], 12, "brazier2"), Props.iron(), Vector3(0, 1.1, 0))
				_place(br, bp)
				Props.fire(br, Vector3(0, 1.45, 0), 1.1, Color(1.0, 0.42, 0.15), true, corner.y < 0)
				add_circle(bp, 0.5)
			boss_spawn = {"kind": act_name("boss"), "pos": Vector3(c.x, 0, c.y - 3)}
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
			var foes: Array = act_info()["foes"]
			for k in rng.randi_range(1, 2):
				var ep := Vector3(rng.randf_range(r.position.x + 2, r.end.x - 2), 0, rng.randf_range(r.position.y + 2, r.end.y - 2))
				var kk: String = foes[rng.randi() % foes.size()]
				enemy_spawns.append({"kind": kk, "pos": ep, "count": rng.randi_range(3, 5), "champ": rng.randf() < 0.15 + ri * 0.04, "pack": ri * 10 + k, "level": level + ri / 2})
	_rasterize()
	# everything that is not floor is solid rock
	rock.resize(gw * gh)
	rock.fill(0)
	for y in gh:
		for xx in gw:
			var wx := origin.x + (xx + 0.5) * CELL
			var wz := origin.y + (y + 0.5) * CELL
			if not is_floor(wx, wz):
				rock[y * gw + xx] = 1
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
	exits.append({"pos": Vector3(r0.get_center().x, 0, r0.end.y - 0.8), "radius": 1.8, "to": "wild", "label": act_name("wild")})
	spawns["start"] = Vector3(r0.get_center().x, 0, r0.end.y - 5.0)
	spawns["boss_room"] = Vector3(boss_r.get_center().x, 0, boss_r.end.y - 3)

## King Grubb's vault: heaps of coins, open chests, his throne of chests, goblin tunnels.
func _hoard_room(r: Rect2, c: Vector2) -> void:
	var coin := Goblin.coin_mat(Goblin.GOLD, 1.0)
	var gm := Goblin.gold_m()
	# the throne at the north end: a heap of gold with a chair of stacked chests on it
	var tp := Vector3(c.x, 0, r.position.y + 2.6)
	var throne := Props.footprint(Models.N(null, "throne"), Vector2(1.9, 1.2))
	Models.P(throne, Goblin.mound_mesh(3.0, 0.9), coin, Vector3(0, 0, 0.3))
	var wd := Props.wood()
	Models.P(throne, Geo.box(1.6, 0.7, 1.1), wd, Vector3(0, 0.75, 0))
	Models.P(throne, Geo.box(1.4, 0.18, 0.9), Goblin.cloth_m(Color(0.42, 0.08, 0.36), Color(0.15, 0.02, 0.12)), Vector3(0, 1.24, -0.05))
	Models.P(throne, Geo.box(1.7, 0.08, 1.2), gm, Vector3(0, 1.12, 0))
	Models.P(throne, Geo.box(1.7, 1.9, 0.35), wd, Vector3(0, 1.9, 0.5))
	Models.P(throne, Geo.box(1.8, 0.1, 0.45), gm, Vector3(0, 2.86, 0.5))
	for sx in [-1, 1]:
		Models.P(throne, Geo.box(0.35, 0.5, 1.0), wd, Vector3(sx * 0.95, 1.35, 0.05))
		Models.P(throne, Geo.sph(0.14, 12), gm, Vector3(sx * 0.95, 1.68, -0.35))
		Models.P(throne, Geo.cone(0.12, 0.5, 8), gm, Vector3(sx * 0.75, 3.1, 0.5))
	Models.P(throne, Geo.sph(0.22, 14), Mats.glow(Color(1.0, 0.2, 0.1), 2.0), Vector3(0, 2.5, 0.31), Vector3.ZERO, Vector3(1, 1, 0.5))
	Models.P(throne, Geo.lathe([Vector2(0.3, 0.0), Vector2(0.34, 0.0), Vector2(0.36, 0.14), Vector2(0.3, 0.14), Vector2(0.3, 0.0)], 20, "throne_crown"), gm, Vector3(0, 2.95, 0.5))
	_place(throne, tp)
	solid(throne)
	var tl := OmniLight3D.new()
	tl.light_color = Color(1.0, 0.72, 0.35)
	tl.light_energy = 2.4
	tl.omni_range = 9.0
	tl.position = Vector3(0, 3.2, -1.5)
	tl.add_to_group("flicker")
	tl.set_meta("base", 2.4)
	throne.add_child(tl)
	# heaps of gold along the walls, open chests, scattered coins
	var heaps := [Vector2(-9.5, -7.5), Vector2(9.0, -8.0), Vector2(-10.0, 4.0), Vector2(9.5, 5.5), Vector2(-5.5, 10.0), Vector2(6.0, 10.5)]
	for i in heaps.size():
		var hp := Vector3(c.x + heaps[i].x, 0, c.y + heaps[i].y)
		var hr := rng.randf_range(1.6, 2.3)
		var heap := Props.footprint(Models.N(null, "heap"), hr * 0.65)
		Models.P(heap, Goblin.mound_mesh(hr, hr * 0.42), coin)
		_place(heap, hp)
		solid(heap)
		if i % 2 == 0:
			var hl := OmniLight3D.new()
			hl.light_color = Color(1.0, 0.75, 0.35)
			hl.light_energy = 1.3
			hl.omni_range = 5.0
			hl.position = Vector3(0, 1.6, 0)
			heap.add_child(hl)
	for k in 4:
		var cp := Vector3(c.x + (-6.0 if k % 2 == 0 else 6.5) + rng.randf_range(-1, 1), 0, c.y + (-3.0 if k < 2 else 2.0) * 2.0)
		if not is_near_obstacle(cp, 1.5):
			_treasure_chest(cp, rng.randf_range(0, 360))
	var cx := []
	for k in 260:
		var a := rng.randf() * TAU
		var d := pow(rng.randf(), 0.6) * 12.5
		var cpos := Vector3(c.x + cos(a) * d, 0.006, c.y + sin(a) * d)
		cx.append(Transform3D(Basis.from_euler(Vector3(rng.randf_range(-0.25, 0.25), rng.randf() * TAU, rng.randf_range(-0.25, 0.25))), cpos))
	Props.multimesh(props_root, Geo.cyl(0.055, 0.055, 0.012, 10), cx, false).material_override = Mats.mat(Color(1.0, 0.74, 0.3), 0.35, 0.7, Color(1.0, 0.7, 0.25), 0.35)
	# goblin tunnels in the floor near the walls
	hoard_holes = []
	for hp2 in [Vector2(-12.0, -1.0), Vector2(12.0, 0.5), Vector2(-3.5, 12.0), Vector2(4.0, -11.5)]:
		var hp3 := Vector3(c.x + hp2.x, 0, c.y + hp2.y)
		var hole := Models.N(null, "hole")
		Models.P(hole, Geo.cyl(0.75, 0.75, 0.02, 20), Mats.flat(Color(0.0, 0.0, 0.0)), Vector3(0, 0.015, 0))
		Models.P(hole, Geo.torus(0.7, 1.05, 22, 6), Mats.world(Color(0.24, 0.17, 0.11), Color(0.15, 0.1, 0.07), 0.95, 2.0), Vector3(0, 0.04, 0), Vector3.ZERO, Vector3(1, 0.35, 1))
		for pl in 3:
			Models.P(hole, Geo.box(0.12, 0.05, 1.3), wd, Vector3(-0.4 + pl * 0.4, 0.07, 0), Vector3(0, 10 - pl * 8, 6))
		_place(hole, hp3)
		hoard_holes.append(hp3)

## An open treasure chest, overflowing.
func _treasure_chest(p: Vector3, yaw: float) -> void:
	var g := Props.footprint(Models.N(null, "tchest"), Vector2(0.6, 0.42))
	var wd := Props.wood()
	var gm := Goblin.gold_m()
	Models.P(g, Geo.box(1.1, 0.6, 0.75), wd, Vector3(0, 0.3, 0))
	for x in [-0.5, 0.5]:
		Models.P(g, Geo.box(0.07, 0.62, 0.78), gm, Vector3(x, 0.31, 0))
	Models.P(g, Goblin.mound_mesh(0.5, 0.28), Goblin.coin_mat(Goblin.GOLD, 1.6), Vector3(0, 0.58, 0), Vector3.ZERO, Vector3(1.0, 1.0, 0.7))
	var lid := Models.N(g, "lid", Vector3(0, 0.6, 0.37), Vector3(-110, 0, 0))
	Models.P(lid, Geo.box(1.1, 0.12, 0.75), wd, Vector3(0, 0.06, -0.375))
	Models.P(lid, Geo.box(1.12, 0.13, 0.08), gm, Vector3(0, 0.06, -0.72))
	Models.P(g, Geo.sph(0.06, 10), Mats.glow(Color(0.3, 0.5, 1.0), 2.0), Vector3(0.2, 0.78, -0.1))
	_place(g, p)
	g.rotation_degrees.y = yaw
	solid(g)

func _pillar(p: Vector3, h: float) -> void:
	var g := Models.N(null, "pillar")
	var sm := Props.stone_clean()
	Models.P(g, Geo.box(1.0, 0.4, 1.0), sm, Vector3(0, 0.2, 0))
	Models.P(g, Geo.cyl(0.36, 0.4, h - 0.8, 12), sm, Vector3(0, h * 0.5, 0))
	Models.P(g, Geo.box(1.0, 0.4, 1.0), sm, Vector3(0, h - 0.2, 0))
	_place(g, p)
	add_circle(p, 0.55)

func _sarcophagus(p: Vector3, yaw: float) -> void:
	var g := Props.footprint(Models.N(null, "sarc"), Vector2(0.6, 1.2))
	var sm := Props.stone_clean()
	Models.P(g, Geo.box(1.1, 0.8, 2.3), sm, Vector3(0, 0.4, 0))
	var lid := Models.P(g, Geo.box(1.2, 0.2, 2.4), sm, Vector3(0.15, 0.9, 0.1), Vector3(0, 8, 4))
	Models.P(g, Geo.sph(0.12, 8), Mats.world(Color(0.75, 0.7, 0.6), Color(0.6, 0.55, 0.45), 0.7, 3.0, 0.0, Props.MOSS, true), Vector3(-0.3, 0.12, 1.4))
	_place(g, p)
	g.rotation_degrees.y = yaw
	solid(g)

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
