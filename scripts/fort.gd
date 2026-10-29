class_name Fort
## King Grubb's fort (Act I and A2; A3's lair stays the Ashen King's crypt). The lair zone becomes an
## outdoor goblin stronghold: a muddy approach where the fort's guards are fighting the moor's dead,
## a palisade ring with a gatehouse and watchtowers, and inside a lived-in camp (huts, tents,
## cookfires, loot, racks, cages, totems) scattered organically round an open courtyard where Grubb
## sits on his hoard. The big pieces are Meshy models (assets/models/fort/*.glb, prepared by
## tools/blender/act1/prep_prop.py); without them simple log stand-ins are built.
## Layout: the approach runs north from the start; the fort's centre is CENTRE, its wall an ellipse.
## Round the wall: a rampart it stands on, a water-logged ditch with a causeway at the gate and a row of
## stakes on its lip; beyond, a second, lower stockade (OUTER_RX/RZ, the south arc) with its own gatehouse
## encloses the outer yard (stables, pens, wagons of loot, a forge, storehouses). North of Grubb's
## courtyard stands his great hall. Outside, the forest is cut back to stumps, a lumber yard and fields.

const GLB := "res://assets/models/fort/%s.glb"
const CENTRE := Vector2(0, -88)
const RX := 33.0
const RZ := 40.0
const GATE_HALF := 5.0              # half the gate's width along the wall
const ARENA := Vector2(0, -97)      # Grubb's courtyard
const ARENA_R := 17.0
const SECTION := 5.0                # a palisade section's length
const GOBLIN_COLS := [Color(0.55, 0.45, 0.12), Color(0.24, 0.3, 0.1), Color(0.4, 0.12, 0.08)]
const DITCH_T := 1.17               # the ditch's middle, in ring_t
const STAKE_T := 1.27               # the stakes on its outer lip
const OUTER_RX := 56.0              # the outer stockade's ellipse (same centre)
const OUTER_RZ := 62.0
const OUTER_A0 := PI * 0.08         # it runs round the south from OUTER_A0 to PI - OUTER_A0
const HALL := Vector2(0, -120)      # Grubb's great hall, behind the throne
const HALL_YAW := PI * 0.5          # turns the Meshy hall's door end toward the courtyard

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

static func ring2(a: float) -> Vector2:
	return CENTRE + Vector2(cos(a) * OUTER_RX, sin(a) * OUTER_RZ)

static func ring2_t(p: Vector2) -> float:
	var d := p - CENTRE
	return sqrt(pow(d.x / OUTER_RX, 2) + pow(d.y / OUTER_RZ, 2))

static func outer_gate() -> Vector2:
	return ring2(PI * 0.5)

static func _bump(t: float, c: float, wdt: float) -> float:
	return 1.0 - smoothstep(0.0, wdt, absf(t - c))

## The ground round the walls (World.ground_fn): a rampart under the palisade, the ditch beyond it
## (none on the causeway in front of the gate), a low bank under the outer stockade.
static func ground(x: float, z: float) -> float:
	var p := Vector2(x, z)
	var t := ring_t(p)
	var h := 0.8 * _bump(t, 1.0, 0.06)
	var gp := gate_pos()
	var causeway := 1.0 - smoothstep(4.0, 6.0, absf(x - gp.x)) if z > gp.y - 2.0 else 0.0
	h -= 1.8 * _bump(t, DITCH_T, 0.065) * (1.0 - causeway)
	if z > CENTRE.y + 8.0:
		h += 0.45 * _bump(ring2_t(p), 1.0, 0.04)
	return h

# ---------------------------------------------------------------- the zone
static func build(w: World) -> void:
	w.flat_floor = false
	w.theme = {"name": "fort"}
	w.bounds = Rect2(-66, -142, 132, 150)
	w.ground_fn = ground
	var gp := gate_pos()
	var og := outer_gate()
	# ground: trodden mud inside the walls, a muddy track up to the gate, puddled patches outside
	w.dirt_blobs = []
	w.dirt_lines = []
	for i in 14:
		var a := TAU * i / 14.0
		w.dirt_blobs.append([CENTRE + Vector2(cos(a) * RX * 0.55, sin(a) * RZ * 0.55), 17.0, 1.0])
	w.dirt_blobs.append([CENTRE, 24.0, 1.0])
	var track := [Vector2(0, 4), Vector2(1.5, -8), Vector2(-1.5, -17), Vector2(og.x, og.y + 2)]
	var poly := w._spline(track, 6)
	for i in poly.size() - 1:
		w.dirt_lines.append([poly[i], poly[i + 1], 3.8])
	# a paved road from the outer gate through the inner gate to the courtyard
	for seg in [[og, gp], [gp, ARENA + Vector2(0, ARENA_R)]]:
		w.cobble_lines.append([seg[0], seg[1], 2.6])
		w.dirt_lines.append([seg[0], seg[1], 5.5])
	for i in 9:
		w.dirt_blobs.append([Vector2(w.rng.randf_range(-45, 45), w.rng.randf_range(-40, 0)), w.rng.randf_range(3, 7), 0.6])
	w.dirt_blobs.append([gp + Vector2(0, 8), 11.0, 1.0])
	w.dirt_blobs.append([og + Vector2(0, 6), 10.0, 1.0])
	# the ditch: dark mud along its length
	for i in 64:
		var a := TAU * i / 64.0
		w.dirt_blobs.append([CENTRE + Vector2(cos(a) * RX, sin(a) * RZ) * DITCH_T, 3.4, 0.9])
	# trampled flagstones and gravel patches inside: the old ground the goblins built over
	for i in 7:
		var a := w.rng.randf() * TAU
		var r := sqrt(w.rng.randf()) * 0.8
		w.cobble_blobs.append([CENTRE + Vector2(cos(a) * RX * r, sin(a) * RZ * r), w.rng.randf_range(2.5, 4.0), w.rng.randf_range(0.35, 0.55)])
	w.cobble_blobs.append([ARENA + Vector2(0, -11.0), 6.0, 0.9])
	_palisade(w)
	_gatehouse(w, gp)
	_towers(w)
	_ditch(w)
	_outer_wall(w)
	_courtyard(w)
	_hall(w)
	_camp(w)
	_outer_yard(w)
	_approach(w, poly)
	_outskirts(w)
	_forest(w)
	w.exits.append({"pos": Vector3(0, 0, 3.0), "radius": 2.6, "to": "wild", "label": w.act_name("wild")})
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
	"col_path": Color(0.3, 0.23, 0.15), "col_cliff": Color(0.16, 0.12, 0.08), "wet": 0.55, "cob_shade": 0.55,
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
		# Grubb's gold-on-red banners hung along the wall, just inside it
		if i % 6 == 3:
			var bp := CENTRE + (mid - CENTRE) * 0.955
			w.solid(Props.banner(w.props_root, Vector3(bp.x, w.height_at(bp.x, bp.y), bp.y), GOBLIN_COLS[2], Color(0.95, 0.72, 0.22)))

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
	for a in [0.0, PI * 0.18, PI * 0.36, PI * 0.64, PI * 0.82, PI, PI * 1.25, PI * 1.5, PI * 1.75]:
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
	w.boss_spawn = {"kind": w.act_name("boss"), "pos": Vector3(c.x, 0, c.y - 3.0)}
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
		if t > 0.84 or p.distance_to(ARENA) < ARENA_R + 2.5 or (absf(p.x - HALL.x) < 11.0 and absf(p.y - HALL.y) < 8.0):
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
		if ring_t(q) > 0.88 or q.distance_to(ARENA) < ARENA_R - 1.0 or (absf(q.x - gp.x) < 3.5 and q.y > ARENA.y) \
				or (absf(q.x - HALL.x) < 9.0 and absf(q.y - HALL.y) < 9.5):
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
	var gp := outer_gate()
	for s in [-1, 1]:
		_barricade(w, Vector3(gp.x + s * 6.5, 0, gp.y + 9.0), s * 0.35)
		_barricade(w, Vector3(gp.x + s * 13.0, 0, gp.y + 6.0), s * 0.6)
	for k in 6:
		var i := int(track.size() * (0.15 + k * 0.13))
		var tp: Vector2 = track[i]
		var side := 1.0 if k % 2 == 0 else -1.0
		_skull_pole(w, Vector3(tp.x + side * 4.0, 0, tp.y))
	for k in 10:
		var bp := Vector3(w.rng.randf_range(-16, 16), 0, w.rng.randf_range(gp.y + 4.0, gp.y + 20.0))
		if not w.is_near_obstacle(bp, 1.0):
			w._bones(bp)
	# the fight: goblins at the barricade, two groups of zombies coming up from the moor
	var lv := w.level
	w.enemy_spawns.append({"kind": "goblin_guard", "pos": Vector3(gp.x - 2.0, 0, gp.y + 11.0), "count": 4, "champ": false, "pack": 700, "level": lv})
	w.enemy_spawns.append({"kind": "goblin_guard", "pos": Vector3(gp.x + 9.0, 0, gp.y + 10.0), "count": 2, "champ": false, "pack": 701, "level": lv})
	w.enemy_spawns.append({"kind": "zombie", "pos": Vector3(gp.x - 9.0, 0, gp.y + 19.0), "count": 5, "champ": false, "pack": 702, "level": lv})
	w.enemy_spawns.append({"kind": "zombie", "pos": Vector3(gp.x + 8.0, 0, gp.y + 21.0), "count": 4, "champ": true, "pack": 703, "level": lv})
	w.enemy_spawns.append({"kind": "skel_archer", "pos": Vector3(gp.x - 14.0, 0, gp.y + 22.0), "count": 2, "champ": false, "pack": 704, "level": lv})
	# a watchtower outside the gate and a broken cart by the track
	var t := model("tower")
	if t == null:
		t = _tower_standin()
	var holder := Node3D.new()
	holder.name = "tower"
	holder.set_meta("fort", "tower")
	holder.add_child(t)
	var tp2 := Vector3(gp.x + 13.0, 0, gp.y + 10.0)
	w._place(holder, tp2)
	holder.rotation.y = 0.6
	w.add_circle(tp2, 1.9)
	var cart := Props.footprint(Models.N(null, "cart"), Vector2(0.85, 1.35))
	Models.P(cart, Geo.box(1.6, 0.12, 2.6), Props.wood(), Vector3(0, 0.6, 0), Vector3(0, 0, 8))
	Models.P(cart, Geo.box(0.1, 0.5, 2.6), Props.wood(), Vector3(0.78, 0.85, 0), Vector3(0, 0, 8))
	Models.P(cart, Geo.cyl(0.55, 0.55, 0.1, 14), Props.wood_dark(), Vector3(-0.9, 0.4, 0.8), Vector3(0, 0, 90))
	Models.P(cart, Geo.cyl(0.55, 0.55, 0.1, 14), Props.wood_dark(), Vector3(0.6, 0.05, -1.4), Vector3(90, 30, 0))
	w.solid(w._place(cart, Vector3(-7.0, 0, -9.0)))

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
		# cleared ground: the outer yard, the stumps round it, the fields and the approach
		if ring2_t(p) < 1.3 and pz > CENTRE.y - 10.0:
			continue
		if ring_t(p) < 1.42:
			continue
		if absf(px) < 40.0 and pz > gp.y and pz < 6.0:
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

# ---------------------------------------------------------------- the ditch and the outer stockade
## Murky water in the ditch's bottom (a strip round the ellipse, broken at the causeway), a plank
## bridge over the causeway with rope rails, and sharpened stakes leaning out along the outer lip.
static func _ditch(w: World) -> void:
	var gp := gate_pos()
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n := 160
	var prev: Array = []
	for i in n + 1:
		var a := TAU * i / n
		var mid := CENTRE + Vector2(cos(a) * RX, sin(a) * RZ) * DITCH_T
		var out := Vector2(cos(a) / RX, sin(a) / RZ).normalized()
		var dry := absf(mid.x - gp.x) < 6.5 and mid.y > gp.y - 4.0
		var y := w.height_at(mid.x, mid.y) + 0.85
		var cur := [Vector3(mid.x - out.x * 2.0, y, mid.y - out.y * 2.0), Vector3(mid.x + out.x * 2.0, y, mid.y + out.y * 2.0), dry]
		if prev.size() > 0 and not dry and not prev[2]:
			for v in [prev[0], cur[0], prev[1], prev[1], cur[0], cur[1]]:
				st.set_normal(Vector3.UP)
				st.add_vertex(v)
		prev = cur
	var water := MeshInstance3D.new()
	water.mesh = st.commit()
	var wm := StandardMaterial3D.new()
	wm.albedo_color = Color(0.035, 0.04, 0.025)
	wm.roughness = 0.12
	wm.metallic = 0.0
	wm.metallic_specular = 0.25
	water.material_override = wm
	water.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	water.name = "ditch_water"
	w.props_root.add_child(water)
	# the bridge: planks across the causeway, posts and rope rails each side
	var br := Models.N(null, "bridge")
	br.set_meta("fort", "bridge")
	var wd := Props.wood_dark()
	var depth := (DITCH_T - 1.0) * RZ * 2.0 + 2.0
	for k in int(depth / 0.45):
		var z := -depth * 0.5 + k * 0.45
		Models.P(br, Geo.box(5.4, 0.1, 0.4), Props.wood() if k % 3 else wd, Vector3(w.rng.randf_range(-0.12, 0.12), 0.06, z), Vector3(0, w.rng.randf_range(-2, 2), 0))
	for sx in [-1, 1]:
		for k in 4:
			var z := -depth * 0.5 + k * depth / 3.0
			Models.seg(br, Vector3(sx * 2.9, -0.3, z), Vector3(sx * 2.9, 1.2, z), 0.1, 0.09, wd, 6)
		Models.seg(br, Vector3(sx * 2.9, 1.05, -depth * 0.5), Vector3(sx * 2.9, 0.95, depth * 0.5), 0.03, 0.03, Props.hide_m(), 4)
	var bc := CENTRE + Vector2(0, RZ * (1.0 + DITCH_T) * 0.5 + 0.6)
	w._place(br, Vector3(bc.x, 0, bc.y))
	for sx in [-1, 1]:
		w.add_box(Vector3(bc.x + sx * 2.95, 0, bc.y), Vector2(0.15, depth * 0.5), 0.0)
	# stakes: a pair or three every couple of metres, leaning outward over the ditch
	var stakes: Array = []
	var m := 140
	for i in m:
		var a := TAU * (i + w.rng.randf_range(-0.3, 0.3)) / m
		var p := CENTRE + Vector2(cos(a) * RX, sin(a) * RZ) * STAKE_T
		if absf(p.x - gp.x) < 7.0 and p.y > gp.y:
			continue
		var out := Vector2(cos(a) / RX, sin(a) / RZ).normalized()
		for k in 2 + i % 2:
			var q := p + Vector2(-out.y, out.x) * w.rng.randf_range(-0.6, 0.6)
			var dir := Vector3(-out.x, 1.1, -out.y).normalized()     # leaning in over the ditch
			var b := Basis(Quaternion(Vector3.UP, dir)).scaled(Vector3(1, w.rng.randf_range(0.8, 1.2), 1))
			stakes.append(Transform3D(b, Vector3(q.x, w.height_at(q.x, q.y) - 0.3, q.y)))
	Props.multimesh(w.props_root, _own_cyl(0.0, 0.09, 2.2, 6, wd), stakes)

## The outer stockade: lower palisade sections round the south from OUTER_A0 to PI - OUTER_A0 on its
## bank, spurs back to the ditch at both ends, a gatehouse where the track comes in, corner towers.
static func _outer_wall(w: World) -> void:
	var og := outer_gate()
	var pts: Array = []
	var last := ring2(OUTER_A0)
	pts.append(last)
	for i in 600:
		var aa := OUTER_A0 + (PI - OUTER_A0 * 2.0) * (i + 1) / 600.0
		var p := ring2(aa)
		if p.distance_to(last) >= SECTION * 0.96:
			pts.append(p)
			last = p
	for e in [OUTER_A0, PI - OUTER_A0]:
		# the spur from the stockade's end in to the ditch's lip
		var from := ring2(e)
		var to := CENTRE + (Vector2(cos(e) * RX, sin(e) * RZ)) * (STAKE_T + 0.06)
		var steps := int(from.distance_to(to) / SECTION) + 1
		var seg := []
		for k in steps + 1:
			seg.append(from.lerp(to, float(k) / steps))
		for k in steps:
			_wall_section(w, seg[k], seg[k + 1], 0.85, k)
		_corner_tower(w, from)
	for i in pts.size() - 1:
		var mid: Vector2 = (pts[i] + pts[i + 1]) * 0.5
		if mid.distance_to(og) < GATE_HALF + SECTION * 0.5:
			continue
		_wall_section(w, pts[i], pts[i + 1], 0.85, i)
	var g := model("gate")
	var holder := Node3D.new()
	holder.name = "outer_gatehouse"
	holder.set_meta("fort", "gatehouse")
	if g == null:
		for sx in [-1, 1]:
			var t := _tower_standin()
			t.position = Vector3(sx * 4.3, 0, 0)
			holder.add_child(t)
	else:
		holder.add_child(g)
	w._place(holder, Vector3(og.x, 0, og.y))
	holder.position.y -= 0.2
	holder.scale = Vector3.ONE * 0.9
	for sx in [-1, 1]:
		w.add_box(Vector3(og.x + sx * 3.5, 0, og.y), Vector2(1.7, 1.8), 0.0)
		w.solid(Props.tripod_torch(w.props_root, Vector3(og.x + sx * 2.5, w.height_at(og.x + sx * 2.5, og.y + 3.4), og.y + 3.4), sx < 0))
	for a in [PI * 0.25, PI * 0.75]:
		_corner_tower(w, CENTRE + (ring2(a) - CENTRE) * 0.96)

static func _wall_section(w: World, p0: Vector2, p1: Vector2, h: float, i: int) -> void:
	var d := p1 - p0
	var mid := (p0 + p1) * 0.5
	var sec := model("palisade")
	if sec == null:
		sec = _stakes(d.length())
	var holder := Node3D.new()
	holder.name = "palisade"
	holder.set_meta("fort", "outer_palisade")
	holder.add_child(sec)
	w._place(holder, Vector3(mid.x, 0, mid.y))
	holder.position.y -= 0.3
	holder.rotation.y = atan2(-d.y, d.x)
	sec.rotation.y = PI if i % 2 == 1 else 0.0
	holder.rotation.z = w.rng.randf_range(-0.04, 0.04)
	sec.scale = Vector3(d.length() / SECTION * 1.04, h * w.rng.randf_range(0.92, 1.06), 1.0)
	w.add_box(Vector3(mid.x, 0, mid.y), Vector2(0.5, d.length() * 0.5 + 0.1), atan2(d.x, d.y))

static func _corner_tower(w: World, p: Vector2) -> void:
	var t := model("tower")
	if t == null:
		t = _tower_standin()
	var holder := Node3D.new()
	holder.name = "tower"
	holder.set_meta("fort", "tower")
	holder.add_child(t)
	w._place(holder, Vector3(p.x, 0, p.y))
	holder.rotation.y = (p - CENTRE).angle() + w.rng.randf_range(-0.3, 0.3)
	holder.scale = Vector3.ONE * 0.9
	w.add_circle(Vector3(p.x, 0, p.y), 1.8)
	w.solid(Props.banner(w.props_root, Vector3(p.x + 2.2, w.height_at(p.x + 2.2, p.y), p.y), GOBLIN_COLS[2], Color(0.95, 0.72, 0.22)))

# ---------------------------------------------------------------- Grubb's great hall
## Behind the throne: a long timber hall on a stone footing, its steep roof ridged in gold, carved
## crossed gable boards, a broad door onto the courtyard, braziers and banners either side. A Meshy
## model (assets/models/fort/hall.glb) if there is one, else built here.
static func _hall(w: World) -> void:
	var holder := Node3D.new()
	holder.name = "great_hall"
	holder.set_meta("fort", "hall")
	var m := model("hall")
	var front := HALL.y + 5.6
	if m != null:
		# the Meshy hall's door is in its gable end: turned so that end faces the throne
		m.rotation.y = HALL_YAW
		m.scale = Vector3.ONE * 0.86
		holder.add_child(m)
		w.add_box(Vector3(HALL.x, 0, HALL.y), Vector2(4.4, 6.0), 0.0)
		front = HALL.y + 6.4
	else:
		_hall_standin(holder)
		w.add_box(Vector3(HALL.x, 0, HALL.y), Vector2(7.6, 4.6), 0.0)
	w._place(holder, Vector3(HALL.x, 0, HALL.y))
	for sx in [-1, 1]:
		_brazier(w, Vector3(HALL.x + sx * 3.4, 0, front + 0.6))
		w.solid(Props.banner(w.props_root, Vector3(HALL.x + sx * 6.0, w.height_at(HALL.x + sx * 6.0, front), front), GOBLIN_COLS[2], Color(0.95, 0.72, 0.22)))
	# the treasury beside it: a hut stuffed with gold, chests outside
	for sx in [-1, 1]:
		var tp := Vector3(HALL.x + sx * 13.0, 0, HALL.y + 1.0)
		_hut(w, tp, sx * 0.5)
		_loot_pile(w, tp + Vector3(-sx * 1.0, 0, 3.6))

static func _hall_standin(g: Node3D) -> void:
	var wd := Props.wood_dark()
	var wl := Props.wood()
	var gold := Goblin.gold_m()
	Models.P(g, Geo.box(15.0, 0.7, 9.4), Props.stone(), Vector3(0, 0.2, 0))
	# log walls
	for k in 9:
		var y := 0.7 + k * 0.36
		Models.P(g, Geo.box(14.4, 0.34, 0.36), wd if k % 2 else wl, Vector3(0, y, -4.2))
		Models.P(g, Geo.box(14.4, 0.34, 0.36), wd if k % 2 else wl, Vector3(0, y, 4.2))
		Models.P(g, Geo.box(0.36, 0.34, 8.4), wd if k % 2 else wl, Vector3(-7.0, y, 0))
		Models.P(g, Geo.box(0.36, 0.34, 8.4), wd if k % 2 else wl, Vector3(7.0, y, 0))
	# a steep roof of hides and shingles, the ridge capped in gold
	for sz in [-1, 1]:
		Models.P(g, Geo.box(16.0, 0.25, 6.6), Props.hide_m(), Vector3(0, 5.6, sz * 2.45), Vector3(sz * 52.0, 0, 0))
	Models.P(g, Geo.box(16.4, 0.4, 0.5), gold, Vector3(0, 8.1, 0))
	# crossed gable boards at both ends, carved into horns
	for sx in [-1, 1]:
		for sz in [-1, 1]:
			Models.seg(g, Vector3(sx * 8.0, 3.8, sz * 4.6), Vector3(sx * 8.0, 9.4, -sz * 0.9), 0.16, 0.1, wd, 6)
		Models.P(g, Geo.cyl(0.55, 0.55, 0.1, 20), gold, Vector3(sx * 7.3, 5.6, 0), Vector3(0, 0, 90))
	# the door onto the courtyard, gold-studded, with pillars and a little porch roof
	Models.P(g, Geo.box(2.6, 3.0, 0.2), Mats.mat(Color(0.2, 0.12, 0.06), 0.8), Vector3(0, 2.2, 4.42))
	for k in 6:
		Models.P(g, Geo.sph(0.07, 6), gold, Vector3(-0.9 + (k % 3) * 0.9, 1.4 + (k / 3) * 1.4, 4.55))
	for sx in [-1, 1]:
		Models.seg(g, Vector3(sx * 1.9, 0.5, 5.4), Vector3(sx * 1.9, 3.9, 5.4), 0.18, 0.15, wd, 7)
	Models.P(g, Geo.box(4.8, 0.2, 2.0), Props.hide_m(), Vector3(0, 4.0, 5.0), Vector3(-14, 0, 0))

static func _brazier(w: World, p: Vector3) -> void:
	var g := Props.footprint(Models.N(null, "brazier"), 0.45)
	var iron := Props.iron()
	for k in 3:
		var a := TAU * k / 3.0
		Models.seg(g, Vector3(cos(a) * 0.45, 0, sin(a) * 0.45), Vector3(cos(a) * 0.2, 1.0, sin(a) * 0.2), 0.04, 0.04, iron, 5)
	Models.P(g, Geo.cyl(0.48, 0.3, 0.4, 14), Goblin.gold_m(), Vector3(0, 1.15, 0))
	w._place(g, p)
	Props.fire(g, Vector3(0, 1.35, 0), 1.6, Color(1.0, 0.55, 0.2), true, false)
	w.solid(g)

# ---------------------------------------------------------------- the outer yard
## Between the ditch and the outer stockade: what a rich chieftain's stronghold keeps outside its inner
## wall. Stables with hay, pens, wagons heaped with plunder, tents, the forge, storehouses on stilts,
## haystacks, and lantern posts along the road; goblins about the place.
static func _outer_yard(w: World) -> void:
	var og := outer_gate()
	var gp := gate_pos()
	var spots: Array = []
	var tries := 0
	while spots.size() < 36 and tries < 9000:
		tries += 1
		var p := Vector2(w.rng.randf_range(-OUTER_RX, OUTER_RX), w.rng.randf_range(CENTRE.y - 6.0, og.y))
		if ring_t(p) < STAKE_T + 0.08 or ring2_t(p) > 0.9:
			continue
		if absf(p.x) < 6.5:
			continue
		var ok := true
		for q in spots:
			if p.distance_to(q) < 6.0:
				ok = false
				break
		if ok:
			spots.append(p)
	# the yard is trodden mud: round everything in it and along a track round the inside of the stockade
	for p in spots:
		w.dirt_blobs.append([p, 4.5, 0.85])
	for i in 24:
		var a0 := OUTER_A0 + (PI - OUTER_A0 * 2.0) * i / 24.0
		var a1 := OUTER_A0 + (PI - OUTER_A0 * 2.0) * (i + 1) / 24.0
		w.dirt_lines.append([CENTRE + (ring2(a0) - CENTRE) * 0.86, CENTRE + (ring2(a1) - CENTRE) * 0.86, 4.0])
	var kinds := ["stable", "pen", "wagon", "forge", "store", "tent", "wagon", "hay", "loot", "stable", "pen", "store", "tent", "wagon", "hay", "fire", "rack"]
	var pack := 600
	for i in spots.size():
		var p: Vector2 = spots[i]
		var face := (CENTRE - p).angle()
		var at := Vector3(p.x, 0, p.y)
		var kind: String = kinds[i % kinds.size()]
		match kind:
			"stable": _stable(w, at, -face + PI * 0.5)
			"pen": _pen(w, at, -face + PI * 0.5)
			"wagon": _wagon(w, at, w.rng.randf() * TAU)
			"forge": _camp_model(w, "forge", at, -face + PI * 0.5, 1.2, Vector2(1.8, 1.4))
			"store": _storehouse(w, at, -face + PI * 0.5)
			"tent": _camp_model(w, "tent", at, -face + PI * 0.5, 1.2, Vector2(2.0, 1.8))
			"hay": _haystacks(w, at)
			"loot": _loot_pile(w, at)
			"fire": _cookfire(w, at)
			"rack": _weapon_rack(w, at, -face)
		_junk(w, at + Vector3(w.rng.randf_range(-3, 3), 0, w.rng.randf_range(-3, 3)), 2)
		if i % 4 == 1:
			w.enemy_spawns.append({"kind": "goblin_guard", "pos": at + Vector3(cos(face), 0, sin(face)) * 3.5, "count": 2 + i % 2, "champ": i == 9, "pack": pack, "level": w.level})
			pack += 1
	# lantern posts down the road between the two gates
	for k in 4:
		var z := lerpf(og.y - 3.0, gp.y + 9.0, (k + 0.5) / 4.0)
		for sx in [-1, 1]:
			_lantern_post(w, Vector2(sx * 3.4, z), k % 2 == 0)

## One of the forest camp's Meshy props (wagon, tent, forge...) with a box footprint.
static func _camp_model(w: World, name: String, p: Vector3, yaw: float, s: float, half: Vector2) -> Node3D:
	var path := ForestCamp.DIR + name + ".glb"
	if not ResourceLoader.exists(path):
		return null
	var m: Node3D = (load(path) as PackedScene).instantiate()
	m.set_meta("fort", name)
	w._place(m, p)
	m.rotation.y = yaw
	m.scale = Vector3.ONE * s
	w.add_box(p, half * s, yaw)
	return m

static func _wagon(w: World, p: Vector3, yaw: float) -> void:
	var m := _camp_model(w, "wagon", p, yaw, 1.15, Vector2(1.0, 1.9))
	if m == null:
		return
	# heaped with plunder: gold, sacks, a chest
	var heap := Models.N(m, "plunder")
	Models.P(heap, Goblin.mound_mesh(0.7, 0.35), Goblin.coin_mat(Goblin.GOLD, 1.4), Vector3(0, 1.05, -0.2))
	Models.P(heap, Geo.sph(0.3, 10), Props.hide_m(), Vector3(0.35, 1.2, 0.6), Vector3.ZERO, Vector3(1, 0.85, 0.9))
	Models.P(heap, Geo.box(0.6, 0.45, 0.45), Props.wood_dark(), Vector3(-0.3, 1.25, 0.65))

static func _stable(w: World, p: Vector3, yaw: float) -> void:
	var g := Props.footprint(Models.N(null, "stable"), Vector2(4.2, 1.8))
	var wd := Props.wood_dark()
	for k in 5:
		var x := -4.0 + k * 2.0
		Models.seg(g, Vector3(x, 0, 1.6), Vector3(x, 2.6, 1.6), 0.1, 0.09, wd, 6)
		Models.seg(g, Vector3(x, 0, -1.6), Vector3(x, 3.3, -1.6), 0.1, 0.09, wd, 6)
		if k < 4:
			Models.P(g, Geo.box(0.08, 1.2, 3.0), Props.wood(), Vector3(x + 2.0, 0.6, 0))   # stall boards
	Models.P(g, Geo.box(8.4, 0.18, 3.9), Props.hide_m(), Vector3(0, 3.0, 0), Vector3(-10, 0, 0))
	Models.P(g, Geo.box(8.2, 2.9, 0.12), Props.wood(), Vector3(0, 1.45, -1.62))
	var hay := Mats.mat(Color(0.72, 0.6, 0.28), 0.95)
	for k in 3:
		Models.P(g, Geo.box(1.1, 0.5, 0.7), hay, Vector3(-3.0 + k * 2.6, 0.25, -0.9), Vector3(0, k * 17.0, 0))
	Models.P(g, Geo.box(1.6, 0.4, 0.5), wd, Vector3(1.6, 0.35, 1.0))   # a trough
	w._place(g, p)
	g.rotation.y = yaw
	w.solid(g)

static func _pen(w: World, p: Vector3, yaw: float) -> void:
	var g := Models.N(null, "pen")
	var wd := Props.wood_dark()
	var hx := 2.8
	var hz := 2.2
	var corners := [Vector2(-hx, -hz), Vector2(hx, -hz), Vector2(hx, hz), Vector2(-hx, hz)]
	for k in 4:
		var a: Vector2 = corners[k]
		var b: Vector2 = corners[(k + 1) % 4]
		var n := int(a.distance_to(b) / 1.4) + 1
		for j in n + 1:
			var q := a.lerp(b, float(j) / n)
			if k == 2 and j == n / 2:
				continue     # the gate gap
			Models.seg(g, Vector3(q.x, 0, q.y), Vector3(q.x, 1.1, q.y), 0.06, 0.05, wd, 5)
		for y in [0.45, 0.9]:
			Models.seg(g, Vector3(a.x, y, a.y), Vector3(b.x, y, b.y), 0.04, 0.04, Props.wood(), 4)
	Models.P(g, Geo.box(1.4, 0.35, 0.45), wd, Vector3(1.2, 0.2, -1.4))
	w._place(g, p)
	g.rotation.y = yaw
	w.dirt_blobs.append([Vector2(p.x, p.z), 3.2, 1.0])
	for k in 4:
		var a: Vector2 = corners[k].rotated(-yaw)
		var b: Vector2 = corners[(k + 1) % 4].rotated(-yaw)
		var mid := (a + b) * 0.5
		var d := b - a
		w.add_box(p + Vector3(mid.x, 0, mid.y), Vector2(0.15, d.length() * 0.5), atan2(d.x, d.y))

## A storehouse on stilts (keeps the grain off the wet ground): a hut raised on posts with a ladder.
static func _storehouse(w: World, p: Vector3, yaw: float) -> void:
	var holder := Node3D.new()
	holder.name = "storehouse"
	holder.set_meta("fort", "store")
	var wd := Props.wood_dark()
	for c in [Vector2(-1.4, -1.4), Vector2(1.4, -1.4), Vector2(1.4, 1.4), Vector2(-1.4, 1.4)]:
		Models.seg(holder, Vector3(c.x, 0, c.y), Vector3(c.x, 1.3, c.y), 0.13, 0.12, wd, 6)
	Models.P(holder, Geo.box(3.4, 0.2, 3.4), Props.wood(), Vector3(0, 1.35, 0))
	var m := model("hut")
	if m != null:
		m.position.y = 1.4
		m.scale = Vector3.ONE * 0.8
		holder.add_child(m)
	Models.seg(holder, Vector3(0.4, 0, 2.6), Vector3(0.4, 1.4, 1.75), 0.04, 0.04, wd, 4)
	Models.seg(holder, Vector3(-0.4, 0, 2.6), Vector3(-0.4, 1.4, 1.75), 0.04, 0.04, wd, 4)
	w._place(holder, p)
	holder.rotation.y = yaw
	w.add_circle(p, 2.0)
	_junk(w, p + Vector3(2.6, 0, 1.2), 2)

static func _haystacks(w: World, p: Vector3) -> void:
	var hay := Mats.mat(Color(0.7, 0.58, 0.27), 0.95)
	for k in 2 + w.rng.randi() % 2:
		var q := p + Vector3(w.rng.randf_range(-2.0, 2.0), 0, w.rng.randf_range(-2.0, 2.0))
		var g := Props.footprint(Models.N(null, "hay"), 1.0)
		var r := w.rng.randf_range(1.0, 1.4)
		Models.P(g, Geo.sph(r, 12), hay, Vector3(0, r * 0.55, 0), Vector3.ZERO, Vector3(1, 1.25, 1))
		Models.seg(g, Vector3(0, r * 1.5, 0), Vector3(0.05, r * 2.0, 0), 0.03, 0.02, Props.wood_dark(), 4)
		w._place(g, q)
		w.solid(g)

static func _lantern_post(w: World, p: Vector2, lit: bool) -> void:
	var post := Props.footprint(Models.N(null, "lpost"), 0.15)
	Models.seg(post, Vector3.ZERO, Vector3(0, 2.7, 0), 0.08, 0.06, Props.wood_dark(), 6)
	Models.seg(post, Vector3(0, 2.6, 0), Vector3(0.55, 2.62, 0), 0.04, 0.035, Props.wood_dark(), 5)
	w._place(post, Vector3(p.x, 0, p.y))
	post.rotation.y = PI if p.x > 0 else 0.0
	w.solid(post)
	if ResourceLoader.exists(ForestCamp.DIR + "lantern.glb"):
		ForestCamp._lantern(w, post.position + Basis(Vector3.UP, post.rotation.y) * Vector3(0.5, 2.6, 0), lit)

# ---------------------------------------------------------------- round the fort
## A cylinder (or cone) of its own with a material, for a MultiMesh (Geo's are shared).
static func _own_cyl(top: float, bottom: float, h: float, seg: int, m: Material) -> CylinderMesh:
	var c := CylinderMesh.new()
	c.top_radius = top
	c.bottom_radius = bottom
	c.height = h
	c.radial_segments = seg
	c.rings = 1
	c.material = m
	return c

## The ground the goblins have worked outside the walls: stumps where the forest was felled for the
## palisade, a lumber yard (log piles, a sawhorse, an axe in a block), a field of crop rows with a
## scarecrow.
static func _outskirts(w: World) -> void:
	var stumps: Array = []
	for i in 240:
		var p := Vector2(w.rng.randf_range(w.bounds.position.x, w.bounds.end.x), w.rng.randf_range(w.bounds.position.y, w.bounds.end.y))
		if ring_t(p) < STAKE_T + 0.08 or (ring2_t(p) < 1.04 and p.y > CENTRE.y - 10.0) or absf(p.x) < 5.0:
			continue
		if w.is_near_obstacle(Vector3(p.x, 0, p.y), 1.2):
			continue
		var s := w.rng.randf_range(0.7, 1.3)
		stumps.append(Transform3D(Basis(Vector3.UP, w.rng.randf() * TAU).scaled(Vector3(s, s * w.rng.randf_range(0.6, 1.1), s)), Vector3(p.x, w.height_at(p.x, p.y) - 0.05, p.y)))
	Props.multimesh(w.props_root, _own_cyl(0.32, 0.4, 0.55, 9, Props.wood()), stumps)
	# lumber yard, west of the approach
	var ly := Vector3(-30.0, 0, -12.0)
	for k in 4:
		w.solid(Props.log_pile(w.props_root, Vector3(ly.x + (k % 2) * 4.0, w.height_at(ly.x, ly.z), ly.z + (k / 2) * 3.5)))
	var block := Props.footprint(Models.N(null, "chop"), 0.4)
	Models.P(block, Geo.cyl(0.38, 0.42, 0.6, 10), Props.wood(), Vector3(0, 0.3, 0))
	Models.seg(block, Vector3(0, 0.6, 0), Vector3(0.25, 1.2, 0.1), 0.03, 0.03, Props.wood_dark(), 4)
	Models.P(block, Geo.box(0.05, 0.22, 0.3), Props.iron(), Vector3(0.02, 0.66, 0), Vector3(0, 0, -25))
	w._place(block, ly + Vector3(2.0, 0, -3.0))
	w.solid(block)
	w.dirt_blobs.append([Vector2(ly.x + 2.0, ly.z + 1.5), 6.0, 0.8])
	# a field of crop rows to the east, a scarecrow in it
	var fc := Vector2(31.0, -12.0)
	var crops: Array = []
	for r in 7:
		var z := fc.y - 7.0 + r * 2.0
		w.dirt_lines.append([Vector2(fc.x - 8.0, z), Vector2(fc.x + 8.0, z), 1.1])
		for k in 16:
			var x := fc.x - 7.5 + k + w.rng.randf_range(-0.2, 0.2)
			var s := w.rng.randf_range(0.6, 1.0)
			crops.append(Transform3D(Basis(Vector3.UP, w.rng.randf() * TAU).scaled(Vector3(s, s, s)), Vector3(x, w.height_at(x, z), z)))
	Props.multimesh(w.props_root, _own_cyl(0.0, 0.22, 0.7, 5, Mats.mat(Color(0.35, 0.42, 0.14), 0.9)), crops, false)
	var sc := Props.footprint(Models.N(null, "scarecrow"), 0.2)
	Models.seg(sc, Vector3.ZERO, Vector3(0, 2.2, 0), 0.05, 0.05, Props.wood_dark(), 5)
	Models.seg(sc, Vector3(-0.8, 1.7, 0), Vector3(0.8, 1.7, 0), 0.04, 0.04, Props.wood_dark(), 5)
	Models.P(sc, Geo.sph(0.22, 10), Props.hide_m(), Vector3(0, 2.25, 0))
	Models.P(sc, Geo.box(0.9, 0.8, 0.25), Mats.mat(Color(0.35, 0.12, 0.08), 0.9), Vector3(0, 1.45, 0), Vector3(0, 0, 4))
	Models.P(sc, Geo.sph(0.07, 6), Goblin.gold_m(), Vector3(0.1, 2.3, 0.2))
	w._place(sc, Vector3(fc.x + 1.0, 0, fc.y))
	w.solid(sc)

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
	w.exits.append({"pos": p + Vector3(0, 0, -0.5), "radius": 2.2, "to": "lair", "label": w.act_name("lair")})
