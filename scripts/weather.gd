class_name Weather
extends Node3D
## Snowfall for A2: two layers of drifting flakes that follow the camera, footprints that the
## knights leave in the snow (fading over half a minute), and frosty breath puffs.

const FOOTPRINTS := 180
const FLAKES := [1400, 3500, 7000, 14000]       # fine flakes per graphics setting
const BIG_FLAKES := [160, 420, 900, 1800]       # larger, closer flakes

var snowing := false
var burning := false
const EMBERS := [250, 600, 1200, 2400]
var _layers: Array = []
var _soft: Texture2D
var _prints: Array = []
var _print_age: PackedFloat32Array
var _next_print := 0
var _print_mat: ShaderMaterial

func _ready() -> void:
	_soft = _soft_disc()
	_print_mat = ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = FOOT_SHADER
	_print_mat.shader = sh
	_print_age.resize(FOOTPRINTS)
	_print_age.fill(999.0)

func _soft_disc() -> Texture2D:
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))
	g.set_color(1, Color(1, 1, 1, 0))
	g.add_point(0.45, Color(1, 1, 1, 0.85))
	var t := GradientTexture2D.new()
	t.gradient = g
	t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(0.5, 0.5)
	t.fill_to = Vector2(1.0, 0.5)
	t.width = 64
	t.height = 64
	return t

## Turn the snowfall on or off for the area just loaded, at the density for this setting.
func set_snow(on: bool, quality: int) -> void:
	snowing = on
	burning = false
	for l in _layers:
		l.queue_free()
	_layers.clear()
	for i in FOOTPRINTS:
		if i < _prints.size() and is_instance_valid(_prints[i]):
			_prints[i].visible = false
		_print_age[i] = 999.0
	if not on:
		return
	var q := clampi(quality, 0, 3)
	_layers.append(_layer(FLAKES[q], 0.1, 1.6, Vector3(30, 13, 26), 16.0, 0.9))
	_layers.append(_layer(BIG_FLAKES[q], 0.17, 1.1, Vector3(24, 11, 22), 20.0, 1.6))

func _layer(amount: int, size: float, speed: float, ext: Vector3, life: float, turb: float) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = amount
	p.lifetime = life
	p.preprocess = life
	p.local_coords = false
	p.position = Vector3(0, ext.y, 5.0)
	p.visibility_aabb = AABB(Vector3(-45, -40, -45), Vector3(90, 80, 90))
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = ext
	pm.direction = Vector3(0.22, -1.0, 0.08)
	pm.spread = 14.0
	pm.initial_velocity_min = speed * 0.7
	pm.initial_velocity_max = speed * 1.25
	pm.gravity = Vector3(0.12, -0.35, 0.04)
	pm.damping_min = 0.2
	pm.damping_max = 0.5
	pm.turbulence_enabled = true
	pm.turbulence_noise_strength = turb
	pm.turbulence_noise_scale = 5.0
	pm.turbulence_noise_speed_random = 0.4
	pm.turbulence_influence_min = 0.04
	pm.turbulence_influence_max = 0.12
	pm.scale_min = 0.55
	pm.scale_max = 1.35
	pm.angle_min = 0.0
	pm.angle_max = 360.0
	pm.angular_velocity_min = -60.0
	pm.angular_velocity_max = 60.0
	var ramp := Gradient.new()
	ramp.set_color(0, Color(1, 1, 1, 0))
	ramp.set_color(1, Color(1, 1, 1, 0))
	ramp.add_point(0.06, Color(1, 1, 1, 1))
	ramp.add_point(0.92, Color(1, 1, 1, 1))
	var rt := GradientTexture1D.new()
	rt.gradient = ramp
	pm.color_ramp = rt
	p.process_material = pm
	var quad := QuadMesh.new()
	quad.size = Vector2(size, size)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.vertex_color_use_as_albedo = true
	m.albedo_color = Color(0.93, 0.96, 1.0, 0.92)
	m.albedo_texture = _soft
	m.distance_fade_mode = BaseMaterial3D.DISTANCE_FADE_PIXEL_ALPHA
	m.distance_fade_min_distance = 0.6
	m.distance_fade_max_distance = 2.5
	quad.material = m
	p.draw_pass_1 = quad
	add_child(p)
	return p

## A3: grey ash drifting down and glowing embers rising from the burning ground.
func set_ash(on: bool, quality: int) -> void:
	burning = on
	if not on:
		return
	var q := clampi(quality, 0, 3)
	var ash := _layer(int(FLAKES[q] * 0.6), 0.09, 0.9, Vector3(30, 13, 26), 22.0, 1.3)
	var am := (ash.draw_pass_1 as QuadMesh).material as StandardMaterial3D
	am.albedo_color = Color(0.42, 0.4, 0.38, 0.85)
	_layers.append(ash)
	_layers.append(_embers(EMBERS[q]))

func _embers(amount: int) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = amount
	p.lifetime = 6.0
	p.preprocess = 6.0
	p.local_coords = false
	p.position = Vector3(0, 0.5, 4.0)
	p.visibility_aabb = AABB(Vector3(-40, -10, -40), Vector3(80, 40, 80))
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(28, 0.5, 24)
	pm.direction = Vector3(0.1, 1.0, 0.0)
	pm.spread = 25.0
	pm.initial_velocity_min = 0.5
	pm.initial_velocity_max = 1.6
	pm.gravity = Vector3(0.2, 0.35, 0.0)
	pm.turbulence_enabled = true
	pm.turbulence_noise_strength = 2.0
	pm.turbulence_noise_scale = 3.0
	pm.turbulence_influence_min = 0.08
	pm.turbulence_influence_max = 0.2
	pm.scale_min = 0.5
	pm.scale_max = 1.4
	var ramp := Gradient.new()
	ramp.set_color(0, Color(1.0, 0.75, 0.3, 0.0))
	ramp.add_point(0.08, Color(1.0, 0.65, 0.2, 1.0))
	ramp.add_point(0.6, Color(1.0, 0.35, 0.08, 0.9))
	ramp.set_color(ramp.get_point_count() - 1, Color(0.6, 0.1, 0.02, 0.0))
	var rt := GradientTexture1D.new()
	rt.gradient = ramp
	pm.color_ramp = rt
	p.process_material = pm
	var quad := QuadMesh.new()
	quad.size = Vector2(0.07, 0.07)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.vertex_color_use_as_albedo = true
	m.albedo_color = Color(2.2, 1.6, 1.0, 1.0)
	m.albedo_texture = _soft
	quad.material = m
	p.draw_pass_1 = quad
	add_child(p)
	return p

## A tall column of dark smoke rising from somewhere burning.
func make_smoke(parent: Node3D, pos: Vector3, s: float = 1.0) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = int(36 * s)
	p.lifetime = 16.0
	p.preprocess = 16.0
	p.local_coords = false
	p.visibility_aabb = AABB(Vector3(-20, -2, -20), Vector3(40, 60, 40))
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = 1.2 * s
	pm.direction = Vector3(0.15, 1.0, 0.05)
	pm.spread = 8.0
	pm.initial_velocity_min = 1.6 * s
	pm.initial_velocity_max = 2.4 * s
	pm.gravity = Vector3(0.35, 0.1, 0.1)
	pm.damping_min = 0.05
	pm.damping_max = 0.1
	pm.angle_min = 0.0
	pm.angle_max = 360.0
	pm.angular_velocity_min = -12.0
	pm.angular_velocity_max = 12.0
	var sc := Curve.new()
	sc.add_point(Vector2(0, 0.35))
	sc.add_point(Vector2(1, 2.2))
	var sct := CurveTexture.new()
	sct.curve = sc
	pm.scale_curve = sct
	var ramp := Gradient.new()
	ramp.set_color(0, Color(0.35, 0.18, 0.1, 0.0))
	ramp.add_point(0.08, Color(0.25, 0.16, 0.12, 0.55))
	ramp.add_point(0.5, Color(0.16, 0.14, 0.13, 0.42))
	ramp.set_color(ramp.get_point_count() - 1, Color(0.14, 0.13, 0.13, 0.0))
	var rt := GradientTexture1D.new()
	rt.gradient = ramp
	pm.color_ramp = rt
	p.process_material = pm
	var quad := QuadMesh.new()
	quad.size = Vector2(4.5, 4.5) * s
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.vertex_color_use_as_albedo = true
	m.albedo_texture = _soft
	m.proximity_fade_enabled = true
	m.proximity_fade_distance = 2.0
	quad.material = m
	p.draw_pass_1 = quad
	p.position = pos
	parent.add_child(p)
	return p

## Keep the snowfall centred on what the camera is looking at.
func follow(p: Vector3) -> void:
	global_position = Vector3(p.x, p.y, p.z)

# ---------------------------------------------------------------- footprints
func footstep(world: Node3D, pos: Vector3, yaw: float, side: float) -> void:
	if not snowing or world == null:
		return
	var i := _next_print
	_next_print = (_next_print + 1) % FOOTPRINTS
	var mi: MeshInstance3D
	if i < _prints.size() and is_instance_valid(_prints[i]) and _prints[i].get_parent() == world:
		mi = _prints[i]
	else:
		mi = MeshInstance3D.new()
		var pm := PlaneMesh.new()
		pm.size = Vector2(0.22, 0.4)
		mi.mesh = pm
		mi.material_override = _print_mat.duplicate()
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		world.add_child(mi)
		if i < _prints.size():
			_prints[i] = mi
		else:
			while _prints.size() < i:
				_prints.append(null)
			_prints.append(mi)
	var right := Vector3(cos(yaw), 0, -sin(yaw))
	mi.global_position = pos + right * side * 0.12 + Vector3(0, 0.03, 0)
	mi.rotation = Vector3(0, yaw, 0)
	mi.visible = true
	_print_age[i] = 0.0
	(mi.material_override as ShaderMaterial).set_shader_parameter("fade", 1.0)

func _process(delta: float) -> void:
	for i in _prints.size():
		if _print_age[i] > 900.0:
			continue
		_print_age[i] += delta
		var mi = _prints[i]
		if not is_instance_valid(mi):
			_print_age[i] = 999.0
			continue
		var f := 1.0 - clampf((_print_age[i] - 18.0) / 12.0, 0.0, 1.0)
		if f <= 0.0:
			mi.visible = false
			_print_age[i] = 999.0
		else:
			(mi.material_override as ShaderMaterial).set_shader_parameter("fade", f)

# ---------------------------------------------------------------- breath
func make_breath() -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = 10
	p.lifetime = 1.4
	p.one_shot = true
	p.explosiveness = 0.75
	p.emitting = false
	p.local_coords = false
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3(0, 0.25, -1)
	pm.spread = 18.0
	pm.initial_velocity_min = 0.35
	pm.initial_velocity_max = 0.7
	pm.gravity = Vector3(0, 0.12, 0)
	pm.damping_min = 0.6
	pm.damping_max = 1.0
	var sc := Curve.new()
	sc.add_point(Vector2(0, 0.3))
	sc.add_point(Vector2(1, 1.6))
	var sct := CurveTexture.new()
	sct.curve = sc
	pm.scale_curve = sct
	var ramp := Gradient.new()
	ramp.set_color(0, Color(1, 1, 1, 0.4))
	ramp.set_color(1, Color(1, 1, 1, 0.0))
	var rt := GradientTexture1D.new()
	rt.gradient = ramp
	pm.color_ramp = rt
	p.process_material = pm
	var quad := QuadMesh.new()
	quad.size = Vector2(0.16, 0.16)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.vertex_color_use_as_albedo = true
	m.albedo_color = Color(0.92, 0.95, 1.0, 0.55)
	m.albedo_texture = _soft if _soft else _soft_disc()
	quad.material = m
	p.draw_pass_1 = quad
	return p

const FOOT_SHADER := """
shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, diffuse_burley, specular_disabled;
uniform float fade = 1.0;
float blob(vec2 p, vec2 c, vec2 r){ vec2 d = (p - c) / r; return 1.0 - smoothstep(0.75, 1.0, length(d)); }
void fragment(){
	// a boot print: sole and toe, a gap, then the heel
	vec2 uv = UV;
	float sole = blob(uv, vec2(0.5, 0.32), vec2(0.36, 0.3));
	float heel = blob(uv, vec2(0.5, 0.77), vec2(0.3, 0.17));
	float a = max(sole, heel);
	float rim = max(blob(uv, vec2(0.5, 0.32), vec2(0.42, 0.36)), blob(uv, vec2(0.5, 0.77), vec2(0.36, 0.22))) - a;
	ALBEDO = mix(vec3(0.42, 0.5, 0.66), vec3(0.9, 0.93, 1.0), clamp(rim * 2.0, 0.0, 1.0));
	ALPHA = (a * 0.75 + rim * 0.3) * fade;
	ROUGHNESS = 0.7;
}
"""
