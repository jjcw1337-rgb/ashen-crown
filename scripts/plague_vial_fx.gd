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

static var _gsh2: Shader
## The same glass with both faces drawn, in `tint` (the vat's thin curved panes show their backs as they tumble), its
## edges catching more light so the big panes read as they fly.
static func glass_mat_2side(tint: Color) -> ShaderMaterial:
	if _gsh2 == null:
		_gsh2 = Shader.new()
		_gsh2.code = _glass_shader().code.replace("cull_back", "cull_disabled").replace("EMISSION = tint.rgb * f * 0.25;", "EMISSION = tint.rgb * (f * 0.7 + 0.06);")
	var m := ShaderMaterial.new()
	m.shader = _gsh2
	m.set_shader_parameter("tint", tint)
	return m

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

# ---------------------------------------------------------------- the landing mark
## Where the vial will land, for everyone, without a UI ring: a ghost of the splash it will make (the Meshy puddle's
## own silhouette, faint, in the mixture's colour) firming up as the vial falls, and the vial's soft shadow darkening
## and tightening under it (`dur` = the flight).
const PUDDLE_ALBEDO := "res://assets/textures/plague/puddle_albedo.png"
const PUDDLE_NORMAL := "res://assets/textures/plague/puddle_normal.png"
const SPLASH_BOOK := "res://assets/textures/fx/vial_splash.png"     # tools/blender/plague/splash_flipbook.py, 5 x 4
const VAPOUR_BOOK := "res://assets/textures/fx/vapour.png"          # tools/blender/plague/vapour_flipbook.py, 6 x 6

static func _tex(path: String) -> Texture2D:
	return load(path) if ResourceLoader.exists(path) else null

static func landing_ring(root: Node3D, w: World, at: Vector3, r: float, ri: int, dur: float) -> void:
	var m := _ground_disc(w, at, r * 1.15, 10, 40, 0.05)
	var sh := ShaderMaterial.new()
	sh.shader = _ring_shader()
	sh.set_shader_parameter("col", recipe(ri)["liq"])
	sh.set_shader_parameter("prog", 0.0)
	sh.set_shader_parameter("rot", randf() * TAU)
	sh.set_shader_parameter("mask", _tex(PUDDLE_ALBEDO))
	m.material_override = sh
	root.add_child(m)
	m.global_position = Vector3(at.x, 0.0, at.z)
	m.set_meta("rot", sh.get_shader_parameter("rot"))
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
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled;
uniform vec4 col : source_color;
uniform float prog = 0.0;
uniform float rot = 0.0;
uniform sampler2D mask : source_color, filter_linear_mipmap;
varying vec2 lp;
void vertex() { lp = UV * 2.0 - 1.0; }
void fragment() {
	float c = cos(rot); float s = sin(rot);
	vec2 uv = vec2(c * lp.x - s * lp.y, s * lp.x + c * lp.y) * 0.5 + 0.5;
	float ghost = texture(mask, uv).a;
	float d = length(lp);
	// the vial's shadow: wide and faint while it's high, small and dark as it comes down
	float sr = mix(0.5, 0.12, prog);
	float shadow = smoothstep(sr, sr * 0.2, d) * mix(0.15, 0.55, prog);
	// the ghost of the splash: its silhouette firming up, edges first
	float g = ghost * smoothstep(0.0, 1.0, prog) * 0.32;
	float edge = ghost * (1.0 - smoothstep(0.0, 0.25, ghost)) * 0.0;
	vec3 tint = col.rgb * 0.55;
	ALBEDO = mix(vec3(0.0), tint, g / max(g + shadow, 0.001));
	ALPHA = clamp(g + shadow + edge, 0.0, 0.8) * smoothstep(0.0, 0.1, prog + 0.02);
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
	_splash(root, pos, col, r)
	_droplets(root, pos + Vector3(0, 0.12, 0), col, fwd, r)
	var mist := Fx.burst(root, pos + Vector3(0, 0.25, 0), (rc["vapour"] as Color) * Color(1, 1, 1, 0.55), 22, 1.6, 0.35, 0.9, false, 0.6, 85.0)
	mist.name = "vial_mist"
	Fx.burst(root, pos + Vector3(0, 0.2, 0), Color(0.9, 1.0, 0.95), 14, 4.0, 0.025, 0.35, true, -9.0)   # glints
	if light:
		Fx.flash(root, pos + Vector3(0, 0.6, 0), col, 3.5, 0.3, r * 1.8)

## The splash: a real liquid simulation (Blender FLIP, tools/blender/plague/splash_flipbook.py: the burst vial's
## contents thrown out and up into a crown of fingers) played as a flipbook on a camera-facing card, in the
## mixture's colour. Falls back to droplets only without the book.
static func _splash(root: Node3D, pos: Vector3, col: Color, r: float) -> void:
	var book := _tex(SPLASH_BOOK)
	if book == null:
		return
	var m := MeshInstance3D.new()
	var q := QuadMesh.new()
	var size := clampf(r * 0.95, 1.6, 3.0)
	q.size = Vector2(size, size)
	q.center_offset = Vector3(0, size * 0.32, 0)
	m.mesh = q
	var sh := ShaderMaterial.new()
	sh.shader = _flip_shader()
	sh.set_shader_parameter("book", book)
	sh.set_shader_parameter("grid", Vector2(5, 4))
	sh.set_shader_parameter("frames", 20.0)
	sh.set_shader_parameter("t", 0.0)
	sh.set_shader_parameter("tint", col)
	sh.set_shader_parameter("flip", 1.0 if randf() < 0.5 else -1.0)
	m.material_override = sh
	m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(m)
	m.global_position = pos + Vector3(0, 0.02, 0)
	var tw := m.create_tween()
	tw.tween_method(func(v: float) -> void: sh.set_shader_parameter("t", v), 0.0, 1.0, 0.7)
	tw.tween_callback(m.queue_free)

static var _fsh: Shader
## A flipbook on a card that turns to face the camera about its vertical axis (so the splash stands on the ground).
static func _flip_shader() -> Shader:
	if _fsh != null:
		return _fsh
	_fsh = Shader.new()
	_fsh.code = """
shader_type spatial;
render_mode blend_mix, cull_disabled, depth_draw_never, specular_schlick_ggx;
uniform sampler2D book : source_color, filter_linear_mipmap;
uniform vec2 grid = vec2(5.0, 4.0);
uniform float frames = 20.0;
uniform float t = 0.0;
uniform vec4 tint : source_color = vec4(0.4, 0.9, 0.2, 1.0);
uniform float flip = 1.0;
void vertex() {
	// face the camera, upright
	vec3 cam = (INV_VIEW_MATRIX[3].xyz - NODE_POSITION_WORLD);
	cam.y = 0.0;
	vec3 z = normalize(cam + vec3(0.0001));
	vec3 x = normalize(cross(vec3(0.0, 1.0, 0.0), z));
	vec3 wp = NODE_POSITION_WORLD + x * VERTEX.x * flip + vec3(0.0, 1.0, 0.0) * VERTEX.y;
	VERTEX = (inverse(MODEL_MATRIX) * vec4(wp, 1.0)).xyz;
	NORMAL = (inverse(MODEL_MATRIX) * vec4(z, 0.0)).xyz;
}
void fragment() {
	float f = min(floor(t * frames), frames - 1.0);
	vec2 cell = vec2(mod(f, grid.x), floor(f / grid.x));
	vec4 c = texture(book, (cell + UV) / grid);
	// the sim was rendered lime: keep its light and shape, take the mixture's colour
	float lum = dot(c.rgb, vec3(0.3, 0.55, 0.15));
	ALBEDO = tint.rgb * lum * 1.1;
	EMISSION = tint.rgb * lum * 0.35;
	ROUGHNESS = 0.08;
	SPECULAR = 0.8;
	ALPHA = c.a * (1.0 - smoothstep(0.75, 1.0, t));
}
"""
	return _fsh

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
		mat.set_shader_parameter("rot", randf() * TAU)
		mat.set_shader_parameter("albedo", PlagueVialFx._tex(PlagueVialFx.PUDDLE_ALBEDO))
		mat.set_shader_parameter("nrm", PlagueVialFx._tex(PlagueVialFx.PUDDLE_NORMAL))
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
		g.add_point(0.25, Color(vc.r, vc.g, vc.b, 0.4))
		g.add_point(0.7, Color(vc.r * 0.9, vc.g * 0.9, vc.b * 0.9, 0.25))
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
		q.size = Vector2(1.3, 1.3)
		var book := PlagueVialFx._tex(PlagueVialFx.VAPOUR_BOOK)
		if book != null:
			# Mantaflow vapour (tools/blender/plague/vapour_flipbook.py): each puff plays the book from its own frame
			var vm := StandardMaterial3D.new()
			vm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			vm.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
			vm.particles_anim_h_frames = 6
			vm.particles_anim_v_frames = 6
			vm.particles_anim_loop = true
			vm.vertex_color_use_as_albedo = true
			vm.albedo_texture = book
			vm.roughness = 1.0
			vm.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
			q.material = vm
			pm.anim_speed_min = 0.6
			pm.anim_speed_max = 1.0
			pm.anim_offset_min = 0.0
			pm.anim_offset_max = 1.0
		else:
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
## The pool: the Meshy puddle painting (tools/blender/plague/ground_decal.py: alpha keyed off its black, a normal map
## baked from its relief in Blender), turned at random per throw, revealed from the impact outward along the
## painting's own splatter (`grow`), retinted to the mixture, with a slow animated shimmer on its wet surface and
## the glow in its core breathing. `fade` shrinks it back, `dry` leaves a dark stain of its shape.
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
uniform float rot = 0.0;
uniform sampler2D albedo : source_color, filter_linear_mipmap;
uniform sampler2D nrm : hint_normal, filter_linear_mipmap;
varying vec2 lp;
float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p); f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), f.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), f.x), f.y);
}
void vertex() { lp = UV * 2.0 - 1.0; }
void fragment() {
	float c = cos(rot); float s = sin(rot);
	vec2 q = vec2(c * lp.x - s * lp.y, s * lp.x + c * lp.y) * 1.12;
	vec2 uv = q * 0.5 + 0.5;
	vec4 a = texture(albedo, uv);
	float d = length(q);
	// revealed from the middle out; the splatter's droplets at the rim arrive last
	float reach = grow * 1.05 + (noise(q * 6.0 + seed) - 0.5) * 0.12;
	float shown = smoothstep(reach, reach - 0.08, d);
	float shrink = smoothstep(fade * 1.1, fade * 1.1 - 0.15, d);
	float m = a.a * shown * shrink;
	// the painting's own colour, moved to the mixture: keep its light and dark, take the mixture's hue
	float lum = dot(a.rgb, vec3(0.3, 0.55, 0.15));
	float core = smoothstep(0.35, 0.7, lum);
	// green keeps the painting's own olive; amber and violet take its light and dark in their hue
	float gray = lum;
	vec3 hued = mix(deep.rgb * 0.5, liq.rgb * 0.55, smoothstep(0.05, 0.5, gray));
	float own = clamp(1.0 - distance(liq.rgb, vec3(0.42, 0.95, 0.22)) * 3.0, 0.0, 1.0);
	vec3 col = mix(hued, a.rgb * 0.8, own * 0.85);
	col = mix(col, a.rgb * 0.8, 0.2 * smoothstep(0.55, 0.9, lum));    // keep its foam and sheen
	// a slow shimmer on the wet surface on top of the baked relief
	vec3 n = texture(nrm, uv).rgb;
	float sh = noise(q * 9.0 + vec2(TIME * 0.35, -TIME * 0.27) + seed);
	NORMAL_MAP = normalize(n + vec3((sh - 0.5) * 0.12, (noise(q * 9.0 - vec2(TIME * 0.3, TIME * 0.2)) - 0.5) * 0.12, 0.0));
	NORMAL_MAP_DEPTH = 1.6;
	ALBEDO = col;
	ROUGHNESS = mix(0.18, 0.04, core);
	SPECULAR = 0.85;
	EMISSION = liq.rgb * core * (0.12 + 0.06 * sin(TIME * 2.4 + seed)) * shrink;
	// the dark stain its shape leaves as it dries
	float stain = a.a * dry * 0.55;
	ALPHA = clamp(max(m, stain), 0.0, 1.0);
	ALBEDO = mix(ALBEDO, vec3(0.03, 0.035, 0.02), (1.0 - m) * step(0.001, stain));
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
