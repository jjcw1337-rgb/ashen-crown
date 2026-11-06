class_name PlagueSwarmFx
extends RefCounted
## Swarmcraft's look (the Plague Doctor's E; gameplay in plague.gd): a living swarm of plague flies.
##
## The flies are one GPUParticles3D run by a particle shader (`SWARM_PROCESS`): each fly has its own orbit round the
## swarm's point (`target`), so the swarm stretches, twists and folds as it travels, thins at its edges (its
## boundary stays readable) and turns as one body. Each fly is the Meshy fly (game/heroes/plague/skills/swarmcraft/fly.glb: concept,
## image-to-3D, decimated to 900 triangles by tools/blender/prep_prop.py) drawn with its own painted texture in
## `MODEL_FLY_SHADER`: whatever of it reaches out past the body's sides beats as wings in the vertex shader, and the
## painting's green eyes glow; it faces where it flies. A dark haze of the Mantaflow vapour (PlagueSmoke) gives the
## cloud its body. `scatter` blows it apart for a moment, `go_home` spirals it back to the Plague Doctor's hand and
## frees it. He releases it from the Meshy reliquary (reliquary.glb: a gothic brass box, its lid thrown open), the
## same flies pouring out of it. Counts by the graphics preset: `COUNTS` (the browser build is capped at Medium).

const COUNTS := [400, 900, 1600, 3000]
const FLY := Color(0.06, 0.07, 0.05)
const EYE := Color(0.5, 1.0, 0.25)
const FLY_GLB := "res://game/heroes/plague/skills/swarmcraft/fly.glb"
const RELIQUARY_GLB := "res://game/heroes/plague/skills/swarmcraft/reliquary.glb"

## Swarmcraft's reliquary in his hand while he releases it: the Meshy box, lid open, a sick light inside and the
## flies pouring out of it.
static func reliquary() -> Node3D:
	var root := Node3D.new()
	if ResourceLoader.exists(RELIQUARY_GLB):
		var m: Node3D = ResCache.inst(RELIQUARY_GLB)
		root.add_child(m)
		m.position = Vector3(0, -0.045, 0)
	else:
		var brass := StandardMaterial3D.new()
		brass.albedo_color = Color(0.72, 0.52, 0.24)
		brass.metallic = 1.0
		brass.roughness = 0.35
		var box := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.09, 0.07, 0.07)
		box.mesh = bm
		box.material_override = brass
		root.add_child(box)
	var glow := OmniLight3D.new()
	glow.light_color = EYE
	glow.light_energy = 0.22
	glow.omni_range = 0.45
	glow.position = Vector3(0, 0.07, 0.03)
	root.add_child(glow)
	# the flies themselves boiling up out of it
	var pour := GPUParticles3D.new()
	pour.amount = 26
	pour.lifetime = 0.8
	pour.local_coords = false
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = 0.03
	pm.direction = Vector3.UP
	pm.spread = 40.0
	pm.initial_velocity_min = 0.5
	pm.initial_velocity_max = 1.4
	pm.gravity = Vector3(0, 0.4, 0)
	pm.angle_min = -180.0
	pm.angle_max = 180.0
	pm.scale_min = 1.4
	pm.scale_max = 2.0
	pour.process_material = pm
	pour.draw_pass_1 = _fly_mesh()
	pour.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(pour)
	pour.position = Vector3(0, 0.04, 0)
	return root

class Swarm extends Node3D:
	var flies: GPUParticles3D
	var haze: GPUParticles3D
	var mat: ShaderMaterial
	var target := Vector3.ZERO
	var radius := 3.0
	var scatter_t := 0.0
	var home_t := -1.0
	var home_node: Node3D = null
	var hum_t := 0.0
	var shadow: MeshInstance3D
	var world: World
	func setup(_w: World, from: Vector3, to: Vector3, r: float, quality: int) -> void:
		radius = r
		target = from
		global_position = Vector3.ZERO
		var n: int = PlagueSwarmFx.COUNTS[clampi(quality, 0, 3)]
		if OS.has_feature("web"):
			n = mini(n, 250)
		flies = GPUParticles3D.new()
		flies.amount = n
		flies.lifetime = 30.0
		flies.explosiveness = 0.85
		flies.local_coords = false
		flies.fixed_fps = 0
		flies.visibility_aabb = AABB(Vector3(-80, -10, -80), Vector3(160, 30, 160))
		mat = ShaderMaterial.new()
		mat.shader = PlagueSwarmFx._process_shader()
		mat.set_shader_parameter("target", from)
		mat.set_shader_parameter("radius", r)
		flies.process_material = mat
		flies.draw_pass_1 = PlagueSwarmFx._fly_mesh()
		flies.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(flies)
		flies.global_position = from
		flies.emitting = true
		# the cloud's body: a dark green-black haze that follows the swarm
		haze = GPUParticles3D.new()
		haze.amount = 34 if quality >= 2 else 20
		haze.lifetime = 1.6
		haze.local_coords = false
		var pm := ParticleProcessMaterial.new()
		pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
		pm.emission_sphere_radius = r * 0.55
		pm.gravity = Vector3.ZERO
		pm.initial_velocity_min = 0.1
		pm.initial_velocity_max = 0.5
		pm.scale_min = 1.8
		pm.scale_max = 3.2
		pm.angle_min = -180.0
		pm.angle_max = 180.0
		var g := Gradient.new()
		g.set_color(0, Color(0.05, 0.07, 0.04, 0.0))
		g.add_point(0.35, Color(0.06, 0.09, 0.04, 0.55))
		g.set_color(g.get_point_count() - 1, Color(0.05, 0.07, 0.04, 0.0))
		var gt := GradientTexture1D.new()
		gt.gradient = g
		pm.color_ramp = gt
		# the Mantaflow vapour, darkened, with a faint sick-green glow: a churning body for the cloud that reads
		# against a dark floor
		PlagueSmoke.anim(pm, false)
		haze.process_material = pm
		var q := QuadMesh.new()
		q.size = Vector2(1.4, 1.4)
		q.material = PlagueSmoke.mat(PlagueSmoke.VAPOUR, false, Color(0.05, 0.1, 0.025))
		haze.draw_pass_1 = q
		haze.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(haze)
		haze.global_position = from + Vector3(0, 0.8, 0)
		# its shadow on the ground: a soft dark blot that follows it, so the swarm's place reads from above
		shadow = MeshInstance3D.new()
		var qm2 := QuadMesh.new()
		qm2.size = Vector2(r * 2.2, r * 2.2)
		qm2.orientation = PlaneMesh.FACE_Y
		shadow.mesh = qm2
		var smat := StandardMaterial3D.new()
		smat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		smat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		smat.albedo_color = Color(0.0, 0.02, 0.0, 0.45)
		smat.albedo_texture = PlagueVialFx.wisp_tex()
		shadow.material_override = smat
		shadow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(shadow)
		world = _w
	func _process(delta: float) -> void:
		scatter_t = maxf(scatter_t - delta, 0.0)
		var home := 0.0
		if home_t >= 0.0:
			home_t += delta
			home = clampf(home_t / 1.1, 0.0, 1.0)
			if home_node != null and is_instance_valid(home_node):
				mat.set_shader_parameter("home_pos", home_node.global_position + Vector3(0, 1.3, 0))
			if home_t > 1.5:
				queue_free()
				return
		mat.set_shader_parameter("target", target)
		mat.set_shader_parameter("scatter", scatter_t / 1.5)
		mat.set_shader_parameter("home", home)
		if haze != null:
			haze.global_position = haze.global_position.lerp(target + Vector3(0, 0.8, 0), clampf(delta * 6.0, 0.0, 1.0))
		if shadow != null:
			var sp := haze.global_position if haze != null else target
			shadow.global_position = Vector3(sp.x, (world.height_at(sp.x, sp.z) if world != null else target.y) + 0.06, sp.z)
			shadow.transparency = clampf(home * 1.5 + scatter_t / 1.5 * 0.6, 0.0, 1.0)
			if home > 0.0:
				haze.emitting = false
		hum_t -= delta
		if hum_t <= 0.0 and home_t < 0.0:
			hum_t = randf_range(0.9, 1.6)
			Sfx.play_at("drip", target, -16.0, 2.4)

static func redirect(node: Node, _to: Vector3) -> void:
	if is_instance_valid(node) and node is Swarm:
		(node as Swarm).scatter_t = maxf((node as Swarm).scatter_t, 0.25)    # a ripple through it as it turns

static func scatter(node: Node) -> void:
	if is_instance_valid(node) and node is Swarm:
		(node as Swarm).scatter_t = 1.5

static func go_home(node: Node, h: Hero) -> void:
	if is_instance_valid(node) and node is Swarm:
		var s := node as Swarm
		s.home_t = 0.0
		s.home_node = h
		s.mat.set_shader_parameter("home_pos", h.global_position + Vector3(0, 1.3, 0))

## A bite: a few flies peel off onto the foe, a fleck of green.
static func bite(node: Node, e: Node3D) -> void:
	if not is_instance_valid(node) or not (node is Swarm) or not is_instance_valid(e):
		return
	var hgt: float = float(e.get("height")) if e.get("height") != null else 1.0
	Fx.burst((node as Swarm), e.global_position + Vector3(randf_range(-0.2, 0.2), hgt * randf_range(0.8, 1.6), randf_range(-0.2, 0.2)), Color(0.55, 0.9, 0.3), 4, 0.8, 0.03, 0.35, true, -2.0)

static var _psh: Shader
static func _process_shader() -> Shader:
	if _psh != null:
		return _psh
	_psh = Shader.new()
	_psh.code = """
shader_type particles;
uniform vec3 target;
uniform float radius = 3.0;
uniform float core = 0.0;
uniform float tall = 1.3;
uniform float scatter = 0.0;
uniform float home = 0.0;
uniform vec3 home_pos;
float hash(float n) { return fract(sin(n) * 43758.5453); }
void start() {
	if (RESTART_POSITION) {
		float h1 = hash(float(INDEX) * 1.31);
		float h2 = hash(float(INDEX) * 7.17);
		float h3 = hash(float(INDEX) * 3.77);
		TRANSFORM[3].xyz = EMISSION_TRANSFORM[3].xyz + (vec3(h1, h2, h3) - 0.5) * 0.25;
	}
	if (RESTART_VELOCITY) {
		VELOCITY = (vec3(hash(float(INDEX) * 2.1), hash(float(INDEX) * 5.3), hash(float(INDEX) * 9.7)) - 0.5) * 6.0 + vec3(0.0, 1.5, 0.0);
	}
	CUSTOM = vec4(hash(float(INDEX) * 0.73), hash(float(INDEX) * 4.41), 0.0, 0.0);
}
void process() {
	float h = CUSTOM.x;
	float k = CUSTOM.y;
	vec3 p = TRANSFORM[3].xyz;
	// its own looping orbit round the swarm's point: a lumpy, breathing cloud, densest in the middle
	float t = TIME * (0.6 + h * 0.9) + h * 60.0;
	float rr = radius * (0.15 + 0.85 * pow(k, 1.5));    // dense in the middle, thinning to its edge
	vec2 ox = vec2(sin(t * 1.3 + h * 7.0) * rr * (0.55 + 0.45 * sin(t * 0.37 + k * 5.0)),
		cos(t * 1.1 + k * 11.0) * rr * (0.55 + 0.45 * cos(t * 0.41 + h * 4.0)));
	// a hollow core: the knot harrying a man flies round his head and shoulders, not inside his body
	ox += normalize(ox + vec2(0.0001)) * core;
	vec3 orbit = target + vec3(ox.x, 0.45 + h * tall + sin(t * 2.1 + k * 3.0) * 0.35, ox.y);
	vec3 want = mix(orbit, home_pos + (vec3(h, k, fract(h * 9.0)) - 0.5) * 0.15 * (1.0 - home), home);
	vec3 acc = (want - p) * mix(7.0, 14.0, home) - VELOCITY * 1.8;
	// buzz: each fly jitters on its own
	acc += vec3(sin(TIME * 23.0 + h * 90.0), sin(TIME * 19.0 + k * 70.0), cos(TIME * 21.0 + h * 40.0)) * 9.0;
	acc += normalize(p - target + vec3(0.001)) * scatter * 60.0;
	VELOCITY += acc * DELTA;
	float sp = length(VELOCITY);
	if (sp > 11.0) { VELOCITY *= 11.0 / sp; }
	// face where it flies
	vec3 f = normalize(VELOCITY + vec3(0.0, 0.0001, 0.0));
	vec3 r = normalize(cross(vec3(0.0, 1.0, 0.0), f) + vec3(0.0001, 0.0, 0.0));
	vec3 u = cross(f, r);
	float s = 4.0 * (1.0 - home * home * 0.8);    // larger than life (the 4.5 cm fly at ~18 cm), so the swarm reads from the game camera
	TRANSFORM[0].xyz = r * s;
	TRANSFORM[1].xyz = u * s;
	TRANSFORM[2].xyz = f * s;
}
"""
	return _psh

static var _fly: Mesh
## One fly: the Meshy model with `MODEL_FLY_SHADER` (its painted texture, wings beating); without the model, one
## made in code (~6 cm: body and head (COLOR.r = 0, eyes COLOR.g = 1), two wings (COLOR.r = 1, side in COLOR.b)).
static func _fly_mesh() -> Mesh:
	if _fly != null:
		return _fly
	if ResourceLoader.exists(FLY_GLB):
		var src: Node3D = ResCache.inst(FLY_GLB)
		var mis := src.find_children("*", "MeshInstance3D", true, false)
		if not mis.is_empty():
			var mi := mis[0] as MeshInstance3D
			var am := mi.mesh.duplicate() as ArrayMesh
			if am != null:
				var albedo: Texture2D = null
				var m0 := mi.get_active_material(0)
				if m0 is BaseMaterial3D:
					albedo = (m0 as BaseMaterial3D).albedo_texture
				var sm := ShaderMaterial.new()
				sm.shader = _model_fly_shader()
				sm.set_shader_parameter("albedo", albedo)
				for i in am.get_surface_count():
					am.surface_set_material(i, sm)
				_fly = am
		src.free()
		if _fly != null:
			return _fly
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	# body: an ellipsoid along +z (the way it flies), a smaller head in front
	_ellipsoid(st, Vector3(0, 0, -0.008), Vector3(0.011, 0.01, 0.022), Color(0, 0, 0, 1))
	_ellipsoid(st, Vector3(0, 0.001, 0.019), Vector3(0.008, 0.008, 0.007), Color(0, 0, 0, 1))
	_ellipsoid(st, Vector3(0.006, 0.003, 0.022), Vector3(0.004, 0.004, 0.004), Color(0, 1, 0, 1))
	_ellipsoid(st, Vector3(-0.006, 0.003, 0.022), Vector3(0.004, 0.004, 0.004), Color(0, 1, 0, 1))
	# wings: from the back, swept back
	for side in [-1.0, 1.0]:
		var a := Vector3(side * 0.004, 0.008, 0.004)
		var b := Vector3(side * 0.034, 0.012, -0.012)
		var c := Vector3(side * 0.026, 0.011, -0.03)
		var d := Vector3(side * 0.004, 0.008, -0.01)
		var col := Color(1, 0, 0.5 + 0.5 * side, 1)
		for tri in [[a, b, c], [a, c, d]]:
			for v in tri:
				st.set_color(col)
				st.set_normal(Vector3.UP)
				st.set_uv(Vector2(absf((v as Vector3).x) / 0.034, -(v as Vector3).z / 0.03 + 0.4))
				st.add_vertex(v)
	var m := st.commit()
	var sm := ShaderMaterial.new()
	sm.shader = _fly_shader()
	m.surface_set_material(0, sm)
	_fly = m
	return _fly

static func _ellipsoid(st: SurfaceTool, c: Vector3, r: Vector3, col: Color) -> void:
	var seg := 6
	var rings := 4
	for i in rings:
		for j in seg:
			var pts := []
			for q in [[i, j], [i + 1, j], [i + 1, j + 1], [i, j], [i + 1, j + 1], [i, j + 1]]:
				var th := PI * float(q[0]) / rings
				var ph := TAU * float(q[1]) / seg
				var n := Vector3(sin(th) * cos(ph), cos(th), sin(th) * sin(ph))
				pts.append([c + n * r, n])
			for pv in pts:
				st.set_color(col)
				st.set_normal(pv[1])
				st.set_uv(Vector2.ZERO)
				st.add_vertex(pv[0])

static var _msh: Shader
## The Meshy fly (4.5 cm, head toward +z, body ~1 cm wide): its painting; everything past the body's sides above its
## belly is wing, beating about the body's long axis on each fly's own phase; the painting's green eyes glow.
static func _model_fly_shader() -> Shader:
	if _msh != null:
		return _msh
	_msh = Shader.new()
	_msh.code = """
shader_type spatial;
render_mode cull_disabled, specular_schlick_ggx;
uniform sampler2D albedo : source_color, filter_linear_mipmap;
varying float wing;
void vertex() {
	float side = VERTEX.x < 0.0 ? -1.0 : 1.0;
	wing = smoothstep(0.005, 0.011, abs(VERTEX.x)) * smoothstep(-0.006, -0.001, VERTEX.y);
	float a = sin(TIME * 95.0 + INSTANCE_CUSTOM.x * 60.0) * 0.95 * side * wing;
	vec2 p = vec2(VERTEX.x - side * 0.005, VERTEX.y - 0.002);
	float ca = cos(a); float sa = sin(a);
	VERTEX.xy = vec2(p.x * ca - p.y * sa + side * 0.005, p.x * sa + p.y * ca + 0.002);
	NORMAL.xy = vec2(NORMAL.x * ca - NORMAL.y * sa, NORMAL.x * sa + NORMAL.y * ca);
}
void fragment() {
	vec4 c = texture(albedo, UV);
	float eye = smoothstep(0.04, 0.16, c.g - max(c.r, c.b));
	ALBEDO = c.rgb * mix(1.0, 1.35, wing);
	// the eyes glow, and a faint sheen of the same sick green on the body, so the swarm sparkles in the dark
	EMISSION = vec3(0.35, 0.9, 0.18) * (eye * 2.2 + 0.035);
	METALLIC = mix(0.3, 0.0, wing);
	ROUGHNESS = mix(0.32, 0.18, wing);
	SPECULAR = 0.7;
}
"""
	return _msh

static var _fsh: Shader
static func _fly_shader() -> Shader:
	if _fsh != null:
		return _fsh
	_fsh = Shader.new()
	_fsh.code = """
shader_type spatial;
render_mode cull_disabled, specular_schlick_ggx;
varying float wing;
varying float eye;
void vertex() {
	wing = COLOR.r;
	eye = COLOR.g;
	if (wing > 0.5) {
		// the wing beat: each fly on its own phase
		float side = COLOR.b * 2.0 - 1.0;
		float ph = TIME * 95.0 + INSTANCE_CUSTOM.x * 60.0;
		float a = sin(ph) * 1.1 * side;
		float x = VERTEX.x;
		float y = VERTEX.y - 0.008;
		VERTEX.x = x * cos(a) - y * sin(a);
		VERTEX.y = x * sin(a) + y * cos(a) + 0.008;
	}
}
void fragment() {
	if (wing > 0.5) {
		// veined, smoky, translucent
		float v = abs(sin(UV.x * 18.0 + UV.y * 6.0)) * 0.5 + abs(sin(UV.y * 22.0)) * 0.3;
		ALBEDO = vec3(0.16, 0.18, 0.15) + vec3(v * 0.08);
		ROUGHNESS = 0.25;
		SPECULAR = 0.8;
		ALPHA = 0.45;
	} else {
		ALBEDO = mix(vec3(0.04, 0.05, 0.035), vec3(0.3, 0.6, 0.15), eye);
		EMISSION = vec3(0.35, 0.9, 0.18) * eye * 1.5;
		METALLIC = 0.3;
		ROUGHNESS = 0.3;
	}
}
"""
	return _fsh
