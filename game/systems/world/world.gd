class_name World
extends Node3D
## A playable zone: terrain, props, collision grid, pathfinding and spawn data.

const CELL := 1.0
const MARGIN := 30.0

var act := 0
var oak_forest := false     # the old forest (the Verdant Reach): its grass and leaf litter
var living_grass := false   # the living 3D grass (Grass) in the zone's own colours where oak_forest is off
var kind := ""
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
## Extra ground shaping for a zone (the Verdant Reach's ridges and stream): f(x, z) -> metres added to the height.
var ground_fn := Callable()
var dirt_blobs: Array = []     # [Vector2 pos, radius, strength]
var cobble_blobs: Array = []
var dirt_lines: Array = []     # [Vector2 a, Vector2 b, width]
var cobble_lines: Array = []   # [Vector2 a, Vector2 b, width] (paved roads)
## Trails through the zone (the Verdant Reach's paths); path_dist counts them too.
var trails: Array = []         # PackedVector2Array each
var obstacles: Array = []      # [Vector2 pos, radius]
var spawns := {}
var enemy_spawns: Array = []
var tree_pts := PackedVector2Array()   # trunk positions (x, z) of the zone's trees, for the undergrowth (Grass)
var _tree_grid := {}                   # Vector2i (4 m cell) -> trees in it
var _grass_dry := FastNoiseLite.new()
var interactables: Array = []
var exits: Array = []          # [{pos: Vector3, radius, to: String, label}]
var props_root: Node3D
var enemies_root: Node3D
var items_root: Node3D
var fx_root: Node3D
var stone_xf: Array = []
var rock_xf := {}               # variant -> Array of transforms
var theme := {}
## Tools can stage their own zone: kind -> Callable(world) built instead of the game's (game/heroes/archer/tools/fire_range.gd's test range).
static var custom_zones := {}

func _init() -> void:
	props_root = Models.N(self, "Props")
	enemies_root = Models.N(self, "Enemies")
	items_root = Models.N(self, "Items")
	fx_root = Models.N(self, "FX")

# ---------------------------------------------------------------- queries

## Where things stand: the ground, or a bridge's deck over it (decks).
func height_at(x: float, z: float) -> float:
	if decks.is_empty():
		return ground_h(x, z)
	return maxf(ground_h(x, z), deck_at(x, z))

## Walkable decks over water or a gap (the Verdant Reach's bridges): [centre Vector2, half size Vector2 (x across its
## length's normal frame like add_box), yaw, height]. The ground itself (terrain, grass) ignores them: they read
## ground_h.
var decks: Array = []

func add_deck(c: Vector2, half: Vector2, yaw: float, h: float) -> void:
	decks.append([c, half, yaw, h])

func deck_at(x: float, z: float) -> float:
	var best := -INF
	for d in decks:
		var lp := (Vector2(x, z) - (d[0] as Vector2)).rotated(float(d[2]))
		var half: Vector2 = d[1]
		if absf(lp.x) <= half.x and absf(lp.y) <= half.y:
			best = maxf(best, float(d[3]))
	return best

## The bare ground (no decks).
func ground_h(x: float, z: float) -> float:
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
	terrain_patch(bounds.grow(MARGIN), 1.0, tcol, "Terrain")

## A piece of ground over `r`, `step` metres between vertices (far ground can be coarser than the ground under the
## hero). Cells wholly deeper than `floor_y` are left out.
func terrain_patch(r: Rect2, step: float, tcol: Dictionary, nm := "Terrain", floor_y := -INF, own := Callable(), drop := 0.0, clip := Callable()) -> MeshInstance3D:
	if not masks_ready:
		_bake_masks()
	var x0 := r.position.x
	var z0 := r.position.y
	var nx := int(r.size.x / step)
	var nz := int(r.size.y / step)
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
			hs[j * (nx + 3) + i] = ground_h(x0 + (i - 1) * step, z0 + (j - 1) * step)
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
			verts[k] = Vector3(x, hc - drop, z)
			if clip.is_valid():
				# (the island camp: a vertex past the edge is drawn in onto it, so the ground ends in a smooth line)
				var q: Vector3 = clip.call(x, z, hc - drop)
				verts[k] = q
			norms[k] = Vector3(hl - hr, 2.0 * step, hd - hu).normalized()
			var cliff := clampf((1.0 - norms[k].y) * 3.0, 0.0, 1.0)
			cols[k] = Color(dirt_at(x, z), cliff, cobble_at(x, z), 1.0)
	for j in nz:
		for i in nx:
			var a := j * (nx + 1) + i
			var b := a + 1
			var c := a + (nx + 1)
			var d := c + 1
			if verts[a].y < floor_y and verts[b].y < floor_y and verts[c].y < floor_y and verts[d].y < floor_y:
				continue
			if own.is_valid() and not bool(own.call(x0 + (i + 0.5) * step, z0 + (j + 0.5) * step)):
				continue
			idx.append_array([a, b, d, a, d, c])
	if idx.is_empty():
		return null
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
	# the ground's small detail: pebbles and grit in the dirt from Medium up, fallen leaves in Act I's oak woods
	mat.set_shader_parameter("ground_detail", 1.0 if detail >= 1 else 0.0)
	mat.set_shader_parameter("litter", 1.0 if oak_forest and detail >= 1 else 0.0)
	mesh.surface_set_material(0, mat)
	var mi := MeshInstance3D.new()
	mi.name = nm
	mi.mesh = mesh
	add_child(mi)
	# Godot culls clockwise as front; flip if our winding is inverted
	mi.set_meta("terrain", true)
	return mi

## Grass (grass.gd) asks the zone three things about a spot. How much grass can grow (0 bare .. 1 full):
## none on the road or under solid things, thinning toward the edges of paths.
func grass_ground(x: float, z: float) -> float:
	var dm := dirt_at(x, z) + cobble_at(x, z)
	if dm > 0.55:
		return 0.0
	if bounds.grow(-1.2).has_point(Vector2(x, z)) and is_blocked(x, z):
		return 0.0
	return clampf(1.0 - dm * 1.6, 0.0, 1.0)

func grass_height(x: float, z: float) -> float:
	return height_at(x, z)

## Biome weights (Grass.BIOMES): meadow by default, sparse verges along paths, undergrowth among the
## trees, dry patches drifting across the ground, and the camp's trodden ground.
func grass_biome(x: float, z: float) -> Dictionary:
	if _tree_grid.is_empty() and tree_pts.size() > 0:
		for p in tree_pts:
			var c := Vector2i(int(floor(p.x / 4.0)), int(floor(p.y / 4.0)))
			_tree_grid[c] = int(_tree_grid.get(c, 0)) + 1
	var verge := clampf((dirt_at(x, z) + cobble_at(x, z)) * 3.0, 0.0, 1.0)
	var cx := int(floor(x / 4.0))
	var cz := int(floor(z / 4.0))
	var trees := 0
	for j in range(-1, 2):
		for i in range(-1, 2):
			trees += int(_tree_grid.get(Vector2i(cx + i, cz + j), 0))
	var wood := clampf((trees - 0.5) / 3.0, 0.0, 1.0)
	var dry := smoothstep(0.2, 0.55, _grass_dry.get_noise_2d(x, z)) * 0.7
	return {"meadow": maxf(0.1, 1.0 - verge * 0.8 - wood * 0.75 - dry * 0.7), "verge": verge, "woodland": wood, "dry": dry, "trampled": 0.0}

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
		var b := Props.boulder(int(v))
		if b.is_empty():
			mm_chunked(Props.rock_mesh(v, 0.38), rock_xf[v], true, 32.0, 0.0, Props.stone())
		else:
			mm_chunked(b[0], Props.seat(rock_xf[v], b[3]), true, 32.0, 0.0, b[1])

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
	if custom_zones.has(kind):
		(custom_zones[kind] as Callable).call(self)
		return
	Maps.build(self)      # (the map that builds this zone: game/maps/maps.gd)
	# the Meshy pieces that keep their glb's own material dither away round the hero too, like every code-built prop
	Props.see_through(self)
	Props.shadow_twins(self)

## Act I's green ground and grass (the archer's fire range, the grass and flora tools).
const MOOR_TERRAIN := {
	"col_a": Color(0.15, 0.2, 0.08), "col_b": Color(0.21, 0.23, 0.11), "col_accent": Color(0.28, 0.3, 0.13),
	"col_path": Color(0.25, 0.21, 0.16), "col_cliff": Color(0.3, 0.3, 0.28), "wet": 0.3,
}
const MOOR_GRASS := {"base_col": Color(0.12, 0.16, 0.06), "tip_col": Color(0.27, 0.32, 0.13), "dry_col": Color(0.36, 0.35, 0.18), "wind": 1.0}

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

# ---------------------------------------------------------------- paths
## How far (x, z) is from the nearest trail (1e9 with none).
func path_dist(x: float, z: float) -> float:
	var best := 1e9
	var p := Vector2(x, z)
	for tr in trails:
		var poly: PackedVector2Array = tr
		for i in poly.size() - 1:
			best = minf(best, p.distance_to(Geometry2D.get_closest_point_to_segment(p, poly[i], poly[i + 1])))
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

func _standing_stone(p: Vector3, h: float) -> void:
	var g := Models.N(null, "menhir")
	Models.P(g, Props.rock_mesh(rng.randi_range(0, 7), 0.25), Props.stone(), Vector3(0, h * 0.42, 0), Vector3.ZERO, Vector3(0.9, h, 0.6))
	_place(g, p)
	g.rotation = Vector3(rng.randf_range(-0.08, 0.08), rng.randf() * TAU, rng.randf_range(-0.08, 0.08))
	add_circle(p, 0.5)

func _chest(p: Vector3) -> Inter:
	var yaw := rng.randf_range(-40, 40)
	var c: Node3D = Props.stash_chest(null, Vector3.ZERO, yaw)
	c.scale = Vector3.ONE * 0.75
	var t = _inter("chest", "Chest", p, 1.4, c)
	solid(c)
	return t

## Floors with walls round them (the Arena's hall).
var floor_rects: Array = []

