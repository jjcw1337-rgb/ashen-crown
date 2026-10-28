class_name Fort
## King Grubb's fort (Act I and A2; A3's lair stays the Ashen King's crypt). The lair zone becomes an
## outdoor goblin stronghold: a muddy approach where the fort's guards are fighting the moor's dead,
## a palisade ring with a gatehouse and watchtowers, and inside a lived-in camp (huts, tents,
## cookfires, loot, racks, cages, totems) scattered organically round an open courtyard where Grubb
## sits on his hoard. The big pieces are Meshy models (assets/models/fort/*.glb, prepared by
## tools/blender/act1/prep_prop.py); without them simple log stand-ins are built.
## Layout: the approach runs north from the start; the fort's centre is CENTRE, its wall an ellipse.

const GLB := "res://assets/models/fort/%s.glb"
const CENTRE := Vector2(0, -88)
const RX := 33.0
const RZ := 40.0
const GATE_HALF := 5.0              # half the gate's width along the wall
const ARENA := Vector2(0, -97)      # Grubb's courtyard
const ARENA_R := 17.0
const SECTION := 5.0                # a palisade section's length
const GOBLIN_COLS := [Color(0.55, 0.45, 0.12), Color(0.24, 0.3, 0.1), Color(0.4, 0.12, 0.08)]

static var _models := {}

static func model(name: String) -> Node3D:
	var path := GLB % name
	if not ResourceLoader.exists(path):
		return null
	if not _models.has(name):
		_models[name] = load(path)
	return (_models[name] as PackedScene).instantiate()

## The wall ellipse's point at angle a (0 = east, PI/2 = south, toward the gate).
static func ring(a: float) -> Vector2:
	return CENTRE + Vector2(cos(a) * RX, sin(a) * RZ)

## How far out a point is in the wall ellipse (1 = on the wall).
static func ring_t(p: Vector2) -> float:
	var d := p - CENTRE
	return sqrt(pow(d.x / RX, 2) + pow(d.y / RZ, 2))

static func gate_pos() -> Vector2:
	return ring(PI * 0.5)

# ---------------------------------------------------------------- the zone
static func build(w: World) -> void:
	w.flat_floor = false
	w.theme = {"name": "fort"}
	w.bounds = Rect2(-58, -138, 116, 146)
	var gp := gate_pos()
	# ground: trodden mud inside the walls, a muddy track up to the gate, puddled patches outside
	w.dirt_blobs = []
	w.dirt_lines = []
	for i in 14:
		var a := TAU * i / 14.0
		w.dirt_blobs.append([CENTRE + Vector2(cos(a) * RX * 0.55, sin(a) * RZ * 0.55), 17.0, 1.0])
	w.dirt_blobs.append([CENTRE, 24.0, 1.0])
	var track := [Vector2(0, 4), Vector2(1.5, -10), Vector2(-2.0, -24), Vector2(0.5, -36), Vector2(gp.x, gp.y + 2)]
	var poly := w._spline(track, 6)
	for i in poly.size() - 1:
		w.dirt_lines.append([poly[i], poly[i + 1], 3.8])
	for i in 9:
		w.dirt_blobs.append([Vector2(w.rng.randf_range(-45, 45), w.rng.randf_range(-40, 0)), w.rng.randf_range(3, 7), 0.6])
	w.dirt_blobs.append([gp + Vector2(0, 8), 11.0, 1.0])
	# trampled flagstones and gravel patches inside: the old ground the goblins built over
	for i in 7:
		var a := w.rng.randf() * TAU
		var r := sqrt(w.rng.randf()) * 0.8
		w.cobble_blobs.append([CENTRE + Vector2(cos(a) * RX * r, sin(a) * RZ * r), w.rng.randf_range(2.5, 4.0), w.rng.randf_range(0.35, 0.55)])
	w.cobble_blobs.append([ARENA + Vector2(0, -11.0), 6.0, 0.9])
	_palisade(w)
	_gatehouse(w, gp)
	_towers(w)
	_courtyard(w)
	_camp(w)
	_approach(w, poly)
	_forest(w)
	w.exits.append({"pos": Vector3(0, 0, 3.0), "radius": 2.6, "to": "wild", "label": Data.ACTS[w.act]["wild"]})
	w.spawns["start"] = Vector3(0, 0, -3.0)
	w.spawns["boss_room"] = Vector3(ARENA.x, 0, ARENA.y + 12.0)
	w.spawns["gate"] = Vector3(gp.x, 0, gp.y + 6.0)
	w.spawns["camp"] = Vector3(gp.x + 10.0, 0, gp.y - 12.0)
	w.spawns["camp_w"] = Vector3(CENTRE.x - 20.0, 0, CENTRE.y + 6.0)
	w._rasterize()
	w._flush_stones(Props.stone())
	w._build_terrain(FORT_TERRAIN)
	w._scatter_grass(52000, World.MOOR_GRASS, 0.3)
	w._scatter_ferns(400)

const FORT_TERRAIN := {
	"col_a": Color(0.14, 0.18, 0.08), "col_b": Color(0.2, 0.21, 0.1), "col_accent": Color(0.27, 0.28, 0.12),
	"col_path": Color(0.3, 0.23, 0.15), "col_cliff": Color(0.28, 0.27, 0.24), "wet": 0.55, "cob_shade": 0.55,
}

# ---------------------------------------------------------------- walls, gate, towers
static func _palisade(w: World) -> void:
	# sections laid end to end round the ellipse, leaving the gate open
	var pts: Array = []
	var a := PI * 0.5 + 0.02
	var steps := 720
	var last := ring(a)
	pts.append(last)
	for i in steps:
		var aa := a + TAU * (i + 1) / steps
		var p := ring(aa)
		if p.distance_to(last) >= SECTION * 0.96:
			pts.append(p)
			last = p
	var gp := gate_pos()
	for i in pts.size() - 1:
		var p0: Vector2 = pts[i]
		var p1: Vector2 = pts[i + 1]
		var mid := (p0 + p1) * 0.5
		if mid.distance_to(gp) < GATE_HALF + SECTION * 0.5:
			continue
		var d := p1 - p0
		var yaw := atan2(-d.y, d.x)
		var sec := model("palisade")
		if sec == null:
			sec = _stakes(d.length())
		var holder := Node3D.new()
		holder.name = "palisade"
		holder.set_meta("fort", "palisade")
		holder.add_child(sec)
		w._place(holder, Vector3(mid.x, 0, mid.y))
		holder.position.y -= 0.25
		holder.rotation.y = yaw
		# every other section turned round and leaning a touch, so the ring isn't a repeat
		sec.rotation.y = PI if i % 2 == 1 else 0.0
		holder.rotation.z = w.rng.randf_range(-0.03, 0.03)
		sec.scale = Vector3(d.length() / SECTION * 1.04, w.rng.randf_range(0.9, 1.08), 1.0)
		w.add_box(Vector3(mid.x, 0, mid.y), Vector2(0.5, d.length() * 0.5 + 0.1), atan2(d.x, d.y))

## Log stand-in for a palisade section (no glb): sharpened stakes along x.
static func _stakes(length: float) -> Node3D:
	var g := Node3D.new()
	var wd := Props.wood_dark()
	var n := int(length / 0.42)
	for i in n:
		var x := -length * 0.5 + (i + 0.5) * length / n
		var h := 3.6 + fmod(i * 0.73, 0.8)
		Models.P(g, Geo.cyl(0.2, 0.22, h, 7), wd, Vector3(x, h * 0.5, 0))
		Models.P(g, Geo.cone(0.2, 0.5, 7), wd, Vector3(x, h + 0.25, 0))
	Models.P(g, Geo.box(length, 0.18, 0.18), wd, Vector3(0, 2.6, 0.24))
	return g

static func _gatehouse(w: World, gp: Vector2) -> void:
	var g := model("gate")
	var holder := Node3D.new()
	holder.name = "gatehouse"
	holder.set_meta("fort", "gatehouse")
	if g == null:
		for s in [-1, 1]:
			var t := _tower_standin()
			t.position = Vector3(s * 4.3, 0, 0)
			holder.add_child(t)
		Models.P(holder, Geo.box(11.0, 0.6, 0.6), Props.wood_dark(), Vector3(0, 6.0, 0))
	else:
		holder.add_child(g)
	w._place(holder, Vector3(gp.x, 0, gp.y))
	holder.position.y -= 0.2
	# the towers either side are solid, the arch between is open
	for s in [-1, 1]:
		w.add_box(Vector3(gp.x + s * 3.8, 0, gp.y), Vector2(1.9, 2.0), 0.0)
	# torches and a pair of goblin banners outside the gate
	for s in [-1, 1]:
		w.solid(Props.tripod_torch(w.props_root, Vector3(gp.x + s * 2.6, w.height_at(gp.x + s * 2.6, gp.y + 3.6), gp.y + 3.6), s < 0))
		w.solid(Props.banner(w.props_root, Vector3(gp.x + s * 6.8, w.height_at(gp.x + s * 6.8, gp.y + 2.4), gp.y + 2.4), GOBLIN_COLS[0], Color(0.85, 0.65, 0.2)))

## Watchtowers round the wall, just inside it.
static func _towers(w: World) -> void:
	for a in [PI * 0.18, PI * 0.82, PI * 1.25, PI * 1.5, PI * 1.75]:
		var p := CENTRE + (ring(a) - CENTRE) * 0.9
		var t := model("tower")
		if t == null:
			t = _tower_standin()
		var holder := Node3D.new()
		holder.name = "tower"
		holder.set_meta("fort", "tower")
		holder.add_child(t)
		w._place(holder, Vector3(p.x, 0, p.y))
		holder.rotation.y = -a + PI * 0.5 + w.rng.randf_range(-0.3, 0.3)
		w.add_circle(Vector3(p.x, 0, p.y), 1.9)

static func _tower_standin() -> Node3D:
	var g := Node3D.new()
	var wd := Props.wood_dark()
	for c in [Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 1), Vector2(1, 1)]:
		Models.seg(g, Vector3(c.x * 1.3, 0, c.y * 1.3), Vector3(c.x * 0.9, 6.0, c.y * 0.9), 0.14, 0.11, wd, 6)
	Models.P(g, Geo.box(2.8, 0.15, 2.8), Props.wood(), Vector3(0, 6.0, 0))
	Models.P(g, Geo.cone(2.2, 2.0, 6), Props.hide_m(), Vector3(0, 8.0, 0))
	return g

# ---------------------------------------------------------------- Grubb's courtyard
static func _courtyard(w: World) -> void:
	var c := ARENA
	w._hoard_room(Rect2(c.x - 14.0, c.y - 14.0, 28.0, 28.0), c)
	w.boss_spawn = {"kind": Data.ACTS[w.act]["boss"], "pos": Vector3(c.x, 0, c.y - 3.0)}
	# a gong beside the throne, two bonfires and torches round the edge, junk heaped between
	_gong(w, Vector3(c.x + 4.6, 0, c.y - 11.5))
	for i in 6:
		var a := PI * 0.5 + TAU * (i + 0.5) / 6.0
		var p := c + Vector2(cos(a), sin(a)) * (ARENA_R - 1.5)
		if i == 1 or i == 4:
			_bonfire(w, Vector3(p.x, 0, p.y))
		else:
			w.solid(Props.tripod_torch(w.props_root, Vector3(p.x, w.height_at(p.x, p.y), p.y), false))
	for i in 9:
		var a := PI * 0.5 + TAU * i / 9.0 + 0.2
		var p := c + Vector2(cos(a), sin(a)) * (ARENA_R + 0.5)
		_junk(w, Vector3(p.x, 0, p.y), 3)

## A big fire in a ring of stones and junk wood, lighting the courtyard.
static func _bonfire(w: World, p: Vector3) -> void:
	var g := Props.footprint(Models.N(null, "bonfire"), 1.2)
	var sm := Props.stone()
	for i in 12:
		var a := TAU * i / 12.0
		Models.P(g, Props.rock_mesh(i % 5, 0.25), sm, Vector3(cos(a) * 1.15, 0.08, sin(a) * 1.15), Vector3(0, i * 37.0, 0), Vector3(0.45, 0.38, 0.4))
	var wd := Props.wood_dark()
	for i in 7:
		var a := TAU * i / 7.0
		Models.seg(g, Vector3(cos(a) * 0.85, 0.05, sin(a) * 0.85), Vector3(cos(a) * 0.1, 1.1, sin(a) * 0.1), 0.09, 0.05, wd, 6)
	w._place(g, p)
	Props.fire(g, Vector3(0, 0.45, 0), 2.6, Color(1.0, 0.5, 0.18), true, false)
	w.solid(g)

static func _gong(w: World, p: Vector3) -> void:
	var g := Props.footprint(Models.N(null, "gong"), Vector2(1.1, 0.3))
	var wd := Props.wood_dark()
	for s in [-1, 1]:
		Models.seg(g, Vector3(s * 0.95, 0, 0), Vector3(s * 0.85, 2.7, 0), 0.09, 0.07, wd, 6)
	Models.seg(g, Vector3(-1.15, 2.6, 0), Vector3(1.15, 2.6, 0), 0.08, 0.08, wd, 6)
	var disc := Models.P(g, Geo.cyl(0.75, 0.75, 0.06, 28), Goblin.gold_m(), Vector3(0, 1.55, 0), Vector3(90, 0, 0))
	disc.name = "disc"
	Models.P(g, Geo.torus(0.5, 0.56, 24, 4), Mats.mat(Color(0.35, 0.22, 0.08), 0.5, 0.8), Vector3(0, 1.55, 0.04), Vector3(90, 0, 0))
	for s in [-1, 1]:
		Models.seg(g, Vector3(s * 0.25, 2.6, 0), Vector3(s * 0.2, 2.25, 0), 0.015, 0.015, Props.hide_m(), 4)
	w._place(g, p)
	g.rotation.y = 0.35
	w.solid(g)

# ---------------------------------------------------------------- the camp inside the walls
## Organic placement: spots at least a few metres apart anywhere between the courtyard and the wall
## (but not on the lane from the gate), each given a small scene: a hut with junk at its door, a
## cookfire with a spit and log seats, a tent with crates, a loot pile, a weapon rack, a cage, a
## totem. Guards are spread round the fires and huts in ones and twos.
static func _camp(w: World) -> void:
	var gp := gate_pos()
	var spots: Array = []
	var tries := 0
	while spots.size() < 44 and tries < 6000:
		tries += 1
		var p := Vector2(w.rng.randf_range(CENTRE.x - RX, CENTRE.x + RX), w.rng.randf_range(CENTRE.y - RZ, CENTRE.y + RZ))
		var t := ring_t(p)
		if t > 0.84 or p.distance_to(ARENA) < ARENA_R + 2.5:
			continue
		if absf(p.x - gp.x) < 4.5 and p.y > ARENA.y and p.y < gp.y:
			continue
		var ok := true
		for q in spots:
			if p.distance_to(q) < 5.2:
				ok = false
				break
		if ok:
			spots.append(p)
	# what goes where: the big pieces nearer the wall, fires nearer the middle
	spots.sort_custom(func(a, b): return ring_t(a) > ring_t(b))
	var fires := 0
	var guards := 0
	var pack := 500
	for i in spots.size():
		var p: Vector2 = spots[i]
		var face := (ARENA - p).angle()      # most things face into the camp
		var kind := "hut"
		if i < 10:
			kind = "hut"
		elif i < 14:
			kind = "tent"
		elif fires < 5 and i % 3 == 0:
			kind = "fire"
		else:
			kind = ["loot", "rack", "cage", "totem", "junk", "banner"][i % 6]
		var at := Vector3(p.x, 0, p.y)
		match kind:
			"hut":
				_hut(w, at, -face + PI * 0.5)
				_junk(w, at + Vector3(cos(face), 0, sin(face)) * 3.2, 2)
				if guards < 16 and w.rng.randf() < 0.45:
					w.enemy_spawns.append({"kind": "goblin_guard", "pos": at + Vector3(cos(face), 0, sin(face)) * 4.0, "count": 1, "champ": false, "pack": pack, "level": w.level})
					guards += 1
					pack += 1
			"tent":
				w.solid(Props.hide_tent(w.props_root, Vector3(p.x, w.height_at(p.x, p.y), p.y), -face + PI * 0.5, w.rng.randf_range(2.8, 3.4), w.rng.randf_range(3.2, 3.8), w.rng.randf_range(2.1, 2.5)))
				_junk(w, at + Vector3(cos(face + 0.9), 0, sin(face + 0.9)) * 2.6, 3)
			"fire":
				fires += 1
				_cookfire(w, at)
				var n := 2 if guards < 14 else 0
				if n > 0:
					w.enemy_spawns.append({"kind": "goblin_guard", "pos": at + Vector3(1.8, 0, 1.2), "count": n, "champ": fires == 2, "pack": pack, "level": w.level})
					guards += n
					pack += 1
			"loot":
				_loot_pile(w, at)
			"rack":
				_weapon_rack(w, at, -face)
			"cage":
				_cage(w, at, -face)
			"totem":
				_skull_pole(w, at)
			"junk":
				_junk(w, at, 5)
			"banner":
				var col: Color = GOBLIN_COLS[i % GOBLIN_COLS.size()]
				w.solid(Props.banner(w.props_root, Vector3(p.x, w.height_at(p.x, p.y), p.y), col, Color(0.8, 0.62, 0.2)))
	# clutter between everything: a barrel, a sack, bones, a crate here and there
	for k in 70:
		var q := Vector2(w.rng.randf_range(CENTRE.x - RX, CENTRE.x + RX), w.rng.randf_range(CENTRE.y - RZ, CENTRE.y + RZ))
		if ring_t(q) > 0.88 or q.distance_to(ARENA) < ARENA_R - 1.0 or (absf(q.x - gp.x) < 3.5 and q.y > ARENA.y):
			continue
		_junk(w, Vector3(q.x, 0, q.y), 1 + w.rng.randi() % 2)
	# a few torches along the lane from the gate to the courtyard
	for k in 3:
		var z := lerpf(gp.y - 6.0, ARENA.y + ARENA_R + 2.0, (k + 0.5) / 3.0)
		for s in [-1, 1]:
			if k == 1 and s > 0:
				continue
			w.solid(Props.tripod_torch(w.props_root, Vector3(gp.x + s * 3.6, w.height_at(gp.x + s * 3.6, z), z), false))

static func _hut(w: World, p: Vector3, yaw: float) -> void:
	var m := model("hut")
	var holder := Node3D.new()
	holder.name = "hut"
	holder.set_meta("fort", "hut")
	if m == null:
		Props.hide_tent(holder, Vector3.ZERO, 0.0, 3.6, 3.6, 2.8)
	else:
		holder.add_child(m)
	w._place(holder, p)
	holder.rotation.y = yaw
	holder.scale = Vector3.ONE * w.rng.randf_range(0.9, 1.1)
	w.add_circle(p, 2.1)

static func _cookfire(w: World, p: Vector3) -> void:
	w.solid(Props.campfire(w.props_root, Vector3(p.x, w.height_at(p.x, p.z), p.z)))
	# a spit over the fire with something roasting
	var g := Models.N(null, "spit")
	var wd := Props.wood_dark()
	for s in [-1, 1]:
		Models.seg(g, Vector3(s * 0.9, 0, 0), Vector3(s * 0.85, 1.05, 0), 0.05, 0.04, wd, 5)
		Models.seg(g, Vector3(s * 0.85, 0.95, 0), Vector3(s * 0.7, 1.2, 0), 0.03, 0.02, wd, 4)
	Models.seg(g, Vector3(-1.2, 1.02, 0), Vector3(1.25, 1.02, 0), 0.03, 0.03, wd, 5)
	Models.P(g, Geo.sph(0.28, 12), Mats.mat(Color(0.42, 0.2, 0.08), 0.6, 0.0, Color(0.35, 0.1, 0.0), 0.15), Vector3(0, 1.0, 0), Vector3.ZERO, Vector3(1.7, 0.8, 0.9))
	w._place(g, p)
	# log seats round it
	for k in 3:
		var a := TAU * k / 3.0 + w.rng.randf_range(-0.3, 0.3)
		var sp := p + Vector3(cos(a), 0, sin(a)) * 2.1
		var seat := Props.footprint(Models.N(null, "seat"), Vector2(0.25, 0.7))
		Models.P(seat, Geo.cyl(0.22, 0.24, 1.4, 9), Props.wood(), Vector3(0, 0.2, 0), Vector3(90, 0, 0))
		w._place(seat, sp)
		seat.rotation.y = -a
		w.solid(seat)

static func _junk(w: World, p: Vector3, n: int) -> void:
	for k in n:
		var q := p + Vector3(w.rng.randf_range(-1.2, 1.2), 0, w.rng.randf_range(-1.2, 1.2))
		if w.is_near_obstacle(q, 0.6):
			continue
		var at := Vector3(q.x, w.height_at(q.x, q.z), q.z)
		match k % 4:
			0: w.solid(Props.barrel(w.props_root, at))
			1: w.solid(Props.crate(w.props_root, at, w.rng.randf_range(0.8, 1.1)))
			2: _sack(w, at)
			_: w._bones(at)

static func _sack(w: World, p: Vector3) -> void:
	var g := Props.footprint(Models.N(null, "sack"), 0.35)
	Models.P(g, Geo.sph(0.34, 12), Props.hide_m(), Vector3(0, 0.3, 0), Vector3.ZERO, Vector3(1.0, 0.9, 0.85))
	Models.seg(g, Vector3(0, 0.55, 0), Vector3(0.05, 0.75, 0), 0.07, 0.03, Props.hide_m(), 6)
	if w.rng.randf() < 0.5:
		Models.P(g, Goblin.mound_mesh(0.25, 0.1), Goblin.coin_mat(Goblin.GOLD, 1.6), Vector3(0.25, 0, 0.2))
	w._place(g, p)
	w.solid(g)

## Stolen loot: a heap of coins with chests, crates and a sack round it.
static func _loot_pile(w: World, p: Vector3) -> void:
	var heap := Props.footprint(Models.N(null, "loot"), 0.9)
	Models.P(heap, Goblin.mound_mesh(1.3, 0.55), Goblin.coin_mat(Goblin.GOLD, 1.0))
	w._place(heap, p)
	w.solid(heap)
	w._treasure_chest(p + Vector3(1.6, 0, 0.3), w.rng.randf_range(0, 360))
	_junk(w, p + Vector3(-1.4, 0, 1.0), 2)

static func _weapon_rack(w: World, p: Vector3, yaw: float) -> void:
	var g := Props.footprint(Models.N(null, "rack"), Vector2(1.2, 0.35))
	var wd := Props.wood_dark()
	for s in [-1, 1]:
		Models.seg(g, Vector3(s * 1.1, 0, 0), Vector3(s * 1.05, 1.5, 0), 0.06, 0.05, wd, 5)
	Models.seg(g, Vector3(-1.2, 1.35, 0), Vector3(1.2, 1.35, 0), 0.05, 0.05, wd, 5)
	for k in 5:
		var x := -0.8 + k * 0.4
		Models.seg(g, Vector3(x + 0.1, 0, 0.35), Vector3(x, 1.9, -0.05), 0.025, 0.025, Props.wood(), 4)
		Models.P(g, Geo.cone(0.05, 0.28, 6), Props.iron(), Vector3(x - 0.005, 2.02, -0.07), Vector3(-10, 0, 0))
	w._place(g, p)
	g.rotation.y = yaw
	w.solid(g)

static func _cage(w: World, p: Vector3, yaw: float) -> void:
	var g := Props.footprint(Models.N(null, "cage"), Vector2(0.9, 0.9))
	var wd := Props.wood_dark()
	Models.P(g, Geo.box(1.9, 0.12, 1.9), wd, Vector3(0, 0.06, 0))
	Models.P(g, Geo.box(1.9, 0.12, 1.9), wd, Vector3(0, 1.9, 0))
	for k in 8:
		for s in [-1, 1]:
			var x := -0.85 + k * (1.7 / 7.0)
			Models.seg(g, Vector3(x, 0, s * 0.9), Vector3(x, 1.9, s * 0.9), 0.035, 0.035, wd, 4)
			Models.seg(g, Vector3(s * 0.9, 0, x), Vector3(s * 0.9, 1.9, x), 0.035, 0.035, wd, 4)
	w._place(g, p)
	g.rotation.y = yaw
	w.solid(g)
	w._bones(p)

static func _skull_pole(w: World, p: Vector3) -> void:
	var g := Props.footprint(Models.N(null, "totem"), 0.25)
	var wd := Props.wood_dark()
	var bone := Mats.world(Color(0.78, 0.72, 0.6), Color(0.55, 0.5, 0.42), 0.75, 2.5)
	Models.seg(g, Vector3.ZERO, Vector3(0.05, 3.1, 0), 0.09, 0.06, wd, 6)
	for k in 3:
		var y := 1.6 + k * 0.55
		var a := k * 2.1
		Models.P(g, Geo.sph(0.16, 10), bone, Vector3(cos(a) * 0.12, y, sin(a) * 0.12), Vector3.ZERO, Vector3(0.9, 1.0, 1.1))
	Models.P(g, Geo.sph(0.2, 10), bone, Vector3(0.05, 3.25, 0), Vector3.ZERO, Vector3(0.9, 1.0, 1.15))
	for s in [-1, 1]:
		Models.P(g, Geo.cone(0.05, 0.35, 6), bone, Vector3(0.05 + s * 0.16, 3.4, 0), Vector3(0, 0, -s * 40))
	Models.seg(g, Vector3(0.05, 2.9, 0), Vector3(0.3, 2.3, 0.05), 0.02, 0.01, Mats.mat(Color(0.5, 0.15, 0.08), 0.8), 4)
	w._place(g, p)
	g.rotation.y = w.rng.randf() * TAU
	w.solid(g)

# ---------------------------------------------------------------- the approach
## Outside the gate: barricades of spiked logs, skull poles along the track, corpses, and the battle
## the hero walks into: a band of the fort's guards holding the barricade against the moor's dead.
static func _approach(w: World, track: PackedVector2Array) -> void:
	var gp := gate_pos()
	for s in [-1, 1]:
		_barricade(w, Vector3(gp.x + s * 6.5, 0, gp.y + 9.0), s * 0.35)
		_barricade(w, Vector3(gp.x + s * 13.0, 0, gp.y + 6.0), s * 0.6)
	for k in 6:
		var i := int(track.size() * (0.15 + k * 0.13))
		var tp: Vector2 = track[i]
		var side := 1.0 if k % 2 == 0 else -1.0
		_skull_pole(w, Vector3(tp.x + side * 4.0, 0, tp.y))
	for k in 10:
		var bp := Vector3(w.rng.randf_range(-16, 16), 0, w.rng.randf_range(gp.y + 4.0, gp.y + 26.0))
		if not w.is_near_obstacle(bp, 1.0):
			w._bones(bp)
	# the fight: goblins at the barricade, two groups of zombies coming up from the moor
	var lv := w.level
	w.enemy_spawns.append({"kind": "goblin_guard", "pos": Vector3(gp.x - 2.0, 0, gp.y + 11.0), "count": 4, "champ": false, "pack": 700, "level": lv})
	w.enemy_spawns.append({"kind": "goblin_guard", "pos": Vector3(gp.x + 9.0, 0, gp.y + 10.0), "count": 2, "champ": false, "pack": 701, "level": lv})
	w.enemy_spawns.append({"kind": "zombie", "pos": Vector3(gp.x - 9.0, 0, gp.y + 19.0), "count": 5, "champ": false, "pack": 702, "level": lv})
	w.enemy_spawns.append({"kind": "zombie", "pos": Vector3(gp.x + 8.0, 0, gp.y + 21.0), "count": 4, "champ": true, "pack": 703, "level": lv})
	w.enemy_spawns.append({"kind": "skel_archer", "pos": Vector3(gp.x - 16.0, 0, gp.y + 28.0), "count": 2, "champ": false, "pack": 704, "level": lv})
	# a watchtower outside the gate and a broken cart by the track
	var t := model("tower")
	if t == null:
		t = _tower_standin()
	var holder := Node3D.new()
	holder.name = "tower"
	holder.set_meta("fort", "tower")
	holder.add_child(t)
	var tp2 := Vector3(gp.x + 12.0, 0, gp.y + 15.0)
	w._place(holder, tp2)
	holder.rotation.y = 0.6
	w.add_circle(tp2, 1.9)
	var cart := Props.footprint(Models.N(null, "cart"), Vector2(0.85, 1.35))
	Models.P(cart, Geo.box(1.6, 0.12, 2.6), Props.wood(), Vector3(0, 0.6, 0), Vector3(0, 0, 8))
	Models.P(cart, Geo.box(0.1, 0.5, 2.6), Props.wood(), Vector3(0.78, 0.85, 0), Vector3(0, 0, 8))
	Models.P(cart, Geo.cyl(0.55, 0.55, 0.1, 14), Props.wood_dark(), Vector3(-0.9, 0.4, 0.8), Vector3(0, 0, 90))
	Models.P(cart, Geo.cyl(0.55, 0.55, 0.1, 14), Props.wood_dark(), Vector3(0.6, 0.05, -1.4), Vector3(90, 30, 0))
	w.solid(w._place(cart, Vector3(-7.0, 0, -14.0)))

## Spiked logs on crossed trestles (a cheval de frise).
static func _barricade(w: World, p: Vector3, yaw: float) -> void:
	var g := Props.footprint(Models.N(null, "barricade"), Vector2(2.4, 0.6))
	var wd := Props.wood_dark()
	Models.P(g, Geo.cyl(0.16, 0.17, 4.8, 8), wd, Vector3(0, 0.75, 0), Vector3(0, 0, 90))
	for k in 6:
		var x := -2.0 + k * 0.8
		var a := 50.0 if k % 2 == 0 else -50.0
		Models.P(g, Geo.cyl(0.06, 0.08, 2.1, 6), wd, Vector3(x, 0.75, 0), Vector3(a, 0, 0))
		Models.P(g, Geo.cone(0.06, 0.25, 6), wd, Vector3(x, 0.75 + cos(deg_to_rad(a)) * 1.1, sin(deg_to_rad(a)) * 1.1), Vector3(a, 0, 0))
	w._place(g, p)
	g.rotation.y = yaw
	w.solid(g)

# ---------------------------------------------------------------- trees round the fort
static func _forest(w: World) -> void:
	var gp := gate_pos()
	var meshes := {"dead": [Flora.dead_tree(11), Flora.dead_tree(23)], "pine": [Flora.pine(4), Flora.pine(6)], "bush": [Flora.bush(3)]}
	if w.oak_forest:
		meshes["oak"] = [Flora.oak_model(1), Flora.oak_model(2), Flora.oak_model(3)]
	var groups := {}
	for i in 900:
		var px := w.rng.randf_range(w.bounds.position.x - 12, w.bounds.end.x + 12)
		var pz := w.rng.randf_range(w.bounds.position.y - 12, w.bounds.end.y + 4)
		var p := Vector2(px, pz)
		if ring_t(p) < 1.16:
			continue
		# keep the approach open: the track and the field in front of the gate
		if absf(px) < 22.0 and pz > gp.y and pz < 6.0:
			continue
		var inside := w.bounds.grow(-1.5).has_point(p)
		if inside and w.is_near_obstacle(Vector3(px, 0, pz), 2.5):
			continue
		var r := w.rng.randf()
		var key := "bush"
		if meshes.has("oak") and r < 0.4:
			key = "oak"
		elif r < 0.65:
			key = "pine"
		elif r < 0.85:
			key = "dead"
		var arr: Array = meshes[key]
		var k := i % arr.size()
		var gk := "%s%d" % [key, k]
		if not groups.has(gk):
			groups[gk] = [arr[k], []]
		var s := w.rng.randf_range(0.8, 1.3)
		(groups[gk][1] as Array).append(Transform3D(Basis(Vector3.UP, w.rng.randf() * TAU).scaled(Vector3.ONE * s), Vector3(px, w.height_at(px, pz) - 0.15, pz)))
		if inside and key != "bush":
			w.add_circle(Vector3(px, 0, pz), 0.55)
	for gk in groups.keys():
		w.mm_chunked(groups[gk][0], groups[gk][1], true, 32.0, 90.0 if gk.begins_with("oak") else 0.0)

# ---------------------------------------------------------------- the moor's end
## Where the moor's road ends (Grubb's runs): a crude goblin arch of lashed logs hung with skulls and a
## stolen-gold banner, torches, spiked barricades and skull poles: the trail to the fort.
static func trail_end(w: World, p: Vector3) -> void:
	var g := Models.N(null, "goblin_arch")
	var wd := Props.wood_dark()
	var bone := Mats.world(Color(0.78, 0.72, 0.6), Color(0.55, 0.5, 0.42), 0.75, 2.5)
	for s in [-1, 1]:
		Models.seg(g, Vector3(s * 2.6, 0, 0), Vector3(s * 2.3, 5.2, 0.1), 0.24, 0.18, wd, 7)
		Models.seg(g, Vector3(s * 2.9, 0, 0.5), Vector3(s * 2.45, 4.6, 0.1), 0.16, 0.12, wd, 6)
		Models.P(g, Geo.cone(0.2, 0.6, 7), wd, Vector3(s * 2.3, 5.5, 0.1))
	Models.seg(g, Vector3(-3.3, 4.5, 0.15), Vector3(3.4, 4.75, 0.15), 0.2, 0.18, wd, 7)
	Models.seg(g, Vector3(-2.9, 3.9, 0.2), Vector3(2.9, 4.0, 0.2), 0.12, 0.12, wd, 6)
	# the gold coin sigil and a row of skulls on ropes
	Models.P(g, Geo.cyl(0.6, 0.6, 0.12, 24), Goblin.gold_m(), Vector3(0, 4.65, 0.42), Vector3(90, 0, 0))
	Models.P(g, Geo.sph(0.16, 10), Mats.glow(Color(1.0, 0.25, 0.08), 1.6), Vector3(0, 4.65, 0.5))
	for k in 4:
		var x := -1.8 + k * 1.2
		var hang := 0.5 + fmod(k * 0.37, 0.4)
		Models.seg(g, Vector3(x, 3.95, 0.2), Vector3(x, 3.95 - hang, 0.2), 0.012, 0.012, Props.hide_m(), 4)
		Models.P(g, Geo.sph(0.15, 10), bone, Vector3(x, 3.8 - hang, 0.2), Vector3.ZERO, Vector3(0.9, 1.0, 1.15))
	w._place(g, p)
	for s in [-1, 1]:
		w.add_circle(p + Vector3(s * 2.6, 0, 0), 0.45)
		w.solid(Props.tripod_torch(w.props_root, Vector3(p.x + s * 3.6, w.height_at(p.x + s * 3.6, p.z + 2.0), p.z + 2.0), s < 0))
		w.solid(Props.banner(w.props_root, Vector3(p.x + s * 5.2, w.height_at(p.x + s * 5.2, p.z + 1.0), p.z + 1.0), GOBLIN_COLS[0], Color(0.85, 0.65, 0.2)))
		_barricade(w, p + Vector3(s * 8.0, 0, 3.5), s * 0.5)
		_skull_pole(w, p + Vector3(s * 4.2, 0, 7.0))
		_skull_pole(w, p + Vector3(s * 5.0, 0, 13.0))
	w.dirt_blobs.append([Vector2(p.x, p.z + 3.0), 8.0, 1.0])
	w.exits.append({"pos": p + Vector3(0, 0, -0.5), "radius": 2.2, "to": "lair", "label": Data.ACTS[w.act]["lair"]})
