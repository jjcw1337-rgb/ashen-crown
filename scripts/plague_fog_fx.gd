class_name PlagueFogFx
extends RefCounted
## Fog of the Forgotten's look (the Plague Doctor's F; gameplay and the hiding rules in plague.gd).
##
## Not a poison cloud: pale grey with a faint lavender, like smelling salts and incense, moving in slow curls. Three
## layers of soft puffs (a heavy ground roll, the body, thin wisps curling off the top), a dense base on the ground
## (`BASE_SHADER`: drifting noise so it never sits still, thinning at the rim so the edge reads), faint glinting
## glass-dust motes inside, and a cool light that halos what's in it. It billows out from his censer (the emitters'
## reach grows over ROLL_T) and at the end thins from the rim inward. Budgets by the graphics preset.

const COL := Color(0.8, 0.8, 0.88)
const DEEP := Color(0.58, 0.56, 0.68)
const ROLL_T := 0.6

class Fog extends Node3D:
	var layers: Array[GPUParticles3D] = []
	var base: MeshInstance3D
	var bmat: ShaderMaterial
	var lamp: OmniLight3D
	var r := 6.0
	var age := 0.0
	var ending := -1.0
	func setup(w: World, g: Vector3, radius: float, _dur: float, quality: int) -> void:
		r = radius
		var q := clampi(quality, 0, 3)
		if OS.has_feature("web"):
			q = mini(q, 1)
		var k: float = [0.45, 0.7, 1.0, 1.25][q]
		# ground roll: big flattened puffs hugging the floor
		layers.append(_layer(int(28 * k), 2.6, 3.2, 0.25, 0.12, PlagueFogFx.DEEP, 0.32, Vector3(0, 0.35, 0), 0.15))
		# the body: the cloud itself
		layers.append(_layer(int(38 * k), 2.2, 2.8, 0.9, 0.18, PlagueFogFx.COL, 0.24, Vector3(0, 1.1, 0), 0.3))
		# wisps curling off the top
		layers.append(_layer(int(18 * k), 1.0, 1.6, 1.8, 0.35, PlagueFogFx.COL.lightened(0.1), 0.14, Vector3(0, 1.9, 0), 0.6))
		# glints: glass dust catching the light
		var glint := Fx.aura(self, Color(0.95, 0.95, 1.0, 0.8), int(14 * k), 0.2, 0.018, 2.5, 0.05, radius * 0.7, 180.0, Vector3(0, 1.0, 0))
		glint.name = "glints"
		base = PlagueVialFx._ground_disc(w, g, radius * 1.1, 10, 48, 0.06)
		bmat = ShaderMaterial.new()
		bmat.shader = PlagueFogFx._base_shader()
		bmat.set_shader_parameter("spread", 0.0)
		bmat.set_shader_parameter("fade", 1.0)
		bmat.set_shader_parameter("col", PlagueFogFx.COL)
		base.material_override = bmat
		add_child(base)
		base.position = Vector3(0, -g.y, 0)
		lamp = OmniLight3D.new()
		lamp.light_color = Color(0.75, 0.75, 0.95)
		lamp.light_energy = 0.0
		lamp.omni_range = radius
		lamp.position = Vector3(0, 1.6, 0)
		add_child(lamp)
		# the censer's burst at its heart
		Fx.burst(self, g + Vector3(0, 0.4, 0), Color(0.9, 0.9, 0.95, 0.6), 30, 4.0, 0.45, 0.9, false, 0.2, 85.0)
		Fx.burst(self, g + Vector3(0, 0.3, 0), Plague.BRASS, 8, 3.0, 0.03, 0.4, true, -9.0)
	func _layer(n: int, smin: float, smax: float, rise: float, vel: float, col: Color, alpha: float, at: Vector3, life_k: float) -> GPUParticles3D:
		var p := GPUParticles3D.new()
		p.amount = maxi(n, 6)
		p.lifetime = 3.2 + life_k * 2.0
		p.preprocess = 0.0
		var pm := ParticleProcessMaterial.new()
		pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_RING
		pm.emission_ring_axis = Vector3.UP
		pm.emission_ring_radius = 0.6
		pm.emission_ring_inner_radius = 0.0
		pm.emission_ring_height = 0.3 + at.y * 0.5
		pm.direction = Vector3.UP
		pm.spread = 80.0
		pm.initial_velocity_min = vel * 0.5
		pm.initial_velocity_max = vel * 1.5
		pm.gravity = Vector3(0.05, rise * 0.06, 0.03)
		pm.damping_min = 0.2
		pm.damping_max = 0.5
		pm.scale_min = smin
		pm.scale_max = smax
		pm.angle_min = -180.0
		pm.angle_max = 180.0
		pm.angular_velocity_min = -12.0
		pm.angular_velocity_max = 12.0
		var g := Gradient.new()
		g.set_color(0, Color(col.r, col.g, col.b, 0.0))
		g.add_point(0.2, Color(col.r, col.g, col.b, alpha))
		g.add_point(0.75, Color(col.r * 0.95, col.g * 0.95, col.b, alpha * 0.8))
		g.set_color(g.get_point_count() - 1, Color(col.r, col.g, col.b, 0.0))
		var gt := GradientTexture1D.new()
		gt.gradient = g
		pm.color_ramp = gt
		p.process_material = pm
		var q := QuadMesh.new()
		q.size = Vector2.ONE
		var qm := StandardMaterial3D.new()
		qm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		qm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		qm.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
		qm.vertex_color_use_as_albedo = true
		qm.albedo_texture = PlagueVialFx.wisp_tex()
		qm.proximity_fade_enabled = true
		qm.proximity_fade_distance = 0.6
		q.material = qm
		p.draw_pass_1 = q
		p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		p.position = at
		add_child(p)
		return p
	func end() -> void:
		if ending < 0.0:
			ending = 0.0
			for p in layers:
				p.emitting = false
	func _process(delta: float) -> void:
		age += delta
		var roll := 1.0 - pow(1.0 - clampf(age / PlagueFogFx.ROLL_T, 0.0, 1.0), 3.0)
		# the emitters' reach grows as it billows out
		for p in layers:
			(p.process_material as ParticleProcessMaterial).emission_ring_radius = maxf(0.6, r * 0.8 * roll)
		var f := 1.0
		if ending >= 0.0:
			ending += delta
			f = clampf(1.0 - ending / 1.6, 0.0, 1.0)
			if ending > 4.0:
				queue_free()
				return
		bmat.set_shader_parameter("spread", roll * (0.4 + 0.6 * f))
		bmat.set_shader_parameter("fade", f)
		lamp.light_energy = 0.55 * roll * f

## A partner standing in a co-op partner's fog is drawn faded (in the Battlegrounds, enemies are hidden instead).
static func ghostly(rig: Node3D, on: bool) -> void:
	for mi in rig.find_children("*", "GeometryInstance3D", true, false):
		(mi as GeometryInstance3D).transparency = 0.55 if on else 0.0

static var _bsh: Shader
static func _base_shader() -> Shader:
	if _bsh != null:
		return _bsh
	_bsh = Shader.new()
	_bsh.code = """
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled;
uniform vec4 col : source_color;
uniform float spread = 1.0;
uniform float fade = 1.0;
varying vec2 lp;
float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p); f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), f.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), f.x), f.y);
}
float fbm(vec2 p) { float v = 0.0; float a = 0.5; for (int i = 0; i < 4; i++) { v += a * noise(p); p *= 2.0; a *= 0.5; } return v; }
void vertex() { lp = UV * 2.0 - 1.0; }
void fragment() {
	float d = length(lp) * 1.1;
	vec2 q = lp * 2.4;
	float n = fbm(q + vec2(TIME * 0.07, TIME * 0.05)) * 0.6 + fbm(q * 2.3 - vec2(TIME * 0.11, -TIME * 0.06)) * 0.4;
	float edge = spread * (0.9 + (n - 0.5) * 0.25);
	float inside = smoothstep(edge, edge - 0.25, d);
	ALBEDO = mix(col.rgb * 0.75, col.rgb, n);
	ALPHA = inside * (0.35 + 0.4 * n) * fade;
}
"""
	return _bsh
