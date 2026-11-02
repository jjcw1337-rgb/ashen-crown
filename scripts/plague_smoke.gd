class_name PlagueSmoke
extends RefCounted
## The Plague Doctor's smoke, spores and vapour: Blender Mantaflow simulations rendered from the game camera's angle
## into flipbooks (tools/blender/plague/smoke_flipbook.py and vapour_flipbook.py, packed by tools/flipbook_pack.py):
##   VAPOUR  a low rolling vapour, looping (6 x 6): the pool's breath, Fever's sweat, poison, the apparatus's steam
##   FOG     one heavy puff pushed onto the floor, rolling out and thinning (8 x 4): Fog of the Forgotten, dust
##   SPORE   a burst of spores swelling up and drifting apart (6 x 4): Corpse Bloom's pulse, the quarantine's spores
## `puffs` throws a one-shot burst of them, `vapour` keeps them coming off something, `spore_card` plays the whole
## spore simulation once, big, on a card that faces the camera. Materials are shared; without a book they fall back
## to the soft wisp.

const VAPOUR := "res://assets/textures/fx/vapour.png"
const FOG := "res://assets/textures/fx/fog_puff.png"
const SPORE := "res://assets/textures/fx/spore_burst.png"
const GRIDS := {VAPOUR: Vector2i(6, 6), FOG: Vector2i(8, 4), SPORE: Vector2i(6, 4)}
## the spore simulation's card: metres of card per metre of simulation (the camera's 2.1 m ortho frame times the
## pack's 0.583 crop), the card's centre and the burst's source above the simulation's floor
const SPORE_CARD := 1.224
const SPORE_CENTRE := 1.0
const SPORE_SOURCE := 0.75

static var _mats := {}

## A material for billboard particles playing a book: once over each particle's life (`once`), or looping.
static func mat(path: String, once: bool, emit := Color(0, 0, 0)) -> Material:
	var key := "%s|%s|%s" % [path, once, emit.to_html()]
	if _mats.has(key):
		return _mats[key]
	var book := PlagueVialFx._tex(path)
	var m := StandardMaterial3D.new()
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.vertex_color_use_as_albedo = true
	m.roughness = 1.0
	m.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	if book != null and GRIDS.has(path):
		var gr: Vector2i = GRIDS[path]
		m.albedo_texture = book
		m.particles_anim_h_frames = gr.x
		m.particles_anim_v_frames = gr.y
		m.particles_anim_loop = not once
	else:
		m.albedo_texture = PlagueVialFx.wisp_tex()
	if emit.r + emit.g + emit.b > 0.0:
		m.emission_enabled = true
		m.emission = emit
	_mats[key] = m
	return m

## Each particle plays the book once over its life, or loops it from its own frame.
static func anim(pm: ParticleProcessMaterial, once: bool) -> void:
	if once:
		pm.anim_speed_min = 1.0
		pm.anim_speed_max = 1.0
	else:
		pm.anim_speed_min = 0.5
		pm.anim_speed_max = 0.9
		pm.anim_offset_min = 0.0
		pm.anim_offset_max = 1.0

static func _ramp(col: Color, peak: float, tail: float) -> GradientTexture1D:
	var g := Gradient.new()
	g.set_color(0, Color(col.r, col.g, col.b, 0.0))
	g.add_point(peak, col)
	g.add_point(tail, Color(col.r, col.g, col.b, col.a * 0.7))
	g.set_color(g.get_point_count() - 1, Color(col.r, col.g, col.b, 0.0))
	var gt := GradientTexture1D.new()
	gt.gradient = g
	return gt

static func _grow(from: float) -> CurveTexture:
	var c := Curve.new()
	c.add_point(Vector2(0.0, from))
	c.add_point(Vector2(1.0, 1.0))
	var ct := CurveTexture.new()
	ct.curve = c
	return ct

## A one-shot burst of `n` puffs at `pos` (world), thrown out up to `speed` and slowing (they come to rest about
## speed / 2 m out), each about `size` m and growing, living `life` s; `rise` lifts (or with a minus, settles) them.
## `flat` throws them out level all round instead (a roll across the ground); `emit` gives them a glow of their own.
static func puffs(root: Node3D, pos: Vector3, path: String, col: Color, n: int, size: float, life: float, speed: float, radius := 0.2, rise := 0.0, spread := 75.0, dir := Vector3.UP, flat := false, emit := Color(0, 0, 0)) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = maxi(n, 1)
	p.lifetime = life
	p.one_shot = true
	p.explosiveness = 0.9
	p.randomness = 0.3
	var reach := speed * life + size * 1.5 + radius
	p.visibility_aabb = AABB(Vector3(-reach, -reach * 0.5 - 1.0, -reach), Vector3(reach * 2.0, reach * 1.5 + 2.0, reach * 2.0))
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = maxf(radius, 0.01)
	pm.direction = dir
	pm.spread = spread
	if flat:
		pm.direction = Vector3(1.0, 0.0, 0.0)
		pm.spread = 180.0
		pm.flatness = 1.0
	pm.initial_velocity_min = speed * 0.4
	pm.initial_velocity_max = speed
	pm.damping_min = speed * 0.8
	pm.damping_max = speed * 1.4
	pm.gravity = Vector3(0.0, rise, 0.0)
	pm.scale_min = size * 0.7
	pm.scale_max = size * 1.2
	pm.scale_curve = _grow(0.45)
	pm.angle_min = -180.0
	pm.angle_max = 180.0
	pm.angular_velocity_min = -20.0
	pm.angular_velocity_max = 20.0
	pm.color_ramp = _ramp(col, 0.12, 0.6)
	anim(pm, true)
	p.process_material = pm
	var q := QuadMesh.new()
	q.size = Vector2.ONE
	q.material = mat(path, true, emit)
	p.draw_pass_1 = q
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(p)
	p.global_position = pos
	p.emitting = true
	Fx._free_later(p, life + 0.6)
	return p

## Vapour coming off something for as long as it is there, `at` in the parent's space: the looping vapour book, or
## another book played once per puff (`path`); `disc` spreads it over a flat disc of `radius` instead of a ball.
static func vapour(parent: Node3D, col: Color, amount: int, size: float, life: float, rise: float, radius: float, at := Vector3.ZERO, emit := Color(0, 0, 0), path := VAPOUR, disc := false) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = maxi(amount, 1)
	p.lifetime = life
	var ext := radius + size * 1.5 + rise * life
	p.visibility_aabb = AABB(Vector3(-ext, -2.0, -ext), Vector3(ext * 2.0, 4.0 + rise * life * 2.0 + size, ext * 2.0))
	var pm := ParticleProcessMaterial.new()
	if disc:
		pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_RING
		pm.emission_ring_axis = Vector3.UP
		pm.emission_ring_radius = maxf(radius, 0.01)
		pm.emission_ring_inner_radius = 0.0
		pm.emission_ring_height = 0.4
	else:
		pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
		pm.emission_sphere_radius = maxf(radius, 0.01)
	pm.direction = Vector3.UP
	pm.spread = 25.0
	pm.initial_velocity_min = rise * 0.4
	pm.initial_velocity_max = rise
	pm.gravity = Vector3(0.04, rise * 0.25, 0.02)
	pm.scale_min = size * 0.7
	pm.scale_max = size * 1.3
	pm.scale_curve = _grow(0.4)
	pm.angle_min = -180.0
	pm.angle_max = 180.0
	pm.angular_velocity_min = -15.0
	pm.angular_velocity_max = 15.0
	pm.color_ramp = _ramp(col, 0.25, 0.7)
	var once := path != VAPOUR
	anim(pm, once)
	p.process_material = pm
	var q := QuadMesh.new()
	q.size = Vector2.ONE
	q.material = mat(path, once, emit)
	p.draw_pass_1 = q
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(p)
	p.position = at
	return p

## The whole spore simulation, once, `scale` times its own size, its source at `pos`: on a card that faces the
## camera about the vertical (lit by the scene, tinted, frames blended, `glow` of its own light), gone after `dur`.
static func spore_card(root: Node3D, pos: Vector3, col: Color, scale: float, dur: float, glow := 0.12) -> MeshInstance3D:
	var book := PlagueVialFx._tex(SPORE)
	if book == null:
		return null
	var size := SPORE_CARD * scale
	var m := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(size, size)
	q.center_offset = Vector3(0.0, (SPORE_CENTRE - SPORE_SOURCE) * scale, 0.0)
	m.mesh = q
	var sh := ShaderMaterial.new()
	sh.shader = _card_shader()
	sh.set_shader_parameter("book", book)
	sh.set_shader_parameter("grid", Vector2(6, 4))
	sh.set_shader_parameter("frames", 24.0)
	sh.set_shader_parameter("t", 0.0)
	sh.set_shader_parameter("tint", col)
	sh.set_shader_parameter("flip", 1.0 if randf() < 0.5 else -1.0)
	sh.set_shader_parameter("glow", glow)
	m.material_override = sh
	m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(m)
	m.global_position = pos
	var tw := m.create_tween()
	tw.tween_method(func(v: float) -> void: sh.set_shader_parameter("t", v), 0.0, 1.0, dur)
	tw.tween_callback(m.queue_free)
	return m

static var _csh: Shader
static func _card_shader() -> Shader:
	if _csh != null:
		return _csh
	_csh = Shader.new()
	_csh.code = """
shader_type spatial;
render_mode blend_mix, cull_disabled, depth_draw_never, specular_disabled;
uniform sampler2D book : source_color, filter_linear_mipmap;
uniform vec2 grid = vec2(6.0, 4.0);
uniform float frames = 24.0;
uniform float t = 0.0;
uniform vec4 tint : source_color = vec4(1.0);
uniform float flip = 1.0;
uniform float glow = 0.12;
void vertex() {
	vec3 cam = INV_VIEW_MATRIX[3].xyz - NODE_POSITION_WORLD;
	cam.y = 0.0;
	vec3 z = normalize(cam + vec3(0.0001));
	vec3 x = normalize(cross(vec3(0.0, 1.0, 0.0), z));
	vec3 wp = NODE_POSITION_WORLD + x * VERTEX.x * flip + vec3(0.0, 1.0, 0.0) * VERTEX.y;
	VERTEX = (inverse(MODEL_MATRIX) * vec4(wp, 1.0)).xyz;
	NORMAL = (inverse(MODEL_MATRIX) * vec4(z, 0.0)).xyz;
}
vec4 cell(float f, vec2 uv) {
	vec2 c = vec2(mod(f, grid.x), floor(f / grid.x));
	return texture(book, (c + uv) / grid);
}
void fragment() {
	float ft = clamp(t, 0.0, 0.999) * (frames - 1.0);
	float f0 = floor(ft);
	vec4 c = mix(cell(f0, UV), cell(min(f0 + 1.0, frames - 1.0), UV), fract(ft));
	ALBEDO = tint.rgb * c.rgb;
	EMISSION = tint.rgb * c.rgb * glow;
	ROUGHNESS = 1.0;
	ALPHA = c.a * tint.a * (1.0 - smoothstep(0.7, 1.0, t)) * smoothstep(0.0, 0.05, t);
}
"""
	return _csh
