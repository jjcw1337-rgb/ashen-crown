extends RefCounted
## Island 2, the Forgotten Ruins (isles.gd): a hill cut into terraces by a people who served the
## Ashen King, climbing to a temple on the summit. Broken colonnades line the terrace edges, walls
## stand knee-high, column drums lie where they fell, cypresses grow through the paving. Landmarks seen
## from the sea: the temple's standing columns on the summit and a colossal statue that has toppled
## down the slope, its plinth still crowning the seaward terrace.

const STEP := 3.4                         # height of one terrace
const TEMPLE := Vector2(-6.0, 0.0)        # island-local
const COLOSSUS := Vector2(52.0, -34.0)
const STAIR := [Vector2(126.0, 0.0), Vector2(90.0, 0.0), Vector2(60.0, 2.0), Vector2(30.0, 0.0), Vector2(8.0, 0.0)]

static func _base(l: Vector2, s: float, rr: float, n: FastNoiseLite) -> float:
	var k := clampf(s / (rr * 0.82), 0.0, 1.0)
	return 19.0 * pow(k, 1.15) * (0.9 + 0.2 * (n.get_noise_2dv(l * 0.6) * 0.5 + 0.5))

static func relief(isle: Dictionary, l: Vector2, s: float, rr: float, n: FastNoiseLite) -> float:
	var b := _base(l, s, rr, n)
	var f := b / STEP
	var h: float = (floorf(f) + smoothstep(0.72, 1.0, f - floorf(f))) * STEP
	# the processional stair up the middle: a smooth ramp instead of steps
	var sd := 1e9
	for i in STAIR.size() - 1:
		sd = minf(sd, l.distance_to(Geometry2D.get_closest_point_to_segment(l, STAIR[i], STAIR[i + 1])))
	h = lerpf(b, h, smoothstep(2.5, 5.0, sd))
	return h

static func pads(isle: Dictionary, n: FastNoiseLite) -> Array:
	var rr := float(isle["r"])
	var th := 1.1 + relief(isle, TEMPLE, rr - TEMPLE.length(), rr, n)
	var ch := 1.1 + relief(isle, COLOSSUS, rr - COLOSSUS.length(), rr, n)
	return [[TEMPLE, 15.0, th], [COLOSSUS, 6.0, ch]]

static func dress(w: World, isle: Dictionary, o: Vector2, full: bool, rng: RandomNumberGenerator) -> void:
	var tp := Isles.at(w, isle, o, TEMPLE)
	# the temple: a peristyle of columns on a stepped platform, half of them standing
	var plat := Models.N(null, "temple_platform")
	for k in 3:
		Models.P(plat, Geo.box(22.0 - k * 1.6, 0.45, 15.0 - k * 1.6), Roman.marble(), Vector3(0, 0.22 + k * 0.45, 0))
	w._place(plat, tp)
	plat.rotation.y = Isles.yaw(isle, 0.0)
	var top := 1.35
	var cols := 0
	for ix in 7:
		for iz in 5:
			if ix != 0 and ix != 6 and iz != 0 and iz != 4:
				continue
			var lp := TEMPLE + Vector2(-9.0 + ix * 3.0, -6.0 + iz * 3.0)
			var p := Isles.at(w, isle, o, lp)
			p.y = tp.y + top
			var broken := 0.0 if rng.randf() < 0.55 else rng.randf_range(0.25, 0.85)
			var c := Roman.column(w, p, 6.5, 0.42, broken)
			c.position.y = tp.y + top
			cols += 1
			if broken > 0.0 and rng.randf() < 0.6:
				Roman.drum(w, Isles.at(w, isle, o, lp + Vector2(rng.randf_range(-2.5, 2.5), rng.randf_range(2.0, 4.0))), 0.42, 1.3)
	# the colossus: its empty plinth on the seaward terrace and the figure fallen down the slope
	var cp := Isles.at(w, isle, o, COLOSSUS)
	var pl := Props.footprint(Models.N(null, "colossus_plinth"), Vector2(2.6, 2.6))
	Models.P(pl, Geo.box(5.2, 4.2, 5.2), Roman.tuff(), Vector3(0, 2.1, 0))
	Models.P(pl, Geo.box(5.8, 0.5, 5.8), Roman.marble(), Vector3(0, 4.45, 0))
	w._place(pl, cp)
	pl.rotation.y = Isles.yaw(isle, 0.3)
	if full:
		w.solid(pl)
	var fallen := Roman.statue(w, Isles.at(w, isle, o, COLOSSUS + Vector2(14.0, 6.0)), Isles.yaw(isle, 1.2), 4.2, true)
	fallen.rotation.z = deg_to_rad(84)
	fallen.position.y += 1.2
	# colonnades along the terrace edges, walls, drums, cypresses
	var placed := 0
	for i in 70:
		var sp: Variant = Isles.land_spot(isle, rng, 2.5, 0.35, 4)
		if sp == null:
			continue
		var l: Vector2 = sp
		if Isles.near_pad(isle, l, 4.0) or l.distance_to(Vector2(80, 0)) < 12.0:
			continue
		var p := Isles.at(w, isle, o, l)
		var r := rng.randf()
		if r < 0.35:
			var d := Vector2(-l.y, l.x).normalized() * rng.randf_range(6.0, 14.0)
			var b := Isles.at(w, isle, o, l + d)
			if absf(b.y - p.y) < 0.6:
				Roman.colonnade(w, p, b, int(d.length() / 3.0) + 2, 4.2, true)
		elif r < 0.65:
			var d2 := Vector2(rng.randf_range(-1, 1), rng.randf_range(-1, 1)).normalized() * rng.randf_range(5.0, 11.0)
			var b2 := Isles.at(w, isle, o, l + d2)
			if absf(b2.y - p.y) < 0.8:
				Roman.ruin_wall(w, Vector2(p.x, p.z), Vector2(b2.x, b2.z), rng.randf_range(1.2, 2.4))
		elif r < 0.8:
			Roman.drum(w, p, 0.34, rng.randf_range(0.9, 1.4))
		else:
			Roman.column(w, p, rng.randf_range(3.5, 5.0), 0.32, rng.randf_range(0.0, 0.8))
		placed += 1
	var cyp: Array = []
	for i in 90:
		var sp2: Variant = Isles.land_spot(isle, rng, 2.0, 0.5, 3)
		if sp2 != null and not Isles.near_pad(isle, sp2, 3.0):
			cyp.append(Isles.at(w, isle, o, sp2))
	Roman.cypresses(w, cyp)
	var trees := [[Flora.oak_model(3), 1.0, 0.8, 1.2], [Flora.bush(7), 1.6, 0.8, 1.3], [Flora.bush(8), 1.2, 0.7, 1.2]]
	Isles.forest(w, isle, o, rng, 600, trees, func(l: Vector2, h: float) -> bool: return rng.randf() < 0.45, full)
	if full:
		for i in STAIR.size() - 1:
			var a := Isles.at(w, isle, o, STAIR[i])
			var b3 := Isles.at(w, isle, o, STAIR[i + 1])
			w.cobble_lines.append([Vector2(a.x, a.z), Vector2(b3.x, b3.z), 2.4])
			w.dirt_lines.append([Vector2(a.x, a.z), Vector2(b3.x, b3.z), 3.6])
		w.cobble_blobs.append([Vector2(tp.x, tp.z), 12.0, 0.7])
		w.spawns["poi_temple"] = tp + Vector3(0, top, 0)
		w.spawns["poi_colossus"] = cp
		var gl := OmniLight3D.new()
		gl.light_color = Color(1.0, 0.75, 0.45)
		gl.light_energy = 1.0
		gl.omni_range = 12.0
		w.props_root.add_child(gl)
		gl.position = tp + Vector3(0, 3.0, 0)
