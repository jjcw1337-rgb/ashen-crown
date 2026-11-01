class_name PlagueBloomFx
extends RefCounted
## Corpse Bloom's look (the Plague Doctor's R; gameplay in plague.gd): a corpse flower erupting from the ground.
##
## The organism is the Meshy model assets/models/plague/bloom.glb (concept, image-to-3D, tools/blender/prep_prop.py:
## swollen spore sacs in diseased petals over black roots). It grows out of the soil (squash and stretch, the petals
## unfolding as it rises), breathes, and on each pulse swells and throws spores up. Under it the roots creep out
## across the ground to the edge of its reach (`ROOT_SHADER`: veined, wet, with the reach's rim always visible), and
## on its own clock (the same as the gameplay's) the warning ring draws in from the rim before each pulse, so
## everyone sees exactly when to move. A snared foe is lashed by roots bursting up round its feet (`lash`). At the
## end it withers, blackens and collapses into dust (`wither`).

const BLOOM_GLB := "res://assets/models/plague/bloom.glb"
const FLESH := Color(0.62, 0.25, 0.32)
const SPORE := Color(0.82, 0.95, 0.42)

## The seed-syringe in his hand as he kneels: a brass syringe with a dark bulb.
static func seed_syringe() -> Node3D:
	var root := Node3D.new()
	var brass := StandardMaterial3D.new()
	brass.albedo_color = Color(0.72, 0.52, 0.24)
	brass.metallic = 1.0
	brass.roughness = 0.35
	var tube := MeshInstance3D.new()
	tube.mesh = Geo.cyl(0.012, 0.012, 0.14, 10)
	tube.material_override = brass
	tube.rotation = Vector3(PI * 0.5, 0, 0)
	root.add_child(tube)
	var bulb := MeshInstance3D.new()
	bulb.mesh = Geo.sph(0.028, 10)
	var bm := StandardMaterial3D.new()
	bm.albedo_color = FLESH.darkened(0.3)
	bm.roughness = 0.25
	bm.emission_enabled = true
	bm.emission = SPORE * 0.25
	bulb.material_override = bm
	bulb.position = Vector3(0, 0, 0.08)
	root.add_child(bulb)
	var needle := MeshInstance3D.new()
	needle.mesh = Geo.cyl(0.002, 0.002, 0.08, 6)
	needle.material_override = Mats.mat(Color(0.8, 0.82, 0.85), 0.2, 1.0)
	needle.rotation = Vector3(PI * 0.5, 0, 0)
	needle.position = Vector3(0, 0, -0.11)
	root.add_child(needle)
	return root

class Bloom extends Node3D:
	var body: Node3D
	var roots: MeshInstance3D
	var rmat: ShaderMaterial
	var lamp: OmniLight3D
	var spores: GPUParticles3D
	var r := 3.5
	var age := 0.0
	var grow := 1.0
	var life := 7.0
	var every := 2.0
	var warn := 0.6
	var last_pulse := -1
	var dying := -1.0
	var size := 1.0
	func setup(w: World, g: Vector3, radius: float, grow_t: float, active_t: float, every_t: float, warn_t: float) -> void:
		r = radius
		grow = grow_t
		life = grow_t + active_t
		every = every_t
		warn = warn_t
		roots = PlagueVialFx._ground_disc(w, g, radius * 1.05, 14, 56, 0.04)
		rmat = ShaderMaterial.new()
		rmat.shader = PlagueBloomFx._root_shader()
		rmat.set_shader_parameter("spread", 0.0)
		rmat.set_shader_parameter("warn", 0.0)
		rmat.set_shader_parameter("seed", randf() * 50.0)
		rmat.set_shader_parameter("fade", 1.0)
		roots.material_override = rmat
		add_child(roots)
		roots.position = Vector3(0, -g.y, 0)
		body = Node3D.new()
		add_child(body)
		if ResourceLoader.exists(PlagueBloomFx.BLOOM_GLB):
			var m: Node3D = (load(PlagueBloomFx.BLOOM_GLB) as PackedScene).instantiate()
			body.add_child(m)
			for mi in m.find_children("*", "MeshInstance3D", true, false):
				(mi as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		body.scale = Vector3(0.05, 0.05, 0.05)
		body.rotation.y = randf() * TAU
		size = 1.7    # larger than the 1.1 m model, so it reads from the game camera
		body.position = Vector3(0, -0.3, 0)
		lamp = OmniLight3D.new()
		lamp.light_color = PlagueBloomFx.SPORE
		lamp.light_energy = 0.0
		lamp.omni_range = radius * 0.9
		lamp.position = Vector3(0, 0.8, 0)
		add_child(lamp)
		# spores drifting up off the sacs the whole time
		spores = Fx.aura(self, Color(PlagueBloomFx.SPORE.r, PlagueBloomFx.SPORE.g, PlagueBloomFx.SPORE.b, 0.8), 24, 0.35, 0.025, 2.2, 0.25, 0.45, 35.0, Vector3(0, 0.8, 0))
		# the ground breaking where it comes up
		Fx.burst(self, g + Vector3(0, 0.15, 0), Color(0.18, 0.13, 0.1), 26, 2.6, 0.07, 0.7, false, -9.0, 60.0)
	func _process(delta: float) -> void:
		age += delta
		var spread := clampf(age / (grow + 0.5), 0.0, 1.0)
		if dying >= 0.0:
			dying += delta
			var k := clampf(dying / 0.9, 0.0, 1.0)
			body.scale = body.scale.lerp(Vector3(0.6, 0.02, 0.6), clampf(delta * 3.5, 0.0, 1.0))
			body.position.y = lerpf(body.position.y, -0.35, clampf(delta * 2.0, 0.0, 1.0))
			rmat.set_shader_parameter("fade", 1.0 - k)
			lamp.light_energy *= 0.9
			if dying > 1.8:
				queue_free()
			return
		rmat.set_shader_parameter("spread", 1.0 - pow(1.0 - spread, 2.0))
		# the growth: squash and stretch out of the soil, overshooting
		var gk := clampf(age / grow, 0.0, 1.0)
		var s := 1.0
		if gk < 1.0:
			var e := 1.0 - pow(1.0 - gk, 3.0)
			s = e * (1.0 + 0.18 * sin(gk * PI))
			body.scale = Vector3(s * (1.0 + 0.15 * (1.0 - gk)), s * (0.6 + 0.4 * gk) * 1.1, s * (1.0 + 0.15 * (1.0 - gk))) * size
			body.position.y = lerpf(-0.3, 0.0, e)
			lamp.light_energy = gk * 0.7
			return
		# alive: the sacs breathe; the warning ring draws in before each pulse; the pulse swells it
		var since := age - grow
		var cyc := fmod(since, every)
		var w := 0.0
		if cyc >= every - warn:
			w = (cyc - (every - warn)) / warn
		rmat.set_shader_parameter("warn", w)
		var breathe := 1.0 + 0.04 * sin(age * 2.6)
		var swell := 1.0 + 0.12 * w * w
		body.scale = Vector3(breathe * swell, (2.0 - breathe) * swell * 1.0, breathe * swell) * size
		lamp.light_energy = 0.35 + 0.5 * w * w
		var n := int(floor(since / every))
		if n > last_pulse and since >= every * float(n) and n >= 1:
			last_pulse = n
			_pulse()
	func _pulse() -> void:
		body.scale *= 0.88
		var p := global_position
		Fx.burst(self, p + Vector3(0, 1.2, 0), PlagueBloomFx.SPORE * Color(0.8, 0.8, 0.8), 44, 3.2, 0.05, 1.2, true, -1.5, 55.0)
		Fx.burst(self, p + Vector3(0, 0.5, 0), Color(PlagueBloomFx.SPORE.r * 0.6, PlagueBloomFx.SPORE.g * 0.6, 0.2, 0.35), 18, 2.2, 0.5, 1.4, false, 0.4, 85.0)
		Fx.ring(self, p, r, Color(PlagueBloomFx.SPORE.r * 0.8, PlagueBloomFx.SPORE.g * 0.8, 0.25), 0.45, 0.35)
		Fx.flash(self, p + Vector3(0, 1.0, 0), PlagueBloomFx.SPORE, 0.9, 0.25, r * 1.2)
	func wither() -> void:
		if dying < 0.0:
			dying = 0.0
			if spores != null:
				spores.emitting = false
			Fx.burst(self, global_position + Vector3(0, 0.5, 0), Color(0.22, 0.18, 0.14, 0.7), 30, 1.6, 0.25, 1.4, false, 0.3, 80.0)

## A snared foe: roots burst up and coil round its feet, and a tendril snaps from the bloom to it.
static func lash(bloom: Node, e: Node3D) -> void:
	if not is_instance_valid(bloom) or not (bloom is Bloom) or not is_instance_valid(e):
		return
	var b := bloom as Bloom
	var at := e.global_position
	var root := Node3D.new()
	b.add_child(root)
	root.global_position = at
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.08, 0.06, 0.06)
	mat.roughness = 0.4
	mat.emission_enabled = true
	mat.emission = SPORE * 0.15
	for k in 5:
		var m := MeshInstance3D.new()
		m.mesh = Geo.cyl(0.015, 0.05, 0.9, 6)
		m.material_override = mat
		var a := TAU * float(k) / 5.0
		m.position = Vector3(cos(a) * 0.32, 0.0, sin(a) * 0.32)
		m.rotation = Vector3(sin(a) * 0.5, 0, -cos(a) * 0.5)
		m.scale = Vector3(1, 0.01, 1)
		root.add_child(m)
		var tw := m.create_tween()
		tw.tween_property(m, "scale", Vector3(1, 1, 1), 0.12).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tw.tween_interval(0.45)
		tw.tween_property(m, "scale", Vector3(1, 0.01, 1), 0.25)
	Fx.burst(b, at + Vector3(0, 0.2, 0), Color(0.18, 0.13, 0.1), 14, 2.0, 0.05, 0.5, false, -9.0, 70.0)
	Fx._free_later(root, 1.2)

static var _rsh: Shader
static func _root_shader() -> Shader:
	if _rsh != null:
		return _rsh
	_rsh = Shader.new()
	_rsh.code = """
shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_back, specular_schlick_ggx;
uniform float spread = 1.0;
uniform float warn = 0.0;
uniform float seed = 0.0;
uniform float fade = 1.0;
varying vec2 lp;
float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p); f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), f.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), f.x), f.y);
}
float fbm(vec2 p) { float v = 0.0; float a = 0.5; for (int i = 0; i < 4; i++) { v += a * noise(p); p *= 2.1; a *= 0.5; } return v; }
void vertex() { lp = UV * 2.0 - 1.0; }
void fragment() {
	float d = length(lp) * 1.05;
	float ang = atan(lp.y, lp.x);
	// roots: dark ridges running outward, branching, reaching as far as `spread`
	float rad = 1.0 - abs(fbm(vec2(ang * 3.0 + seed, d * 2.5)) * 2.0 - 1.0);
	float roots = pow(rad, 6.0) * smoothstep(spread * 1.0 + 0.02, spread * 0.85, d);
	float mid = smoothstep(0.45, 0.0, d);
	// the rim of its reach, always faintly there once grown, and the warning ring drawing in from it
	float rim = smoothstep(0.02, 0.0, abs(d - 0.96)) * smoothstep(0.7, 1.0, spread);
	float ring = smoothstep(0.025, 0.0, abs(d - 0.96 * (1.0 - warn * 0.92))) * step(0.001, warn);
	vec3 col = mix(vec3(0.06, 0.04, 0.035), vec3(0.16, 0.07, 0.08), noise(lp * 8.0 + seed));
	ALBEDO = col;
	ROUGHNESS = 0.35;
	SPECULAR = 0.6;
	EMISSION = vec3(0.75, 0.9, 0.3) * (roots * 0.22 + rim * 0.45 + ring * (0.8 + warn));
	ALPHA = clamp(roots * 1.0 + mid * 0.7 * spread + rim * 0.7 + ring, 0.0, 1.0) * fade;
}
"""
	return _rsh
