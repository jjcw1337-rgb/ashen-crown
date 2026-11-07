class_name BgForest
extends RefCounted
## The Verdant Reach: the Battlegrounds map of the multiplayer overhaul (Blaine, 2026-11-06: "a whole rebuild of the
## map for battlegrounds, no corridors"). A lush open forest of oversized oaks, 210 m across, with four starting
## glades in its corners, every place joined by winding trails with loops and shortcuts, a stream down the middle,
## ridgelines with passes, and four regions:
##   the mushroom woodland (south-west): giant fungi, glowing growths, brambles; treant-like things; Old Mossbeard's grotto
##   the dark elf encampments (north-east): tents, carved totems, timber lookouts, a ritual circle
##   the frostfang hollow (north-west): pines, ice and rime on a raised hollow; Hrimgar the Frostbound
##   the old ruins (south-east and the middle): standing stones, broken walls, the barrow, the Sundered Circle
## Seventeen camps (Camps: six tier I near the glades, five tier II, three tier III, three bosses), each its own
## clearing with a deliberate fight; extraction portals at the four edges. Every number placing things is here, the
## camps' encounters in CAMPS (swap the foes without touching the place).

const TITLE := "The Verdant Reach"
const PROPS := "res://game/maps/verdant_reach/props/"
const LANTERN_AT := Vector3(-0.6, 1.5, 0.0)     # where the lantern hangs on lantern_post.glb (its own frame)
const HALF := 105.0
## The four starting glades, the four extraction portals
const SPAWNS := [Vector2(-88, 88), Vector2(88, 88), Vector2(88, -88), Vector2(-88, -88)]
const PORTALS := [Vector2(-102, 2), Vector2(102, -4), Vector2(34, -101), Vector2(-34, 101)]
const MUSH_C := Vector2(-56, 46)
const MUSH_R := 42.0
const ELF_C := Vector2(54, -52)
const ELF_R := 40.0
const FROST_C := Vector2(-50, -56)
const FROST_R := 30.0
## The stream, north to south, and the ridges (polyline, height, half-width); trails cut passes through them
const STREAM := [Vector2(22, -118), Vector2(14, -82), Vector2(26, -50), Vector2(18, -18), Vector2(26, 8), Vector2(16, 40),
	Vector2(-2, 64), Vector2(-10, 88), Vector2(-18, 118)]
const RIDGES := [
	[[Vector2(-108, -4), Vector2(-70, -12), Vector2(-32, -24), Vector2(-16, -52), Vector2(-24, -86), Vector2(-30, -112)], 7.0, 8.0],
	[[Vector2(110, 40), Vector2(80, 38), Vector2(60, 16), Vector2(64, -8)], 6.0, 7.0],
]
## The camps: id, name, tier (4 = boss), centre, radius, region, foes (kind, count, champ?, at: offset), chest offset
const CAMPS := [
	{"id": "sporefall", "name": "Sporefall Dell", "tier": 1, "at": Vector2(-60, 70), "r": 11.0, "region": "mush",
		"foes": [{"kind": "spore_shroom", "count": 2, "at": Vector3(-3, 0, 2)}, {"kind": "treant", "count": 1}]},
	{"id": "fallen_watch", "name": "Fallen Watch", "tier": 1, "at": Vector2(64, 72), "r": 11.0, "region": "ruins",
		"foes": [{"kind": "fallen_skirmisher", "count": 2}, {"kind": "skel_archer", "count": 1, "at": Vector3(3, 0, -4)}]},
	{"id": "shadeleaf", "name": "Shadeleaf Outpost", "tier": 1, "at": Vector2(70, -58), "r": 11.0, "region": "elf",
		"foes": [{"kind": "dark_elf", "count": 2}, {"kind": "dark_elf_archer", "count": 1, "at": Vector3(-3, 0, -4)}]},
	{"id": "pinehollow", "name": "Pinehollow", "tier": 1, "at": Vector2(-74, -70), "r": 11.0, "region": "frost",
		"foes": [{"kind": "spirit_beast", "count": 3}]},
	{"id": "thornbrook", "name": "Thornbrook Ford", "tier": 1, "at": Vector2(-10, 88), "r": 10.0, "region": "ruins",
		"foes": [{"kind": "goblin_guard", "count": 3}, {"kind": "zombie", "count": 1, "at": Vector3(4, 0, 2)}]},
	{"id": "hollow_stump", "name": "Hollow Stump", "tier": 1, "at": Vector2(6, -86), "r": 10.0, "region": "forest",
		"foes": [{"kind": "feral", "count": 2}, {"kind": "spirit_beast", "count": 1, "at": Vector3(3, 0, 3)}]},
	{"id": "rootknot", "name": "Rootknot Hollow", "tier": 2, "at": Vector2(-36, 56), "r": 12.0, "region": "mush",
		"foes": [{"kind": "treant", "count": 2}, {"kind": "spore_shroom", "count": 2, "at": Vector3(4, 0, -3)}, {"kind": "spider", "count": 2, "at": Vector3(-4, 0, 3)}]},
	{"id": "brookside", "name": "Brookside Ruins", "tier": 2, "at": Vector2(40, 54), "r": 12.0, "region": "ruins",
		"foes": [{"kind": "fallen_reaver", "count": 1}, {"kind": "fallen_stalker", "count": 2, "at": Vector3(-3, 0, 3)}, {"kind": "skel_archer", "count": 2, "at": Vector3(4, 0, -5)}]},
	{"id": "nightwhisper", "name": "Nightwhisper Camp", "tier": 2, "at": Vector2(42, -68), "r": 12.0, "region": "elf",
		"foes": [{"kind": "dark_elf", "count": 3}, {"kind": "dark_elf_archer", "count": 2, "at": Vector3(0, 0, -6)}]},
	{"id": "rimewood", "name": "Rimewood Edge", "tier": 2, "at": Vector2(-88, -24), "r": 12.0, "region": "frost",
		"foes": [{"kind": "troll_shaman", "count": 1, "at": Vector3(0, 0, -4)}, {"kind": "spirit_beast", "count": 3}]},
	{"id": "barrow", "name": "Mossy Barrow", "tier": 2, "at": Vector2(88, 20), "r": 12.0, "region": "barrow",
		"foes": [{"kind": "zombie", "count": 3}, {"kind": "skel_archer", "count": 2, "at": Vector3(-4, 0, 4)}]},
	{"id": "heartwood", "name": "Heartwood Grove", "tier": 3, "at": Vector2(-40, 18), "r": 14.0, "region": "mush",
		"foes": [{"kind": "treant", "count": 1, "champ": true}, {"kind": "treant", "count": 1, "at": Vector3(5, 0, 3)}, {"kind": "bear", "count": 1, "at": Vector3(-5, 0, -3)}]},
	{"id": "obsidian", "name": "The Obsidian Circle", "tier": 3, "at": Vector2(44, -28), "r": 14.0, "region": "elf",
		"foes": [{"kind": "dark_elf", "count": 2, "champ": true}, {"kind": "dark_elf_archer", "count": 3, "at": Vector3(0, 0, -7)}, {"kind": "troll_shaman", "count": 1, "at": Vector3(6, 0, 2)}]},
	{"id": "sundered", "name": "The Sundered Circle", "tier": 3, "at": Vector2(4, 16), "r": 15.0, "region": "ruins",
		"foes": [{"kind": "fallen_reaver", "count": 1, "champ": true}, {"kind": "fallen_reaver", "count": 1, "at": Vector3(5, 0, 4)},
			{"kind": "fallen_stalker", "count": 2, "at": Vector3(-5, 0, -2)}, {"kind": "skel_archer", "count": 2, "at": Vector3(0, 0, -8)}]},
	{"id": "frostfang", "name": "Frostfang Hollow", "tier": 4, "at": Vector2(-50, -54), "r": 16.0, "region": "frost", "boss": "ice_troll",
		"foes": [{"kind": "ice_troll", "count": 1}, {"kind": "spirit_beast", "count": 2, "at": Vector3(6, 0, 5)}]},
	{"id": "gilded_hoard", "name": "The Gilded Hoard", "tier": 4, "at": Vector2(58, 30), "r": 16.0, "region": "ruins", "boss": "goblin_king",
		"foes": [{"kind": "goblin_king", "count": 1}, {"kind": "goblin_guard", "count": 3, "at": Vector3(5, 0, 4)}]},
	{"id": "grotto", "name": "Mycelial Grotto", "tier": 4, "at": Vector2(-72, 30), "r": 16.0, "region": "mush", "boss": "hermit",
		"foes": [{"kind": "hermit", "count": 1}, {"kind": "spore_shroom", "count": 3, "at": Vector3(5, 0, -4)}]},
]
## The trails: pairs of places (camp ids, "s0".."s3" for the glades, "p0".."p3" for the portals), each a winding path
const TRAILS := [
	["s0", "sporefall"], ["sporefall", "rootknot"], ["s0", "thornbrook"], ["thornbrook", "rootknot"], ["thornbrook", "fallen_watch"],
	["s1", "fallen_watch"], ["fallen_watch", "brookside"], ["brookside", "sundered"], ["rootknot", "heartwood"], ["heartwood", "sundered"],
	["heartwood", "grotto"], ["sporefall", "grotto"], ["s1", "barrow"], ["barrow", "obsidian"], ["s2", "shadeleaf"], ["shadeleaf", "nightwhisper"],
	["nightwhisper", "hollow_stump"], ["shadeleaf", "obsidian"], ["obsidian", "sundered"], ["nightwhisper", "obsidian"], ["s2", "barrow"],
	["s3", "pinehollow"], ["pinehollow", "frostfang"], ["pinehollow", "hollow_stump"], ["s3", "rimewood"], ["rimewood", "grotto"],
	["rimewood", "frostfang"], ["frostfang", "heartwood"], ["brookside", "barrow"], ["brookside", "gilded_hoard"], ["barrow", "gilded_hoard"],
	["p0", "rimewood"], ["p1", "barrow"], ["p2", "hollow_stump"], ["p3", "thornbrook"],
]
const TERRAIN := {
	"col_a": Color(0.2, 0.34, 0.11), "col_b": Color(0.27, 0.4, 0.13), "col_accent": Color(0.34, 0.46, 0.16),
	"col_path": Color(0.42, 0.34, 0.22), "col_cliff": Color(0.36, 0.36, 0.32), "wet": 0.25,
}
## The grass: a WoW-like rich green (Grass.scatter's palette)
const GRASS := {"base_col": Color(0.13, 0.27, 0.07), "tip_col": Color(0.42, 0.62, 0.2), "dry_col": Color(0.55, 0.52, 0.28), "wind": 1.0}
const TREES := 1900
## How far an oak's crown reaches: oaks stand at least this far from open ground (camps, trails, glades)
const CANOPY := 9.0

static var _noise: FastNoiseLite
static var _paths: Array = []        # PackedVector2Array per trail, laid by build (relief cuts passes along them)

static func place_of(key: String) -> Vector2:
	if key.begins_with("s") and key.length() == 2:
		return SPAWNS[int(key.substr(1))]
	if key.begins_with("p") and key.length() == 2:
		return PORTALS[int(key.substr(1))]
	for c in CAMPS:
		if c["id"] == key:
			return c["at"]
	return Vector2.ZERO

static func _seg_d(p: Vector2, pts: Array) -> float:
	var m := 1e9
	for i in pts.size() - 1:
		m = minf(m, p.distance_to(Geometry2D.get_closest_point_to_segment(p, pts[i], pts[i + 1])))
	return m

static func stream_d(p: Vector2) -> float:
	return _seg_d(p, STREAM)

## Distance to the nearest trail, from a grid baked once (_bake_trails): the ground, the trees and the grass ask it
## hundreds of thousands of times.
static func trail_d(p: Vector2) -> float:
	if _tgrid.is_empty():
		return 99.0
	var i := int(floor((p.x - _go.x) / CELL))
	var j := int(floor((p.y - _go.y) / CELL))
	if i < 0 or j < 0 or i >= _gw or j >= _gh:
		return 99.0
	return _tgrid[j * _gw + i]

const CELL := 1.0
const REACH := 10.0
static var _go := Vector2.ZERO
static var _gw := 0
static var _gh := 0
static var _tgrid := PackedFloat32Array()

static func _bake_trails() -> void:
	var area := Rect2(-HALF - 34.0, -HALF - 34.0, HALF * 2.0 + 68.0, HALF * 2.0 + 68.0)
	_go = area.position
	_gw = int(area.size.x / CELL) + 1
	_gh = int(area.size.y / CELL) + 1
	_tgrid = PackedFloat32Array()
	_tgrid.resize(_gw * _gh)
	_tgrid.fill(99.0)
	for poly in _paths:
		for k in poly.size() - 1:
			var a: Vector2 = poly[k]
			var b: Vector2 = poly[k + 1]
			var i0 := maxi(0, int(floor((minf(a.x, b.x) - REACH - _go.x) / CELL)))
			var i1 := mini(_gw - 1, int(ceil((maxf(a.x, b.x) + REACH - _go.x) / CELL)))
			var j0 := maxi(0, int(floor((minf(a.y, b.y) - REACH - _go.y) / CELL)))
			var j1 := mini(_gh - 1, int(ceil((maxf(a.y, b.y) + REACH - _go.y) / CELL)))
			for j in range(j0, j1 + 1):
				for i in range(i0, i1 + 1):
					var q := _go + Vector2((i + 0.5) * CELL, (j + 0.5) * CELL)
					var d := q.distance_to(Geometry2D.get_closest_point_to_segment(q, a, b))
					var at := j * _gw + i
					if d < _tgrid[at]:
						_tgrid[at] = d

## The ground's shape on top of World's own (its rim hills): rolling ground, the ridges (cut down where a trail
## crosses), the frost hollow raised, the stream's bed, and each camp levelled so its fight reads.
static func relief(x: float, z: float) -> float:
	if _noise == null:
		_noise = FastNoiseLite.new()
		_noise.seed = 5150
		_noise.frequency = 0.012
		_noise.fractal_octaves = 3
	var p := Vector2(x, z)
	var h := 2.6 * _noise.get_noise_2dv(p) + 1.0 * _noise.get_noise_2dv(p * 3.1 + Vector2(50, 9))
	var cut := 1.0 - smoothstep(3.0, 9.0, trail_d(p))
	for r in RIDGES:
		var d := _seg_d(p, r[0])
		var rh := float(r[1]) * exp(-pow(d / float(r[2]), 2.0)) * (0.85 + 0.3 * _noise.get_noise_2dv(p * 0.7))
		h += rh * (1.0 - 0.9 * cut)
	h += 2.4 * (1.0 - smoothstep(FROST_R * 0.7, FROST_R * 1.15, p.distance_to(FROST_C)))
	for c in CAMPS:
		var dc := p.distance_to(c["at"])
		var k := smoothstep(float(c["r"]) * 0.7, float(c["r"]) * 1.5, dc)
		h = lerpf(h * 0.25, h, k)
	h -= 1.5 * (1.0 - smoothstep(2.2, 5.5, stream_d(p)))
	return h

static func build(w: World) -> void:
	w.theme = {"name": "bg_forest"}
	w.bounds = Rect2(-HALF, -HALF, HALF * 2.0, HALF * 2.0)
	var rng := w.rng
	# the trails first: the ground's passes and the trees' clearance follow them
	_paths = []
	for t in TRAILS:
		var a := place_of(t[0])
		var b := place_of(t[1])
		var mid := (a + b) * 0.5 + (b - a).orthogonal().normalized() * rng.randf_range(-0.16, 0.16) * a.distance_to(b)
		var q1 := a.lerp(mid, 0.5) + Vector2(rng.randf_range(-4, 4), rng.randf_range(-4, 4))
		var q2 := mid.lerp(b, 0.5) + Vector2(rng.randf_range(-4, 4), rng.randf_range(-4, 4))
		var poly := w._spline([a, q1, mid, q2, b], 6)
		_paths.append(poly)
		w.trails.append(poly)
		for i in poly.size() - 1:
			w.dirt_lines.append([poly[i], poly[i + 1], 2.3])
	_bake_trails()
	w.ground_fn = func(x: float, z: float) -> float: return BgForest.relief(x, z)
	for s in SPAWNS:
		w.dirt_blobs.append([s, 8.0, 0.8])
	for c in CAMPS:
		w.dirt_blobs.append([c["at"], float(c["r"]) * 0.75, 0.55])
	for p in PORTALS:
		w.dirt_blobs.append([p, 5.0, 0.7])
	# the camps: each its clearing, its region's dressing, its encounter and chest
	for c in CAMPS:
		var at := Vector3(c["at"].x, 0, c["at"].y)
		var chest_ofs := Vector3(0, 0, -float(c["r"]) * 0.45)
		var foes: Array = c["foes"]
		Camps.add(w, c["id"], c["name"], int(c["tier"]), at, float(c["r"]), foes, chest_ofs)
		_dress_camp(w, c, rng)
	# the starting glades: lanterns (no bell: a match starts by itself, Blaine 2026-11-06); the extraction portals: a
	# ring of rune stones round the light
	var spawns := []
	for s in SPAWNS:
		var sp := Vector3(s.x, 0, s.y)
		spawns.append(sp)
		for k in 4:
			var a := TAU * k / 4.0 + 0.4
			_lantern_post(w, Vector2(s.x + cos(a) * 7.5, s.y + sin(a) * 7.5))
	w.set_meta("bg_spawns", spawns)
	w.set_meta("bg_gates", [])
	for p in PORTALS:
		var it: Inter = w._inter("extract", "Extraction Portal", Vector3(p.x, 0, p.y), 1.8, Fx.portal_model(Color(0.45, 0.95, 0.75)), {"open": false})
		var m := it.get_node_or_null("Model")
		if m:
			m.visible = false
		for k in 6:
			var a := TAU * k / 6.0
			w._standing_stone(Vector3(p.x + cos(a) * 4.2, 0, p.y + sin(a) * 4.2), rng.randf_range(1.8, 2.6))
	_ridge_rocks(w, rng)
	_stream(w)
	_forest(w, rng)
	_regions(w, rng)
	w._rasterize()
	w._flush_stones(Props.stone())
	w._build_terrain(TERRAIN)
	if not Engine.is_editor_hint():
		w.living_grass = true
		w._grass_dry.seed = 77
		w._grass_dry.frequency = 0.03
		Grass.scatter(w.props_root, w.bounds.grow(World.MARGIN * 0.6), w, GRASS, World.detail, 6060)
		w._scatter_ferns(1400)
	w.spawns["start"] = spawns[0]
	# the life and colour on top: flowers, butterflies, fireflies, shrines (ForestLife; visual only, its own seeds)
	ForestLife.dress(w)

## Is a point kept clear of trees and growth: trails, camps' fighting ground, the glades, the portals, the stream.
static func open_at(p: Vector2, pad := 0.0) -> bool:
	if trail_d(p) < 4.0 + pad or stream_d(p) < 4.5 + pad:
		return true
	for c in CAMPS:
		if p.distance_to(c["at"]) < float(c["r"]) * 0.9 + pad:
			return true
	for s in SPAWNS:
		if p.distance_to(s) < 13.0 + pad:
			return true
	for q in PORTALS:
		if p.distance_to(q) < 8.0 + pad:
			return true
	return false

static func region_at(p: Vector2) -> String:
	if p.distance_to(MUSH_C) < MUSH_R:
		return "mush"
	if p.distance_to(ELF_C) < ELF_R:
		return "elf"
	if p.distance_to(FROST_C) < FROST_R * 1.35:
		return "frost"
	return "forest"

## The forest: oversized oaks everywhere (bigger toward the middle), pines in the frost hollow, bushes under them,
## and the woodland's floor; trees thin near the open ground so camps have cover at their edges, not walls.
static func _forest(w: World, rng: RandomNumberGenerator) -> void:
	var meshes := {"oak0": Flora.oak_model(1), "oak1": Flora.oak_model(2), "oak2": Flora.oak_model(3),
		"pine0": Flora.pine(4), "pine1": Flora.pine(5), "bush0": Flora.bush(3), "bush1": Flora.bush(5), "dead0": Flora.dead_tree(23)}
	var groups := {}
	var placed := 0
	var tries := 0
	var area := w.bounds.grow(World.MARGIN - 4.0)
	while placed < TREES and tries < TREES * 8:
		tries += 1
		var p := Vector2(rng.randf_range(area.position.x, area.end.x), rng.randf_range(area.position.y, area.end.y))
		var inside := w.bounds.grow(-1.5).has_point(p)
		if inside and open_at(p):
			continue
		if inside and open_at(p, 5.0) and rng.randf() < 0.7:
			continue       # (a looser fringe round the open ground)
		var fringe := inside and open_at(p, CANOPY)       # (an oak's crown would hang over the fight or the trail)
		var reg := region_at(p)
		var key := ""
		var r := rng.randf()
		match reg:
			"frost":
				key = "pine%d" % (placed % 2) if r < 0.75 else ("dead0" if r < 0.85 else "bush1")
			"mush":
				if r < 0.35:
					continue       # (the fungi stand in for trees there: _mushrooms)
				key = "oak%d" % (placed % 3) if r < 0.75 else "bush0"
			_:
				key = "oak%d" % (placed % 3) if r < 0.72 else ("bush%d" % (placed % 2) if r < 0.93 else "pine0")
		if fringe and key.begins_with("oak"):
			key = "bush%d" % (placed % 2)
		var s := rng.randf_range(1.15, 1.9) if key.begins_with("oak") else rng.randf_range(0.9, 1.4)
		if not groups.has(key):
			groups[key] = []
		groups[key].append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * s), Vector3(p.x, w.height_at(p.x, p.y) - 0.15, p.y)))
		if inside and not key.begins_with("bush"):
			w.add_circle(Vector3(p.x, 0, p.y), (0.75 if key.begins_with("oak") else 0.5) * s)
		if not key.begins_with("bush"):
			w.tree_pts.append(p)
		placed += 1
	for key in groups:
		w.mm_chunked(meshes[key], groups[key], true, 32.0, 110.0 if key.begins_with("oak") else 0.0)

## Boulders along each ridge's crest, solid, with a gap wherever a trail crosses: the passes.
static func _ridge_rocks(w: World, rng: RandomNumberGenerator) -> void:
	for r in RIDGES:
		var pts: Array = r[0]
		for i in pts.size() - 1:
			var a: Vector2 = pts[i]
			var b: Vector2 = pts[i + 1]
			var n := int(a.distance_to(b) / 3.2)
			for k in n:
				var q := a.lerp(b, (k + rng.randf()) / float(n)) + (b - a).orthogonal().normalized() * rng.randf_range(-1.5, 1.5)
				if trail_d(q) < 7.0 or not w.bounds.grow(-2.0).has_point(q):
					continue
				w._rock(Vector3(q.x, 0, q.y), rng.randf_range(1.4, 2.6), true)

## The stream: a ribbon of moving water in its bed, plank bridges where the main trails cross it.
static func _stream(w: World) -> void:
	var pts := w._spline(STREAM, 8)
	# its bed: wet mud and pebbles under the water, so the grass doesn't grow through it (visual only: the dirt
	# mask colours the ground and keeps grass off, nothing walks by it)
	for i in pts.size() - 1:
		w.dirt_lines.append([pts[i], pts[i + 1], 2.9])
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var half := 2.6
	var along := 0.0
	# each point's sideways direction is the mean of its two segments', so the ribbon bends without gaps or overlaps
	var sides := PackedVector2Array()
	for i in pts.size():
		var d0: Vector2 = (pts[i] - pts[maxi(i - 1, 0)]).normalized() if i > 0 else Vector2.ZERO
		var d1: Vector2 = (pts[mini(i + 1, pts.size() - 1)] - pts[i]).normalized() if i < pts.size() - 1 else Vector2.ZERO
		var dd := (d0 + d1).normalized()
		sides.append(dd.orthogonal() * half / maxf(0.5, dd.dot(d1 if d1 != Vector2.ZERO else d0)))
	for i in pts.size() - 1:
		var a: Vector2 = pts[i]
		var b: Vector2 = pts[i + 1]
		var na: Vector2 = sides[i]
		var nb: Vector2 = sides[i + 1]
		var ya := w.ground_h(a.x, a.y) + 0.55
		var yb := w.ground_h(b.x, b.y) + 0.55
		var l := a.distance_to(b)
		var v := [Vector3(a.x + na.x, ya, a.y + na.y), Vector3(a.x - na.x, ya, a.y - na.y), Vector3(b.x + nb.x, yb, b.y + nb.y), Vector3(b.x - nb.x, yb, b.y - nb.y)]
		var uv := [Vector2(0, along), Vector2(1, along), Vector2(0, along + l), Vector2(1, along + l)]
		for idx in [0, 2, 1, 1, 2, 3]:
			st.set_uv(uv[idx])
			st.add_vertex(v[idx])
		along += l
	var mi := MeshInstance3D.new()
	mi.name = "stream"
	mi.mesh = st.commit()
	mi.material_override = _water_mat()
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	w.props_root.add_child(mi)
	# stones on the banks
	var rng := RandomNumberGenerator.new()
	rng.seed = 909
	for i in range(0, pts.size(), 3):
		var p: Vector2 = pts[i]
		var side := 1.0 if rng.randf() < 0.5 else -1.0
		var d := (pts[mini(i + 1, pts.size() - 1)] - p).orthogonal().normalized() * side * rng.randf_range(3.0, 4.2)
		if trail_d(p + d) > 4.0:
			w._rock(Vector3(p.x + d.x, 0, p.y + d.y), rng.randf_range(0.3, 0.8), false)
	# bridges: where a trail crosses
	for poly in _paths:
		for i in poly.size() - 1:
			var a: Vector2 = poly[i]
			var b: Vector2 = poly[i + 1]
			if stream_d(a) > 2.0 or stream_d(a) > stream_d(b):
				continue
			if not w.bounds.grow(-4.0).has_point(a):
				continue
			_bridge(w, a, (b - a).normalized())
			break

static func _bridge(w: World, at: Vector2, dir: Vector2) -> void:
	var g := Models.N(null, "bridge")
	var wood := Props.wood()
	var yaw := atan2(dir.x, dir.y)
	var top := maxf(w.ground_h(at.x - dir.x * 4.0, at.y - dir.y * 4.0), w.ground_h(at.x + dir.x * 4.0, at.y + dir.y * 4.0)) + 0.25
	var y0 := w.ground_h(at.x, at.y)
	for k in 9:
		Models.P(g, Geo.box(2.6, 0.12, 0.8), wood, Vector3(0, top - y0, -3.6 + k * 0.9), Vector3(0, 0, randf_range(-2, 2)))
	for sx in [-1.35, 1.35]:
		Models.P(g, Geo.box(0.12, 0.12, 8.4), Props.wood_dark(), Vector3(sx, top - y0 + 0.9, 0))
		for k in 4:
			Models.P(g, Geo.box(0.14, 1.0, 0.14), Props.wood_dark(), Vector3(sx, top - y0 + 0.4, -3.6 + k * 2.4))
	w._place(g, Vector3(at.x, 0, at.y))
	g.rotation.y = yaw
	w.add_deck(at, Vector2(1.3, 4.2), -yaw, top)

static var _water: ShaderMaterial
static func _water_mat() -> ShaderMaterial:
	if _water != null:
		return _water
	var sh := Shader.new()
	sh.code = """shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled, specular_schlick_ggx;
uniform vec3 deep : source_color = vec3(0.03, 0.2, 0.36);
uniform vec3 shallow : source_color = vec3(0.1, 0.44, 0.56);
float h(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float n(vec2 p) { vec2 i = floor(p); vec2 f = fract(p); f = f * f * (3.0 - 2.0 * f);
	return mix(mix(h(i), h(i + vec2(1, 0)), f.x), mix(h(i + vec2(0, 1)), h(i + vec2(1, 1)), f.x), f.y); }
void fragment() {
	vec2 flow = vec2(UV.x * 3.0, UV.y * 0.35 - TIME * 0.9);
	float w = n(flow * 2.0) * 0.6 + n(flow * 5.0 + 3.0) * 0.4;
	float edge = smoothstep(0.0, 0.25, UV.x) * smoothstep(1.0, 0.75, UV.x);
	// sunlit glints riding the current, a little foam where it runs against the banks
	float glint = pow(n(vec2(UV.x * 9.0, UV.y * 1.6 - TIME * 1.3)) * n(vec2(UV.x * 7.0 + 4.0, UV.y * 1.2 - TIME * 0.8)), 3.0);
	float foam = (1.0 - edge) * smoothstep(0.45, 0.8, n(vec2(UV.x * 14.0, UV.y * 1.4 - TIME * 1.1)));
	ALBEDO = mix(shallow, deep, edge * 0.75) + vec3(0.6, 0.8, 0.8) * pow(w, 6.0) * 0.25 + vec3(0.9) * foam * 0.3;
	EMISSION = vec3(1.0, 0.97, 0.85) * glint * 1.6;
	ROUGHNESS = 0.06;
	METALLIC = 0.0;
	SPECULAR = 0.7;
	NORMAL_MAP = vec3(0.5 + (n(flow * 4.0) - 0.5) * 0.5, 0.5 + (n(flow * 4.0 + 7.0) - 0.5) * 0.5, 1.0);
	ALPHA = mix(0.58, 0.86, edge) + foam * 0.2;
}"""
	_water = ShaderMaterial.new()
	_water.shader = sh
	return _water

# ---------------------------------------------------------------- camps' dressing

static func _prop(path: String) -> Node3D:
	return ResCache.inst(path) as Node3D if ResourceLoader.exists(path) else null

## Place a model on the ground, solid by a round footprint.
## (the fungus model stands on a 0.2-high slab of rock: sunk this share of its height, the cap and stalk rise from the moss)
const FUNGUS_SINK := 0.2

static func _fungus(w: World, p: Vector2, yaw: float, s: float, foot := 0.0) -> Node3D:
	var n := _put(w, "res://game/maps/verdant_reach/props/fungus.glb", p, yaw, s, foot)
	if n != null:
		n.position.y -= FUNGUS_SINK * s
	return n

## The giant mushroom cluster (3.3 m as modelled, its mossy rock base the bottom 0.3 m): sunk to the stalks
const SHROOM_SINK := 0.34

static func _shrooms(w: World, p: Vector2, yaw: float, s: float) -> Node3D:
	var n := _put(w, "res://game/maps/verdant_reach/props/mushrooms.glb", p, yaw, s, 1.1 * s)
	if n != null:
		n.position.y -= SHROOM_SINK * s
	return n

static func _put(w: World, path: String, p: Vector2, yaw: float, s: float, foot := 0.0) -> Node3D:
	var m := _prop(path)
	if m == null:
		return null
	var root := Models.N(null, path.get_file().get_basename())
	if foot > 0.0:
		Props.footprint(root, foot)
	root.add_child(m)
	w._place(root, Vector3(p.x, 0, p.y))
	root.rotation.y = yaw
	root.scale = Vector3.ONE * s
	if foot > 0.0:
		w.solid(root)
	return root

static func _lantern_post(w: World, p: Vector2) -> void:
	var n := MapKit.piece(w, PROPS + "lantern_post.glb", Vector2(0.26, 0.18), p, randf() * TAU)
	if n != null:
		var l := OmniLight3D.new()
		l.light_color = Color(1.0, 0.78, 0.45)
		l.light_energy = 1.1
		l.omni_range = 7.0
		l.shadow_enabled = false
		l.position = LANTERN_AT
		n.add_child(l)

static func _ring(c: Vector2, r: float, k: int, n: int, ofs := 0.0) -> Vector2:
	var a := TAU * k / float(n) + ofs
	return c + Vector2(cos(a), sin(a)) * r

static func _dress_camp(w: World, c: Dictionary, rng: RandomNumberGenerator) -> void:
	var at: Vector2 = c["at"]
	var r: float = c["r"]
	match str(c["region"]):
		"elf":
			# a dark elf encampment: tents round a fire, carved totems, a timber lookout over the way in
			for k in 3:
				var tp := _ring(at, r * 0.75, k, 3, rng.randf() * TAU)
				_put(w, PROPS + "tent.glb", tp, MapKit.face(tp, at), 0.9, 1.6)
			for k in 4:
				var q := _ring(at, r * 1.02, k, 4, 0.3)
				_totem(w, q, rng)
			_put(w, "res://game/maps/verdant_reach/props/tower.glb", at + (at - ELF_C).normalized().rotated(0.6) * (r + 3.0), rng.randf() * TAU, 0.55, 1.8)
			MapKit.piece(w, PROPS + "cookfire.glb", Vector2(0.9, 0.9), at + Vector2(1.5, 1.5), 0.0)
			MapKit.piece(w, PROPS + "weapon_rack.glb", Vector2(1.15, 0.45), at + Vector2(-3.5, -1.0), rng.randf() * TAU)
			_light(w, at, Color(0.7, 0.4, 1.0), 2.2, 13.0)
		"mush":
			for k in 7:
				var q := _ring(at, r * rng.randf_range(0.9, 1.25), k, 7, rng.randf())
				if k % 2 == 0:
					_shrooms(w, _ring(at, r * 1.35, k, 7, 0.2), rng.randf() * TAU, rng.randf_range(1.0, 1.35))
				else:
					_fungus(w, q, rng.randf() * TAU, rng.randf_range(1.6, 2.6), 0.5)
			for k in 4:
				_fungus(w, _ring(at, r * rng.randf_range(0.75, 0.95), k, 4, rng.randf()), rng.randf() * TAU, rng.randf_range(1.0, 1.5))
			_light(w, at, Color(0.4, 1.0, 0.75), 1.8, 14.0)
		"frost":
			for k in 6:
				var q := _ring(at, r * rng.randf_range(0.85, 1.15), k, 6, rng.randf())
				_put(w, "res://game/maps/verdant_reach/props/ice_crystals.glb" if k % 2 == 0 else "res://game/maps/verdant_reach/props/ice_rock.glb", q, rng.randf() * TAU, rng.randf_range(1.2, 2.0), 1.0)
			if int(c["tier"]) >= 4:
				for k in 4:
					_put(w, "res://game/maps/verdant_reach/props/frozen_pillar.glb", _ring(at, r * 0.8, k, 4, 0.4), rng.randf() * TAU, 1.3, 0.8)
			if at.distance_to(FROST_C) > FROST_R:
				_frost_ground(w, at, r * 2.0)      # (the hollow's own frost covers the camps inside it)
			_light(w, at, Color(0.55, 0.8, 1.0), 1.2, 15.0)
		"barrow":
			for k in 9:
				w._standing_stone(Vector3(_ring(at, r * 0.95, k, 9).x, 0, _ring(at, r * 0.95, k, 9).y), rng.randf_range(2.2, 3.6))
			# (footprint in the model's metres, scaled with it: the boulder is ~1 m across, so 0.55 x 2.6 = 1.4 m; its old
			# 2.4 made a 6 m wall that swallowed the chest and the barrow's own zombies, Blaine 2026-11-06)
			_put(w, "res://assets/models/rocks/boulder_b.glb", at + Vector2(0, -r * 0.2), 0.0, 2.6, 0.55)
		"ruins":
			for k in 6:
				var a := _ring(at, r * rng.randf_range(0.85, 1.1), k, 6, rng.randf())
				var b := a + (a - at).normalized().rotated(PI * 0.5) * rng.randf_range(3.0, 5.0)
				w._wall(Vector3(a.x, 0, a.y), Vector3(b.x, 0, b.y), rng.randf_range(0.7, 1.8))
			for k in 3:
				var sp := _ring(at, r * 0.6, k, 3, 1.0)
				w._standing_stone(Vector3(sp.x, 0, sp.y), rng.randf_range(2.6, 3.8))
		_:
			for k in 4:
				_put(w, "res://assets/models/props/logs.glb", _ring(at, r * 0.9, k, 4, rng.randf()), rng.randf() * TAU, 1.0, 1.0)

## A carved dark elf totem: a runestone with its runes lit violet.
static func _totem(w: World, p: Vector2, rng: RandomNumberGenerator) -> void:
	var n := _put(w, PROPS + "runestone.glb", p, rng.randf() * TAU, rng.randf_range(0.9, 1.3), 0.6)
	if n == null:
		w._standing_stone(Vector3(p.x, 0, p.y), 2.6)

static func _light(w: World, at: Vector2, col: Color, energy: float, rng_m: float) -> void:
	var l := OmniLight3D.new()
	l.light_color = col
	l.light_energy = energy
	l.omni_range = rng_m
	l.shadow_enabled = false
	l.position = Vector3(at.x, w.height_at(at.x, at.y) + 3.5, at.y)
	w.props_root.add_child(l)

static func _frost_ground(w: World, at: Vector2, size: float) -> void:
	var d := Decal.new()
	d.size = Vector3(size, 10.0, size)
	var tex := _frost_tex()
	d.texture_albedo = tex[0]
	d.texture_emission = tex[1]
	d.emission_energy = 0.3
	d.albedo_mix = 0.38
	d.modulate = Color(0.6, 0.74, 0.9)       # (pale blue rime over the grass, not a sheet of white under the afternoon sun)
	d.position = Vector3(at.x, w.height_at(at.x, at.y), at.y)
	w.props_root.add_child(d)

static var _frost_cache: Array = []

## The rime on the hollow's ground (albedo with alpha, emission): frost-white over noise, faint blue light in a web of
## cellular cracks, a soft round edge. Made once, procedurally (no texture file).
static func _frost_tex() -> Array:
	if not _frost_cache.is_empty():
		return _frost_cache
	var n := 256
	var cells := FastNoiseLite.new()
	cells.noise_type = FastNoiseLite.TYPE_CELLULAR
	cells.cellular_return_type = FastNoiseLite.RETURN_DISTANCE2_SUB
	cells.frequency = 0.022
	cells.seed = 7
	var grain := FastNoiseLite.new()
	grain.frequency = 0.05
	grain.seed = 11
	var alb := Image.create(n, n, false, Image.FORMAT_RGBA8)
	var emi := Image.create(n, n, false, Image.FORMAT_RGB8)
	for y in n:
		for x in n:
			var u := (float(x) / n - 0.5) * 2.0
			var v := (float(y) / n - 0.5) * 2.0
			var rr := sqrt(u * u + v * v)
			var g := grain.get_noise_2d(x, y) * 0.5 + 0.5
			var edge := clampf((1.0 - rr) * 3.2 + (g - 0.5) * 1.4, 0.0, 1.0)
			# DISTANCE2_SUB is -1 on the cells' edges, rising inside them: the cracks are where it's near -1
			var crack := 1.0 - clampf((cells.get_noise_2d(x, y) + 1.0) * 7.0, 0.0, 1.0)
			crack *= smoothstep(0.95, 0.35, rr)
			var fr := 0.78 + 0.18 * g
			alb.set_pixel(x, y, Color(fr * 0.9, fr * 0.95, fr, edge * 0.95))
			emi.set_pixel(x, y, Color(0.35, 0.6, 1.0) * crack * 0.6)
	_frost_cache = [ImageTexture.create_from_image(alb), ImageTexture.create_from_image(emi)]
	return _frost_cache

## The regions between the camps: the mushroom woodland's giant fungi and glowing growths, brambles and fallen
## roots; the elves' palisade stakes and banners near their camps; frost on the hollow.
static func _regions(w: World, rng: RandomNumberGenerator) -> void:
	var fungi := 0
	var tries := 0
	while fungi < 55 and tries < 900:
		tries += 1
		var p := MUSH_C + Vector2(rng.randf_range(-1, 1), rng.randf_range(-1, 1)) * MUSH_R
		if p.distance_to(MUSH_C) > MUSH_R or open_at(p, 1.5) or not w.bounds.grow(-3.0).has_point(p):
			continue
		var big := rng.randf() < 0.45 and not open_at(p, CANOPY * 0.7)
		if big:
			# the giant fungi: the mushroom clusters, 3.5-5.5 m, their crowns kept off the trails and fights
			_shrooms(w, p, rng.randf() * TAU, rng.randf_range(1.1, 1.7))
		else:
			_fungus(w, p, rng.randf() * TAU, rng.randf_range(1.5, 2.8), 0.5)
		if rng.randf() < 0.5:
			var q2 := p + Vector2(rng.randf_range(-2.5, 2.5), rng.randf_range(-2.5, 2.5))
			if not open_at(q2, 1.0):
				_fungus(w, q2, rng.randf() * TAU, rng.randf_range(0.8, 1.4))
		if rng.randf() < 0.25:
			_put(w, "res://game/maps/verdant_reach/props/brambles.glb", p + Vector2(rng.randf_range(-3, 3), rng.randf_range(-3, 3)), rng.randf() * TAU, rng.randf_range(1.0, 1.6), 0.9)
		fungi += 1
	for k in 10:
		var p := MUSH_C + Vector2(rng.randf_range(-1, 1), rng.randf_range(-1, 1)) * MUSH_R * 0.9
		if not open_at(p, 0.5):
			_light(w, p, Color(0.35, 0.95, 0.7) if k % 2 == 0 else Color(0.65, 0.45, 1.0), 1.2, 9.0)
	# frost on the hollow's ground round its boss
	_frost_ground(w, FROST_C, FROST_R * 1.6)
	# the elves' marker stakes along their trails
	for poly in _paths:
		for i in range(2, poly.size() - 2, 5):
			var p: Vector2 = poly[i]
			if p.distance_to(ELF_C) > ELF_R:
				continue
			var side: Vector2 = (poly[i + 1] - p).orthogonal().normalized() * 3.2
			if rng.randf() < 0.5:
				_totem(w, p + side, rng)
