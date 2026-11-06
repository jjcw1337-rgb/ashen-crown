class_name ForestLife
extends Node3D
## The Verdant Reach's life and colour (Blaine, 2026-11-06: "good fun, brighter, more lively and engaging"). Only
## for the look, nothing is solid and nothing is synced: every player's game makes the same dressing from its own
## seeds (never `World.rng`, so the layout, the footprints and the spawns stay exactly as BgForest lays them).
##   dress(w)    called at the end of BgForest.build: the static dressing (drifts of wildflowers by region, little
##               glowing mushrooms, lily pads, the elves' violet banners, the ruins' fallen columns and arches, the
##               crystal shrines) and the node itself, which owns what moves
##   the node    butterflies over the meadows, dragonflies and ripples on the stream, fireflies in the mushroom
##               woods, violet wisps by the elves, ice glints in the frost hollow, golden pollen and shafts of light
##               in the clearings, leaves falling round the camera, the shrines' crystals turning
## Every moving thing is a MultiMesh whose motion is in its shader (no per-frame work on the CPU but the leaves'
## emitter following the camera and the crystals' spin). A dedicated server (`-- --server`) builds none of it.

const SEED := 6262
## How much of everything per graphics preset (World.detail 0..3)
const AMOUNT := [0.45, 0.7, 1.0, 1.25]
const FLOWER_CLUMPS := 5200
const VIS := 48.0
const CHUNK := 34.0

## Each region's flowers: [colour, weight] (the drifts take one colour each), how much they glow
const PALETTES := {
	"forest": [[Color(1.0, 0.86, 0.2), 3.0], [Color(0.98, 0.98, 0.95), 3.0], [Color(0.95, 0.42, 0.62), 2.0], [Color(0.55, 0.5, 1.0), 2.0], [Color(1.0, 0.45, 0.15), 1.0]],
	"mush": [[Color(0.3, 0.85, 1.0), 3.0], [Color(0.7, 0.4, 1.0), 3.0], [Color(0.95, 0.5, 0.95), 1.5], [Color(0.4, 1.0, 0.75), 1.5]],
	"elf": [[Color(0.72, 0.32, 1.0), 3.0], [Color(0.95, 0.35, 0.75), 2.0], [Color(0.45, 0.4, 0.95), 2.0], [Color(0.95, 0.9, 1.0), 1.0]],
	"frost": [[Color(0.9, 0.96, 1.0), 3.0], [Color(0.55, 0.78, 1.0), 3.0], [Color(0.75, 0.7, 1.0), 1.0]],
	"ruins": [[Color(1.0, 0.8, 0.18), 3.0], [Color(0.95, 0.25, 0.15), 2.5], [Color(1.0, 0.95, 0.85), 1.5], [Color(1.0, 0.55, 0.15), 1.5]],
}
const GLOW := {"forest": 0.0, "mush": 0.55, "elf": 0.3, "frost": 0.15, "ruins": 0.0}

var game: Node
var leaves: GPUParticles3D
var spinners: Array = []          # [Node3D, base y, phase]
static var _mats := {}

# ---------------------------------------------------------------- building

static func dress(w: World) -> void:
	# (a dedicated server, `-- --server`, draws nothing; checked from the command line, as Game does before it sets
	# Enemy.server_nopose, so this class needs no static tie to Enemy and its chain)
	if OS.get_cmdline_user_args().has("--server") or Engine.is_editor_hint():
		return
	var k: float = AMOUNT[clampi(World.detail, 0, 3)]
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED
	var node := ForestLife.new()
	node.name = "ForestLife"
	w.add_child(node)
	_flowers(w, rng, k)
	_mushrooms(w, rng, k)
	_lilies(w, rng)
	_banners(w, rng)
	_ruins(w, rng)
	_shrines(w, rng, node)
	node._creatures(w, rng, k)

## Which colour region a point belongs to: BgForest's three, and the ruins (and barrow) round their camps.
static func region(p: Vector2) -> String:
	var r := BgForest.region_at(p)
	if r != "forest":
		return r
	for c in BgForest.CAMPS:
		if (c["region"] == "ruins" or c["region"] == "barrow") and p.distance_to(c["at"]) < float(c["r"]) + 16.0:
			return "ruins"
	return "forest"

static func _camp_core(p: Vector2, k: float) -> bool:
	for c in BgForest.CAMPS:
		if p.distance_to(c["at"]) < float(c["r"]) * k:
			return true
	for s in BgForest.SPAWNS:
		if p.distance_to(s) < 5.5:
			return true
	for q in BgForest.PORTALS:
		if p.distance_to(q) < 5.0:
			return true
	return false

static func _pick_col(pal: Array, rng: RandomNumberGenerator) -> Color:
	var tot := 0.0
	for e in pal:
		tot += float(e[1])
	var r := rng.randf() * tot
	for e in pal:
		r -= float(e[1])
		if r <= 0.0:
			return e[0]
	return pal[0][0]

## Drifts of wildflowers: noise patches over the open ground and the woods' floor, each drift one colour from its
## region's palette; off the trails' trodden middle, the stream and the camps' fighting ground. The flowers are the
## Meshy-painted cut-outs of the grass atlas (daisy, yarrow, dandelion, buttercup: Grass's own sheet), in
## clumps of cards leaning back to the camera; white petals take the drift's colour (FLOWER_SHADER).
static var flower_pts: Array = []      # (every fifth clump: the butterflies keep to the flowers)
static func _flowers(w: World, rng: RandomNumberGenerator, k: float) -> void:
	flower_pts = []
	var nz := FastNoiseLite.new()
	nz.seed = SEED + 1
	nz.frequency = 0.045
	var cz := FastNoiseLite.new()
	cz.seed = SEED + 2
	cz.frequency = 0.03
	var kinds := [[], []]       # white (daisy, yarrow, dandelion: tinted), buttercup
	var want := int(FLOWER_CLUMPS * k)
	var tries := 0
	var area := w.bounds.grow(-2.0)
	var placed := 0
	while placed < want and tries < want * 14:
		tries += 1
		var p := Vector2(rng.randf_range(area.position.x, area.end.x), rng.randf_range(area.position.y, area.end.y))
		var n := nz.get_noise_2dv(p)
		if n < 0.08:
			continue
		var td := BgForest.trail_d(p)
		if td < 2.2 or BgForest.stream_d(p) < 3.6 or _camp_core(p, 0.55):
			continue
		if w.grass_ground(p.x, p.y) < 0.3:
			continue
		var reg := region(p)
		var pal: Array = PALETTES[reg]
		# one colour per drift: the drift's colour noise picks from the palette deterministically
		var cr := RandomNumberGenerator.new()
		cr.seed = int(floor((cz.get_noise_2dv(p) + 1.0) * 3.5)) * 97 + reg.hash()
		var col := _pick_col(pal, cr)
		var kind := 0
		if col.r > 0.85 and col.g > 0.7 and col.b < 0.4:
			kind = 1                 # (yellow: the painted buttercups, as they are)
			col = Color.WHITE
		col = col.lerp(Color.WHITE, rng.randf() * 0.12)
		var s := rng.randf_range(1.15, 1.7) * (0.85 + n * 0.8)
		var t := Transform3D(Basis().scaled(Vector3.ONE * s), Vector3(p.x, w.height_at(p.x, p.y) - 0.03, p.y))
		kinds[kind].append([t, Color(col.r, col.g, col.b, float(GLOW[reg]))])
		if placed % 5 == 0:
			flower_pts.append(p)
		placed += 1
	var tex := ResCache.get_res(Grass.ATLAS) as Texture2D if ResourceLoader.exists(Grass.ATLAS) else null
	if tex == null:
		return
	var mat := _flower_mat(tex)
	for i in 2:
		_mm(w.props_root, _card_clump(i), kinds[i], mat, CHUNK, VIS, "flowers")

## The grass atlas's flower cells (atlas.json): daisy 19, buttercup 20, yarrow 22, dandelion 23 (the heather, 21,
## reads as dark sticks from the camera)
const CARD_CELLS := [[19, 19, 22, 19, 22, 23, 19, 19], [20, 20, 20, 20, 20, 20, 20]]
const CARD_LEAN := 24.0

## A clump of flower cards: each a quad of one atlas cell (128 x 512 px, so a quarter as wide as tall), its root in
## the ground, leaning back toward the fixed camera, jittered and of different heights. UV2.y = height (sway).
static func _card_clump(kind: int) -> ArrayMesh:
	var key := "cards%d" % kind
	if _cache.has(key):
		return _cache[key]
	var rng := RandomNumberGenerator.new()
	rng.seed = 21 + kind
	var st := _st()
	var cells: Array = CARD_CELLS[kind]
	for c in cells:
		var col := int(c) % 16
		var row := int(c) / 16
		var u0 := col / 16.0
		var u1 := (col + 1) / 16.0
		var v0 := row * 0.5
		var v1 := (row + 1) * 0.5
		var h := rng.randf_range(0.42, 0.72)
		var wd := h * 0.3
		var b := Vector3(rng.randf_range(-0.34, 0.34), -0.04, rng.randf_range(-0.28, 0.28))
		var yaw := rng.randf_range(-0.35, 0.35)
		var lean := deg_to_rad(CARD_LEAN + rng.randf_range(-8.0, 8.0))
		var side := Vector3(cos(yaw), 0, -sin(yaw)) * wd * 0.5
		var up := Basis(Vector3.UP, yaw) * Vector3(0, cos(lean), -sin(lean)) * h
		var nrm := Basis(Vector3.UP, yaw) * Vector3(0, sin(lean), cos(lean))
		var q := [[b - side, Vector2(u0, v1), 0.0], [b + side, Vector2(u1, v1), 0.0], [b + side + up, Vector2(u1, v0), 1.0],
			[b - side, Vector2(u0, v1), 0.0], [b + side + up, Vector2(u1, v0), 1.0], [b - side + up, Vector2(u0, v0), 1.0]]
		for v in q:
			st.set_normal(nrm)
			st.set_uv(v[1])
			st.set_uv2(Vector2(0, v[2]))
			st.add_vertex(v[0])
	return _commit(key, st, 0.15)

## Mushrooms: little clusters of the woodland's own glowing Meshy mushrooms through the mushroom woods and round the
## shrines, the Meshy fungus small under the oaks elsewhere. Their own materials, a soft glow on the blue ones.
static func _mushrooms(w: World, rng: RandomNumberGenerator, k: float) -> void:
	var blue := []
	var brown := []
	var want := int(420 * k)
	var tries := 0
	while blue.size() + brown.size() < want and tries < want * 12:
		tries += 1
		var inmush := rng.randf() < 0.65
		var p: Vector2
		if inmush:
			p = BgForest.MUSH_C + Vector2(rng.randf_range(-1, 1), rng.randf_range(-1, 1)) * BgForest.MUSH_R
			if p.distance_to(BgForest.MUSH_C) > BgForest.MUSH_R:
				continue
		else:
			if w.tree_pts.is_empty():
				continue
			var tp: Vector2 = w.tree_pts[rng.randi() % w.tree_pts.size()]
			p = tp + Vector2(rng.randf_range(-3.5, 3.5), rng.randf_range(-3.5, 3.5))
		if not w.bounds.grow(-2.0).has_point(p) or BgForest.trail_d(p) < 2.8 or BgForest.stream_d(p) < 3.5 or _camp_core(p, 0.75):
			continue
		var y := w.height_at(p.x, p.y)
		if inmush:
			var s := rng.randf_range(0.1, 0.19)
			blue.append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * s), Vector3(p.x, y - BgForest.SHROOM_SINK * s, p.y)))
		else:
			var s := rng.randf_range(0.28, 0.5)
			brown.append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * s), Vector3(p.x, y - BgForest.FUNGUS_SINK * s, p.y)))
	_meshy_mm(w, "res://assets/models/bg/mushrooms.glb", blue, 0.0)
	_meshy_mm(w, "res://assets/models/bg/fungus.glb", brown, 0.0)

## A Meshy model's first mesh instanced over `xforms` (World.mm_chunked, no shadows), its material given a glow.
static func _meshy_mm(w: World, path: String, xforms: Array, glow: float) -> void:
	if xforms.is_empty():
		return
	var mesh := _glb_mesh(path)
	if mesh == null:
		return
	var mat: Material = null
	if glow > 0.0:
		mat = _glow_mat(path, mesh, glow)
	for mmi in w.mm_chunked(mesh, xforms, false, 32.0, VIS - 14.0, mat):
		(mmi as Node).set_meta("keep_material", true)

static func _glb_mesh(path: String) -> Mesh:
	if _cache.has(path):
		return _cache[path]
	if not ResourceLoader.exists(path):
		return null
	var n := ResCache.inst(path)
	if n == null:
		return null
	var found := n.find_children("*", "MeshInstance3D", true, false)
	var m: Mesh = (found[0] as MeshInstance3D).mesh if not found.is_empty() else null
	n.free()
	_cache[path] = m
	return m

## The model's own material with its painting lit from within (the glowing mushrooms of the woodland's heart).
static func _glow_mat(key: String, mesh: Mesh, glow: float) -> Material:
	var k := key + ":glow"
	if _mats.has(k):
		return _mats[k]
	var src := mesh.surface_get_material(0) if mesh.get_surface_count() > 0 else null
	if not (src is StandardMaterial3D):
		return null
	var m := (src as StandardMaterial3D).duplicate() as StandardMaterial3D
	m.emission_enabled = true
	m.emission = Color(0.4, 0.8, 1.0)
	m.emission_texture = (src as StandardMaterial3D).albedo_texture
	m.emission_energy_multiplier = glow
	_mats[k] = m
	return m

## The stream's surface height at a point on its course (as BgForest._stream lays the ribbon).
static func water_y(w: World, p: Vector2) -> float:
	return w.ground_h(p.x, p.y) + 0.55

## Lily pads along the stream's quiet edges, some in flower, bobbing on the current.
static func _lilies(w: World, rng: RandomNumberGenerator) -> void:
	var pts := w._spline(BgForest.STREAM, 8)
	var pads := [[], []]
	for i in pts.size() - 1:
		var a: Vector2 = pts[i]
		var b: Vector2 = pts[i + 1]
		if not w.bounds.grow(-3.0).has_point(a):
			continue
		var dir := (b - a).normalized()
		var nrm := dir.orthogonal()
		var n := rng.randi_range(0, 3)
		for j in n:
			var t := rng.randf()
			var side := 1.0 if rng.randf() < 0.5 else -1.0
			var q := a.lerp(b, t) + nrm * side * rng.randf_range(1.0, 2.2)
			if BgForest.trail_d(q) < 3.0:
				continue      # (not under the bridges)
			var y := lerpf(water_y(w, a), water_y(w, b), t) + 0.02
			var s := rng.randf_range(0.7, 1.3)
			var flower := rng.randf() < 0.25
			var col: Color = [Color(1.0, 0.6, 0.8), Color(1.0, 0.95, 0.95), Color(1.0, 0.85, 0.3)][rng.randi() % 3]
			pads[1 if flower else 0].append([Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * s), Vector3(q.x, y, q.y)), Color(col.r, col.g, col.b, 0.0)])
	_mm(w.props_root, _lily_mesh(false), pads[0], _dress_mat("lily", 0.0, 1.0), CHUNK, VIS, "lilies")
	_mm(w.props_root, _lily_mesh(true), pads[1], _dress_mat("lily", 0.0, 1.0), CHUNK, VIS, "lilies")

## The dark elves' banners: the waypoint's Meshy banner on its stone foot, its red cloth dyed violet and its sigil lit
## (BANNER_SHADER), beside the totems round their three camps (on the totems' ring, never in the fight).
const BANNER_GLB := "res://assets/models/waypoint/banner.glb"
static func _banners(w: World, rng: RandomNumberGenerator) -> void:
	for c in BgForest.CAMPS:
		if c["region"] != "elf":
			continue
		var at: Vector2 = c["at"]
		var r: float = c["r"]
		for k in 4:
			var a := TAU * k / 4.0 + 0.3 + 0.36
			var p := at + Vector2(cos(a), sin(a)) * r * 1.12
			if BgForest.trail_d(p) < 3.0:
				continue
			# (turned to the camera, which always looks north: the cloth reads face on)
			var n := _glb(w, BANNER_GLB, p, rng.randf_range(-0.3, 0.3), 0.82, -0.05)
			if n != null:
				_dye_banner(n)

static func _dye_banner(n: Node) -> void:
	for mi in n.find_children("*", "MeshInstance3D", true, false):
		var m: Mesh = (mi as MeshInstance3D).mesh
		for i in m.get_surface_count():
			var src := m.surface_get_material(i)
			if src is StandardMaterial3D:
				SurfaceMaterials.assign(mi as MeshInstance3D, i, _banner_mat(src as StandardMaterial3D))

## The old ruins: fallen column drums lying in the grass, broken columns and a mossy arch at the treeline round
## each ruined camp, all deep enough off the trails that nobody fights through them.
static func _ruins(w: World, rng: RandomNumberGenerator) -> void:
	for c in BgForest.CAMPS:
		if c["region"] != "ruins":
			continue
		var at: Vector2 = c["at"]
		var r: float = c["r"]
		var arch := false
		for k in 14:
			var a := rng.randf() * TAU
			var p := at + Vector2(cos(a), sin(a)) * r * rng.randf_range(1.15, 1.7)
			if BgForest.open_at(p, 1.5) or not w.bounds.grow(-4.0).has_point(p):
				continue
			var pick := rng.randi_range(0, 2)
			if not arch and not BgForest.open_at(p, 3.5):
				_glb(w, "res://assets/models/roman/arch.glb", p, ForestCamp.face(p, at) + PI * 0.5, 3.4, 0.0)
				arch = true
			elif pick == 0:
				_glb(w, "res://assets/models/roman/broken.glb", p, rng.randf() * TAU, rng.randf_range(2.2, 3.2), 0.0)
			elif pick == 1:
				var n := _glb(w, "res://assets/models/roman/drum.glb", p, rng.randf() * TAU, rng.randf_range(0.9, 1.2), -0.15)
				if n != null:
					n.rotation.x = PI * 0.5      # (a drum on its side, half in the grass)
			else:
				_glb(w, "res://assets/models/roman/column.glb", p, rng.randf() * TAU, rng.randf_range(2.6, 3.6), 0.0)

static func _glb(w: World, path: String, p: Vector2, yaw: float, s: float, dy: float) -> Node3D:
	if not ResourceLoader.exists(path):
		return null
	var m := ResCache.inst(path) as Node3D
	if m == null:
		return null
	var root := Node3D.new()
	root.name = path.get_file().get_basename()
	root.add_child(m)
	w.props_root.add_child(root)
	root.position = Vector3(p.x, w.height_at(p.x, p.y) + dy, p.y)
	root.rotation.y = yaw
	root.scale = Vector3.ONE * s
	return root

## A few crystal shrines beside the trails: the waypoint's Meshy rune crystal hanging and turning over a ring of the
## Meshy boulders and a fairy ring of the glowing mushrooms, its cold light on the grass. Places found from the layout:
## just off a trail (on its grass, clear of the dirt), out from under the oaks' crowns, away from the camps and the
## stream, spread out across the map. `shrines` keeps them (the screenshots go there).
const SHRINE_LIGHT := Color(0.45, 0.8, 1.0)
const CRYSTAL_GLB := "res://assets/models/waypoint/crystal_rune.glb"
static var shrines: Array = []

static func shrine_spots(w: World) -> Array:
	var out := []
	var cands := []
	var trees := {}
	for t: Vector2 in w.tree_pts:
		trees[Vector2i(floori(t.x / 8.0), floori(t.y / 8.0))] = true
	for j in range(-48, 49):
		for i in range(-48, 49):
			var p := Vector2(i * 2.0, j * 2.0)
			var td := BgForest.trail_d(p)
			if td < 6.2 or td > 7.6 or BgForest.stream_d(p) < 9.0:
				continue
			var near := false
			for c in BgForest.CAMPS:
				if p.distance_to(c["at"]) < float(c["r"]) + 8.0:
					near = true
			for q in BgForest.SPAWNS + BgForest.PORTALS:
				if p.distance_to(q) < 16.0:
					near = true
			var cell := Vector2i(floori(p.x / 8.0), floori(p.y / 8.0))
			for dj in range(-1, 2):
				for di in range(-1, 2):
					if trees.has(cell + Vector2i(di, dj)):
						for t: Vector2 in w.tree_pts:
							if t.distance_to(p) < 7.0:
								near = true
								break
			if not near:
				cands.append(p)
	var r := RandomNumberGenerator.new()
	r.seed = SEED + 7
	for tries in 600:
		if out.size() >= 5 or cands.is_empty():
			break
		var p: Vector2 = cands[r.randi() % cands.size()]
		if out.any(func(q: Vector2) -> bool: return q.distance_to(p) < 45.0):
			continue
		out.append(p)
	return out

static func _shrines(w: World, rng: RandomNumberGenerator, node: ForestLife) -> void:
	var stones := []
	var ring := []
	var rock := Props.boulder(1)
	shrines = shrine_spots(w)
	for p: Vector2 in shrines:
		var y := w.height_at(p.x, p.y)
		for k in 6:
			var a := TAU * k / 6.0 + rng.randf() * 0.3
			var q := p + Vector2(cos(a), sin(a)) * 1.7
			var s := rng.randf_range(0.32, 0.48)
			stones.append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(s, s * 1.4, s)), Vector3(q.x, w.height_at(q.x, q.y) - 0.04, q.y)))
		for k in 9:
			var a := TAU * k / 9.0 + rng.randf() * 0.25
			var q := p + Vector2(cos(a), sin(a)) * rng.randf_range(2.6, 3.0)
			var s := rng.randf_range(0.11, 0.16)
			ring.append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * s), Vector3(q.x, w.height_at(q.x, q.y) - BgForest.SHROOM_SINK * s, q.y)))
		var cr := _glb(w, CRYSTAL_GLB, p, rng.randf() * TAU, 0.6, 2.7)
		if cr != null:
			node.spinners.append([cr, cr.position.y, rng.randf() * TAU])
			for mi in cr.find_children("*", "GeometryInstance3D", true, false):
				(mi as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				if mi is MeshInstance3D:
					_glow_crystal(mi as MeshInstance3D)
		var l := OmniLight3D.new()
		l.light_color = SHRINE_LIGHT
		l.light_energy = 1.8
		l.omni_range = 7.5
		l.shadow_enabled = false
		l.position = Vector3(p.x, y + 2.2, p.y)
		w.props_root.add_child(l)
	if not rock.is_empty():
		w.mm_chunked(rock[0], Props.seat(stones, rock[3], false), true, 32.0, 90.0, rock[1])
	_meshy_mm(w, "res://assets/models/bg/mushrooms.glb", ring, 0.22)

## The crystal's own painting, its runes and cracks lit (the waypoint's crystal glows the same way).
static func _glow_crystal(mi: MeshInstance3D) -> void:
	var m := mi.mesh
	for i in m.get_surface_count():
		var src := m.surface_get_material(i)
		if not (src is StandardMaterial3D):
			continue
		var k := "crystal:%d" % src.get_instance_id()
		if not _mats.has(k):
			var g := (src as StandardMaterial3D).duplicate() as StandardMaterial3D
			g.emission_enabled = true
			g.emission = Color(0.3, 0.65, 1.0)
			g.emission_texture = (src as StandardMaterial3D).albedo_texture
			g.emission_energy_multiplier = 1.3
			_mats[k] = g
		SurfaceMaterials.assign(mi, i, _mats[k])

# ---------------------------------------------------------------- what moves

func _ready() -> void:
	game = get_parent().get_parent() if get_parent() != null else null
	if World.detail >= 1:
		_leaves()

## Towards the sun (the game's one shadowed light), for the shafts to lean along.
func _sun_up() -> Vector3:
	var sun: DirectionalLight3D = null
	if game != null and "sun" in game:
		sun = game.get("sun") as DirectionalLight3D
	if sun == null:
		return Vector3(0.45, 0.8, 0.4).normalized()
	return sun.global_transform.basis.z.normalized()

func _process(delta: float) -> void:
	var t := Time.get_ticks_msec() * 0.001
	for s in spinners:
		var n: Node3D = s[0]
		if is_instance_valid(n):
			n.rotation.y += delta * 0.5
			n.position.y = float(s[1]) + sin(t * 1.1 + float(s[2])) * 0.18
	if leaves != null:
		var cam := get_viewport().get_camera_3d()
		if cam != null:
			var o := cam.global_position
			var f := -cam.global_transform.basis.z
			var at := o + f * (absf(o.y - 2.0) / maxf(0.2, -f.y))
			leaves.global_position = Vector3(at.x, at.y + 9.0, at.z)

func _creatures(w: World, rng: RandomNumberGenerator, k: float) -> void:
	var fl := []        # butterflies
	var dr := []        # dragonflies
	var ff := []        # fireflies (mushroom woods)
	var wi := []        # violet wisps (elves)
	var gl := []        # ice glints (frost)
	var po := []        # golden pollen (clearings)
	var sh := []        # light shafts
	var area := w.bounds.grow(-3.0)
	var bcols := [Color(1.0, 0.55, 0.1), Color(0.3, 0.65, 1.0), Color(1.0, 0.92, 0.3), Color(0.98, 0.98, 0.98), Color(0.95, 0.4, 0.8)]
	for i in int(minf(flower_pts.size(), 700.0 * k)):
		var p: Vector2 = flower_pts[rng.randi() % flower_pts.size()]
		if BgForest.stream_d(p) > 3.0:
			var reg := region(p)
			var col: Color = bcols[rng.randi() % bcols.size()]
			if reg == "mush":
				col = [Color(0.3, 0.85, 1.0), Color(0.75, 0.45, 1.0)][rng.randi() % 2]
			elif reg == "frost":
				col = Color(0.85, 0.93, 1.0)
			fl.append([Transform3D(Basis(), Vector3(p.x, w.height_at(p.x, p.y), p.y)), Color(col.r, col.g, col.b, rng.randf())])
	var pts := w._spline(BgForest.STREAM, 8)
	for i in range(0, pts.size(), 2):
		var p: Vector2 = pts[i]
		if not area.has_point(p) or rng.randf() > 0.55 * k:
			continue
		var col: Color = [Color(0.2, 0.85, 0.95), Color(0.35, 0.95, 0.45), Color(0.9, 0.3, 0.25)][rng.randi() % 3]
		dr.append([Transform3D(Basis(), Vector3(p.x, water_y(w, p), p.y)), Color(col.r, col.g, col.b, rng.randf())])
	for i in int(900 * k):
		var p := Vector2(rng.randf_range(area.position.x, area.end.x), rng.randf_range(area.position.y, area.end.y))
		var reg := region(p)
		var y := w.height_at(p.x, p.y)
		var c := Color(0, 0, 0, rng.randf())
		match reg:
			"mush":
				var col := Color(0.35, 1.0, 0.85) if rng.randf() < 0.55 else Color(0.75, 0.5, 1.0)
				ff.append([Transform3D(Basis(), Vector3(p.x, y, p.y)), Color(col.r, col.g, col.b, c.a)])
			"elf":
				if rng.randf() < 0.5:
					wi.append([Transform3D(Basis(), Vector3(p.x, y, p.y)), Color(0.75, 0.42, 1.0, c.a)])
			"frost":
				gl.append([Transform3D(Basis(), Vector3(p.x, y, p.y)), Color(0.8, 0.92, 1.0, c.a)])
			_:
				if BgForest.open_at(p, 3.0) and rng.randf() < 0.55:
					po.append([Transform3D(Basis(), Vector3(p.x, y, p.y)), Color(1.0, 0.85, 0.45, c.a)])
	# shafts of light on the open ground at the trees' edge, leaning toward the sun
	if World.detail >= 1:
		for i in int(3200 * k):
			var p := Vector2(rng.randf_range(area.position.x, area.end.x), rng.randf_range(area.position.y, area.end.y))
			if not BgForest.open_at(p, 0.0) or BgForest.open_at(p, -2.5):
				continue      # (the open ground's edge, where the light falls past the trees)
			if rng.randf() > 0.4:
				continue
			var ln := rng.randf_range(9.0, 14.0)
			var wd := rng.randf_range(1.6, 3.4)
			sh.append([Transform3D(Basis(Vector3(wd, 0, 0), Vector3(0, ln, 0), Vector3(0, 0, 1)), Vector3(p.x, w.height_at(p.x, p.y), p.y)), Color(1.0, 0.9, 0.62, rng.randf())])
	_mm(w.props_root, _wing_mesh(false), fl, _flyer_mat("butterfly", 0.5, 1.8, 10.0, 0.75, 0.0), CHUNK, 55.0, "butterflies", 6.0)
	_mm(w.props_root, _wing_mesh(true), dr, _flyer_mat("dragonfly", 1.6, 3.2, 38.0, 0.75, 1.0), CHUNK, 55.0, "dragonflies", 6.0)
	_mm(w.props_root, _quad(), ff, _mote_mat("firefly", 0.16, 2.2, 1.4, 1.0, 4.5), CHUNK, 60.0, "fireflies", 5.0)
	_mm(w.props_root, _quad(), wi, _mote_mat("wisp", 0.26, 1.6, 1.6, 0.4, 1.6), CHUNK, 60.0, "wisps", 5.0)
	_mm(w.props_root, _quad(), gl, _mote_mat("glint", 0.07, 1.2, 0.9, 1.0, 3.0), CHUNK, 60.0, "glints", 5.0)
	_mm(w.props_root, _quad(), po, _mote_mat("pollen", 0.06, 2.0, 1.8, 0.2, 1.4), CHUNK, 60.0, "pollen", 5.0)
	if not sh.is_empty():
		_shaft_mat().set_shader_parameter("sun_up", _sun_up())
		_mm(w.props_root, _quad(), sh, _shaft_mat(), CHUNK, 70.0, "shafts", 16.0)
	# the stream's ripples: rings spreading now and then where fish rise
	var rp := []
	for i in range(0, pts.size()):
		var p: Vector2 = pts[i]
		if not area.has_point(p) or rng.randf() > 0.7:
			continue
		var q := p + Vector2(rng.randf_range(-1.4, 1.4), rng.randf_range(-1.4, 1.4))
		rp.append([Transform3D(Basis().scaled(Vector3.ONE * rng.randf_range(1.0, 1.8)), Vector3(q.x, water_y(w, p) + 0.03, q.y)), Color(1, 1, 1, rng.randf())])
	_mm(w.props_root, _flat_quad(), rp, _ripple_mat(), CHUNK, 60.0, "ripples", 1.0)

## Leaves drifting down round the camera, tumbling, green and gold.
func _leaves() -> void:
	var p := GPUParticles3D.new()
	p.name = "leaves"
	p.amount = 46 if World.detail >= 2 else 24
	p.lifetime = 9.0
	p.preprocess = 9.0
	p.local_coords = false
	p.visibility_aabb = AABB(Vector3(-30, -20, -30), Vector3(60, 30, 60))
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(20, 2, 16)
	pm.direction = Vector3(0.3, -1, 0.2)
	pm.spread = 25.0
	pm.initial_velocity_min = 0.4
	pm.initial_velocity_max = 0.9
	pm.gravity = Vector3(0.35, -0.55, 0.18)
	pm.damping_min = 0.1
	pm.damping_max = 0.3
	pm.scale_min = 0.7
	pm.scale_max = 1.3
	var ramp := Gradient.new()
	ramp.set_color(0, Color(0.55, 0.75, 0.2))
	ramp.set_color(1, Color(0.95, 0.62, 0.15))
	ramp.add_point(0.5, Color(0.9, 0.82, 0.25))
	var rt := GradientTexture1D.new()
	rt.gradient = ramp
	pm.color_initial_ramp = rt
	var fade := Gradient.new()
	fade.set_color(0, Color(1, 1, 1, 0))
	fade.set_color(1, Color(1, 1, 1, 0))
	fade.add_point(0.12, Color(1, 1, 1, 1))
	fade.add_point(0.85, Color(1, 1, 1, 1))
	var ft := GradientTexture1D.new()
	ft.gradient = fade
	pm.color_ramp = ft
	p.process_material = pm
	var q := QuadMesh.new()
	q.size = Vector2(0.2, 0.14)
	q.material = _leaf_mat()
	p.draw_pass_1 = q
	add_child(p)
	leaves = p

# ---------------------------------------------------------------- multimesh

## The instances [[Transform3D, Color custom]] in chunk-metre cells, one MultiMeshInstance3D each (culled per cell),
## no shadows; `reach` grows each cell's box for what the shader moves away from its instance.
static func _mm(parent: Node3D, mesh: Mesh, items: Array, mat: Material, chunk: float, vis_end: float, nm: String, reach := 0.0) -> void:
	if items.is_empty() or mesh == null:
		return
	var cells := {}
	for it in items:
		var o: Vector3 = (it[0] as Transform3D).origin
		var key := Vector2i(floori(o.x / chunk), floori(o.z / chunk))
		if not cells.has(key):
			cells[key] = []
		(cells[key] as Array).append(it)
	for key in cells:
		var arr: Array = cells[key]
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_custom_data = true
		mm.mesh = mesh
		mm.instance_count = arr.size()
		for i in arr.size():
			mm.set_instance_transform(i, arr[i][0])
			mm.set_instance_custom_data(i, arr[i][1])
		var mmi := MultiMeshInstance3D.new()
		mmi.name = nm
		mmi.multimesh = mm
		mmi.material_override = mat
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		if reach > 0.0:
			mmi.extra_cull_margin = reach
		if vis_end > 0.0:
			mmi.visibility_range_end = vis_end
			mmi.visibility_range_end_margin = 6.0
		mmi.set_meta("keep_material", true)
		parent.add_child(mmi)

# ---------------------------------------------------------------- meshes
# Dressing meshes carry: COLOR.rgb the part's own colour, COLOR.a how far the instance's tint replaces it; UV2.x how
# much the tinted part glows (times the instance's glow), UV2.y how much it sways (0 at the root).

static var _cache := {}

static func _st() -> SurfaceTool:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	return st

static func _v(st: SurfaceTool, p: Vector3, n: Vector3, col: Color, glow: float, sway: float) -> void:
	st.set_color(col)
	st.set_normal(n)
	st.set_uv2(Vector2(glow, sway))
	st.add_vertex(p)

static func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, col: Color, glow: float, sa: float, sb: float, sc: float) -> void:
	var n := (b - a).cross(c - a).normalized()
	if n.y < 0.0:
		n = -n
	_v(st, a, n, col, glow, sa)
	_v(st, b, n, col, glow, sb)
	_v(st, c, n, col, glow, sc)

static func _commit(key: String, st: SurfaceTool, aabb_grow := 0.0) -> ArrayMesh:
	var m := st.commit()
	if aabb_grow > 0.0:
		m.custom_aabb = m.get_aabb().grow(aabb_grow)
	_cache[key] = m
	return m

const PETAL := Color(1, 1, 1, 1.0)
const HEART := Color(1.0, 0.78, 0.15, 0.0)

## A lily pad (a disc with its notch), with or without a flower.
static func _lily_mesh(flower: bool) -> ArrayMesh:
	var key := "lily%d" % int(flower)
	if _cache.has(key):
		return _cache[key]
	var st := _st()
	var pad := Color(0.2, 0.52, 0.16, 0.0)
	var rim := Color(0.32, 0.62, 0.2, 0.0)
	var r := 0.34
	var n := 14
	for k in n:
		var a0 := 0.35 + (TAU - 0.5) * k / n
		var a1 := 0.35 + (TAU - 0.5) * (k + 1) / n
		_tri(st, Vector3.ZERO, Vector3(cos(a0), 0, sin(a0)) * r, Vector3(cos(a1), 0, sin(a1)) * r, pad if k % 2 == 0 else rim, 0.0, 0, 0, 0)
	if flower:
		var rng := RandomNumberGenerator.new()
		rng.seed = 15
		var c := Vector3(0.05, 0.03, -0.04)
		for k in 8:
			var a := TAU * k / 8.0
			var o := Vector3(cos(a), 0, sin(a))
			var t := o.cross(Vector3.UP)
			_tri(st, c + t * 0.025, c - t * 0.025, c + o * 0.1 + Vector3(0, 0.07, 0), PETAL, 0.4, 0, 0, 0)
		_tri(st, c + Vector3(-0.02, 0.03, 0), c + Vector3(0.02, 0.03, 0), c + Vector3(0, 0.03, 0.025), HEART, 0.0, 0, 0, 0)
	return _commit(key, st)

## A butterfly's (or a dragonfly's) wings: quads hinged on the body's axis (z forward), UV over each wing; the
## shader beats them and flies the whole along its path.
static func _wing_mesh(dragon: bool) -> ArrayMesh:
	var key := "wings%d" % int(dragon)
	if _cache.has(key):
		return _cache[key]
	var st := _st()
	var span := 0.17 if dragon else 0.17
	var front := 0.035 if dragon else 0.13
	var back := 0.035 if dragon else 0.1
	var pairs := [0.03, -0.035] if dragon else [0.0]
	for zc in pairs:
		for sx in [-1.0, 1.0]:
			var a := Vector3(0, 0, zc - back)
			var b := Vector3(0, 0, zc + front)
			var c := Vector3(sx * span, 0, zc + front)
			var d := Vector3(sx * span, 0, zc - back)
			for v in [[a, Vector2(0, 0)], [b, Vector2(0, 1)], [c, Vector2(1, 1)], [a, Vector2(0, 0)], [c, Vector2(1, 1)], [d, Vector2(1, 0)]]:
				st.set_normal(Vector3.UP)
				st.set_uv(v[1])
				st.set_color(Color(1, 1, 1, 1))
				st.add_vertex(v[0])
	# the body: a thin strip along z (UV.x < 0 marks it)
	var bl := 0.14 if dragon else 0.07
	var bw := 0.012
	var q := [Vector3(-bw, 0.004, -bl), Vector3(-bw, 0.004, bl * 0.4), Vector3(bw, 0.004, bl * 0.4), Vector3(bw, 0.004, -bl)]
	for idx in [0, 1, 2, 0, 2, 3]:
		st.set_normal(Vector3.UP)
		st.set_uv(Vector2(-1, 0))
		st.set_color(Color(1, 1, 1, 1))
		st.add_vertex(q[idx])
	return _commit(key, st, 6.0)

static func _quad() -> ArrayMesh:
	if _cache.has("quad"):
		return _cache["quad"]
	var st := _st()
	var q := [Vector3(-0.5, -0.5, 0), Vector3(-0.5, 0.5, 0), Vector3(0.5, 0.5, 0), Vector3(0.5, -0.5, 0)]
	var uv := [Vector2(0, 1), Vector2(0, 0), Vector2(1, 0), Vector2(1, 1)]
	for idx in [0, 1, 2, 0, 2, 3]:
		st.set_normal(Vector3.BACK)
		st.set_uv(uv[idx])
		st.add_vertex(q[idx])
	return _commit("quad", st, 4.0)

static func _flat_quad() -> ArrayMesh:
	if _cache.has("flat"):
		return _cache["flat"]
	var st := _st()
	var q := [Vector3(-0.5, 0, -0.5), Vector3(-0.5, 0, 0.5), Vector3(0.5, 0, 0.5), Vector3(0.5, 0, -0.5)]
	var uv := [Vector2(0, 0), Vector2(0, 1), Vector2(1, 1), Vector2(1, 0)]
	for idx in [0, 1, 2, 0, 2, 3]:
		st.set_normal(Vector3.UP)
		st.set_uv(uv[idx])
		st.add_vertex(q[idx])
	return _commit("flat", st)

# ---------------------------------------------------------------- materials

const DRESS_SHADER := """shader_type spatial;
render_mode cull_disabled, specular_disabled;
uniform float sway = 1.0;
uniform float bob = 0.0;
varying vec3 tint;
varying float glow;
varying float tinted;
void vertex() {
	tint = INSTANCE_CUSTOM.rgb;
	glow = INSTANCE_CUSTOM.a * UV2.x;
	tinted = COLOR.a;
	vec3 o = MODEL_MATRIX[3].xyz;
	float t = TIME * 1.7 + o.x * 0.21 + o.z * 0.17;
	float h = UV2.y;
	VERTEX.x += (sin(t) * 0.05 + sin(t * 2.3) * 0.015) * h * sway;
	VERTEX.z += cos(t * 0.8) * 0.035 * h * sway;
	VERTEX.y += sin(TIME * 0.9 + o.x * 0.7 + o.z) * 0.02 * bob;
}
void fragment() {
	vec3 c = mix(COLOR.rgb, tint * COLOR.rgb, tinted);
	ALBEDO = c;
	ROUGHNESS = 0.75;
	BACKLIGHT = c * 0.35 * tinted;
	EMISSION = tint * glow * tinted * 1.4;
}
"""

static func _dress_mat(key: String, sway: float, bob: float) -> ShaderMaterial:
	if _mats.has(key):
		return _mats[key]
	var m := ShaderMaterial.new()
	m.shader = _shader("dress", DRESS_SHADER)
	m.set_shader_parameter("sway", sway)
	m.set_shader_parameter("bob", bob)
	_mats[key] = m
	return m

const FLOWER_SHADER := """shader_type spatial;
render_mode cull_disabled, specular_disabled;
uniform sampler2D atlas : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
varying vec4 tint;
void vertex() {
	tint = INSTANCE_CUSTOM;
	vec3 o = MODEL_MATRIX[3].xyz;
	float t = TIME * 1.6 + o.x * 0.21 + o.z * 0.17;
	float h = UV2.y;
	VERTEX.x += (sin(t) * 0.05 + sin(t * 2.3 + VERTEX.z * 9.0) * 0.015) * h;
	VERTEX.z += cos(t * 0.8) * 0.03 * h;
}
void fragment() {
	vec4 c = texture(atlas, UV);
	if (c.a < 0.5) discard;
	float mx = max(c.r, max(c.g, c.b));
	float mn = min(c.r, min(c.g, c.b));
	// the painted petals that are white (and grey-white in their shade) take the drift's colour
	float white = smoothstep(0.42, 0.72, mn) * (1.0 - smoothstep(0.1, 0.22, mx - mn));
	vec3 col = mix(c.rgb, tint.rgb * mx * 1.05, white);
	ALBEDO = col;
	ROUGHNESS = 0.8;
	BACKLIGHT = col * 0.35;
	EMISSION = tint.rgb * white * tint.a * 0.8;
}
"""

static func _flower_mat(tex: Texture2D) -> ShaderMaterial:
	if _mats.has("flower_cards"):
		return _mats["flower_cards"]
	var m := ShaderMaterial.new()
	m.shader = _shader("flower_cards", FLOWER_SHADER)
	m.set_shader_parameter("atlas", tex)
	_mats["flower_cards"] = m
	return m

static var _shaders := {}
static func _shader(key: String, code: String) -> Shader:
	if _shaders.has(key):
		return _shaders[key]
	var s := Shader.new()
	s.code = code
	_shaders[key] = s
	return s

const FLYER_SHADER := """shader_type spatial;
render_mode cull_disabled, specular_disabled;
uniform float speed = 0.6;
uniform float radius = 2.4;
uniform float flap_rate = 11.0;
uniform float hover = 0.7;
uniform float dragon = 0.0;
varying vec3 tint;
varying float body;
vec3 path(float t, float p) {
	return vec3(sin(t * 0.37 + p) * radius + sin(t * 0.91 + p * 1.3) * radius * 0.45,
		hover + sin(t * 0.73 + p * 2.1) * 0.3 * (1.0 - dragon * 0.7),
		cos(t * 0.29 + p * 0.7) * radius + sin(t * 1.13 + p) * radius * 0.4);
}
void vertex() {
	tint = INSTANCE_CUSTOM.rgb;
	body = UV.x < -0.5 ? 1.0 : 0.0;
	float p = INSTANCE_CUSTOM.a * 31.0;
	float t = TIME * speed + p * 3.0;
	// a dragonfly darts and hangs: time runs in bursts
	t += dragon * sin(t * 1.7) * 0.6;
	vec3 a = path(t, p);
	vec3 d = path(t + 0.05, p) - a;
	float yaw = atan(d.x, d.z);
	float flap = sin(TIME * flap_rate + p * 5.0);
	float ang = mix(0.15 + 1.05 * (flap * 0.5 + 0.5), 0.12 * flap, dragon);
	vec3 v = VERTEX;
	if (body < 0.5) {
		v = vec3(v.x * cos(ang), abs(v.x) * sin(ang), v.z);
	}
	float cy = cos(yaw);
	float sy = sin(yaw);
	v = vec3(v.x * cy + v.z * sy, v.y, -v.x * sy + v.z * cy);
	VERTEX = v + a + vec3(0.0, flap * 0.025 * (1.0 - dragon), 0.0);
	NORMAL = vec3(0.0, 1.0, 0.0);
}
void fragment() {
	if (body > 0.5) {
		ALBEDO = mix(vec3(0.08, 0.06, 0.05), tint * 0.6, dragon);
	} else {
		vec2 u = UV;
		// butterfly: a broad forewing and a rounder hindwing; dragonfly: one long slender wing
		float fw = length((u - vec2(0.55, 0.7)) * vec2(1.0, 1.25));
		float hw = length((u - vec2(0.45, 0.28)) * vec2(1.2, 1.35));
		float shape = dragon > 0.5 ? length((u - vec2(0.5, 0.5)) * vec2(1.0, 2.2)) : min(fw, hw);
		if (shape > 0.48) discard;
		float edge = smoothstep(0.36, 0.46, shape);
		float spot = 1.0 - smoothstep(0.05, 0.08, length(u - vec2(0.72, 0.78)));
		vec3 c = mix(tint, vec3(0.06, 0.05, 0.05), edge * (1.0 - dragon));
		c = mix(c, vec3(1.0), spot * (1.0 - dragon) * 0.9);
		c = mix(c, mix(vec3(0.8, 0.9, 1.0), tint, 0.3), dragon);
		ALBEDO = c;
		EMISSION = tint * 0.12;
		BACKLIGHT = c * 0.5;
	}
	ROUGHNESS = 0.6;
}
"""

static func _flyer_mat(key: String, speed: float, radius: float, flap: float, hover: float, dragon: float) -> ShaderMaterial:
	if _mats.has(key):
		return _mats[key]
	var m := ShaderMaterial.new()
	m.shader = _shader("flyer", FLYER_SHADER)
	m.set_shader_parameter("speed", speed)
	m.set_shader_parameter("radius", radius)
	m.set_shader_parameter("flap_rate", flap)
	m.set_shader_parameter("hover", hover)
	m.set_shader_parameter("dragon", dragon)
	_mats[key] = m
	return m

const MOTE_SHADER := """shader_type spatial;
render_mode blend_add, unshaded, depth_draw_never, cull_disabled, fog_disabled, shadows_disabled;
uniform float size = 0.1;
uniform float drift = 2.0;
uniform float height = 1.4;
uniform float blink = 1.0;
uniform float energy = 2.5;
varying vec3 col;
varying float lit;
void vertex() {
	col = INSTANCE_CUSTOM.rgb;
	float p = INSTANCE_CUSTOM.a * 40.0;
	float t = TIME;
	vec3 off = vec3(sin(t * 0.23 + p) * drift + sin(t * 0.61 + p * 2.0) * drift * 0.35,
		height + sin(t * 0.41 + p * 1.7) * height * 0.45,
		cos(t * 0.19 + p * 0.8) * drift + sin(t * 0.53 + p * 1.1) * drift * 0.35);
	lit = mix(1.0, pow(max(sin(t * 1.1 + p * 3.0), 0.0), 2.0), blink);
	vec4 c = VIEW_MATRIX * (MODEL_MATRIX * vec4(off, 1.0));
	c.xy += VERTEX.xy * size * (0.6 + 0.4 * lit);
	POSITION = PROJECTION_MATRIX * c;
}
void fragment() {
	float d = length(UV - 0.5) * 2.0;
	float a = exp(-d * d * 5.0) * lit;
	if (a < 0.003) discard;
	ALBEDO = col * energy;
	ALPHA = a;
}
"""

static func _mote_mat(key: String, size: float, drift: float, height: float, blink: float, energy: float) -> ShaderMaterial:
	if _mats.has(key):
		return _mats[key]
	var m := ShaderMaterial.new()
	m.shader = _shader("mote", MOTE_SHADER)
	m.set_shader_parameter("size", size)
	m.set_shader_parameter("drift", drift)
	m.set_shader_parameter("height", height)
	m.set_shader_parameter("blink", blink)
	m.set_shader_parameter("energy", energy)
	_mats[key] = m
	return m

const SHAFT_SHADER := """shader_type spatial;
render_mode blend_add, unshaded, depth_draw_never, cull_disabled, fog_disabled, shadows_disabled, world_vertex_coords;
uniform vec3 sun_up = vec3(0.45, 0.8, 0.4);
uniform float strength = 0.2;
uniform vec3 tint : source_color = vec3(1.0, 0.88, 0.6);
varying float along;
varying float seed;
void vertex() {
	vec3 base = MODEL_MATRIX[3].xyz;
	float len = length(MODEL_MATRIX[1].xyz);
	float wd = length(MODEL_MATRIX[0].xyz);
	vec3 ax = normalize(sun_up) * len;
	vec3 cam = INV_VIEW_MATRIX[3].xyz;
	vec3 side = normalize(cross(normalize(ax), cam - base));
	along = 1.0 - UV.y;
	seed = INSTANCE_CUSTOM.a;
	VERTEX = base + ax * along + side * (UV.x - 0.5) * wd * (0.8 + along * 0.7);
}
float h(float x) { return fract(sin(x * 127.1) * 43758.5); }
void fragment() {
	float x = UV.x;
	float a = pow(sin(3.14159 * x), 2.0);
	a *= smoothstep(0.0, 0.3, along) * smoothstep(1.0, 0.55, along);
	float n = 0.7 + 0.3 * sin(x * 9.0 + seed * 20.0 + TIME * 0.25) * sin(x * 4.0 - TIME * 0.17 + seed * 7.0);
	float breathe = 0.65 + 0.35 * sin(TIME * 0.21 + seed * 30.0);
	ALBEDO = tint;
	ALPHA = a * n * breathe * strength;
}
"""

static func _shaft_mat() -> ShaderMaterial:
	if _mats.has("shaft"):
		return _mats["shaft"]
	var m := ShaderMaterial.new()
	m.shader = _shader("shaft", SHAFT_SHADER)
	_mats["shaft"] = m
	return m

const RIPPLE_SHADER := """shader_type spatial;
render_mode blend_add, unshaded, depth_draw_never, cull_disabled, fog_disabled, shadows_disabled;
varying float ph;
void vertex() { ph = INSTANCE_CUSTOM.a; }
void fragment() {
	float t = fract(TIME * 0.22 + ph * 7.0);
	float d = length(UV - 0.5) * 2.0;
	float r = t * 0.95;
	float ring = exp(-pow((d - r) * 18.0, 2.0)) + 0.5 * exp(-pow((d - r * 0.6) * 22.0, 2.0));
	float a = ring * (1.0 - t) * (1.0 - t) * step(t, 0.7) * 0.5;
	if (a < 0.003) discard;
	ALBEDO = vec3(0.85, 0.95, 1.0);
	ALPHA = a;
}
"""

static func _ripple_mat() -> ShaderMaterial:
	if _mats.has("ripple"):
		return _mats["ripple"]
	var m := ShaderMaterial.new()
	m.shader = _shader("ripple", RIPPLE_SHADER)
	_mats["ripple"] = m
	return m

const BANNER_SHADER := """shader_type spatial;
render_mode cull_disabled;
uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap_anisotropic;
uniform bool has_normal = false;
uniform vec3 cloth : source_color = vec3(0.46, 0.16, 0.86);
uniform vec3 sigil : source_color = vec3(0.86, 0.7, 1.0);
void fragment() {
	vec4 c = texture(albedo_tex, UV);
	// the Meshy banner's red cloth turned the dark elves' violet; its gold sigil made pale silver-violet and lit
	float red = clamp((c.r - max(c.g, c.b)) * 5.0, 0.0, 1.0);
	float gold = clamp((min(c.r, c.g) - c.b) * 5.0, 0.0, 1.0) * step(0.3, c.g);
	vec3 col = mix(c.rgb, cloth * (0.3 + c.r * 1.7), red * (1.0 - gold));
	float l = dot(c.rgb, vec3(0.3, 0.55, 0.15));
	col = mix(col, sigil * l * 1.3, gold);
	ALBEDO = col;
	if (has_normal) {
		NORMAL_MAP = texture(normal_tex, UV).rgb;
	}
	ROUGHNESS = 0.85;
	EMISSION = sigil * gold * (0.55 + 0.25 * sin(TIME * 1.6 + UV.y * 6.0));
	BACKLIGHT = cloth * red * 0.4;
}
"""

static func _banner_mat(src: StandardMaterial3D) -> ShaderMaterial:
	var key := "banner:%d" % src.get_instance_id()
	if _mats.has(key):
		return _mats[key]
	var m := ShaderMaterial.new()
	m.shader = _shader("banner", BANNER_SHADER)
	m.set_shader_parameter("albedo_tex", src.albedo_texture)
	if src.normal_texture != null:
		m.set_shader_parameter("normal_tex", src.normal_texture)
		m.set_shader_parameter("has_normal", true)
	_mats[key] = m
	return m

const LEAF_SHADER := """shader_type spatial;
render_mode cull_disabled, specular_disabled;
varying vec4 col;
void vertex() {
	col = COLOR;
	float p = float(INSTANCE_ID) * 1.618;
	float a = TIME * (1.6 + fract(p) * 1.5) + p * 6.0;
	float b = TIME * (1.1 + fract(p * 3.1)) + p * 2.0;
	vec3 v = VERTEX;
	v = vec3(v.x, v.y * cos(a) - v.z * sin(a), v.y * sin(a) + v.z * cos(a));
	v = vec3(v.x * cos(b) + v.z * sin(b), v.y, -v.x * sin(b) + v.z * cos(b));
	VERTEX = v;
	NORMAL = vec3(0.0, 1.0, 0.0);
}
void fragment() {
	vec2 u = UV - 0.5;
	float leaf = abs(u.y) * 2.0 + pow(abs(u.x) * 2.0, 2.0) * 0.9;
	if (leaf > 1.0 || col.a < 0.05) discard;
	ALBEDO = col.rgb * (0.85 + 0.15 * step(abs(u.y), 0.04));
	BACKLIGHT = col.rgb * 0.6;
	ROUGHNESS = 0.7;
}
"""

static func _leaf_mat() -> ShaderMaterial:
	if _mats.has("leaf"):
		return _mats["leaf"]
	var m := ShaderMaterial.new()
	m.shader = _shader("leaf", LEAF_SHADER)
	_mats["leaf"] = m
	return m
