## Not a script: what sailing had in scripts/birds.gd, cut out whole when sailing was archived (2026-11-06), to paste back.
## REVIVE.md says where each piece was used.

# Birds was gulls at sea (`sea`, set from World.sea by Game.load_zone): pale long-winged gulls low over the water,
# some wheeling over the boat, no flocks bursting from trees, gull cries and leaping fish. The whole file as it was:

class_name Birds
extends Node3D
## Act I's birds (the moor, the camp and the fort, outdoors): small flocks of dark birds crossing the sky
## on their own courses, flapping, gliding now and then and banking into their turns, their shadows
## sliding over the ground; and now and then a flock bursting up out of the trees near the hero with a
## flutter of wings, climbing away. Only for the look: each player's game has its own (nothing is synced).
## Game.load_zone adds one when the zone is Act I's forest and outdoors.
## At sea (`sea`, the coast and the isles) they're gulls instead: pale, long-winged, low over the water,
## gliding and wheeling, some circling the boat; no flocks bursting out of trees; and now and then a fish
## leaps out of the swell with a splash (`_fish`).

const FLOCKS := 5              # crossing the sky at once
const HEIGHT := Vector2(8.5, 13.0)
const SPEED := Vector2(6.5, 9.5)

var game
var sea := false               # gulls over the water, and leaping fish
var fishes: Array = []         # {node, a, b, t, dur, h, splashed}
var _fish_t := 4.0
var flocks: Array = []         # {birds: [Node3D], pos, dir, speed, h, left, turn, flap}
var _burst_t := 12.0
var _rng := RandomNumberGenerator.new()
static var _mesh_body: Mesh
static var _mesh_wing: Mesh
static var _mesh_tail: Mesh
static var _mat: Material
static var _gull_wing: Mesh
static var _gull_tip: Mesh
static var _gull_mat: Material
static var _gull_dark: Material
static var _fish_mesh: Mesh
static var _fish_mat: Material
static var _drop_mat: Material

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
	if sea and _gull_wing == null:
		# a gull's long, narrow, angled wing with a black tip
		_gull_wing = _flat([Vector2(0.0, -0.05), Vector2(0.24, -0.06), Vector2(0.5, -0.02), Vector2(0.62, 0.04), Vector2(0.4, 0.06), Vector2(0.2, 0.07), Vector2(0.0, 0.07)])
		_gull_tip = _flat([Vector2(0.5, -0.02), Vector2(0.66, 0.035), Vector2(0.52, 0.055), Vector2(0.44, 0.03)])
		var gm := StandardMaterial3D.new()
		gm.albedo_color = Color(0.86, 0.87, 0.86)
		gm.roughness = 0.85
		gm.cull_mode = BaseMaterial3D.CULL_DISABLED
		_gull_mat = gm
		var dm := StandardMaterial3D.new()
		dm.albedo_color = Color(0.12, 0.12, 0.13)
		dm.roughness = 0.9
		dm.cull_mode = BaseMaterial3D.CULL_DISABLED
		_gull_dark = dm
	var bm: Material = _gull_mat if sea else _mat
	var root := Node3D.new()
	var body := MeshInstance3D.new()
	body.mesh = _mesh_body
	body.material_override = bm
	body.scale = Vector3(0.9, 0.8, 2.6)
	root.add_child(body)
	var tail := MeshInstance3D.new()
	tail.mesh = _mesh_tail
	tail.material_override = bm
	root.add_child(tail)
	for side in [-1.0, 1.0]:
		var hinge := Node3D.new()
		hinge.name = "wl" if side < 0.0 else "wr"
		hinge.position = Vector3(0.03 * side, 0.01, -0.02)
		hinge.scale = Vector3(side, 1, 1)
		root.add_child(hinge)
		var wing := MeshInstance3D.new()
		wing.mesh = _gull_wing if sea else _mesh_wing
		wing.material_override = bm
		hinge.add_child(wing)
		if sea:
			var tip := MeshInstance3D.new()
			tip.mesh = _gull_tip
			tip.material_override = _gull_dark
			tip.position.y = 0.002
			hinge.add_child(tip)
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
	# the birds roost after dark (DayNight)
	if not sea and game.day_night != null and game.day_night.on and game.day_night.night > 0.6:
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
	if sea:
		h = _rng.randf_range(4.5, 9.0)
		start.y = h
	var n := _rng.randi_range(5, 9) if burst else _rng.randi_range(3, 8)
	if sea:
		n = _rng.randi_range(1, 4)
	var birds := []
	for i in n:
		var bd := _bird(_rng.randf_range(1.0, 1.35))
		# a loose V or a scatter, each with its own beat
		var off := Vector3(_rng.randf_range(-2.5, 2.5), _rng.randf_range(-0.8, 0.8), _rng.randf_range(0.0, 3.5))
		if burst:
			off = Vector3(_rng.randf_range(-1.5, 1.5), _rng.randf_range(-1.0, 0.5), _rng.randf_range(-1.5, 1.5))
		bd.set_meta("off", off)
		bd.set_meta("ph", _rng.randf() * TAU)
		bd.set_meta("rate", _rng.randf_range(6.0, 8.0) if sea else _rng.randf_range(13.0, 17.0))
		if sea:
			bd.set_meta("off", Vector3(_rng.randf_range(-4.0, 4.0), _rng.randf_range(-1.2, 1.2), _rng.randf_range(-3.0, 4.0)))
		bd.position = start + off
		birds.append(bd)
	var f := {"birds": birds, "pos": start, "dir": dir, "speed": _rng.randf_range(SPEED.x, SPEED.y) * (1.25 if burst else 1.0),
		"h": h, "climb": burst, "left": 75.0 if not burst else 30.0, "turn": _rng.randf_range(-0.25, 0.25), "glide": 0.0, "t": 0.0}
	if sea:
		# gulls: slower, long glides; one in three wheels round and round over the hero (the boat) a while
		f["speed"] = _rng.randf_range(4.5, 7.0)
		f["left"] = 60.0
		if _rng.randf() < 0.35:
			f["circle"] = _rng.randf_range(0.35, 0.55) * (1.0 if _rng.randf() < 0.5 else -1.0)
			f["pos"] = hp + Vector3(_rng.randf_range(-10, 10), h, _rng.randf_range(-10, 10))
			f["left"] = _rng.randf_range(25.0, 45.0)
	flocks.append(f)

func _process(delta: float) -> void:
	if game == null or game.hero == null or game.world == null:
		return
	_burst_t -= delta
	if sea:
		_burst_t = 99.0
		_fish(delta)
		_gull_calls(delta)
	if _burst_t <= 0.0:
		_burst_t = _rng.randf_range(25.0, 50.0)
		_new_flock(true)
	for f in flocks.duplicate():
		f["t"] += delta
		# a slow wandering turn, the occasional glide
		f["turn"] = clampf(float(f["turn"]) + _rng.randf_range(-0.6, 0.6) * delta, -0.35, 0.35)
		if f.has("circle"):
			# wheeling over the hero: a steady turn, drifting along with him
			f["turn"] = f["circle"]
			f["pos"] = (f["pos"] as Vector3) + (game.hero.global_position - (f["pos"] as Vector3)) * Vector3(1, 0, 1) * delta * 0.12
		var dir: Vector3 = (f["dir"] as Vector3).rotated(Vector3.UP, float(f["turn"]) * delta)
		f["dir"] = dir
		if f["glide"] <= 0.0 and _rng.randf() < delta * (0.6 if sea else 0.15):
			f["glide"] = _rng.randf_range(2.5, 6.0) if sea else _rng.randf_range(1.2, 2.5)
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
			if sea:
				# a gull holds its wings in a shallow M and beats them slow and deep
				beat = (0.08 + sin(float(f["t"]) * 0.9 + ph) * 0.05) if gl else beat * 0.75
			(bird.get_node("wl") as Node3D).rotation.z = beat
			(bird.get_node("wr") as Node3D).rotation.z = beat
		# gone off past the edge: a new flock takes its place
		if float(f["left"]) <= 0.0:
			for bd in f["birds"]:
				(bd as Node3D).queue_free()
			flocks.erase(f)
			if not f["climb"]:
				_new_flock(false)

## Now and then a fish leaps out of the swell near the hero (or his boat): out of the water, an arc
## of a metre or so, back in, a splash at each end. Only over water deep enough (the sea map).
func _fish(delta: float) -> void:
	_fish_t -= delta
	var oc: Ocean = game.world.get_node_or_null("Ocean")
	if oc == null:
		return
	if _fish_t <= 0.0:
		_fish_t = _rng.randf_range(4.0, 11.0)
		var hp: Vector3 = game.hero.global_position
		var a := _rng.randf() * TAU
		var c := hp + Vector3(cos(a), 0, sin(a)) * _rng.randf_range(7.0, 22.0)
		if oc.depth_at(c.x, c.z) > 2.0:
			var d := Vector3(cos(a + 1.3), 0, sin(a + 1.3)) * _rng.randf_range(0.7, 1.4)
			if _fish_mesh == null:
				var cm := CapsuleMesh.new()
				cm.radius = 0.06
				cm.height = 0.42
				cm.radial_segments = 8
				cm.rings = 2
				_fish_mesh = cm
				var fm := StandardMaterial3D.new()
				fm.albedo_color = Color(0.62, 0.68, 0.72)
				fm.metallic = 0.7
				fm.roughness = 0.25
				_fish_mat = fm
			var n := MeshInstance3D.new()
			n.mesh = _fish_mesh
			n.material_override = _fish_mat
			add_child(n)
			fishes.append({"node": n, "size": _rng.randf_range(0.8, 1.4), "a": c - d, "b": c + d, "t": 0.0, "dur": _rng.randf_range(0.8, 1.1), "h": _rng.randf_range(0.7, 1.3), "splashed": false})
			_splash(oc, c - d)
	for f in fishes.duplicate():
		f["t"] = float(f["t"]) + delta
		var k: float = float(f["t"]) / float(f["dur"])
		var n: MeshInstance3D = f["node"]
		if k >= 1.0:
			_splash(oc, f["b"])
			n.queue_free()
			fishes.erase(f)
			continue
		var a: Vector3 = f["a"]
		var b: Vector3 = f["b"]
		var p := a.lerp(b, k)
		var sy := oc.surface_y(p.x, p.z)
		p.y = sy + 4.0 * float(f["h"]) * k * (1.0 - k) - 0.15
		var dir := (b - a).normalized()
		var vy := 4.0 * float(f["h"]) * (1.0 - 2.0 * k) / float(f["dur"])
		var v := dir * a.distance_to(b) / float(f["dur"]) + Vector3(0, vy, 0)
		n.position = p
		# nose along its flight, the body flexing
		var bs := Basis.looking_at(v.normalized(), Vector3.UP) * Basis(Vector3.RIGHT, PI * 0.5) * Basis(Vector3.FORWARD, sin(float(f["t"]) * 30.0) * 0.25)
		n.basis = bs * Basis.from_scale(Vector3(0.8, 1.0, 1.0) * float(f["size"]))

## Now and then one of the gulls near the hero cries (nearer flocks first; the wheeling ones more often).
var _call_t := 3.0
func _gull_calls(delta: float) -> void:
	_call_t -= delta
	if _call_t > 0.0 or flocks.is_empty():
		return
	_call_t = _rng.randf_range(4.0, 11.0)
	var hp: Vector3 = game.hero.global_position
	var best: Node3D = null
	var bd := 60.0
	for f in flocks:
		for bd_ in f["birds"]:
			var b: Node3D = bd_
			var d := b.global_position.distance_to(hp) * (0.6 if f.has("circle") else 1.0)
			if d < bd:
				bd = d
				best = b
	if best:
		Sfx.play_at("gull", best.global_position, -8.0, _rng.randf_range(0.9, 1.12))

## A little burst of white droplets and a ring on the water where a fish broke the surface.
func _splash(oc: Ocean, at: Vector3) -> void:
	var y := oc.surface_y(at.x, at.z)
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.emitting = true
	p.amount = 14
	p.lifetime = 0.7
	p.explosiveness = 0.95
	p.direction = Vector3.UP
	p.spread = 35.0
	p.initial_velocity_min = 1.2
	p.initial_velocity_max = 2.6
	p.gravity = Vector3(0, -9.8, 0)
	p.scale_amount_min = 0.03
	p.scale_amount_max = 0.07
	var q := QuadMesh.new()
	q.size = Vector2.ONE
	if _drop_mat == null:
		var dm := StandardMaterial3D.new()
		dm.albedo_color = Color(0.92, 0.96, 1.0, 0.85)
		dm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		dm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		dm.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
		dm.billboard_keep_scale = true
		_drop_mat = dm
	q.material = _drop_mat
	p.mesh = q
	add_child(p)
	p.position = Vector3(at.x, y + 0.05, at.z)
	Sfx.play_at("splash", Vector3(at.x, y, at.z), -9.0, _rng.randf_range(0.85, 1.25))
	Fx.ring(self, Vector3(at.x, y + 0.04, at.z), 0.6, Color(0.9, 0.95, 1.0, 0.6), 0.7, 0.05)
	get_tree().create_timer(1.2).timeout.connect(p.queue_free)
