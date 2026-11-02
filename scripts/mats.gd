class_name Mats
extends RefCounted
## Shared materials and shaders.

static var _cache := {}
static var _detail: NoiseTexture2D
static var _soft: GradientTexture2D
static var _shaders := {}
static var _globals_ready := false

static func ensure_globals() -> void:
	if _globals_ready:
		return
	_globals_ready = true
	RenderingServer.global_shader_parameter_add("player_pos", RenderingServer.GLOBAL_VAR_TYPE_VEC3, Vector3.ZERO)
	RenderingServer.global_shader_parameter_add("occlude_k", RenderingServer.GLOBAL_VAR_TYPE_FLOAT, 0.73)
	# 0 = no snow, 1 = everything outdoors snowed over (A2)
	RenderingServer.global_shader_parameter_add("snow_amt", RenderingServer.GLOBAL_VAR_TYPE_FLOAT, 0.0)
	# 0 = normal, 1 = everything scorched and burning (A3)
	RenderingServer.global_shader_parameter_add("ash_amt", RenderingServer.GLOBAL_VAR_TYPE_FLOAT, 0.0)
	# 0 = normal, 1 = the Demon has phased into the Underworld
	RenderingServer.global_shader_parameter_add("under_amt", RenderingServer.GLOBAL_VAR_TYPE_FLOAT, 0.0)
	# grass (grass_field.gd / grass.gd): where the touch field lies (origin x, z, size, strength; strength 0 =
	# no touch; the field's texture itself goes to the grass materials, Grass.set_field), the camera for the
	# distance fade, and the wind
	RenderingServer.global_shader_parameter_add("grass_field_rect", RenderingServer.GLOBAL_VAR_TYPE_VEC4, Vector4(0, 0, 64, 0))
	RenderingServer.global_shader_parameter_add("grass_cam", RenderingServer.GLOBAL_VAR_TYPE_VEC3, Vector3(0, 20, 20))
	RenderingServer.global_shader_parameter_add("wind_dir", RenderingServer.GLOBAL_VAR_TYPE_VEC2, Vector2(0.87, 0.5))
	RenderingServer.global_shader_parameter_add("wind_strength", RenderingServer.GLOBAL_VAR_TYPE_FLOAT, 0.45)
	RenderingServer.global_shader_parameter_add("wind_gust", RenderingServer.GLOBAL_VAR_TYPE_FLOAT, 0.6)
	RenderingServer.global_shader_parameter_add("wind_phase", RenderingServer.GLOBAL_VAR_TYPE_FLOAT, 0.0)
	# the sea's clock (ocean.gd): its waves on the GPU and Ocean.surface_y on the CPU read the same time
	RenderingServer.global_shader_parameter_add("ocean_t", RenderingServer.GLOBAL_VAR_TYPE_FLOAT, 0.0)

static func detail_normal() -> Texture2D:
	if _detail == null:
		var n := FastNoiseLite.new()
		n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
		n.frequency = 0.03
		n.fractal_octaves = 4
		_detail = NoiseTexture2D.new()
		_detail.width = 256
		_detail.height = 256
		_detail.seamless = true
		_detail.as_normal_map = true
		_detail.bump_strength = 3.0
		_detail.noise = n
	return _detail

static func soft_dot() -> Texture2D:
	if _soft == null:
		var g := Gradient.new()
		g.set_color(0, Color(1, 1, 1, 1))
		g.set_color(1, Color(1, 1, 1, 0))
		g.add_point(0.35, Color(1, 1, 1, 0.55))
		_soft = GradientTexture2D.new()
		_soft.gradient = g
		_soft.fill = GradientTexture2D.FILL_RADIAL
		_soft.fill_from = Vector2(0.5, 0.5)
		_soft.fill_to = Vector2(1.0, 0.5)
		_soft.width = 64
		_soft.height = 64
	return _soft

## Character / item material (standard PBR with detail normals).
static func mat(color: Color, rough: float = 0.8, metal: float = 0.0, emis: Color = Color.BLACK, emis_e: float = 0.0, rim: float = 0.0) -> StandardMaterial3D:
	var key := "m%s|%.2f|%.2f|%s|%.2f|%.2f" % [color.to_html(), rough, metal, emis.to_html(), emis_e, rim]
	if _cache.has(key):
		return _cache[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = rough
	m.metallic = metal
	m.metallic_specular = 0.6 if metal > 0.4 else 0.4
	m.normal_enabled = true
	m.normal_texture = detail_normal()
	m.normal_scale = 0.6 if metal > 0.4 else 1.0
	m.uv1_triplanar = true
	m.uv1_scale = Vector3(3, 3, 3)
	if emis_e > 0.0:
		m.emission_enabled = true
		m.emission = emis
		m.emission_energy_multiplier = emis_e
	if rim > 0.0:
		m.rim_enabled = true
		m.rim = rim
		m.rim_tint = 0.6
	_cache[key] = m
	return m

static func flat(color: Color) -> StandardMaterial3D:
	var key := "f" + color.to_html()
	if _cache.has(key):
		return _cache[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = 0.9
	_cache[key] = m
	return m

## Additive glowing material for magic effects, beams, runes.
static func glow(color: Color, energy: float = 2.0, fade_uv: float = 0.0, rim: float = 0.0) -> ShaderMaterial:
	var key := "g%s|%.2f|%.2f|%.2f" % [color.to_html(), energy, fade_uv, rim]
	if _cache.has(key):
		return _cache[key]
	var m := ShaderMaterial.new()
	m.shader = shader("fx")
	m.set_shader_parameter("color", color)
	m.set_shader_parameter("energy", energy)
	m.set_shader_parameter("fade_uv", fade_uv)
	m.set_shader_parameter("rim", rim)
	_cache[key] = m
	return m

## Unique (non-cached) glow material so it can be animated per instance.
static func glow_unique(color: Color, energy: float = 2.0, fade_uv: float = 0.0, rim: float = 0.0) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = shader("fx")
	m.set_shader_parameter("color", color)
	m.set_shader_parameter("energy", energy)
	m.set_shader_parameter("fade_uv", fade_uv)
	m.set_shader_parameter("rim", rim)
	return m

## Environment material: procedural stone/wood detail + see-through near the hero.
static func world(c1: Color, c2: Color = Color(-1, 0, 0), rough: float = 0.88, scale: float = 1.4, moss: float = 0.0, moss_col: Color = Color(0.2, 0.3, 0.12), occlude: bool = true, metal: float = 0.0, emis: Color = Color.BLACK, emis_e: float = 0.0, grain: float = 0.0) -> ShaderMaterial:
	if c2.r < 0.0:
		c2 = c1.darkened(0.25)
	var key := "w%s%s%.2f%.2f%.2f%s%d%.2f%s%.2f%.2f" % [c1.to_html(), c2.to_html(), rough, scale, moss, moss_col.to_html(), int(occlude), metal, emis.to_html(), emis_e, grain]
	if _cache.has(key):
		return _cache[key]
	var m := ShaderMaterial.new()
	m.shader = shader("prop")
	m.set_shader_parameter("albedo", c1)
	m.set_shader_parameter("albedo2", c2)
	m.set_shader_parameter("roughness", rough)
	m.set_shader_parameter("noise_scale", scale)
	m.set_shader_parameter("moss", moss)
	m.set_shader_parameter("moss_col", moss_col)
	m.set_shader_parameter("occlude", 1.0 if occlude else 0.0)
	m.set_shader_parameter("metallic", metal)
	m.set_shader_parameter("emission", emis)
	m.set_shader_parameter("emission_energy", emis_e)
	m.set_shader_parameter("grain", grain)
	_cache[key] = m
	return m

static func shader_water_mat(deep: Color = Color(0.03, 0.07, 0.06), shallow: Color = Color(0.12, 0.2, 0.14)) -> ShaderMaterial:
	var key := "water%s%s" % [deep.to_html(), shallow.to_html()]
	if _cache.has(key):
		return _cache[key]
	var m := ShaderMaterial.new()
	m.shader = shader("water")
	m.set_shader_parameter("deep", deep)
	m.set_shader_parameter("shallow", shallow)
	_cache[key] = m
	return m

static func particle_mat(additive: bool, color: Color = Color.WHITE) -> StandardMaterial3D:
	var key := "p%d%s" % [int(additive), color.to_html()]
	if _cache.has(key):
		return _cache[key]
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	if additive:
		m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.vertex_color_use_as_albedo = true
	m.albedo_color = color
	m.albedo_texture = soft_dot()
	m.disable_receive_shadows = true
	_cache[key] = m
	return m

static func shader(name: String) -> Shader:
	if _shaders.has(name):
		return _shaders[name]
	ensure_globals()
	var s := Shader.new()
	match name:
		"fx": s.code = FX_SHADER
		"prop": s.code = PROP_SHADER
		"terrain": s.code = TERRAIN_SHADER
		"grass": s.code = GRASS_SHADER
		"water": s.code = WATER_SHADER
		"lava": s.code = LAVA_SHADER
		"orb": s.code = ORB_SHADER
		"cloth": s.code = CLOTH_SHADER
	_shaders[name] = s
	return s

## A shader of another script's, made once and kept by key (after the global uniforms it may read exist).
static func custom(key: String, code: String) -> Shader:
	if not _shaders.has(key):
		ensure_globals()
		var s := Shader.new()
		s.code = code
		_shaders[key] = s
	return _shaders[key]

const NOISE_LIB := """
float hash21(vec2 p){ p = fract(p*vec2(123.34, 456.21)); p += dot(p, p+45.32); return fract(p.x*p.y); }
// ordered 4x4 dither for the see-through near the player: a steady screen, not per-pixel noise that sparkles
float bayer2(vec2 a){ a = floor(a); return fract(a.x / 2.0 + a.y * a.y * 0.75); }
float dith(vec2 a){ return bayer2(0.5 * a) * 0.25 + bayer2(a) + 0.03125; }
float vnoise(vec2 p){ vec2 i=floor(p); vec2 f=fract(p); vec2 u=f*f*(3.0-2.0*f);
	return mix(mix(hash21(i),hash21(i+vec2(1.0,0.0)),u.x), mix(hash21(i+vec2(0.0,1.0)),hash21(i+vec2(1.0,1.0)),u.x), u.y); }
float fbm(vec2 p){ float v=0.0; float a=0.5; for(int i=0;i<5;i++){ v+=a*vnoise(p); p=p*2.03+vec2(1.7,9.2); a*=0.5; } return v; }
float fbm3(vec2 p){ float v=0.0; float a=0.5; for(int i=0;i<3;i++){ v+=a*vnoise(p); p=p*2.03+vec2(1.7,9.2); a*=0.5; } return v; }
"""

const FX_SHADER := """
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled;
uniform vec4 color : source_color = vec4(1.0);
uniform float energy = 2.0;
uniform float fade_uv = 0.0;
uniform float rim = 0.0;
uniform float alpha_mul = 1.0;
void fragment(){
	float a = color.a * alpha_mul;
	if (fade_uv > 0.0) { a *= pow(clamp(1.0 - UV.y, 0.0, 1.0), fade_uv) * smoothstep(0.0, 0.08, UV.y); }
	if (rim > 0.0) { float f = clamp(1.0 - abs(dot(NORMAL, VIEW)), 0.0, 1.0); a *= mix(1.0, f * f * 2.0, rim); }
	a = clamp(a, 0.0, 4.0);
	ALBEDO = color.rgb * energy * a;
	ALPHA = clamp(a, 0.0, 1.0);
}
"""

const PROP_SHADER := """
shader_type spatial;
render_mode blend_mix, cull_back, diffuse_burley, specular_schlick_ggx;
global uniform vec3 player_pos;
global uniform float occlude_k;
global uniform float snow_amt;
global uniform float ash_amt;
uniform float breakable = 0.0;
uniform vec3 albedo : source_color = vec3(0.5);
uniform vec3 albedo2 : source_color = vec3(0.4);
uniform float roughness = 0.85;
uniform float metallic = 0.0;
uniform float noise_scale = 1.4;
uniform float occlude = 1.0;
uniform float moss = 0.0;
uniform vec3 moss_col : source_color = vec3(0.2, 0.3, 0.12);
uniform vec3 emission : source_color = vec3(0.0);
uniform float emission_energy = 0.0;
uniform float grain = 0.0;
varying vec3 wpos;
varying vec3 wnorm;
""" + NOISE_LIB + """
void vertex(){
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnorm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}
void fragment(){
	if (occlude > 0.5) {
		vec3 d = wpos - player_pos;
		float h = wpos.y - player_pos.y;
		float along = d.z - occlude_k * (h - 1.0);
		float cover = (1.0 - smoothstep(1.6, 3.2, abs(along))) * (1.0 - smoothstep(2.2, 3.6, abs(d.x)));
		cover *= step(0.9, h) * step(0.2, d.z);
		if (cover * 0.9 > dith(FRAGCOORD.xy)) { discard; }
	}
	float burn_rim = 0.0;
	if (ash_amt > 0.0 && breakable > 0.5 && emission_energy < 0.5) {
		// burned-through holes in hides and planks, with glowing edges
		float hn = fbm(wpos.xz * 0.85 + vec2(wpos.y * 1.3, -wpos.y * 0.7) + 4.0);
		if (hn > 0.64) { discard; }
		burn_rim = smoothstep(0.55, 0.64, hn);
	}
	vec3 an = abs(wnorm);
	vec2 uvp = an.y > 0.6 ? wpos.xz : (an.x > an.z ? wpos.zy : wpos.xy);
	if (grain > 0.0) { uvp = vec2(uvp.x * 4.0, uvp.y * 0.35); }
	float n1 = fbm(uvp * noise_scale);
	float n2 = fbm3(uvp * noise_scale * 6.0 + 3.1);
	vec3 col = mix(albedo, albedo2, smoothstep(0.3, 0.75, n1));
	col *= 0.78 + n2 * 0.44;
	float mossf = moss * smoothstep(0.35, 0.9, wnorm.y + (n1 - 0.5) * 0.8);
	col = mix(col, moss_col * (0.8 + n2 * 0.4), clamp(mossf, 0.0, 1.0));
	float snowc = 0.0;
	if (snow_amt > 0.0 && emission_energy < 0.5) {
		snowc = snow_amt * smoothstep(0.28, 0.62, wnorm.y + (n1 - 0.5) * 0.45 + (n2 - 0.5) * 0.15);
		vec3 sn = vec3(0.8, 0.84, 0.9) * (0.9 + n2 * 0.12);
		sn = mix(sn, vec3(0.7, 0.78, 0.92), (1.0 - wnorm.y) * 0.4);
		col = mix(col, sn, snowc);
	}
	float ember = 0.0;
	if (ash_amt > 0.0 && emission_energy < 0.5) {
		// soot-blackened, ash dusted on top, embers smouldering in wood and hide
		float charv = ash_amt * (0.5 + 0.4 * smoothstep(0.3, 0.7, n1));
		col = mix(col, col * 0.2 + vec3(0.018, 0.015, 0.013), charv);
		col = mix(col, vec3(0.34, 0.32, 0.3) * (0.85 + n2 * 0.2), ash_amt * smoothstep(0.5, 0.85, wnorm.y + (n1 - 0.5) * 0.4) * 0.5);
		col = mix(col, vec3(0.06, 0.02, 0.01), burn_rim);
		if (breakable > 0.5 || grain > 0.0) {
			ember = smoothstep(0.82, 0.95, n2) * smoothstep(0.4, 0.7, n1) * ash_amt;
		}
		ember += burn_rim * 1.6;
	}
	ALBEDO = col;
	ROUGHNESS = mix(clamp(roughness + (n2 - 0.5) * 0.2, 0.05, 1.0), 0.6, snowc);
	METALLIC = metallic * (1.0 - snowc);
	float e = 0.06;
	float sc = noise_scale * 5.0;
	float hc = fbm3(uvp * sc);
	float hx = fbm3((uvp + vec2(e, 0.0)) * sc);
	float hy = fbm3((uvp + vec2(0.0, e)) * sc);
	vec3 wn = normalize(wnorm);
	vec3 t = normalize(cross(wn, abs(wn.y) > 0.9 ? vec3(1.0, 0.0, 0.0) : vec3(0.0, 1.0, 0.0)));
	vec3 b = cross(wn, t);
	vec3 pn = normalize(wn + (t * (hc - hx) + b * (hc - hy)) * 3.0 * (1.0 - snowc * 0.7));
	NORMAL = normalize((VIEW_MATRIX * vec4(pn, 0.0)).xyz);
	float pulse = 0.7 + 0.3 * sin(TIME * 2.2 + wpos.x * 1.7 + wpos.z * 1.3);
	EMISSION = emission * emission_energy + vec3(1.0, 0.34, 0.07) * ember * pulse * 2.4;
}
"""

const TERRAIN_SHADER := """
shader_type spatial;
render_mode blend_mix, cull_back, diffuse_burley, specular_schlick_ggx;
uniform vec3 col_a : source_color = vec3(0.25, 0.3, 0.15);
uniform vec3 col_b : source_color = vec3(0.3, 0.25, 0.18);
uniform vec3 col_accent : source_color = vec3(0.35, 0.33, 0.2);
uniform vec3 col_path : source_color = vec3(0.35, 0.3, 0.24);
uniform vec3 col_cliff : source_color = vec3(0.3, 0.3, 0.3);
uniform vec3 crack_col : source_color = vec3(1.0, 0.35, 0.05);
uniform float cracks = 0.0;
uniform float tiles = 0.0;
uniform float cob_shade = 1.0;
uniform float wet = 0.0;
uniform float ripples = 0.0;
// the ground's small detail (World.terrain_patch): pebbles and grit in the dirt; fallen oak leaves on the floor
uniform float ground_detail = 1.0;
uniform float litter = 0.0;
// the coast (coast.gd): sand round the sea (y = 0), wet sand at the waterline, the seabed under water
uniform float sea = 0.0;
uniform vec3 col_sand : source_color = vec3(0.6, 0.53, 0.4);
global uniform float ocean_t;
global uniform float snow_amt;
global uniform float ash_amt;
global uniform float under_amt;
global uniform vec3 player_pos;
varying vec3 wpos;
varying vec3 wnorm;
varying vec4 vcol;
""" + NOISE_LIB + """
void vertex(){
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnorm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	vcol = COLOR;
}
float tile_mask(vec2 p, out float id){
	vec2 g = p / 2.0;
	vec2 c = floor(g);
	vec2 f = fract(g);
	id = hash21(c);
	float edge = min(min(f.x, 1.0 - f.x), min(f.y, 1.0 - f.y));
	return smoothstep(0.02, 0.06, edge);
}
vec2 vor(vec2 p, out float id){
	vec2 i = floor(p); vec2 f = fract(p);
	float d1 = 8.0; float d2 = 8.0; vec2 best = vec2(0.0);
	for (int y = -1; y <= 1; y++) { for (int x = -1; x <= 1; x++) {
		vec2 g = vec2(float(x), float(y));
		vec2 o = vec2(hash21(i + g), hash21(i + g + 17.3)) * 0.8 + 0.1;
		float d = length(g + o - f);
		if (d < d1) { d2 = d1; d1 = d; best = i + g; } else if (d < d2) { d2 = d; }
	}}
	id = hash21(best);
	return vec2(d1, d2);
}
// vor() that also gives the nearest feature point (the stone's centre)
vec2 vorc(vec2 p, out float id, out vec2 cen){
	vec2 i = floor(p); vec2 f = fract(p);
	float d1 = 8.0; float d2 = 8.0; vec2 best = vec2(0.0); cen = vec2(0.0);
	for (int y = -1; y <= 1; y++) { for (int x = -1; x <= 1; x++) {
		vec2 g = vec2(float(x), float(y));
		vec2 o = vec2(hash21(i + g), hash21(i + g + 17.3)) * 0.8 + 0.1;
		float d = length(g + o - f);
		if (d < d1) { d2 = d1; d1 = d; best = i + g; cen = i + g + o; } else if (d < d2) { d2 = d; }
	}}
	id = hash21(best);
	return vec2(d1, d2);
}
// one cobble of the old roads, as a height (0 in the joints, ~1 on a worn crown): a domed stone with chipped edges,
// set a little askew, its granite pitted; some split by a crack, a few gone (a muddy hole). e = distance to its edge.
float cobble(vec2 p, out float id, out float e, out float gone, out float crack){
	vec2 q = p * 2.6;
	vec2 cen = vec2(0.0);
	vec2 v = vorc(q, id, cen);
	float chip = (vnoise(p * 15.0) - 0.5) * 0.07 + (vnoise(p * 41.0) - 0.5) * 0.025;
	float loose = max(vnoise(p * 1.3 + 4.1) - 0.5, 0.0) * 0.14;   // stretches where the joints have opened up
	e = v.y - v.x + chip - loose;
	float crown = pow(smoothstep(0.02, 0.34, e), 0.6);
	vec2 tdir = vec2(hash21(vec2(id * 13.1, 2.7)), hash21(vec2(id * 7.3, 9.1))) - 0.5;
	float h = crown * (0.72 + 0.28 * hash21(vec2(id, 4.4))) + dot(q - cen, tdir) * 0.4 * crown;
	h += (fbm3(p * 7.0) - 0.5) * 0.14 * crown;
	float ang = hash21(vec2(id * 5.9, 8.2)) * 6.2832;
	vec2 cd = vec2(cos(ang), sin(ang));
	float off = (hash21(vec2(id * 2.3, 6.6)) - 0.5) * 0.3;
	float cl = abs(dot(q - cen, vec2(-cd.y, cd.x)) + off + (vnoise(q * 7.0) - 0.5) * 0.14);
	crack = (1.0 - smoothstep(0.004, 0.03, cl)) * step(0.86, hash21(vec2(id * 11.7, 0.4))) * smoothstep(0.06, 0.14, e);
	h -= crack * 0.3;
	gone = step(hash21(vec2(id * 3.7, 1.3)), 0.03);
	return h * (1.0 - gone * 0.85);
}
void fragment(){
	vec2 p = wpos.xz;
	float n1 = fbm(p * 0.05);
	float n2 = fbm(p * 0.33 + 7.0);
	float n3 = fbm3(p * 2.1);
	float n4 = vnoise(p * 9.0);
	float n5 = fbm3(p * 0.9 + 3.3);
	// mossy ground: large tone patches, mid clumps, fine speckle
	vec3 base = mix(col_a, col_b, smoothstep(0.38, 0.66, n1));
	base = mix(base, col_accent, smoothstep(0.52, 0.75, n2) * 0.65);
	base = mix(base, col_a * 0.55, smoothstep(0.6, 0.8, n5) * 0.5);
	base *= 0.78 + n3 * 0.3 + (n4 - 0.5) * 0.18;
	if (ripples > 0.0) {
		float r = sin(p.x * 1.7 + p.y * 0.6 + n1 * 9.0) * 0.5 + 0.5;
		base *= 1.0 - ripples * 0.12 * r;
	}
	// trodden dirt with ragged edges and grass islands
	float pr = vcol.r + (n2 - 0.5) * 0.7 + (n3 - 0.5) * 0.35 + (n4 - 0.5) * 0.12;
	float path = smoothstep(0.42, 0.62, pr);
	path *= 1.0 - smoothstep(0.66, 0.8, n5) * 0.55 * (1.0 - smoothstep(0.85, 1.0, vcol.r));
	vec3 pathc = mix(col_path, col_path * vec3(0.78, 0.8, 0.72), smoothstep(0.35, 0.7, n2));
	pathc = mix(pathc, col_path * 0.6, smoothstep(0.55, 0.8, n3) * 0.5);
	pathc *= 0.85 + n4 * 0.3;
	float pebble = smoothstep(0.86, 0.93, vnoise(p * 14.0)) * smoothstep(0.4, 0.7, n3);
	pathc = mix(pathc, vec3(0.42, 0.4, 0.36), pebble * 0.6);
	float edge = smoothstep(0.2, 0.5, path) * (1.0 - smoothstep(0.5, 0.95, path));
	base = mix(base, pathc, path);
	base = mix(base, base * vec3(0.85, 0.82, 0.7), edge * 0.5);
	// stones and grit in the trodden dirt: pebbles half sunk in the soil, each domed, lit on its crown and shadowed at
	// its foot, more of them toward the path's edges than down its trodden middle; a speckle of light and dark grains
	vec2 pebg = vec2(0.0);
	if (ground_detail > 0.0 && path > 0.02) {
		float pid; vec2 pc;
		vec2 pq = p * 7.0;
		vorc(pq, pid, pc);
		vec2 po = pq - pc;
		float pd = length(po) + (vnoise(pq * 3.1) - 0.5) * 0.09;
		float prad = 0.12 + 0.2 * hash21(vec2(pid, 3.1)) * hash21(vec2(pid, 4.2));
		float pkeep = step(1.0 - mix(0.5, 0.16, smoothstep(0.55, 0.95, path)) * (0.4 + 0.8 * n3), hash21(vec2(pid, 7.7)));
		float pdome = pkeep * clamp(1.0 - (pd * pd) / (prad * prad), 0.0, 1.0);
		float pfoot = pkeep * (1.0 - smoothstep(prad, prad * 1.5, pd)) * step(prad, pd);
		vec3 stone = mix(col_path * 1.25, vec3(0.36, 0.35, 0.33), 0.35 + 0.45 * hash21(vec2(pid, 5.5)));
		stone *= 0.8 + 0.25 * pdome + (n4 - 0.5) * 0.15;
		base = mix(base, base * 0.75, pfoot * path);
		base = mix(base, stone, smoothstep(0.0, 0.25, pdome) * path);
		pebg = step(pd, prad) * pkeep * (-2.0 * po / (prad * prad)) * 0.018 * 7.0 * path;
		float gr = vnoise(p * 38.0);
		base *= 1.0 + (smoothstep(0.78, 0.92, gr) * 0.12 - (1.0 - smoothstep(0.08, 0.22, gr)) * 0.12) * path;
	}
	if (litter > 0.0) {
		// fallen oak leaves on the forest floor, lying in drifts, fewer on the paths: lobed, each turned its own way,
		// brown, a few russet, some dark and rotting, a darker midrib
		float lid; vec2 lc;
		vec2 lq = p * 3.0;
		vorc(lq, lid, lc);
		vec2 lo = lq - lc;
		float la = hash21(vec2(lid, 3.3)) * 6.2832;
		vec2 ld = vec2(cos(la), sin(la));
		vec2 lr = vec2(dot(lo, ld), dot(lo, vec2(-ld.y, ld.x)));
		float llen = 0.16 + 0.22 * hash21(vec2(lid, 5.1));
		float lw = llen * (0.42 + 0.1 * sin(lr.x / llen * 9.0));
		float leaf = 1.0 - smoothstep(0.8, 1.0, length(vec2(lr.x / llen, lr.y / lw)));
		float drifts = 0.05 + 0.5 * smoothstep(0.45, 0.72, fbm(p * 0.35 + 11.0)) + 0.15 * smoothstep(0.5, 0.75, n2);
		leaf *= step(1.0 - litter * drifts, hash21(vec2(lid, 8.8))) * (1.0 - path * 0.6);
		vec3 lcol = mix(vec3(0.24, 0.16, 0.08), vec3(0.36, 0.24, 0.12), hash21(vec2(lid, 2.2)));
		lcol = mix(lcol, vec3(0.4, 0.21, 0.09), step(0.85, hash21(vec2(lid, 1.7))));
		lcol = mix(lcol, vec3(0.15, 0.11, 0.07), step(0.65, hash21(vec2(lid, 6.6))));
		float rib = (1.0 - smoothstep(0.0, 0.015, abs(lr.y))) * step(abs(lr.x), llen * 0.85);
		base = mix(base, lcol * (0.8 + n4 * 0.35) * (1.0 - rib * 0.3), leaf * 0.9);
	}
	float tid = 0.0;
	float tm = 1.0;
	if (tiles > 0.0) {
		vec2 vv = vor(p * 1.3, tid);
		tm = smoothstep(0.02, 0.09, vv.y - vv.x);
		vec3 slab = col_path * (0.7 + tid * 0.45) * (0.85 + n3 * 0.3);
		base = mix(base, mix(col_path * 0.3, slab, tm), path);
	}
	// cobbles: irregular stones, half buried in dirt
	float cob = smoothstep(0.35, 0.65, vcol.b + (n2 - 0.5) * 0.7 + (n4 - 0.5) * 0.15);
	cob *= smoothstep(0.3, 0.55, n5 + vcol.b * 0.3);
	float cid = 0.0;
	float cm = 1.0;
	float ch = 0.0;
	float cwear = 0.0;
	float cgone = 0.0;
	if (cob > 0.01) {
		float ce0 = 0.0; float ccrack = 0.0;
		ch = cobble(p, cid, ce0, cgone, ccrack);
		cm = smoothstep(0.03, 0.12, ce0) * (1.0 - cgone);
		// granite in a spread of greys, some warmer or cooler, with specks of grain
		float h1 = hash21(vec2(cid * 5.1, 0.7));
		float h2 = hash21(vec2(cid * 9.7, 3.3));
		vec3 stonec = mix(vec3(0.2, 0.195, 0.185), vec3(0.37, 0.355, 0.33), cid);
		stonec *= mix(vec3(1.0), h2 > 0.5 ? vec3(1.09, 1.0, 0.88) : vec3(0.92, 0.97, 1.07), abs(h2 - 0.5) * 1.3);
		stonec *= 0.82 + n3 * 0.26 + (n4 - 0.5) * 0.12;
		float grain = vnoise(p * 46.0);
		stonec *= 0.92 + smoothstep(0.6, 0.92, grain) * 0.24 - smoothstep(0.4, 0.08, grain) * 0.14;
		// worn crowns: lighter where feet and wheels have polished them
		cwear = smoothstep(0.45, 0.85, ch) * (0.45 + 0.55 * smoothstep(0.3, 0.7, n2));
		stonec *= 1.0 + cwear * 0.17;
		// moss creeping in from the joints, mossy stretches of road, lichen rosettes
		float mossy = smoothstep(0.58, 0.82, n5 * 0.7 + h1 * 0.5) * (1.0 - cwear);
		float edgemoss = (1.0 - smoothstep(0.04, 0.17, ce0)) * smoothstep(0.35, 0.65, n2);
		stonec = mix(stonec, col_accent * 0.72 * (0.8 + n4 * 0.4), clamp(mossy * 0.55 + edgemoss * 0.6, 0.0, 1.0) * (0.55 + 0.45 * vnoise(p * 21.0)));
		float lichen = smoothstep(0.78, 0.86, vnoise(p * 9.0 + cid * 31.0)) * (1.0 - cwear) * 0.45;
		stonec = mix(stonec, vec3(0.5, 0.52, 0.45), lichen);
		stonec *= (1.0 - ccrack * 0.45) * cob_shade;
		// the joints and the holes where a stone is gone: dark packed dirt with moss and grass in it
		vec3 gap = mix(col_path * 0.36, col_a * 0.55, smoothstep(0.35, 0.7, n2 + (vnoise(p * 12.0) - 0.5) * 0.45));
		gap *= 0.72 + vnoise(p * 30.0) * 0.38;
		vec3 hole = mix(col_path * 0.95, col_a * 1.1, smoothstep(0.4, 0.75, vnoise(p * 6.0) + n2 * 0.3)) * (0.85 + n4 * 0.3);
		gap = mix(gap, hole, cgone * smoothstep(0.0, 0.12, ce0 + 0.1));
		base = mix(base, mix(gap, stonec, cm), cob);
	}
	float cliff = clamp(vcol.g + (1.0 - wnorm.y) * 2.0, 0.0, 1.0);
	base = mix(base, col_cliff * (0.6 + n2 * 0.5 + (n4 - 0.5) * 0.2), cliff);
	// sea cliffs (the coast and the isles): layered rock projected on the face, not the ground plane:
	// strata bands of different stone, blocky joints, ledges that catch the light, lichen up top
	float ledge = 0.0;
	if (sea > 0.0 && cliff > 0.02) {
		vec3 an = abs(wnorm);
		vec2 q = an.x > an.z ? vec2(wpos.z, wpos.y) : vec2(wpos.x, wpos.y);
		float wob = fbm(q * vec2(0.035, 0.02)) * 4.0 + fbm(q * 0.3) * 0.7;
		float lay = wpos.y * 0.42 + wob;
		float band = floor(lay);
		float bh = hash21(vec2(band, 3.1));
		float bf = fract(lay);
		vec3 rock = col_cliff * mix(0.66, 1.2, bh);
		rock = mix(rock, rock * vec3(1.1, 1.02, 0.88), step(0.62, hash21(vec2(band, 7.7))) * 0.55);
		rock *= 0.78 + fbm(q * 0.04 + 4.0) * 0.45;                                   // big tonal patches
		rock *= 0.86 + fbm(vec2(q.x * 0.7, q.y * 0.06) + 2.0) * 0.28;               // rain streaks down the face
		float jid = 0.0;
		vec2 jv = vor(vec2(q.x * 0.16, lay * 0.7), jid);
		float joint = (1.0 - smoothstep(0.015, 0.07, jv.y - jv.x)) * smoothstep(0.45, 0.7, fbm(q * 0.12 + 5.0));
		rock *= 0.88 + jid * 0.18 + fbm3(q * 1.3) * 0.22 + (n4 - 0.5) * 0.1;
		rock *= 1.0 - joint * 0.5;
		rock *= 1.0 - (1.0 - smoothstep(0.0, 0.07, bf)) * 0.4 * step(0.35, bh);    // a seam under some ledges
		float lich = smoothstep(0.55, 0.8, fbm(q * 0.25 + 9.0)) * smoothstep(1.0, 4.0, wpos.y) * 0.5;
		rock = mix(rock, col_a * 0.9, lich);
		float rk = smoothstep(0.25, 0.7, cliff);
		base = mix(base, rock, rk);
		ledge = (smoothstep(0.88, 1.0, bf) * step(0.35, bh) * 0.6 - (1.0 - smoothstep(0.0, 0.07, bf)) * 0.35 * step(0.35, bh) - joint * 0.3) * rk;
	}
	float wetf = wet * smoothstep(0.5, 0.72, n2) * (1.0 - cliff) * (0.4 + path * 0.6);
	base *= 1.0 - wetf * 0.3;
	float wetb = 0.0;
	if (sea > 0.0) {
		float hy = wpos.y + (n2 - 0.5) * 0.6 + (n4 - 0.5) * 0.15;
		float sandm = (1.0 - smoothstep(0.85, 1.5, hy)) * (1.0 - cliff * 0.85);
		vec3 sand = col_sand * (0.86 + n3 * 0.2 + (n4 - 0.5) * 0.12);
		sand = mix(sand, sand * vec3(0.86, 0.84, 0.76), smoothstep(0.5, 0.8, n5) * 0.5);
		sand *= 0.95 + 0.05 * sin(p.x * 2.3 + p.y * 1.1 + n2 * 6.0);
		float shellm = smoothstep(0.9, 0.95, vnoise(p * 11.0)) * 0.35;
		sand = mix(sand, vec3(0.78, 0.76, 0.7), shellm);
		base = mix(base, sand, sandm);
		// the waterline: dark glossy wet sand where the swash reaches
		wetb = (1.0 - smoothstep(-0.05, 0.4, wpos.y)) * (1.0 - cliff * 0.5);
		base *= 1.0 - wetb * 0.38;
		// under the water: the seabed fading darker with depth, weed in patches, sunlight caustics
		float uw = smoothstep(0.0, -0.35, wpos.y);
		float deep = smoothstep(0.0, -11.0, wpos.y);
		vec3 bed = mix(sand, col_a * 0.75, smoothstep(0.55, 0.75, n1) * 0.55);
		bed = mix(bed, col_cliff * 0.7, cliff * 0.7);
		base = mix(base, bed * (1.0 - deep * 0.6), uw);
		if (uw > 0.01) {
			float cid1 = 0.0;
			float cid2 = 0.0;
			vec2 v1 = vor(p * 1.7 + vec2(ocean_t * 0.23, ocean_t * 0.11), cid1);
			vec2 v2 = vor(p * 2.3 - vec2(ocean_t * 0.15, -ocean_t * 0.19) + 3.7, cid2);
			float e1 = 1.0 - smoothstep(0.0, 0.12, v1.y - v1.x);
			float e2 = 1.0 - smoothstep(0.0, 0.12, v2.y - v2.x);
			float caus = e1 * e2 * 1.6 + (e1 + e2) * 0.18;
			base += base * caus * 0.8 * uw * (1.0 - smoothstep(-0.4, -6.0, wpos.y));
		}
	}
	float cover = 0.0;
	float trod = 0.0;
	float drift = 0.5;
	if (snow_amt > 0.0) {
		drift = fbm(p * 0.11 + 5.0);
		float steep = clamp((1.0 - wnorm.y) * 2.6, 0.0, 1.0);
		cover = snow_amt * smoothstep(0.1, 0.42, 0.55 - steep * 0.9 + (drift - 0.5) * 0.7 + (n3 - 0.5) * 0.25);
		cover *= 1.0 - smoothstep(0.55, 0.95, vcol.g) * 0.6;
		// the road is packed into grey slush with ruts; cobbles poke through
		trod = path * (0.55 + 0.45 * smoothstep(0.25, 0.75, n2 * 0.6 + n4 * 0.3 + 0.2)) + cob * cm * 0.6;
		trod = clamp(trod, 0.0, 1.0);
		float rut = smoothstep(0.65, 0.95, abs(sin(p.x * 2.4 + n2 * 4.0))) * path * 0.35;
		vec3 snowcol = vec3(0.8, 0.84, 0.91) * (0.9 + n3 * 0.1 + (n4 - 0.5) * 0.04);
		snowcol = mix(snowcol, vec3(0.66, 0.74, 0.9), smoothstep(0.5, 0.15, drift) * 0.4);
		vec3 slush = mix(vec3(0.5, 0.49, 0.48), vec3(0.3, 0.27, 0.24), smoothstep(0.3, 0.75, n3) + rut);
		base = mix(base, mix(snowcol, slush, trod * 0.9), cover);
	}
	if (ash_amt > 0.0) {
		// scorched earth: charcoal and grey ash, dusty ash on the roads
		vec3 charc = mix(vec3(0.07, 0.06, 0.055), vec3(0.17, 0.15, 0.13), n3);
		vec3 ashg = mix(vec3(0.33, 0.31, 0.29), vec3(0.47, 0.45, 0.42), n4);
		vec3 burnt = mix(charc, ashg, smoothstep(0.45, 0.78, fbm(p * 0.35 + 3.0)) * 0.85);
		burnt = mix(burnt, vec3(0.3, 0.28, 0.26) * (0.85 + n4 * 0.3), path * 0.75);
		burnt = mix(burnt, col_cliff * 0.35, cliff * 0.6);
		base = mix(base, burnt * (0.85 + n3 * 0.2), ash_amt);
	}
	ALBEDO = base;
	ROUGHNESS = mix(mix(mix(0.95, 0.35, wetf), 0.3, wetb), 0.55 + trod * 0.35, cover);
	if (ash_amt > 0.0) {
		// glowing cracks and smouldering patches that pulse slowly
		float cv = abs(fbm(p * 0.17 + 3.0) - 0.5);
		float cr = (1.0 - smoothstep(0.0, 0.016, cv)) * smoothstep(0.5, 0.68, fbm(p * 0.05 + 9.0));
		float hotspot = smoothstep(0.9, 0.97, vnoise(p * 2.6)) * smoothstep(0.45, 0.7, n2);
		float pulse = 0.65 + 0.35 * sin(TIME * 1.3 + p.x * 0.25 + p.y * 0.17);
		float keep = ash_amt * (1.0 - path) * (1.0 - cliff * 0.7);
		float glow = (cr * 1.7 + hotspot * 0.8) * pulse * keep;
		EMISSION = vec3(1.0, 0.32, 0.06) * glow;
		ALBEDO = mix(ALBEDO, vec3(0.2, 0.05, 0.02), clamp(cr * 0.9 + hotspot * 0.5, 0.0, 1.0) * keep);
	}
	if (cover > 0.0) {
		// tiny ice crystals glinting in the light
		vec2 gc = floor(p * 38.0);
		float g = step(0.988, hash21(gc)) * cover * (1.0 - trod);
		float tw = 0.5 + 0.5 * sin(TIME * 2.5 + hash21(gc + 3.1) * 60.0);
		EMISSION = vec3(0.85, 0.92, 1.0) * g * tw * 0.9;
	}
	if (under_amt > 0.0) {
		// the Underworld: bone-pale ground, veins of violet soul-light that crawl slowly,
		// and rings of crimson runes rippling outward from the Demon
		vec3 bone = mix(vec3(0.07, 0.05, 0.09), vec3(0.2, 0.16, 0.24), n3) * (0.8 + n4 * 0.3);
		ALBEDO = mix(ALBEDO, bone * 1.6, under_amt * 0.55);
		float vv = abs(fbm(p * 0.21 + vec2(TIME * 0.04, -TIME * 0.025)) - 0.5);
		float vein = (1.0 - smoothstep(0.0, 0.018, vv)) * (0.6 + 0.4 * sin(TIME * 2.0 + p.x * 0.3));
		vec2 dp = wpos.xz - player_pos.xz;
		float d = length(dp);
		float wave = fract(d * 0.18 - TIME * 0.35);
		float ringl = smoothstep(0.0, 0.03, wave) * (1.0 - smoothstep(0.03, 0.08, wave));
		float ang = atan(dp.y, dp.x);
		float runes = step(0.5, fract(ang * 9.549 + floor(d * 0.18 - TIME * 0.35) * 0.37));
		float fade = 1.0 - smoothstep(6.0, 16.0, d);
		EMISSION += (vec3(0.55, 0.22, 1.0) * vein * 1.3 + vec3(1.0, 0.08, 0.16) * ringl * runes * 1.6 * fade) * under_amt;
	}
	float e = 0.05;
	float sc = 1.8;
	float hc = fbm3(p * sc); float hx = fbm3((p + vec2(e, 0.0)) * sc); float hz = fbm3((p + vec2(0.0, e)) * sc);
	vec3 wn = normalize(wnorm + vec3(hc - hx, 0.0, hc - hz) * (2.0 + path) / e * 0.05 * (1.0 - cover * 0.8));
	if (ledge != 0.0) {
		wn = normalize(wn + vec3(0.0, ledge * 0.9, 0.0));
	}
	if (cover > 0.0) {
		// soft wind-blown drift ripples
		float dd = 0.4;
		float d0 = fbm(p * 0.6 + 2.0); float dx = fbm((p + vec2(dd, 0.0)) * 0.6 + 2.0); float dz = fbm((p + vec2(0.0, dd)) * 0.6 + 2.0);
		wn = normalize(wn + vec3(d0 - dx, 0.0, d0 - dz) * 1.4 * cover);
	}
	if (cob > 0.01) {
		// the stones' relief (about 9 cm from joint to crown) from the same height the colour used
		float ce = 0.015; float i1; float i2; float i3; float i4;
		float ha = cobble(p + vec2(ce, 0.0), i1, i2, i3, i4);
		float hb = cobble(p + vec2(0.0, ce), i1, i2, i3, i4);
		wn = normalize(wn + vec3(ch - ha, 0.0, ch - hb) * (0.09 / ce) * cob * (1.0 - cover * 0.5));
		ROUGHNESS = mix(ROUGHNESS, mix(0.82, 0.6, cwear), cob * cm);
	}
	if (pebg.x != 0.0 || pebg.y != 0.0) {
		wn = normalize(wn + vec3(-pebg.x, 0.0, -pebg.y) * (1.0 - cob) * (1.0 - cover * 0.8));
	}
	if (tiles > 0.0 && path > 0.5) {
		float ex = 0.03; float tidx;
		vec2 ta = vor((p + vec2(ex, 0.0)) * 1.3, tidx); vec2 tb = vor((p + vec2(0.0, ex)) * 1.3, tidx);
		wn = normalize(wn + vec3(tm - smoothstep(0.02, 0.09, ta.y - ta.x), 0.0, tm - smoothstep(0.02, 0.09, tb.y - tb.x)) * 3.0);
	}
	AO = mix(1.0, 0.55, (1.0 - smoothstep(0.0, 0.42, mix(ch, 0.45, cgone))) * cob);   // a hole is mud, not a pit
	NORMAL = normalize((VIEW_MATRIX * vec4(wn, 0.0)).xyz);
	if (cracks > 0.0) {
		float v = abs(fbm(p * 0.22 + 3.0) - 0.5);
		float c = 1.0 - smoothstep(0.0, 0.035, v);
		float pulse = 0.75 + 0.25 * sin(TIME * 1.7 + p.x * 0.3 + p.y * 0.2);
		EMISSION = crack_col * c * cracks * pulse * 3.0 * (1.0 - path * 0.7);
		ALBEDO = mix(ALBEDO, crack_col * 0.3, c * 0.8);
	}
}
"""

const GRASS_SHADER := """
shader_type spatial;
render_mode cull_disabled, diffuse_burley, specular_disabled;
uniform vec3 base_col : source_color = vec3(0.12, 0.16, 0.05);
uniform vec3 tip_col : source_color = vec3(0.45, 0.45, 0.2);
uniform vec3 dry_col : source_color = vec3(0.5, 0.4, 0.2);
uniform float wind = 1.0;
varying float hgt;
varying vec3 wpos;
""" + NOISE_LIB + """
void vertex(){
	hgt = UV.y;
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float w = sin(TIME * 1.6 + wpos.x * 0.35 + wpos.z * 0.22) + sin(TIME * 2.7 + wpos.x * 0.9) * 0.35;
	VERTEX.x += w * 0.12 * hgt * hgt * wind;
	VERTEX.z += w * 0.06 * hgt * hgt * wind;
	NORMAL = vec3(0.0, 1.0, 0.0);
}
void fragment(){
	float n = vnoise(wpos.xz * 0.15);
	vec3 tip = mix(tip_col, dry_col, smoothstep(0.4, 0.8, n));
	ALBEDO = mix(base_col, tip, hgt);
	BACKLIGHT = vec3(0.25) * hgt;
	ROUGHNESS = 0.9;
	AO = mix(0.6, 1.0, hgt);
	AO_LIGHT_AFFECT = 0.4;
}
"""

const WATER_SHADER := """
shader_type spatial;
render_mode blend_mix, cull_back, specular_schlick_ggx, depth_draw_always;
uniform vec3 deep : source_color = vec3(0.03, 0.07, 0.06);
uniform vec3 shallow : source_color = vec3(0.12, 0.2, 0.14);
""" + NOISE_LIB + """
varying vec3 wpos;
void vertex(){ wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }
void fragment(){
	vec2 p = wpos.xz;
	float t = TIME * 0.25;
	float e = 0.08;
	float h0 = fbm3(p * 0.9 + vec2(t, t * 0.6)) + fbm3(p * 1.7 - vec2(t * 0.8, -t));
	float hx = fbm3((p + vec2(e, 0.0)) * 0.9 + vec2(t, t * 0.6)) + fbm3((p + vec2(e, 0.0)) * 1.7 - vec2(t * 0.8, -t));
	float hz = fbm3((p + vec2(0.0, e)) * 0.9 + vec2(t, t * 0.6)) + fbm3((p + vec2(0.0, e)) * 1.7 - vec2(t * 0.8, -t));
	vec3 wn = normalize(vec3((h0 - hx) * 1.2, 1.0, (h0 - hz) * 1.2));
	NORMAL = normalize((VIEW_MATRIX * vec4(wn, 0.0)).xyz);
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 4.0);
	ALBEDO = mix(deep, shallow, h0 * 0.5);
	ROUGHNESS = 0.06;
	METALLIC = 0.2;
	SPECULAR = 0.8;
	ALPHA = mix(0.82, 0.97, fres);
}
"""

const LAVA_SHADER := """
shader_type spatial;
render_mode cull_back, diffuse_burley;
""" + NOISE_LIB + """
varying vec3 wpos;
void vertex(){ wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }
void fragment(){
	vec2 p = wpos.xz * 0.35;
	float t = TIME * 0.12;
	float n = fbm(p + vec2(fbm(p * 1.5 + t), fbm(p * 1.3 - t)) * 1.6);
	float crust = smoothstep(0.42, 0.6, n);
	vec3 hot = mix(vec3(1.0, 0.85, 0.3), vec3(1.0, 0.3, 0.02), smoothstep(0.2, 0.5, n));
	ALBEDO = mix(vec3(0.05, 0.02, 0.01), vec3(0.08, 0.03, 0.02), crust);
	EMISSION = hot * (1.0 - crust) * 4.0;
	ROUGHNESS = mix(0.4, 0.9, crust);
}
"""

const CLOTH_SHADER := """
shader_type spatial;
render_mode cull_disabled, diffuse_burley;
uniform vec3 albedo : source_color = vec3(0.6, 0.1, 0.1);
uniform vec3 trim : source_color = vec3(0.8, 0.65, 0.2);
uniform float wave = 1.0;
uniform float stripes = 0.0;
uniform float edges = 1.0;
global uniform float ash_amt;
varying vec3 cwp;
float ch(vec2 p){ p = fract(p * vec2(123.34, 456.21)); p += dot(p, p + 45.32); return fract(p.x * p.y); }
float cn(vec2 p){ vec2 i = floor(p); vec2 f = fract(p); vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(ch(i), ch(i + vec2(1.0, 0.0)), u.x), mix(ch(i + vec2(0.0, 1.0)), ch(i + vec2(1.0, 1.0)), u.x), u.y); }
void vertex(){
	float w = sin(TIME * 2.2 + VERTEX.x * 3.0 + VERTEX.y * 1.5) * 0.08 * wave;
	VERTEX.z += w * UV.y;
	cwp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}
void fragment(){
	float edge = (step(0.9, UV.y) + step(UV.x, 0.06) + step(0.94, UV.x)) * edges;
	vec3 c = mix(albedo, trim, clamp(edge, 0.0, 1.0));
	float stripe = step(0.45, UV.y) * step(UV.y, 0.55) * edges;
	c = mix(c, trim, stripe * 0.6);
	if (stripes > 0.0) { c = mix(albedo, trim, step(0.5, fract(UV.x * stripes))); }
	vec3 em = vec3(0.0);
	if (ash_amt > 0.0) {
		// scorched cloth: burned-through holes with glowing edges, soot creeping up from the hem
		float hn = cn(UV * vec2(5.0, 4.0) + cwp.xz * 0.4) * 0.65 + cn(UV * 13.0) * 0.35;
		if (hn > 0.68) { discard; }
		float rim = smoothstep(0.58, 0.68, hn);
		c = mix(c * 0.32, vec3(0.03, 0.02, 0.015), clamp(rim + (1.0 - UV.y) * 0.3, 0.0, 1.0) * ash_amt);
		em = vec3(1.0, 0.36, 0.07) * rim * rim * 2.2 * ash_amt * (0.7 + 0.3 * sin(TIME * 3.0 + cwp.x * 4.0));
	}
	ALBEDO = c;
	EMISSION = em;
	ROUGHNESS = 0.95;
	BACKLIGHT = c * 0.4;
}
"""

const ORB_SHADER := """
shader_type canvas_item;
uniform vec4 liquid : source_color = vec4(0.75, 0.05, 0.05, 1.0);
uniform vec4 liquid2 : source_color = vec4(0.35, 0.0, 0.0, 1.0);
uniform float fill = 1.0;
uniform float flash = 0.0;
float h(vec2 p){ return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453); }
float n2(vec2 p){ vec2 i=floor(p); vec2 f=fract(p); vec2 u=f*f*(3.0-2.0*f);
	return mix(mix(h(i),h(i+vec2(1,0)),u.x), mix(h(i+vec2(0,1)),h(i+vec2(1,1)),u.x), u.y); }
void fragment(){
	vec2 uv = UV * 2.0 - 1.0;
	float r = length(uv);
	if (r > 1.0) { discard; }
	float z = sqrt(1.0 - r * r);
	vec3 n = vec3(uv.x, -uv.y, z);
	float level = 1.0 - fill * 2.0;
	float wave = sin(uv.x * 6.0 + TIME * 2.5) * 0.025 + sin(uv.x * 11.0 - TIME * 3.1) * 0.012;
	float inside = step(level + wave, uv.y);
	float swirl = n2(uv * 3.5 + vec2(TIME * 0.4, -TIME * 0.6)) * 0.6 + n2(uv * 7.0 - TIME * 0.3) * 0.4;
	vec3 lc = mix(liquid2.rgb, liquid.rgb, swirl * 0.8 + z * 0.4);
	vec3 glass = vec3(0.02, 0.02, 0.025);
	vec3 col = mix(glass, lc, inside);
	float surf = (1.0 - smoothstep(0.0, 0.03, abs(uv.y - (level + wave)))) * inside;
	col += liquid.rgb * surf * 0.8;
	float spec = pow(max(dot(n, normalize(vec3(-0.5, 0.6, 0.8))), 0.0), 40.0);
	col += vec3(spec) * 0.9;
	col += vec3(0.25) * pow(1.0 - z, 3.0);
	col += flash * vec3(1.0, 0.9, 0.7) * 0.5;
	col *= mix(0.55, 1.0, z);
	float rim = smoothstep(0.92, 1.0, r);
	COLOR = vec4(mix(col, vec3(0.0), rim), 1.0);
}
"""
