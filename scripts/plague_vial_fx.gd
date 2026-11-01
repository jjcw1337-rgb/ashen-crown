class_name PlagueVialFx
extends RefCounted
## Pestilence Vial's look (the Plague Doctor's Q; gameplay in plague.gd): the glass vial with its liquid sloshing
## inside, its tumbling flight, the landing ring, the shatter and the contaminated pool.
##
## The vial is assets/models/plague/vial.glb (built in code by tools/blender/plague/vial_build.py): its objects
## glass / liquid / cork / wax / twine / collar get the materials below by name. The liquid is a full inner volume
## cut by a plane in the shader (`plane_n`, `plane_d`, world space): its back faces read as the liquid's surface, and
## the plane leans against the vial's acceleration on a spring (`Slosh`), so the liquid lags behind every throw,
## spin and stop. The shatter flings the real glass, cut by the same script into `vial_shards.glb`.
##
## Recipes: three mixtures rotate (`RECIPES`: green, amber, violet, the colours on his bandolier) so throws in a row
## don't look the same. Everything here only draws; the damage is Plague's.

const VIAL_GLB := "res://assets/models/plague/vial.glb"
const SHARDS_GLB := "res://assets/models/plague/vial_shards.glb"
const RECIPES := [
	{"name": "green", "liq": Color(0.42, 0.95, 0.22), "deep": Color(0.05, 0.22, 0.03), "vapour": Color(0.55, 0.8, 0.45)},
	{"name": "amber", "liq": Color(1.0, 0.62, 0.12), "deep": Color(0.28, 0.1, 0.01), "vapour": Color(0.85, 0.7, 0.45)},
	{"name": "violet", "liq": Color(0.7, 0.34, 1.0), "deep": Color(0.13, 0.03, 0.22), "vapour": Color(0.7, 0.6, 0.85)},
]
const FLIGHT_SCALE := 2.2      # the vial in flight, so it reads from the game camera
const HAND_SCALE := 1.25

static func recipe(i: int) -> Dictionary:
	return RECIPES[posmod(i, RECIPES.size())]

# ---------------------------------------------------------------- the vial
static var _vial_scene: PackedScene
static var _shard_scene: PackedScene

## A vial filled with recipe `ri`. Its liquid material is in meta "liquid" (one per vial: the slosh plane is its own).
static func vial(ri: int) -> Node3D:
	var root := Node3D.new()
	var rc := recipe(ri)
	if _vial_scene == null and ResourceLoader.exists(VIAL_GLB):
		_vial_scene = load(VIAL_GLB)
	if _vial_scene == null:
		var m := MeshInstance3D.new()
		m.mesh = Geo.sph(0.04, 12)
		m.material_override = Mats.glow(rc["liq"], 1.5)
		root.add_child(m)
		return root
	var n: Node3D = _vial_scene.instantiate()
	root.add_child(n)
	var liq := ShaderMaterial.new()
	liq.shader = _liquid_shader()
	liq.set_shader_parameter("liq", rc["liq"])
	liq.set_shader_parameter("deep", rc["deep"])
	liq.set_shader_parameter("plane_n", Vector3.UP)
	liq.set_shader_parameter("plane_d", -999.0)
	for mi in n.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var k := m.name.to_lower()
		if k.begins_with("liquid"):
			m.material_override = liq
		elif k.begins_with("glass"):
			m.material_override = glass_mat()
		elif k.begins_with("cork"):
			m.material_override = _cork_mat()
		elif k.begins_with("wax"):
			m.material_override = _std(Color(0.32, 0.03, 0.03), 0.32, 0.0, 0.6)
		elif k.begins_with("twine"):
			m.material_override = _std(Color(0.55, 0.45, 0.3), 0.95, 0.0)
		elif k.begins_with("collar"):
			m.material_override = _std(Color(0.86, 0.62, 0.28), 0.32, 1.0)
	root.set_meta("liquid", liq)
	return root

static func _std(col: Color, rough: float, metal: float, clear := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.roughness = rough
	m.metallic = metal
	if clear > 0.0:
		m.clearcoat_enabled = true
		m.clearcoat = clear
	return m

static var _cork: StandardMaterial3D
static func _cork_mat() -> StandardMaterial3D:
	if _cork != null:
		return _cork
	_cork = _std(Color(0.5, 0.36, 0.22), 0.92, 0.0)
	var nt := NoiseTexture2D.new()
	var fn := FastNoiseLite.new()
	fn.frequency = 0.09
	fn.fractal_octaves = 3
	nt.noise = fn
	nt.width = 64
	nt.height = 64
	nt.seamless = true
	var g := Gradient.new()
	g.set_color(0, Color(0.32, 0.2, 0.11))
	g.set_color(1, Color(0.66, 0.5, 0.33))
	nt.color_ramp = g
	_cork.albedo_color = Color.WHITE
	_cork.albedo_texture = nt
	_cork.uv1_triplanar = true
	_cork.uv1_scale = Vector3(40, 40, 40)
	return _cork

static var _glass: ShaderMaterial
static func glass_mat() -> ShaderMaterial:
	if _glass != null:
		return _glass
	_glass = ShaderMaterial.new()
	_glass.shader = _glass_shader()
	return _glass

static var _gsh: Shader
static func _glass_shader() -> Shader:
	if _gsh != null:
		return _gsh
	_gsh = Shader.new()
	_gsh.code = """
shader_type spatial;
render_mode blend_mix, cull_back, depth_draw_never, specular_schlick_ggx;
uniform vec4 tint : source_color = vec4(0.82, 0.95, 0.88, 1.0);
uniform float fade = 1.0;
void fragment() {
	float f = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);
	ALBEDO = tint.rgb * 0.6;
	ROUGHNESS = 0.03;
	SPECULAR = 1.0;
	EMISSION = tint.rgb * f * 0.25;
	ALPHA = clamp(0.1 + f * 0.8, 0.0, 0.95) * fade;
}
"""
	return _gsh

static var _lsh: Shader
static func _liquid_shader() -> Shader:
	if _lsh != null:
		return _lsh
	_lsh = Shader.new()
	_lsh.code = """
shader_type spatial;
render_mode cull_disabled, depth_draw_opaque, specular_schlick_ggx;
uniform vec4 liq : source_color;
uniform vec4 deep : source_color;
uniform vec3 plane_n = vec3(0.0, 1.0, 0.0);
uniform float plane_d = -999.0;
uniform float wobble = 0.0;
varying vec3 wp;
void vertex() {
	wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}
void fragment() {
	// ripples on the surface follow the slosh
	float rip = sin(wp.x * 160.0 + TIME * 9.0) * sin(wp.z * 150.0 - TIME * 7.0) * 0.0012 * wobble;
	if (dot(wp, plane_n) - plane_d + rip > 0.0) {
		discard;
	}
	if (!FRONT_FACING) {
		// a back face seen through the cut is the liquid's top surface
		NORMAL = normalize((VIEW_MATRIX * vec4(plane_n, 0.0)).xyz);
		ALBEDO = liq.rgb * 0.55;
		EMISSION = liq.rgb * 0.95;
		ROUGHNESS = 0.08;
	} else {
		float f = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 2.0);
		ALBEDO = mix(deep.rgb, liq.rgb, 0.35 + 0.5 * f);
		EMISSION = liq.rgb * (0.35 + 0.9 * f);
		ROUGHNESS = 0.12;
	}
}
"""
	return _lsh

## The liquid's surface on a spring: it tilts against the vial's acceleration and settles back to level.
class Slosh:
	var n := Vector3.UP
	var nv := Vector3.ZERO
	var last := Vector3.ZERO
	var vel := Vector3.ZERO
	var started := false
	var wob := 0.0
	func step(node: Node3D, delta: float) -> void:
		if node == null or not node.has_meta("liquid") or delta <= 0.0:
			return
		var mat: ShaderMaterial = node.get_meta("liquid")
		var p := node.global_position
		if not started:
			last = p
			started = true
		var v := (p - last) / delta
		var acc := (v - vel) / delta
		vel = v
		last = p
		# the surface wants to lie perpendicular to gravity minus acceleration (what the liquid feels)
		var want := (Vector3(0, 9.8, 0) + acc.limit_length(60.0) * 0.12).normalized()
		var k := 90.0
		var c := 8.0
		nv += ((want - n) * k - nv * c) * delta
		n = (n + nv * delta).normalized()
		wob = clampf(lerpf(wob, nv.length() * 0.6, 0.2), 0.0, 1.0)
		# the plane passes through the liquid's middle (half full whatever way the bottle turns)
		var mid := node.global_transform * Vector3(0, 0.055, 0)
		mat.set_shader_parameter("plane_n", n)
		mat.set_shader_parameter("plane_d", n.dot(mid))
		mat.set_shader_parameter("wobble", wob)

# ---------------------------------------------------------------- flight
## One vial in the air: a tumbling arc from the hand to the landing point, its liquid sloshing, a thin vapour
## from the neck. `step` returns true when it lands.
class Flight:
	var node: Node3D
	var from: Vector3
	var to: Vector3
	var t := 0.0
	var dur := 0.6
	var spin_axis := Vector3.RIGHT
	var spins := 2.0
	var slosh := Slosh.new()
	var ri := 0
	func _init(root: Node3D, a: Vector3, b: Vector3, recipe_i: int, d: float) -> void:
		from = a
		to = b
		dur = d
		ri = recipe_i
		node = PlagueVialFx.vial(recipe_i)
		node.scale = Vector3.ONE * PlagueVialFx.FLIGHT_SCALE
		root.add_child(node)
		node.global_position = a
		var flat := (b - a) * Vector3(1, 0, 1)
		var fwd := flat.normalized() if flat.length() > 0.01 else Vector3.FORWARD
		spin_axis = fwd.cross(Vector3.UP).normalized()
		spins = 1.4 + flat.length() * 0.12
		# a faint vapour leaking from the neck, left behind in the air
		var rc := PlagueVialFx.recipe(recipe_i)
		var trail := Fx.aura(node, (rc["vapour"] as Color) * Color(1, 1, 1, 0.5), 18, 0.15, 0.035, 0.55, 0.3, 0.01, 25.0, Vector3(0, 0.14, 0), false)
		trail.local_coords = false
		var lamp := OmniLight3D.new()
		lamp.light_color = rc["liq"]
		lamp.light_energy = 0.9
		lamp.omni_range = 1.8
		lamp.position = Vector3(0, 0.06, 0)
		node.add_child(lamp)
	func step(delta: float) -> bool:
		if not is_instance_valid(node):
			return true
		t += delta
		var a := clampf(t / dur, 0.0, 1.0)
		var p := from.lerp(to, a)
		p.y += sin(a * PI) * (1.0 + from.distance_to(to) * 0.11)
		node.global_position = p
		# end over end, slowing a little as it falls
		var ang := spins * TAU * (a - 0.15 * a * a)
		node.global_basis = Basis(spin_axis, -ang) * Basis(Vector3.UP, a * 1.7)
		node.scale = Vector3.ONE * PlagueVialFx.FLIGHT_SCALE
		slosh.step(node, delta)
		return a >= 1.0

# ---------------------------------------------------------------- the landing ring
## Where the vial will land, for everyone: a thin rim in the recipe's colour with an inner ring closing in on it
## as the vial falls (`dur` = the flight).
static func landing_ring(root: Node3D, w: World, at: Vector3, r: float, ri: int, dur: float) -> void:
	var m := _ground_disc(w, at, r * 1.02, 10, 40, 0.05)
	var sh := ShaderMaterial.new()
	sh.shader = _ring_shader()
	sh.set_shader_parameter("col", recipe(ri)["liq"])
	sh.set_shader_parameter("prog", 0.0)
	m.material_override = sh
	root.add_child(m)
	m.global_position = Vector3(at.x, 0.0, at.z)
	var tw := m.create_tween()
	tw.tween_method(func(v: float) -> void: sh.set_shader_parameter("prog", v), 0.0, 1.0, dur)
	tw.tween_callback(m.queue_free)

static var _rsh: Shader
static func _ring_shader() -> Shader:
	if _rsh != null:
		return _rsh
	_rsh = Shader.new()
	_rsh.code = """
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled;
uniform vec4 col : source_color;
uniform float prog = 0.0;
varying vec2 lp;
void vertex() { lp = UV * 2.0 - 1.0; }
void fragment() {
	float d = length(lp);
	float rim = smoothstep(0.018, 0.0, abs(d - 0.97));
	float inner = smoothstep(0.014, 0.0, abs(d - (1.0 - prog) * 0.97)) * 0.55;
	float fill = smoothstep(1.0, 0.2, d) * 0.05 * prog;
	float dash = smoothstep(0.35, 0.5, fract(atan(lp.y, lp.x) * 12.0 / 3.14159 + TIME * 0.3)) * 0.5 + 0.5;
	ALBEDO = col.rgb * 0.7;
	ALPHA = clamp((rim * dash * 0.7 + inner + fill) * smoothstep(0.0, 0.08, prog + 0.02), 0.0, 1.0);
}
"""
	return _rsh

## A flat disc of rings laid over the ground (each vertex at the terrain's height plus `lift`), UV 0..1 across.
static func _ground_disc(w: World, at: Vector3, r: float, rings: int, segs: int, lift: float) -> MeshInstance3D:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var pts: Array[PackedVector3Array] = []
	var uvs: Array[PackedVector2Array] = []
	for k in rings + 1:
		var rr := r * float(k) / rings
		var ring := PackedVector3Array()
		var ru := PackedVector2Array()
		for i in segs:
			var ang := TAU * float(i) / segs
			var x := at.x + cos(ang) * rr
			var z := at.z + sin(ang) * rr
			var y := (w.height_at(x, z) if w != null else at.y) + lift
			ring.append(Vector3(x - at.x, y, z - at.z))
			ru.append(Vector2(0.5 + cos(ang) * 0.5 * float(k) / rings, 0.5 + sin(ang) * 0.5 * float(k) / rings))
		pts.append(ring)
		uvs.append(ru)
	for k in rings:
		for i in segs:
			var j := (i + 1) % segs
			var quad := [[k, i], [k + 1, i], [k + 1, j], [k, i], [k + 1, j], [k, j]]
			for q in quad:
				var kk: int = q[0]
				var ii: int = q[1]
				st.set_normal(Vector3.UP)
				st.set_uv(uvs[kk][ii])
				st.add_vertex(pts[kk][ii])
	var m := MeshInstance3D.new()
	m.mesh = st.commit()
	m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return m

# ---------------------------------------------------------------- the shatter
## The vial bursts where it lands: its real glass flies apart (with the cork and the seal), the liquid splashes up
## in a crown and droplets, a flash in its colour, a puff of vapour. `dir` is the way it was travelling.
static func shatter(root: Node3D, w: World, at: Vector3, r: float, ri: int, dir: Vector3, light: bool) -> void:
	var rc := recipe(ri)
	var col: Color = rc["liq"]
	var gy := w.height_at(at.x, at.z) if w != null else at.y
	var pos := Vector3(at.x, gy, at.z)
	var fwd := (dir * Vector3(1, 0, 1)).normalized() if (dir * Vector3(1, 0, 1)).length() > 0.01 else Vector3.FORWARD
	# the glass
	if _shard_scene == null and ResourceLoader.exists(SHARDS_GLB):
		_shard_scene = load(SHARDS_GLB)
	if _shard_scene != null:
		var src: Node3D = _shard_scene.instantiate()
		for mi in src.find_children("*", "MeshInstance3D", true, false):
			var m := MeshInstance3D.new()
			m.mesh = (mi as MeshInstance3D).mesh
			m.material_override = glass_mat()
			m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			var d := Debris.new()
			d.add_child(m)
			root.add_child(d)
			var loc: Vector3 = (mi as Node3D).position * FLIGHT_SCALE
			d.global_position = pos + Vector3(0, 0.12, 0) + loc
			d.scale = Vector3.ONE * FLIGHT_SCALE
			var out := Vector3(loc.x, 0, loc.z).normalized() if Vector2(loc.x, loc.z).length() > 0.001 else Vector3.RIGHT
			d.vel = out * randf_range(1.6, 4.2) + fwd * randf_range(0.3, 1.6) + Vector3(0, randf_range(1.5, 3.8), 0)
			d.spin = Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)).normalized() * randf_range(8.0, 20.0)
			d.floor_y = gy + 0.02
			d.life = randf_range(1.1, 1.8)
		src.free()
	# the cork, still in its wax, tumbling away
	var cork := Debris.new()
	var cm := MeshInstance3D.new()
	cm.mesh = Geo.cyl(0.011, 0.013, 0.03, 10)
	cm.material_override = _cork_mat()
	cork.add_child(cm)
	var wm := MeshInstance3D.new()
	wm.mesh = Geo.sph(0.016, 10)
	wm.position = Vector3(0, 0.018, 0)
	wm.material_override = _std(Color(0.32, 0.03, 0.03), 0.32, 0.0, 0.6)
	cork.add_child(wm)
	root.add_child(cork)
	cork.global_position = pos + Vector3(0, 0.25, 0)
	cork.scale = Vector3.ONE * FLIGHT_SCALE
	cork.vel = fwd * 2.2 + Vector3(randf_range(-1, 1), 4.2, randf_range(-1, 1))
	cork.spin = Vector3(13, 4, 7)
	cork.floor_y = gy + 0.03
	cork.life = 2.2
	# the liquid: a crown thrown up off the ground, droplets, a fine mist
	_crown(root, pos, col, r)
	_droplets(root, pos + Vector3(0, 0.12, 0), col, fwd, r)
	var mist := Fx.burst(root, pos + Vector3(0, 0.25, 0), (rc["vapour"] as Color) * Color(1, 1, 1, 0.55), 22, 1.6, 0.35, 0.9, false, 0.6, 85.0)
	mist.name = "vial_mist"
	Fx.burst(root, pos + Vector3(0, 0.2, 0), Color(0.9, 1.0, 0.95), 14, 4.0, 0.025, 0.35, true, -9.0)   # glints
	if light:
		Fx.flash(root, pos + Vector3(0, 0.6, 0), col, 3.5, 0.3, r * 1.8)

## The splash's crown: a thin sheet of liquid flaring up and out from the impact and breaking into fingers.
static func _crown(root: Node3D, pos: Vector3, col: Color, r: float) -> void:
	var m := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 1.0
	cm.bottom_radius = 0.55
	cm.height = 1.0
	cm.radial_segments = 40
	cm.rings = 6
	cm.cap_top = false
	cm.cap_bottom = false
	m.mesh = cm
	var sh := ShaderMaterial.new()
	sh.shader = _crown_shader()
	sh.set_shader_parameter("col", col)
	sh.set_shader_parameter("t", 0.0)
	m.material_override = sh
	m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(m)
	m.global_position = pos + Vector3(0, 0.12, 0)
	var size := clampf(r * 0.32, 0.5, 1.1)
	m.scale = Vector3(size * 0.2, 0.05, size * 0.2)
	var tw := m.create_tween().set_parallel(true)
	tw.tween_property(m, "scale", Vector3(size, size * 0.42, size), 0.28).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_method(func(v: float) -> void: sh.set_shader_parameter("t", v), 0.0, 1.0, 0.55)
	tw.chain().tween_callback(m.queue_free)

static var _csh: Shader
static func _crown_shader() -> Shader:
	if _csh != null:
		return _csh
	_csh = Shader.new()
	_csh.code = """
shader_type spatial;
render_mode blend_mix, cull_disabled, depth_draw_never, specular_schlick_ggx;
uniform vec4 col : source_color;
uniform float t = 0.0;
float h(float x) { return fract(sin(x * 91.7) * 43758.5); }
void fragment() {
	float ang = UV.x * 40.0;
	float fid = floor(ang);
	float fingers = mix(h(fid), h(fid + 1.0), smoothstep(0.0, 1.0, fract(ang)));
	// the sheet's top edge tears into fingers that break off as it ages
	float top = 1.0 - t * (0.4 + 0.7 * fingers);
	float y = 1.0 - UV.y;
	if (y > top) { discard; }
	float holes = step(0.82 - t * 0.5, h(fid * 7.3 + floor(y * 9.0)));
	if (holes > 0.5 && y > 0.25) { discard; }
	float f = pow(1.0 - clamp(abs(dot(NORMAL, VIEW)), 0.0, 1.0), 2.0);
	ALBEDO = col.rgb * 0.5;
	EMISSION = col.rgb * (0.6 + f * 0.8);
	ROUGHNESS = 0.06;
	SPECULAR = 0.9;
	ALPHA = (0.55 + f * 0.4) * (1.0 - smoothstep(0.6, 1.0, t)) * smoothstep(0.0, 0.08, y);
}
"""
	return _csh

## Droplets of the liquid: stretched along their flight, falling back.
static func _droplets(root: Node3D, pos: Vector3, col: Color, fwd: Vector3, r: float) -> void:
	var p := GPUParticles3D.new()
	p.amount = int(clampf(r * 18.0, 28.0, 70.0))
	p.lifetime = 0.75
	p.one_shot = true
	p.explosiveness = 0.95
	var pm := ParticleProcessMaterial.new()
	pm.direction = (Vector3.UP * 1.6 + fwd * 0.4).normalized()
	pm.spread = 62.0
	pm.initial_velocity_min = 2.2
	pm.initial_velocity_max = 5.8
	pm.gravity = Vector3(0, -11.0, 0)
	pm.scale_min = 0.5
	pm.scale_max = 1.4
	pm.particle_flag_align_y = true
	var g := Gradient.new()
	g.set_color(0, Color(col.r, col.g, col.b, 1.0))
	g.set_color(1, Color(col.r * 0.6, col.g * 0.6, col.b * 0.6, 0.0))
	var gt := GradientTexture1D.new()
	gt.gradient = g
	pm.color_ramp = gt
	p.process_material = pm
	var drop := SphereMesh.new()
	drop.radius = 0.022
	drop.height = 0.12
	drop.radial_segments = 6
	drop.rings = 4
	var dm := StandardMaterial3D.new()
	dm.vertex_color_use_as_albedo = true
	dm.albedo_color = Color(1, 1, 1)
	dm.emission_enabled = true
	dm.emission = col * 0.8
	dm.roughness = 0.05
	dm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	drop.material = dm
	p.draw_pass_1 = drop
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(p)
	p.global_position = pos
	p.emitting = true
	Fx._free_later(p, 1.5)

## A flung piece (a shard, the cork): ballistic, spinning, one bounce, then it settles and shrinks away.
class Debris extends Node3D:
	var vel := Vector3.ZERO
	var spin := Vector3.ZERO
	var floor_y := 0.0
	var life := 1.5
	var age := 0.0
	var bounced := false
	func _process(delta: float) -> void:
		age += delta
		vel.y -= 11.0 * delta
		global_position += vel * delta
		if spin.length() > 0.01:
			rotate(spin.normalized(), spin.length() * delta)
		if global_position.y < floor_y:
			global_position.y = floor_y
			if not bounced and vel.y < -1.0:
				vel = Vector3(vel.x * 0.35, -vel.y * 0.28, vel.z * 0.35)
				spin *= 0.4
				bounced = true
			else:
				vel = Vector3.ZERO
				spin *= 0.8
		if age > life:
			scale *= maxf(0.0, 1.0 - delta * 5.0)
			if scale.x < 0.02:
				queue_free()

# ---------------------------------------------------------------- the pool
## The contaminated pool: it creeps out from the splash over the ground, wet and veined, bubbling, with a thin
## vapour drifting off it; at the end it shrinks back and dries to a dark stain that fades. `end()` starts that.
class Pool extends Node3D:
	var mat: ShaderMaterial
	var wisps: GPUParticles3D
	var lamp: OmniLight3D
	var r := 2.6
	var age := 0.0
	var ending := -1.0
	func setup(w: World, at: Vector3, radius: float, ri: int, light: bool) -> void:
		r = radius
		var rc := PlagueVialFx.recipe(ri)
		var col: Color = rc["liq"]
		var disc := PlagueVialFx._ground_disc(w, at, radius * 1.12, 14, 56, 0.035)
		mat = ShaderMaterial.new()
		mat.shader = PlagueVialFx._pool_shader()
		mat.set_shader_parameter("liq", col)
		mat.set_shader_parameter("deep", rc["deep"])
		mat.set_shader_parameter("grow", 0.0)
		mat.set_shader_parameter("fade", 1.0)
		mat.set_shader_parameter("dry", 0.0)
		mat.set_shader_parameter("seed", randf() * 100.0)
		disc.material_override = mat
		add_child(disc)
		disc.position = Vector3(0, -at.y, 0)
		# vapour off the surface, drifting
		wisps = GPUParticles3D.new()
		wisps.amount = int(clampf(radius * radius * 5.0, 16.0, 60.0))
		wisps.lifetime = 2.4
		wisps.preprocess = 0.0
		var pm := ParticleProcessMaterial.new()
		pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
		pm.emission_sphere_radius = radius * 0.75
		pm.direction = Vector3.UP
		pm.spread = 25.0
		pm.initial_velocity_min = 0.15
		pm.initial_velocity_max = 0.45
		pm.gravity = Vector3(0.12, 0.08, 0.05)
		pm.scale_min = 0.8
		pm.scale_max = 1.8
		pm.angle_min = -180.0
		pm.angle_max = 180.0
		pm.angular_velocity_min = -20.0
		pm.angular_velocity_max = 20.0
		var vc: Color = rc["vapour"]
		var g := Gradient.new()
		g.set_color(0, Color(vc.r, vc.g, vc.b, 0.0))
		g.add_point(0.25, Color(vc.r, vc.g, vc.b, 0.22))
		g.add_point(0.7, Color(vc.r * 0.9, vc.g * 0.9, vc.b * 0.9, 0.12))
		g.set_color(g.get_point_count() - 1, Color(vc.r, vc.g, vc.b, 0.0))
		var gt := GradientTexture1D.new()
		gt.gradient = g
		pm.color_ramp = gt
		var sc := Curve.new()
		sc.add_point(Vector2(0, 0.4))
		sc.add_point(Vector2(1, 1.0))
		var sct := CurveTexture.new()
		sct.curve = sc
		pm.scale_curve = sct
		wisps.process_material = pm
		var q := QuadMesh.new()
		q.size = Vector2(0.9, 0.9)
		var qm := StandardMaterial3D.new()
		qm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		qm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		qm.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
		qm.vertex_color_use_as_albedo = true
		qm.albedo_texture = PlagueVialFx.wisp_tex()
		q.material = qm
		wisps.draw_pass_1 = q
		wisps.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		wisps.position = Vector3(0, 0.25, 0)
		add_child(wisps)
		if light:
			lamp = OmniLight3D.new()
			lamp.light_color = col
			lamp.light_energy = 0.0
			lamp.omni_range = radius * 1.4
			lamp.position = Vector3(0, 0.5, 0)
			add_child(lamp)
	func end() -> void:
		if ending < 0.0:
			ending = 0.0
			if wisps != null:
				wisps.emitting = false
	func _process(delta: float) -> void:
		age += delta
		var grow := 1.0 - pow(1.0 - clampf(age / 0.45, 0.0, 1.0), 3.0)
		if mat != null:
			mat.set_shader_parameter("grow", grow)
		if lamp != null:
			lamp.light_energy = 0.7 * grow * (0.85 + 0.15 * sin(age * 7.0))
		if ending >= 0.0:
			ending += delta
			var f := clampf(1.0 - ending / 0.7, 0.0, 1.0)
			if mat != null:
				mat.set_shader_parameter("fade", f)
				mat.set_shader_parameter("dry", clampf(ending / 0.7, 0.0, 1.0) * clampf(1.0 - (ending - 0.7) / 2.0, 0.0, 1.0))
			if lamp != null:
				lamp.light_energy *= f
			if ending > 3.0:
				queue_free()

static var _psh: Shader
static func _pool_shader() -> Shader:
	if _psh != null:
		return _psh
	_psh = Shader.new()
	_psh.code = """
shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_back, specular_schlick_ggx;
uniform vec4 liq : source_color;
uniform vec4 deep : source_color;
uniform float grow = 1.0;
uniform float fade = 1.0;
uniform float dry = 0.0;
uniform float seed = 0.0;
varying vec2 lp;
float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p); f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), f.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), f.x), f.y);
}
float fbm(vec2 p) {
	float v = 0.0; float a = 0.5;
	for (int i = 0; i < 4; i++) { v += a * noise(p); p *= 2.03; a *= 0.5; }
	return v;
}
// the liquid's height: slow swell, veins and the bubbles' domes (bub = the dome, rim = its bright edge)
float surf(vec2 p, out float veins, out float bub, out float rim) {
	vec2 q = p * 2.6 + seed;
	float sw = fbm(q + vec2(TIME * 0.12, -TIME * 0.08));
	float vn = 1.0 - abs(fbm(q * 1.9 + vec2(-TIME * 0.04, TIME * 0.06)) * 2.0 - 1.0);
	veins = pow(vn, 14.0);
	bub = 0.0;
	rim = 0.0;
	for (int k = 0; k < 2; k++) {
		float sc = 6.0 + float(k) * 5.0;
		vec2 c = p * sc + seed + float(k) * 17.0;
		vec2 ci = floor(c);
		vec2 cf = fract(c) - 0.5;
		float hsh = hash(ci);
		if (hsh < 0.62) { continue; }
		vec2 off = (vec2(hash(ci + 3.1), hash(ci + 7.7)) - 0.5) * 0.55;
		float ph = fract(TIME * (0.25 + hsh * 0.45) + hsh * 9.0);
		float rad = (0.06 + 0.3 * ph) * (0.6 + 0.6 * hash(ci + 1.3));
		float dd = length((cf - off) * vec2(1.0, 0.85 + 0.3 * hsh));
		float alive = 1.0 - smoothstep(0.82, 0.9, ph);
		bub = max(bub, smoothstep(rad, rad * 0.3, dd) * alive);
		rim = max(rim, smoothstep(0.05, 0.0, abs(dd - rad * 0.85)) * alive);
	}
	return sw * 0.6 + veins * 0.2 + bub * 0.45;
}
void vertex() { lp = UV * 2.0 - 1.0; }
void fragment() {
	float d = length(lp) * 1.12;
	float ang = atan(lp.y, lp.x);
	// the creeping edge: fingers that run out first, then fill in
	float fing = fbm(vec2(ang * 2.2, seed)) * 0.22 + fbm(lp * 5.0 + seed) * 0.1;
	float edge = grow * (0.8 + fing);
	float inside = smoothstep(edge, edge - 0.05, d);
	float halo = smoothstep(edge * 1.12 + 0.05, edge * 0.92, d);
	float veins; float bub; float rim;
	float ex = surf(lp + vec2(0.012, 0.0), veins, bub, rim);
	float ez = surf(lp + vec2(0.0, 0.012), veins, bub, rim);
	float hgt = surf(lp, veins, bub, rim);
	vec3 n = normalize(vec3(-(ex - hgt) * 6.0, 1.0, -(ez - hgt) * 6.0));
	NORMAL = normalize((VIEW_MATRIX * vec4(n, 0.0)).xyz);
	float wet = inside * fade;
	// a scum line where the liquid meets the ground
	float scum = smoothstep(0.035, 0.0, abs(d - edge + 0.03)) * (0.5 + 0.5 * noise(vec2(ang * 9.0, seed)));
	vec3 body = mix(deep.rgb * 0.35, deep.rgb * 0.9, hgt);
	body = mix(body, liq.rgb * 0.3 + vec3(0.03), scum * 0.5);
	ALBEDO = mix(vec3(0.03, 0.03, 0.025), body, wet);
	ROUGHNESS = mix(0.75, 0.03 + bub * 0.04, wet);
	SPECULAR = mix(0.2, 0.9, wet);
	EMISSION = liq.rgb * (0.02 + veins * 0.42 + rim * 0.4 + scum * 0.1) * wet;
	// the dark wet ground round it, and the stain left when it has dried
	float stain = max(halo * 0.35 * fade, dry * smoothstep(edge * 0.9, edge * 0.5, d) * 0.5);
	ALPHA = clamp(max(wet * (0.88 + 0.12 * hgt), stain), 0.0, 1.0);
}
"""
	return _psh

static var _wisp: Texture2D
## A soft, ragged puff for vapour (made once in code: noise inside a falloff).
static func wisp_tex() -> Texture2D:
	if _wisp != null:
		return _wisp
	var img := Image.create(64, 64, false, Image.FORMAT_RGBA8)
	var fn := FastNoiseLite.new()
	fn.frequency = 0.07
	fn.fractal_octaves = 4
	for y in 64:
		for x in 64:
			var d := Vector2(x - 31.5, y - 31.5).length() / 31.5
			var n := fn.get_noise_2d(x, y) * 0.5 + 0.5
			var a := clampf(smoothstep(1.0, 0.2, d) * (0.35 + 0.9 * n), 0.0, 1.0)
			img.set_pixel(x, y, Color(1, 1, 1, a))
	_wisp = ImageTexture.create_from_image(img)
	return _wisp
