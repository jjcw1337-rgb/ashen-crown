class_name ArcFx
extends RefCounted
## Arc's lightning, rebuilt (jj, 2026-11-04: "redo the lightning coming off of it to look better"), for the shared
## Arc (SharedFx), the Storm Wyvern's Storm Arc (StormArcFx) and the Archer's storm arrows. Draws only, on the caster's game and
## his puppet's alike, from the skills' "cast" and "impact" {ps: the path, d} events.
##  - The bolts are real lightning: branching channels grown and rendered in Blender (tools/blender/fx/lightning_bolts.py,
##    Cycles + glare, packed by tools/fx_bolt_atlas.py into assets/textures/fx/storm/bolts.png, 4x4), each leap a
##    camera-facing strip stretched between two points (BOLT_SHADER: the white-hot core, the coloured glow round it),
##    struck again with another of the sixteen every few frames (the flicker), a thin jagged core over it
##    (ElementalFx.bolt) for its depth, and its light flashing on what it passes.
##  - The leaps go one after another (LEAP_GAP), each target struck: a crackle of small arcs over its body (from its
##    skeleton's joints), sparks, a flash, and the Meshy Lichtenberg burn on the ground at its feet
##    (lightning_scorch, glowing in its cracks, fading).
##  - The cast: the Meshy plasma ball flaring in the hand (or the wyvern's jaws) with filaments spitting off it; the
##    wyvern's wings crackle along their bones as it rears.
## Sounds: arc_zap (the chain, synced to the cast's impact), arc_hit on each one struck.

const BOLTS := "res://assets/textures/fx/storm/bolts.png"
const PLASMA := "res://assets/textures/fx/storm/plasma.png"
const GRID := Vector2(4, 4)
const LEAP_GAP := 0.05
const LIGHT_CAP := 3
## palettes: core, glow
const STORM := [Color(0.95, 0.97, 1.0), Color(0.45, 0.55, 1.0)]

static var _shaders := {}
static var _tex := {}
static var _lights := 0

static func tex(path: String) -> Texture2D:
	if not _tex.has(path):
		_tex[path] = load(path) if ResourceLoader.exists(path) else null
	return _tex[path]

static func _shader(key: String) -> Shader:
	if not _shaders.has(key):
		var s := Shader.new()
		s.code = BOLT_SHADER if key == "bolt" else PLASMA_SHADER
		_shaders[key] = s
	return _shaders[key]

# ---------------------------------------------------------------- the pieces
## The charge: the plasma ball swelling where the lightning will leave him, filaments spitting off it.
static func charge(h: Hero, at: Vector3, pal: Array, size := 0.3) -> void:
	var root: Node3D = h.game.world.fx_root
	var tr := InfernalFx.tier(h.game)
	var mi := MeshInstance3D.new()
	mi.mesh = InfernalFx.quad()
	var m := ShaderMaterial.new()
	m.shader = _shader("plasma")
	m.set_shader_parameter("tex", tex(PLASMA))
	m.set_shader_parameter("glow", pal[1])
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mi)
	mi.global_position = at
	mi.scale = Vector3.ONE * size * 0.2
	var tw := mi.create_tween()
	tw.tween_property(mi, "scale", Vector3.ONE * size, 0.22).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_method(func(v: float): m.set_shader_parameter("spin", v), 0.0, 6.0, 0.4)
	tw.tween_method(func(v: float): m.set_shader_parameter("alpha", v), 1.0, 0.0, 0.18)
	tw.tween_callback(mi.queue_free)
	for i in [1, 2, 3, 4][tr]:
		var d := Vector3(randf_range(-1, 1), randf_range(-0.4, 1.0), randf_range(-1, 1)).normalized()
		ElementalFx.bolt(root, at, at + d * randf_range(0.3, 0.7) * (size / 0.3), 0.16, 0.025, tr, pal[0], pal[1])
	_flash(root, at, pal[1], 1.6, 0.25, 3.0)

## The chain along the path: one leap after another, each a bolt, each target struck; a fizzle ahead if it found
## nobody.
static func chain(h: Hero, root: Node3D, ps: PackedVector3Array, d: Vector3, pal: Array, width := 1.0) -> void:
	if ps.size() < 2:
		var from := ps[0] if ps.size() > 0 else h.global_position + Vector3(0, 1.2, 0)
		var to := from + d * 4.0
		to.y = h.game.world.height_at(to.x, to.z) + 0.05
		bolt(root, from, to, 0.3, width, pal, h.game)
		_scorch(root, to, 0.9)
		Sfx.play_at("arc_hit", to, -6.0, 1.2)
		return
	for i in ps.size() - 1:
		var a: Vector3 = ps[i]
		var b: Vector3 = ps[i + 1]
		var wk := width * (1.0 if i == 0 else 0.8)
		if i == 0:
			bolt(root, a, b, 0.36, wk, pal, h.game)
			_struck(h, root, b, pal)
		else:
			# (Fx.later skips it once the zone's fx_root is gone; the caster, a puppet that may leave, by weak reference)
			var hw: WeakRef = weakref(h)
			Fx.later(root, LEAP_GAP * i, func():
				var hh := hw.get_ref() as Hero
				if hh != null and is_instance_valid(hh):
					bolt(root, a, b, 0.32, wk, pal, hh.game)
					_struck(hh, root, b, pal))

## One bolt from a to b living `dur` s: a frame of the Blender lightning stretched between them, turning to the camera
## round its own line, struck again with another frame every 50 ms, a thin jagged core over it, its light flashing.
static func bolt(root: Node3D, a: Vector3, b: Vector3, dur: float, width: float, pal: Array, game = null) -> void:
	var tr := InfernalFx.tier(game)
	var L := a.distance_to(b)
	if L < 0.05:
		return
	var mi := MeshInstance3D.new()
	var q := QuadMesh.new()
	var wd := clampf(L * 0.32, 0.55, 3.0) * width
	q.size = Vector2(L, wd)
	mi.mesh = q
	var m := ShaderMaterial.new()
	m.shader = _shader("bolt")
	m.set_shader_parameter("bolts", tex(BOLTS))
	m.set_shader_parameter("a", a)
	m.set_shader_parameter("b", b)
	m.set_shader_parameter("core", pal[0])
	m.set_shader_parameter("glow", pal[1])
	m.set_shader_parameter("cell", float(randi() % 16))
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.extra_cull_margin = L
	root.add_child(mi)
	mi.global_position = (a + b) * 0.5
	var state := {"t": 0.0}
	var tw := mi.create_tween()
	tw.tween_method(func(u: float):
		if not is_instance_valid(mi):
			return
		var t := u * dur
		if t - float(state["t"]) > 0.05:
			state["t"] = t
			m.set_shader_parameter("cell", float(randi() % 16))
			m.set_shader_parameter("flip", 1.0 if randf() < 0.5 else -1.0)
		m.set_shader_parameter("fade", pow(1.0 - u, 1.3) * randf_range(0.75, 1.0)), 0.0, 1.0, dur)
	tw.tween_callback(mi.queue_free)
	# its white-hot core in depth, and its light
	ElementalFx.bolt(root, a, b, dur * 0.8, 0.035 * width, tr, pal[0], pal[1])
	_flash(root, (a + b) * 0.5, pal[1], 3.0, dur, maxf(L, 4.0))

## A target struck: a crackle of arcs over its body, sparks, a flash, the burn at its feet, the snap of it.
static func _struck(h: Hero, root: Node3D, at: Vector3, pal: Array) -> void:
	var tr := InfernalFx.tier(h.game)
	var e = null
	var bd := 1.2
	for x in h.game.enemies_near(at - Vector3(0, 1.0, 0), 1.2):
		var dd: float = (x.global_position + Vector3(0, 1.0, 0)).distance_to(at)
		if dd < bd:
			bd = dd
			e = x
	var pts: Array = []
	if e != null and is_instance_valid(e):
		for s in (e as Node).find_children("*", "Skeleton3D", true, false):
			var sk := s as Skeleton3D
			for i in range(0, sk.get_bone_count(), maxi(1, sk.get_bone_count() / 10)):
				pts.append(sk.global_transform * sk.get_bone_global_pose(i).origin)
			break
	if pts.size() < 3:
		for k in 6:
			pts.append(at + Vector3(randf_range(-0.35, 0.35), randf_range(-0.9, 0.5), randf_range(-0.35, 0.35)))
	for k in [2, 3, 5, 7][tr]:
		var p1: Vector3 = pts[randi() % pts.size()]
		var p2: Vector3 = pts[randi() % pts.size()]
		if p1.distance_to(p2) > 0.15:
			ElementalFx.bolt(root, p1, p2, randf_range(0.18, 0.4), 0.02, tr, pal[0], pal[1])
	DemonKitFx.sparks(root, at, Vector3.UP, [6, 10, 14, 20][tr], 90.0, Vector2(2.0, 6.0), 0.4)
	var g := Vector3(at.x, h.game.world.height_at(at.x, at.z), at.z)
	_scorch(root, g, 1.1)
	Sfx.play_at("arc_hit", at, -6.0, randf_range(0.95, 1.15))

static func _scorch(root: Node3D, g: Vector3, size: float) -> void:
	DemonKitFx.decal(root, g, "lightning_scorch", Vector2(size, size) * 2.0, randf() * TAU, 3.5, 2.5)

static func _flash(root: Node3D, at: Vector3, col: Color, energy: float, dur: float, rng: float) -> void:
	if _lights >= LIGHT_CAP:
		return
	_lights += 1
	var l := OmniLight3D.new()
	l.light_color = col
	l.light_energy = energy
	l.omni_range = rng
	l.shadow_enabled = false
	root.add_child(l)
	l.global_position = at
	var tw := l.create_tween()
	tw.tween_property(l, "light_energy", 0.0, dur)
	tw.tween_callback(func():
		_lights = maxi(0, _lights - 1)
		l.queue_free())

## A bolt frame on a strip from a to b (world space, world_vertex_coords), turned to the camera round its own line:
## UV.x along it, UV.y across; the frame's light is the Blender render's (white on black): its brightest is the core,
## its dimmer halo the glow colour. COLOR-free; `fade` carries the flicker.
const BOLT_SHADER := """
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled, world_vertex_coords;
uniform sampler2D bolts : source_color, filter_linear_mipmap, repeat_disable;
uniform vec3 a;
uniform vec3 b;
uniform vec4 core : source_color = vec4(0.95, 0.97, 1.0, 1.0);
uniform vec4 glow : source_color = vec4(0.45, 0.55, 1.0, 1.0);
uniform float cell = 0.0;
uniform float flip = 1.0;
uniform float fade = 1.0;
uniform float energy = 4.0;
void vertex() {
	vec3 c = (a + b) * 0.5;
	vec3 local = VERTEX - MODEL_MATRIX[3].xyz;
	vec3 ax = normalize(b - a);
	vec3 to_cam = normalize(INV_VIEW_MATRIX[3].xyz - c);
	vec3 side = normalize(cross(ax, to_cam));
	VERTEX = c + ax * local.x + side * local.y * flip;
}
void fragment() {
	vec2 g = vec2(4.0, 4.0);
	vec2 o = vec2(mod(cell, g.x), floor(cell / g.x));
	vec2 uv = (o + clamp(UV, vec2(0.002), vec2(0.998))) / g;
	float l = texture(bolts, uv).r;
	// the halo round the channel: the same frame read from a blurred mip, so it follows the bolt's own shape
	float halo = textureLod(bolts, uv, 3.5).r;
	float hot = smoothstep(0.55, 0.95, l);
	vec3 light = mix(glow.rgb * l, core.rgb * (0.6 + l), hot) * energy + glow.rgb * halo * 2.2;
	ALBEDO = light;
	ALPHA = clamp((l + halo * 0.8) * fade, 0.0, 1.0);
}
"""

## The plasma ball (the Meshy sprite: RGB its hue, A its light), facing the camera, turning, flickering.
const PLASMA_SHADER := """
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled;
uniform sampler2D tex : source_color, filter_linear_mipmap, repeat_disable;
uniform vec4 glow : source_color = vec4(0.45, 0.55, 1.0, 1.0);
uniform float spin = 0.0;
uniform float alpha = 1.0;
void vertex() {
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
	MODELVIEW_MATRIX = MODELVIEW_MATRIX * mat4(vec4(length(MODEL_MATRIX[0].xyz), 0.0, 0.0, 0.0), vec4(0.0, length(MODEL_MATRIX[1].xyz), 0.0, 0.0), vec4(0.0, 0.0, length(MODEL_MATRIX[2].xyz), 0.0), vec4(0.0, 0.0, 0.0, 1.0));
}
void fragment() {
	vec2 d = UV - vec2(0.5);
	float cs = cos(spin);
	float sn = sin(spin);
	vec2 q = vec2(cs * d.x - sn * d.y, sn * d.x + cs * d.y) + vec2(0.5);
	vec4 t = texture(tex, q);
	float fl = 0.8 + 0.2 * sin(TIME * 41.0) * sin(TIME * 17.0);
	ALBEDO = mix(glow.rgb, t.rgb, 0.6) * (1.0 + 2.5 * t.a) * fl;
	ALPHA = clamp(t.a * alpha, 0.0, 1.0);
}
"""
