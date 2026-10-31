class_name Isles
extends RefCounted
## The islands off the Mournwater Coast (coast.gd), as data. Each entry is one island; adding an island
## is a new entry here plus a small builder script (see ISLE_SCRIPTS and isle_verdant.gd for the shape
## of one). Nothing else in the sea needs to change: the coast zone's size, the water's depth map, the
## minimap and the routes all come from this table.
##
## An island lives in two places:
## - out at sea (the coast zone): drawn at full size from a distance (its ground, cliffs, trees and
##   landmark), so you watch it grow as you sail to it;
## - as its own zone ("isle_<id>"), loaded when you step off the boat at its jetty: the same ground
##   (same function, same seed, same trees) with everything else on it: grass, props, places to explore.
##
## Shape: a blob of radius `r` (+8% / -12% wobble along the coast, none at the landing), beaches where
## `cliff` allows and cliffs elsewhere, the island's own relief inland (its script's `relief`), flat
## pads for buildings (its script's `pads`). Positions: `bearing` (degrees from due west, + south) and
## `sail` (metres of open water from the coast's dock to the end of the island's jetty).
##
## Room to grow: every island has `foes` (Data.ENEMIES ids for its packs), `loot` (chests and caches),
## `quests` (Quests ids) and `dungeon` (a zone its cave or crypt leads to), all empty for now. The
## builder marks named spots (`w.spawns["poi_<name>"]`) for them.

const JETTY := 14.0            # metres the island's jetty reaches out from its beach toward the dock
const DEEP := -24.0            # the open sea's floor
const ZONE_HALF := 160.0       # half the size of an island's own zone (its ground is within r * 1.08)

## One entry per island, in the order a player meets them on the map from north round to south.
const ISLANDS := [
	{"id": "verdant", "ferns": 1100, "name": "The Verdant Isle", "bearing": -112.0, "sail": 164.0, "r": 125.0, "seed": 101,
		"beach": 13.0, "cliff": 0.35, "cliff_h": 6.0, "sand": Color(0.62, 0.56, 0.41),
		"terrain": {"col_a": Color(0.13, 0.19, 0.07), "col_b": Color(0.19, 0.24, 0.09), "col_accent": Color(0.26, 0.32, 0.12),
			"col_path": Color(0.3, 0.25, 0.17), "col_cliff": Color(0.34, 0.33, 0.29), "wet": 0.4},
		"lore": "Green and silent under a giant oak older than any kingdom. Something tends the clearings.",
		"foes": [], "loot": [], "quests": [], "dungeon": ""},
	{"id": "ruins", "ferns": 300, "name": "The Forgotten Ruins", "bearing": -56.0, "sail": 164.0, "r": 125.0, "seed": 202,
		"beach": 11.0, "cliff": 0.55, "cliff_h": 7.0, "sand": Color(0.66, 0.6, 0.47),
		"terrain": {"col_a": Color(0.2, 0.22, 0.1), "col_b": Color(0.27, 0.27, 0.15), "col_accent": Color(0.33, 0.33, 0.18),
			"col_path": Color(0.42, 0.38, 0.3), "col_cliff": Color(0.5, 0.47, 0.41), "wet": 0.2},
		"lore": "Terraces of a city that knelt to the Ashen King, and a temple still waiting for him.",
		"foes": [], "loot": [], "quests": [], "dungeon": ""},
	{"id": "lost", "ferns": 700, "name": "The Lost Isle", "bearing": 0.0, "sail": 164.0, "r": 125.0, "seed": 303,
		"beach": 12.0, "cliff": 1.0, "cliff_h": 17.0, "sand": Color(0.7, 0.66, 0.56),
		"terrain": {"col_a": Color(0.14, 0.2, 0.12), "col_b": Color(0.2, 0.24, 0.16), "col_accent": Color(0.24, 0.3, 0.2),
			"col_path": Color(0.36, 0.33, 0.28), "col_cliff": Color(0.42, 0.42, 0.44), "wet": 0.3},
		"lore": "Sheer cliffs and a monolith carved with the same runes as the camp's stones, still awake.",
		"foes": [], "loot": [], "quests": [], "dungeon": ""},
	{"id": "bleak", "ferns": 120, "name": "The Bleak Isle", "bearing": 56.0, "sail": 164.0, "r": 125.0, "seed": 404,
		"beach": 9.0, "cliff": 0.8, "cliff_h": 9.0, "sand": Color(0.34, 0.33, 0.32),
		"terrain": {"col_a": Color(0.09, 0.1, 0.08), "col_b": Color(0.13, 0.13, 0.11), "col_accent": Color(0.16, 0.17, 0.12),
			"col_path": Color(0.2, 0.19, 0.17), "col_cliff": Color(0.12, 0.12, 0.13), "wet": 0.5},
		"lore": "Black rock, dead trees and a fog that never lifts. Ships that put in here stay.",
		"foes": [], "loot": [], "quests": [], "dungeon": ""},
	{"id": "merchant", "ferns": 350, "name": "The Merchant's Reach", "bearing": 112.0, "sail": 164.0, "r": 125.0, "seed": 505,
		"beach": 10.0, "cliff": 0.5, "cliff_h": 5.0, "sand": Color(0.6, 0.55, 0.43),
		"terrain": {"col_a": Color(0.17, 0.2, 0.09), "col_b": Color(0.23, 0.23, 0.12), "col_accent": Color(0.3, 0.29, 0.15),
			"col_path": Color(0.36, 0.3, 0.21), "col_cliff": Color(0.4, 0.38, 0.33), "wet": 0.35},
		"lore": "A trading post on a sheltered harbour, emptied in a single night. The ledgers stop mid-line.",
		"foes": [], "loot": [], "quests": [], "dungeon": ""},
]

## Each island's builder (relief, pads, dress). A new island adds its script here.
const ISLE_SCRIPTS := {
	"verdant": preload("res://scripts/isle_verdant.gd"),
	"ruins": preload("res://scripts/isle_ruins.gd"),
	"lost": preload("res://scripts/isle_lost.gd"),
	"bleak": preload("res://scripts/isle_bleak.gd"),
	"merchant": preload("res://scripts/isle_merchant.gd"),
}

static var _cache := {}
static var _grids := {}

static func get_isle(id: String) -> Dictionary:
	for i in ISLANDS:
		if i["id"] == id:
			return i
	return {}

static func ids() -> Array:
	return ISLANDS.map(func(i): return i["id"])

static func zone_of(id: String) -> String:
	return "isle_" + id

static func id_of(zone: String) -> String:
	return zone.trim_prefix("isle_") if zone.begins_with("isle_") else ""

static func script_of(isle: Dictionary) -> Script:
	return ISLE_SCRIPTS[isle["id"]]

## Unit vector from the dock out toward the island (x, z): bearing 0 is due west, + is south.
static func heading(isle: Dictionary) -> Vector2:
	var b := deg_to_rad(float(isle["bearing"]))
	return Vector2(-cos(b), sin(b))

## [centre, u, v] per island, worked out once (the ground asks thousands of times a frame).
static var _geo := {}

static func _g(isle: Dictionary) -> Array:
	var id: String = isle["id"]
	if not _geo.has(id):
		var u := -heading(isle)
		_geo[id] = [heading(isle) * (float(isle["sail"]) + JETTY + float(isle["r"])), u, Vector2(-u.y, u.x)]
	return _geo[id]

## The island's centre in the coast zone's frame (the dock's end at the origin).
static func centre(isle: Dictionary) -> Vector2:
	return _g(isle)[0]

## The island's local frame: +u points back toward the dock (its landing side), +v to its right.
static func axes(isle: Dictionary) -> Array:
	var g := _g(isle)
	return [g[1], g[2]]

## Coast-frame point -> island-local (u, v).
static func to_local(isle: Dictionary, p: Vector2) -> Vector2:
	var g := _g(isle)
	var d: Vector2 = p - (g[0] as Vector2)
	return Vector2(d.dot(g[1]), d.dot(g[2]))

## Island-local (u, v) -> coast frame.
static func to_coast(isle: Dictionary, l: Vector2) -> Vector2:
	var ax := axes(isle)
	return centre(isle) + (ax[0] as Vector2) * l.x + (ax[1] as Vector2) * l.y

## Where the jetty meets the beach, and its far end (the boat's mooring), island-local.
static func jetty_root(isle: Dictionary) -> Vector2:
	return Vector2(float(isle["r"]) - 3.0, 0.0)

static func jetty_end(isle: Dictionary) -> Vector2:
	return Vector2(float(isle["r"]) + JETTY, 0.0)

# ---------------------------------------------------------------- shape
## Per island, per angle (720 steps round): the coast's radius and how much of it is cliff.
static func _tables(isle: Dictionary) -> Dictionary:
	var id: String = isle["id"]
	if _cache.has(id):
		return _cache[id]
	var n := FastNoiseLite.new()
	n.seed = int(isle["seed"])
	n.frequency = 1.0
	n.fractal_octaves = 3
	var rad := PackedFloat32Array()
	var cl := PackedFloat32Array()
	rad.resize(720)
	cl.resize(720)
	var r := float(isle["r"])
	for k in 720:
		var a := TAU * k / 720.0
		var land := absf(wrapf(a, -PI, PI))
		var keep := smoothstep(0.12, 0.55, land)      # the landing beach keeps its exact radius
		var w := n.get_noise_2d(cos(a) * 1.3, sin(a) * 1.3) * 0.75 + n.get_noise_2d(cos(a) * 4.0 + 9.0, sin(a) * 4.0) * 0.25
		rad[k] = r * (1.0 + clampf(w * 0.32, -0.12, 0.08) * keep)
		var c := float(isle["cliff"]) * smoothstep(0.35, 0.95, land)
		var cn := n.get_noise_2d(cos(a) * 2.2 + 30.0, sin(a) * 2.2) * 0.5 + 0.5
		cl[k] = clampf(c * smoothstep(0.3, 0.6, cn + float(isle["cliff"]) * 0.45), 0.0, 1.0)
	var relief := FastNoiseLite.new()
	relief.seed = int(isle["seed"]) + 7
	relief.frequency = 0.018
	relief.fractal_octaves = 4
	var t := {"rad": rad, "cliff": cl, "noise": relief, "pads": script_of(isle).pads(isle, relief)}
	_cache[id] = t
	return t

static func _ang_i(a: float) -> int:
	return posmod(int(round(a / TAU * 720.0)), 720)

static func coast_r(isle: Dictionary, a: float) -> float:
	return float((_tables(isle)["rad"] as PackedFloat32Array)[_ang_i(a)])

static func cliff_at(isle: Dictionary, a: float) -> float:
	return float((_tables(isle)["cliff"] as PackedFloat32Array)[_ang_i(a)])

## Ground height at island-local (u, v): sea floor, beach or cliff, the island's own relief inland, pads.
static func elev(isle: Dictionary, l: Vector2) -> float:
	var d := l.length()
	var r := float(isle["r"])
	if d > r * 1.08 + 56.0:
		return DEEP
	var tb := _tables(isle)
	var a := atan2(l.y, l.x)
	var rr := coast_r(isle, a)
	var s := rr - d
	var cl := cliff_at(isle, a)
	var h: float
	if s < 0.0:
		# under the water: a sandy shelf that drops away, steeper below the cliffs
		var shelf := -0.25 + s * 0.2 - s * s * 0.006
		var wall := -2.5 + s * 0.75
		h = maxf(lerpf(shelf, wall, cl), DEEP)
	else:
		var bw := lerpf(float(isle["beach"]), 2.0, cl)
		var beach := minf(s / bw, 1.0) * 1.1 + maxf(s - bw, 0.0) * 0.02
		var cliff := float(isle["cliff_h"]) * smoothstep(0.0, 3.2, s) + maxf(s - 3.2, 0.0) * 0.01
		var edge := lerpf(beach, cliff, cl)
		var inner: float = script_of(isle).relief(isle, l, s, rr, tb["noise"]) * smoothstep(bw * 0.5, bw + 16.0, s)
		# the beach slopes down into the water; inland rises from where the sand ends
		h = maxf(edge, lerpf(edge, 1.1 + inner, smoothstep(bw * 0.6, bw + 4.0, s)))
	for p in tb["pads"]:
		var pd := l.distance_to(p[0])
		if pd < float(p[1]) + 6.0:
			h = lerpf(h, float(p[2]), 1.0 - smoothstep(float(p[1]), float(p[1]) + 6.0, pd))
	return h

## The island's height at a coast-frame point (DEEP when far from it).
static func elev_coast(isle: Dictionary, p: Vector2) -> float:
	return elev(isle, to_local(isle, p))

## Rough local spots for dressing: a point on dry, gentle ground (null if none in `tries`).
static func land_spot(isle: Dictionary, rng: RandomNumberGenerator, min_h := 1.6, max_slope := 0.6, tries := 12) -> Variant:
	var r := float(isle["r"])
	for i in tries:
		var a := rng.randf() * TAU
		var d := sqrt(rng.randf()) * r
		var l := Vector2(cos(a), sin(a)) * d
		var h := elev(isle, l)
		if h < min_h:
			continue
		var gx := elev(isle, l + Vector2(1, 0)) - h
		var gz := elev(isle, l + Vector2(0, 1)) - h
		if Vector2(gx, gz).length() > max_slope:
			continue
		return l
	return null

static func near_pad(isle: Dictionary, l: Vector2, extra := 2.0) -> bool:
	for p in _tables(isle)["pads"]:
		if l.distance_to(p[0]) < float(p[1]) + extra:
			return true
	return false

# ---------------------------------------------------------------- building
## Places island-local `l` into zone `w`, whose frame puts the island centre at `o` (the coast: its
## real centre; its own zone: the origin) and keeps the coast's orientation, so the sun, the swell and
## the far shores line up wherever you stand.
static func at(w: World, isle: Dictionary, o: Vector2, l: Vector2) -> Vector3:
	var p := to_coast(isle, l) - centre(isle) + o
	return Vector3(p.x, w.height_at(p.x, p.y), p.y)

## Yaw (rotation.y) in the zone for a heading given in island-local terms.
static func yaw(isle: Dictionary, local_yaw: float) -> float:
	var u: Vector2 = axes(isle)[0]
	return local_yaw + atan2(u.x, u.y)

## Everything that is the same out at sea and on the island: trees, rocks, the landmark, the jetty.
## `full` adds what only its own zone has: grass, small props, the places to explore.
static func dress(w: World, isle: Dictionary, o: Vector2, full: bool) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = int(isle["seed"]) * 13 + 1
	jetty(w, isle, o, full)
	shore_rocks(w, isle, o, rng, full)
	script_of(isle).dress(w, isle, o, full, rng)

## The jetty: posts and planks from the beach out to where a boat can tie up.
static func jetty(w: World, isle: Dictionary, o: Vector2, full: bool) -> void:
	var a := jetty_root(isle)
	var b := jetty_end(isle)
	var g := Models.N(null, "jetty")
	var len := a.distance_to(b)
	var wd := Props.wood()
	var wdd := Props.wood_dark()
	var deck := 0.95
	var n := int(len / 0.42)
	for k in n:
		var x := -len * 0.5 + (k + 0.5) * len / n
		Models.P(g, Geo.box(0.38, 0.08, 2.6), wd if k % 4 else wdd, Vector3(x, deck, 0), Vector3(0, w.rng.randf_range(-1.5, 1.5), 0))
	for k in int(len / 3.0) + 1:
		var x := -len * 0.5 + k * 3.0
		for sz in [-1.25, 1.25]:
			Models.seg(g, Vector3(x, -4.5, sz), Vector3(x, deck + (0.6 if k % 2 == 0 else 0.1), sz), 0.13, 0.12, wdd, 7)
	Models.P(g, Geo.box(len, 0.12, 0.18), wdd, Vector3(0, deck - 0.12, 1.2))
	Models.P(g, Geo.box(len, 0.12, 0.18), wdd, Vector3(0, deck - 0.12, -1.2))
	var mid := (a + b) * 0.5
	var p := at(w, isle, o, mid)
	if g.get_parent() == null:
		w.props_root.add_child(g)
	g.position = Vector3(p.x, 0.0, p.z)
	g.rotation.y = yaw(isle, PI * 0.5)
	w.add_deck(Vector2(p.x, p.z), Vector2(len * 0.5 + 0.3, 1.3), g.rotation.y, deck + 0.05)
	if full:
		# a lantern post at the jetty's end and a mooring bollard
		var ep := at(w, isle, o, b - Vector2(0.6, 0))
		Props.fire(w.props_root, Vector3(ep.x, deck + 2.1, ep.z), 0.25, Color(1.0, 0.7, 0.35), true, false, false)
		var post := Models.N(w.props_root, "jetty_lamp")
		Models.seg(post, Vector3(ep.x, deck, ep.z), Vector3(ep.x, deck + 2.0, ep.z), 0.08, 0.07, wdd, 6)

## Boulders along the shore (and sea stacks off the cliffs), more where it's cliff.
static func shore_rocks(w: World, isle: Dictionary, o: Vector2, rng: RandomNumberGenerator, full: bool) -> void:
	var n := 140
	for i in n:
		var a := rng.randf() * TAU
		if absf(wrapf(a, -PI, PI)) < 0.22:
			continue                     # keep the landing clear
		var cl := cliff_at(isle, a)
		if rng.randf() > 0.35 + cl * 0.65:
			continue
		var rr := coast_r(isle, a)
		var off := rng.randf_range(-7.0, 2.5) - cl * rng.randf_range(0.0, 7.0)
		var l := Vector2(cos(a), sin(a)) * (rr - off)
		var p := at(w, isle, o, l)
		var s := rng.randf_range(0.8, 2.4) * (1.0 + cl * rng.randf_range(0.0, 1.6))
		if p.y < -3.2:
			continue
		if p.y < -0.3:
			s = maxf(s, (-p.y + rng.randf_range(0.4, 1.2)) / 0.28)   # tall enough to break the surface
		w._rock(Vector3(p.x, 0, p.z), s, full)
		if p.y < 0.4:
			sea_rock(w, Vector2(p.x, p.z), s * 0.5)

## Moves each named place ("poi_*") that landed on something solid or steep to the nearest open
## ground you can walk to from the jetty, so later content placed there is always reachable.
static func _settle_places(w: World) -> void:
	var st: Vector3 = w.spawns["start"]
	for k in w.spawns.keys():
		if not str(k).begins_with("poi_"):
			continue
		var p: Vector3 = w.spawns[k]
		if not w.is_blocked(p.x, p.z) and w.find_path(st, p).size() > 1:
			continue
		var best := p
		var found := false
		for ring in range(1, 26):
			for i in 16:
				var a := TAU * i / 16.0
				var q := p + Vector3(cos(a), 0, sin(a)) * ring
				if w.is_blocked(q.x, q.z) or w.find_path(st, q).size() < 2:
					continue
				best = Vector3(q.x, w.height_at(q.x, q.z), q.z)
				found = true
				break
			if found:
				break
		if found:
			w.spawns[k] = best
		else:
			push_warning("Isles: no reachable ground near %s" % k)

## Rocks standing in the water: boats steer round them (boat.gd reads World meta "sea_rocks").
static func sea_rock(w: World, p: Vector2, r: float) -> void:
	if not w.has_meta("sea_rocks"):
		w.set_meta("sea_rocks", [])
	(w.get_meta("sea_rocks") as Array).append([p, r])

## Trees over the island: `n` tries, each kind [mesh, weight, scale min, scale max]; `ok(l, h)` says
## whether a local spot may have one. Its own zone gives them trunks to bump into.
static func forest(w: World, isle: Dictionary, o: Vector2, rng: RandomNumberGenerator, n: int, kinds: Array, ok: Callable, full: bool, sink := 0.15) -> Array:
	var tot := 0.0
	for k in kinds:
		tot += float(k[1])
	var xf: Array = []
	for k in kinds:
		xf.append([])
	var placed: Array = []
	for i in n:
		var sp: Variant = land_spot(isle, rng, 1.7, 0.75, 3)
		if sp == null:
			continue
		var l: Vector2 = sp
		var h := elev(isle, l)
		if near_pad(isle, l, 3.0) or not bool(ok.call(l, h)):
			continue
		var pick := rng.randf() * tot
		var ki := 0
		while ki < kinds.size() - 1 and pick > float(kinds[ki][1]):
			pick -= float(kinds[ki][1])
			ki += 1
		var sc := rng.randf_range(float(kinds[ki][2]), float(kinds[ki][3]))
		var p := at(w, isle, o, l)
		(xf[ki] as Array).append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * sc), Vector3(p.x, p.y - sink, p.z)))
		placed.append(l)
		if full:
			w.add_circle(Vector3(p.x, 0, p.z), 0.55 * sc)
			w.tree_pts.append(Vector2(p.x, p.z))
	for ki in kinds.size():
		if not (xf[ki] as Array).is_empty():
			w.mm_chunked(kinds[ki][0], xf[ki], true, 40.0, 0.0)
	return placed

## A local point's zone position on the ground plus a lift.
static func pos(w: World, isle: Dictionary, o: Vector2, l: Vector2, lift := 0.0) -> Vector3:
	var p := at(w, isle, o, l)
	p.y += lift
	return p

## The island's own zone ("isle_<id>"): its ground at full detail with the island at the origin,
## everything on it, and the rest of the sea (the other islands, the mainland) drawn far off.
static func build_zone(w: World, id: String) -> void:
	var isle := get_isle(id)
	var c := centre(isle)
	w.sea = true
	w.steep = 1.35
	w.theme = {"name": "isle", "isle": id}
	var half := float(isle["r"]) * 1.08 + 6.0
	w.bounds = Rect2(-half, -half, half * 2.0, half * 2.0)
	var key := "isle_" + id
	if not _grids.has(key):
		_grids[key] = HeightGrid.new().bake(w.bounds.grow(World.MARGIN + 30.0), 1.0, func(x: float, z: float) -> float: return Coast.ground(Vector2(x, z) + c))
	var grid: HeightGrid = _grids[key]
	var coarse := Coast.coarse()
	w.height_fn = func(x: float, z: float) -> float:
		if grid.has(x, z):
			return grid.sample(x, z)
		if coarse.has(x + c.x, z + c.y):
			return coarse.sample(x + c.x, z + c.y)
		return Isles.DEEP
	dress(w, isle, Vector2.ZERO, true)
	var lr := at(w, isle, Vector2.ZERO, jetty_root(isle) - Vector2(4.0, 0))
	w.spawns["start"] = lr
	w.spawns["jetty"] = lr
	w.exits.append({"pos": at(w, isle, Vector2.ZERO, jetty_end(isle) - Vector2(1.0, 0)), "radius": 1.8, "to": "coast", "label": "Back to the Mournwater Coast"})
	w._rasterize()
	_settle_places(w)
	w._flush_stones(Props.stone())
	var tc: Dictionary = (isle["terrain"] as Dictionary).duplicate()
	tc["sea"] = 1.0
	tc["col_sand"] = isle["sand"]
	var near := w.bounds.grow(World.MARGIN + 28.0)
	w.terrain_patch(near, 1.0 if World.detail >= 2 else 1.5, tc, "Terrain", DEEP + 1.0)
	w.set_meta("sea_rect", Rect2(Coast.sea_rect().position - c, Coast.sea_rect().size))
	Grass.scatter(w.props_root, w.bounds, w, Grass.ACT1, World.detail, int(isle["seed"]) * 97)
	w._scatter_ferns(int(isle.get("ferns", 400)))
	# the rest of the sea, far off: the other islands and the mainland, as seen from the shore
	Coast.distant(w, -c, near, 4.0)
