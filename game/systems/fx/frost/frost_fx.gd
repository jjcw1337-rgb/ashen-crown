class_name FrostFx
extends RefCounted
## The shared frost toolkit: the frost palette, its shaders (ground, streak, rim, body), the hoarfrost texture, the
## Meshy ice crystals and their shattering, and the frost on a chilled foe's body (rime crawling up it, cold vapour
## falling off it; one that dies frozen shatters). Frost Volley, the Serpent, the dragons and every chilled monster
## draw with it. Draws only. `update_bodies` runs once a frame (SkillFx.update).

const CRYSTAL := "res://assets/models/fx/frost/crystal.glb"
const CRYSTAL_PIECES := "res://assets/models/fx/frost/crystal_pieces.glb"
const HOARFROST := "res://assets/textures/fx/frost/hoarfrost.png"
const PALE := Color(0.82, 0.94, 1.0)
const DEEP := Color(0.25, 0.55, 0.95)
const MIST := Color(0.72, 0.82, 0.92)

static var _shaders := {}
static var _tex: Texture2D
static var _bodies := {}
static var _body_frame := -1

static func shader(key: String) -> Shader:
	if not _shaders.has(key):
		var s := Shader.new()
		s.code = {"ground": GROUND_SHADER, "streak": STREAK_SHADER, "rim": RIM_SHADER, "body": BODY_SHADER}[key]
		_shaders[key] = s
	return _shaders[key]

static func hoarfrost() -> Texture2D:
	if _tex == null and ResourceLoader.exists(HOARFROST):
		_tex = load(HOARFROST)
	return _tex

static func mat(key: String) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = shader(key)
	return m

## A Meshy ice-crystal cluster bursting up out of the ground at p, `s` metres tall: grows with an overshoot, its blue
## lit from inside (the albedo's own blues glow) and a cold rim.
static func crystal(root: Node3D, p: Vector3, s: float, tr: int) -> Node3D:
	var n := DemonKitFx.model(CRYSTAL)
	if n == null:
		return null
	DemonKitFx.heat_model(n, 0.9, Color(0.45, 0.75, 1.0))
	var rim := mat("rim")
	rim.set_shader_parameter("col", PALE)
	rim.set_shader_parameter("glow", 1.6)
	for mi in n.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		m.material_overlay = rim
		for i in m.get_surface_override_material_count():
			var c = m.get_surface_override_material(i)
			if c is StandardMaterial3D:
				(c as StandardMaterial3D).roughness = 0.12
				(c as StandardMaterial3D).metallic_specular = 0.9
	n.set_meta("rim", rim)
	root.add_child(n)
	n.global_position = p + Vector3(0, -0.06 * s, 0)
	n.rotation = Vector3(randf_range(-0.2, 0.2), randf() * TAU, randf_range(-0.2, 0.2))
	n.set_meta("s", s)
	n.scale = Vector3.ONE * 0.02
	var tw := n.create_tween()
	tw.tween_property(n, "scale", Vector3.ONE * s, 0.16).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	InfernalFx.tween_param(n, rim, "glow", 3.0, 1.2, 0.5)
	# the ground bursts round its foot
	ElementalFx._dust(root, p + Vector3(0, 0.1, 0), MIST, 0.6 * s + 0.3, 0.4, {"amount": [2, 3, 4, 5][tr], "life": 0.9,
		"explosive": 1.0, "shape": "ring", "r": 0.25 * s, "r_in": 0.1, "dir": Vector3.UP, "spread": 20.0, "vel": [0.2, 0.5],
		"radial": [1.0, 2.0], "damping": [2.0, 3.0], "scale": [0.7, 1.1], "grow": [0.5, 1.5]})
	return n

static func glints(root: Node3D, at: Vector3, n: int) -> void:
	InfernalFx.particles(root, at, {"amount": n, "life": 0.7, "explosive": 0.8, "shape": "sphere", "r": 0.25,
		"dir": Vector3.UP, "spread": 90.0, "vel": [0.2, 0.9], "gravity": -0.6, "scale": [0.4, 1.0], "size": 0.016,
		"colors": [[0.0, Color(PALE, 0)], [0.2, Color(1.2, 1.35, 1.5)], [0.5, Color(PALE, 0.4)], [0.7, Color(1.2, 1.35, 1.5)], [1.0, Color(DEEP, 0)]]})

## One crystal cluster breaking: its Voronoi pieces (fracture_rock.py) thrown out from where they sat, glinting, the
## break's faces frosted white; ice dust where it stood.
static func smash(root: Node3D, w, n: Node3D, tr: int, pieces := CRYSTAL_PIECES) -> void:
	var set := DemonKitFx.piece_set(pieces)
	var base := n.global_position
	var xf := n.global_transform
	var centre := Vector3.ZERO
	var src := n.find_children("*", "MeshInstance3D", true, false)
	if not src.is_empty():
		centre = ((src[0] as MeshInstance3D).mesh as Mesh).get_aabb().get_center()
	var inner := StandardMaterial3D.new()
	inner.albedo_color = Color(0.85, 0.93, 1.0)
	inner.roughness = 0.35
	inner.emission_enabled = true
	inner.emission = Color(0.5, 0.75, 1.0)
	inner.emission_energy_multiplier = 0.8
	var s: float = float(n.get_meta("s", 0.6))
	var keep: int = [4, 7, 11, 99][tr]
	for i in mini(set.size(), keep):
		var pc: Dictionary = set[i]
		var mi := MeshInstance3D.new()
		mi.mesh = pc["mesh"]
		var mats: Array = pc["mats"]
		for j in mats.size():
			var mt = mats[j]
			if mt is BaseMaterial3D and str((mt as BaseMaterial3D).resource_name).to_lower().contains("interior"):
				mi.set_surface_override_material(j, inner)
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(mi)
		var at: Vector3 = xf * (centre + (pc["at"] as Vector3))
		mi.global_transform = Transform3D(xf.basis, at)
		var out := (at - base) * Vector3(1, 0, 1)
		out = out.normalized() if out.length() > 0.01 else Vector3(randf_range(-1, 1), 0, randf_range(-1, 1)).normalized()
		var v := out * randf_range(1.6, 3.6) * (0.6 + s) + Vector3(0, randf_range(2.0, 4.2) * (0.5 + s * 0.6), 0)
		var spin := Vector3(randf_range(-8, 8), randf_range(-5, 5), randf_range(-8, 8))
		DemonKitFx._throw(mi, w, v, spin, randf_range(1.0, 1.5))
	n.queue_free()
	var top := base + Vector3(0, 0.5 * s, 0)
	glints(root, top, [4, 6, 9, 12][tr])
	InfernalFx.particles(root, top, {"amount": [6, 9, 14, 20][tr], "life": 0.7, "explosive": 1.0, "shape": "sphere",
		"r": 0.3 * s, "dir": Vector3.UP, "spread": 80.0, "vel": [1.5, 4.0], "gravity": -12.0, "scale": [0.4, 1.1],
		"size": 0.05, "colors": [[0.0, Color(1, 1, 1)], [0.5, PALE], [1.0, Color(DEEP, 0.0)]]})
	ElementalFx._dust(root, base + Vector3(0, 0.2, 0), MIST, 0.45 + 0.5 * s, 0.16, {"amount": [2, 2, 3, 4][tr], "life": 1.0,
		"explosive": 1.0, "shape": "sphere", "r": 0.3 * s, "dir": Vector3.UP, "spread": 60.0, "vel": [0.3, 0.9],
		"gravity": -0.5, "damping": [1.5, 2.5], "scale": [0.8, 1.2], "grow": [0.6, 1.7]})

# ---------------------------------------------------------------- frost on the foes
## A foe frosted over for `dur` s (refreshed by later strikes): rime crawling up from the feet (Enemy.set_frost, its
## rest overlay), wisps of cold vapour falling off it and pooling at its feet (an emitter riding it, shedding into the
## world). One that dies frozen shatters.
static func frost_body(game, e: Node3D, dur: float) -> void:
	var id := e.get_instance_id()
	if _bodies.has(id):
		_bodies[id]["t"] = maxf(float(_bodies[id]["t"]), dur)
		return
	var hgt := DemonKitFx.height_of(e)
	var tr := InfernalFx.tier(game)
	var card := ElementalFx._dust(e, e.global_position + Vector3(0, hgt * 0.55, 0), MIST, clampf(hgt * 0.28, 0.3, 0.9), 0.24,
		{"one_shot": false, "amount": [4, 6, 9, 12][tr], "life": 1.3, "explosive": 0.0, "shape": "box",
		"box": Vector3(0.22, hgt * 0.35, 0.22), "dir": Vector3.DOWN, "spread": 25.0, "vel": [0.1, 0.35], "gravity": -0.7,
		"damping": [0.6, 1.2], "scale": [0.6, 1.1], "grow": [0.5, 1.9]})
	_bodies[id] = {"e": e, "t": dur, "amt": 0.0, "card": card, "game": game}

static func update_bodies(game, delta: float) -> void:
	var f := Engine.get_process_frames()
	if f == _body_frame:
		return
	_body_frame = f
	for id in _bodies.keys():
		var b: Dictionary = _bodies[id]
		var e = b["e"]
		var card = b["card"]
		if e == null or not is_instance_valid(e):
			_bodies.erase(id)
			continue
		if bool(e.dead):
			_shatter_body(b, e)
			_bodies.erase(id)
			continue
		b["t"] = float(b["t"]) - delta
		var on := float(b["t"]) > 0.0
		b["amt"] = clampf(float(b["amt"]) + delta * (2.2 if on else -1.6), 0.0, 1.0)
		if e.has_method("set_frost"):
			e.set_frost(float(b["amt"]))
		if is_instance_valid(card):
			(card as GPUParticles3D).emitting = on
		if not on and float(b["amt"]) <= 0.0:
			_stop(card)
			_bodies.erase(id)

## A foe that died frozen: the rime bursts off him in glints and splinters with a crack of ice.
static func _shatter_body(b: Dictionary, e) -> void:
	var game = b["game"]
	_stop(b["card"])
	if e.has_method("set_frost"):
		e.set_frost(0.0)
	if game == null or not is_instance_valid(game) or game.world == null:
		return
	var root: Node3D = game.world.fx_root
	var at: Vector3 = (e as Node3D).global_position + Vector3(0, DemonKitFx.height_of(e) * 0.5, 0)
	InfernalFx.particles(root, at, {"amount": 16, "life": 0.7, "explosive": 1.0, "shape": "sphere", "r": 0.35,
		"dir": Vector3.UP, "spread": 80.0, "vel": [1.5, 3.6], "gravity": -12.0, "scale": [0.4, 1.1], "size": 0.05,
		"colors": [[0.0, Color(1, 1, 1)], [0.5, PALE], [1.0, Color(DEEP, 0.0)]]})
	glints(root, at, 8)
	Sfx.play_at("ice_shatter", at, -6.0, randf_range(1.0, 1.15))

## Stops a riding emitter and frees it once its last wisps are gone.
static func _stop(p) -> void:
	if is_instance_valid(p):
		(p as GPUParticles3D).emitting = false
		Fx._free_later(p as Node, 1.5)

# ---------------------------------------------------------------- shaders
## The hoarfrost over the ground (InfernalFx.disc_mesh: UV 0.5 at the centre): the Meshy-painted hoarfrost tiled over
## it (RGB its colour, A its coverage), a glaze between the ferns, spreading out with a bright edge (`front`), glossy and
## glinting; the thaw (`thaw` 0..1) eats it from the edges in, leaving wet dark ground that dries.
const GROUND_SHADER := """
shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, shadows_disabled;
uniform sampler2D hoar : source_color, repeat_enable, filter_linear_mipmap;
uniform sampler2D noise_tex : repeat_enable, filter_linear_mipmap;
uniform vec4 pale : source_color = vec4(0.82, 0.94, 1.0, 1.0);
uniform vec4 deep : source_color = vec4(0.25, 0.55, 0.95, 1.0);
uniform float front = 0.0;
uniform float thaw = 0.0;
uniform float seed = 0.0;
uniform float tile = 2.0;
void fragment() {
	vec2 d = UV - vec2(0.5);
	float r = length(d) * 2.0;
	float n = texture(noise_tex, UV * 2.3 + vec2(seed, 0.0)).r;
	float n2 = texture(noise_tex, UV * 7.0 + vec2(0.3, seed)).r;
	vec4 hf = texture(hoar, UV * tile + vec2(seed * 0.37, seed * 0.11));
	float edge = (n - 0.5) * 0.24;
	float inside = smoothstep(front + 0.02, front - 0.07, r + edge);
	float band = smoothstep(front - 0.12, front, r + edge) * inside * step(front, 0.995);
	float rim = smoothstep(1.0, 0.8, r + edge * 0.8);
	float keep = smoothstep((1.0 - thaw) * 1.2 - 0.02, (1.0 - thaw) * 1.2 - 0.2, r + (n - 0.5) * 0.5);
	float cover = clamp(0.3 + 1.1 * hf.a, 0.0, 1.0);
	float sparkle = smoothstep(0.86, 0.98, n2) * hf.a;
	vec3 frost = mix(deep.rgb * 0.45, hf.rgb, 0.35 + 0.65 * hf.a);
	vec3 wet = vec3(0.03, 0.035, 0.04);
	ALBEDO = mix(wet, frost, keep);
	ROUGHNESS = mix(0.1, mix(0.22, 0.6, hf.a), keep);
	SPECULAR = 0.9;
	EMISSION = (pale.rgb * (band * (0.35 + 0.6 * n2) + sparkle * 1.1 + hf.a * 0.14) + deep.rgb * 0.03) * keep;
	float wet_a = 0.32 * (1.0 - smoothstep(0.55, 1.0, thaw));
	ALPHA = clamp(mix(wet_a * step(0.001, thaw), cover, keep) * inside * rim, 0.0, 1.0);
}
"""

## A mist streak behind a flying arrow: a quad whose long side runs along `axis`, turned round it to face the camera;
## a soft core thinning to the tail, broken by drifting noise. UV.y 0 at the head (the node), 1 at the tail.
const STREAK_SHADER := """
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled, world_vertex_coords;
uniform vec3 axis = vec3(0.0, 1.0, 0.0);
uniform vec4 col : source_color = vec4(0.82, 0.94, 1.0, 1.0);
uniform float alpha = 0.6;
uniform float seed = 0.0;
uniform sampler2D noise_tex : repeat_enable, filter_linear_mipmap;
void vertex() {
	vec3 c = MODEL_MATRIX[3].xyz;
	vec3 local = VERTEX - c;
	vec3 ax = normalize(axis);
	vec3 to_cam = normalize(INV_VIEW_MATRIX[3].xyz - c);
	vec3 side = normalize(cross(ax, to_cam));
	VERTEX = c + side * local.x + ax * local.y;
}
void fragment() {
	float across = abs(UV.x - 0.5) * 2.0;
	float along = UV.y;
	float n = texture(noise_tex, vec2(UV.x * 0.6 + seed, along * 1.4 - TIME * 1.6)).r;
	float core = pow(1.0 - across, 2.2);
	float tail = smoothstep(1.0, 0.75, along) * smoothstep(0.0, 0.08, along);
	float a = core * tail * (0.55 + 0.9 * n) * smoothstep(1.0, 0.0, along * 0.9);
	ALBEDO = col.rgb;
	ALPHA = clamp(a * alpha, 0.0, 1.0);
}
"""

## A cold rim of light over ice (an overlay): bright at the silhouette, a faint glow through the faces.
const RIM_SHADER := """
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_back, shadows_disabled;
uniform vec4 col : source_color = vec4(0.82, 0.94, 1.0, 1.0);
uniform float glow = 1.0;
void fragment() {
	float f = 1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	float a = (pow(f, 2.6) * 0.9 + 0.05) * glow;
	ALBEDO = col.rgb;
	ALPHA = clamp(a, 0.0, 1.0);
}
"""

## Rime on a frozen body (Enemy's rest overlay; skinned, so VERTEX is the posed body): white crust and glittering
## crystals growing up from the feet to `amt` of its height, heaviest on the faces turned up, a cold rim, and a bright
## line where the frost is creeping on.
const BODY_SHADER := """
shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_back, shadows_disabled;
uniform sampler2D noise_tex : repeat_enable, filter_linear_mipmap;
uniform float amt = 0.0;
uniform float base_y = 0.0;
uniform float height = 1.8;
varying vec3 wp;
varying vec3 wn;
void vertex() {
	wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wn = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}
void fragment() {
	float hgt = clamp((wp.y - base_y) / height, 0.0, 1.0);
	float n = texture(noise_tex, vec2(wp.x + wp.z, wp.y) * 0.9).r;
	float n2 = texture(noise_tex, vec2(wp.x - wp.z, wp.y * 1.3) * 3.7).r;
	float line = amt * 1.18 - hgt + (n - 0.5) * 0.28;
	float on = smoothstep(0.0, 0.1, line);
	float up = clamp(wn.y * 0.6 + 0.5, 0.0, 1.0);
	float crust = clamp(up * 0.65 + smoothstep(0.42, 0.72, n2) * 0.7, 0.0, 1.0);
	float f = 1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	float creep = smoothstep(0.0, 0.05, line) * (1.0 - smoothstep(0.05, 0.13, line));
	ALBEDO = mix(vec3(0.55, 0.72, 0.9), vec3(0.93, 0.97, 1.0), n2);
	ROUGHNESS = 0.22;
	SPECULAR = 0.9;
	EMISSION = vec3(0.5, 0.75, 1.0) * (pow(f, 3.0) * 0.7 * on + creep * 0.9 + smoothstep(0.8, 0.95, n2) * on * 0.4);
	ALPHA = clamp(crust * on * 0.85 + pow(f, 2.0) * 0.3 * on + creep * 0.5, 0.0, 1.0) * step(0.001, amt);
}
"""
