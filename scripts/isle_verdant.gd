extends RefCounted
## Island 1, the Verdant Isle (isles.gd): rolling wooded hills, beaches on the landing side and low cliffs
## round the back, a forest so thick the light comes through green. Landmark: the Eldest, a colossal
## oak on a knoll in the middle, ringed by old rune stones round a mossy altar; you see its crown from
## the dock. Hidden clearings in the woods: a fern hollow with a ring of stones, an overgrown shrine.

const KNOLL := Vector2(-18.0, 10.0)          # island-local (u toward the dock, v across)
const CLEARINGS := [[Vector2(42.0, -48.0), 13.0], [Vector2(-58.0, 52.0), 11.0], [Vector2(30.0, 55.0), 10.0]]
const PATH := [Vector2(126.0, 0.0), Vector2(95.0, 6.0), Vector2(62.0, -4.0), Vector2(30.0, 8.0), Vector2(2.0, 9.0), Vector2(-10.0, 10.0)]

static func relief(isle: Dictionary, l: Vector2, s: float, rr: float, n: FastNoiseLite) -> float:
	var hills := 9.0 * smoothstep(0.0, rr * 0.7, s) * (0.55 + 0.55 * (n.get_noise_2dv(l) * 0.5 + 0.5))
	hills += 2.2 * n.get_noise_2dv(l * 2.7 + Vector2(40, 10))
	# the knoll under the Eldest
	hills += 6.0 * (1.0 - smoothstep(8.0, 30.0, l.distance_to(KNOLL)))
	return maxf(hills, 0.4)

static func pads(isle: Dictionary, n: FastNoiseLite) -> Array:
	var rr := float(isle["r"])
	var kh := 1.1 + relief(isle, KNOLL, rr, rr, n)
	return [[KNOLL, 9.0, kh]]

static func dress(w: World, isle: Dictionary, o: Vector2, full: bool, rng: RandomNumberGenerator) -> void:
	var path_d := func(l: Vector2) -> float:
		var m := 1e9
		for i in PATH.size() - 1:
			m = minf(m, l.distance_to(Geometry2D.get_closest_point_to_segment(l, PATH[i], PATH[i + 1])))
		return m
	var open := func(l: Vector2, h: float) -> bool:
		for c in CLEARINGS:
			if l.distance_to(c[0]) < float(c[1]):
				return false
		return l.distance_to(KNOLL) > 13.0 and float(path_d.call(l)) > 3.2
	var oaks := [[Flora.oak_model(1), 3.0, 1.0, 1.55], [Flora.oak_model(2), 3.0, 0.95, 1.5], [Flora.oak_model(3), 3.0, 1.0, 1.6],
		[Flora.pine(3), 0.8, 0.9, 1.3], [Flora.bush(2), 1.6, 0.9, 1.6], [Flora.bush(5), 1.4, 0.8, 1.4]]
	Isles.forest(w, isle, o, rng, 2600, oaks, open, full)
	# the Eldest: a vast oak on the knoll
	var kp := Isles.at(w, isle, o, KNOLL)
	var eld := Props.multimesh(w.props_root, Flora.oak_model(2), [Transform3D(Basis(Vector3.UP, 0.7).scaled(Vector3.ONE * 4.6), kp - Vector3(0, 0.6, 0))])
	eld.name = "the_eldest"
	if full:
		w.add_circle(kp, 2.6)
	# rune stones round the altar, glowing faintly like the camp's
	var rs: Array = []
	for i in 9:
		var a := TAU * i / 9.0
		var lp := KNOLL + Vector2(cos(a), sin(a)) * 7.5
		var p := Isles.at(w, isle, o, lp)
		rs.append(Transform3D(Basis(Vector3.UP, -a + PI * 0.5).scaled(Vector3.ONE * rng.randf_range(0.9, 1.25)), p - Vector3(0, 0.15, 0)))
		if full:
			w.add_circle(p, 0.45)
	if ForestCamp.ok():
		var rmm := Props.multimesh(w.props_root, ForestCamp.mesh(ForestCamp.DIR + "runestone.glb"), rs)
		rmm.material_override = ForestCamp._rune_material()
	var alt := Props.footprint(Models.N(null, "altar"), Vector2(0.9, 0.6))
	Models.P(alt, Geo.box(1.8, 0.8, 1.2), Props.stone(), Vector3(0, 0.4, 0))
	Models.P(alt, Geo.box(2.0, 0.16, 1.4), Props.stone_clean(), Vector3(0, 0.86, 0))
	var ap := Isles.at(w, isle, o, KNOLL + Vector2(4.5, 0))
	w._place(alt, ap)
	alt.rotation.y = Isles.yaw(isle, 0.0)
	if full:
		w.solid(alt)
		var gl := OmniLight3D.new()
		gl.light_color = Color(0.7, 1.0, 0.55)
		gl.light_energy = 1.4
		gl.omni_range = 9.0
		w.props_root.add_child(gl)
		gl.position = ap + Vector3(0, 1.6, 0)
		w.spawns["poi_eldest"] = ap + Vector3(2.0, 0, 0)
		_clearings(w, isle, o, rng)
		_path(w, isle, o)

## The hidden clearings: a fern hollow with a ring of fallen stones, an overgrown shrine of broken
## columns, a still glade (each a named spot for later: treasure, a quest, a guardian).
static func _clearings(w: World, isle: Dictionary, o: Vector2, rng: RandomNumberGenerator) -> void:
	var c0: Vector2 = CLEARINGS[0][0]
	for i in 7:
		var a := TAU * i / 7.0
		w._rock(Isles.at(w, isle, o, c0 + Vector2(cos(a), sin(a)) * 6.0), rng.randf_range(0.7, 1.3), true)
	w.spawns["poi_hollow"] = Isles.at(w, isle, o, c0)
	var c1: Vector2 = CLEARINGS[1][0]
	for i in 5:
		var a := TAU * i / 5.0 + 0.3
		Roman.column(w, Isles.at(w, isle, o, c1 + Vector2(cos(a), sin(a)) * 5.0), 3.4, 0.28, rng.randf_range(0.0, 0.7), Props.stone_clean())
	Roman.drum(w, Isles.at(w, isle, o, c1 + Vector2(1.5, -2.0)))
	w.spawns["poi_shrine"] = Isles.at(w, isle, o, c1)
	w.spawns["poi_glade"] = Isles.at(w, isle, o, CLEARINGS[2][0])

## A trodden path from the jetty up through the woods to the knoll.
static func _path(w: World, isle: Dictionary, o: Vector2) -> void:
	for i in PATH.size() - 1:
		var a := Isles.at(w, isle, o, PATH[i])
		var b := Isles.at(w, isle, o, PATH[i + 1])
		w.dirt_lines.append([Vector2(a.x, a.z), Vector2(b.x, b.z), 2.6])
