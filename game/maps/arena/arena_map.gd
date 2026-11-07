class_name ArenaMap
extends RefCounted
## The Arena's hall (game/maps/arena/): a 40 m stone hall with a ring of pillars to fight round and break line of sight,
## wall torches, four braziers and candles, walled in by the crypt stone. Zones "arena" (the Arena mode, arena_match.gd)
## and "sandbox" (practice, sandbox.gd) both build it (World.build). Its pieces are ArenaProps (props/, textures/).
## Every peer builds it from the same rolls on World.rng, the dedicated server too (it has no pixels: the props are
## placeholders there, the footprints the same).

const ZONES := ["arena", "sandbox"]
const HALL := Rect2(-20.0, -20.0, 40.0, 40.0)
const PILLAR_RING := 11.0            # the eight pillars' circle
const TEAM_X := 12.0                 # where each Arena team starts (-x Ember, +x Frost), lined up along z
const TEAM_GAP := 5.0
const RING_SPAWN := 13.0             # Sandbox's free-for-all starts, round the hall
## The floor: dark flagstones (World's terrain shader, its tiles on)
const STONE := {
	"col_a": Color(0.08, 0.075, 0.07), "col_b": Color(0.1, 0.09, 0.08), "col_accent": Color(0.12, 0.13, 0.08),
	"col_path": Color(0.42, 0.4, 0.37), "col_cliff": Color(0.12, 0.11, 0.1), "tiles": 1.0, "wet": 0.5,
}

static func build(w: World) -> void:
	w.flat_floor = true
	w.theme = {"name": "arena"}
	w.floor_rects.append(HALL)
	w.bounds = HALL.grow(3.0)
	w.dirt_blobs = [[w.bounds.get_center(), 9999.0, 1.0]]
	w.dirt_lines = []
	for i in 8:
		var a := TAU * (i + 0.5) / 8.0
		_pillar(w, Vector3(cos(a) * PILLAR_RING, 0, sin(a) * PILLAR_RING), 5.0)
	for k in 4:
		_torch(w, Vector3(lerpf(HALL.position.x + 4.0, HALL.end.x - 4.0, k / 3.0), 0, HALL.position.y + 0.15), k == 1 or k == 2)
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			_brazier(w, Vector3(sx * 15.0, 0, sz * 15.0))
	for k in 4:
		var fill := OmniLight3D.new()
		fill.light_color = Color(1.0, 0.75, 0.5)
		fill.light_energy = 0.9
		fill.omni_range = 16.0
		fill.shadow_enabled = false
		fill.position = Vector3(cos(TAU * k / 4.0) * 9.0, 4.0, sin(TAU * k / 4.0) * 9.0)
		w.props_root.add_child(fill)
	_candles(w, Vector3.ZERO)
	for k in 8:
		_bones(w, Vector3(w.rng.randf_range(-17, 17), 0, w.rng.randf_range(-17, 17)))
	_walls(w)
	w.spawns["start"] = Vector3(0, 0, 12)

## Where an Arena player starts: its team's side, lined up by its place in the team.
static func team_spawn(team: int, index: int, team_size: int) -> Vector3:
	return Vector3(-TEAM_X if team == 0 else TEAM_X, 0, (index - (team_size - 1) * 0.5) * TEAM_GAP)

## Where Sandbox player `index` of `count` starts: spread round the hall.
static func ring_spawn(w: World, index: int, count: int) -> Vector3:
	var a := TAU * float(index) / float(maxi(1, count))
	return w.free_spot_near(Vector3(cos(a) * RING_SPAWN, 0, sin(a) * RING_SPAWN), 1.5)

# ---------------------------------------------------------------- the pieces
static func _pillar(w: World, p: Vector3, h: float) -> void:
	var g := Models.N(null, "pillar")
	var m := ArenaProps.pillar(h)
	if m != null:
		g.add_child(m)
	else:
		var sm := Props.stone_clean()
		Models.P(g, Geo.box(1.0, 0.4, 1.0), sm, Vector3(0, 0.2, 0))
		Models.P(g, Geo.cyl(0.36, 0.4, h - 0.8, 12), sm, Vector3(0, h * 0.5, 0))
		Models.P(g, Geo.box(1.0, 0.4, 1.0), sm, Vector3(0, h - 0.2, 0))
	w._place(g, p)
	w.add_circle(p, 0.55)

## A wall torch in its iron sconce, its back to the wall behind it (-z).
static func _torch(w: World, p: Vector3, shadow: bool) -> void:
	var g := Models.N(null, "sconce")
	var m := ArenaProps.sconce()
	if m != null:
		m.position = Vector3(0, 2.1, 0.0)
		g.add_child(m)
		w._place(g, p)
		ArenaProps.torch_light(Props.fire(g, Vector3(0, 2.1, 0) + ArenaProps.SCONCE_CUP, 0.6, Color(1.0, 0.5, 0.2), true, shadow, false, "torch"))
		return
	Models.P(g, Geo.box(0.12, 0.3, 0.1), Props.iron(), Vector3(0, 2.2, 0.0))
	Models.seg(g, Vector3(0, 2.1, 0), Vector3(0, 2.5, 0.3), 0.03, 0.04, Props.wood_dark(), 6)
	w._place(g, p)
	Props.fire(g, Vector3(0, 2.62, 0.34), 0.6, Color(1.0, 0.5, 0.2), true, shadow, false, "torch")

static func _brazier(w: World, p: Vector3) -> void:
	var g := Models.N(null, "brazier")
	for k in 3:
		var a := TAU * k / 3.0
		Models.seg(g, Vector3(cos(a) * 0.35, 0, sin(a) * 0.35), Vector3(cos(a) * 0.22, 0.85, sin(a) * 0.22), 0.04, 0.05, Props.iron(), 6)
	Models.P(g, Geo.cyl(0.5, 0.3, 0.28, 12), Props.iron(), Vector3(0, 0.95, 0))
	w._place(g, p)
	Props.fire(g, Vector3(0, 1.05, 0), 0.85, Color(1.0, 0.5, 0.2), true, false, true, "brazier")
	w.add_circle(p, 0.5)

## The row of melted candles in the middle of the hall (or wax sticks without the model).
static func _candles(w: World, p: Vector3) -> void:
	var c := ArenaProps.candles()
	if c != null:
		w._place(c, p)
		return
	var g := Models.N(null, "candles")
	var wax := Mats.mat(Color(0.85, 0.8, 0.65), 0.6, 0.0, Color(1.0, 0.7, 0.3), 0.1)
	for i in 5:
		var hh := w.rng.randf_range(0.12, 0.35)
		var cp := Vector3(w.rng.randf_range(-0.25, 0.25), 0, w.rng.randf_range(-0.25, 0.25))
		Models.P(g, Geo.cyl(0.03, 0.035, hh, 6), wax, cp + Vector3(0, hh * 0.5, 0))
		Models.P(g, Geo.sph(0.02, 5), Mats.glow(Color(1.0, 0.7, 0.3), 4.0), cp + Vector3(0, hh + 0.03, 0), Vector3.ZERO, Vector3(0.7, 1.5, 0.7))
	w._place(g, p)

static func _bones(w: World, p: Vector3) -> void:
	var g := Models.N(null, "bones")
	var yaw := w.rng.randf() * TAU
	var skull := w.rng.randf() < 0.6
	var m := ArenaProps.bones(yaw)
	if m != null:
		g.add_child(m)
	else:
		var bm := Mats.world(Color(0.72, 0.68, 0.58), Color(0.55, 0.5, 0.4), 0.7, 3.0, 0.0, Props.MOSS, false)
		for i in 6:
			Models.P(g, Geo.cyl(0.025, 0.025, 0.4, 5), bm, Vector3(cos(i) * 0.3, 0.03, sin(i) * 0.3), Vector3(90, rad_to_deg(yaw) + i * 50.0, 0))
		if skull:
			Models.P(g, Geo.sph(0.11, 8), bm, Vector3(0.1, 0.1, 0.0), Vector3.ZERO, Vector3(0.9, 1.0, 1.1))
	w._place(g, p)

## The rock round the hall: every cell off the floor is solid, the ones along its edge drawn as stone blocks of the
## crypt stone (ArenaProps.wall_meshes), a dark cap over the rest, then the flat floor.
static func _walls(w: World) -> void:
	w._rasterize()
	var fl := PackedByteArray()
	fl.resize(w.gw * w.gh)
	fl.fill(0)
	for j in w.gh:
		for i in w.gw:
			if HALL.has_point(Vector2(w.origin.x + (i + 0.5) * World.CELL, w.origin.y + (j + 0.5) * World.CELL)):
				fl[j * w.gw + i] = 1
	var at := func(i: int, j: int) -> int:
		return fl[j * w.gw + i] if i >= 0 and j >= 0 and i < w.gw and j < w.gh else 0
	w.rock.resize(w.gw * w.gh)
	w.rock.fill(0)
	var wall_xf: Array = []
	var top_xf: Array = []
	for j in w.gh:
		for i in w.gw:
			if fl[j * w.gw + i] == 1:
				continue
			w.rock[j * w.gw + i] = 1
			w.blocked[j * w.gw + i] = 1
			w.astar.set_point_solid(Vector2i(i, j), true)
			var x := w.origin.x + (i + 0.5) * World.CELL
			var z := w.origin.y + (j + 0.5) * World.CELL
			var edge := false
			var near := false
			for dj in range(-4, 5):
				for di in range(-4, 5):
					if at.call(i + di, j + dj) == 1:
						near = true
						if absi(di) <= 1 and absi(dj) <= 1:
							edge = true
			if edge:
				var hh := w.rng.randf_range(2.8, 3.4)
				wall_xf.append(Transform3D(Basis(Vector3.UP, w.rng.randf_range(-0.04, 0.04)).scaled(Vector3(1.0, hh, 1.0)), Vector3(x, hh * 0.5, z)))
			elif near:
				top_xf.append(Transform3D(Basis().scaled(Vector3(1.0, 0.2, 1.0)), Vector3(x, 3.0, z)))
	ArenaProps.wall_meshes(w, wall_xf)
	Props.multimesh(w.props_root, Geo.box(1.0, 1.0, 1.0), top_xf, false).material_override = Mats.world(Color(0.05, 0.05, 0.05), Color(0.03, 0.03, 0.03), 1.0, 1.0, 0.0, Props.MOSS, true)
	w._flush_stones(Props.stone())
	w._build_terrain(STONE)
