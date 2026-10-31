class_name Ocean
extends Node3D
## The sea (the coast zone, coast.gd): one wave surface that follows the camera out to the horizon.
##
## - Gerstner waves (WAVES) roll the surface in the vertex shader; `surface_y` evaluates the same sum on
##   the CPU, so anything that floats (boats) rides the very waves you see. Both read the global
##   `ocean_t`, which Ocean advances each frame.
## - A map of the zone baked from its ground (`bake`): R = water depth, G = distance from the shore.
##   It tints the water (turquoise over sand, deep blue-green further out), calms the waves in the
##   shallows, rolls surf in toward every beach and rings rocks and cliffs with foam. Because it's baked
##   from World.height_at, the islands, the peninsula and anything shaped later get it for free.
## - Forward+ (Medium and up): refraction of the seabed through the screen texture, true view-ray
##   thickness from the depth buffer (so posts, rocks and hulls get contact foam), Fresnel sky
##   reflection, sun glint, light through the wave crests. Low and the OpenGL renderer (Safe Mode, the
##   browser) use the LITE variant: the same waves, colour and foam, blended by baked depth instead.

## [wavelength m, amplitude m, direction (x, z), steepness]. The swell rolls in from the open sea to
## the west toward the mainland; shorter chop crosses it.
const WAVES := [
	[26.0, 0.30, Vector2(1.0, 0.22), 0.55],
	[15.0, 0.17, Vector2(0.92, -0.38), 0.6],
	[9.5, 0.10, Vector2(0.66, 0.75), 0.6],
	[5.6, 0.055, Vector2(1.0, -0.12), 0.65],
	[3.3, 0.03, Vector2(0.3, 0.95), 0.6],
	[2.1, 0.017, Vector2(-0.45, 0.89), 0.55],
]
const G := 9.81
const MAP_MARGIN := 40.0       # the baked map reaches this far past the zone's terrain
const DEPTH_MAX := 24.0        # metres of depth the map's R channel spans
const SHORE_MAX := 48.0        # metres of distance from the shore its G channel spans
const PERIOD := 1800.0         # ocean_t wraps every half hour (float precision in the shader)

static var _shaders := {}
static var _tex := {}
static var _bakes := {}

var mat: ShaderMaterial
var mesh_i: MeshInstance3D
var map_img: Image
var map_rect := Rect2()
var t := 0.0
var quality := -1
var _forward := true

static func wave_k(i: int) -> float:
	return TAU / float(WAVES[i][0])

## One wave's steepness term (Q): how far its crests lean, kept so crests never fold over.
static func wave_q(i: int) -> float:
	var k := wave_k(i)
	return float(WAVES[i][3]) / (k * float(WAVES[i][1]) * WAVES.size())

# ---------------------------------------------------------------- setup
func _init() -> void:
	name = "Ocean"

## Builds the surface for a zone. `forward`: the Forward+ renderer (refraction, depth); else LITE.
## `key` names the bake so a zone visited again reuses its map (the coast and islands never change).
func setup(w: World, rect: Rect2, c: float, q: int, forward: bool, key := "") -> void:
	Mats.ensure_globals()
	_forward = forward
	if key != "" and _bakes.has(key):
		var b: Array = _bakes[key]
		map_img = b[0]; _depth = b[1]; _dist = b[2]; map_rect = b[3]; cell = b[4]; _nx = b[5]; _nz = b[6]
	else:
		bake(w, rect, c)
		if key != "":
			_bakes[key] = [map_img, _depth, _dist, map_rect, cell, _nx, _nz]
	mat = ShaderMaterial.new()
	mesh_i = MeshInstance3D.new()
	mesh_i.name = "surface"
	mesh_i.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mesh_i.extra_cull_margin = 16.0
	mesh_i.custom_aabb = AABB(Vector3(-4000, -10, -4000), Vector3(8000, 20, 8000))
	mesh_i.material_override = mat
	add_child(mesh_i)
	var wa: Array = []
	var wb: Array = []
	for i in WAVES.size():
		var d: Vector2 = (WAVES[i][2] as Vector2).normalized()
		var k := wave_k(i)
		wa.append(Vector4(d.x, d.y, k, float(WAVES[i][1])))
		wb.append(Vector4(wave_q(i), sqrt(G * k), 0.0, 0.0))
	mat.set_shader_parameter("waves_a", wa)
	mat.set_shader_parameter("waves_b", wb)
	mat.set_shader_parameter("ocean_map", ImageTexture.create_from_image(map_img))
	mat.set_shader_parameter("map_rect", Vector4(map_rect.position.x, map_rect.position.y, map_rect.size.x, map_rect.size.y))
	mat.set_shader_parameter("ripple_a", ripple_tex(0))
	mat.set_shader_parameter("ripple_b", ripple_tex(1))
	mat.set_shader_parameter("foam_tex", foam_tex())
	set_quality(q)

## Low and OpenGL: the LITE shader and a coarser surface; Medium+: the full water.
func set_quality(q: int) -> void:
	q = clampi(q, 0, 3)
	if q == quality:
		return
	quality = q
	var lite := q == 0 or not _forward
	mat.shader = shader(lite)
	mesh_i.mesh = surface_mesh([72, 112, 144, 176][q])
	mat.set_shader_parameter("detail", [0.6, 0.85, 1.0, 1.0][q])

## Keeps the scene's light in the water: where the sun shines from, and how bright the sky is.
func set_light(sun_dir: Vector3, sun_col: Color, sky: Color) -> void:
	if mat == null:
		return
	mat.set_shader_parameter("sun_dir", sun_dir.normalized())
	mat.set_shader_parameter("sun_col", Vector3(sun_col.r, sun_col.g, sun_col.b))
	mat.set_shader_parameter("sky_col", Vector3(sky.r, sky.g, sky.b))

func _process(delta: float) -> void:
	t = fmod(t + delta, PERIOD)
	RenderingServer.global_shader_parameter_set("ocean_t", t)
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	# centre the rings where the camera looks at the sea, snapped so the grid doesn't crawl
	var o := cam.global_position
	var f := -cam.global_basis.z
	var c := Vector3(o.x, 0, o.z)
	if f.y < -0.05:
		var k := clampf(-o.y / f.y, 0.0, 400.0)
		c = o + f * k
	global_position = Vector3(snappedf(c.x, 1.0), 0.0, snappedf(c.z, 1.0))

# ---------------------------------------------------------------- the surface
## Rings of vertices growing geometrically from the centre out to 2 km: spacing about the same in
## every direction everywhere (the distance between rings matches the arc between spokes), so the
## near water is dense enough for the short waves and the horizon costs little.
static func surface_mesh(seg: int) -> Mesh:
	var key := "surf%d" % seg
	if _tex.has(key):
		return _tex[key]
	var verts := PackedVector3Array()
	var idx := PackedInt32Array()
	var grow := 1.0 + TAU / seg
	var r := 3.0
	verts.append(Vector3.ZERO)
	var rings := 0
	while r < 2200.0:
		for s in seg:
			var a := TAU * s / seg
			verts.append(Vector3(cos(a) * r, 0, sin(a) * r))
		rings += 1
		r *= grow
	for s in seg:
		idx.append_array([0, 1 + s, 1 + (s + 1) % seg])
	for ri in rings - 1:
		var b0 := 1 + ri * seg
		var b1 := b0 + seg
		for s in seg:
			var s1 := (s + 1) % seg
			idx.append_array([b0 + s, b1 + s, b0 + s1, b1 + s, b1 + s1, b0 + s1])
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	var norms := PackedVector3Array()
	norms.resize(verts.size())
	norms.fill(Vector3.UP)
	arr[Mesh.ARRAY_NORMAL] = norms
	arr[Mesh.ARRAY_INDEX] = idx
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	_tex[key] = m
	return m

## Small ripples: two tiling normal maps from noise, scrolled against each other in the shader.
static func ripple_tex(i: int) -> Texture2D:
	var key := "ripple%d" % i
	if _tex.has(key):
		return _tex[key]
	var n := FastNoiseLite.new()
	n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	n.seed = 71 + i * 13
	n.frequency = [0.012, 0.02][i]
	n.fractal_octaves = [5, 4][i]
	n.fractal_gain = 0.5
	var nt := NoiseTexture2D.new()
	nt.width = 512
	nt.height = 512
	nt.seamless = true
	nt.seamless_blend_skirt = 0.15
	nt.as_normal_map = true
	nt.bump_strength = [5.0, 3.5][i]
	nt.generate_mipmaps = true
	nt.noise = n
	_tex[key] = nt
	return nt

## Foam's lacy texture: cellular noise (bubbles and the threads between them).
static func foam_tex() -> Texture2D:
	if _tex.has("foam"):
		return _tex["foam"]
	var n := FastNoiseLite.new()
	n.noise_type = FastNoiseLite.TYPE_CELLULAR
	n.cellular_return_type = FastNoiseLite.RETURN_DISTANCE2_SUB
	n.seed = 5
	n.frequency = 0.035
	n.fractal_type = FastNoiseLite.FRACTAL_FBM
	n.fractal_octaves = 3
	var nt := NoiseTexture2D.new()
	nt.width = 512
	nt.height = 512
	nt.seamless = true
	nt.generate_mipmaps = true
	nt.normalize = true
	nt.noise = n
	_tex["foam"] = nt
	return nt

# ---------------------------------------------------------------- the zone's map
## Samples the zone's ground once (1 m cells): depth below the sea (y = 0) and distance from the
## nearest dry land (a chamfer distance transform, two passes).
func bake(w: World, r: Rect2, c := 1.0) -> void:
	cell = c
	var nx := int(r.size.x / c)
	var nz := int(r.size.y / c)
	map_rect = Rect2(r.position, Vector2(nx, nz) * c)
	var depth := PackedFloat32Array()
	depth.resize(nx * nz)
	var dist := PackedFloat32Array()
	dist.resize(nx * nz)
	for j in nz:
		for i in nx:
			var h := w.ground_h(r.position.x + (i + 0.5) * cell, r.position.y + (j + 0.5) * cell)
			var k := j * nx + i
			depth[k] = -h
			dist[k] = 0.0 if h > 0.0 else 1e6
	# chamfer distance (1, 1.414) forward then backward
	for j in nz:
		for i in nx:
			var k := j * nx + i
			var v := dist[k]
			if v == 0.0:
				continue
			if i > 0: v = minf(v, dist[k - 1] + c)
			if j > 0:
				v = minf(v, dist[k - nx] + c)
				if i > 0: v = minf(v, dist[k - nx - 1] + c * 1.414)
				if i < nx - 1: v = minf(v, dist[k - nx + 1] + c * 1.414)
			dist[k] = v
	for j in range(nz - 1, -1, -1):
		for i in range(nx - 1, -1, -1):
			var k := j * nx + i
			var v := dist[k]
			if v == 0.0:
				continue
			if i < nx - 1: v = minf(v, dist[k + 1] + c)
			if j < nz - 1:
				v = minf(v, dist[k + nx] + c)
				if i < nx - 1: v = minf(v, dist[k + nx + 1] + c * 1.414)
				if i > 0: v = minf(v, dist[k + nx - 1] + c * 1.414)
			dist[k] = v
	map_img = Image.create(nx, nz, false, Image.FORMAT_RGBA8)
	for j in nz:
		for i in nx:
			var k := j * nx + i
			map_img.set_pixel(i, j, Color(clampf(depth[k] / DEPTH_MAX, 0.0, 1.0), clampf(dist[k] / SHORE_MAX, 0.0, 1.0), 0.0, 1.0))
	_depth = depth
	_dist = dist
	_nx = nx
	_nz = nz

var cell := 1.0
var _depth := PackedFloat32Array()
var _dist := PackedFloat32Array()
var _nx := 0
var _nz := 0

## Water depth at a point (negative on land); deep open sea outside the map.
func depth_at(x: float, z: float) -> float:
	return _sample(_depth, x, z, DEPTH_MAX)

## Distance from the nearest dry land (0 on land); far outside the map.
func shore_at(x: float, z: float) -> float:
	return _sample(_dist, x, z, SHORE_MAX * 4.0)

func _sample(a: PackedFloat32Array, x: float, z: float, outside: float) -> float:
	var fx := (x - map_rect.position.x) / cell - 0.5
	var fz := (z - map_rect.position.y) / cell - 0.5
	var ix := int(floor(fx))
	var iz := int(floor(fz))
	if ix < 0 or iz < 0 or ix >= _nx - 1 or iz >= _nz - 1:
		return outside
	var tx := fx - ix
	var tz := fz - iz
	var k := iz * _nx + ix
	return lerpf(lerpf(a[k], a[k + 1], tx), lerpf(a[k + _nx], a[k + _nx + 1], tx), tz)

# ---------------------------------------------------------------- floating
## How much of the swell reaches a spot: calm in the shallows, full from about 6 m deep.
static func swell(depth: float) -> float:
	return 0.25 + 0.75 * smoothstep(0.5, 6.0, depth)

## The sea's height at (x, z) now, as the shader draws it (one step back through the waves' sideways
## push, which is plenty for a boat).
func surface_y(x: float, z: float) -> float:
	var p := Vector2(x, z)
	var amp := swell(depth_at(x, z))
	var q := p
	for it in 2:
		var off := Vector2.ZERO
		for i in WAVES.size():
			var d: Vector2 = (WAVES[i][2] as Vector2).normalized()
			var k := wave_k(i)
			var f := k * d.dot(q) - sqrt(G * k) * t
			off += d * (wave_q(i) * float(WAVES[i][1]) * amp * cos(f))
		q = p - off
	var y := 0.0
	for i in WAVES.size():
		var d: Vector2 = (WAVES[i][2] as Vector2).normalized()
		var k := wave_k(i)
		y += float(WAVES[i][1]) * amp * sin(k * d.dot(q) - sqrt(G * k) * t)
	return y

## The surface's normal at (x, z) (for a boat's pitch and roll), by differences.
func surface_normal(x: float, z: float, e := 0.8) -> Vector3:
	var hx := surface_y(x + e, z) - surface_y(x - e, z)
	var hz := surface_y(x, z + e) - surface_y(x, z - e)
	return Vector3(-hx, 2.0 * e, -hz).normalized()

# ---------------------------------------------------------------- shader
static func shader(lite: bool) -> Shader:
	if _shaders.has(lite):
		return _shaders[lite]
	var s := Shader.new()
	s.code = ("#define LITE\n" if lite else "") + WATER
	_shaders[lite] = s
	return s

const WATER := """
shader_type spatial;
#ifdef LITE
render_mode blend_mix, depth_draw_always, cull_disabled, diffuse_burley, specular_schlick_ggx;
#else
render_mode blend_mix, depth_draw_always, cull_disabled, diffuse_burley, specular_schlick_ggx;
uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform sampler2D depth_tex : hint_depth_texture, filter_nearest;
#endif
uniform vec4 waves_a[6];
uniform vec4 waves_b[6];
uniform sampler2D ocean_map : filter_linear, repeat_disable;
uniform vec4 map_rect;
uniform sampler2D ripple_a : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D ripple_b : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D foam_tex : filter_linear_mipmap, repeat_enable;
uniform float detail = 1.0;
uniform vec3 sun_dir = vec3(-0.5, 0.45, -0.3);
uniform vec3 sun_col = vec3(1.0, 0.8, 0.6);
uniform vec3 sky_col = vec3(0.5, 0.6, 0.7);
uniform vec3 shallow_col : source_color = vec3(0.07, 0.40, 0.42);
uniform vec3 deep_col : source_color = vec3(0.012, 0.075, 0.10);
uniform vec3 absorb = vec3(0.42, 0.085, 0.06);
global uniform float ocean_t;

varying vec3 wpos;
varying float v_depth;
varying float v_shore;
varying float v_crest;
varying float v_dist;

vec4 map_at(vec2 p){
	vec2 uv = (p - map_rect.xy) / map_rect.zw;
	if (uv.x < 0.0 || uv.y < 0.0 || uv.x > 1.0 || uv.y > 1.0) return vec4(1.0, 1.0, 0.0, 1.0);
	return textureLod(ocean_map, uv, 0.0);
}

void vertex(){
	vec3 base = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec4 m = map_at(base.xz);
	float depth = m.r * 24.0;
	float shore = m.g * 48.0;
	float amp = 0.25 + 0.75 * smoothstep(0.5, 6.0, depth);
	float far = length(base.xz - (INV_VIEW_MATRIX[3].xz));
	vec3 disp = vec3(0.0);
	vec3 tx = vec3(1.0, 0.0, 0.0);
	vec3 tz = vec3(0.0, 0.0, 1.0);
	for (int i = 0; i < 6; i++) {
		vec2 d = waves_a[i].xy;
		float k = waves_a[i].z;
		// short waves fade out with distance, where the rings are too far apart to draw them
		float fade = (i > 2) ? 1.0 - smoothstep(60.0, 160.0, far) : 1.0;
		float a = waves_a[i].w * amp * fade;
		float q = waves_b[i].x;
		float f = k * dot(d, base.xz) - waves_b[i].y * ocean_t;
		float c = cos(f);
		float s = sin(f);
		disp += vec3(q * a * d.x * c, a * s, q * a * d.y * c);
		tx += vec3(-q * a * d.x * d.x * k * s, a * d.x * k * c, -q * a * d.x * d.y * k * s);
		tz += vec3(-q * a * d.x * d.y * k * s, a * d.y * k * c, -q * a * d.y * d.y * k * s);
	}
	// the swash: near the beach the water creeps up and back down the sand
	float near = 1.0 - smoothstep(0.0, 6.0, shore);
	disp.y += near * 0.07 * sin(ocean_t * 1.25 - shore * 0.9);
	VERTEX += disp;
	vec3 n = normalize(cross(tz, tx));
	NORMAL = n;
	wpos = base + disp;
	v_depth = depth;
	v_shore = shore;
	v_crest = clamp(disp.y / 0.35, -1.0, 1.0) * (1.0 - n.y) * 6.0;
	v_dist = far;
}

void fragment(){
	vec3 view_w = normalize((INV_VIEW_MATRIX * vec4(VIEW, 0.0)).xyz);
	vec3 nw = normalize((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
	// ripples: two normal maps drifting across each other, fading with distance into a smoother sheen
	float t = ocean_t;
	vec2 p = wpos.xz;
	vec3 ra = texture(ripple_a, p * 0.045 + vec2(t * 0.011, t * 0.006)).rgb * 2.0 - 1.0;
	vec3 rb = texture(ripple_b, p * 0.13 + vec2(-t * 0.017, t * 0.021)).rgb * 2.0 - 1.0;
	float dfade = (1.0 - smoothstep(30.0, 220.0, v_dist)) * detail;
	vec2 rip = (ra.xy * 0.55 + rb.xy * 0.45) * (0.32 * dfade + 0.04);
	nw = normalize(nw + vec3(rip.x, 0.0, rip.y));
	NORMAL = normalize((VIEW_MATRIX * vec4(nw, 0.0)).xyz);
	float ndv = clamp(dot(nw, view_w), 0.0, 1.0);
	float fres = 0.02 + 0.98 * pow(1.0 - ndv, 5.0);

	// how much water the eye looks through
	float thick;
	vec3 under;
#ifdef LITE
	thick = v_depth / max(ndv, 0.25);
	under = vec3(0.0);
#else
	float zr = texture(depth_tex, SCREEN_UV).r;
	vec4 sp = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, zr, 1.0);
	float scene_d = -sp.z / sp.w;
	float water_d = -VERTEX.z;
	thick = max(scene_d - water_d, 0.0);
	// refraction: bend the view of the seabed by the waves, more where the water is deeper
	vec2 ruv = SCREEN_UV + NORMAL.xz * 0.045 * clamp(thick * 0.25, 0.0, 1.0) * detail;
	float zr2 = texture(depth_tex, ruv).r;
	vec4 sp2 = INV_PROJECTION_MATRIX * vec4(ruv * 2.0 - 1.0, zr2, 1.0);
	float scene_d2 = -sp2.z / sp2.w;
	if (scene_d2 < water_d) { ruv = SCREEN_UV; } else { thick = max(scene_d2 - water_d, 0.0); }
	under = textureLod(screen_tex, ruv, 0.0).rgb;
#endif
	vec3 trans = exp(-absorb * thick);
	float tavg = (trans.r + trans.g + trans.b) / 3.0;
	// the water's own colour: light scattered back by it, turquoise over sand, blue-green far out,
	// lit by the sky and the sun
	vec3 scat = mix(shallow_col, deep_col, smoothstep(0.5, 14.0, v_depth));
	// lit by the sky and sun's brightness, only a little by their colour (a warm evening shouldn't turn
	// the sea olive)
	float sky_l = dot(sky_col, vec3(0.3, 0.5, 0.2));
	vec3 light = mix(vec3(sky_l), sky_col, 0.25) * 1.1 + mix(vec3(dot(sun_col, vec3(0.33))), sun_col, 0.3) * max(sun_dir.y, 0.0) * 0.5;
	scat *= light;
	vec3 body = under * trans + scat * (1.0 - tavg);
	// light through the thin top of a wave, seen against the sun
	float back = pow(clamp(dot(view_w, -normalize(vec3(sun_dir.x, 0.0, sun_dir.z))) * 0.5 + 0.5, 0.0, 1.0), 4.0);
	body += vec3(0.05, 0.28, 0.22) * sun_col * clamp(v_crest, 0.0, 1.0) * back * 0.9;

	// foam: breaking surf rolling in on the beaches, a collar where the water meets rock, sand and posts,
	// and whitecaps on the steepest crests
	float shoreband = 1.0 - smoothstep(0.0, 9.0, v_shore);
	float surf = sin(v_shore * 1.15 + t * 1.6 - texture(foam_tex, p * 0.02).r * 4.0) * 0.5 + 0.5;
	surf = smoothstep(0.55, 0.95, surf) * shoreband * smoothstep(0.0, 1.2, v_shore + 0.6);
	// the swash line: a thin, broken edge of foam that rides up and back with the water
	float swash = 0.5 + 0.5 * sin(t * 1.25 - v_shore * 0.9 + 1.4);
	float contact = (1.0 - smoothstep(0.0, 0.45, thick)) * 0.8;
	contact = max(contact, (1.0 - smoothstep(0.0, 0.5 + swash * 0.9, v_shore)) * (0.55 + 0.45 * swash));
	float caps = smoothstep(0.55, 1.0, v_crest) * 0.7;
	float lace = texture(foam_tex, p * 0.21 + vec2(t * 0.02, -t * 0.013)).r;
	float lace2 = texture(foam_tex, p * 0.53 - vec2(t * 0.031, t * 0.017)).r;
	float famt = clamp(surf * 0.9 + contact * 0.85 + caps, 0.0, 1.0);
	float foam = smoothstep(1.0 - famt, 1.0 - famt * 0.55, lace * 0.6 + lace2 * 0.4) * famt;
	foam = clamp(foam * 1.35, 0.0, 1.0);

#ifdef LITE
	ALBEDO = mix(scat * 0.6, vec3(0.92, 0.95, 0.95), foam);
	ALPHA = clamp(1.0 - tavg * 0.85 + foam, 0.0, 1.0);
	EMISSION = vec3(0.05, 0.28, 0.22) * sun_col * clamp(v_crest, 0.0, 1.0) * back * 0.6;
#else
	ALBEDO = vec3(0.92, 0.95, 0.95) * foam;
	EMISSION = body * (1.0 - fres) * (1.0 - foam);
#endif
	// far water: the ripples average out into a wider, softer sun path
	ROUGHNESS = mix(0.025 + 0.06 * smoothstep(40.0, 400.0, v_dist), 0.85, foam);
	SPECULAR = 0.5;
	METALLIC = 0.0;
}
"""
