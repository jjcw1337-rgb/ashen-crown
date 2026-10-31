extends RefCounted
## Island 3 (south), the Merchant's Reach (isles.gd): low, rugged ground round a sheltered harbour.
## Two arms of piled rock close the bay in front of the landing, and behind the beach the trading post
## its people left in a night: storehouses and huts round a yard, crates and barrels still stacked,
## a loading crane, a wagon with a broken wheel, a second pier with nothing tied to it. Landmark: the
## beacon tower on the headland behind, its fire still lit by someone. Room for NPCs and a vendor later
## (the post's counter is a named spot).

const YARD := Vector2(96.0, 0.0)            # island-local
const BEACON := Vector2(-40.0, -62.0)

static func relief(isle: Dictionary, l: Vector2, s: float, rr: float, n: FastNoiseLite) -> float:
	var h := 4.5 * smoothstep(0.0, rr * 0.5, s) * (0.5 + 0.5 * (n.get_noise_2dv(l) * 0.5 + 0.5))
	h += 2.0 * absf(n.get_noise_2dv(l * 2.4 + Vector2(5, 5)))
	# the headland under the beacon
	h += 10.0 * (1.0 - smoothstep(10.0, 48.0, l.distance_to(BEACON)))
	return h

static func pads(isle: Dictionary, n: FastNoiseLite) -> Array:
	var rr := float(isle["r"])
	var bh := 1.1 + relief(isle, BEACON, rr - BEACON.length(), rr, n)
	return [[YARD, 17.0, 1.9], [BEACON, 6.0, bh]]

static func dress(w: World, isle: Dictionary, o: Vector2, full: bool, rng: RandomNumberGenerator) -> void:
	_harbour(w, isle, o, rng, full)
	_post(w, isle, o, rng, full)
	_beacon(w, isle, o, rng, full)
	var trees := [[Flora.pine(5), 2.0, 0.9, 1.4], [Flora.pine(6), 2.0, 0.9, 1.5], [Flora.oak_model(3), 0.8, 0.8, 1.2], [Flora.bush(3), 1.6, 0.8, 1.5]]
	Isles.forest(w, isle, o, rng, 900, trees, func(l: Vector2, h: float) -> bool: return rng.randf() < 0.6 and l.distance_to(YARD) > 24.0, full)

## Two curving breakwaters of big rocks out from the shore either side of the landing.
static func _harbour(w: World, isle: Dictionary, o: Vector2, rng: RandomNumberGenerator, full: bool) -> void:
	var r := float(isle["r"])
	for side in [-1.0, 1.0]:
		for k in 16:
			var t := k / 15.0
			var lp := Vector2(r - 4.0 + t * 30.0, side * (34.0 - t * t * 14.0))
			var p := Isles.at(w, isle, o, lp)
			var sc := rng.randf_range(2.2, 3.4)
			if p.y < -0.3:
				sc = maxf(sc, (-p.y + 0.8) / 0.28)
			w._rock(Vector3(p.x, 0, p.z), minf(sc, 9.0), full)
			Isles.sea_rock(w, Vector2(p.x, p.z), minf(sc, 9.0) * 0.5)
	# a second, longer pier along the bay
	var a := Vector2(r - 3.0, -18.0)
	var b := Vector2(r + 10.0, -18.0)
	var g := Models.N(w.props_root, "pier2")
	var len := a.distance_to(b)
	for k in int(len / 0.42):
		Models.P(g, Geo.box(0.38, 0.08, 2.2), Props.wood() if k % 5 else Props.wood_dark(), Vector3(-len * 0.5 + k * 0.42, 0.95, 0), Vector3(0, rng.randf_range(-2, 2), 0))
	for k in int(len / 3.0) + 1:
		for sz in [-1.0, 1.0]:
			Models.seg(g, Vector3(-len * 0.5 + k * 3.0, -4.0, sz), Vector3(-len * 0.5 + k * 3.0, 1.2, sz), 0.12, 0.11, Props.wood_dark(), 6)
	var mp := Isles.at(w, isle, o, (a + b) * 0.5)
	g.position = Vector3(mp.x, 0, mp.z)
	g.rotation.y = Isles.yaw(isle, PI * 0.5)

## The trading post round its yard: storehouses, huts, the counter, stacked goods, a crane.
static func _post(w: World, isle: Dictionary, o: Vector2, rng: RandomNumberGenerator, full: bool) -> void:
	var houses := [[Vector2(-12, -9), 0.0], [Vector2(-12, 9), PI], [Vector2(-2, -13), 0.3], [Vector2(-2, 13), PI - 0.3], [Vector2(-16, 0), PI * 0.5]]
	for hs in houses:
		var lp: Vector2 = YARD + hs[0]
		var p := Isles.at(w, isle, o, lp)
		var m := Fort.model("hut")
		var holder := Node3D.new()
		holder.name = "storehouse"
		if m == null:
			Props.hide_tent(holder, Vector3.ZERO, 0.0, 3.6, 3.6, 2.8)
		else:
			holder.add_child(m)
		w._place(holder, p)
		holder.rotation.y = Isles.yaw(isle, float(hs[1]) + PI * 0.5)
		holder.scale = Vector3.ONE * 1.25
		if full:
			w.add_circle(p, 2.6)
	# the counter where the factor kept his books (a vendor stands here later)
	var cp := Isles.at(w, isle, o, YARD + Vector2(-5, 0))
	var counter := Props.footprint(Models.N(null, "counter"), Vector2(1.8, 0.5))
	Models.P(counter, Geo.box(3.6, 1.0, 0.9), Props.wood(), Vector3(0, 0.5, 0))
	Models.P(counter, Geo.box(3.8, 0.08, 1.1), Props.wood_dark(), Vector3(0, 1.04, 0))
	for x in [-1.7, 1.7]:
		Models.seg(counter, Vector3(x, 1.0, -0.3), Vector3(x, 2.6, -0.3), 0.07, 0.06, Props.wood_dark(), 5)
	Models.P(counter, Geo.box(3.8, 0.06, 1.6), Props.hide_m(), Vector3(0, 2.62, 0.2), Vector3(-12, 0, 0))
	w._place(counter, cp)
	counter.rotation.y = Isles.yaw(isle, PI * 0.5)
	# the crane at the head of the jetty
	var kp := Isles.at(w, isle, o, Vector2(float(isle["r"]) - 6.0, 6.0))
	var crane := Models.N(w.props_root, "crane")
	var wd := Props.wood_dark()
	Models.seg(crane, Vector3.ZERO, Vector3(0, 6.5, 0), 0.22, 0.18, wd, 7)
	Models.seg(crane, Vector3(-1.0, 5.8, 0), Vector3(5.5, 7.2, 0), 0.14, 0.1, wd, 6)
	Models.seg(crane, Vector3(0, 0.5, 0), Vector3(-1.4, 0, 0), 0.16, 0.16, wd, 6)
	Models.seg(crane, Vector3(5.3, 7.1, 0), Vector3(5.3, 3.4, 0), 0.025, 0.025, Props.hide_m(), 4)
	Models.P(crane, Geo.box(0.8, 0.6, 0.8), Props.wood(), Vector3(5.3, 3.1, 0))
	crane.position = kp
	crane.rotation.y = Isles.yaw(isle, -0.6)
	if not full:
		return
	w.add_circle(kp, 0.5)
	w.spawns["poi_counter"] = cp + Vector3(1.5, 0, 0)
	w.spawns["poi_yard"] = Isles.at(w, isle, o, YARD)
	w.dirt_blobs.append([Vector2(Isles.at(w, isle, o, YARD).x, Isles.at(w, isle, o, YARD).z), 16.0, 0.95])
	var road := [Isles.at(w, isle, o, Vector2(float(isle["r"]) - 2.0, 0)), Isles.at(w, isle, o, YARD)]
	w.dirt_lines.append([Vector2(road[0].x, road[0].z), Vector2(road[1].x, road[1].z), 3.0])
	# goods left stacked in the yard and on the beach
	for i in 26:
		var lp := YARD + Vector2(rng.randf_range(-12, 14), rng.randf_range(-11, 11))
		if absf(lp.y) < 3.0 or lp.distance_to(YARD + Vector2(-5, 0)) < 3.0:
			continue
		var p := Isles.at(w, isle, o, lp)
		if w.is_near_obstacle(p, 1.0):
			continue
		match i % 3:
			0: w.solid(Props.crate(w.props_root, p, rng.randf_range(0.85, 1.2)))
			1: w.solid(Props.barrel(w.props_root, p))
			2: w.solid(Props.log_pile(w.props_root, p))
	if ForestCamp.ok():
		var wg := ForestCamp.model("wagon")
		w._place(wg, Isles.at(w, isle, o, YARD + Vector2(6, 9)))
		wg.rotation = Vector3(0, Isles.yaw(isle, 0.4), deg_to_rad(9))
		wg.scale = Vector3.ONE * 1.2
		w.add_circle(wg.position, 2.0)
	for lp2 in [YARD + Vector2(8, -3.5), YARD + Vector2(8, 3.5), YARD + Vector2(-8, 4)]:
		var lpp: Vector3 = Isles.at(w, isle, o, lp2)
		var post := Props.footprint(Models.N(null, "lpost"), 0.15)
		Models.seg(post, Vector3.ZERO, Vector3(0, 2.7, 0), 0.08, 0.06, Props.wood_dark(), 6)
		w._place(post, lpp)
		w.solid(post)
		Props.fire(w.props_root, lpp + Vector3(0, 2.85, 0), 0.22, Color(1.0, 0.7, 0.35), true, false, false)

## The beacon on the headland: a stone tower with a brazier on top, still burning.
static func _beacon(w: World, isle: Dictionary, o: Vector2, rng: RandomNumberGenerator, full: bool) -> void:
	var p := Isles.at(w, isle, o, BEACON)
	var g := Props.footprint(Models.N(null, "beacon"), 2.6)
	var sm := Props.stone_clean()
	Models.P(g, Geo.cyl(2.2, 2.7, 11.0, 12), sm, Vector3(0, 5.5, 0))
	Models.P(g, Geo.cyl(2.8, 2.8, 0.5, 12), Props.stone(), Vector3(0, 11.2, 0))
	for k in 8:
		var a := TAU * k / 8.0
		Models.P(g, Geo.box(0.7, 0.9, 0.5), sm, Vector3(cos(a) * 2.5, 11.9, sin(a) * 2.5), Vector3(0, -rad_to_deg(a), 0))
	Models.P(g, Geo.box(1.1, 2.0, 0.2), Mats.mat(Color(0.05, 0.04, 0.03), 1.0), Vector3(0, 1.0, 2.62))
	Models.P(g, Geo.cyl(0.9, 0.6, 0.7, 10), Props.iron(), Vector3(0, 11.8, 0))
	w._place(g, p)
	g.rotation.y = Isles.yaw(isle, 0.0)
	Props.fire(g, Vector3(0, 12.3, 0), 1.3, Color(1.0, 0.55, 0.2), true, false, true)
	if full:
		w.solid(g)
		w.spawns["poi_beacon"] = p + Vector3(4.0, 0, 0)
