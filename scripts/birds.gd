class_name Birds
extends Node3D
## Act I's birds (the moor, the camp and the fort, outdoors): small flocks of dark birds crossing the sky
## on their own courses, flapping, gliding now and then and banking into their turns, their shadows
## sliding over the ground; and now and then a flock bursting up out of the trees near the hero with a
## flutter of wings, climbing away. Only for the look: each player's game has its own (nothing is synced).
## Game.load_zone adds one when the zone is Act I's forest and outdoors.

const FLOCKS := 5              # crossing the sky at once
const HEIGHT := Vector2(6.5, 11.0)
const SPEED := Vector2(6.5, 9.5)

var game
var flocks: Array = []         # {birds: [Node3D], pos, dir, speed, h, left, turn, flap}
var _burst_t := 12.0
var _rng := RandomNumberGenerator.new()
static var _mesh_body: Mesh
static var _mesh_wing: Mesh
static var _mesh_tail: Mesh
static var _mat: Material

func _ready() -> void:
	_rng.randomize()
	for i in FLOCKS:
		_new_flock(false, true)

## One bird, a dark silhouette for the high camera: a slim body, a fanned tail, and two swept, tapering
## wings hinged at its shoulders (x left/right, -z forward) that fold up as they beat.
func _bird(s: float) -> Node3D:
	if _mesh_body == null:
		var b := SphereMesh.new()
		b.radius = 0.05
		b.height = 0.1
		b.radial_segments = 8
		b.rings = 4
		_mesh_body = b
		_mesh_wing = _flat([Vector2(0.0, -0.06), Vector2(0.2, -0.05), Vector2(0.44, 0.06), Vector2(0.3, 0.07), Vector2(0.16, 0.1), Vector2(0.0, 0.08)])
		_mesh_tail = _flat([Vector2(0.0, 0.05), Vector2(0.07, 0.24), Vector2(0.0, 0.21), Vector2(-0.07, 0.24)])
		var m := StandardMaterial3D.new()
		m.albedo_color = Color(0.1, 0.09, 0.08)
		m.roughness = 0.95
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		_mat = m
	var root := Node3D.new()
	var body := MeshInstance3D.new()
	body.mesh = _mesh_body
	body.material_override = _mat
	body.scale = Vector3(0.9, 0.8, 2.6)
	root.add_child(body)
	var tail := MeshInstance3D.new()
	tail.mesh = _mesh_tail
	tail.material_override = _mat
	root.add_child(tail)
	for side in [-1.0, 1.0]:
		var hinge := Node3D.new()
		hinge.name = "wl" if side < 0.0 else "wr"
		hinge.position = Vector3(0.03 * side, 0.01, -0.02)
		hinge.scale = Vector3(side, 1, 1)
		root.add_child(hinge)
		var wing := MeshInstance3D.new()
		wing.mesh = _mesh_wing
		wing.material_override = _mat
		hinge.add_child(wing)
	root.scale = Vector3.ONE * s
	add_child(root)
	return root

## A flat shape in the xz plane (a fan from its first point).
static func _flat(pts: Array) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in range(1, pts.size() - 1):
		for q in [pts[0], pts[i], pts[i + 1]]:
			st.set_normal(Vector3.UP)
			st.add_vertex(Vector3(q.x, 0.0, q.y))
	return st.commit()

## A flock: from somewhere off to one side of the zone across to the other, passing over or near the hero
## now and then. burst: rising out of the trees near the hero instead.
func _new_flock(burst: bool, anywhere := false) -> void:
	if game == null or game.world == null:
		return
	var b: Rect2 = game.world.bounds
	var hp: Vector3 = game.hero.global_position
	var start: Vector3
	var dir: Vector3
	var h: float
	if burst:
		var a := _rng.randf() * TAU
		start = hp + Vector3(cos(a), 0, sin(a)) * _rng.randf_range(8.0, 15.0)
		start.y = game.world.height_at(start.x, start.z) + 3.5
		var away := start - hp
		away.y = 0
		dir = away.normalized().rotated(Vector3.UP, _rng.randf_range(-0.5, 0.5))
		h = start.y
		Sfx.play_at("birds_flutter", start, -4.0, _rng.randf_range(0.92, 1.08))
	else:
		# aimed near the hero (or anywhere on the first ones), from 40 m out
		var aim := hp + Vector3(_rng.randf_range(-16, 16), 0, _rng.randf_range(-16, 16))
		if anywhere:
			aim = Vector3(_rng.randf_range(b.position.x, b.end.x), 0, _rng.randf_range(b.position.y, b.end.y))
		var a2 := _rng.randf() * TAU
		dir = Vector3(cos(a2), 0, sin(a2))
		start = aim - dir * (40.0 if not anywhere else _rng.randf_range(0.0, 40.0))
		h = _rng.randf_range(HEIGHT.x, HEIGHT.y)
		start.y = h
	var n := _rng.randi_range(5, 9) if burst else _rng.randi_range(3, 8)
	var birds := []
	for i in n:
		var bd := _bird(_rng.randf_range(1.5, 2.0))
		# a loose V or a scatter, each with its own beat
		var off := Vector3(_rng.randf_range(-2.5, 2.5), _rng.randf_range(-0.8, 0.8), _rng.randf_range(0.0, 3.5))
		if burst:
			off = Vector3(_rng.randf_range(-1.5, 1.5), _rng.randf_range(-1.0, 0.5), _rng.randf_range(-1.5, 1.5))
		bd.set_meta("off", off)
		bd.set_meta("ph", _rng.randf() * TAU)
		bd.set_meta("rate", _rng.randf_range(13.0, 17.0))
		bd.position = start + off
		birds.append(bd)
	flocks.append({"birds": birds, "pos": start, "dir": dir, "speed": _rng.randf_range(SPEED.x, SPEED.y) * (1.25 if burst else 1.0),
		"h": h, "climb": burst, "left": 75.0 if not burst else 30.0, "turn": _rng.randf_range(-0.25, 0.25), "glide": 0.0, "t": 0.0})

func _process(delta: float) -> void:
	if game == null or game.hero == null or game.world == null:
		return
	_burst_t -= delta
	if _burst_t <= 0.0:
		_burst_t = _rng.randf_range(25.0, 50.0)
		_new_flock(true)
	for f in flocks.duplicate():
		f["t"] += delta
		# a slow wandering turn, the occasional glide
		f["turn"] = clampf(float(f["turn"]) + _rng.randf_range(-0.6, 0.6) * delta, -0.35, 0.35)
		var dir: Vector3 = (f["dir"] as Vector3).rotated(Vector3.UP, float(f["turn"]) * delta)
		f["dir"] = dir
		if f["glide"] <= 0.0 and _rng.randf() < delta * 0.15:
			f["glide"] = _rng.randf_range(1.2, 2.5)
		f["glide"] = maxf(0.0, float(f["glide"]) - delta)
		var pos: Vector3 = f["pos"] + dir * float(f["speed"]) * delta
		if f["climb"]:
			# up out of the trees to cruising height
			pos.y = move_toward(pos.y, HEIGHT.y, delta * 4.0)
		else:
			pos.y = float(f["h"]) + sin(float(f["t"]) * 0.7) * 0.8
		f["pos"] = pos
		f["left"] = float(f["left"]) - delta
		var bank: float = -float(f["turn"]) * 1.6
		var yaw := atan2(-dir.x, -dir.z)
		var basis := Basis(Vector3.UP, yaw) * Basis(Vector3.BACK, bank)
		for bd in f["birds"]:
			var bird: Node3D = bd
			var off: Vector3 = bird.get_meta("off")
			var ph: float = bird.get_meta("ph")
			var tgt: Vector3 = pos + basis * off + Vector3(0, sin(float(f["t"]) * 2.0 + ph) * 0.25, 0)
			bird.position = bird.position.lerp(tgt, clampf(delta * 3.0, 0.0, 1.0))
			bird.basis = basis.scaled(bird.basis.get_scale())
			# wings: a beat (faster when climbing), held out in a glide
			var gl: bool = float(f["glide"]) > 0.0 and not f["climb"]
			var beat: float = 0.15 if gl else sin(float(f["t"]) * float(bird.get_meta("rate")) * (1.3 if f["climb"] else 1.0) + ph) * 0.85
			(bird.get_node("wl") as Node3D).rotation.z = beat
			(bird.get_node("wr") as Node3D).rotation.z = beat
		# gone off past the edge: a new flock takes its place
		if float(f["left"]) <= 0.0:
			for bd in f["birds"]:
				(bd as Node3D).queue_free()
			flocks.erase(f)
			if not f["climb"]:
				_new_flock(false)
