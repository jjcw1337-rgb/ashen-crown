extends RefCounted
## Island 5 (straight out from the dock), the Lost Isle (isles.gd): a plateau ringed by sheer 17 m
## cliffs, one beach and a ravine climbing from it to the top. On the plateau, a pine wood round a
## ring of standing stones, and at the centre the Monolith: a rune-carved spire of black stone as tall
## as a tower, its runes glowing like the camp's, visible from the dock across the whole sea. Off the
## north cliffs a sea arch; under the south cliffs a cave mouth at the waterline (its dungeon, later).

const MONO := Vector2(-8.0, 0.0)          # island-local
const PLATEAU := 16.0
const ARCH := Vector2(-30.0, -128.0)
const CAVE := Vector2(-10.0, 118.0)

static func relief(isle: Dictionary, l: Vector2, s: float, rr: float, n: FastNoiseLite) -> float:
	var top := PLATEAU * smoothstep(0.0, 9.0, s) + 3.0 * (n.get_noise_2dv(l) * 0.5 + 0.5) * smoothstep(10.0, 40.0, s)
	top += 5.0 * (1.0 - smoothstep(10.0, 46.0, l.distance_to(MONO)))
	# the ravine from the beach up to the plateau
	var along := clampf((rr - l.x - 8.0) / 74.0, 0.0, 1.0)
	var ramp := PLATEAU * smoothstep(0.0, 1.0, along) + 0.2
	var across := absf(l.y) - 4.0 * sin(along * PI)
	var inr := 1.0 - smoothstep(6.0, 13.0, across)
	if l.x > 0.0:
		top = lerpf(top, minf(top, ramp), inr)
	return top

static func pads(isle: Dictionary, n: FastNoiseLite) -> Array:
	var rr := float(isle["r"])
	var mh := 1.1 + relief(isle, MONO, rr, rr, n)
	return [[MONO, 12.0, mh]]

static func dress(w: World, isle: Dictionary, o: Vector2, full: bool, rng: RandomNumberGenerator) -> void:
	var mp := Isles.at(w, isle, o, MONO)
	# the Monolith: a tapering black spire, its faces cut with glowing runes
	var mono := Props.footprint(Models.N(null, "monolith"), Vector2(2.4, 2.0))
	var mat := ForestCamp._rune_material() if ForestCamp.ok() else Props.stone()
	var dark := Mats.world(Color(0.07, 0.07, 0.08), Color(0.03, 0.03, 0.04), 0.6, 1.4, 0.0)
	Models.P(mono, Geo.box(6.0, 1.2, 5.0), dark, Vector3(0, 0.6, 0))
	Models.P(mono, Geo.cyl(1.9, 2.6, 18.0, 4), mat, Vector3(0, 10.2, 0), Vector3(0, 45, 0))
	Models.P(mono, Geo.cyl(0.05, 1.9, 4.5, 4), mat, Vector3(0, 21.4, 0), Vector3(0, 45, 0))
	w._place(mono, mp)
	mono.rotation.y = Isles.yaw(isle, 0.2)
	var glow := OmniLight3D.new()
	glow.light_color = Color(0.45, 0.8, 1.0)
	glow.light_energy = 2.2 if full else 3.5
	glow.omni_range = 16.0 if full else 30.0
	mono.add_child(glow)
	glow.position = Vector3(0, 12.0, 0)
	if full:
		w.solid(mono)
	# the standing stones round it
	for i in 12:
		var a := TAU * i / 12.0
		var lp := MONO + Vector2(cos(a), sin(a)) * 11.0
		var p := Isles.at(w, isle, o, lp)
		var st := Props.footprint(Models.N(null, "stone"), 0.5)
		Models.P(st, Props.rock_mesh(rng.randi_range(0, 7), 0.25), Props.stone(), Vector3(0, 1.4, 0), Vector3.ZERO, Vector3(0.9, 3.4 + rng.randf() * 1.4, 0.7))
		w._place(st, p)
		st.rotation.y = -a
		if full:
			w.solid(st)
	# the sea arch off the north cliffs: two legs of rock and a bridge
	for leg in [Vector2(-8.0, 0.0), Vector2(8.0, 0.0)]:
		var lp: Vector2 = ARCH + leg
		var p := Isles.at(w, isle, o, lp)
		var g := Models.N(w.props_root, "arch_leg")
		Models.P(g, Props.rock_mesh(rng.randi_range(0, 7), 0.3), Props.stone(), Vector3.ZERO, Vector3.ZERO, Vector3(6.5, 40.0, 6.0))
		g.position = Vector3(p.x, p.y + 12.0, p.z)
	var ap := Isles.at(w, isle, o, ARCH)
	var br := Models.N(w.props_root, "arch_top")
	Models.P(br, Props.rock_mesh(3, 0.3), Props.stone(), Vector3.ZERO, Vector3.ZERO, Vector3(24.0, 7.0, 7.0))
	br.position = Vector3(ap.x, 16.0, ap.z)
	br.rotation.y = Isles.yaw(isle, PI * 0.5)
	Isles.sea_rock(w, Vector2(Isles.at(w, isle, o, ARCH + Vector2(-8, 0)).x, Isles.at(w, isle, o, ARCH + Vector2(-8, 0)).z), 3.0)
	Isles.sea_rock(w, Vector2(Isles.at(w, isle, o, ARCH + Vector2(8, 0)).x, Isles.at(w, isle, o, ARCH + Vector2(8, 0)).z), 3.0)
	# pines over the plateau, thinner near the cliff edge
	var pines := [[Flora.pine(1), 2.0, 1.0, 1.6], [Flora.pine(2), 2.0, 1.0, 1.7], [Flora.pine(4), 1.5, 1.1, 1.8], [Flora.oak_model(1), 0.6, 0.9, 1.3], [Flora.bush(4), 1.0, 0.9, 1.4]]
	Isles.forest(w, isle, o, rng, 1500, pines, func(l: Vector2, h: float) -> bool: return h > 12.0 and l.distance_to(MONO) > 16.0 and not (l.x > 30.0 and absf(l.y) < 12.0), full)
	if full:
		w.spawns["poi_monolith"] = mp + Vector3(6.0, 0, 0)
		w.spawns["poi_arch"] = Isles.at(w, isle, o, ARCH * 0.82)      # the cliff top over the arch
		w.spawns["poi_cave"] = Isles.at(w, isle, o, CAVE)
