class_name FlameFx
extends RefCounted
## Simulated flames for skills: flipbooks of Blender fire and smoke played on particles (flip_particles), embers and
## sparks (streaks), heat haze, a light that breathes with the fire, the shaders they use; and a body set alight
## (`burn`: the flames climbing a foe's skeleton, embers, smoke off the top, a light, sinking when it runs out), which
## every burn in the game shows. The Archer's arrows are built from these (ArrowFx). FireFx is the other fire library
## (torches, campfires, braziers); the two may become one. Draws only.

## A burning body: its flames, embers, smoke and light.
const BURN := {"amount": 30, "embers": 16, "smoke": 9, "light": 2.6}

const TEX := {"flame": "res://assets/textures/fx/real_flame.png", "burst_fire": "res://assets/textures/fx/real_burst_fire.png",
	"burst_smoke": "res://assets/textures/fx/real_burst_smoke.png", "smoke": "res://assets/textures/fx/real_smoke.png",
	"scorch": "res://assets/textures/fx/real_scorch.png", "scorch_n": "res://assets/textures/fx/real_scorch_n.png",
	"scorch_e": "res://assets/textures/fx/real_scorch_e.png"}
## where the source sits in each sim's frame (of the card's height from its middle), so a card's origin is the fire's
const PIVOT := {"flame": 0.40, "burst_fire": 0.32, "burst_smoke": 0.32, "smoke": 0.38}
const BURN_LIGHT_CAP := 4

static var _shaders := {}
static var _tex := {}
static var _noise: Texture2D
static var _burn_lights := 0

## Fewer particles, no heat haze, no light shadows: the browser build or the Low preset.
static func cheap(game) -> bool:
	return OS.has_feature("web") or (game != null and int(game.get("quality")) <= 0)

## Forward+ / Mobile (a RenderingDevice): the screen and depth textures exist (haze, soft particles, decals).
static func rd_ok() -> bool:
	return RenderingServer.get_rendering_device() != null and not OS.has_feature("web")

static func shimmer_ok() -> bool:
	return rd_ok()

static func tex(key: String) -> Texture2D:
	if not _tex.has(key):
		_tex[key] = load(TEX[key]) if ResourceLoader.exists(TEX[key]) else null
	return _tex[key]

## A seamless normal-mapped noise for the heat haze.
static func noise_tex() -> Texture2D:
	if _noise == null:
		var nt := NoiseTexture2D.new()
		var n := FastNoiseLite.new()
		n.frequency = 0.012
		n.fractal_octaves = 3
		nt.noise = n
		nt.width = 128
		nt.height = 128
		nt.seamless = true
		nt.as_normal_map = true
		nt.bump_strength = 4.0
		_noise = nt
	return _noise

static func shader(key: String) -> Shader:
	if _shaders.has(key):
		return _shaders[key]
	var s := Shader.new()
	var soft_u := "uniform sampler2D depth_tex : hint_depth_texture, filter_nearest;" if rd_ok() else ""
	var soft_f := SOFT_FN if rd_ok() else "float soft_k(vec2 suv, vec3 vtx, mat4 ip, float len){ return 1.0; }"
	match key:
		"fire": s.code = FIRE_SHADER % [soft_u, BLACKBODY, soft_f, Mats.NOISE_LIB]
		"smoke": s.code = SMOKE_SHADER % [soft_u, soft_f, Mats.NOISE_LIB]
		"streak": s.code = STREAK_SHADER % BLACKBODY
		"haze": s.code = HAZE_SHADER % Mats.NOISE_LIB
		"heat": s.code = HEAT_SHADER % [Mats.NOISE_LIB, BLACKBODY]
		"scorch": s.code = SCORCH_SHADER
		"ribbon_fire": s.code = RIBBON_FIRE_SHADER % [Mats.NOISE_LIB, BLACKBODY]
		"ribbon_smoke": s.code = RIBBON_SMOKE_SHADER % Mats.NOISE_LIB
	_shaders[key] = s
	return s

## The colour of a blackbody at k Kelvin (linear, red channel 1), as the shaders' blackbody().
static func blackbody(k: float) -> Color:
	var t := k / 100.0
	var g := clampf(0.39008158 * log(t) - 0.63184144, 0.0, 1.0)
	var b := 0.0 if k <= 1900.0 else clampf(0.54320679 * log(t - 10.0) - 1.19625409, 0.0, 1.0)
	return Color(1.0, pow(g, 2.2), pow(b, 2.2))

# ---------------------------------------------------------------- the building blocks
## Flipbook particles of the sim ("flame", "burst_fire": additive fire; "smoke", "burst_smoke": lit smoke).
## axis: 0 = the card stands up (world up, leaning with `lean`), 1 = it lies along the emitter's +z (the arrow's tail),
## 2 = along the particle's own flight (with particle_flag_align_y).
static func flip_particles(key: String, amount: int, life: float, size: Vector2, axis := 0, energy := 6.0, t := Vector2(1050, 2500)) -> GPUParticles3D:
	var missing := tex(key) == null and key != "flame"
	if missing:
		# a sheet not built yet (tools/fx_flipbook.py): the flame stands in for fire; smoke is left out
		key = "flame"
	var p := GPUParticles3D.new()
	p.amount = maxi(1, amount)
	p.lifetime = life
	p.local_coords = false
	p.fixed_fps = 0
	p.interpolate = false
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.visibility_aabb = AABB(Vector3(-6, -3, -6), Vector3(12, 9, 12))
	var pm := ParticleProcessMaterial.new()
	pm.scale_min = size.x
	pm.scale_max = size.y
	pm.anim_offset_min = 0.0
	pm.anim_offset_max = 1.0
	pm.anim_speed_min = 1.0
	pm.anim_speed_max = 1.0
	pm.gravity = Vector3.ZERO
	p.process_material = pm
	var q := QuadMesh.new()
	q.size = Vector2.ONE
	p.draw_pass_1 = q
	var fire := key == "flame" or key == "burst_fire"
	var m := ShaderMaterial.new()
	m.shader = shader("fire" if fire else "smoke")
	m.set_shader_parameter("atlas", tex(key))
	m.set_shader_parameter("pivot", float(PIVOT.get(key, 0.0)))
	m.set_shader_parameter("loop_anim", 1.0 if key == "flame" else 0.0)
	if fire:
		m.set_shader_parameter("energy", energy)
		m.set_shader_parameter("t_lo", t.x)
		m.set_shader_parameter("t_hi", t.y)
		m.set_shader_parameter("axis_mode", float(axis))
	if missing:
		m.set_shader_parameter("alpha_mul", 0.0)
	p.material_override = m
	return p

## Blackbody points: embers (slow, drifting on turbulence) or sparks (fast, stretched along their flight). They cool
## from t.x to t.y Kelvin over their life.
static func streaks(amount: int, life: Vector2, size: float, stretch: float, t: Vector2, energy := 1.0) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = maxi(1, amount)
	p.lifetime = life.y
	p.local_coords = false
	p.fixed_fps = 0
	p.interpolate = false
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.visibility_aabb = AABB(Vector3(-8, -3, -8), Vector3(16, 10, 16))
	p.trail_enabled = false
	var pm := ParticleProcessMaterial.new()
	pm.lifetime_randomness = 1.0 - life.x / life.y
	pm.scale_min = size * 0.6
	pm.scale_max = size * 1.4
	pm.particle_flag_align_y = true
	pm.color_ramp = ramp([Color(1, 1, 1, 1), Color(1, 1, 1, 1), Color(1, 1, 1, 0)])
	p.process_material = pm
	var q := QuadMesh.new()
	q.size = Vector2.ONE
	p.draw_pass_1 = q
	var m := ShaderMaterial.new()
	m.shader = shader("streak")
	m.set_shader_parameter("stretch", stretch)
	m.set_shader_parameter("t_hot", t.x)
	m.set_shader_parameter("t_cold", t.y)
	m.set_shader_parameter("energy", energy)
	p.material_override = m
	return p

## Heat haze cards (Forward+ only): what is behind them bends.
static func haze(amount: int, life: float, size: float, strength: float) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = maxi(1, amount)
	p.lifetime = life
	p.local_coords = false
	p.fixed_fps = 0
	p.interpolate = false
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var pm := ParticleProcessMaterial.new()
	pm.scale_min = size * 0.7
	pm.scale_max = size * 1.3
	pm.gravity = Vector3(0, 0.6, 0)
	pm.color_ramp = ramp([Color(1, 1, 1, 0), Color(1, 1, 1, 1), Color(1, 1, 1, 0)])
	pm.scale_curve = curve_tex([[0.0, 0.6], [1.0, 1.4]])
	p.process_material = pm
	var q := QuadMesh.new()
	q.size = Vector2.ONE
	p.draw_pass_1 = q
	var m := ShaderMaterial.new()
	m.shader = shader("haze")
	m.set_shader_parameter("noise_tex", noise_tex())
	m.set_shader_parameter("strength", strength)
	m.render_priority = -20       # drawn before the other see-through things: it bends only the solid scene
	p.material_override = m
	return p

## A flickering fire light (Kelvin), its flicker driven by `fly` / the burn's timer.
static func fire_light(t: float, energy: float, rng: float, shadow: bool) -> OmniLight3D:
	var lt := OmniLight3D.new()
	lt.light_color = blackbody(t)
	lt.light_energy = energy
	lt.omni_range = rng
	lt.omni_attenuation = 1.0
	# its shadow: a cheap map a frame after it is lit, within the effects' shadow budget (Fx.effect_shadow)
	lt.shadow_enabled = false
	if shadow:
		Fx.effect_shadow(lt)
	lt.shadow_bias = 0.08
	lt.shadow_normal_bias = 1.5
	lt.light_size = 0.15
	lt.set_meta("base", energy)
	return lt

static func flicker(t: float, seed_v: float) -> float:
	return 0.82 + 0.1 * sin(t * 23.0 + seed_v) * sin(t * 7.3 + seed_v * 2.1) + 0.06 * sin(t * 41.0 + seed_v * 3.7) + 0.05 * sin(t * 13.1 + seed_v)

## A foe set alight: the sim's flames climbing his body, embers going up, smoke off the top, a little light that
## breathes with the fire (one per foe, at most BURN_LIGHT_CAP lit); when the burn runs out the flames sink, the
## smoke goes on a moment longer.
static func burn(game, e: Node3D, kind: String, dur: float) -> void:
	if kind != "fire" or not is_instance_valid(e):
		return
	var b: Dictionary = BURN
	var old := e.get_node_or_null("fire_burn") as Node3D
	if old != null:
		old.set_meta("until", maxf(float(old.get_meta("until", 0.0)), GameClock.now() + dur))
		return
	var hgt: float = float(e.get("height"))
	var rad: float = float(e.get("radius"))
	var root := Node3D.new()
	root.name = "fire_burn"
	# (Enemy.height is about half his standing height: the body runs to ~1.9 x it)
	root.position = Vector3(0, hgt * 0.8, 0)
	e.add_child(root)
	var lite := cheap(game)
	var div := 2 if lite else 1
	var fl := flip_particles("flame", int(b["amount"]) / div, 0.75, Vector2(0.8, 1.4), 0, 4.2, Vector2(950, 2250))
	(fl.material_override as ShaderMaterial).set_shader_parameter("soft", 0.02)   # flames hug the body
	var pm := fl.process_material as ParticleProcessMaterial
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(rad * 0.5, hgt * 0.6, rad * 0.5)
	# the body burns where the body is: flames rise from points along his bones (the skeleton's joints and the
	# middles of its bones, re-read as he moves), so they climb his legs, back and arms, not one patch
	var skels := e.find_children("*", "Skeleton3D", true, false)
	if not skels.is_empty():
		root.set_meta("skel", skels[0])
		_burn_points(fl, skels[0] as Skeleton3D)
	pm.anim_speed_min = 0.3
	pm.anim_speed_max = 0.5
	pm.gravity = Vector3(0, 0.6, 0)
	pm.color_ramp = ramp([Color(1, 1, 1, 0), Color(1, 1, 1, 1), Color(1, 1, 1, 0.7), Color(1, 1, 1, 0)])
	pm.scale_curve = curve_tex([[0.0, 0.6], [0.3, 1.0], [1.0, 0.7]])
	root.add_child(fl)
	var em := streaks(int(b["embers"]) / div, Vector2(0.7, 1.6), 0.017, 1.5, Vector2(1900, 850))
	var epm := em.process_material as ParticleProcessMaterial
	epm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	epm.emission_box_extents = Vector3(rad * 0.5, hgt * 0.6, rad * 0.5)
	epm.direction = Vector3.UP
	epm.spread = 30.0
	epm.initial_velocity_min = 0.6
	epm.initial_velocity_max = 1.8
	epm.gravity = Vector3(0, 0.8, 0)
	epm.turbulence_enabled = true
	epm.turbulence_noise_strength = 2.5
	epm.turbulence_influence_min = 0.15
	epm.turbulence_influence_max = 0.4
	root.add_child(em)
	var sm := flip_particles("smoke", int(b["smoke"]) / div, 2.0, Vector2(0.5, 1.1))
	var spm := sm.process_material as ParticleProcessMaterial
	spm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	spm.emission_box_extents = Vector3(rad * 0.4, 0.1, rad * 0.4)
	spm.direction = Vector3.UP
	spm.spread = 15.0
	spm.initial_velocity_min = 0.4
	spm.initial_velocity_max = 0.9
	spm.gravity = Vector3(0, 0.3, 0)
	spm.angle_max = 360.0
	spm.angular_velocity_min = -20.0
	spm.angular_velocity_max = 20.0
	spm.color_ramp = ramp([Color(1, 1, 1, 0), Color(1, 1, 1, 0.45), Color(1, 1, 1, 0.25), Color(1, 1, 1, 0)])
	spm.scale_curve = curve_tex([[0.0, 0.4], [1.0, 1.4]])
	(sm.material_override as ShaderMaterial).set_shader_parameter("tint", Color(0.16, 0.15, 0.14))
	(sm.material_override as ShaderMaterial).set_shader_parameter("glow", 0.8)
	(sm.material_override as ShaderMaterial).set_shader_parameter("soot", 0.6)
	sm.position = Vector3(0, hgt * 0.8, 0)
	root.add_child(sm)
	var hz: GPUParticles3D = null
	if shimmer_ok() and not lite:
		hz = haze(3, 0.6, 0.9, 0.016)
		(hz.process_material as ParticleProcessMaterial).emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
		(hz.process_material as ParticleProcessMaterial).emission_box_extents = Vector3(rad * 0.4, hgt * 0.5, rad * 0.4)
		hz.position = Vector3(0, hgt * 0.6, 0)
		root.add_child(hz)
	var lt: OmniLight3D = null
	if _burn_lights < BURN_LIGHT_CAP:
		lt = fire_light(2500.0, float(b["light"]), 4.0, false)
		lt.position = Vector3(0, hgt * 0.2, 0)
		root.add_child(lt)
		_burn_lights += 1
		lt.tree_exited.connect(func(): _burn_lights = maxi(0, _burn_lights - 1))
	root.set_meta("until", GameClock.now() + dur)
	# counts itself down (the enemy's burn_t is gameplay; this only has to end near the same time) and breathes the light
	var tm := Timer.new()
	tm.wait_time = 0.05
	tm.autostart = true
	root.add_child(tm)
	var seed_v := float(e.get_instance_id() % 89)
	tm.timeout.connect(func():
		if not is_instance_valid(root):
			return
		var tnow := GameClock.now()
		var left: float = float(root.get_meta("until")) - tnow
		if lt != null and is_instance_valid(lt):
			lt.light_energy = float(b["light"]) * flicker(tnow, seed_v) * clampf(left / 0.6, 0.0, 1.0)
		if root.has_meta("skel") and is_instance_valid(root.get_meta("skel")) and Engine.get_process_frames() % 3 == 0:
			_burn_points(fl, root.get_meta("skel") as Skeleton3D)
		if left <= 0.0:
			fl.emitting = false
			em.emitting = false
			if hz != null:
				hz.emitting = false
			tm.stop()
			# the smoke goes on a moment, then all of it is gone
			var tw := root.create_tween()
			tw.tween_interval(1.0)
			tw.tween_callback(func(): sm.emitting = false)
			Fx._free_later(root, 3.2)
		else:
			fl.amount_ratio = clampf(left / 0.8, 0.3, 1.0))

## The emission points of a burning body: every bone's joint and the middle of every bone, in the emitter's frame.
static func _burn_points(fl: GPUParticles3D, sk: Skeleton3D) -> void:
	if not fl.is_inside_tree() or not sk.is_inside_tree():
		return
	var inv := fl.global_transform.affine_inverse()
	var sg := sk.global_transform
	var pts := PackedVector3Array()
	for i in sk.get_bone_count():
		var pi: Vector3 = sg * sk.get_bone_global_pose(i).origin
		pts.append(inv * pi)
		var par := sk.get_bone_parent(i)
		if par >= 0:
			var pp: Vector3 = sg * sk.get_bone_global_pose(par).origin
			pts.append(inv * pi.lerp(pp, 0.5))
	if pts.size() < 2:
		return
	var img := Image.create(pts.size(), 1, false, Image.FORMAT_RGBF)
	for i in pts.size():
		img.set_pixel(i, 0, Color(pts[i].x, pts[i].y, pts[i].z))
	var pm := fl.process_material as ParticleProcessMaterial
	var t := pm.emission_point_texture as ImageTexture
	if t == null or t.get_width() != pts.size():
		pm.emission_point_texture = ImageTexture.create_from_image(img)
	else:
		t.update(img)
	pm.emission_point_count = pts.size()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_POINTS

static func ramp(cols: Array) -> GradientTexture1D:
	var g := Gradient.new()
	g.set_color(0, cols[0])
	g.set_color(1, cols[cols.size() - 1])
	for i in range(1, cols.size() - 1):
		g.add_point(float(i) / (cols.size() - 1), cols[i])
	var gt := GradientTexture1D.new()
	gt.gradient = g
	return gt

static func curve_tex(pts: Array) -> CurveTexture:
	var c := Curve.new()
	for p in pts:
		c.add_point(Vector2(float(p[0]), float(p[1])))
	var ct := CurveTexture.new()
	ct.curve = c
	return ct

# ---------------------------------------------------------------- shaders
## Kelvin -> linear colour (red 1): the curve fitted to Planck's law for 1000-6600 K.
const BLACKBODY := """
vec3 blackbody(float k){
	float t = k / 100.0;
	float g = clamp(0.39008158 * log(t) - 0.63184144, 0.0, 1.0);
	float b = k <= 1900.0 ? 0.0 : clamp(0.54320679 * log(t - 10.0) - 1.19625409, 0.0, 1.0);
	return pow(vec3(1.0, g, b), vec3(2.2));
}
"""

## Soft intersections: fade where the card meets the scene (the depth buffer, Forward+ / Mobile).
const SOFT_FN := """
float soft_k(vec2 suv, vec3 vtx, mat4 ip, float len){
	float d = texture(depth_tex, suv).r;
	vec4 v = ip * vec4(suv * 2.0 - 1.0, d, 1.0);
	float scene = -v.z / v.w;
	return clamp((scene + vtx.z) / max(len, 0.001), 0.0, 1.0);
}
"""

## The sim's fire, one flipbook frame blended into the next. R = flame, G = flame x temperature: the light is the
## flame's (linearised), its colour a blackbody at the sim's own temperature (t_lo..t_hi Kelvin), brighter with the
## fourth-ish power of it so the thick hot core goes white-yellow through the tonemapper and the thin edges deep red.
## The card stands up the world (axis_mode 0, leaning by `lean`) or lies along the emitter's +z (1: the arrow's
## flames blown back); seen down its axis it turns to the screen so it never goes edge-on. Additive, soft where it
## meets the ground or a body.
const FIRE_SHADER := """
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;
uniform sampler2D atlas : filter_linear_mipmap, repeat_disable;
uniform float grid = 8.0;
uniform float loop_anim = 1.0;
uniform float frame = 0.0;
uniform float pivot = 0.43;
uniform float energy = 6.0;
uniform float t_lo = 1050.0;
uniform float t_hi = 2500.0;
uniform float axis_mode = 0.0;
uniform vec3 lean = vec3(0.0);
uniform float flip = 0.0;
uniform float spin = 0.0;
uniform float alpha_mul = 1.0;
uniform float soft = 0.25;
// the burst's flame (a filled ball in the sim's first frames) given the inside of a fireball: turbulent tongues
// and holes carved by drifting noise that eat in as it ages (it tears open), hot filaments and cooler lobes
uniform float detail = 0.0;
// 1 on particles (INSTANCE_CUSTOM carries their animation), 0 on a lone card (MeshInstance3D: no custom data)
uniform float particles = 1.0;
uniform float erode_from = 4.0;
uniform float erode_span = 14.0;
%s
%s
%s
%s
varying float v_frame;
varying vec4 v_col;
varying float v_flip;
void vertex(){
	float s = length(MODEL_MATRIX[0].xyz);
	vec3 c = MODEL_MATRIX[3].xyz;
	// (a particle aligned to a velocity that has died away has no axis: it stands up rather than turning to NaN)
	vec3 ax = axis_mode > 1.5 ? MODEL_MATRIX[1].xyz : MODEL_MATRIX[2].xyz;
	vec3 up = axis_mode > 0.5 ? (length(ax) > 1e-5 ? normalize(ax) : vec3(0.0, 1.0, 0.0)) : normalize(vec3(0.0, 1.0, 0.0) + lean);
	vec3 to_cam = normalize(INV_VIEW_MATRIX[3].xyz - c);
	vec3 side = cross(up, to_cam);
	float sl = length(side);
	float k = smoothstep(0.1, 0.4, sl);
	vec3 side_n = normalize(mix(INV_VIEW_MATRIX[0].xyz, sl > 0.0001 ? side / sl : INV_VIEW_MATRIX[0].xyz, k));
	vec3 up_n = normalize(mix(INV_VIEW_MATRIX[1].xyz, up, k));
	vec3 n = normalize(cross(side_n, up_n));
	vec3 sd = side_n * cos(spin) + up_n * sin(spin);
	vec3 ud = -side_n * sin(spin) + up_n * cos(spin);
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(vec4(sd * s, 0.0), vec4(ud * s, 0.0), vec4(n * s, 0.0), vec4(c, 1.0));
	VERTEX.y += pivot;
	v_frame = (particles > 0.5 ? INSTANCE_CUSTOM.z * grid * grid : 0.0) + frame;
	v_col = COLOR;
	float h = fract(sin(float(INSTANCE_ID) * 12.9898 + c.x * 3.1) * 43758.5453);
	v_flip = flip > 0.5 ? 1.0 : step(0.5, h);
}
vec2 cell(float i, vec2 uv){
	return (vec2(mod(i, grid), floor(i / grid)) + uv) / grid;
}
void fragment(){
	vec2 uv = vec2(mix(UV.x, 1.0 - UV.x, v_flip), UV.y);
	float total = grid * grid;
	float f0 = floor(v_frame);
	float fr = v_frame - f0;
	float a0 = loop_anim > 0.5 ? mod(f0, total) : clamp(f0, 0.0, total - 1.0);
	float a1 = loop_anim > 0.5 ? mod(f0 + 1.0, total) : clamp(f0 + 1.0, 0.0, total - 1.0);
	vec2 v = mix(texture(atlas, cell(a0, uv)).rg, texture(atlas, cell(a1, uv)).rg, fr);
	// thin wisps fade out instead of glowing as a sheet; the hot mean temperature (G/R) drops toward the edges
	float r = smoothstep(0.03, 1.0, v.r);
	float tm = clamp(v.g / max(v.r, 0.004), 0.0, 1.0);
	if (detail > 0.0) {
		// noise rolling outward from the middle (the burst's own billows) at two scales
		vec2 c = uv - vec2(0.5, 0.5 - pivot * 0.5);
		vec2 q = c * (1.0 - 0.012 * v_frame);
		float n1 = fbm(q * 6.0 + vec2(flip * 7.0, -v_frame * 0.06));
		float n2 = fbm(q * 15.0 + vec2(3.1 + flip * 5.0, -v_frame * 0.11));
		float er = clamp((v_frame - erode_from) / erode_span, 0.0, 1.0);
		float cut = 0.18 + 0.5 * er;
		float body = r * (0.55 + 0.9 * n1) + (n2 - 0.5) * 0.45;
		float carved = r * smoothstep(cut - 0.12, cut + 0.18, body);
		r = mix(r, carved, detail);
		// filaments burn hotter than the lobes round them
		tm = clamp(tm * mix(1.0, 0.55 + 0.9 * n2 + 0.25 * (n1 - 0.5), detail), 0.0, 1.0);
	}
	float lin = pow(r, 2.4);
	float kel = mix(t_lo, t_hi, clamp(tm * 1.05, 0.0, 1.0) * smoothstep(0.05, 0.95, r));
	float lum = lin * energy * pow(kel / 1500.0, 2.5);
	float a = v_col.a * alpha_mul * soft_k(SCREEN_UV, VERTEX, INV_PROJECTION_MATRIX, soft);
	ALBEDO = blackbody(kel) * lum * v_col.rgb;
	ALPHA = clamp(a, 0.0, 1.0);
}
"""

## The sim's smoke relit in the game: the sheet holds how the smoke looked lit from the right (R), above (G) and the
## left (B), and its opacity (A). light() turns each real light's direction (in the card's frame) into a mix of
## them, so the sun, the sky and the fire's own OmniLights light it, with their shadows; light from behind scatters
## through it. Alpha blended, soft where it meets things.
const SMOKE_SHADER := """
shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, specular_disabled;
uniform sampler2D atlas : filter_linear_mipmap, repeat_disable;
uniform float grid = 8.0;
uniform float loop_anim = 0.0;
uniform float frame = 0.0;
uniform float pivot = 0.39;
uniform vec4 tint : source_color = vec4(0.14, 0.13, 0.12, 1.0);
uniform float density = 1.0;
uniform float alpha_mul = 1.0;
uniform float lm_gain = 3.0;
uniform float wrap = 0.45;
uniform float flip = 0.0;
uniform float soft = 0.5;
uniform float soot = 0.45;
// the fire under young smoke lights it from inside and below (blackbody), fading as the puff ages
uniform vec4 glow_col : source_color = vec4(1.0, 0.36, 0.06, 1.0);
uniform float glow = 0.0;
// 1 on particles (INSTANCE_CUSTOM: spin, age, animation), 0 on a lone card (MeshInstance3D: no custom data)
uniform float particles = 1.0;
%s
%s
%s
varying float v_frame;
varying vec4 v_col;
varying float v_spin;
varying float v_age;
varying vec3 v_lm;
varying float v_flip;
void vertex(){
	float s = length(MODEL_MATRIX[0].xyz);
	vec3 c = MODEL_MATRIX[3].xyz;
	vec4 cu = particles > 0.5 ? INSTANCE_CUSTOM : vec4(0.0);
	float sp = cu.x;
	vec3 r = INV_VIEW_MATRIX[0].xyz;
	vec3 u = INV_VIEW_MATRIX[1].xyz;
	vec3 r2 = r * cos(sp) + u * sin(sp);
	vec3 u2 = -r * sin(sp) + u * cos(sp);
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(vec4(r2 * s, 0.0), vec4(u2 * s, 0.0), vec4(INV_VIEW_MATRIX[2].xyz * s, 0.0), vec4(c, 1.0));
	VERTEX.y += pivot;
	v_frame = cu.z * grid * grid + frame;
	v_col = COLOR;
	v_spin = sp;
	v_age = clamp(max(cu.y, frame / 24.0), 0.0, 1.0);
	float h = fract(sin(float(INSTANCE_ID) * 78.233 + c.z * 1.7) * 43758.5453);
	v_flip = flip > 0.5 ? 1.0 : step(0.5, h);
}
vec2 cell(float i, vec2 uv){
	return (vec2(mod(i, grid), floor(i / grid)) + uv) / grid;
}
void fragment(){
	vec2 uv = vec2(mix(UV.x, 1.0 - UV.x, v_flip), UV.y);
	float total = grid * grid;
	float f0 = floor(v_frame);
	float fr = v_frame - f0;
	float a0 = loop_anim > 0.5 ? mod(f0, total) : clamp(f0, 0.0, total - 1.0);
	float a1 = loop_anim > 0.5 ? mod(f0 + 1.0, total) : clamp(f0 + 1.0, 0.0, total - 1.0);
	vec4 lm = mix(texture(atlas, cell(a0, uv)), texture(atlas, cell(a1, uv)), fr);
	vec3 l = pow(lm.rgb, vec3(2.2)) * lm_gain;
	// the sheet's left and right swap with the mirror
	v_lm = v_flip > 0.5 ? l.bgr : l;
	// soot gathers at the top of a puff, the underside is the paler, fire-lit smoke
	ALBEDO = tint.rgb * v_col.rgb * mix(1.0 - soot, 1.0 + soot * 0.4, smoothstep(0.15, 0.85, UV.y));
	// the sim's domain walls never show: the sheet fades out toward a circle inside the card
	// (the circle's edge itself is wobbled by noise, so a big puff's outline is never a clean disc or a card's side)
	float br = fbm(uv * 5.0 + vec2(v_frame * 0.05, v_spin * 3.0));
	float bw = fbm(uv * 2.5 + vec2(v_spin * 1.7, v_frame * 0.03));
	float rm = 1.0 - smoothstep(0.2, 0.47, length(UV - vec2(0.5)) + (bw - 0.5) * 0.16);
	// the thin edges break up into wisps (noise drifting with the sequence): erosion eats the thin smoke first
	// (fbm, low frequency and a soft threshold: thresholded high-frequency value noise shows its square cells)
	rm *= smoothstep(0.0, 0.6, lm.a * 1.6 - (br - 0.5) * 0.9 * (1.0 - lm.a) - 0.08);
	// and a card the camera is nearly inside fades rather than slicing the view
	rm *= smoothstep(0.6, 2.0, -VERTEX.z);
	float under = (1.0 - clamp(l.g, 0.0, 1.0)) * (0.4 + 0.6 * UV.y);
	EMISSION = glow_col.rgb * glow * pow(1.0 - v_age, 3.0) * under * lm.a * rm;
	ALPHA = clamp(lm.a * rm * density * v_col.a * alpha_mul * soft_k(SCREEN_UV, VERTEX, INV_PROJECTION_MATRIX, soft), 0.0, 1.0);
	NORMAL = vec3(0.0, 0.0, 1.0);
}
void light(){
	float cs = cos(v_spin);
	float sn = sin(v_spin);
	vec2 l2 = vec2(LIGHT.x * cs + LIGHT.y * sn, -LIGHT.x * sn + LIGHT.y * cs);
	float lit = v_lm.r * max(l2.x, 0.0) + v_lm.b * max(-l2.x, 0.0) + v_lm.g * max(l2.y, 0.0)
		+ (0.12 + 0.3 * (1.0 - clamp(v_lm.g, 0.0, 1.0))) * max(-l2.y, 0.0);
	float avg = (v_lm.r + v_lm.g + v_lm.b) / 3.0;
	lit += avg * (max(LIGHT.z, 0.0) * 0.6 + max(-LIGHT.z, 0.0) * wrap);
	// (never below zero: a bright lightmap texel lit from underneath must not darken the smoke to black)
	DIFFUSE_LIGHT += LIGHT_COLOR * ATTENUATION * max(lit, 0.0) / PI;
}
"""

## Embers and sparks: a point of blackbody light (a hot core in a soft glow) stretched along its velocity, cooling
## from t_hot to t_cold Kelvin over its life (dimming as it goes, the way a spark goes red and out).
const STREAK_SHADER := """
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled;
uniform float stretch = 4.0;
uniform float energy = 1.0;
uniform float t_hot = 2200.0;
uniform float t_cold = 900.0;
uniform float max_size = 0.045;
%s
varying float v_age;
varying float v_rand;
varying float v_a;
void vertex(){
	float s = min(length(MODEL_MATRIX[0].xyz), max_size);
	vec3 c = MODEL_MATRIX[3].xyz;
	vec3 ax = MODEL_MATRIX[1].xyz;
	ax = length(ax) > 0.00001 ? normalize(ax) : vec3(0.0, 1.0, 0.0);
	vec3 to_cam = normalize(INV_VIEW_MATRIX[3].xyz - c);
	vec3 side = cross(ax, to_cam);
	float sl = length(side);
	vec3 side_n = sl > 0.05 ? side / sl : INV_VIEW_MATRIX[0].xyz;
	// seen end-on a streak is a dot
	float len = mix(1.0, stretch, smoothstep(0.05, 0.5, sl));
	vec3 n = normalize(cross(side_n, ax));
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(vec4(side_n * s, 0.0), vec4(ax * s * len, 0.0), vec4(n * s, 0.0), vec4(c, 1.0));
	v_age = clamp(INSTANCE_CUSTOM.y, 0.0, 1.0);
	v_rand = fract(sin(float(INSTANCE_ID) * 91.7) * 43758.5453);
	v_a = COLOR.a;
}
void fragment(){
	vec2 p = UV * 2.0 - 1.0;
	float r2 = p.x * p.x + p.y * p.y;
	float glow = exp(-r2 * 5.0);
	float core = exp(-r2 * 30.0);
	float kel = mix(t_hot, t_cold, pow(clamp(v_age, 0.0, 1.0), 0.6)) * (0.85 + 0.3 * v_rand);
	// a glowing grain: no wide halo (the tonemapper turned big soft halos yellow-green), orange to dark red
	float lum = energy * 2.2 * pow(kel / 1500.0, 2.0);
	float dot_ = exp(-r2 * 9.0);
	ALBEDO = blackbody(kel) * lum * dot_;
	ALPHA = clamp(v_a * dot_, 0.0, 1.0);
}
"""

## Heat haze: the solid scene behind the card bent by two drifting layers of a normal-mapped noise, strongest in the
## middle, fading in and out with the particle (drawn before the other see-through things, render_priority -20).
const HAZE_SHADER := """
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;
uniform sampler2D screen_tex : hint_screen_texture, filter_linear;
uniform sampler2D noise_tex : hint_normal, filter_linear, repeat_enable;
uniform float strength = 0.02;
%s
varying float v_a;
varying float v_seed;
void vertex(){
	float s = length(MODEL_MATRIX[0].xyz);
	vec3 c = MODEL_MATRIX[3].xyz;
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(vec4(INV_VIEW_MATRIX[0].xyz * s, 0.0), vec4(INV_VIEW_MATRIX[1].xyz * s, 0.0), vec4(INV_VIEW_MATRIX[2].xyz * s, 0.0), vec4(c, 1.0));
	v_a = COLOR.a;
	v_seed = fract(sin(float(INSTANCE_ID) * 17.31) * 4375.85);
}
void fragment(){
	float d = 1.0 - smoothstep(0.12, 0.5, distance(UV, vec2(0.5)));
	// two drifting layers of smooth noise as the bend (computed here: no texture to be generated first)
	vec2 q = UV * 3.0;
	vec2 n1 = vec2(fbm(q + vec2(v_seed, -TIME * 0.9)), fbm(q + vec2(5.2 + v_seed, -TIME * 0.9))) * 2.0 - 1.0;
	vec2 n2 = vec2(fbm(q * 2.1 + vec2(-v_seed * 3.0, -TIME * 1.7)), fbm(q * 2.1 + vec2(1.7, -TIME * 1.7 + 3.3))) * 2.0 - 1.0;
	float k = d * v_a;
	vec2 off = (n1 + n2 * 0.6) * strength * k;
	ALBEDO = textureLod(screen_tex, SCREEN_UV + off, 0.0).rgb;
	ALPHA = smoothstep(0.0, 0.25, k);
}
"""

## Over the arrow (material_overlay, the Meshy arrow: its head toward -z, tip at z -0.62): the head glowing with
## heat (blackbody, mottled), the shaft behind it charred and blistered black with embers in the cracks.
const HEAT_SHADER := """
shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_back, specular_disabled;
%s
%s
uniform float heat = 1.0;
uniform float char_amt = 1.0;
uniform float tip_z = -0.62;
uniform float head_z = -0.5;
uniform float char_len = 0.3;
varying vec3 mp;
void vertex(){ mp = VERTEX; }
void fragment(){
	float n = fbm(mp.xz * 60.0 + mp.y * 40.0);
	float n2 = vnoise(mp.xy * 120.0 + mp.z * 90.0);
	float along = mp.z - tip_z;
	float hl = head_z - tip_z;
	float head = 1.0 - smoothstep(hl - 0.02, hl + 0.03, along);
	float sootk = (1.0 - smoothstep(0.0, char_len, along - hl)) * (1.0 - head) * char_amt;
	float soot = clamp(sootk * (0.55 + 0.7 * n), 0.0, 1.0);
	float t = mix(780.0, 1180.0, heat * (0.55 + 0.45 * n)) * (0.95 + 0.1 * sin(TIME * 9.0 + n * 6.0));
	float hot = head * heat * smoothstep(0.25, 0.75, n + 0.25 * (1.0 - along / max(hl, 0.01)));
	float speck = sootk * step(0.78, n2) * 0.8;
	ALBEDO = vec3(0.025, 0.021, 0.018);
	ROUGHNESS = 0.95;
	EMISSION = blackbody(t) * (hot * 2.2 * pow(t / 1000.0, 4.0) + speck * 1.2);
	ALPHA = clamp(max(soot, hot * 0.9), 0.0, 1.0);
}
"""

## Compatibility's scorch (no decals there): a lit quad with the soot, its normal and the cooling ember cracks.
const SCORCH_SHADER := """
shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, specular_disabled;
uniform sampler2D tex : source_color, filter_linear_mipmap;
uniform sampler2D ntex : hint_normal, filter_linear_mipmap;
uniform sampler2D etex : source_color, filter_linear_mipmap;
uniform float glow = 1.0;
uniform float alpha_mul = 1.0;
void fragment(){
	vec4 t = texture(tex, UV);
	vec4 e = texture(etex, UV);
	ALBEDO = t.rgb;
	ROUGHNESS = 1.0;
	NORMAL_MAP = texture(ntex, UV).rgb;
	EMISSION = e.rgb * glow * glow * 5.0;
	ALPHA = t.a * alpha_mul;
}
"""

## The flame's tail (a strip along the flight, UV.x 0 at the head .. 1 at the tail, UV.y across): the sim's flame
## laid along it (its base at the head, its tips toward the tail), two frames of the loop a beat apart and mirrored
## so it never repeats, eaten by drifting noise more and more toward the tail so it tears into tongues, coloured by
## the sim's own temperature (blackbody), with a white-hot core just behind the head.
const RIBBON_FIRE_SHADER := """
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;
uniform sampler2D atlas : filter_linear_mipmap, repeat_disable;
uniform float energy = 3.0;
uniform float t_lo = 1000.0;
uniform float t_hi = 2400.0;
uniform float alpha_mul = 1.0;
uniform float seed = 0.0;
%s
%s
varying vec3 wpos;
void vertex(){ wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }
vec2 cell(float i, vec2 uv){ return (vec2(mod(i, 8.0), floor(i / 8.0)) + uv) / 8.0; }
vec2 samp(float fr, vec2 uv){
	float f0 = floor(fr);
	return mix(texture(atlas, cell(mod(f0, 64.0), uv)).rg, texture(atlas, cell(mod(f0 + 1.0, 64.0), uv)).rg, fr - f0);
}
void fragment(){
	float u = UV.x;
	float v = UV.y;
	vec2 c1 = vec2(0.5 + (v - 0.5) * 0.78, clamp(0.93 - u * 0.86, 0.02, 0.98));
	vec2 c2 = vec2(0.5 - (v - 0.5) * 0.62, clamp(0.93 - u * 0.95, 0.02, 0.98));
	float fr = TIME * 30.0 + seed * 13.0;
	vec2 a = samp(fr, c1);
	vec2 b = samp(fr * 1.13 + 21.0, c2) * 0.9;
	vec2 sv = max(a, b);
	// tearing: noise eats the flame, more toward the tail, drifting back along it
	float n = fbm(vec2(u * 7.0 - TIME * 5.0 + seed, v * 2.6) + wpos.xz * 0.5);
	float keep = smoothstep(u * 0.8 - 0.1, u * 0.8 + 0.25, n);
	float r = smoothstep(0.03, 1.0, sv.x) * keep;
	// the hot core just behind the head
	float core = pow(1.0 - u, 3.0) * exp(-pow((v - 0.5) * 5.0, 2.0)) * 0.55;
	r = clamp(r + core, 0.0, 1.0);
	float tm = clamp(sv.y / max(sv.x, 0.004), 0.0, 1.0);
	float kel = mix(t_lo, t_hi, clamp(max(tm * 1.05 * smoothstep(0.05, 0.95, r), core * 1.6), 0.0, 1.0));
	float lum = pow(r, 2.4) * energy * pow(kel / 1500.0, 2.5);
	ALBEDO = blackbody(kel) * lum;
	ALPHA = clamp(COLOR.a * alpha_mul, 0.0, 1.0);
}
"""

## The smoke behind the flame (a strip, UV.x in metres along it, UV.y across; COLOR.r how near the fire, COLOR.a
## its fade): billows of drifting noise, edges broken into wisps, sooty in the middle, lit by the scene's lights
## (wrapped, as thin smoke scatters) and, near the fire, glowing faintly orange from it.
const RIBBON_SMOKE_SHADER := """
shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, specular_disabled;
uniform vec4 tint : source_color = vec4(0.3, 0.285, 0.27, 1.0);
uniform vec4 glow_col : source_color = vec4(1.0, 0.36, 0.06, 1.0);
uniform float alpha_mul = 1.0;
uniform float seed = 0.0;
%s
varying vec3 wpos;
void vertex(){ wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }
void fragment(){
	float u = UV.x;
	float v = UV.y;
	float n = fbm(vec2(u * 1.3 - TIME * 0.35 + seed, v * 2.2 + TIME * 0.2));
	float n2 = fbm(vec2(u * 3.3 + TIME * 0.6, v * 4.5 + 3.0 + seed));
	float across = abs(v - 0.5) * 2.0;
	float body = 1.0 - smoothstep(0.25, 1.0, across + (n - 0.5) * 0.8);
	float a = body * smoothstep(0.3, 0.7, n * 0.75 + n2 * 0.45) * COLOR.a * alpha_mul * 0.8;
	ALBEDO = tint.rgb * mix(0.65, 1.15, n2) * mix(0.75, 1.0, across);
	NORMAL = vec3(0.0, 0.0, 1.0);
	EMISSION = glow_col.rgb * COLOR.r * 0.9 * a;
	ALPHA = clamp(a, 0.0, 1.0);
}
void light(){
	DIFFUSE_LIGHT += LIGHT_COLOR * ATTENUATION * (0.35 + 0.65 * max(dot(NORMAL, LIGHT), 0.0)) / PI;
}
"""
