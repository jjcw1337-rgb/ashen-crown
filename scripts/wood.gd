class_name Wood
extends RefCounted
## Wood made in code: logs (the resources' models and icons), the end grain of a cut, stumps, the notch an axe
## bites into a trunk, and the chips, splinters and debris that fly off it (Harvest). Bark is Flora's bark shader
## so a log matches the tree it came from; the cut faces are END_GRAIN_SHADER (growth rings, rays, checks, a
## fresh pale heart that greys with age; Ashen Heartwood's rings glow like coals).

const END_GRAIN_SHADER := """
shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;
uniform vec3 heart : source_color = vec3(0.78, 0.6, 0.4);
uniform vec3 sap : source_color = vec3(0.86, 0.72, 0.5);
uniform vec3 bark : source_color = vec3(0.24, 0.18, 0.12);
uniform float rings = 14.0;
uniform float age = 0.0;          // 0 fresh, 1 weathered grey
uniform float ember = 0.0;        // Ashen Heartwood: the rings smoulder
uniform float seed = 0.0;
float h21(vec2 p){ p = fract(p * vec2(123.34, 456.21)); p += dot(p, p + 45.32); return fract(p.x * p.y); }
float vn(vec2 p){ vec2 i = floor(p); vec2 f = fract(p); vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(h21(i), h21(i + vec2(1.0, 0.0)), u.x), mix(h21(i + vec2(0.0, 1.0)), h21(i + vec2(1.0, 1.0)), u.x), u.y); }
void fragment(){
	vec2 p = UV * 2.0 - 1.0;                       // the disc's UV: centre (0.5, 0.5), rim at radius 1
	float r = length(p);
	float a = atan(p.y, p.x);
	float wob = vn(vec2(a * 2.0 + seed, r * 3.0)) * 0.08 + vn(p * 6.0 + seed) * 0.03;
	float rr = (r + wob) * rings;
	float ring = smoothstep(0.0, 0.35, fract(rr)) * smoothstep(1.0, 0.7, fract(rr));   // latewood lines
	float ray = smoothstep(0.92, 1.0, vn(vec2(a * 40.0 + seed, r * 2.0)));             // medullary rays
	float check = smoothstep(0.985, 1.0, vn(vec2(a * 9.0 + seed * 3.0, 0.5))) * smoothstep(0.15, 0.9, r);  // drying cracks
	vec3 c = mix(heart, sap, smoothstep(0.55, 0.85, r));
	c *= 0.82 + 0.18 * ring;
	c = mix(c, c * 0.72, ray * 0.6);
	c = mix(c, c * 0.25, check);
	c *= 0.9 + vn(p * 30.0) * 0.12;                 // saw marks and fibre
	c = mix(c, bark, smoothstep(0.9, 0.97, r));     // the bark round the edge
	c = mix(c, vec3(dot(c, vec3(0.33))) * 0.75, age * 0.8);
	ALBEDO = c;
	ROUGHNESS = 0.9;
	SPECULAR = 0.2;
	if (ember > 0.0) {
		float glow = (1.0 - ring) * smoothstep(0.85, 0.2, r) + check * 2.0;
		EMISSION = vec3(1.0, 0.35, 0.06) * glow * ember * (0.75 + 0.25 * sin(TIME * 2.0 + r * 9.0));
	}
}
"""

## Bark lit from inside by cracks that breathe (Ashen Heartwood; its logs and its tree).
const EMBER_BARK_SHADER := """
shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;
uniform vec3 col : source_color = vec3(0.06, 0.05, 0.05);
uniform vec3 hot : source_color = vec3(1.0, 0.36, 0.07);
uniform float heat = 1.0;
global uniform float snow_amt;
float h21(vec2 p){ p = fract(p * vec2(123.34, 456.21)); p += dot(p, p + 45.32); return fract(p.x * p.y); }
float vn(vec2 p){ vec2 i = floor(p); vec2 f = fract(p); vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(h21(i), h21(i + vec2(1.0, 0.0)), u.x), mix(h21(i + vec2(0.0, 1.0)), h21(i + vec2(1.0, 1.0)), u.x), u.y); }
varying vec3 wp;
varying vec3 wn;
void vertex(){ wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; wn = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz); }
void fragment(){
	vec2 uv = vec2(UV.x * 7.0, UV.y * 1.6);
	float wob = vn(vec2(UV.x * 3.0, UV.y * 0.8)) * 1.6;
	float ridge = abs(fract(uv.x + wob) - 0.5) * 2.0;
	float fis = smoothstep(0.8, 0.97, ridge);
	float plates = vn(uv * vec2(1.0, 2.5) + 3.0);
	vec3 c = col * (0.7 + plates * 0.5);
	c = mix(c, vec3(0.75, 0.75, 0.78), snow_amt * smoothstep(0.3, 0.7, wn.y) * 0.8);
	ALBEDO = c;
	ROUGHNESS = 0.95;
	float breathe = 0.65 + 0.35 * sin(TIME * 1.3 + wp.y * 2.0 + vn(wp.xz) * 6.0);
	EMISSION = hot * fis * heat * breathe * 2.2;
}
"""

static var _mats := {}
static var _meshes := {}

static func _shader(key: String, code: String) -> Shader:
	var k := "wood_" + key
	if not _mats.has(k):
		var s := Shader.new()
		s.code = code
		_mats[k] = s
	return _mats[k]

## The end grain of a base's wood (ShaderMaterial, shared per base and age).
static func end_grain(base_id: String, aged := false) -> ShaderMaterial:
	var key := "grain_%s_%d" % [base_id, int(aged)]
	if not _mats.has(key):
		var b: Dictionary = Data.BASES.get(base_id, Data.BASES["oak_log"])
		var m := ShaderMaterial.new()
		m.shader = _shader("grain", END_GRAIN_SHADER)
		var hc: Color = b.get("heart", Color(0.78, 0.6, 0.4))
		m.set_shader_parameter("heart", hc)
		m.set_shader_parameter("sap", hc.lightened(0.15))
		m.set_shader_parameter("bark", b.get("bark", Color(0.24, 0.18, 0.12)))
		m.set_shader_parameter("rings", 18.0 if base_id == "oak_log" else (11.0 if base_id == "pine_log" else 24.0))
		m.set_shader_parameter("age", 0.6 if aged else 0.0)
		m.set_shader_parameter("ember", 1.0 if b.get("glow", false) else 0.0)
		m.set_shader_parameter("seed", float(base_id.hash() % 97))
		_mats[key] = m
	return _mats[key]

## The bark of a base's wood: Flora's bark (oak, pine) or the ember bark (heartwood).
static func bark(base_id: String) -> Material:
	var b: Dictionary = Data.BASES.get(base_id, Data.BASES["oak_log"])
	if b.get("glow", false):
		var key := "emberbark"
		if not _mats.has(key):
			var m := ShaderMaterial.new()
			m.shader = _shader("emberbark", EMBER_BARK_SHADER)
			_mats[key] = m
		return _mats[key]
	var bc: Color = b.get("bark", Color(0.24, 0.18, 0.12))
	return Flora.bark_mat(bc.lightened(0.15), bc.darkened(0.45), 0.25 if base_id == "oak_log" else 0.1)

## A tube of bark from y=0 to y=len along +Y, slightly irregular, with a disc of end grain at each end.
static func _log_mesh(base_id: String, radius: float, length: float, seed_v: int) -> ArrayMesh:
	var key := "log_%s_%.2f_%.2f_%d" % [base_id, radius, length, seed_v]
	if _meshes.has(key):
		return _meshes[key]
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_v * 7919 + 31
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var sides := 12
	var segs := 5
	var prof := []
	for k in sides:
		prof.append(1.0 + rng.randf_range(-0.07, 0.07))
	for j in segs + 1:
		var y := length * j / float(segs)
		var bulge := 1.0 + sin(j * 1.7 + seed_v) * 0.03
		for k in sides + 1:
			var a := TAU * k / float(sides)
			var rr: float = radius * float(prof[k % sides]) * bulge
			st.set_normal(Vector3(cos(a), 0, sin(a)))
			st.set_uv(Vector2(k / float(sides) * 1.4, y * 2.2))
			st.set_color(Color(1, 1, 1, 0))
			st.add_vertex(Vector3(cos(a) * rr, y, sin(a) * rr))
	for j in segs:
		for k in sides:
			var i0 := j * (sides + 1) + k
			var i1 := i0 + sides + 1
			st.add_index(i0)
			st.add_index(i1)
			st.add_index(i0 + 1)
			st.add_index(i0 + 1)
			st.add_index(i1)
			st.add_index(i1 + 1)
	var m := ArrayMesh.new()
	st.commit(m)
	m.surface_set_material(0, bark(base_id))
	# the two cut ends
	for end in [0, 1]:
		var cs := SurfaceTool.new()
		cs.begin(Mesh.PRIMITIVE_TRIANGLES)
		var y2: float = length * end
		var nrm := Vector3(0, 1 if end == 1 else -1, 0)
		cs.set_normal(nrm)
		cs.set_uv(Vector2(0.5, 0.5))
		cs.add_vertex(Vector3(0, y2, 0))
		for k in sides + 1:
			var a := TAU * k / float(sides)
			var rr: float = radius * float(prof[k % sides]) * 0.995
			cs.set_normal(nrm)
			cs.set_uv(Vector2(0.5 + cos(a) * 0.5, 0.5 + sin(a) * 0.5))
			cs.add_vertex(Vector3(cos(a) * rr, y2, sin(a) * rr))
		for k in sides:
			cs.add_index(0)
			if end == 1:
				cs.add_index(k + 2)
				cs.add_index(k + 1)
			else:
				cs.add_index(k + 1)
				cs.add_index(k + 2)
		cs.commit(m)
		m.surface_set_material(m.get_surface_count() - 1, end_grain(base_id))
	_meshes[key] = m
	return m

## A resource's model: a bundle of three logs lying down (inventory icon and on the ground), tied with a cord.
static func item_model(base_id: String) -> Node3D:
	var root := Node3D.new()
	var r := 0.085 if base_id != "pine_log" else 0.075
	var ln := 0.62 if base_id != "heartwood" else 0.5
	var spots := [Vector3(-r * 1.05, r, 0), Vector3(r * 1.05, r, 0), Vector3(0, r * 2.75, 0)]
	for i in spots.size():
		var mi := MeshInstance3D.new()
		mi.mesh = _log_mesh(base_id, r * (1.0 + 0.08 * (i % 2)), ln, i + base_id.length())
		mi.rotation_degrees = Vector3(0, 0, 90)
		mi.position = spots[i] + Vector3(ln * 0.5 + (i - 1) * 0.03, 0, 0)
		root.add_child(mi)
	# the cord round the bundle
	var cord := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = r * 2.05
	tm.outer_radius = r * 2.25
	cord.mesh = tm
	cord.material_override = Mats.mat(Color(0.42, 0.33, 0.2), 0.95)
	cord.rotation_degrees = Vector3(0, 0, 90)
	cord.position = Vector3(0.04, r * 1.45, 0)
	cord.scale = Vector3(1.0, 1.0, 0.8)
	root.add_child(cord)
	if Data.BASES[base_id].get("glow", false):
		var l := OmniLight3D.new()
		l.light_color = Color(1.0, 0.45, 0.12)
		l.light_energy = 0.6
		l.omni_range = 1.4
		l.position = Vector3(0, 0.25, 0)
		root.add_child(l)
	return root

## A single log, its long axis along +X from the origin (what spills out of a felled tree).
static func log_node(base_id: String, radius: float, length: float, seed_v: int) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = _log_mesh(base_id, radius, length, seed_v)
	return mi

## A disc of end grain (the top of a stump, the bottom of the falling trunk), facing +Y.
static func cut_disc(base_id: String, radius: float, aged := false) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var key := "disc_%.2f" % radius
	if not _meshes.has(key):
		var cs := SurfaceTool.new()
		cs.begin(Mesh.PRIMITIVE_TRIANGLES)
		var sides := 16
		cs.set_normal(Vector3.UP)
		cs.set_uv(Vector2(0.5, 0.5))
		cs.add_vertex(Vector3.ZERO)
		for k in sides + 1:
			var a := TAU * k / float(sides)
			var rr := radius * (1.0 + 0.04 * sin(a * 5.0))
			cs.set_normal(Vector3.UP)
			cs.set_uv(Vector2(0.5 + cos(a) * 0.5, 0.5 + sin(a) * 0.5))
			cs.add_vertex(Vector3(cos(a) * rr, 0, sin(a) * rr))
		for k in sides:
			cs.add_index(0)
			cs.add_index(k + 2)
			cs.add_index(k + 1)
		var m := ArrayMesh.new()
		cs.commit(m)
		_meshes[key] = m
	mi.mesh = _meshes[key]
	mi.material_override = end_grain(base_id, aged)
	return mi

## The axe's bite in a trunk: a wedge of pale fresh wood whose depth grows with the damage (0..1), facing +Z
## (Harvest turns it to the side the hero chops from). The top and bottom faces are cut grain, the back is darker.
static func notch(base_id: String, radius: float) -> Node3D:
	var root := Node3D.new()
	var face := end_grain(base_id)
	for s in [-1.0, 1.0]:
		var q := MeshInstance3D.new()
		var pm := PlaneMesh.new()
		pm.size = Vector2(radius * 1.5, radius * 0.9)
		q.mesh = pm
		q.material_override = face
		q.rotation_degrees = Vector3(0, 0, 0) if s < 0 else Vector3(180, 0, 0)
		q.position = Vector3(0, s * 0.06, 0)
		q.name = "face_%s" % ("lo" if s < 0 else "hi")
		root.add_child(q)
	var back := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(radius * 1.4, 0.12, 0.02)
	back.mesh = bm
	var bb: Color = Data.BASES.get(base_id, Data.BASES["oak_log"]).get("heart", Color(0.78, 0.6, 0.4))
	back.material_override = Mats.mat(bb.darkened(0.25), 0.95)
	back.name = "back"
	root.add_child(back)
	return root

# ---------------------------------------------------------------- chips and debris
## Flying bits of wood that land and lie on the ground for a while, then shrink away. One node per zone
## (Debris.of(world)); cheap: plain MeshInstances moved on the CPU, at most MAX alive.
class Debris extends Node3D:
	const MAX := 160
	var bits: Array = []     # [node, vel, spin, life, rest_y, landed]
	var world: Node = null

	static func of(w: Node) -> Debris:
		var d = w.get_node_or_null("WoodDebris")
		if d == null:
			d = Debris.new()
			d.name = "WoodDebris"
			d.world = w
			w.add_child(d)
		return d

	## n chips thrown from `at` mostly along `dir` (and up), coloured like the wood; splinters are long and thin.
	func spray(at: Vector3, dir: Vector3, base_id: String, n: int, splinters: int, power := 1.0) -> void:
		var b: Dictionary = Data.BASES.get(base_id, Data.BASES["oak_log"])
		var heart: Color = b.get("heart", Color(0.78, 0.6, 0.4))
		var barkc: Color = b.get("bark", Color(0.24, 0.18, 0.12))
		for i in n + splinters:
			if bits.size() >= MAX:
				var old: Array = bits.pop_front()
				if is_instance_valid(old[0]):
					old[0].queue_free()
			var mi := MeshInstance3D.new()
			var bx := BoxMesh.new()
			var spl := i >= n
			if spl:
				bx.size = Vector3(0.012, 0.012, randf_range(0.09, 0.18))
			else:
				bx.size = Vector3(randf_range(0.03, 0.06), randf_range(0.008, 0.016), randf_range(0.03, 0.07))
			mi.mesh = bx
			var c := heart.lerp(barkc, 0.85 if randf() < 0.3 else randf() * 0.2)
			mi.material_override = Wood._chip_mat(c)
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			add_child(mi)
			mi.global_position = at + Vector3(randf_range(-0.05, 0.05), randf_range(-0.05, 0.05), randf_range(-0.05, 0.05))
			mi.rotation = Vector3(randf() * TAU, randf() * TAU, randf() * TAU)
			var side := dir.cross(Vector3.UP).normalized()
			var v := (dir * randf_range(1.2, 3.4) + side * randf_range(-1.6, 1.6) + Vector3.UP * randf_range(1.0, 3.2)) * power
			var spin := Vector3(randf_range(-14, 14), randf_range(-14, 14), randf_range(-14, 14))
			var ry := 0.0
			if world != null and world.has_method("height_at"):
				ry = world.height_at(mi.global_position.x + v.x * 0.35, mi.global_position.z + v.z * 0.35)
			bits.append([mi, v, spin, randf_range(7.0, 11.0), ry + 0.01, false])

	func _process(delta: float) -> void:
		var i := 0
		while i < bits.size():
			var b: Array = bits[i]
			var mi: MeshInstance3D = b[0]
			if not is_instance_valid(mi):
				bits.remove_at(i)
				continue
			b[3] -= delta
			if not b[5]:
				var v: Vector3 = b[1]
				v.y -= 9.8 * delta
				v *= 1.0 - 0.6 * delta
				b[1] = v
				mi.global_position += v * delta
				mi.rotation += (b[2] as Vector3) * delta
				if mi.global_position.y <= b[4]:
					# landed: a small bounce, then it settles flat
					if v.y < -2.0 and randf() < 0.6:
						b[1] = Vector3(v.x * 0.35, -v.y * 0.25, v.z * 0.35)
						b[2] = (b[2] as Vector3) * 0.4
						mi.global_position.y = b[4]
					else:
						b[5] = true
						mi.global_position.y = b[4]
						mi.rotation = Vector3(0, mi.rotation.y, 0)
			if b[3] < 1.0:
				mi.scale = Vector3.ONE * maxf(0.01, b[3])
			if b[3] <= 0.0:
				mi.queue_free()
				bits.remove_at(i)
				continue
			i += 1

static func _chip_mat(c: Color) -> StandardMaterial3D:
	var key := "chip_" + c.to_html()
	if not _mats.has(key):
		_mats[key] = Mats.mat(c, 0.9)
	return _mats[key]
