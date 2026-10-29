class_name Aurelia
## A2's lair (World.run == 1): the city of Aurelia, run by bandits, and its old arena. In through the city
## gate, up the colonnaded main street (shops and apartment blocks, a crossroads with a fountain, a
## temple to the west, the market to the east) to the arena plaza, where Varro the lanista waits by the
## arena's gate with an offer: fight in the games. Inside, the colosseum is half fallen (its south side,
## toward the camera, is down to its first storey and rubble), the bandits' crowd packs the standing
## stands, and the games (games.gd) run on the sand: lions, gladiators, the beasts of the pit, then the
## champion, the act's boss.

const CENTRE := Vector2(0, -150)      # the arena floor's middle
const FLOOR_RX := 15.5                # the sand: an ellipse (small enough that the stands stay in view)
const FLOOR_RZ := 11.5
const OUTER_RX := 34.0                # the outer wall
const OUTER_RZ := 28.0
const PODIUM_H := 3.4                 # the wall round the sand
const STREET_W := 8.0
const WALL_Z := -12.0                 # the city wall, gate at x = 0

static func floor_pt(a: float, k := 1.0) -> Vector2:
	return CENTRE + Vector2(cos(a) * FLOOR_RX, sin(a) * FLOOR_RZ) * k

static func outer_pt(a: float, k := 1.0) -> Vector2:
	return CENTRE + Vector2(cos(a) * OUTER_RX, sin(a) * OUTER_RZ) * k

## How far out a point is on the sand (1 = the podium wall).
static func floor_t(p: Vector2) -> float:
	var d := p - CENTRE
	return sqrt(pow(d.x / FLOOR_RX, 2) + pow(d.y / FLOOR_RZ, 2))

## The gates in the podium wall: the Gate of Life (south, where heroes come in), the two beast gates
## and the champion's gate (north). Angles on the floor ellipse.
const GATES := {"life": PI * 0.5, "beast_w": -PI * 0.5 - 0.62, "beast_e": -PI * 0.5 + 0.62, "champion": -PI * 0.5}

static func build(w: World) -> void:
	w.bounds = Rect2(-70, -195, 140, 199)
	w.theme = {"name": "wild"}
	# a city on level ground (the hills stay round the edges)
	var wr: WeakRef = weakref(w)
	w.ground_fn = func(x: float, z: float) -> float:
		var ww: World = wr.get_ref()
		if ww == null or not ww.bounds.grow(-2.0).has_point(Vector2(x, z)):
			return 0.0
		return -ww.hnoise.get_noise_2d(x, z) * 0.35
	_city_wall(w)
	_streets(w)
	_temple(w, Vector2(-40, -56))
	_market(w, Vector2(38, -56))
	_plaza(w)
	_colosseum(w)
	var games := Games.new()
	games.name = "Games"
	w.add_child(games)
	games.setup(w)
	w.set_meta("games", games)
	_lanista(w, games)
	w.exits.append({"pos": Vector3(0, 0, 1.5), "radius": 2.6, "to": "wild", "label": w.act_name("wild")})
	w.spawns["start"] = Vector3(0, 0, -4)
	w.spawns["from_wild"] = Vector3(0, 0, -4)
	w.spawns["plaza"] = Vector3(0, 0, -104)
	w.spawns["arena"] = Vector3(CENTRE.x, 0, CENTRE.y + 9.0)
	w.spawns["boss_room"] = w.spawns["plaza"]
	# beyond the city: cypresses and oaks on the hills round the walls
	_trees(w)
	w._rasterize()
	w._flush_stones(Props.stone())
	w._build_terrain(CITY_TERRAIN)
	w._scatter_grass(40000, Via.VIA_GRASS, 0.3)
	games.after_raster(w)
	_gangs(w)

const CITY_TERRAIN := {
	"col_a": Color(0.2, 0.2, 0.11), "col_b": Color(0.27, 0.25, 0.14), "col_accent": Color(0.34, 0.31, 0.17),
	"col_path": Color(0.5, 0.42, 0.3), "col_cliff": Color(0.4, 0.37, 0.32), "wet": 0.1, "cob_shade": 0.66,
}

# ---------------------------------------------------------------- the city wall and gate
static func _city_wall(w: World) -> void:
	var m := Roman.tuff()
	for sx: int in [-1, 1]:
		var x0 := sx * 4.5
		var x1 := sx * 70.0
		var n := int(absf(x1 - x0) / 6.0)
		for i in n:
			var xa := x0 + (x1 - x0) * i / n
			var xb := x0 + (x1 - x0) * (i + 1) / n
			var g := Models.N(null, "city_wall")
			var len := absf(xb - xa)
			Models.P(g, Geo.box(len + 0.05, 6.5, 2.2), m, Vector3(0, 3.0, 0))
			for k in int(len / 1.5):
				Models.P(g, Geo.box(0.8, 0.8, 2.3), m, Vector3(-len * 0.5 + 0.75 + k * 1.5, 6.65, 0))
			w._place(g, Vector3((xa + xb) * 0.5, 0, WALL_Z))
			w.add_box(Vector3((xa + xb) * 0.5, 0, WALL_Z), Vector2(len * 0.5, 1.1), PI * 0.5)
		# a gate tower each side
		var t := Props.footprint(Models.N(null, "gate_tower"), Vector2(2.6, 2.6))
		Models.P(t, Geo.box(5.2, 9.5, 5.2), m, Vector3(0, 4.5, 0))
		Models.P(t, Geo.box(5.6, 0.4, 5.6), Roman.marble(), Vector3(0, 9.3, 0))
		for k in 4:
			Models.P(t, Geo.box(0.9, 0.9, 0.9), m, Vector3(-1.9 + k * 1.27, 9.9, 2.4))
		Models.P(t, Geo.box(0.6, 1.4, 0.1), Mats.mat(Color(0.05, 0.04, 0.03), 0.9), Vector3(0, 6.5, 2.62))
		w.solid(w._place(t, Vector3(sx * 6.0, 0, WALL_Z)))
		w.solid(Props.banner(w.props_root, Vector3(sx * 3.4, 0, WALL_Z + 2.4), Color(0.55, 0.06, 0.05), Color(0.85, 0.65, 0.25)))
	var arch := Models.N(null, "city_gate")
	Models.P(arch, Roman._own(Roman.arch_mesh(7.4, 7.5, 2.6, 4.2, 6.2), Roman.tuff()), Roman.tuff())
	Models.P(arch, Geo.box(7.8, 0.4, 2.9), Roman.marble(), Vector3(0, 7.6, 0))
	w._place(arch, Vector3(0, 0, WALL_Z))
	for sx: int in [-1, 1]:
		w.add_box(Vector3(sx * 2.8, 0, WALL_Z), Vector2(0.75, 1.3), 0.0)
		w.solid(Props.tripod_torch(w.props_root, Vector3(sx * 2.6, 0, WALL_Z + 3.2), sx < 0))
	w.cobble_lines.append([Vector2(0, 2), Vector2(0, WALL_Z - 2), 4.0])
	w.dirt_lines.append([Vector2(0, 4), Vector2(0, WALL_Z), 5.0])

# ---------------------------------------------------------------- streets, porticoes, blocks
static func _streets(w: World) -> void:
	var top := CENTRE.y + OUTER_RZ + 6.0     # where the arena plaza begins
	w.cobble_lines.append([Vector2(0, WALL_Z - 1), Vector2(0, top), STREET_W])
	w.dirt_lines.append([Vector2(0, WALL_Z - 1), Vector2(0, top), STREET_W + 2.0])
	# the cross street, with a fountain where they meet
	var cz := -56.0
	w.cobble_lines.append([Vector2(-66, cz), Vector2(66, cz), 6.5])
	w.dirt_lines.append([Vector2(-66, cz), Vector2(66, cz), 8.0])
	w.cobble_blobs.append([Vector2(0, cz), 9.5, 1.0])
	Roman.fountain(w, Vector3(0, 0, cz))
	# porticoes along the main street, gaps at the crossroads; blocks of shops and apartments behind
	for seg in [[WALL_Z - 6.0, cz + 9.0], [cz - 9.0, top + 4.0]]:
		for sx: int in [-1, 1]:
			var a := Vector3(sx * (STREET_W * 0.5 + 1.6), 0, seg[0])
			var b := Vector3(sx * (STREET_W * 0.5 + 1.6), 0, seg[1])
			Roman.colonnade(w, a, b, int(absf(seg[1] - seg[0]) / 4.0) + 1, 4.0, false)
			_blocks(w, sx, seg[0], seg[1])
	# the districts behind: blocks with alleys between, a garden or a ruin here and there
	for sx: int in [-1, 1]:
		var col := 0
		var x := sx * 26.0
		while absf(x) < 64.0:
			var z := WALL_Z - 8.0
			while z > top + 8.0:
				var p := Vector2(x, z)
				if absf(z - cz) < 9.5 or (sx < 0 and p.distance_to(Vector2(-40, cz)) < 16.0) or (sx > 0 and p.distance_to(Vector2(38, cz)) < 15.0):
					z -= 4.0
					continue
				var size := Vector2(w.rng.randf_range(7.0, 10.0), w.rng.randf_range(7.0, 10.0))
				var r := w.rng.randf()
				if r < 0.12:
					w.cobble_blobs.append([p, 3.5, 0.6])     # a little yard with a tree
					Roman.cypresses(w, [Vector3(p.x, 0, p.y)])
				else:
					_building(w, Vector3(p.x, 0, p.y), size, [0.0, PI * 0.5, PI, -PI * 0.5][w.rng.randi() % 4], 2 if r < 0.3 else (1 if r < 0.75 else 0))
				z -= size.y + w.rng.randf_range(2.5, 4.0)
			x += sx * w.rng.randf_range(11.0, 13.0)
			col += 1
		# alleys of packed dirt between the columns of blocks
		for k in col:
			var ax := sx * (20.5 + k * 12.0)
			w.dirt_lines.append([Vector2(ax, WALL_Z - 3.0), Vector2(ax, top + 4.0), 3.0])
	# the cross street's blocks
	for sx: int in [-1, 1]:
		var x0 := sx * 20.0
		for k in 3:
			var x := x0 + sx * k * 10.0
			if absf(x) > 62.0:
				continue
			for sz: int in [-1, 1]:
				if (sx < 0 and absf(x + 40.0) < 12.0) or (sx > 0 and absf(x - 38.0) < 12.0):
					continue     # the temple's and the market's plazas
				_building(w, Vector3(x, 0, cz + sz * 9.5), Vector2(8.5, 6.0), 0.0 if sz > 0 else PI, w.rng.randi() % 3)

## Shops and apartment blocks behind a portico from z0 to z1 on side sx of the main street.
static func _blocks(w: World, sx: int, z0: float, z1: float) -> void:
	var z := z0 - 1.0
	while z > z1 + 5.0:
		var depth := w.rng.randf_range(7.0, 10.0)
		var len := w.rng.randf_range(7.0, 11.0)
		if z - len < z1:
			len = z - z1
		if len < 5.0:
			break
		var cx := sx * (STREET_W * 0.5 + 3.6 + depth * 0.5)
		_building(w, Vector3(cx, 0, z - len * 0.5), Vector2(len, depth), -sx * PI * 0.5, w.rng.randi() % 3)
		z -= len + w.rng.randf_range(0.6, 2.4)

## A Roman building: plastered brick walls, a terracotta roof; style 0 a shop (open front, awning,
## amphorae), 1 a two-storey apartment block (windows, a balcony), 2 a ruin (roof gone, walls broken).
## size: x along the front, y deep. Faces +z rotated by yaw.
static func _building(w: World, p: Vector3, size: Vector2, yaw: float, style: int) -> void:
	var g := Props.footprint(Models.N(null, "building"), Vector2(size.x * 0.5, size.y * 0.5))
	g.set_meta("roman", "building")
	var plaster := Mats.world([Color(0.78, 0.66, 0.5), Color(0.72, 0.5, 0.36), Color(0.82, 0.76, 0.62)][w.rng.randi() % 3], Color(0.6, 0.48, 0.36), 0.92, 1.4, 0.15)
	var h := 4.2 if style == 0 else (7.6 if style == 1 else w.rng.randf_range(2.0, 3.6))
	var hx := size.x * 0.5
	var hz := size.y * 0.5
	Models.P(g, Geo.box(size.x, 0.4, size.y), Roman.tuff(), Vector3(0, 0.2, 0))
	if style == 2:
		for side in 4:
			var along := size.x if side % 2 == 0 else size.y
			var n := maxi(2, int(along / 1.3))
			for k in n:
				var hh := h * w.rng.randf_range(0.3, 1.0)
				var off := -along * 0.5 + (k + 0.5) * along / n
				var pos := Vector3(off, hh * 0.5 + 0.4, hz) if side == 0 else (Vector3(off, hh * 0.5 + 0.4, -hz) if side == 2 else Vector3(hx if side == 1 else -hx, hh * 0.5 + 0.4, off))
				var sz := Vector3(along / n + 0.02, hh, 0.5) if side % 2 == 0 else Vector3(0.5, hh, along / n + 0.02)
				Models.P(g, Geo.box(sz.x, sz.y, sz.z), Roman.brick(), pos)
	else:
		Models.P(g, Geo.box(size.x, h, size.y), plaster, Vector3(0, 0.4 + h * 0.5, 0))
		var roof := Models.P(g, Geo.prism(size.x + 0.6, 1.6, size.y + 0.6), Roman.tile(), Vector3(0, 0.4 + h + 0.8, 0))
		roof.rotation.y = PI * 0.5 if size.x < size.y else 0.0
		if style == 0:
			# the open shop front: a dark doorway, an awning on poles, wares out front
			Models.P(g, Geo.box(size.x * 0.6, 2.6, 0.05), Mats.mat(Color(0.06, 0.05, 0.04), 0.9), Vector3(0, 1.7, hz + 0.03))
			var aw := Models.P(g, Geo.box(size.x * 0.75, 0.08, 2.0), Roman.red_cloth() if w.rng.randf() < 0.5 else Mats.world(Color(0.75, 0.68, 0.5), Color(0.6, 0.52, 0.38), 0.9, 1.5), Vector3(0, 3.0, hz + 1.0))
			aw.rotation.x = 0.18
			for sx: int in [-1, 1]:
				Models.seg(g, Vector3(sx * size.x * 0.36, 0.4, hz + 1.9), Vector3(sx * size.x * 0.36, 2.8, hz + 1.9), 0.05, 0.05, Props.wood_dark(), 5)
			for k in 3:
				Models.P(g, Geo.lathe([Vector2(0.0, 0.0), Vector2(0.12, 0.05), Vector2(0.24, 0.35), Vector2(0.2, 0.7), Vector2(0.08, 0.85), Vector2(0.1, 1.0), Vector2(0.0, 1.0)], 10, "amphora"), Roman.tile(), Vector3(-size.x * 0.3 + k * 0.6, 0.4, hz + 0.6))
		else:
			# windows on both floors and a wooden balcony
			for fl in 2:
				for k in int(size.x / 2.2):
					var wx := -hx + 1.1 + k * 2.2
					Models.P(g, Geo.box(0.7, 1.0, 0.05), Mats.mat(Color(0.06, 0.05, 0.04), 0.9), Vector3(wx, 2.2 + fl * 3.0, hz + 0.03))
			Models.P(g, Geo.box(size.x * 0.7, 0.15, 1.0), Props.wood(), Vector3(0, 3.6, hz + 0.5))
			Models.P(g, Geo.box(size.x * 0.7, 0.6, 0.06), Props.wood_dark(), Vector3(0, 3.95, hz + 1.0))
	w._place(g, p)
	g.rotation.y = yaw
	w.solid(g)

# ---------------------------------------------------------------- temple and market
## A temple on a high podium facing the cross street: steps up the front, six columns carrying a
## pediment, the cella behind, an altar out front.
static func _temple(w: World, c: Vector2) -> void:
	var g := Props.footprint(Models.N(null, "temple"), Vector2(7.0, 10.0))
	g.set_meta("roman", "temple")
	var m := Roman.marble()
	Models.P(g, Geo.box(14.0, 2.4, 20.0), Roman.tuff(), Vector3(0, 1.2, 0))
	Models.P(g, Geo.box(14.4, 0.3, 20.4), m, Vector3(0, 2.55, 0))
	for k in 5:
		Models.P(g, Geo.box(9.0, 0.5, 1.0), m, Vector3(0, 0.25 + k * 0.48, 10.0 + 2.6 - k * 0.55))
	Models.P(g, Geo.box(10.0, 7.0, 11.0), m, Vector3(0, 6.2, -3.5))
	for k in 6:
		var x := -5.6 + k * 2.24
		Models.P(g, Geo.cyl(0.42, 0.48, 7.0, 14), m, Vector3(x, 6.2, 6.8))
		Models.P(g, Geo.box(1.1, 0.35, 1.1), m, Vector3(x, 9.85, 6.8))
		if k == 0 or k == 5:
			for z in [3.4, 0.0]:
				Models.P(g, Geo.cyl(0.42, 0.48, 7.0, 14), m, Vector3(x, 6.2, z))
	Models.P(g, Geo.box(13.4, 1.2, 19.0), m, Vector3(0, 10.6, -0.5))
	var ped := Models.P(g, Geo.prism(13.6, 2.6, 19.4), Roman.tile(), Vector3(0, 12.5, -0.5))
	ped.rotation.y = PI * 0.5
	Models.P(g, Geo.box(3.0, 5.0, 0.06), Roman.bronze(), Vector3(0, 5.2, 2.03))
	w._place(g, Vector3(c.x, 0, c.y))
	g.rotation.y = PI * 0.5     # facing east, onto the cross street
	w.solid(g)
	var altar := Props.footprint(Models.N(null, "altar"), Vector2(1.0, 0.7))
	Models.P(altar, Geo.box(2.0, 1.1, 1.4), m, Vector3(0, 0.55, 0))
	w.solid(w._place(altar, Vector3(c.x + 16.0, 0, c.y)))
	Props.fire(altar, Vector3(0, 1.2, 0), 1.2, Color(1.0, 0.6, 0.25), true, false)
	w.cobble_blobs.append([c + Vector2(12, 0), 9.0, 1.0])
	for sz: int in [-1, 1]:
		Roman.statue(w, Vector3(c.x + 14.0, 0, c.y + sz * 6.0), -PI * 0.5, 1.2)

## The market east of the crossroads: stalls under awnings round a statue, crates and amphorae.
static func _market(w: World, c: Vector2) -> void:
	w.cobble_blobs.append([c, 11.0, 1.0])
	Roman.statue(w, Vector3(c.x, 0, c.y), PI * 0.5 + 0.3, 1.3)
	for k in 7:
		var a := TAU * k / 7.0 + 0.3
		var p := c + Vector2(cos(a), sin(a)) * 8.0
		var face := atan2(c.x - p.x, c.y - p.y)
		var path: String = ForestCamp.DIR + ["alchemy", "armory", "forge"][k % 3] + ".glb"
		if k % 2 == 0 and ResourceLoader.exists(path):
			var st: Node3D = (load(path) as PackedScene).instantiate()
			w._place(st, Vector3(p.x, 0, p.y))
			st.rotation.y = face
			st.scale = Vector3.ONE * 1.2
			w.add_box(Vector3(p.x, 0, p.y), Vector2(1.8, 1.4), face)
		else:
			w.solid(Props.crate(w.props_root, Vector3(p.x, 0, p.y), 1.0))
			w.solid(Props.barrel(w.props_root, Vector3(p.x + 1.2, 0, p.y + 0.4)))

# ---------------------------------------------------------------- the arena plaza
static func _plaza(w: World) -> void:
	var zc := CENTRE.y + OUTER_RZ + 9.0
	w.cobble_blobs.append([Vector2(0, zc), 16.0, 1.0])
	w.cobble_blobs.append([Vector2(-16, zc - 2.0), 9.0, 1.0])
	w.cobble_blobs.append([Vector2(16, zc - 2.0), 9.0, 1.0])
	for sx: int in [-1, 1]:
		Roman.statue(w, Vector3(sx * 12.0, 0, zc + 4.0), PI, 1.4)
		Roman.column(w, Vector3(sx * 20.0, 0, zc), 6.0, 0.4, 0.0)
		Roman.column(w, Vector3(sx * 26.0, 0, zc - 3.0), 6.0, 0.4, 0.45)
		_brazier(w, Vector3(sx * 4.5, 0, zc - 3.5))
		w.solid(Props.banner(w.props_root, Vector3(sx * 7.0, 0, zc - 5.5), Color(0.55, 0.06, 0.05), Color(0.85, 0.65, 0.25)))

static func _brazier(w: World, p: Vector3) -> void:
	var g := Props.footprint(Models.N(null, "brazier"), 0.5)
	Models.P(g, Geo.cyl(0.25, 0.35, 1.0, 10), Roman.marble(), Vector3(0, 0.5, 0))
	Models.P(g, Geo.cyl(0.6, 0.3, 0.45, 14), Roman.bronze(), Vector3(0, 1.2, 0))
	w._place(g, p)
	Props.fire(g, Vector3(0, 1.45, 0), 1.8, Color(1.0, 0.55, 0.2), true, false)
	w.solid(g)

## Varro the lanista by the arena's gate, two of his bandits lounging near: he offers you the games.
static func _lanista(w: World, games: Games) -> void:
	var p := Vector3(4.5, 0, CENTRE.y + OUTER_RZ + 4.5)
	var look := {"skin": Color(0.66, 0.5, 0.38), "cloth": Color(0.4, 0.12, 0.42), "cloth2": Color(0.3, 0.2, 0.12), "height": 1.0, "bulk": 1.1, "head": "human", "hair": Color(0.08, 0.06, 0.05), "robe": true}
	var it := w._npc("Varro the Lanista", look, p, "lanista", PI * 0.85)
	it.kind = "lanista"
	games.lanista = it
	for sx: int in [-1, 1]:
		var gl := {"skin": Color(0.6, 0.45, 0.33), "cloth": Color(0.3, 0.24, 0.16), "cloth2": Color(0.22, 0.25, 0.14), "height": 1.0, "bulk": 1.0, "head": "human", "hair": Color(0.12, 0.09, 0.06), "weapon": "scimitar"}
		var rig := Models.humanoid(gl)
		w.props_root.add_child(rig)
		rig.position = Vector3(p.x + sx * 2.4 - 1.0, 0, p.z - 1.5)
		rig.rotation.y = PI + sx * 0.4
		w.add_circle(rig.position, 0.4)

# ---------------------------------------------------------------- the colosseum
## The arena: the podium wall round the sand (solid, its Gate of Life on the south a gap the games open
## and shut), tiers of stands, the outer arcade three storeys high on the north half and fallen to its
## first storey and rubble on the south (so the camera sees in), a passage in from the plaza, the
## beast gates and the champion's gate in the north wall, the patron's box above it. The crowd is the
## games' (games.gd).
static func _colosseum(w: World) -> void:
	var root := Models.N(w.props_root, "colosseum")
	root.set_meta("roman", "colosseum")
	w.dirt_blobs.append([CENTRE, FLOOR_RX + 1.0, 1.0])
	# the podium wall round the sand, in short straight runs
	var n := 72
	var life: float = GATES["life"]
	for i in n:
		var a0 := TAU * i / n
		var a1 := TAU * (i + 1) / n
		var am := (a0 + a1) * 0.5
		if absf(angle_difference(am, life)) < 0.13:
			continue
		var p0 := floor_pt(a0, 1.04)
		var p1 := floor_pt(a1, 1.04)
		var d := p1 - p0
		var mid := (p0 + p1) * 0.5
		var seg := Models.N(root, "podium")
		Models.P(seg, Geo.box(d.length() + 0.08, PODIUM_H, 1.2), Roman.marble(), Vector3(0, PODIUM_H * 0.5, 0))
		Models.P(seg, Geo.box(d.length() + 0.1, 0.5, 1.25), Roman.red_cloth(), Vector3(0, PODIUM_H - 0.6, 0.0))
		seg.position = Vector3(mid.x, 0, mid.y)
		seg.rotation.y = atan2(-d.y, d.x)
		w.add_box(Vector3(mid.x, 0, mid.y), Vector2(0.7, d.length() * 0.5 + 0.05), atan2(d.x, d.y))
	# stands: four stepped tiers between the podium and the outer wall; low and broken on the south
	var tiers: Array = [[], [], [], []]
	var tier_m := Roman._own(Geo.box(1.0, 1.0, 1.0), Roman.tuff())
	for k in 4:
		var kk := float(k) / 3.0
		var rx := lerpf(FLOOR_RX * 1.04 + 1.8, OUTER_RX - 3.0, kk)
		var rz := lerpf(FLOOR_RZ * 1.04 + 1.8, OUTER_RZ - 3.0, kk)
		var steps := 64 + k * 8
		for i in steps:
			var a := TAU * (i + 0.5) / steps
			if absf(angle_difference(a, life)) < 0.16:
				continue
			var south := sin(a) > 0.15
			var h := PODIUM_H + 0.4 + k * 1.7
			if south:
				if w.rng.randf() < 0.3:
					continue
				h *= w.rng.randf_range(0.25, 0.55)
			var pa := CENTRE + Vector2(cos(a) * rx, sin(a) * rz)
			var pb := CENTRE + Vector2(cos(a + TAU / steps) * rx, sin(a + TAU / steps) * rz)
			var len := pa.distance_to(pb) + 0.15
			var tang := pb - pa
			var b := Basis(Vector3.UP, atan2(-tang.y, tang.x)).scaled(Vector3(len, h, 3.4))
			(tiers[k] as Array).append(Transform3D(b, Vector3((pa.x + pb.x) * 0.5, h * 0.5, (pa.y + pb.y) * 0.5)))
	for k in 4:
		Props.multimesh(root, tier_m, tiers[k])
	# the outer arcade: three storeys on the north half, one broken storey on the south
	var bays: Array = [[], [], []]
	var arch_m := Roman._own(Roman.arch_mesh(4.6, 5.2, 2.2, 2.8, 4.2), Roman.marble())
	var cap_m := Roman._own(Geo.box(4.6, 1.1, 2.4), Roman.marble())
	var caps: Array = []
	var nb := 50
	for i in nb:
		var a := TAU * (i + 0.5) / nb
		var p := outer_pt(a)
		var q := outer_pt(a + 0.02)
		var tang := q - p
		var bs := Basis(Vector3.UP, atan2(-tang.y, tang.x))
		var south := sin(a) > 0.1
		if absf(angle_difference(a, life)) < 0.08:
			continue     # the entrance passage
		var storeys := 3
		if south:
			if w.rng.randf() < 0.25:
				Roman.drum(w, Vector3(p.x + w.rng.randf_range(-2, 2), 0, p.y + w.rng.randf_range(1, 4)), 0.5, 1.4)
				continue
			storeys = 1
		for s in storeys:
			(bays[s] as Array).append(Transform3D(bs, Vector3(p.x, s * 5.2, p.y)))
		if storeys == 3:
			caps.append(Transform3D(bs, Vector3(p.x, 15.6 + 0.55, p.y)))
		w.add_box(Vector3(p.x, 0, p.y), Vector2(1.2, tang.length() / 0.02 * TAU / nb * 0.5 + 0.1), atan2(tang.x, tang.y))
	for s in 3:
		Props.multimesh(root, arch_m, bays[s])
	Props.multimesh(root, cap_m, caps)
	# rubble along the fallen south side
	for k in 26:
		var a := w.rng.randf_range(0.2, PI - 0.2)
		if absf(angle_difference(a, life)) < 0.2:
			continue
		var p := outer_pt(a, w.rng.randf_range(0.78, 1.08))
		w._rock(Vector3(p.x, 0, p.y), w.rng.randf_range(0.6, 1.4), false)
	# the passage in from the plaza to the Gate of Life
	var g0 := outer_pt(life, 1.03)
	var g1 := floor_pt(life, 1.04)
	for sx: int in [-1, 1]:
		var wall := Models.N(root, "passage")
		var len := g0.distance_to(g1)
		Models.P(wall, Geo.box(1.2, 5.0, len), Roman.tuff(), Vector3(0, 2.5, 0))
		wall.position = Vector3(sx * 3.0, 0, (g0.y + g1.y) * 0.5)
		w.add_box(wall.position, Vector2(0.6, len * 0.5), 0.0)
	var ent := Models.N(root, "entrance")
	Models.P(ent, Roman._own(Roman.arch_mesh(9.0, 7.0, 2.4, 4.6, 5.8), Roman.marble()), Roman.marble())
	Models.P(ent, Geo.box(4.0, 0.9, 0.08), Mats.mat(Color(0.2, 0.18, 0.16), 0.9), Vector3(0, 6.3, 1.25))
	ent.position = Vector3(g0.x, 0, g0.y)
	w.dirt_lines.append([g0 + Vector2(0, 4), g1 - Vector2(0, 2), 5.0])
	w.cobble_lines.append([g0 + Vector2(0, 5), g0 - Vector2(0, 2), 4.0])
	# the patron's box over the champion's gate: a dais with columns and a red canopy
	var cg := floor_pt(GATES["champion"], 1.25)
	var box := Models.N(root, "patron_box")
	Models.P(box, Geo.box(9.0, 0.5, 4.0), Roman.marble(), Vector3(0, PODIUM_H + 2.2, 0))
	for sx: int in [-1, 1]:
		for sz: int in [-1, 1]:
			Models.P(box, Geo.cyl(0.22, 0.25, 3.2, 10), Roman.marble(), Vector3(sx * 4.0, PODIUM_H + 4.0, sz * 1.6))
	Models.P(box, Geo.box(9.4, 0.15, 4.4), Roman.red_cloth(), Vector3(0, PODIUM_H + 5.7, 0), Vector3(4, 0, 0))
	box.position = Vector3(cg.x, 0, cg.y)
	# braziers round the sand
	for k in 8:
		var a := TAU * (k + 0.5) / 8.0
		if absf(angle_difference(a, life)) < 0.4:
			continue
		var p := floor_pt(a, 0.93)
		_brazier(w, Vector3(p.x, 0, p.y))

# ---------------------------------------------------------------- outside the walls, and the gangs
static func _trees(w: World) -> void:
	var cyp: Array = []
	for i in 160:
		var p := Vector2(w.rng.randf_range(w.bounds.position.x - 14, w.bounds.end.x + 14), w.rng.randf_range(w.bounds.position.y - 14, w.bounds.end.y + 8))
		if w.bounds.grow(-1.0).has_point(p) and p.y < WALL_Z + 2.0:
			# inside the city: only round the arena's outer edge and in the temple's grove
			if not (p.distance_to(Vector2(-58, -30)) < 9.0 or (absf(p.x) > 48.0 and p.y < -100.0)):
				continue
		if w.is_near_obstacle(Vector3(p.x, 0, p.y), 2.0) or absf(p.x) < 8.0:
			continue
		cyp.append(Vector3(p.x, 0, p.y))
	Roman.cypresses(w, cyp)

## Bandit gangs hold the streets and plazas.
static func _gangs(w: World) -> void:
	var lv := w.level
	var pid := 400
	for spot in [Vector2(-2, -30), Vector2(3, -46), Vector2(-30, -56), Vector2(30, -50), Vector2(48, -60), Vector2(-50, -60), Vector2(2, -72), Vector2(-3, -90), Vector2(40, -92), Vector2(-40, -90)]:
		var k := "bandit_archer" if pid % 3 == 2 else "bandit"
		w.enemy_spawns.append({"kind": k, "pos": Vector3(spot.x, 0, spot.y), "count": 3 + pid % 2 if k == "bandit" else 2, "champ": pid == 406, "pack": pid, "level": lv})
		pid += 1
