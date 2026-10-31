class_name Coast
extends RefCounted
## Act I: the Mournwater Coast, west of the camp through its west gate. A wooded headland runs out
## into the sea with the open water on three sides; at its tip the dock (the boat's mooring, the
## shipwright's shed). Out on the water, the five islands of isles.gd, each about 250 m across and
## about 22 s of sailing from the dock, drawn at full size so you watch them grow as you sail.
##
## Frame: the dock's end is the origin, west is -x, the camera looks north (-z). The mainland's shore is
## a parabola round the headland's tip (`shore_x`), so the sea curls back along both sides of it.
##
## Everything you can walk on here is the headland (`World.bounds`); the islands are reached by boat and
## have their own zones (Isles.build_zone). The sea's extent (`sea_rect`) is worked out from the
## island table, so a new island gets water round it without touching this file.

const TIP := 14.0             # the headland's shore at its tip (x), in front of the dock
const SHORE_K := 0.012        # how fast the shore curls back east with distance from the tip
const BOUNDS := Rect2(-10, -55, 82, 110)
const DOCK := Vector2(0.0, 0.0)         # the end of the pier (where boats tie up)
const PIER_ROOT := Vector2(17.0, 0.0)
const SHED := Vector2(25.0, -10.0)      # the shipwright's shed (his stall: Stage 3)
const EXIT := Vector2(68.0, 0.0)        # the path back to the camp

static var _n: FastNoiseLite
static var _grids := {}

const TERRAIN := {
	"col_a": Color(0.15, 0.2, 0.08), "col_b": Color(0.21, 0.23, 0.11), "col_accent": Color(0.28, 0.3, 0.13),
	"col_path": Color(0.34, 0.29, 0.21), "col_cliff": Color(0.36, 0.35, 0.31), "wet": 0.35,
	"sea": 1.0, "col_sand": Color(0.63, 0.57, 0.43),
}
const FAR_TERRAIN := {
	"col_a": Color(0.13, 0.18, 0.08), "col_b": Color(0.18, 0.21, 0.1), "col_accent": Color(0.24, 0.27, 0.12),
	"col_path": Color(0.34, 0.29, 0.21), "col_cliff": Color(0.36, 0.35, 0.31), "wet": 0.35,
	"sea": 1.0, "col_sand": Color(0.6, 0.55, 0.42),
}

static func _noise() -> FastNoiseLite:
	if _n == null:
		_n = FastNoiseLite.new()
		_n.seed = 4711
		_n.frequency = 0.02
		_n.fractal_octaves = 3
	return _n

## Where the mainland's shore is at z (the headland's outline).
static func shore_x(z: float) -> float:
	return TIP + SHORE_K * z * z + _noise().get_noise_1d(z * 0.6 + 300.0) * 4.0 * smoothstep(20.0, 60.0, absf(z))

## The mainland's ground: a shelving beach, then meadow and woods rising inland.
static func mainland(p: Vector2) -> float:
	var s := (p.x - shore_x(p.y)) / sqrt(1.0 + pow(2.0 * SHORE_K * p.y, 2.0))
	if s < 0.0:
		return maxf(-0.25 + s * 0.2 - s * s * 0.006, Isles.DEEP)
	var n := _noise()
	var h := minf(s / 10.0, 1.0) * 1.1
	h += smoothstep(10.0, 80.0, s) * 5.0 + smoothstep(10.0, 30.0, s) * (n.get_noise_2d(p.x * 1.4, p.y * 1.4) * 0.5 + 0.5) * 1.6
	return h

## Ground height anywhere in the coast's frame: sea floor, mainland, islands.
static func ground(p: Vector2) -> float:
	var h := Isles.DEEP + _noise().get_noise_2d(p.x * 0.4, p.y * 0.4) * 1.5
	h = maxf(h, mainland(p))
	for isle in Isles.ISLANDS:
		var c := Isles.centre(isle)
		if p.distance_squared_to(c) < pow(float(isle["r"]) * 1.08 + 56.0, 2.0):
			h = maxf(h, Isles.elev_coast(isle, p))
	return h

## The whole sea: every island with water round it, and the mainland's shore behind the dock.
static func sea_rect() -> Rect2:
	var r := BOUNDS.grow(World.MARGIN)
	for isle in Isles.ISLANDS:
		var c := Isles.centre(isle)
		var e := float(isle["r"]) * 1.08 + 80.0
		r = r.merge(Rect2(c - Vector2(e, e), Vector2(e, e) * 2.0))
	return r

## Which island a coast-frame point belongs to (the nearest whose shelf reaches it), or "".
static func owner_of(p: Vector2) -> String:
	var best := ""
	var bd := 1e18
	for isle in Isles.ISLANDS:
		var d := p.distance_to(Isles.centre(isle))
		if d < float(isle["r"]) * 1.08 + 56.0 and d < bd:
			bd = d
			best = isle["id"]
	return best

## The whole sea's ground at 2 m (made once a session; the islands' own zones read it for the far shores).
static func coarse() -> HeightGrid:
	return _grid("coarse", sea_rect(), 2.0)

static func _grid(key: String, r: Rect2, cell: float) -> HeightGrid:
	if not _grids.has(key):
		_grids[key] = HeightGrid.new().bake(r, cell, func(x: float, z: float) -> float: return ground(Vector2(x, z)))
	return _grids[key]

# ---------------------------------------------------------------- the zone
static func build(w: World) -> void:
	w.sea = true
	w.steep = 1.35
	w.bounds = BOUNDS
	w.theme = {"name": "coast"}
	var fine := _grid("fine", BOUNDS.grow(World.MARGIN + 4.0), 1.0)
	var coarse := coarse()
	w.height_fn = func(x: float, z: float) -> float:
		if fine.has(x, z):
			return fine.sample(x, z)
		if coarse.has(x, z):
			return coarse.sample(x, z)
		return ground(Vector2(x, z))
	w.set_meta("sea_rect", sea_rect())
	_headland(w)
	for isle in Isles.ISLANDS:
		Isles.dress(w, isle, Isles.centre(isle), false)
	_far_shore(w)
	w.exits.append({"pos": Vector3(EXIT.x, 0, EXIT.y), "radius": 3.2, "to": "town", "label": w.act_name("town")})
	w.spawns["start"] = Vector3(EXIT.x - 6.0, 0, EXIT.y)
	w.spawns["from_town"] = w.spawns["start"]
	w.spawns["dock"] = Vector3(PIER_ROOT.x + 1.5, 0, PIER_ROOT.y + 2.5)
	for isle in Isles.ISLANDS:
		w.spawns["from_" + Isles.zone_of(isle["id"])] = w.spawns["dock"]
	w._rasterize()
	w._flush_stones(Props.stone())
	w.terrain_patch(BOUNDS.grow(World.MARGIN), 1.0, TERRAIN, "Terrain")
	distant(w, Vector2.ZERO, BOUNDS.grow(World.MARGIN))
	Grass.scatter(w.props_root, BOUNDS.grow(6.0), w, Grass.ACT1, World.detail, 3131)
	w._scatter_ferns(260)

## The sea's other ground, coarser, round a hole where the zone's own detailed ground is: each island
## (its own colours), and the mainland and sea floor. `o` is where the coast's origin sits in this
## zone (an island's zone shifts everything so the island is at its origin).
static func distant(w: World, o: Vector2, hole: Rect2, step := 2.0) -> void:
	var sr := sea_rect()
	for isle in Isles.ISLANDS:
		var c := Isles.centre(isle) + o
		var e := float(isle["r"]) * 1.08 + 56.0
		var id: String = isle["id"]
		var tc: Dictionary = (isle["terrain"] as Dictionary).duplicate()
		tc["sea"] = 1.0
		tc["col_sand"] = isle["sand"]
		w.terrain_patch(Rect2(c - Vector2(e, e), Vector2(e, e) * 2.0), step, tc, "far_" + id, Isles.DEEP + 1.0,
			func(x: float, z: float) -> bool: return not hole.has_point(Vector2(x, z)) and owner_of(Vector2(x, z) - o) == id)
	# the mainland and the sea floor: under the islands' patches too where it's deep (a little lower, so
	# there are no cracks between patches and the islands' own ground always wins), and on east past the
	# sea so the mainland never ends in sight
	var far := Rect2(sr.position + o, sr.size + Vector2(260.0, 0.0)).grow_individual(0, 120.0, 0, 120.0)
	w.terrain_patch(far, step * 2.0, FAR_TERRAIN, "far_sea", Isles.DEEP + 1.0,
		func(x: float, z: float) -> bool: return not hole.has_point(Vector2(x, z)) and (owner_of(Vector2(x, z) - o) == "" or w.ground_h(x, z) < -5.0), 0.25)

## The headland: a path from the camp's woods down to the dock, the pier, the shipwright's shed,
## boats pulled up on the sand, nets drying, lanterns, the woods closing in behind.
static func _headland(w: World) -> void:
	var rng := w.rng
	# the path from the woods to the pier
	var path := [EXIT + Vector2(8, 0), Vector2(52, 3), Vector2(38, -2), Vector2(27, 1), PIER_ROOT]
	for i in path.size() - 1:
		w.dirt_lines.append([path[i], path[i + 1], 3.0])
	w.dirt_blobs.append([SHED + Vector2(0, 4), 7.0, 0.9])
	w.dirt_blobs.append([PIER_ROOT + Vector2(3, 0), 5.0, 0.8])
	_pier(w)
	# the shipwright's shed: a hut with an awning, a hull on trestles beside it (his stall: Stage 3)
	var shed := Fort.model("hut")
	var holder := Node3D.new()
	holder.name = "shed"
	if shed == null:
		Props.hide_tent(holder, Vector3.ZERO, 0.0, 3.6, 3.6, 2.8)
	else:
		holder.add_child(shed)
	w._place(holder, Vector3(SHED.x, 0, SHED.y))
	holder.rotation.y = PI * 0.5 + 0.5
	holder.scale = Vector3.ONE * 1.35
	w.add_circle(Vector3(SHED.x, 0, SHED.y), 2.7)
	_trestle_hull(w, SHED + Vector2(-2.0, 7.5))
	# boats pulled up on the beach and nets drying on racks
	for bp in [Vector2(20.5, 9.0), Vector2(22.0, -19.0)]:
		_rowboat(w, bp, rng.randf_range(-0.5, 0.5) + PI * 0.5)
	for np in [Vector2(30.0, 9.5), Vector2(33.0, -15.0)]:
		_net_rack(w, np, rng.randf_range(-0.3, 0.3))
	for c in [[Vector2(23.5, -5.5), "crate"], [Vector2(24.3, -4.8), "crate"], [Vector2(22.8, -6.6), "barrel"], [Vector2(19.0, 3.4), "barrel"], [Vector2(28.0, -13.0), "logs"]]:
		var cp: Vector2 = c[0]
		var p3 := Vector3(cp.x, w.height_at(cp.x, cp.y), cp.y)
		match c[1]:
			"crate": w.solid(Props.crate(w.props_root, p3, rng.randf_range(0.9, 1.15)))
			"barrel": w.solid(Props.barrel(w.props_root, p3))
			"logs": w.solid(Props.log_pile(w.props_root, p3))
	for lp in [Vector2(20.0, -2.6), Vector2(36.0, 1.4), Vector2(52.0, 5.8)]:
		var post := Props.footprint(Models.N(null, "lpost"), 0.15)
		Models.seg(post, Vector3.ZERO, Vector3(0, 2.7, 0), 0.08, 0.06, Props.wood_dark(), 6)
		Models.seg(post, Vector3(0, 2.6, 0), Vector3(0.55, 2.62, 0), 0.04, 0.035, Props.wood_dark(), 5)
		w._place(post, Vector3(lp.x, 0, lp.y))
		w.solid(post)
		Props.fire(w.props_root, Vector3(lp.x + 0.5, w.height_at(lp.x, lp.y) + 2.35, lp.y), 0.2, Color(1.0, 0.68, 0.32), true, false, false)
	# boulders along the headland's shore
	for i in 70:
		var z := rng.randf_range(-80.0, 80.0)
		var x := shore_x(z) + rng.randf_range(-5.0, 2.0)
		if absf(z) < 14.0 and x < 22.0:
			continue
		var s := rng.randf_range(0.7, 2.2)
		var hy := w.height_at(x, z)
		if hy < -2.0:
			continue
		if hy < -0.3:
			s = maxf(s, (-hy + 0.6) / 0.28)
		w._rock(Vector3(x, 0, z), s, BOUNDS.has_point(Vector2(x, z)))
		if hy < 0.4:
			Isles.sea_rock(w, Vector2(x, z), s * 0.5)
	# the woods: thick behind the meadow, a few trees out on the headland
	var kinds := [Flora.oak_model(1), Flora.oak_model(2), Flora.oak_model(3), Flora.pine(1), Flora.pine(2)]
	var xf := [[], [], [], [], []]
	for i in 900:
		var x := rng.randf_range(BOUNDS.position.x - 25, BOUNDS.end.x + 40)
		var z := rng.randf_range(BOUNDS.position.y - 40, BOUNDS.end.y + 40)
		var hy := w.height_at(x, z)
		if hy < 1.6:
			continue
		var into := x - shore_x(z)
		var dens := smoothstep(18.0, 40.0, into)
		if rng.randf() > dens * 0.9 + 0.04:
			continue
		var q := Vector2(x, z)
		var near_path := false
		for k in path.size() - 1:
			if q.distance_to(Geometry2D.get_closest_point_to_segment(q, path[k], path[k + 1])) < 4.5:
				near_path = true
		if near_path or q.distance_to(SHED) < 7.0 or q.distance_to(EXIT) < 6.0:
			continue
		var k2 := rng.randi_range(0, 4)
		var sc := rng.randf_range(0.95, 1.5)
		(xf[k2] as Array).append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * sc), Vector3(x, hy - 0.15, z)))
		if BOUNDS.grow(2.0).has_point(q):
			w.add_circle(Vector3(x, 0, z), 0.55 * sc)
			w.tree_pts.append(q)
	for k in 5:
		w.mm_chunked(kinds[k], xf[k], true, 32.0, 0.0)

## Trees along the mainland's shore all round the bay, so the coast reads as forest from the sea.
static func _far_shore(w: World) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 919
	var kinds := [Flora.oak_model(1), Flora.oak_model(3), Flora.pine(2), Flora.pine(3)]
	var xf := [[], [], [], []]
	var sr := sea_rect()
	for i in 1600:
		var z := rng.randf_range(sr.position.y, sr.end.y)
		var x := shore_x(z) + rng.randf_range(14.0, 90.0)
		if BOUNDS.grow(40.0).has_point(Vector2(x, z)) or x > sr.end.x + 60.0:
			continue
		var hy := w.height_at(x, z)
		if hy < 1.5:
			continue
		var sc := rng.randf_range(1.0, 1.6)
		(xf[i % 4] as Array).append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * sc), Vector3(x, hy - 0.15, z)))
	for k in 4:
		w.mm_chunked(kinds[k], xf[k], false, 80.0, 0.0)

## The pier: planks on posts from the beach out past the shallows, bollards at its end.
static func _pier(w: World) -> void:
	var g := Models.N(w.props_root, "pier")
	var len := PIER_ROOT.distance_to(DOCK) + 1.0
	var deck := 1.0
	var wd := Props.wood()
	var wdd := Props.wood_dark()
	for k in int(len / 0.42):
		Models.P(g, Geo.box(0.38, 0.09, 3.0), wd if k % 4 else wdd, Vector3(-len * 0.5 + (k + 0.5) * 0.42, deck, 0), Vector3(0, w.rng.randf_range(-1.5, 1.5), 0))
	for k in int(len / 2.6) + 1:
		for sz in [-1.45, 1.45]:
			Models.seg(g, Vector3(-len * 0.5 + k * 2.6, -5.0, sz), Vector3(-len * 0.5 + k * 2.6, deck + (0.65 if k % 2 == 0 else 0.1), sz), 0.14, 0.13, wdd, 7)
	for sz in [-1.4, 1.4]:
		Models.P(g, Geo.box(len, 0.14, 0.2), wdd, Vector3(0, deck - 0.14, sz))
	for bz in [-1.2, 1.2]:
		Models.seg(g, Vector3(-len * 0.5 + 0.4, deck, bz), Vector3(-len * 0.5 + 0.4, deck + 0.55, bz), 0.16, 0.14, Props.iron(), 8)
	var mid := (PIER_ROOT + DOCK) * 0.5 + Vector2(-0.5, 0)
	g.position = Vector3(mid.x, 0.0, mid.y)
	Props.fire(w.props_root, Vector3(DOCK.x + 0.5, deck + 2.2, DOCK.y - 1.5), 0.24, Color(1.0, 0.7, 0.35), true, false, false)
	var lamp := Models.N(w.props_root, "pier_lamp")
	Models.seg(lamp, Vector3(DOCK.x + 0.5, deck, DOCK.y - 1.45), Vector3(DOCK.x + 0.5, deck + 2.1, DOCK.y - 1.45), 0.08, 0.07, wdd, 6)
	# walkers can stand on the pier (the sea check would stop them otherwise)
	w.add_deck(mid, Vector2((len + 1.0) * 0.5, 1.5), 0.0, deck + 0.05)

## A rowboat pulled up on the sand, tipped a little.
static func _rowboat(w: World, p: Vector2, yaw: float) -> void:
	var g := Props.footprint(Models.N(null, "rowboat"), Vector2(0.8, 2.0))
	var wd := Props.wood()
	var wdd := Props.wood_dark()
	Models.P(g, Geo.lathe([Vector2(0.0, 0.0), Vector2(0.55, 0.05), Vector2(0.75, 0.45), Vector2(0.8, 0.55)], 14, "rowhull"), wd, Vector3(0, 0.1, 0), Vector3.ZERO, Vector3(1.0, 1.0, 2.6))
	Models.P(g, Geo.box(1.3, 0.06, 0.3), wdd, Vector3(0, 0.5, 0.2))
	Models.P(g, Geo.box(1.1, 0.06, 0.3), wdd, Vector3(0, 0.5, -0.8))
	Models.seg(g, Vector3(0.4, 0.55, -0.5), Vector3(1.4, 0.1, 1.4), 0.03, 0.03, wdd, 5)
	w._place(g, Vector3(p.x, 0, p.y))
	g.rotation = Vector3(0, yaw, deg_to_rad(8))
	w.solid(g)

## A rack of poles with nets hung to dry.
static func _net_rack(w: World, p: Vector2, yaw: float) -> void:
	var g := Props.footprint(Models.N(null, "net_rack"), Vector2(2.2, 0.4))
	var wdd := Props.wood_dark()
	for x in [-2.0, 0.0, 2.0]:
		Models.seg(g, Vector3(x, 0, 0), Vector3(x, 2.0, 0), 0.06, 0.05, wdd, 5)
	Models.seg(g, Vector3(-2.1, 1.95, 0), Vector3(2.1, 1.95, 0), 0.05, 0.05, wdd, 5)
	var net := Mats.world(Color(0.42, 0.37, 0.28), Color(0.3, 0.27, 0.2), 0.95, 3.0)
	Models.P(g, Geo.box(4.0, 1.5, 0.03), net, Vector3(0, 1.2, 0.05))
	w._place(g, Vector3(p.x, 0, p.y))
	g.rotation.y = yaw
	w.solid(g)

## A hull under construction on trestles by the shed: keel, ribs, a few planks.
static func _trestle_hull(w: World, p: Vector2) -> void:
	var g := Props.footprint(Models.N(null, "hull_build"), Vector2(1.4, 3.6))
	var wd := Props.wood()
	var wdd := Props.wood_dark()
	for z in [-2.4, 0.0, 2.4]:
		Models.P(g, Geo.box(2.4, 0.12, 0.2), wdd, Vector3(0, 0.75, z))
		for x in [-1.0, 1.0]:
			Models.seg(g, Vector3(x * 1.1, 0, z), Vector3(x * 0.8, 0.75, z), 0.05, 0.05, wdd, 5)
	Models.seg(g, Vector3(0, 0.9, -3.4), Vector3(0, 0.9, 3.4), 0.12, 0.12, wd, 6)
	Models.seg(g, Vector3(0, 0.9, 3.4), Vector3(0, 2.0, 3.9), 0.1, 0.08, wd, 6)
	for k in 9:
		var z := -3.0 + k * 0.75
		var span := 1.05 * sin(PI * (k + 0.6) / 9.6)
		for sd in [-1.0, 1.0]:
			Models.seg(g, Vector3(0, 0.95, z), Vector3(sd * span, 1.35, z), 0.05, 0.05, wd, 4)
			Models.seg(g, Vector3(sd * span, 1.35, z), Vector3(sd * span * 1.12, 2.1, z), 0.05, 0.045, wd, 4)
	for k in 3:
		Models.P(g, Geo.box(0.06, 0.18, 5.2), wd, Vector3(0.9 - k * 0.04, 1.4 + k * 0.17, 0))
	w._place(g, Vector3(p.x, 0, p.y))
	g.rotation.y = 0.3
	w.solid(g)
