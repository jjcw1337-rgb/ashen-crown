extends RefCounted
## The proof range's ground (game/heroes/archer/tools/fire_range.gd): five lanes running east from x = X0 to X1, each its own surface:
## grass (the living 3D grass), stone (the terrain's flagstones), dirt, wooden planks with logs, and dark charred
## soil in the shadow of a wall. World.surface_fn (a meta) tells ArrowFx which surface a point is on.
const LANES := {"grass": -14.0, "stone": -7.0, "dirt": 0.0, "wood": 7.0, "dark": 14.0}
const HALF := 2.7
const X0 := -8.0
const X1 := 34.0

## Builds this range instead of the camp (the game boots into "town").
static func install() -> void:
	World.custom_zones["town"] = func(w: World) -> void: build(w)

static func lane_at(z: float) -> String:
	var best := "dirt"
	var bd := 99.0
	for k in LANES:
		var d: float = absf(z - float(LANES[k]))
		if d < bd:
			bd = d
			best = k
	return best if bd < HALF + 0.4 else "grass"

static func build(w: World) -> void:
	w.theme = {"name": "range"}
	w.bounds = Rect2(-22, -28, 66, 54)
	w.ground_fn = func(x: float, z: float) -> float:
		var y := -w.hnoise.get_noise_2d(x, z) * 0.35
		if lane_at(z) == "wood" and x > X0 and x < X1 and absf(z - float(LANES["wood"])) < HALF:
			y += 0.1
		return y
	w.set_meta("wood_grain", Vector3(0, 0, 1))     # the planks run across the lanes
	w.set_meta("surface_fn", func(p: Vector3) -> String: return lane_at(p.z) if p.x > X0 - 1.0 else "grass")
	# the terrain's own flagstones and earth for the stone and dirt lanes, packed earth under the planks and the char
	w.cobble_lines.append([Vector2(X0, LANES["stone"]), Vector2(X1, LANES["stone"]), HALF + 0.4])
	for k in ["dirt", "wood", "dark"]:
		w.dirt_lines.append([Vector2(X0, LANES[k]), Vector2(X1, LANES[k]), HALF + 0.4])
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	# planks across the wood lane, a few logs on them
	var wood_m := Props.wood()
	var dz: float = LANES["wood"]
	var x := X0
	while x < X1:
		var pw := rng.randf_range(0.22, 0.3)
		var b := MeshInstance3D.new()
		b.mesh = Geo.box(pw - 0.015, 0.09, HALF * 2.0)
		b.material_override = wood_m
		w.props_root.add_child(b)
		b.position = Vector3(x + pw * 0.5, 0.055 + rng.randf_range(-0.01, 0.01), dz + rng.randf_range(-0.08, 0.08))
		b.rotation.y = rng.randf_range(-0.012, 0.012)
		x += pw
	for i in 5:
		var lg := MeshInstance3D.new()
		lg.mesh = Geo.cyl(0.16, 0.18, rng.randf_range(1.6, 2.6), 12)
		lg.material_override = Props.wood_dark()
		w.props_root.add_child(lg)
		lg.position = Vector3(rng.randf_range(X0 + 2, X1 - 2), 0.27, dz + (HALF - 0.45) * (1.0 if i % 2 == 0 else -1.0))
		lg.rotation = Vector3(PI * 0.5, rng.randf_range(-0.3, 0.3), PI * 0.5)
	# the dark lane: charred soil, a wall on the sun's side (north) throwing it into shadow
	var dk := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(X1 - X0, HALF * 2.0)
	pm.subdivide_width = 40
	pm.subdivide_depth = 6
	dk.mesh = pm
	var dm := StandardMaterial3D.new()
	dm.albedo_color = Color(0.07, 0.062, 0.055)
	dm.roughness = 0.95
	var nt := NoiseTexture2D.new()
	var nz := FastNoiseLite.new()
	nz.frequency = 0.08
	nt.noise = nz
	nt.as_normal_map = true
	nt.bump_strength = 6.0
	nt.seamless = true
	dm.normal_enabled = true
	dm.normal_texture = nt
	dm.uv1_scale = Vector3(12, 2, 1)
	dk.material_override = dm
	w.props_root.add_child(dk)
	dk.position = Vector3((X0 + X1) * 0.5, 0.02, LANES["dark"])
	var wall := MeshInstance3D.new()
	wall.mesh = Geo.box(X1 - X0 + 6.0, 4.5, 0.6)
	wall.material_override = Props.stone()
	w.props_root.add_child(wall)
	wall.position = Vector3((X0 + X1) * 0.5, 2.25, LANES["dark"] - HALF - 0.95)
	# a backdrop: oaks and rocks beyond the lanes
	if w.oak_forest:
		for i in 9:
			var oak := MeshInstance3D.new()
			oak.mesh = Flora.oak_model(i % 3)
			w.props_root.add_child(oak)
			oak.position = Vector3(X0 + 2.0 + i * 4.6 + rng.randf_range(-1, 1), 0, LANES["grass"] - HALF - 4.5 - rng.randf_range(0, 3))
			oak.rotation.y = rng.randf() * TAU
	for i in 14:
		w._rock(Vector3(rng.randf_range(X0, X1), 0, LANES["grass"] - HALF - rng.randf_range(1.0, 2.5)), rng.randf_range(0.3, 0.9), false)
	w._rasterize()
	w._flush_stones(Props.stone())
	w._build_terrain(World.MOOR_TERRAIN)
	# the living 3D grass, on the grass lane and the verges only
	if w.oak_forest:
		Grass.scatter(w.props_root, Rect2(X0 - 6.0, LANES["grass"] - HALF - 3.0, X1 - X0 + 12.0, HALF * 2.0 + 3.0), _GrassCtx.new(w, func(z: float) -> String: return lane_at(z)), Grass.ACT1, World.detail, 99)
	w.spawns["start"] = Vector3(0, 0, LANES["dirt"])
	w.spawns["portal"] = Vector3(-4, 0, LANES["dirt"])

class _GrassCtx:
	var w: World
	var lane: Callable
	func _init(wv: World, lf: Callable) -> void:
		w = wv
		lane = lf
	func grass_ground(x: float, z: float) -> float:
		if str(lane.call(z)) != "grass" and x > X0 and x < X1:
			return 0.0
		return 1.0 if absf(z - float(LANES["grass"])) < HALF + 3.0 else 0.0
	func grass_height(x: float, z: float) -> float:
		return w.height_at(x, z)
	func grass_biome(_x: float, _z: float) -> Dictionary:
		return {"meadow": 1.0, "verge": 0.2, "woodland": 0.0, "dry": 0.25, "trampled": 0.0}

