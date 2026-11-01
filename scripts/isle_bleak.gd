extends RefCounted
## Island 4 (south-west), the Bleak Isle (isles.gd): black rock heaved up in jagged ridges, dead and
## twisted trees, grey-black sand, a low fog that never lifts and a sickly green light in it. Landmark:
## the Spire, a hooked fang of black rock on the highest ridge that you can pick out from the dock.
## Below it a cave mouth breathing fog; on the landing beach the bones of a wrecked ship; inland an
## abandoned camp, its fire long cold, its tents torn.

const SPIRE := Vector2(-22.0, -30.0)       # island-local
const CAMP := Vector2(46.0, 34.0)
const CAVE := Vector2(-4.0, -46.0)
const WRECK := Vector2(118.0, -30.0)

static func relief(isle: Dictionary, l: Vector2, s: float, rr: float, n: FastNoiseLite) -> float:
	var ridge := 1.0 - absf(n.get_noise_2dv(l * 1.4 + Vector2(17, 3)))
	ridge = pow(ridge, 2.4)
	var h := 11.0 * ridge * smoothstep(0.0, rr * 0.55, s) + 2.5 * (n.get_noise_2dv(l * 3.1) * 0.5 + 0.5)
	h += 9.0 * (1.0 - smoothstep(6.0, 30.0, l.distance_to(SPIRE)))
	return h

static func pads(isle: Dictionary, n: FastNoiseLite) -> Array:
	var rr := float(isle["r"])
	var front := CAVE + Vector2(9.0, 0.0)
	return [[CAMP, 9.0, 1.1 + relief(isle, CAMP, rr - CAMP.length(), rr, n) * 0.8],
		[front, 6.0, 1.1 + relief(isle, front, rr - front.length(), rr, n) * 0.7]]

static func dark_rock() -> Material:
	return Mats.world(Color(0.1, 0.1, 0.11), Color(0.04, 0.04, 0.05), 0.75, 1.6, 0.15, Color(0.18, 0.22, 0.12))

static func dress(w: World, isle: Dictionary, o: Vector2, full: bool, rng: RandomNumberGenerator) -> void:
	var dr := dark_rock()
	# the Spire: a tall leaning fang on the highest ridge, smaller fangs round it
	var sp := Isles.at(w, isle, o, SPIRE)
	var spire := Models.N(w.props_root, "the_spire")
	Models.P(spire, Props.rock_mesh(5, 0.32), dr, Vector3(0, 9.0, 0), Vector3(0, 0, 8), Vector3(7.0, 34.0, 6.0))
	Models.P(spire, Props.rock_mesh(2, 0.4), dr, Vector3(1.6, 19.0, 0.4), Vector3(0, 30, -24), Vector3(3.2, 14.0, 3.0))
	spire.position = sp
	spire.rotation.y = Isles.yaw(isle, 0.6)
	if full:
		w.add_circle(sp, 3.2)
	for i in 26:
		var a := rng.randf() * TAU
		var lp := SPIRE + Vector2(cos(a), sin(a)) * rng.randf_range(9.0, 60.0)
		var p := Isles.at(w, isle, o, lp)
		if p.y < 2.0:
			continue
		var g := Models.N(w.props_root, "fang")
		var hh := rng.randf_range(5.0, 16.0)
		Models.P(g, Props.rock_mesh(rng.randi_range(0, 7), 0.35), dr, Vector3(0, hh * 0.25, 0), Vector3(rng.randf_range(-12, 12), 0, rng.randf_range(-12, 12)), Vector3(hh * 0.28, hh, hh * 0.25))
		g.position = p
		if full:
			w.add_circle(p, hh * 0.11)
	# dead trees, twisted and leaning
	var dead: Array = [[Flora.dead_tree(3), 1.5, 0.9, 1.5], [Flora.dead_tree(7), 1.5, 0.9, 1.6], [Flora.dead_tree(11), 1.0, 1.2, 1.9]]
	if ResourceLoader.exists("res://assets/models/trees/deadtree.glb"):
		dead.append([ForestCamp.mesh("res://assets/models/trees/deadtree.glb"), 2.0, 0.9, 1.4])
	Isles.forest(w, isle, o, rng, 700, dead, func(l: Vector2, h: float) -> bool: return rng.randf() < 0.55 and l.distance_to(SPIRE) > 8.0, full, 0.3)
	_wreck(w, isle, o, rng, full)
	_camp(w, isle, o, rng, full)
	_fog_bank(w, isle, o)
	# the cave mouth under the Spire: a ring of black boulders round a dark hollow
	var cp := Isles.at(w, isle, o, CAVE)
	for i in 9:
		var a := PI + (i - 4) * 0.32
		var lp := CAVE + Vector2(cos(a), sin(a)) * 4.2
		var p := Isles.at(w, isle, o, lp)
		var g := Models.N(w.props_root, "cave_rock")
		Models.P(g, Props.rock_mesh(rng.randi_range(0, 7), 0.3), dr, Vector3(0, 1.4, 0), Vector3.ZERO, Vector3(3.0, 4.0 + (4 - absi(i - 4)) * 0.9, 2.6))
		g.position = p
		if full:
			w.add_circle(p, 1.2)
	var hole := Models.N(w.props_root, "cave_dark")
	Models.P(hole, Geo.box(4.2, 3.2, 0.2), Mats.mat(Color(0.0, 0.0, 0.0), 1.0), Vector3(0, 1.6, -1.5))
	hole.position = cp
	hole.rotation.y = Isles.yaw(isle, PI)
	if full:
		w.spawns["poi_spire"] = sp + Vector3(5.0, 0, 5.0)
		w.spawns["poi_cave"] = cp
		w.spawns["poi_camp"] = Isles.at(w, isle, o, CAMP)
		w.spawns["poi_wreck"] = Isles.at(w, isle, o, WRECK)
		var gl := OmniLight3D.new()
		gl.light_color = Color(0.45, 0.85, 0.5)
		gl.light_energy = 1.6
		gl.omni_range = 14.0
		w.props_root.add_child(gl)
		gl.position = cp + Vector3(0, 2.0, 2.0)

## A wrecked ship on its side in the shallows: the keel, ribs standing like bones, a few planks, the
## mast snapped and lying across the sand.
static func _wreck(w: World, isle: Dictionary, o: Vector2, rng: RandomNumberGenerator, full: bool) -> void:
	var p := Isles.at(w, isle, o, WRECK)
	var mw := Isles.prop("wreck")
	if mw:
		# the Meshy wreck, 20 m from stem to stern, heeled over and settled into the sand
		var gw := Props.footprint(Models.N(null, "wreck"), Vector2(9.4, 2.8))
		gw.add_child(mw)
		w._place(gw, Vector3(p.x, maxf(p.y, -0.6) - 0.7, p.z))
		gw.position.y = maxf(p.y, -0.6) - 0.7
		gw.rotation = Vector3(0, Isles.yaw(isle, 0.4), deg_to_rad(6))
		if full:
			w.solid(gw)
		else:
			Isles.sea_rock(w, Vector2(p.x, p.z), 6.0)
		return
	var g := Models.N(w.props_root, "wreck")
	var wd := Props.wood_dark()
	Models.seg(g, Vector3(-9, 0.2, 0), Vector3(9, 0.6, 0), 0.35, 0.3, wd, 6)
	for k in 13:
		var x := -8.0 + k * 1.35
		var span := 3.2 * sin(PI * (k + 0.5) / 13.0) + 0.6
		var broken := rng.randf() < 0.35
		for sd in [-1.0, 1.0]:
			if broken and sd > 0.0:
				continue
			var top := Vector3(x, 3.2 * (0.8 + 0.2 * sin(PI * k / 12.0)), sd * span)
			Models.seg(g, Vector3(x, 0.3, 0), Vector3(x, 1.4, sd * span * 1.05), 0.12, 0.11, wd, 5)
			Models.seg(g, Vector3(x, 1.4, sd * span * 1.05), top, 0.11, 0.08, wd, 5)
	for k in 6:
		Models.P(g, Geo.box(rng.randf_range(4.0, 8.0), 0.08, 0.35), wd, Vector3(rng.randf_range(-4, 4), 1.1 + k * 0.3, -2.6 + rng.randf() * 0.4), Vector3(rng.randf_range(-6, 6), 0, rng.randf_range(-30, -12)))
	Models.seg(g, Vector3(1.0, 0.2, -1.0), Vector3(-6.0, 0.4, 9.0), 0.22, 0.18, wd, 7)
	g.position = Vector3(p.x, maxf(p.y, -0.6), p.z)
	g.rotation = Vector3(deg_to_rad(18), Isles.yaw(isle, 0.4), 0)
	if full:
		w.add_box(Vector3(p.x, 0, p.z), Vector2(3.2, 8.5), g.rotation.y)
	else:
		Isles.sea_rock(w, Vector2(p.x, p.z), 6.0)

## The abandoned camp: torn tents, a cold fire ring, crates and barrels knocked over.
static func _camp(w: World, isle: Dictionary, o: Vector2, rng: RandomNumberGenerator, full: bool) -> void:
	var c := Isles.at(w, isle, o, CAMP)
	for i in 3:
		var a := TAU * i / 3.0 + 0.4
		var tp := Isles.at(w, isle, o, CAMP + Vector2(cos(a), sin(a)) * 5.5)
		var t := Props.hide_tent(w.props_root, tp, rad_to_deg(-a + PI * 0.5), 3.0, 3.2, 2.0)
		t.rotation.z = deg_to_rad(rng.randf_range(-12, 12))
		if full:
			w.add_box(tp, Vector2(1.6, 1.8), t.rotation.y)
	if not full:
		return
	for i in 7:
		var lp := CAMP + Vector2(rng.randf_range(-7, 7), rng.randf_range(-7, 7))
		if lp.distance_to(CAMP) < 2.6:
			continue
		var p := Isles.at(w, isle, o, lp)
		if rng.randf() < 0.5:
			w.solid(Props.crate(w.props_root, p, rng.randf_range(0.8, 1.1)))
		else:
			var b := Props.barrel(w.props_root, p)
			b.rotation.x = deg_to_rad(90) if rng.randf() < 0.5 else 0.0
			w.solid(b)
	for i in 8:
		var a := TAU * i / 8.0
		w._rock(c + Vector3(cos(a) * 1.1, 0, sin(a) * 1.1), 0.35, false)

## The fog that never lifts: a low bank of green-grey mist lying over the whole isle and its shallows,
## thickest at the waterline, seen from the coast and the boat as well as ashore (a FogVolume: the
## volumetric fog of the High and Ultra presets; the isle's own zone also has its height fog, Game._isle_mood).
static func _fog_bank(w: World, isle: Dictionary, o: Vector2) -> void:
	var c := Isles.at(w, isle, o, Vector2.ZERO)
	var fv := FogVolume.new()
	fv.name = "fog_bank"
	fv.shape = RenderingServer.FOG_VOLUME_SHAPE_ELLIPSOID
	var rr := float(isle["r"]) * 1.25
	fv.size = Vector3(rr * 2.0, 22.0, rr * 2.0)
	var fm := FogMaterial.new()
	fm.density = 0.07
	fm.albedo = Color(0.6, 0.68, 0.58)
	fm.height_falloff = 0.18
	fm.edge_fade = 0.6
	fv.material = fm
	w.props_root.add_child(fv)
	fv.position = Vector3(c.x, 2.0, c.z)
