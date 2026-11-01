class_name DemonKitFx
extends RefCounted
## The pieces the Demon's overhauled skills are made of. None of it is Molten Fists' (no hellfire tongues, rift
## cracks or obsidian fangs): each skill has its own look out of these.
##  - Simulated smoke (`smoke`): Blender Mantaflow sims rendered as RGBA flipbooks (tools/blender/fx/smoke_flipbook.py,
##    packed by tools/fx_smokebook.sh into assets/textures/fx/demon/smoke_<kind>.png): impact (a rock hitting the
##    ground), comet (a burning rock's trail), steam, ash (a hoof's puff), blast (the Crucible's ring). One shot or
##    looping, on camera-facing cards (or one stretched along a flight).
##  - Ground marks (`decal`): Meshy-painted top-down textures projected on the terrain by Godot Decals (crater,
##    furrow, crush), each with a glow mask for its hot part (made from the painting by tools/fx_glow_mask.py).
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
## smoke books: file, grid (cols, rows), frames, cell aspect (w / h)
const BOOKS := {
	"impact": ["smoke_impact.png", Vector2(8, 6), 48, 1.0],
	"comet": ["smoke_comet.png", Vector2(6, 6), 36, 2.0],
	"steam": ["smoke_steam.png", Vector2(6, 6), 36, 1.0],
	"ash": ["smoke_ash.png", Vector2(8, 4), 32, 1.0],
	"blast": ["smoke_blast.png", Vector2(8, 5), 40, 1.6],
}

static var _scenes := {}
static var _tex := {}
static var _target_shader: Shader
static var _smoke_shader: Shader
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
		_scenes[path] = load(path) if ResourceLoader.exists(path) else null
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
				m.set_surface_override_material(i, c)

static func set_heat(n: Node3D, heat: float) -> void:
	if n == null or not is_instance_valid(n):
		return
	for mi in n.find_children("*", "MeshInstance3D", true, false):
		var m := (mi as MeshInstance3D)
		for i in m.get_surface_override_material_count():
			var c = m.get_surface_override_material(i)
			if c is StandardMaterial3D:
				(c as StandardMaterial3D).emission_energy_multiplier = heat

static func tex(name: String) -> Texture2D:
	if not _tex.has(name):
		var p := TEX + name
		_tex[name] = load(p) if ResourceLoader.exists(p) else null
	return _tex[name]

# ---------------------------------------------------------------- simulated smoke
## A simulated smoke flipbook on a camera-facing card. size = its height in metres (the width follows the book's
## cell aspect); dur = how long the one shot plays (loop: seconds per pass); a looping card lives until freed.
## anchor_bottom: the card stands on pos (a cloud off the ground) rather than centred on it. Returns the card.
static func smoke(root: Node3D, pos: Vector3, kind: String, size: float, dur: float, loop := false, anchor_bottom := true, tint := Color.WHITE) -> MeshInstance3D:
	var b: Array = BOOKS[kind]
	var t := tex(str(b[0]))
	if _smoke_shader == null:
		_smoke_shader = Shader.new()
		_smoke_shader.code = SMOKE_SHADER
	var m := ShaderMaterial.new()
	m.shader = _smoke_shader
	m.set_shader_parameter("book", t)
	m.set_shader_parameter("grid", b[1])
	m.set_shader_parameter("frames", float(b[2]))
	m.set_shader_parameter("loop", loop)
	m.set_shader_parameter("tint", tint)
	m.set_shader_parameter("dur", dur)
	m.set_shader_parameter("offset", randf())
	m.set_shader_parameter("flip", 1.0 if randf() < 0.5 else -1.0)
	var mi := MeshInstance3D.new()
	var q := QuadMesh.new()
	var w: float = size * float(b[3])
	q.size = Vector2(w, size)
	if anchor_bottom:
		q.center_offset = Vector3(0, size * 0.5, 0)
	mi.mesh = q
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.extra_cull_margin = size
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

## Fades a looping smoke card out over dur and frees it.
static func smoke_out(mi, dur: float) -> void:
	if mi == null or not is_instance_valid(mi):
		return
	var m: ShaderMaterial = (mi as MeshInstance3D).material_override
	var tw := (mi as Node).create_tween()
	tw.tween_method(func(v: float): m.set_shader_parameter("fade", v), 1.0, 0.0, dur)
	tw.tween_callback((mi as Node).queue_free)

# ---------------------------------------------------------------- ground marks
## A Meshy-painted mark projected on the ground (and anything standing on it, a little): size x by z metres,
## turned by yaw, its hot part glowing `glow` and cooling, gone after `life` s (fading over the last third).
static func decal(root: Node3D, pos: Vector3, name: String, size: Vector2, yaw: float, life: float, glow := 2.0) -> Decal:
	var d := Decal.new()
	d.texture_albedo = tex(name + ".png")
	d.texture_emission = tex(name + "_glow.png")
	d.size = Vector3(size.x, 1.6, size.y)
	d.emission_energy = glow
	d.upper_fade = 0.3
	d.lower_fade = 0.3
	d.cull_mask = 1
	root.add_child(d)
	d.global_position = pos + Vector3(0, 0.3, 0)
	d.rotation.y = yaw
	var tw := d.create_tween()
	tw.tween_property(d, "emission_energy", glow * 0.25, life * 0.6).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(d, "modulate", Color(1, 1, 1, 1), life * 0.66)
	tw.tween_property(d, "emission_energy", 0.0, life * 0.34)
	tw.parallel().tween_property(d, "modulate", Color(1, 1, 1, 0), life * 0.34)
	tw.tween_callback(d.queue_free)
	return d

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
				mi.set_surface_override_material(i, inner)
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
	var mi := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 0.82
	tm.outer_radius = 1.0
	tm.rings = 48
	tm.ring_segments = 6
	mi.mesh = tm
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var hz: ShaderMaterial
	if InfernalFx.haze_ok(game):
		hz = InfernalFx.haze_mat(0.05, false)
	else:
		hz = InfernalFx.glow_mat(Color(0.55, 0.45, 0.38), 0.6, 1.2)
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
render_mode unshaded, blend_premul_alpha, depth_draw_never, cull_disabled, shadows_disabled;
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
vec4 cell(float i, vec2 uv) {
	float c = mod(i, grid.x);
	float r = floor(i / grid.x);
	return texture(book, (vec2(c, r) + uv) / grid);
}
void vertex() {
	// face the camera round the vertical axis
	vec3 cam = (inverse(VIEW_MATRIX) * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	vec3 o = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	vec3 to = normalize(vec3(cam.x - o.x, 0.0, cam.z - o.z));
	vec3 side = normalize(cross(vec3(0.0, 1.0, 0.0), to));
	vec3 sc = vec3(length(MODEL_MATRIX[0].xyz), length(MODEL_MATRIX[1].xyz), length(MODEL_MATRIX[2].xyz));
	vec3 w = o + side * VERTEX.x * sc.x + vec3(0.0, 1.0, 0.0) * VERTEX.y * sc.y;
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
	float edge = smoothstep(0.0, 0.04, uv.x) * smoothstep(1.0, 0.96, uv.x) * smoothstep(0.0, 0.03, uv.y) * smoothstep(1.0, 0.97, uv.y);
	float k = fade * edge;
	ALBEDO = a.rgb * tint.rgb * k;
	ALPHA = a.a * k;
}
"""

## The charge's apparition: a glowing, flickering ghost of the model (additive, fresnel-edged, heat-shimmering).
const GHOST_SHADER := """
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled;
uniform vec4 col : source_color = vec4(1.0, 0.35, 0.06, 1.0);
uniform float energy = 1.5;
uniform float alpha = 1.0;
void fragment() {
	float fr = pow(1.0 - abs(dot(NORMAL, VIEW)), 2.2);
	float flick = 0.75 + 0.25 * sin(TIME * 23.0 + VERTEX.y * 9.0) * sin(TIME * 7.0);
	ALBEDO = col.rgb * energy * (0.25 + 1.6 * fr) * flick * alpha;
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
