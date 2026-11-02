extends RefCounted
## Island 1, the Verdant Isle (isles.gd): rolling wooded hills, beaches on the landing side and low cliffs
## round the back, a forest so thick the light comes through green. Landmark: the Eldest, a colossal
## oak on a knoll in the middle, ringed by old rune stones round a mossy altar; you see its crown from
## the dock. Hidden clearings in the woods: a fern hollow with a ring of stones, an overgrown shrine.
## Island 1 of the level zones (level 10, Blaine 2026-11-01): the dinosaur island. Raptor packs along the path and
## in the hollow, a triceratops nest in the glade (the babies, and their mother in the brush beside it), and Gorehide
## the Tyrant in the domain round the Eldest.

const KNOLL := Vector2(-18.0, 10.0)          # island-local (u toward the dock, v across)
## Gorehide's domain: a wide open ground beyond the knoll, ringed by the forest (the boss arena; its pits later)
const DOMAIN := Vector2(-62.0, -22.0)
const DOMAIN_R := 26.0
## a second, smaller troll camp beside the path; the dwarves' tunnel, hidden deep in the jungle off the path
const CAMP2 := Vector2(40.0, 30.0)
const TUNNEL := Vector2(82.0, -64.0)
const CLEARINGS := [[Vector2(42.0, -48.0), 13.0], [Vector2(-58.0, 52.0), 11.0], [Vector2(30.0, 55.0), 10.0]]
const PATH := [Vector2(126.0, 0.0), Vector2(95.0, 6.0), Vector2(62.0, -4.0), Vector2(30.0, 8.0), Vector2(2.0, 9.0), Vector2(-10.0, 10.0)]

static func relief(isle: Dictionary, l: Vector2, s: float, rr: float, n: FastNoiseLite) -> float:
	var hills := 9.0 * smoothstep(0.0, rr * 0.7, s) * (0.55 + 0.55 * (n.get_noise_2dv(l) * 0.5 + 0.5))
	hills += 2.2 * n.get_noise_2dv(l * 2.7 + Vector2(40, 10))
	# the knoll under the Eldest
	hills += 6.0 * (1.0 - smoothstep(8.0, 30.0, l.distance_to(KNOLL)))
	# Gorehide's domain: levelled to a broad floor (the arena), easing back into the hills at its edge
	var dk := smoothstep(DOMAIN_R * 0.75, DOMAIN_R * 1.3, l.distance_to(DOMAIN))
	hills = lerpf(3.0, hills, dk)
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
		# (and the way on from the knoll into the domain)
		m = minf(m, l.distance_to(Geometry2D.get_closest_point_to_segment(l, KNOLL + Vector2(-10.0, -6.0), DOMAIN + Vector2(DOMAIN_R * 0.6, DOMAIN_R * 0.35))) - 0.6)
		return m
	var open := func(l: Vector2, h: float) -> bool:
		for c in CLEARINGS:
			if l.distance_to(c[0]) < float(c[1]):
				return false
		return l.distance_to(KNOLL) > 13.0 and l.distance_to(DOMAIN) > DOMAIN_R and l.distance_to(CAMP2) > 9.0 and l.distance_to(TUNNEL) > 4.0 \
			and float(path_d.call(l)) > 3.2
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
		_dinos(w, isle, o)

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
	# on from the knoll into Gorehide's domain
	var k := Isles.at(w, isle, o, KNOLL + Vector2(-10.0, -6.0))
	var d := Isles.at(w, isle, o, DOMAIN + Vector2(DOMAIN_R * 0.6, DOMAIN_R * 0.35))
	w.dirt_lines.append([Vector2(k.x, k.z), Vector2(d.x, d.z), 3.4])

## The island's dinosaurs (Data.ENEMIES raptor, trike, trike_baby, trex): packs and their places; the host spawns
## them (Game.load_zone, World.enemy_spawns). Levels from the island's own (Isles "level").
static func _dinos(w: World, isle: Dictionary, o: Vector2) -> void:
	var lv := int(isle.get("level", 10))
	var add := func(kind: String, l: Vector2, n: int, plus: int, pack: int, champ := false):
		w.enemy_spawns.append({"kind": kind, "pos": Isles.at(w, isle, o, l), "count": n, "champ": champ, "pack": pack, "level": lv + plus})
	# raptors: in the woods beside the path as it climbs, and a bigger pack in the hollow
	add.call("raptor", Vector2(96.0, 22.0), 3, 0, 1100)
	add.call("raptor", Vector2(66.0, -20.0), 3, 0, 1101)
	add.call("raptor", Vector2(34.0, 26.0), 4, 1, 1102, true)
	add.call("raptor", CLEARINGS[0][0], 4, 1, 1103)
	# the troll camp in the hollow: beast-tamers round their fire, with the raptors they keep
	add.call("troll_shaman", CLEARINGS[0][0] + Vector2(2.0, 1.5), 2, 1, 1103)
	add.call("troll_shaman", CAMP2, 1, 1, 1102)
	var c0: Vector2 = CLEARINGS[0][0]
	var fire := Isles.at(w, isle, o, c0)
	Props.fire(w.props_root, fire, 1.6, Color(1.0, 0.55, 0.2), true)
	w.add_circle(fire, 0.9)
	# the camps (Meshy props, assets/models/isles/verdant/): huts facing the fire, totems, the raptors' pen
	_prop(w, isle, o, "troll_hut", c0 + Vector2(7.5, 4.0), 1.9)
	_prop(w, isle, o, "troll_hut", c0 + Vector2(-7.0, 5.5), 1.9)
	_prop(w, isle, o, "troll_totem", c0 + Vector2(3.5, -6.5), 0.4)
	_prop(w, isle, o, "troll_totem", c0 + Vector2(-4.5, -5.5), 0.4)
	_prop(w, isle, o, "raptor_pen", c0 + Vector2(0.0, 10.0), 0.0)
	_prop(w, isle, o, "troll_hut", CAMP2 + Vector2(3.0, 3.0), 1.9)
	_prop(w, isle, o, "troll_totem", CAMP2 + Vector2(-2.5, -1.5), 0.4)
	Props.fire(w.props_root, Isles.at(w, isle, o, CAMP2), 1.1, Color(1.0, 0.55, 0.2), true)
	# the tunnel's mouth, half lost in the jungle (where the drunken dwarves are: later its own cave)
	_prop(w, isle, o, "tunnel", TUNNEL, 2.2)
	w.spawns["poi_tunnel"] = Isles.at(w, isle, o, TUNNEL)
	# the nest in the glade: babies, and their mother waiting in the brush beside it
	var glade: Vector2 = CLEARINGS[2][0]
	add.call("trike_baby", glade + Vector2(1.5, 2.5), 3, -2, 1110)
	_prop(w, isle, o, "egg_nest", glade, 0.0)
	# their mother isn't to be seen until you come near them: then she crashes out of the brush (World.ambushes)
	var bush := Isles.at(w, isle, o, glade + Vector2(13.0, 9.0))
	w.ambushes.append({"pos": Isles.at(w, isle, o, glade), "radius": 7.0, "done": false, "land": Isles.at(w, isle, o, glade + Vector2(4.0, 3.0)),
		"msg": "The mother!", "sound": "trike_bellow", "pitch": 0.9,
		"spawns": [{"kind": "trike", "pos": bush, "count": 1, "level": lv + 1, "champ": false, "pack": 1111}]})
	# the Tyrant: the domain round the Eldest
	add.call("trex", DOMAIN, 1, 2, 1120)

## One of the island's Meshy props at an island-local spot, turned to `yaw` (island-local), solid; nothing without the file.
static func _prop(w: World, isle: Dictionary, o: Vector2, name: String, l: Vector2, yaw: float) -> void:
	var m := Isles.prop("verdant/" + name)
	if m == null:
		return
	var p := Isles.at(w, isle, o, l)
	w._place(m, p)
	m.rotation.y = Isles.yaw(isle, yaw)
	var r := {"troll_hut": 2.0, "troll_totem": 0.35, "raptor_pen": 0.0, "egg_nest": 1.2, "tunnel": 0.0}.get(name, 0.8) as float
	if r > 0.0:
		w.add_circle(p, r)

