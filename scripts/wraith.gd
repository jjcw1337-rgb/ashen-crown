class_name Wraith
extends RefCounted
## The Wraith class: a hovering, hooded spirit in a tattered robe. It reuses the knight's
## skeleton and animation joints (so Anim.pose, weapon grips, co-op puppets and the cape
## physics all work unchanged) and swaps the body for its own mesh and spectral shader.

const ROBE := 0
const HOOD := 1
const SLEEVE := 2
const MANTLE := 3
const CAPE := 4          # Knight._cape writes material 4

static var _shader: Shader

static func default_gear() -> Dictionary:
	return {"robe": Color(0.045, 0.05, 0.07), "trim": Color(0.3, 0.8, 1.0), "spirit": Color(0.35, 0.85, 1.0)}

## The Wraith's real body: the Meshy horned, chained wraith on the shared mocap system (tools/blender/wraith/
## prep_wraith_mocap.py: Meshy library clips, root motion taken out, the robe on six cloth panels hA..hF).
const MOCAP_GLB := "res://assets/models/wraith_mocap.glb"
## Clip ground speeds (m/s, measured from the planted foot): the stalking walk and the low glide.
const WALK_SPEED := 0.45
const GLIDE_SPEED := 4.27
const HOVER := 0.16            # it floats this far off the ground

static func mocap_ok() -> bool:
	return ResourceLoader.exists(MOCAP_GLB)

static func build(gear: Dictionary) -> Node3D:
	if mocap_ok():
		return build_mocap(gear)
	var root := Knight.build(Knight.default_gear())
	root.set_meta("wraith", true)
	rebuild_body(root, gear)
	_extras(root, gear)
	return root

static func build_mocap(gear: Dictionary) -> Node3D:
	var r := Knight.build_mocap(MOCAP_GLB, {
		"relaxed": ["idle", 0.0, "walk", WALK_SPEED, "run", GLIDE_SPEED],
		"combat": ["combat_idle", 0.0, "walk", WALK_SPEED, "run", GLIDE_SPEED],
		"meta": "wraith", "hair_run": 0.35})
	r.remove_meta("knight")
	r.set_meta("wraith", true)
	r.set("hover", HOVER)
	_spectral(r, gear)
	_mocap_extras(r, gear)
	return r

## The Meshy textures under the spectral shader (MOCAP_SHADER): its own shading, the cyan light in the robe's tears
## and its eyes, a cold rim, and the robe, shins and feet fraying into mist toward the hem (vertex colour R).
static func _spectral(r: Node3D, gear: Dictionary) -> void:
	var sh: Shader = load("res://scripts/wraith_mocap.gdshader")
	for mi in r.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		if m.mesh == null or m.get_parent() is BoneAttachment3D or m.has_meta("fx"):
			continue
		for si in m.mesh.get_surface_count():
			var src := m.mesh.surface_get_material(si) as StandardMaterial3D
			if src == null or src.albedo_texture == null:
				continue
			var mat := ShaderMaterial.new()
			mat.shader = sh
			mat.set_shader_parameter("albedo_tex", src.albedo_texture)
			if src.normal_texture != null:
				mat.set_shader_parameter("normal_tex", src.normal_texture)
				mat.set_shader_parameter("use_normal", true)
			if src.roughness_texture != null:
				mat.set_shader_parameter("rough_tex", src.roughness_texture)
				mat.set_shader_parameter("use_rough", true)
			m.set_surface_override_material(si, mat)
			var mats: Array = r.get_meta("spectral_mats") if r.has_meta("spectral_mats") else []
			mats.append(mat)
			r.set_meta("spectral_mats", mats)
	_tint(r, gear)

static func _tint(r: Node3D, gear: Dictionary) -> void:
	if not r.has_meta("spectral_mats"):
		return
	for mat in r.get_meta("spectral_mats"):
		(mat as ShaderMaterial).set_shader_parameter("spirit", gear["spirit"])

## Mist pouring off the hem, a cold light in the hood (its eyes light the horns and shoulders a little).
static func _mocap_extras(r: Node3D, gear: Dictionary) -> void:
	var J: Dictionary = r.get_meta("j")
	var head: Node3D = J.get("at_head", J["head"])
	var l := OmniLight3D.new()
	l.name = "EyeGlow"
	l.light_color = gear["spirit"]
	l.light_energy = 0.45
	l.omni_range = 0.45
	l.omni_attenuation = 2.0
	l.shadow_enabled = false
	l.position = Vector3(0, 0.12, -0.16)
	head.add_child(l)
	r.add_child(_hem_mist(gear, 0.34, 64))

static func rebuild_body(root: Node3D, gear: Dictionary) -> void:
	if str(root.get_meta("meshy", "")) == "wraith":
		_tint(root, gear)
		var gl := root.find_child("EyeGlow", true, false) as OmniLight3D
		if gl != null:
			gl.light_color = gear["spirit"]
		return
	var skel: Skeleton3D = root.get_node("Skeleton")
	var old := skel.get_node_or_null("Body")
	if old:
		old.name = "OldBody"
		old.queue_free()
	var mi := MeshInstance3D.new()
	mi.name = "Body"
	mi.mesh = _mesh()
	mi.material_override = material(gear)
	skel.add_child(mi)
	mi.skeleton = NodePath("..")
	if root.has_meta("eyes"):
		for e in root.get_meta("eyes"):
			if is_instance_valid(e):
				(e as MeshInstance3D).material_override = Mats.glow(gear["spirit"], 5.0)

static func material(g: Dictionary) -> ShaderMaterial:
	if _shader == null:
		_shader = Shader.new()
		_shader.code = SHADER
	var m := ShaderMaterial.new()
	m.shader = _shader
	m.set_shader_parameter("robe", g["robe"])
	m.set_shader_parameter("trim", g["trim"])
	m.set_shader_parameter("spirit", g["spirit"])
	return m

# ---------------------------------------------------------------- mesh
static var _cached: ArrayMesh

static func _mesh() -> ArrayMesh:
	if _cached != null:
		return _cached
	var b := Knight.Body.new()
	var hips := Knight.bi("hips")
	var torso := Knight.bi("torso")
	var head := Knight.bi("head")
	var lr := Knight.bi("leg_r")
	var ll := Knight.bi("leg_l")
	# the robe: from the shoulders to the ground, flaring out and trailing behind
	var robe := [
		[0.02, 0.0, 0.13, 0.47, 0.38], [0.2, 0.0, 0.1, 0.42, 0.34], [0.45, 0.0, 0.07, 0.36, 0.29],
		[0.7, 0.0, 0.04, 0.29, 0.23], [0.95, 0.0, 0.02, 0.22, 0.17], [1.12, 0.0, 0.01, 0.185, 0.145],
		[1.3, 0.0, 0.0, 0.195, 0.14], [1.45, 0.0, 0.0, 0.2, 0.135], [1.55, 0.0, 0.01, 0.15, 0.11],
		[1.62, 0.0, 0.015, 0.07, 0.065]]
	b.sweep(robe, 32, -PI * 1.5, PI * 0.5, ROBE, 1.0, 0.0, func(p: Vector3, _t):
		var up := smoothstep(0.95, 1.3, p.y)
		var sx := clampf(p.x / 0.35, -1.0, 1.0)
		var low := 1.0 - smoothstep(0.55, 0.95, p.y)
		var legs := low * 0.3
		return {torso: up, hips: (1.0 - up) * (1.0 - legs), lr: legs * (0.5 + 0.5 * sx), ll: legs * (0.5 - 0.5 * sx)})
	# a deep hood, open at the front
	var hood := [
		[1.5, 0.0, 0.035, 0.2, 0.185], [1.6, 0.0, 0.03, 0.165, 0.16], [1.72, 0.0, 0.02, 0.155, 0.158],
		[1.83, 0.0, 0.03, 0.14, 0.145], [1.92, 0.0, 0.055, 0.1, 0.105], [1.99, 0.0, 0.1, 0.045, 0.045],
		[2.03, 0.0, 0.15, 0.008, 0.008]]
	b.sweep(hood, 26, -PI * 0.5 + 0.8, -PI * 0.5 + TAU - 0.8, HOOD, 0.0, 0.0, func(p: Vector3, _t):
		var k := smoothstep(1.52, 1.66, p.y)
		return {torso: 1.0 - k, head: k})
	# a ragged shroud over the shoulders
	var mantle := [[1.24, 0.0, 0.0, 0.3, 0.22], [1.36, 0.0, 0.0, 0.29, 0.205], [1.47, 0.0, 0.0, 0.24, 0.17], [1.55, 0.0, 0.01, 0.14, 0.12]]
	b.sweep(mantle, 28, -PI * 1.5, PI * 0.5, MANTLE, 1.0, 0.0, func(_p, _t): return {torso: 1.0})
	# bell sleeves
	for side in [1, -1]:
		var x: float = 0.235 * side
		var sh := Knight.bi("sh_r" if side > 0 else "sh_l")
		var el := Knight.bi("el_r" if side > 0 else "el_l")
		var sleeve := [[0.86, x, 0.0, 0.12, 0.115], [0.98, x, 0.0, 0.095, 0.09], [1.18, x, 0.0, 0.066, 0.066],
			[1.36, x, 0.0, 0.07, 0.07], [1.5, x, 0.0, 0.085, 0.08], [1.56, x * 0.85, 0.0, 0.07, 0.07]]
		b.sweep(sleeve, 16, -PI * 1.5, PI * 0.5, SLEEVE, 1.0, 0.0, func(p: Vector3, _t):
			var k := smoothstep(1.12, 1.32, p.y)
			return {el: 1.0 - k, sh: k})
	# long tattered strips down the back, swinging on the cape bones
	Knight._cape(b)
	_cached = b.commit()
	return _cached

## Hood void, burning eyes, bony claws and the trail of spirit-mist under the robe.
static func _extras(root: Node3D, gear: Dictionary) -> void:
	var J: Dictionary = root.get_meta("j")
	var hd: Node3D = J["head"]
	var void_m := StandardMaterial3D.new()
	void_m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	void_m.albedo_color = Color(0.0, 0.0, 0.004)
	Models.P(hd, Geo.sph(0.125, 14), void_m, Vector3(0, 0.12, -0.01), Vector3.ZERO, Vector3(1.0, 1.15, 0.95))
	var eyes := []
	for sx in [-1, 1]:
		var e := Models.P(hd, Geo.sph(0.016, 8), Mats.glow(gear["spirit"], 5.0), Vector3(0.042 * sx, 0.125, -0.115), Vector3.ZERO, Vector3(1.4, 0.7, 1.0))
		eyes.append(e)
	root.set_meta("eyes", eyes)
	var bone := Mats.world(Color(0.72, 0.7, 0.62), Color(0.5, 0.48, 0.42), 0.7, 3.0, 0.0, Color.BLACK, false)
	for hand in ["hand_r", "hand_l"]:
		var h: Node3D = J[hand]
		Models.P(h, Geo.sph(0.03, 8), bone, Vector3(0, -0.02, 0), Vector3.ZERO, Vector3(1.0, 0.8, 1.3))
		for i in 4:
			var f := Models.P(h, Geo.cone(0.008, 0.085, 6), bone, Vector3((i - 1.5) * 0.014, -0.075, -0.02), Vector3(180 + 12, 0, (i - 1.5) * 9.0))
			f.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(_hem_mist(gear, 0.38, 48))

## Spirit-mist pouring off the hem (world-space particles, so it trails behind when it moves).
static func _hem_mist(gear: Dictionary, radius: float, amount: int) -> GPUParticles3D:
	var mist := GPUParticles3D.new()
	mist.name = "Mist"
	mist.amount = amount
	mist.lifetime = 1.6
	mist.local_coords = false
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_RING
	pm.emission_ring_axis = Vector3.UP
	pm.emission_ring_radius = radius
	pm.emission_ring_inner_radius = radius * 0.55
	pm.emission_ring_height = 0.05
	pm.direction = Vector3(0, -0.2, 1)
	pm.spread = 70.0
	pm.initial_velocity_min = 0.1
	pm.initial_velocity_max = 0.45
	pm.gravity = Vector3(0, 0.25, 0)
	pm.damping_min = 0.4
	pm.damping_max = 0.8
	pm.scale_min = 0.6
	pm.scale_max = 1.6
	var sc := Curve.new()
	sc.add_point(Vector2(0, 0.4))
	sc.add_point(Vector2(0.4, 1.0))
	sc.add_point(Vector2(1, 1.4))
	var sct := CurveTexture.new()
	sct.curve = sc
	pm.scale_curve = sct
	var g := Gradient.new()
	var sp: Color = gear["spirit"]
	g.set_color(0, Color(sp.r * 0.5, sp.g * 0.6, sp.b * 0.7, 0.0))
	g.add_point(0.25, Color(sp.r * 0.45, sp.g * 0.55, sp.b * 0.65, 0.22))
	g.set_color(1, Color(0.05, 0.06, 0.1, 0.0))
	var gt := GradientTexture1D.new()
	gt.gradient = g
	pm.color_ramp = gt
	mist.process_material = pm
	var q := QuadMesh.new()
	q.size = Vector2(0.32, 0.32)
	q.material = Mats.particle_mat(false, Color.WHITE)
	mist.draw_pass_1 = q
	mist.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mist.position = Vector3(0, 0.12, 0.05)
	return mist

# ---------------------------------------------------------------- shader
const SHADER := """
shader_type spatial;
render_mode cull_disabled, diffuse_burley, specular_schlick_ggx;
uniform vec3 robe : source_color = vec3(0.045, 0.05, 0.07);
uniform vec3 trim : source_color = vec3(0.3, 0.8, 1.0);
uniform vec3 spirit : source_color = vec3(0.35, 0.85, 1.0);
uniform float flash = 0.0;
varying float v_hem;
varying float v_tat;
varying float v_id;

float h21(vec2 p){ p = fract(p * vec2(123.34, 456.21)); p += dot(p, p + 45.32); return fract(p.x * p.y); }
float vn(vec2 p){ vec2 i = floor(p); vec2 f = fract(p); vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(h21(i), h21(i + vec2(1.0, 0.0)), u.x), mix(h21(i + vec2(0.0, 1.0)), h21(i + vec2(1.0, 1.0)), u.x), u.y); }
float fb(vec2 p){ float v = 0.0; float a = 0.5; for (int i = 0; i < 4; i++){ v += a * vn(p); p = p * 2.07 + 3.1; a *= 0.5; } return v; }

void vertex(){
	float id = floor(COLOR.r * 8.0);
	v_id = id;
	v_tat = (id == 1.0) ? 0.0 : 1.0;
	v_hem = (v_tat > 0.5) ? 1.0 - UV2.y : 0.0;
	// the lower cloth drifts as if under water
	float s = v_hem * v_hem;
	VERTEX.x += sin(TIME * 2.3 + UV2.x * 12.566 + VERTEX.y * 3.0) * 0.04 * s;
	VERTEX.z += (0.05 + sin(TIME * 1.7 + UV2.x * 9.0) * 0.035) * s;
	VERTEX.y += sin(TIME * 2.9 + UV2.x * 18.0) * 0.015 * s;
}

void fragment(){
	float n = fb(UV * vec2(5.0, 2.5));
	float strips = (v_id == 2.0) ? 9.0 : ((v_id == 3.0) ? 22.0 : 30.0);
	float strip = floor(UV2.x * strips);
	float rnd = h21(vec2(strip, v_id * 7.13 + 1.0));
	// ragged hem: every strip of cloth ends at a different length, edges flicker slightly
	float limit = (v_id == 3.0) ? 0.55 + 0.4 * rnd : 0.74 + 0.24 * rnd;
	limit -= 0.03 * vn(vec2(UV2.x * 80.0, TIME * 0.7));
	if (v_tat > 0.5 && v_hem > limit) {
		discard;
	}
	// the robe thins into mist towards the ground
	float thin = smoothstep(0.6, 1.0, v_hem) * ((v_id == 0.0) ? 1.0 : 0.6);
	if (h21(FRAGCOORD.xy * 0.731 + vec2(floor(TIME * 6.0) * 0.37, 0.0)) < thin * 0.3) {
		discard;
	}
	float folds = 0.75 + 0.25 * sin(UV.x * 38.0 + n * 5.0);
	vec3 alb = robe * (0.65 + 0.7 * n) * folds;
	float rim = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);
	// slow currents of spirit-light running up the cloth
	float flow = smoothstep(0.88, 1.0, sin(UV.y * 7.0 - TIME * 1.6 + n * 6.0 + strip * 0.7));
	vec3 em = spirit * (rim * 0.9 + flow * 0.35 * v_tat + thin * 0.45 * (0.6 + 0.4 * sin(TIME * 3.0 + UV2.x * 25.0)));
	// glowing frayed edges and the rim of the hood
	float edge = smoothstep(limit - 0.06, limit, v_hem) * v_tat;
	float hood_rim = (v_id == 1.0) ? max(smoothstep(0.08, 0.0, UV2.x), smoothstep(0.92, 1.0, UV2.x)) : 0.0;
	em += trim * (edge * 1.6 + hood_rim * 1.4);
	if (v_id == 1.0) {
		// the inside of the hood is pitch black
		alb *= FRONT_FACING ? 1.0 : 0.15;
		em *= FRONT_FACING ? 1.0 : 0.25;
	}
	ALBEDO = alb;
	ROUGHNESS = 0.92;
	SPECULAR = 0.2;
	EMISSION = em + vec3(flash);
}
"""
