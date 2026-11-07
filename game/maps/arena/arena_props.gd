class_name ArenaProps
extends RefCounted
## The Arena hall's pieces (game/maps/arena/): Meshy models re-baked onto clean UVs (props/), the tiled crypt stone of its
## walls (textures/), and the see-through that keeps a pillar from hiding the hero. Made for the Hollow Crypt in
## 2026-11 (tools/blender/battlegrounds/); the Arena is what still uses them.

const DIR := "res://game/maps/arena/props/"
const TEX := "res://game/maps/arena/textures/"
const RUNE := Color(0.3, 0.55, 1.0)           # (SEE_SHADER's rune colour; the hall's pieces have none lit)
const PILLAR_H := 4.0                         # pillar.glb as prepared (--xy 0.6: slim enough for the 0.55 m circle)
const SCONCE_CUP := Vector3(0.0, 0.46, 0.06)  # where the torch flame stands in sconce.glb (its own frame)
const TORCH_ENERGY := 2.4                     # the wall torches' warm pool (torch_light)
const TORCH_RANGE := 8.5
const TILE := 12.0                            # wall meshes are cut into tiles this size (the OpenGL renderer lights a
                                              # mesh by at most eight lights)
const CANDLE_WICKS := [Vector3(-0.2638, 0.271, -0.0086), Vector3(-0.1733, 0.2579, -0.0072), Vector3(-0.0988, 0.2816, -0.0115),
	Vector3(-0.0542, 0.2228, 0.0349), Vector3(-0.0033, 0.3058, -0.0115), Vector3(0.0543, 0.2242, 0.0351),
	Vector3(0.0991, 0.2933, -0.0109), Vector3(0.1736, 0.2645, -0.0106), Vector3(0.2563, 0.2685, -0.0101)]

static var _cache := {}

static func has(name: String) -> bool:
	return ResourceLoader.exists(DIR + name + ".glb")

## A fresh instance of a prepared model, or null without the file.
static func model(name: String) -> Node3D:
	if not has(name):
		return null
	return (load(DIR + name + ".glb") as PackedScene).instantiate()

## The model's bounds in its own frame (it isn't in the tree yet, so the transforms are walked by hand).
static func bounds(root: Node3D) -> AABB:
	var out := AABB()
	var first := true
	for n in root.find_children("*", "MeshInstance3D", true, false):
		var mi: MeshInstance3D = n
		var xf := Transform3D.IDENTITY
		var p: Node = mi
		while p != null and p != root:
			if p is Node3D:
				xf = (p as Node3D).transform * xf
			p = p.get_parent()
		var b := xf * mi.get_aabb()
		out = b if first else out.merge(b)
		first = false
	return out

static func _no_shadow(root: Node3D) -> void:
	for mi in root.find_children("*", "MeshInstance3D", true, false):
		(mi as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

## A pillar `h` metres tall: the Meshy pillar scaled to the height, no wider than as prepared (its base fits the
## 0.55 m collision circle).
static func pillar(h: float) -> Node3D:
	var m := model("pillar")
	if m == null:
		return null
	var k := h / PILLAR_H
	m.scale = Vector3(minf(k, 1.0), k, minf(k, 1.0))
	see_through(m)
	return m

static func bones(yaw: float) -> Node3D:
	var m := model("bones")
	if m == null:
		return null
	m.rotation.y = yaw
	m.scale = Vector3.ONE * 0.85
	_no_shadow(m)
	return m

## The iron wall sconce: its back plate toward -z (the wall), its cup toward the room. The flame goes at SCONCE_CUP.
static func sconce() -> Node3D:
	return model("sconce")

## A wall torch's light: a warm pool that reaches the floor in front of its wall. The torch
## preset at the sconce's size lit 3.9 m, a patch of wall, and left the rooms to the hero's own light.
static func torch_light(fire: Node3D) -> void:
	var l := fire.get_node_or_null("FireLight") as OmniLight3D
	if l == null:
		return
	l.light_energy = TORCH_ENERGY
	l.omni_range = TORCH_RANGE
	l.set_meta("base", TORCH_ENERGY)
	l.position.z += 0.35          # out from the wall: the pool lands on the floor, not only on the stones behind it

# ---------------------------------------------------------------- the see-through
const SEE_SHADER := """
shader_type spatial;
render_mode blend_mix, cull_back, diffuse_burley, specular_schlick_ggx;
global uniform vec3 player_pos;
global uniform float occlude_k;
uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap_anisotropic;
uniform sampler2D mr_tex : hint_default_white, filter_linear_mipmap;
uniform vec4 albedo : source_color = vec4(1.0);
uniform float roughness = 1.0;
uniform float metallic = 0.0;
uniform float normal_depth = 1.0;
uniform float use_normal = 1.0;
uniform vec3 rune_col : source_color = vec3(0.3, 0.55, 1.0);
uniform float rune_energy = 0.0;
varying vec3 wpos;
float bayer2(vec2 a){ a = floor(a); return fract(a.x / 2.0 + a.y * a.y * 0.75); }
float dith(vec2 a){ return bayer2(0.5 * a) * 0.25 + bayer2(a) + 0.03125; }
void vertex(){
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}
void fragment(){
	// the see-through near the player, as the walls and the code-built props have (Mats PROP_SHADER)
	vec3 d = wpos - player_pos;
	float h = wpos.y - player_pos.y;
	float along = d.z - occlude_k * (h - 1.0);
	float cover = (1.0 - smoothstep(1.6, 3.2, abs(along))) * (1.0 - smoothstep(2.2, 3.6, abs(d.x)));
	cover *= step(0.9, h) * step(0.2, d.z);
	if (cover * 0.9 > dith(FRAGCOORD.xy)) { discard; }
	vec3 c = texture(albedo_tex, UV).rgb;
	ALBEDO = c * albedo.rgb;
	vec4 mr = texture(mr_tex, UV);
	ROUGHNESS = mr.g * roughness;
	METALLIC = mr.b * metallic;
	if (use_normal > 0.5) {
		NORMAL_MAP = texture(normal_tex, UV).rgb;
		NORMAL_MAP_DEPTH = normal_depth;
	}
	if (rune_energy > 0.0) {
		// the runes Meshy painted blue into the stone light up
		float rune = smoothstep(0.05, 0.16, c.b - max(c.r, c.g));
		EMISSION = rune_col * rune * rune_energy * (0.85 + 0.15 * sin(TIME * 2.3 + wpos.y * 3.0));
	}
}
"""

## Gives a Meshy prop the see-through near the player that the crypt's walls and code-built props have: its
## imported materials (albedo, normal and the glTF metal-rough map) redrawn by SEE_SHADER. The tall pieces needed it:
## a hall pillar between the camera and the hero hid him. `own` = materials of its own (a gate's runes are lit
## one gate at a time); otherwise shared by every prop drawn from the same imported material.
static func see_through(root: Node3D, own := false) -> void:
	for n in root.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if mi.mesh == null:
			continue
		for si in mi.mesh.get_surface_count():
			var src := mi.get_active_material(si) as StandardMaterial3D
			if src == null:
				continue
			var key := "see_%d" % src.get_instance_id()
			var sm: ShaderMaterial = null
			if not own and _cache.has(key):
				sm = _cache[key]
			else:
				sm = ShaderMaterial.new()
				if not _cache.has("see_shader"):
					var sh := Shader.new()
					sh.code = SEE_SHADER
					_cache["see_shader"] = sh
				sm.shader = _cache["see_shader"]
				sm.set_shader_parameter("albedo_tex", src.albedo_texture)
				sm.set_shader_parameter("albedo", src.albedo_color)
				sm.set_shader_parameter("normal_tex", src.normal_texture)
				sm.set_shader_parameter("use_normal", 1.0 if src.normal_enabled and src.normal_texture != null else 0.0)
				sm.set_shader_parameter("normal_depth", src.normal_scale)
				sm.set_shader_parameter("mr_tex", src.roughness_texture if src.roughness_texture != null else src.metallic_texture)
				sm.set_shader_parameter("roughness", src.roughness)
				sm.set_shader_parameter("metallic", src.metallic)
				sm.set_shader_parameter("rune_col", Vector3(RUNE.r, RUNE.g, RUNE.b))
				if not own:
					_cache[key] = sm
			mi.set_surface_override_material(si, sm)


## A row of nine melted candles on a stone slab (candles.glb: Meshy, its modelled flames cut away by
## tools/blender/battlegrounds/cut_flames.py, which wrote CANDLE_WICKS), each wick burning FireFx's candle flame,
## one light for the row. The row runs along x, its short candles toward +z.
static func candles() -> Node3D:
	var m := model("candles")
	if m == null:
		return null
	var root := Models.N(null, "candles")
	root.add_child(m)
	for wk in CANDLE_WICKS:
		FireFx.make(root, (wk as Vector3) + Vector3(0, 0.004, 0), "candle", 0.16, Color(1.0, 0.72, 0.35), false, false, false)
	var l := OmniLight3D.new()
	l.light_color = Color(1.0, 0.66, 0.32)
	l.light_energy = 0.95
	l.omni_range = 4.2
	l.omni_attenuation = 1.3
	l.position = Vector3(0, 0.55, 0.25)
	l.add_to_group("flicker")
	l.set_meta("base", 0.95)
	l.set_meta("fire", 0.3)
	root.add_child(l)
	return root


const WALL_SHADER := """
shader_type spatial;
render_mode blend_mix, cull_back, diffuse_burley, specular_schlick_ggx;
global uniform vec3 player_pos;
global uniform float occlude_k;
uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float tile = 0.5;          // texture repeats per metre
uniform float roughness = 0.92;
uniform vec3 tint : source_color = vec3(1.0);
uniform float moss = 0.35;
uniform vec3 moss_col : source_color = vec3(0.2, 0.28, 0.12);
uniform float occlude = 1.0;
varying vec3 wpos;
varying vec3 wnorm;
float hash21(vec2 p){ p = fract(p*vec2(123.34, 456.21)); p += dot(p, p+45.32); return fract(p.x*p.y); }
float bayer2(vec2 a){ a = floor(a); return fract(a.x / 2.0 + a.y * a.y * 0.75); }
float dith(vec2 a){ return bayer2(0.5 * a) * 0.25 + bayer2(a) + 0.03125; }
float vnoise(vec2 p){ vec2 i=floor(p); vec2 f=fract(p); vec2 u=f*f*(3.0-2.0*f);
	return mix(mix(hash21(i),hash21(i+vec2(1.0,0.0)),u.x), mix(hash21(i+vec2(0.0,1.0)),hash21(i+vec2(1.0,1.0)),u.x), u.y); }
float fbm3(vec2 p){ float v=0.0; float a=0.5; for(int i=0;i<3;i++){ v+=a*vnoise(p); p=p*2.03+vec2(1.7,9.2); a*=0.5; } return v; }
void vertex(){
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnorm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}
void fragment(){
	if (occlude > 0.5) {
		// the see-through near the player, as every prop has (Mats PROP_SHADER)
		vec3 d = wpos - player_pos;
		float h = wpos.y - player_pos.y;
		float along = d.z - occlude_k * (h - 1.0);
		float cover = (1.0 - smoothstep(1.6, 3.2, abs(along))) * (1.0 - smoothstep(2.2, 3.6, abs(d.x)));
		cover *= step(0.9, h) * step(0.2, d.z);
		if (cover * 0.9 > dith(FRAGCOORD.xy)) { discard; }
	}
	// world-space mapping, the side that faces the normal (every wall block is axis-aligned, give or take a degree):
	// u runs to the right of someone facing the wall, v down the wall (the image's top at the top), so the normal
	// map's tangent frame is t (right) and up
	vec3 an = abs(wnorm);
	vec2 uv;
	vec3 t;
	vec3 bt;
	if (an.y > 0.6) { uv = wpos.xz; t = vec3(1.0, 0.0, 0.0); bt = vec3(0.0, 0.0, -1.0); }
	else if (an.x > an.z) { uv = vec2(-wpos.z * sign(wnorm.x), -wpos.y); t = vec3(0.0, 0.0, -sign(wnorm.x)); bt = vec3(0.0, 1.0, 0.0); }
	else { uv = vec2(wpos.x * sign(wnorm.z), -wpos.y); t = vec3(sign(wnorm.z), 0.0, 0.0); bt = vec3(0.0, 1.0, 0.0); }
	uv *= tile;
	vec3 col = texture(albedo_tex, uv).rgb * tint;
	// slow variation across the room so no two blocks read the same, grime toward the floor, moss in the damp
	float big = fbm3(wpos.xz * 0.11 + wpos.y * 0.05);
	col *= 0.82 + big * 0.36;
	col *= mix(0.72, 1.0, smoothstep(0.0, 1.1, wpos.y));
	float mossf = moss * smoothstep(0.45, 0.85, fbm3(wpos.xz * 0.6 + wpos.y * 0.9 + 7.0) + (1.0 - smoothstep(0.3, 1.6, wpos.y)) * 0.25);
	col = mix(col, moss_col * (0.75 + big * 0.5), clamp(mossf, 0.0, 0.85));
	ALBEDO = col;
	vec3 nm = texture(normal_tex, uv).rgb * 2.0 - 1.0;
	vec3 wn = normalize(wnorm);
	vec3 n = normalize(t * nm.x + bt * nm.y + wn * nm.z * 1.4);
	NORMAL = (VIEW_MATRIX * vec4(n, 0.0)).xyz;
	ROUGHNESS = roughness - mossf * 0.1;
	METALLIC = 0.0;
}
"""

## The hall's wall: baked stone blocks (TEX wall_albedo / wall_normal), else plain procedural stone.
static func wall_material() -> Material:
	if _cache.has("wall"):
		return _cache["wall"]
	var m: Material
	if ResourceLoader.exists(TEX + "wall_albedo.png") and ResourceLoader.exists(TEX + "wall_normal.png"):
		var sm := ShaderMaterial.new()
		var sh := Shader.new()
		sh.code = WALL_SHADER
		sm.shader = sh
		sm.set_shader_parameter("albedo_tex", load(TEX + "wall_albedo.png"))
		sm.set_shader_parameter("normal_tex", load(TEX + "wall_normal.png"))
		sm.set_shader_parameter("tile", 0.5)
		sm.set_shader_parameter("tint", Vector3(0.92, 0.9, 0.86))
		m = sm
	else:
		m = Mats.world(Color(0.36, 0.34, 0.31), Color(0.24, 0.23, 0.21), 0.92, 2.2, 0.3, Color(0.14, 0.16, 0.09))
	_cache["wall"] = m
	return m

## The plain wall blocks (what `walls` leaves) in tiles of TILE metres, one MultiMesh each, under the crypt stone:
## one MultiMesh round the whole crypt took only eight of its torches in the OpenGL renderer.
static func wall_meshes(w: World, wall_xf: Array) -> void:
	var tiles := {}
	for xf in wall_xf:
		var o: Vector3 = (xf as Transform3D).origin
		var key := Vector2i(floori(o.x / TILE), floori(o.z / TILE))
		if not tiles.has(key):
			tiles[key] = []
		(tiles[key] as Array).append(xf)
	var mesh := Geo.box(1.02, 1.0, 1.02)
	var wm := wall_material()
	for key in tiles:
		Props.multimesh(w.props_root, mesh, tiles[key]).material_override = wm
