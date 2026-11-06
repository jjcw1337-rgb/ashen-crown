class_name DemonKitFx
extends RefCounted
## The pieces the Demon's overhauled skills are made of. None of it is Molten Fists' (no hellfire tongues, rift
## cracks or obsidian fangs): each skill has its own look out of these.
##  - Simulated smoke (`smoke`): Blender Mantaflow sims rendered as premultiplied flipbooks
##    (tools/blender/fx/smoke_flipbook.py, packed by tools/fx_smokebook.py into assets/textures/fx/demon/smoke_<kind>.png):
##    impact (a rock hitting the ground), comet (a burning rock's trail), steam, ash (a hoof's puff), blast (the
##    Crucible's ring). The ground ones were rendered from the game camera's own 44 deg and are held facing the camera,
##    so the card shows the cloud as the camera would see it in 3D; steam stands upright; the comet lies along its flight.
##  - Ground marks (`decal`): Meshy-painted top-down textures (crater, furrow, crush) on a mesh laid over the terrain
##    (not a Decal: the Compatibility renderer draws none), each with a glow mask for its hot part (made from the
##    painting by tools/fx_glow_mask.py).
##  - Real pieces (`pieces`): the Meshy boulder broken into Voronoi chunks in Blender (fracture_rock.py), the cocoon
##    broken the same way: thrown with gravity, bouncing, their molten insides cooling.
##  - Sparks (`sparks`): metal-spark streaks stretched along their flight.
##  - The Meshy props: boulder, meteor, fault plate, fissure, claw, chain, horns, cocoon (`model`), stand-ins without them.
##  - Landing marks (`target_mark`), shock rings of bending air (`shock_ring`), lights (`flash_light`), finding a
##    player's body from an event (`by_pid`, `targets`).

const DIR := "res://assets/models/fx/demon/"
const BOULDER := DIR + "boulder.glb"
const BOULDER_PIECES := DIR + "boulder_pieces.glb"
const METEOR := DIR + "meteor.glb"
const METEOR_PIECES := DIR + "meteor_pieces.glb"
const PLATE := DIR + "fault_plate.glb"
const FISSURE := DIR + "fissure.glb"
const CLAW := DIR + "hellclaw.glb"
const CHAIN := DIR + "chain.glb"
const HORNS := DIR + "horns.glb"
const COCOON := DIR + "cocoon.glb"
const COCOON_PIECES := DIR + "cocoon_pieces.glb"
const TEX := "res://assets/textures/fx/demon/"
## smoke books (the lines tools/fx_smokebook.py prints): file, grid (cols, rows), frames, cell aspect (w / h), where
## the sim's origin sits in a frame (u, v from the bottom left: the card's anchor), the cloud's width as a fraction of
## the frame's, how the card is held (0 upright, turning round the vertical; 1 facing the camera; 2 along a direction)
const BOOKS := {
	"impact": ["smoke_impact.png", Vector2(8, 6), 48, 1.2, Vector2(0.5, 0.417), 0.795, 1],
	"comet": ["smoke_comet.png", Vector2(6, 6), 36, 2.0, Vector2(0.882, 0.5), 1.0, 2],
	"steam": ["smoke_steam.png", Vector2(6, 6), 36, 1.0, Vector2(0.5, 0.019), 0.923, 0],
	"ash": ["smoke_ash.png", Vector2(6, 6), 32, 1.25, Vector2(0.5, 0.338), 0.76, 1],
	"blast": ["smoke_blast.png", Vector2(8, 5), 40, 1.25, Vector2(0.5, 0.378), 0.729, 1],
	# Frost Volley's cold mists (FrostVolleyFx): an ice arrow's strike, the freezing fog under the storm
	"frost": ["smoke_frost.png", Vector2(7, 4), 28, 1.3, Vector2(0.5, 0.4288), 0.7826, 1],
	"rime": ["smoke_rime.png", Vector2(6, 6), 36, 1.4, Vector2(0.5, 0.4685), 0.8333, 1],
	# wood smoke rising from the camp's chimneys and fires (ForestCamp._smokes): a plume leaning on a light breeze
	"chimney": ["smoke_chimney.png", Vector2(7, 6), 40, 1.000, Vector2(0.158, 0.013), 1.000, 0],
}

## how much of the books' daylight the smoke keeps in the game's dusk (fire keeps all of its own); steam rising off
## lava and the comet's smoke are lit from inside by their fire
const SMOKE_LIGHT := {"chimney": 0.75, "impact": 0.5, "ash": 0.5, "blast": 0.5, "steam": 0.7, "comet": 0.6, "frost": 0.75, "rime": 0.7}
## each book's fire, per channel: the Crucible's burst is a big sheet of flame, held back and deepened toward the
## Pit's red; the impact's flash toward molten rock
const FIRE_GAIN := {"blast": Color(0.72, 0.4, 0.22), "impact": Color(0.92, 0.74, 0.56)}

static var _scenes := {}
static var _tex := {}
static var _target_shader: Shader
static var _smoke_shader: Shader
static var _mark_shader: Shader
static var _ghost_shader: Shader

# ---------------------------------------------------------------- bodies
## A player's body on this game: his own hero if it is him, else his puppet.
static func by_pid(h: Hero, pid: int) -> Node3D:
	if pid <= 0 or h.game.net == null:
		return null
	if h.game.multiplayer.has_multiplayer_peer() and pid == h.game.multiplayer.get_unique_id():
		return h.game.hero
	var p = h.game.net.players.get(pid)
	if p is Dictionary and is_instance_valid(p.get("hero")):
		return p["hero"]
	return null

## The bodies an event names: its monsters ("t") and its player ("pid").
static func targets(h: Hero, ev: Dictionary) -> Array:
	var out: Array = []
	for e in ev.get("t", []):
		if e != null and is_instance_valid(e):
			out.append(e)
	var b := by_pid(h, int(ev.get("pid", 0)))
	if b != null:
		out.append(b)
	return out

static func height_of(n: Node) -> float:
	var v = n.get("height")
	return float(v) if v != null and float(v) > 0.2 else 1.9

static func chest(n: Node3D, k := 0.6) -> Vector3:
	return n.global_position + Vector3(0, height_of(n) * k, 0)

## His head, roughly: above his shoulders and a little forward of his facing.
static func head(h: Hero) -> Vector3:
	return h.global_position + Vector3(0, 2.15 * Demon.SCALE, 0) + h.facing() * 0.32

# ---------------------------------------------------------------- models
static func model(path: String) -> Node3D:
	if not _scenes.has(path):
		_scenes[path] = ResCache.get_res(path) if ResourceLoader.exists(path) else null
	var ps = _scenes[path]
	if ps == null:
		return null
	var n: Node3D = (ps as PackedScene).instantiate()
	for mi in n.find_children("*", "MeshInstance3D", true, false):
		(mi as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return n

## Gives every mesh of a model a heat glow drawn from its own texture's hot parts (its lava seams flare, then cool).
static func heat_model(n: Node3D, heat: float, col := Color(1.0, 0.42, 0.07)) -> void:
	for mi in n.find_children("*", "MeshInstance3D", true, false):
		var m := (mi as MeshInstance3D)
		for i in m.get_surface_override_material_count():
			var base = m.get_active_material(i)
			if base is StandardMaterial3D:
				var c := (base as StandardMaterial3D).duplicate() as StandardMaterial3D
				c.emission_enabled = true
				c.emission = col
				c.emission_energy_multiplier = heat
				if c.albedo_texture != null:
					c.emission_texture = c.albedo_texture
					c.emission_operator = BaseMaterial3D.EMISSION_OP_MULTIPLY
				SurfaceMaterials.assign(m, i, c)

static func set_heat(n: Node3D, heat: float) -> void:
	if n == null or not is_instance_valid(n):
		return
	for mi in n.find_children("*", "MeshInstance3D", true, false):
		var m := (mi as MeshInstance3D)
		for i in m.get_surface_override_material_count():
			var c = m.get_surface_override_material(i)
			if c is StandardMaterial3D:
				(c as StandardMaterial3D).emission_energy_multiplier = heat
			elif c is ShaderMaterial:
				(c as ShaderMaterial).set_shader_parameter("heat", heat)

static func tex(name: String) -> Texture2D:
	if not _tex.has(name):
		var p := TEX + name
		_tex[name] = ResCache.get_res(p) if ResourceLoader.exists(p) else null
	return _tex[name]

# ---------------------------------------------------------------- simulated smoke
## A simulated smoke flipbook on a card at pos (the sim's origin: where the rock hit, the puff's foot, the rock in
## flight). size = the cloud's width in metres; dur = how long the one shot plays (loop: seconds per pass; a looping
## card lives until freed or faded with `smoke_out`); tint darkens or colours it; axis = the way a "along" card (the
## comet) points, kept up to date with `aim_smoke`. Returns the card.
static func smoke(root: Node3D, pos: Vector3, kind: String, size: float, dur: float, loop := false, tint := Color.WHITE, axis := Vector3.RIGHT) -> MeshInstance3D:
	var b: Array = BOOKS[kind]
	var t := tex(str(b[0]))
	if _smoke_shader == null:
		_smoke_shader = Shader.new()
		_smoke_shader.code = SMOKE_SHADER
	var aspect: float = b[3]
	var anchor: Vector2 = b[4]
	var mode: int = b[6]
	var w: float = size / float(b[5])
	var hgt: float = w / aspect
	var m := ShaderMaterial.new()
	m.shader = _smoke_shader
	m.set_shader_parameter("book", t)
	m.set_shader_parameter("grid", b[1])
	m.set_shader_parameter("frames", float(b[2]))
	m.set_shader_parameter("loop", loop)
	m.set_shader_parameter("tint", tint)
	m.set_shader_parameter("dur", dur)
	m.set_shader_parameter("offset", randf())
	m.set_shader_parameter("mode", mode)
	m.set_shader_parameter("axis", axis)
	m.set_shader_parameter("smoke_light", float(SMOKE_LIGHT.get(kind, 0.5)))
	var fg: Color = FIRE_GAIN.get(kind, Color.WHITE)
	m.set_shader_parameter("fire_gain", Vector3(fg.r, fg.g, fg.b))
	# (an along card's head must lead; the others may be mirrored for variety)
	m.set_shader_parameter("flip", 1.0 if mode == 2 or randf() < 0.5 else -1.0)
	if mode == 1:
		# held facing the camera, the cloud's near half would sink into the ground: drawn nearer the camera instead
		# (shrunk to keep its size on screen), far enough that the frame's bottom clears the ground for a camera
		# looking down as low as 30 degrees (the game's is 44)
		m.set_shader_parameter("push", anchor.y * hgt * 1.75 + 0.3)
	var mi := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(w, hgt)
	q.center_offset = Vector3((0.5 - anchor.x) * w, (0.5 - anchor.y) * hgt, 0)
	mi.mesh = q
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.extra_cull_margin = maxf(w, hgt)
	root.add_child(mi)
	mi.global_position = pos
	if t == null:
		mi.visible = false       # (the book isn't built yet)
	if not loop:
		# one shot: the frames run from the first to the last over dur (driven here: the shader's TIME wraps)
		var tw := mi.create_tween()
		tw.tween_method(func(v: float): m.set_shader_parameter("prog", v), 0.0, 1.0, dur)
		tw.tween_callback(mi.queue_free)
	return mi

## Keeps an along card (the comet) on its rock: where it is, and the way it is going.
static func aim_smoke(mi, pos: Vector3, axis: Vector3) -> void:
	if mi == null or not is_instance_valid(mi):
		return
	(mi as Node3D).global_position = pos
	if axis.length() > 0.01:
		((mi as MeshInstance3D).material_override as ShaderMaterial).set_shader_parameter("axis", axis.normalized())

## Fades a looping smoke card out over dur and frees it.
static func smoke_out(mi, dur: float) -> void:
	if mi == null or not is_instance_valid(mi):
		return
	var m: ShaderMaterial = (mi as MeshInstance3D).material_override
	var tw := (mi as Node).create_tween()
	tw.tween_method(func(v: float): m.set_shader_parameter("fade", v), 1.0, 0.0, dur)
	tw.tween_callback((mi as Node).queue_free)

# ---------------------------------------------------------------- ground marks
## A Meshy-painted mark on the ground: size x by z metres, turned by yaw, its hot part glowing `glow` and cooling,
## gone after `life` s (fading over the last third). Not a Decal: the Compatibility renderer (the web build, the
## OpenGL fallback) draws no decals, and some of these marks are what an opponent reads (the charge's path, the
## fault's warning). It is a mesh laid over the ground instead, every vertex at the terrain's height. Drive its glow
## with `set_mark_glow`.
static func decal(root: Node3D, pos: Vector3, name: String, size: Vector2, yaw: float, life: float, glow := 2.0) -> MeshInstance3D:
	var mi := ground_mark(root, pos, name, size, yaw, glow)
	var m: ShaderMaterial = mi.material_override
	var tw := mi.create_tween()
	tw.tween_method(func(v: float): m.set_shader_parameter("glow", v), glow, glow * 0.25, life * 0.6).set_ease(Tween.EASE_OUT)
	tw.tween_interval(life * 0.06)
	tw.tween_method(func(v: float): m.set_shader_parameter("glow", v * glow * 0.25); m.set_shader_parameter("alpha", v), 1.0, 0.0, life * 0.34)
	tw.tween_callback(mi.queue_free)
	return mi

static func set_mark_glow(mark, energy: float) -> void:
	if mark != null and is_instance_valid(mark) and mark is MeshInstance3D:
		((mark as MeshInstance3D).material_override as ShaderMaterial).set_shader_parameter("glow", energy)

## The mesh of a ground mark: a grid over the rectangle following the terrain (the world fx_root hangs from; flat
## where there is none, as on the class picker's stage), a little above it.
static func ground_mark(root: Node3D, pos: Vector3, name: String, size: Vector2, yaw: float, glow: float) -> MeshInstance3D:
	if _mark_shader == null:
		_mark_shader = Shader.new()
		_mark_shader.code = MARK_SHADER
	var world = root.get_parent()
	var has_h: bool = world != null and world.has_method("height_at")
	var nx := clampi(int(size.x / 0.3) + 1, 2, 48)
	var nz := clampi(int(size.y / 0.3) + 1, 2, 48)
	var b := Basis(Vector3.UP, yaw)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for j in nz + 1:
		for i in nx + 1:
			var u := float(i) / nx
			var v := float(j) / nz
			var lp := Vector3((u - 0.5) * size.x, 0.0, (v - 0.5) * size.y)
			var wp := pos + b * lp
			lp.y = (float(world.height_at(wp.x, wp.z)) if has_h else pos.y) - pos.y + 0.04
			st.set_normal(Vector3.UP)
			st.set_uv(Vector2(u, v))
			st.add_vertex(lp)
	for j in nz:
		for i in nx:
			var k := j * (nx + 1) + i
			st.add_index(k)
			st.add_index(k + 1)
			st.add_index(k + nx + 1)
			st.add_index(k + 1)
			st.add_index(k + nx + 2)
			st.add_index(k + nx + 1)
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	var m := ShaderMaterial.new()
	m.shader = _mark_shader
	m.render_priority = -1          # under smoke and sparks
	m.set_shader_parameter("albedo_tex", tex(name + ".png"))
	m.set_shader_parameter("glow_tex", tex(name + "_glow.png"))
	m.set_shader_parameter("glow", glow)
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mi)
	mi.global_position = pos
	mi.rotation.y = yaw
	return mi

# ---------------------------------------------------------------- real pieces
static var _piece_sets := {}

## The pieces of a fractured model (meshes with their own materials and their offsets from its centre).
static func piece_set(path: String) -> Array:
	if _piece_sets.has(path):
		return _piece_sets[path]
	var out: Array = []
	var n := model(path)
	if n != null:
		for mi in n.find_children("*", "MeshInstance3D", true, false):
			var m := mi as MeshInstance3D
			out.append({"mesh": m.mesh, "at": (m.global_transform.origin if m.is_inside_tree() else _pos_in(n, m)), "mats": _mats(m)})
		n.free()
	_piece_sets[path] = out
	return out

static func _pos_in(root: Node3D, n: Node3D) -> Vector3:
	var t := n.transform
	var p := n.get_parent()
	while p != null and p != root:
		if p is Node3D:
			t = (p as Node3D).transform * t
		p = p.get_parent()
	return t.origin

static func _mats(m: MeshInstance3D) -> Array:
	var out: Array = []
	for i in m.mesh.get_surface_count():
		out.append(m.get_active_material(i))
	return out

## Throws the pieces of a fractured model out of `at` (scaled by `scale`): each spins, falls, bounces once and
## settles, its broken face glowing `hot` and cooling (the pieces' "Interior" material), then sinks away.
## Returns how many flew.
static func pieces(root: Node3D, world, at: Vector3, path: String, scale: float, speed: float, hot: float, life := 2.6, up := 1.0, dir := Vector3.ZERO, shadows := false) -> int:
	var set := piece_set(path)
	if set.is_empty():
		return 0
	var inner := StandardMaterial3D.new()
	inner.albedo_color = Color(0.15, 0.05, 0.02)
	inner.roughness = 0.8
	inner.emission_enabled = true
	inner.emission = Color(1.0, 0.38, 0.06)
	inner.emission_energy_multiplier = hot
	for p in set:
		var mi := MeshInstance3D.new()
		mi.mesh = p["mesh"]
		var mats: Array = p["mats"]
		for i in mats.size():
			var mt = mats[i]
			if mt is BaseMaterial3D and str((mt as BaseMaterial3D).resource_name).to_lower().contains("interior"):
				SurfaceMaterials.assign(mi, i, inner)
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(mi)
		var off: Vector3 = (p["at"] as Vector3) * scale
		mi.scale = Vector3.ONE * scale
		mi.global_position = at + off
		mi.rotation = Vector3(randf() * TAU, randf() * TAU, randf() * TAU)
		var out := off.normalized() if off.length() > 0.01 else Vector3(randf_range(-1, 1), 0.5, randf_range(-1, 1)).normalized()
		var v := (out * Vector3(1, 0.4, 1) + dir * 0.6).normalized() * speed * randf_range(0.55, 1.1) + Vector3(0, speed * up * randf_range(0.6, 1.1), 0)
		var w := Vector3(randf_range(-9, 9), randf_range(-6, 6), randf_range(-9, 9))
		_throw(mi, world, v, w, life)
	var tw := root.create_tween()
	tw.tween_method(func(k: float): inner.emission_energy_multiplier = k, hot, 0.0, life * 0.8)
	return set.size()

## One piece in flight: gravity, a bounce off the ground, rolling to rest, then sinking out of sight.
static func _throw(mi: MeshInstance3D, world, v: Vector3, w: Vector3, life: float) -> void:
	var st := {"v": v, "w": w, "t": 0.0, "bounced": 0}
	var tw := mi.create_tween()
	tw.tween_method(func(t: float):
		if not is_instance_valid(mi):
			return
		var dt: float = t - float(st["t"])
		st["t"] = t
		var vv: Vector3 = st["v"]
		vv.y -= 15.0 * dt
		var p := mi.global_position + vv * dt
		var gy: float = world.height_at(p.x, p.z) + 0.06 * mi.scale.x
		if p.y < gy:
			p.y = gy
			if int(st["bounced"]) < 2 and absf(vv.y) > 1.5:
				vv = Vector3(vv.x * 0.45, -vv.y * 0.32, vv.z * 0.45)
				st["w"] = (st["w"] as Vector3) * 0.5
				st["bounced"] = int(st["bounced"]) + 1
			else:
				vv = vv * Vector3(0.82, 0.0, 0.82)
				st["w"] = (st["w"] as Vector3) * 0.85
		st["v"] = vv
		mi.global_position = p
		mi.rotation += (st["w"] as Vector3) * dt, 0.0, life, life)
	tw.tween_property(mi, "position:y", mi.position.y - 0.4, 0.6)
	tw.tween_callback(mi.queue_free)

# ---------------------------------------------------------------- sparks
## Metal sparks: bright streaks stretched along their flight, falling and dying orange (not embers: these are
## struck, not burnt).
static func sparks(root: Node3D, pos: Vector3, dir: Vector3, n: int, spread := 40.0, speed := Vector2(5.0, 12.0), life := 0.45) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = maxi(1, n)
	p.lifetime = life
	p.one_shot = true
	p.explosiveness = 0.95
	p.local_coords = false
	p.transform_align = GPUParticles3D.TRANSFORM_ALIGN_Z_BILLBOARD_Y_TO_VELOCITY
	var pm := ParticleProcessMaterial.new()
	pm.direction = dir.normalized() if dir.length() > 0.01 else Vector3.UP
	pm.spread = spread
	pm.initial_velocity_min = speed.x
	pm.initial_velocity_max = speed.y
	pm.gravity = Vector3(0, -12.0, 0)
	pm.damping_min = 1.0
	pm.damping_max = 2.5
	pm.particle_flag_align_y = true
	pm.scale_min = 0.6
	pm.scale_max = 1.2
	var g := Gradient.new()
	g.set_color(0, Color(1.0, 0.95, 0.8, 1.0))
	g.add_point(0.35, Color(1.0, 0.65, 0.25, 1.0))
	g.set_color(1, Color(0.9, 0.2, 0.02, 0.0))
	var gt := GradientTexture1D.new()
	gt.gradient = g
	pm.color_ramp = gt
	p.process_material = pm
	var q := QuadMesh.new()
	q.size = Vector2(0.025, 0.28)
	q.material = Mats.particle_mat(true, Color(3, 3, 3))
	p.draw_pass_1 = q
	p.visibility_aabb = AABB(Vector3(-6, -3, -6), Vector3(12, 8, 12))
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(p)
	p.global_position = pos
	p.emitting = true
	Fx._free_later(p, life + 0.5)
	return p

## Clods of dirt and grit thrown up (dark, falling fast, not glowing).
static func clods(root: Node3D, pos: Vector3, n: int, speed: float, dir := Vector3.UP, spread := 60.0) -> void:
	Fx.burst(root, pos, Color(0.12, 0.09, 0.07, 1.0), n, speed, 0.07, 0.7, false, -16.0, spread, dir)

# ---------------------------------------------------------------- ghost (the charge's horns)
static func ghost_mat(col: Color, energy: float) -> ShaderMaterial:
	if _ghost_shader == null:
		_ghost_shader = Shader.new()
		_ghost_shader.code = GHOST_SHADER
	var m := ShaderMaterial.new()
	m.shader = _ghost_shader
	m.set_shader_parameter("col", col)
	m.set_shader_parameter("energy", energy)
	return m

# ---------------------------------------------------------------- marks, rings, lights
## A landing mark on the ground: a ring closing in to the size it will hit, filling as the moment comes (k 0..1).
static func target_mark(root: Node3D, world, at: Vector3, r: float, col: Color) -> Array:
	if _target_shader == null:
		_target_shader = Shader.new()
		_target_shader.code = TARGET_SHADER
	var m := ShaderMaterial.new()
	m.shader = _target_shader
	m.set_shader_parameter("col", col)
	m.set_shader_parameter("hot", Color(1.0, 0.42, 0.07))
	var mi := MeshInstance3D.new()
	mi.mesh = InfernalFx.disc_mesh(world, at, r * 1.25, 36, 4, 0.06)
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mi)
	mi.global_position = at
	return [mi, m]

## A ring of air bending outward (heat haze from High; on Low/Medium a faint dust ring instead).
static func shock_ring(root: Node3D, game, at: Vector3, r: float, dur: float) -> void:
	# only as bending air: without the heat haze (below High, the web) a coloured ring is just a flat band in the air,
	# and the dust, the crater and the shards already carry the blow
	if not InfernalFx.haze_ok(game):
		return
	var mi := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 0.82
	tm.outer_radius = 1.0
	tm.rings = 48
	tm.ring_segments = 6
	mi.mesh = tm
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var hz: ShaderMaterial = InfernalFx.haze_mat(0.05, false)
	mi.material_override = hz
	root.add_child(mi)
	mi.global_position = at + Vector3(0, 0.3, 0)
	mi.scale = Vector3(0.3, 0.6, 0.3)
	var tw := mi.create_tween().set_parallel(true)
	tw.tween_property(mi, "scale", Vector3(r, 1.4, r), dur).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	InfernalFx.tween_param(mi, hz, "life", 1.0, 0.0, dur)
	InfernalFx.tween_param(mi, hz, "alpha", 0.6, 0.0, dur)
	Fx._free_later(mi, dur + 0.05)

static func flash_light(root: Node3D, at: Vector3, col: Color, energy: float, rng: float, dur: float) -> OmniLight3D:
	var l := OmniLight3D.new()
	l.light_color = col
	l.light_energy = energy
	l.omni_range = rng
	l.shadow_enabled = false
	root.add_child(l)
	l.global_position = at
	var tw := l.create_tween()
	tw.tween_property(l, "light_energy", 0.0, dur).set_ease(Tween.EASE_OUT)
	tw.tween_callback(l.queue_free)
	return l

# ---------------------------------------------------------------- shaders
## A simulated smoke book: premultiplied RGBA (smoke darkens what's behind, its fire adds), lit already in the
## render; `tint` keys it to the scene (darker at night). One shot: the frames from `start` over `dur`; loop: from a
## random offset, round and round. Camera-facing round the vertical; frames blend into each other.
const SMOKE_SHADER := """
shader_type spatial;
render_mode unshaded, blend_premul_alpha, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;
uniform sampler2D book : source_color, filter_linear_mipmap, repeat_disable;
uniform vec2 grid = vec2(8.0, 6.0);
uniform float frames = 48.0;
uniform bool loop = false;
uniform float prog = 0.0;
uniform float dur = 1.5;
uniform float offset = 0.0;
uniform float flip = 1.0;
uniform float fade = 1.0;
uniform vec4 tint : source_color = vec4(1.0);
uniform int mode = 0;
uniform vec3 axis = vec3(1.0, 0.0, 0.0);
uniform float push = 0.0;
uniform float smoke_light = 0.5;
uniform vec3 fire_gain = vec3(1.0);
vec4 cell(float i, vec2 uv) {
	float c = mod(i, grid.x);
	float r = floor(i / grid.x);
	return texture(book, (vec2(c, r) + uv) / grid);
}
void vertex() {
	vec3 cam = INV_VIEW_MATRIX[3].xyz;
	vec3 o = MODEL_MATRIX[3].xyz;
	float sc = length(MODEL_MATRIX[0].xyz);
	vec3 side;
	vec3 up;
	if (mode == 1) {
		// facing the camera (the book was rendered from the game camera's elevation)
		side = INV_VIEW_MATRIX[0].xyz;
		up = INV_VIEW_MATRIX[1].xyz;
	} else if (mode == 2) {
		// lying along the flight, turned to the camera round it
		vec3 to = normalize(cam - o);
		vec3 d = normalize(axis);
		side = d - to * dot(d, to);
		side = length(side) > 0.001 ? normalize(side) : INV_VIEW_MATRIX[0].xyz;
		up = normalize(cross(to, side));
	} else {
		// upright, turning round the vertical
		vec3 to = normalize(vec3(cam.x - o.x, 0.0, cam.z - o.z));
		side = normalize(cross(vec3(0.0, 1.0, 0.0), to));
		up = vec3(0.0, 1.0, 0.0);
	}
	vec3 w = o + side * VERTEX.x * sc + up * VERTEX.y * sc;
	if (push > 0.0) {
		// nearer the camera along its own sight lines: the same place and size on screen, clear of the ground
		w = cam + (w - cam) * max(0.05, 1.0 - push / max(length(cam - o), 0.01));
	}
	POSITION = PROJECTION_MATRIX * VIEW_MATRIX * vec4(w, 1.0);
}
void fragment() {
	float f;
	if (loop) {
		f = fract(TIME / max(dur, 0.01) + offset) * frames;
	} else {
		f = clamp(prog, 0.0, 0.9999) * (frames - 1.0);
	}
	vec2 uv = vec2(flip > 0.0 ? UV.x : 1.0 - UV.x, UV.y);
	float i0 = floor(f);
	float i1 = loop ? mod(i0 + 1.0, frames) : min(i0 + 1.0, frames - 1.0);
	vec4 a = mix(cell(i0, uv), cell(i1, uv), fract(f));
	// (the packer fades every frame out at its edges; this only guards the atlas's neighbours under mipmaps)
	float edge = smoothstep(0.0, 0.015, uv.x) * smoothstep(1.0, 0.985, uv.x) * smoothstep(0.0, 0.015, uv.y) * smoothstep(1.0, 0.985, uv.y);
	float k = fade * edge * tint.a;
	if (mode == 0) {
		// an upright sheet (steam): its sides fade away so no card's edge stands in the air
		k *= smoothstep(0.0, 0.22, uv.x) * smoothstep(1.0, 0.78, uv.x);
	}
	if (!loop) {
		k *= 1.0 - smoothstep(0.86, 1.0, prog);
	}
	// premultiplied: smoke is colour x alpha, fire's light sits above it (no fog: the engine's fog mixes its colour
	// into clear pixels too, which premultiplied blending turns into a milky sheet over the whole card). The books
	// were lit like daylight: the smoke takes the scene's light (smoke_light), the fire keeps its own. Whatever is
	// brighter than lit smoke can be is fire.
	vec3 fire = max(a.rgb - vec3(0.42 * a.a), vec3(0.0));
	vec3 smoke = a.rgb - fire;
	ALBEDO = (smoke * smoke_light + fire * fire_gain) * tint.rgb * k;
	ALPHA = a.a * k;
}
"""

## A ground mark: the Meshy painting lit like the ground under it, its hot part glowing on top.
const MARK_SHADER := """
shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled;
uniform sampler2D albedo_tex : source_color, filter_linear_mipmap, repeat_disable;
uniform sampler2D glow_tex : source_color, filter_linear_mipmap, repeat_disable;
uniform float glow = 1.0;
uniform float alpha = 1.0;
uniform float tone = 0.5;      // the paintings are lit bright; scorched, broken earth is darker than the road
void fragment() {
	vec4 t = texture(albedo_tex, UV);
	ALBEDO = t.rgb * tone;
	ALPHA = t.a * alpha;
	ROUGHNESS = 0.95;
	EMISSION = texture(glow_tex, UV).rgb * glow;
}
"""

## The charge's apparition: a glowing, flickering ghost of the model (additive, fresnel-edged, heat-shimmering).
const GHOST_SHADER := """
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;
uniform vec4 col : source_color = vec4(1.0, 0.35, 0.06, 1.0);
uniform float energy = 1.5;
uniform float alpha = 1.0;
void fragment() {
	// a ghost: its silhouette burns, its body is all but clear, licked by moving heat
	float fr = pow(1.0 - abs(dot(NORMAL, VIEW)), 2.6);
	float lick = 0.6 + 0.4 * sin(TIME * 13.0 + VERTEX.y * 7.0 + VERTEX.x * 5.0) * sin(TIME * 5.0 + VERTEX.z * 6.0);
	float flick = 0.8 + 0.2 * sin(TIME * 23.0 + VERTEX.y * 9.0) * sin(TIME * 7.0);
	ALBEDO = col.rgb * energy * (0.06 + 1.2 * fr * lick) * flick * alpha;
}
"""

const TARGET_SHADER := """
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;
uniform float k = 0.0;          // 0 thrown .. 1 landing now
uniform float life = 1.0;
uniform vec3 col : source_color = vec3(0.78, 0.035, 0.05);
uniform vec3 hot : source_color = vec3(1.0, 0.42, 0.07);
void fragment() {
	vec2 q = (UV - 0.5) * 2.0 * 1.25;
	float r = length(q);
	if (r > 1.25) { discard; }
	float ring_r = mix(1.22, 1.0, k);
	float ring = 1.0 - smoothstep(0.0, 0.045, abs(r - ring_r));
	float edge = (1.0 - smoothstep(0.0, 0.02, abs(r - 1.0))) * 0.5;
	float fill = (1.0 - smoothstep(0.92, 1.0, r)) * k * k * 0.35;
	float a = atan(q.y, q.x);
	float ticks = step(0.9, fract(a * 12.0 / 6.2831853 + TIME * 0.3)) * (1.0 - smoothstep(0.0, 0.08, abs(r - 1.07)));
	float pulse = 0.8 + 0.2 * sin(TIME * 18.0 * (0.4 + k));
	vec3 c = mix(col, hot, k);
	vec3 o = c * (ring * 1.6 * pulse + edge + ticks * 0.6) + col * fill;
	ALBEDO = o * life;
	ALPHA = 1.0;
}
"""
