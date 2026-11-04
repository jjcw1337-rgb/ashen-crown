class_name InfernalFx
extends RefCounted
## The Demon's visual language, reusable by any of his skills: hellfire (a corrupted black flame shell round a
## molten core, its edge glowing blood-red), the brand (a demonic sigil that draws itself on the ground), obsidian
## fangs (black glass shards with crimson veins, lit by the scene's lights), the rift (cracks racing over the
## ground), rolling smoke lit from below, a crescent wave of fire, heat haze, and the soft glow sprites the hits
## flash with. Everything is built in code from two noise textures made once (no texture files) and a handful of
## shaders compiled once; one-shot pieces go under the zone's FX node and free themselves.
##
## Palette: corrupted black carries the shapes (OBSIDIAN, SMOKE), dark CRIMSON the runes and the deep cracks,
## MOLTEN the core, WHITEHOT only the instant of a blow.
##
## Budgets: `tier(game)` 0 = Low (and the browser), 1 = Medium (or the OpenGL renderer), 2 = High, 3 = Ultra.
## Heat haze (a screen read) only from High on the Forward+ renderer; counts of shards, flames and particles
## scale with the tier.

const OBSIDIAN := Color(0.022, 0.014, 0.018)
const CRIMSON := Color(0.78, 0.035, 0.05)
const BLOODFIRE := Color(1.0, 0.14, 0.05)
const MOLTEN := Color(1.0, 0.42, 0.07)
const WHITEHOT := Color(1.0, 0.86, 0.62)
const SMOKE := Color(0.05, 0.034, 0.038)

## Simulated fire (tools/blender/fx/fire_flipbook.py, packed by tools/fx_flipbook.sh): 36 frames, 6 x 6.
const FIRE_FLIPBOOK := "res://assets/textures/fx/fire_flipbook.png"
const FLIP_GRID := Vector2(6, 6)
const FLIP_FPS := 30.0

## Preview tools can force a tier (-1 = from the game's graphics setting).
static var force_tier := -1

static var _shaders := {}
static var _noise: Texture2D
static var _cells: Texture2D
static var _quad: QuadMesh
static var _shard_meshes: Array = []
static var _arcs := {}

static func tier(game) -> int:
	if force_tier >= 0:
		return force_tier
	var q: int = int(game.get("quality")) if game != null and game.get("quality") != null else 1
	if OS.has_feature("web") or game == null or not game.has_method("is_forward") or not game.is_forward():
		q = mini(q, 1)
	return clampi(q, 0, 3)

## Heat haze reads the screen: Forward+ on High and Ultra only.
static func haze_ok(game) -> bool:
	if force_tier >= 0:
		return force_tier >= 2 and game != null and game.is_forward()
	return tier(game) >= 2 and game.is_forward()

# ---------------------------------------------------------------- resources made once
static func noise() -> Texture2D:
	if _noise == null:
		var n := FastNoiseLite.new()
		n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
		n.frequency = 1.0 / 42.0
		n.fractal_type = FastNoiseLite.FRACTAL_FBM
		n.fractal_octaves = 4
		n.seed = 1337
		var img := n.get_seamless_image(256, 256)
		img.generate_mipmaps()
		_noise = ImageTexture.create_from_image(img)
	return _noise

## Cell edges (F2 - F1): 0 on the borders between cells, for cracks and veins.
static func cells() -> Texture2D:
	if _cells == null:
		var n := FastNoiseLite.new()
		n.noise_type = FastNoiseLite.TYPE_CELLULAR
		n.cellular_return_type = FastNoiseLite.RETURN_DISTANCE2_SUB
		n.cellular_distance_function = FastNoiseLite.DISTANCE_EUCLIDEAN
		n.cellular_jitter = 1.0
		n.fractal_type = FastNoiseLite.FRACTAL_NONE
		n.frequency = 1.0 / 32.0
		n.seed = 666
		var img := n.get_seamless_image(256, 256, false, false, 0.05)
		img.generate_mipmaps()
		_cells = ImageTexture.create_from_image(img)
	return _cells

static func shader(key: String) -> Shader:
	if not _shaders.has(key):
		var s := Shader.new()
		s.code = {"flame": FLAME_SHADER, "glow": GLOW_SHADER, "smoke": SMOKE_SHADER, "sigil": SIGIL_SHADER,
			"rift": RIFT_SHADER, "shard": SHARD_SHADER, "wave": WAVE_SHADER, "haze": HAZE_SHADER,
			"tongue": TONGUE_SHADER, "flipfire": FLIPFIRE_SHADER}[key]
		_shaders[key] = s
	return _shaders[key]

static func quad() -> QuadMesh:
	if _quad == null:
		_quad = QuadMesh.new()
		_quad.size = Vector2.ONE
	return _quad

static func _palette(m: ShaderMaterial) -> ShaderMaterial:
	m.set_shader_parameter("crimson", CRIMSON)
	m.set_shader_parameter("molten", MOLTEN)
	m.set_shader_parameter("whitehot", WHITEHOT)
	return m

## Compiles every shader once by drawing a tiny copy of each under the given node (a first cast would hitch).
static func warm(parent: Node3D, game) -> void:
	if parent == null or not parent.is_inside_tree():
		return
	var mats := [flame_mat(), tongue_mat(), glow_mat(MOLTEN), smoke_mat(), sigil_mat(), rift_mat(), shard_mat(), shard_mat(true), wave_mat()]
	if haze_ok(game):
		mats.append(haze_mat())
	for m in mats:
		var mi := MeshInstance3D.new()
		mi.mesh = quad()
		mi.material_override = m
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.scale = Vector3.ONE * 0.001
		parent.add_child(mi)
		mi.position = Vector3(0, 0.05, 0)
		Fx._free_later(mi, 0.3)

# ---------------------------------------------------------------- materials (a new one per use, so it can be animated)
## Hellfire: dark = how much black shell, heat = brightness, alpha = fade, lean = the tip's sway.
static func flame_mat(dark := 0.85, heat := 1.0, speed := 1.0) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = shader("flame")
	m.set_shader_parameter("noise_tex", noise())
	m.set_shader_parameter("dark", dark)
	m.set_shader_parameter("heat", heat)
	m.set_shader_parameter("speed", speed)
	m.set_shader_parameter("seed", randf() * 10.0)
	return _palette(m)

static func glow_mat(col: Color, energy := 2.0, power := 2.2, rays := 0.0) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = shader("glow")
	m.set_shader_parameter("color", col)
	m.set_shader_parameter("energy", energy)
	m.set_shader_parameter("power", power)
	m.set_shader_parameter("rays", rays)
	m.set_shader_parameter("seed", randf() * 6.28)
	return m

static func smoke_mat(glow := 1.0, density := 0.8) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = shader("smoke")
	m.set_shader_parameter("noise_tex", noise())
	m.set_shader_parameter("smoke", SMOKE)
	m.set_shader_parameter("glow_col", BLOODFIRE)
	m.set_shader_parameter("glow_amt", glow)
	m.set_shader_parameter("density", density)
	return m

static func sigil_mat() -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = shader("sigil")
	m.set_shader_parameter("seed", float(randi() % 97))
	return _palette(m)

static func rift_mat() -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = shader("rift")
	m.set_shader_parameter("noise_tex", noise())
	m.set_shader_parameter("cell_tex", cells())
	m.set_shader_parameter("seed", randf() * 10.0)
	return _palette(m)

static func shard_mat(particle := false) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = shader("shard")
	m.set_shader_parameter("cell_tex", cells())
	m.set_shader_parameter("particle", particle)
	return _palette(m)

static func wave_mat() -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = shader("wave")
	m.set_shader_parameter("noise_tex", noise())
	m.set_shader_parameter("seed", randf() * 10.0)
	return _palette(m)

static func haze_mat(strength := 0.025, round_mask := false) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = shader("haze")
	m.set_shader_parameter("noise_tex", noise())
	m.set_shader_parameter("strength", strength)
	m.set_shader_parameter("round_mask", round_mask)
	return m

static func tween_param(n: Node, m: ShaderMaterial, param: String, from: float, to: float, dur: float, delay := 0.0) -> Tween:
	var tw := n.create_tween()
	if delay > 0.0:
		tw.tween_interval(delay)
	tw.tween_method(func(v: float): m.set_shader_parameter(param, v), from, to, dur)
	return tw

# ---------------------------------------------------------------- pieces
## A hellfire flame standing upright at pos (it turns to the camera round its own vertical axis), size in metres.
static func flame(root: Node3D, pos: Vector3, size: Vector2, mat: ShaderMaterial) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = quad()
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.extra_cull_margin = 2.0
	root.add_child(mi)
	mi.global_position = pos
	mi.scale = Vector3(size.x, size.y, 1.0)
	return mi

## Living fire: no fixed shape. A stream of short-lived flame tongues (particles) born in a small volume, each one
## its own warped, eroding wisp that rises, stretches, twists, splits and burns out from white-gold through molten
## and crimson to a black, smoking tip; turbulence pushes them about, so the silhouette never repeats. Soot rises
## off the top (blend mix), a few embers spin away. World-space particles: moved (a fist swinging), the fire
## streams back off it. size = the fire's height in metres; rate = tongues per second.
static func fire(parent: Node3D, pos: Vector3, size := 0.8, rate := 40.0, tr := 2, soot := true, embers := true) -> Node3D:
	var n := Node3D.new()
	parent.add_child(n)
	n.global_position = pos
	var life := 0.32 + size * 0.28
	var q := QuadMesh.new()
	q.size = Vector2(size * 0.7, size * 1.0)
	q.center_offset = Vector3(0, size * 0.42, 0)
	q.material = tongue_mat(life)
	# each simulated-fire particle is a whole flame, so far fewer of them than procedural tongues
	var per := 0.16 if flipbook() != null else 0.5
	var tongues := particles(n, pos, {"amount": maxi(3, int(rate * per * life * [0.5, 0.75, 1.0, 1.25][tr])), "life": life,
		"one_shot": false, "randomness": 0.5, "shape": "sphere", "r": size * 0.16, "dir": Vector3.UP, "spread": 12.0,
		"vel": [size * 0.3, size * 1.0], "gravity": size * 1.6, "damping": [0.0, 0.6], "scale": [0.55, 1.15],
		"grow": [0.55, 1.0], "angle": true, "turb": size * 1.6, "mesh": q,
		"colors": [[0.0, Color(1, 1, 1, 0.0)], [0.08, Color(1, 1, 1, 1.0)], [1.0, Color(1, 1, 1, 1.0)]]})
	tongues.name = "tongues"
	# a hot, tight churn at the root (fewer, smaller, brighter)
	var q2 := QuadMesh.new()
	q2.size = Vector2(size * 0.35, size * 0.42)
	q2.center_offset = Vector3(0, size * 0.1, 0)
	var core_mat := tongue_mat(0.22)
	core_mat.set_shader_parameter("hot", 1.05)
	q2.material = core_mat
	var core := particles(n, pos, {"amount": maxi(3, int(rate * 0.35 * [0.5, 0.75, 1.0, 1.0][tr] * 0.15)), "life": 0.22,
		"one_shot": false, "randomness": 0.4, "shape": "sphere", "r": size * 0.1, "dir": Vector3.UP, "spread": 25.0,
		"vel": [size * 0.6, size * 1.4], "gravity": size, "scale": [0.6, 1.1], "angle": true, "mesh": q2,
		"colors": [[0.0, Color(1, 1, 1, 0.0)], [0.15, Color(1, 1, 1, 1.0)], [1.0, Color(1, 1, 1, 1.0)]]})
	core.name = "core"
	if soot and tr >= 1:
		var q3 := QuadMesh.new()
		q3.size = Vector2(size * 0.5, size * 0.5)
		q3.material = smoke_mat(0.5, 0.65)
		var s := particles(n, pos + Vector3(0, size * 0.6, 0), {"amount": maxi(3, int(rate * 0.18 * [0.0, 0.6, 1.0, 1.2][tr])),
			"life": 0.9, "one_shot": false, "randomness": 0.5, "shape": "sphere", "r": size * 0.15, "dir": Vector3.UP,
			"spread": 18.0, "vel": [size * 1.0, size * 1.8], "gravity": size * 0.6, "damping": [0.5, 1.0], "scale": [0.6, 1.2],
			"grow": [0.5, 1.7], "angle": true, "spin": 40.0, "turb": size * 1.2, "mesh": q3,
			"colors": [[0.0, Color(1, 1, 1, 0.0)], [0.25, Color(1, 1, 1, 0.75)], [1.0, Color(1, 1, 1, 0.0)]]})
		s.name = "soot"
	if embers:
		var e := particles(n, pos + Vector3(0, size * 0.3, 0), {"amount": maxi(3, int(rate * 0.25 * [0.4, 0.7, 1.0, 1.2][tr])),
			"life": 0.8, "one_shot": false, "randomness": 0.6, "shape": "sphere", "r": size * 0.2, "dir": Vector3.UP,
			"spread": 35.0, "vel": [size * 1.5, size * 3.5], "gravity": size * 1.5, "damping": [0.3, 1.0],
			"scale": [0.4, 1.0], "size": clampf(size * 0.06, 0.025, 0.07), "turb": size * 3.0,
			"colors": [[0.0, WHITEHOT], [0.3, MOLTEN], [0.75, BLOODFIRE], [1.0, Color(CRIMSON, 0.0)]]})
		e.name = "embers"
	return n

## A fire that is already burning when it appears (its particles pre-run a lifetime).
static func ready_fire(f: Node3D) -> Node3D:
	for c in f.get_children():
		if c is GPUParticles3D:
			(c as GPUParticles3D).preprocess = (c as GPUParticles3D).lifetime
	return f

## Turns a fire on or off (off: the tongues already alive burn out, nothing new is born).
## Turns a fire made here (`fire`, `smoke`) blue: the spirit-fire of the camp waypoint's braziers (FireFx "spirit").
## Its flipbook flames play the spirit book (already blue) with the shader's `cool`, and the palette, the smoke's
## glow and the embers' colours go to SPIRIT; every mesh, material and colour ramp is copied first, so the shared
## ones stay red. For a blue stash chest (jj's stash #2, Battlegrounds.STASH_THEMES).
const SPIRIT := [Color(0.2, 0.37, 0.78), Color(0.35, 0.66, 1.0), Color(0.66, 0.88, 1.0)]   # crimson, molten, whitehot

static func spirit(n: Node) -> void:
	var ps: Array = n.find_children("*", "GPUParticles3D", true, false)
	if n is GPUParticles3D:
		ps.append(n)
	for p in ps:
		var gp: GPUParticles3D = p
		if gp.process_material is ParticleProcessMaterial:
			var pm := (gp.process_material as ParticleProcessMaterial).duplicate(true) as ParticleProcessMaterial
			if pm.color_ramp is GradientTexture1D and (pm.color_ramp as GradientTexture1D).gradient != null:
				var gr := (pm.color_ramp as GradientTexture1D).gradient
				for i in gr.get_point_count():
					gr.set_color(i, _to_spirit(gr.get_color(i)))
			pm.color = _to_spirit(pm.color)
			gp.process_material = pm
		for i in gp.draw_passes:
			var me := gp.get_draw_pass_mesh(i)
			if me is PrimitiveMesh and (me as PrimitiveMesh).material is ShaderMaterial:
				var m2 := me.duplicate() as PrimitiveMesh
				var sm := (m2.material as ShaderMaterial).duplicate() as ShaderMaterial
				_spirit_mat(sm)
				m2.material = sm
				gp.set_draw_pass_mesh(i, m2)
		if gp.material_override is ShaderMaterial:
			var mo := (gp.material_override as ShaderMaterial).duplicate() as ShaderMaterial
			_spirit_mat(mo)
			gp.material_override = mo

static func _spirit_mat(sm: ShaderMaterial) -> void:
	if sm.get_shader_parameter("flip_tex") != null and FireFx.book("spirit") != null:
		sm.set_shader_parameter("flip_tex", FireFx.book("spirit"))
		sm.set_shader_parameter("grid", FireFx.grid_of("spirit"))
		sm.set_shader_parameter("tint", 0.0)
		sm.set_shader_parameter("cool", 1.0)
	sm.set_shader_parameter("crimson", SPIRIT[0])
	sm.set_shader_parameter("molten", SPIRIT[1])
	sm.set_shader_parameter("whitehot", SPIRIT[2])
	if sm.get_shader_parameter("glow_col") != null:
		sm.set_shader_parameter("glow_col", SPIRIT[0])
	if sm.get_shader_parameter("color") is Color:
		sm.set_shader_parameter("color", _to_spirit(sm.get_shader_parameter("color")))

## A fire colour turned to the spirit-fire's: its brightness kept, its hue moved to blue (orange -> electric blue,
## white-hot -> cyan-white, blood red -> deep blue); alpha kept.
static func _to_spirit(c: Color) -> Color:
	var l := maxf(c.r, maxf(c.g, c.b))
	return Color(0.25 * l + 0.55 * c.g * c.g, 0.45 * l + 0.5 * c.g, l, c.a)

static func fire_on(f: Node3D, on: bool) -> void:
	if f == null or not is_instance_valid(f):
		return
	for c in f.get_children():
		if c is GPUParticles3D:
			(c as GPUParticles3D).emitting = on

static var _flipbook: Texture2D
static func flipbook() -> Texture2D:
	if _flipbook == null:
		_flipbook = FireFx.book("tongue")      # the game's simulated fire (falls back to the body book)
	if _flipbook == null and ResourceLoader.exists(FIRE_FLIPBOOK):
		_flipbook = load(FIRE_FLIPBOOK)
	return _flipbook

## A flame tongue: the simulated fire's flipbook when it is there, else the procedural flame. life = the
## particle's lifetime (the flipbook plays at FLIP_FPS through it).
static func tongue_mat(life := 0.6) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	var fb := flipbook()
	if fb != null:
		m.shader = shader("flipfire")
		m.set_shader_parameter("flip_tex", fb)
		m.set_shader_parameter("grid", FireFx.grid_of("tongue"))
		m.set_shader_parameter("frames_per_life", FLIP_FPS * life)
		return _palette(m)
	m.shader = shader("tongue")
	m.set_shader_parameter("noise_tex", noise())
	return _palette(m)

## A soft glow facing the camera (hit flashes, the cores of the fists).
static func glow(root: Node3D, pos: Vector3, size: float, mat: ShaderMaterial) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = quad()
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.extra_cull_margin = 2.0
	root.add_child(mi)
	mi.global_position = pos
	mi.scale = Vector3.ONE * size
	return mi

## A particle system from a description (the keys are ParticleProcessMaterial's, shortened). World space.
##   amount, life, one_shot, explosive, shape ("sphere" r / "box" box / "ring" r), dir, spread, vel [min, max],
##   gravity, radial [min, max], damping [min, max], scale [min, max], grow [start, end] (a scale curve),
##   colors [[offset, Color]...], size, mat (a draw material; else the game's soft particle), mesh, angle (random spin)
static func particles(root: Node3D, pos: Vector3, d: Dictionary) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = maxi(1, int(d.get("amount", 16)))
	p.lifetime = float(d.get("life", 0.6))
	p.one_shot = bool(d.get("one_shot", true))
	p.explosiveness = float(d.get("explosive", 0.9 if p.one_shot else 0.0))
	p.randomness = float(d.get("randomness", 0.3))
	p.local_coords = false
	p.fixed_fps = 0
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var pm := ParticleProcessMaterial.new()
	match str(d.get("shape", "point")):
		"sphere":
			pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
			pm.emission_sphere_radius = float(d.get("r", 0.2))
		"box":
			pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
			pm.emission_box_extents = d.get("box", Vector3.ONE * 0.5)
		"ring":
			pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_RING
			pm.emission_ring_axis = Vector3.UP
			pm.emission_ring_radius = float(d.get("r", 1.0))
			pm.emission_ring_inner_radius = float(d.get("r_in", float(d.get("r", 1.0)) * 0.8))
			pm.emission_ring_height = 0.05
		"points":
			pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_POINTS
			pm.emission_point_texture = d["points"]
			pm.emission_point_count = int(d.get("point_count", 1))
	pm.direction = d.get("dir", Vector3.UP)
	pm.spread = float(d.get("spread", 30.0))
	var vel: Array = d.get("vel", [1.0, 2.0])
	pm.initial_velocity_min = vel[0]
	pm.initial_velocity_max = vel[1]
	pm.gravity = Vector3(0, float(d.get("gravity", 0.0)), 0)
	if d.has("radial"):
		pm.radial_accel_min = d["radial"][0]
		pm.radial_accel_max = d["radial"][1]
	if d.has("damping"):
		pm.damping_min = d["damping"][0]
		pm.damping_max = d["damping"][1]
	var sc: Array = d.get("scale", [0.6, 1.2])
	pm.scale_min = sc[0]
	pm.scale_max = sc[1]
	if d.has("grow"):
		var c := Curve.new()
		c.add_point(Vector2(0.0, d["grow"][0]))
		c.add_point(Vector2(1.0, d["grow"][1]))
		var ct := CurveTexture.new()
		ct.curve = c
		pm.scale_curve = ct
	if d.has("angle"):
		pm.angle_min = -180.0
		pm.angle_max = 180.0
	if d.has("turb"):
		pm.turbulence_enabled = true
		pm.turbulence_noise_strength = float(d["turb"])
		pm.turbulence_noise_scale = 2.2
		pm.turbulence_noise_speed_random = 0.4
		pm.turbulence_noise_speed = Vector3(0.0, 0.6, 0.0)
		pm.turbulence_influence_min = 0.05
		pm.turbulence_influence_max = 0.18
	if d.has("spin"):
		pm.angular_velocity_min = -float(d["spin"])
		pm.angular_velocity_max = float(d["spin"])
	if d.has("colors"):
		var g := Gradient.new()
		var cs: Array = d["colors"]
		g.set_offset(0, cs[0][0])
		g.set_color(0, cs[0][1])
		g.set_offset(1, cs[cs.size() - 1][0])
		g.set_color(1, cs[cs.size() - 1][1])
		for i in range(1, cs.size() - 1):
			g.add_point(cs[i][0], cs[i][1])
		var gt := GradientTexture1D.new()
		gt.gradient = g
		pm.color_ramp = gt
	p.process_material = pm
	if d.has("mesh"):
		p.draw_pass_1 = d["mesh"]
		if d.has("mat"):
			p.material_override = d["mat"]
	else:
		var q := QuadMesh.new()
		var s: float = float(d.get("size", 0.1))
		q.size = Vector2(s, s)
		q.material = d["mat"] if d.has("mat") else Mats.particle_mat(bool(d.get("add", true)), Color(2, 2, 2) if bool(d.get("add", true)) else Color.WHITE)
		p.draw_pass_1 = q
	p.visibility_aabb = AABB(Vector3(-6, -2, -6), Vector3(12, 8, 12))
	root.add_child(p)
	if p.is_inside_tree():
		p.global_position = pos
	else:
		p.position = pos
	p.emitting = true
	if p.one_shot:
		Fx._free_later(p, p.lifetime + 0.6)
	return p

## Low, dark smoke that rolls out and up, lit from below by the fire (blend: mix, few big particles).
static func smoke(root: Node3D, pos: Vector3, amount: int, box: Vector3, dir: Vector3, size := 1.4, life := 1.6, glow_amt := 1.0, density := 0.8) -> GPUParticles3D:
	var mat := smoke_mat(glow_amt, density)
	var q := QuadMesh.new()
	q.size = Vector2(size, size)
	q.material = mat
	return particles(root, pos, {"amount": amount, "life": life, "explosive": 0.75, "shape": "box", "box": box,
		"dir": dir, "spread": 35.0, "vel": [0.8, 2.2], "gravity": 0.35, "damping": [1.2, 2.0], "scale": [0.7, 1.25],
		"grow": [0.55, 1.6], "angle": true, "spin": 25.0, "mesh": q,
		"colors": [[0.0, Color(1, 1, 1, 0.0)], [0.12, Color(1, 1, 1, 0.9)], [0.55, Color(1, 1, 1, 0.55)], [1.0, Color(1, 1, 1, 0.0)]]})

## A ground mesh following the terrain: a wedge from radius r0 to r1 over +-half (rad) round yaw (facing -z
## at yaw 0), vertices relative to `at`. UV.x across the wedge (0 at +half .. 1 at -half), UV.y out along it.
static func wedge_mesh(world, at: Vector3, yaw: float, r0: float, r1: float, half: float, segs := 18, rings := 10, lift := 0.045) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var pts := []
	for i in rings + 1:
		var r := lerpf(r0, r1, float(i) / rings)
		for j in segs + 1:
			var u := float(j) / segs
			var a := yaw + lerpf(half, -half, u)
			var p := at + Vector3(-sin(a), 0.0, -cos(a)) * r
			p.y = (world.height_at(p.x, p.z) if world != null else at.y) + lift
			pts.append([p - at, Vector2(u, float(i) / rings)])
	for i in rings:
		for j in segs:
			var a0: int = i * (segs + 1) + j
			for k in [a0, a0 + segs + 1, a0 + 1, a0 + 1, a0 + segs + 1, a0 + segs + 2]:
				st.set_uv(pts[k][1])
				st.set_normal(Vector3.UP)
				st.add_vertex(pts[k][0])
	return st.commit()

## A disc on the terrain round `at` (UV 0.5 at the centre, unrotated).
static func disc_mesh(world, at: Vector3, radius: float, segs := 32, rings := 5, lift := 0.05) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var pts := [[Vector3(0, (world.height_at(at.x, at.z) if world != null else at.y) + lift - at.y, 0), Vector2(0.5, 0.5)]]
	for i in range(1, rings + 1):
		var r := radius * float(i) / rings
		for j in segs:
			var a := TAU * j / segs
			var p := at + Vector3(cos(a), 0, sin(a)) * r
			p.y = (world.height_at(p.x, p.z) if world != null else at.y) + lift
			pts.append([p - at, Vector2(0.5 + cos(a) * r / radius * 0.5, 0.5 + sin(a) * r / radius * 0.5)])
	for j in segs:
		for k in [0, 1 + (j + 1) % segs, 1 + j]:
			st.set_uv(pts[k][1])
			st.set_normal(Vector3.UP)
			st.add_vertex(pts[k][0])
	for i in range(1, rings):
		var o0 := 1 + (i - 1) * segs
		var o1 := 1 + i * segs
		for j in segs:
			var j1 := (j + 1) % segs
			for k in [o0 + j, o0 + j1, o1 + j, o0 + j1, o1 + j1, o1 + j]:
				st.set_uv(pts[k][1])
				st.set_normal(Vector3.UP)
				st.add_vertex(pts[k][0])
	return st.commit()

## A standing arc of unit radius round the origin over +-half (rad) facing -z, 1 high, its top leaning out a little.
## UV.x along the arc, UV.y 0 at the foot .. 1 at the top.
static func arc_mesh(half: float) -> ArrayMesh:
	var key := int(round(rad_to_deg(half)))
	if _arcs.has(key):
		return _arcs[key]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var segs := 24
	for j in segs:
		var corners := []
		for jj in [j, j + 1]:
			var u := float(jj) / segs
			var a := lerpf(half, -half, u)
			var d := Vector3(-sin(a), 0.0, -cos(a))
			corners.append([d, d * 1.12 + Vector3(0, 1, 0), u])
		var c0: Array = corners[0]
		var c1: Array = corners[1]
		for v in [[c0[0], Vector2(c0[2], 0)], [c0[1], Vector2(c0[2], 1)], [c1[0], Vector2(c1[2], 0)],
				[c1[0], Vector2(c1[2], 0)], [c0[1], Vector2(c0[2], 1)], [c1[1], Vector2(c1[2], 1)]]:
			st.set_uv(v[1])
			st.set_normal(-(v[0] as Vector3) * Vector3(1, 0, 1))
			st.add_vertex(v[0])
	_arcs[key] = st.commit()
	return _arcs[key]

## Obsidian shards: faceted, irregular spikes 1 high from y -0.35 (so they rise out of the ground) to a leaning
## tip. A few variants made once.
static func shard_mesh(i: int) -> ArrayMesh:
	if _shard_meshes.is_empty():
		var rng := RandomNumberGenerator.new()
		rng.seed = 4242
		for v in 6:
			var st := SurfaceTool.new()
			st.begin(Mesh.PRIMITIVE_TRIANGLES)
			var n := 5 + (v % 2)
			var base := []
			var mid := []
			for k in n:
				var a := TAU * k / n + rng.randf_range(-0.3, 0.3)
				var rb := rng.randf_range(0.17, 0.3)
				base.append(Vector3(cos(a) * rb, -0.35, sin(a) * rb))
				var rm := rb * rng.randf_range(0.5, 0.75)
				mid.append(Vector3(cos(a + 0.2) * rm + 0.04, 0.45 + rng.randf_range(-0.08, 0.1), sin(a + 0.2) * rm))
			var tip := Vector3(rng.randf_range(0.04, 0.16), 1.0, rng.randf_range(-0.06, 0.06))
			for k in n:
				var k1 := (k + 1) % n
				for tri in [[base[k], mid[k], base[k1]], [base[k1], mid[k], mid[k1]], [mid[k], tip, mid[k1]]]:
					var nrm: Vector3 = ((tri[1] - tri[0]) as Vector3).cross(tri[2] - tri[0]).normalized()
					if nrm.dot(((tri[0] + tri[1] + tri[2]) / 3.0) * Vector3(1, 0, 1)) < 0.0:
						nrm = -nrm
						tri = [tri[0], tri[2], tri[1]]
					for p in tri:
						st.set_normal(nrm)
						st.set_uv(Vector2(0.0, (p as Vector3).y))
						st.add_vertex(p)
			_shard_meshes.append(st.commit())
	return _shard_meshes[i % _shard_meshes.size()]

## A burst of points flown in a parabola with a spin, freed at the end (shatter fragments). Cheap: one tween each.
static func fly(n: Node3D, v: Vector3, w: Vector3, dur: float, g := -14.0, shrink := true) -> void:
	var p0 := n.global_position
	var r0 := n.rotation
	var s0 := n.scale
	var step := func(u: float) -> void:
		var t := u * dur
		n.global_position = p0 + v * t + Vector3(0, 0.5 * g * t * t, 0)
		n.rotation = r0 + w * t
		if shrink:
			n.scale = s0 * maxf(1.0 - smoothstep(0.6, 1.0, u), 0.001)
	var tw := n.create_tween()
	tw.tween_method(step, 0.0, 1.0, dur)
	tw.tween_callback(n.queue_free)

# ---------------------------------------------------------------- shaders
## Hellfire. A camera-facing (round the vertical) quad, sized by the node's scale. Premultiplied alpha: the black
## shell darkens what is behind it, the fire inside adds light.
const FLAME_SHADER := """
shader_type spatial;
render_mode unshaded, blend_premul_alpha, depth_draw_never, cull_disabled, shadows_disabled, world_vertex_coords, fog_disabled;
uniform sampler2D noise_tex : repeat_enable, filter_linear_mipmap;
uniform float dark = 0.85;
uniform float heat = 1.0;
uniform float alpha = 1.0;
uniform float seed = 0.0;
uniform float speed = 1.0;
uniform float lean = 0.0;
uniform vec3 crimson : source_color = vec3(0.78, 0.035, 0.05);
uniform vec3 molten : source_color = vec3(1.0, 0.42, 0.07);
uniform vec3 whitehot : source_color = vec3(1.0, 0.86, 0.62);
varying vec2 v_uv;
void vertex() {
	vec3 o = NODE_POSITION_WORLD;
	vec2 sz = vec2(length(MODEL_MATRIX[0].xyz), length(MODEL_MATRIX[1].xyz));
	vec3 to = CAMERA_POSITION_WORLD - o;
	to.y = 0.0;
	vec3 fw = length(to) > 0.001 ? normalize(to) : vec3(0.0, 0.0, 1.0);
	vec3 rt = normalize(cross(vec3(0.0, 1.0, 0.0), fw));
	vec3 up = normalize(vec3(0.0, 1.0, 0.0) + fw * 0.35);
	vec2 c = vec2(UV.x - 0.5, 1.0 - UV.y);
	VERTEX = o + rt * c.x * sz.x + up * c.y * sz.y;
	v_uv = vec2(UV.x, 1.0 - UV.y);
}
void fragment() {
	vec2 uv = v_uv;
	float t = TIME * speed;
	float n1 = texture(noise_tex, vec2(uv.x * 0.9 + seed, uv.y * 0.75 - t * 1.3)).r;
	float n2 = texture(noise_tex, vec2(uv.x * 1.9 - seed * 1.7, uv.y * 1.6 - t * 2.4)).r;
	float n = n1 * 0.62 + n2 * 0.38;
	float x = (uv.x - 0.5) * 2.0;
	x += (n1 - 0.5) * 0.9 * uv.y + lean * uv.y * uv.y;
	float w = mix(0.92, 0.16, uv.y);
	float body = 1.0 - smoothstep(w * 0.3, w, abs(x));
	body *= smoothstep(0.0, 0.15, uv.y) * (1.0 - smoothstep(0.86, 1.0, uv.y));
	float f = body * (1.2 - uv.y * 1.05) + (n - 0.5) * 0.9 * body;
	float shell = smoothstep(0.05, 0.25, f);
	float fire = smoothstep(0.38, 0.62, f);
	float core = smoothstep(0.62, 0.9, f);
	float rim = clamp(shell - fire, 0.0, 1.0);
	// the corruption: black tendrils of smoke cutting through the fire
	float tendril = smoothstep(0.58, 0.74, n2) * dark * (1.0 - core * 0.6);
	vec3 col = crimson * 2.0 * clamp(fire - core, 0.0, 1.0) + molten * 2.4 * core + whitehot * 2.6 * smoothstep(0.88, 1.1, f);
	col *= 1.0 - tendril * 0.85;
	col += crimson * 1.1 * rim * smoothstep(0.05, 0.4, uv.y);
	col *= heat;
	float a = clamp(shell * dark * 0.92 + fire * 0.5, 0.0, 1.0);
	ALBEDO = col * alpha;
	ALPHA = a * alpha;
}
"""

## A flame tongue (fire's particles): camera-facing, standing on its particle. The noise warps itself (two passes,
## scrolling up), the tongue sways and erodes from its edges and its top as it rises and ages, so it breaks into
## licks and wisps. Heat (young, low, dense) runs a ramp from white-gold through molten and crimson to black: the
## old, high, thin parts are soot that darkens what is behind them (premultiplied), the hot heart adds light.
const TONGUE_SHADER := """
shader_type spatial;
render_mode unshaded, blend_premul_alpha, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;
uniform sampler2D noise_tex : repeat_enable, filter_linear_mipmap;
uniform float hot = 1.0;
uniform vec3 crimson : source_color = vec3(0.78, 0.035, 0.05);
uniform vec3 molten : source_color = vec3(1.0, 0.42, 0.07);
uniform vec3 whitehot : source_color = vec3(1.0, 0.86, 0.62);
varying float v_age;
varying float v_rnd;
void vertex() {
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
	MODELVIEW_MATRIX = MODELVIEW_MATRIX * mat4(vec4(length(MODEL_MATRIX[0].xyz), 0.0, 0.0, 0.0), vec4(0.0, length(MODEL_MATRIX[1].xyz), 0.0, 0.0), vec4(0.0, 0.0, length(MODEL_MATRIX[2].xyz), 0.0), vec4(0.0, 0.0, 0.0, 1.0));
	v_age = INSTANCE_CUSTOM.y;
	v_rnd = INSTANCE_CUSTOM.x * 1.7;
}
float fbm(vec2 p) {
	return texture(noise_tex, p * 0.25).r * 0.55 + texture(noise_tex, p * 0.5 + 3.1).r * 0.3 + texture(noise_tex, p + 7.7).r * 0.15;
}
void fragment() {
	// a flame the way real fire moves: fractal noise racing upward pushes the edge of a soft column outward, more
	// and more toward the top, so tongues stretch, pinch off and burn out; the colour is a black-body ramp of the
	// heat (red, orange, yellow, a pale heart) and the flame is mostly light (premultiplied, low alpha)
	vec2 uv = vec2(UV.x, 1.0 - UV.y);
	float t = TIME * (1.0 + 0.25 * fract(v_rnd * 3.7)) + v_rnd * 13.0;
	vec2 q = vec2(uv.x - 0.5, uv.y * 2.0 - 0.25);
	float n = (fbm(vec2(q.x * 1.5, q.y * 1.2) + vec2(v_rnd, -t * 1.6)) - 0.5) * 1.8 + 0.5;
	n = clamp(n, 0.0, 1.0);
	float c = 1.0 - 16.0 * pow(max(0.0, length(q * vec2(1.8 + q.y * 1.5, 0.75)) - n * max(0.0, q.y + 0.25)), 1.2);
	float fade = 1.0 - smoothstep(0.35, 1.0, v_age);
	float c1 = clamp(n * c * (1.5 - pow(1.25 * uv.y, 4.0)) * hot * fade, 0.0, 1.0);
	// kept low: many flames overlap, and their light adds up (it must stay orange, never clip to white)
	vec3 col = vec3(1.0 * c1, 0.55 * pow(c1, 2.4), 0.18 * pow(c1, 6.0)) * 0.62;
	float a = clamp(c * (1.0 - pow(uv.y, 3.0)), 0.0, 1.0) * fade * COLOR.a;
	ALBEDO = col * a;
	ALPHA = a * 0.22 * (1.0 - c1);
}
"""

## Simulated fire played from its flipbook on a flame particle: each particle starts at its own frame, plays at
## the sim's speed through its life (blending frame to frame), is flipped at random, fades in and burns out. The
## frames are the fire's light on black, so it is all light (premultiplied, almost no alpha). `hot` scales it;
## `tint` pulls it toward the Demon's hellfire.
const FLIPFIRE_SHADER := """
shader_type spatial;
render_mode unshaded, blend_premul_alpha, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;
uniform sampler2D flip_tex : source_color, filter_linear_mipmap;
uniform vec2 grid = vec2(6.0, 6.0);
uniform float frames_per_life = 18.0;
uniform float hot = 1.0;
uniform float tint = 0.25;
uniform float cool = 0.0;     // the blue spirit-fire: keeps red and green low so overlapping flames sum to blue, not white
uniform float fade_in = 0.12;     // of the flame's life
uniform float fade_out = 0.55;    // it burns out from here to the end of its life
uniform float seamless = 0.0;     // 1: start where the whole life plays without wrapping past the book's last frame
uniform vec3 crimson : source_color = vec3(0.78, 0.035, 0.05);
uniform vec3 molten : source_color = vec3(1.0, 0.42, 0.07);
uniform vec3 whitehot : source_color = vec3(1.0, 0.86, 0.62);
varying float v_age;
varying float v_rnd;
void vertex() {
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
	MODELVIEW_MATRIX = MODELVIEW_MATRIX * mat4(vec4(length(MODEL_MATRIX[0].xyz), 0.0, 0.0, 0.0), vec4(0.0, length(MODEL_MATRIX[1].xyz), 0.0, 0.0), vec4(0.0, 0.0, length(MODEL_MATRIX[2].xyz), 0.0), vec4(0.0, 0.0, 0.0, 1.0));
	v_age = INSTANCE_CUSTOM.y;
	v_rnd = fract(INSTANCE_CUSTOM.x * 0.1591549 + 0.5);
}
vec3 frame_at(float f, vec2 uv) {
	float n = grid.x * grid.y;
	f = mod(f, n);
	vec2 cell = vec2(mod(f, grid.x), floor(f / grid.x));
	return texture(flip_tex, (cell + uv) / grid).rgb;
}
void fragment() {
	vec2 uv = UV;
	bool flip = seamless > 0.5 ? fract(v_rnd * 7.31) > 0.5 : v_rnd > 0.5;
	if (flip) { uv.x = 1.0 - uv.x; }
	float span = grid.x * grid.y - 1.0;
	float f = v_rnd * mix(span, max(span - frames_per_life - 1.0, 0.0), seamless) + v_age * frames_per_life;
	float f0 = floor(f);
	vec3 c = mix(frame_at(f0, uv), frame_at(f0 + 1.0, uv), f - f0);
	float fade = smoothstep(0.0, fade_in, v_age) * (1.0 - smoothstep(fade_out, 1.0, v_age));
	// the sim's floor is the frame's bottom edge: soften it so a flame never shows a straight cut
	fade *= smoothstep(0.0, 0.14, 1.0 - UV.y) * smoothstep(0.0, 0.2, UV.y);   // and its ceiling
	fade *= smoothstep(0.0, 0.16, UV.x) * smoothstep(0.0, 0.16, 1.0 - UV.x);    // and its walls (a wide fire touches them)
	float lum = max(c.r, max(c.g, c.b));
	// a touch toward hellfire: the dim edges go blood-red, the hearts stay molten
	vec3 hell = mix(crimson * 1.6, molten * 1.3, smoothstep(0.25, 0.8, lum)) * lum;
	c = mix(c, hell, tint * (1.0 - smoothstep(0.6, 1.0, lum)));
	c *= mix(vec3(1.0), vec3(0.42, 0.7, 1.0), cool);
	// and its faint haze is cut away, so dark gaps open between the tongues (crisp flames, not a glowing cloud)
	c *= mix(1.0, smoothstep(0.1, 0.32, lum), cool);
	ALBEDO = c * hot * fade * COLOR.a;
	ALPHA = clamp(lum * 0.12 * fade, 0.0, 1.0);
}
"""

const GLOW_SHADER := """
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;
uniform vec4 color : source_color = vec4(1.0, 0.42, 0.07, 1.0);
uniform float energy = 2.0;
uniform float power = 2.2;
uniform float rays = 0.0;
uniform float alpha = 1.0;
uniform float seed = 0.0;
void vertex() {
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
	MODELVIEW_MATRIX = MODELVIEW_MATRIX * mat4(vec4(length(MODEL_MATRIX[0].xyz), 0.0, 0.0, 0.0), vec4(0.0, length(MODEL_MATRIX[1].xyz), 0.0, 0.0), vec4(0.0, 0.0, length(MODEL_MATRIX[2].xyz), 0.0), vec4(0.0, 0.0, 0.0, 1.0));
}
void fragment() {
	vec2 c = (UV - 0.5) * 2.0;
	float d = length(c);
	float g = pow(clamp(1.0 - d, 0.0, 1.0), power);
	if (rays > 0.0) {
		float ang = atan(c.y, c.x) + seed;
		float st = pow(abs(sin(ang * 3.0)), 24.0) + 0.6 * pow(abs(sin(ang * 5.0 + 1.3)), 40.0);
		g += rays * st * pow(clamp(1.0 - d, 0.0, 1.0), 1.4);
	}
	ALBEDO = color.rgb * energy;
	ALPHA = clamp(g * alpha * color.a, 0.0, 1.0);
}
"""

## Smoke for particles: a soft, eroded puff (its own spin from the particle's angle), darker where the noise is
## thin, lit blood-red from below while it is young. COLOR.a (the colour ramp) fades it in and out.
const SMOKE_SHADER := """
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled;
uniform sampler2D noise_tex : repeat_enable, filter_linear_mipmap;
uniform vec3 smoke : source_color = vec3(0.05, 0.034, 0.038);
uniform vec3 glow_col : source_color = vec3(1.0, 0.14, 0.05);
uniform float glow_amt = 1.0;
uniform float density = 0.8;
varying float v_age;
varying float v_rot;
void vertex() {
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
	MODELVIEW_MATRIX = MODELVIEW_MATRIX * mat4(vec4(length(MODEL_MATRIX[0].xyz), 0.0, 0.0, 0.0), vec4(0.0, length(MODEL_MATRIX[1].xyz), 0.0, 0.0), vec4(0.0, 0.0, length(MODEL_MATRIX[2].xyz), 0.0), vec4(0.0, 0.0, 0.0, 1.0));
	v_age = INSTANCE_CUSTOM.y;
	v_rot = INSTANCE_CUSTOM.x;
}
void fragment() {
	vec2 c = UV - 0.5;
	float cs = cos(v_rot);
	float sn = sin(v_rot);
	vec2 r = vec2(cs * c.x - sn * c.y, sn * c.x + cs * c.y);
	float d = length(c) * 2.0;
	float n = texture(noise_tex, r * 0.75 + vec2(v_rot * 0.37, TIME * 0.03)).r;
	float n2 = texture(noise_tex, r * 1.9 + vec2(-v_rot * 0.21, TIME * 0.07)).r;
	float m = 1.0 - smoothstep(0.25, 1.0, d + (n - 0.5) * 1.0 + (n2 - 0.5) * 0.35 + v_age * 0.25);
	vec3 col = smoke * (0.55 + 0.9 * n);
	float under = clamp(UV.y, 0.0, 1.0);
	col += glow_col * glow_amt * pow(1.0 - v_age, 3.0) * under * 1.6 * (0.6 + 0.4 * n2);
	ALBEDO = col;
	ALPHA = clamp(m * density * COLOR.a, 0.0, 1.0);
}
"""

## The brand: rings, a band of runes, a counter-turning seven-pointed star and a slit eye in the middle; it draws
## itself (draw 0..1), flares white at the blow (flare), burns down (life 1..0). The ground under it is charred.
const SIGIL_SHADER := """
shader_type spatial;
render_mode unshaded, blend_premul_alpha, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;
uniform float draw = 0.0;
uniform float flare = 0.0;
uniform float life = 1.0;
uniform float spin = 0.0;
uniform float seed = 0.0;
uniform vec3 crimson : source_color = vec3(0.78, 0.035, 0.05);
uniform vec3 molten : source_color = vec3(1.0, 0.42, 0.07);
uniform vec3 whitehot : source_color = vec3(1.0, 0.86, 0.62);
float h11(float p) { return fract(sin(p * 127.1 + seed * 13.7) * 43758.5453); }
float seg(vec2 p, vec2 a, vec2 b) { vec2 pa = p - a; vec2 ba = b - a; float h = clamp(dot(pa, ba) / max(dot(ba, ba), 1e-5), 0.0, 1.0); return length(pa - ba * h); }
vec2 rot(vec2 p, float a) { float c = cos(a); float s = sin(a); return vec2(c * p.x - s * p.y, s * p.x + c * p.y); }
void fragment() {
	vec2 q = (UV - 0.5) * 2.0;
	float r = length(q);
	if (r > 1.02) { discard; }
	float big = 9.0;
	vec2 qo = rot(q, spin);
	float an = fract(atan(qo.y, qo.x) / 6.2831853 + 0.5);
	float d = big;
	if (an < clamp(draw * 1.3, 0.0, 1.0)) {
		d = min(d, abs(r - 0.94) - 0.016);
		d = min(d, abs(r - 0.865) - 0.006);
	}
	if (1.0 - an < clamp(draw * 1.6 - 0.25, 0.0, 1.0)) {
		d = min(d, abs(r - 0.615) - 0.009);
	}
	float N = 13.0;
	float cell = floor(an * N);
	float u = fract(an * N);
	float v = (r - 0.66) / 0.17;
	if (v > 0.0 && v < 1.0 && cell / N < draw * 1.4 - 0.2) {
		vec2 gp = vec2((u - 0.5) * (r * 6.2831853 / N) / 0.17, v - 0.5);
		float gd = big;
		for (int k = 0; k < 3; k++) {
			float hk = h11(cell * 7.0 + float(k) * 1.9);
			float hk2 = h11(cell * 3.1 + float(k) * 5.3 + 11.0);
			vec2 a = vec2(floor(hk * 3.0) - 1.0, floor(fract(hk * 7.0) * 3.0) - 1.0) * vec2(0.26, 0.34);
			vec2 b = vec2(floor(hk2 * 3.0) - 1.0, floor(fract(hk2 * 7.0) * 3.0) - 1.0) * vec2(0.26, 0.34);
			if (distance(a, b) < 0.1) { b = vec2(-a.x, 0.34 - a.y); }
			gd = min(gd, seg(gp, a, b));
		}
		if (h11(cell + 0.5) > 0.35) { gd = min(gd, seg(gp, vec2(0.0, -0.34), vec2(0.0, 0.34))); }
		d = min(d, gd * 0.17 - 0.008);
	}
	vec2 qi = rot(q, -spin * 1.6);
	float ri = length(qi);
	float ai = atan(qi.y, qi.x);
	// a ring of fangs pointing inward off the inner ring, growing in as it draws
	float fk = clamp(draw * 1.6 - 0.45, 0.0, 1.0);
	float NF = 11.0;
	float cf = fract(ai / 6.2831853 * NF + 0.5) - 0.5;
	float tl = 0.15 * fk;
	float tooth = (0.6 - ri) / max(tl, 1e-4);
	float fang = (tooth > 0.0 && tooth < 1.0) ? abs(cf) - 0.36 * (1.0 - tooth) : big;
	d = min(d, fang * ri * 6.2831853 / NF);
	// an inverted triangle, its strokes drawn one by one
	float ts = clamp(draw * 1.8 - 0.7, 0.0, 1.0) * 3.0;
	vec2 t0 = vec2(0.0, -0.46);
	vec2 t1 = vec2(0.4, 0.23);
	vec2 t2 = vec2(-0.4, 0.23);
	float td = big;
	if (ts > 0.0) { td = min(td, seg(qi, t1, mix(t1, t2, clamp(ts, 0.0, 1.0)))); }
	if (ts > 1.0) { td = min(td, seg(qi, t2, mix(t2, t0, clamp(ts - 1.0, 0.0, 1.0)))); }
	if (ts > 2.0) { td = min(td, seg(qi, t0, mix(t0, t1, clamp(ts - 2.0, 0.0, 1.0)))); }
	d = min(d, td - 0.008);
	// two horns curling up off the triangle's top corners
	float hk = smoothstep(0.6, 0.9, draw);
	if (hk > 0.0) {
		vec2 hp = vec2(abs(qi.x), qi.y);
		float hr = abs(length(hp - vec2(0.2, 0.23)) - 0.22);
		float hang = atan(hp.y - 0.23, hp.x - 0.2);
		float harc = (hang > 0.0 && hang < 2.6 * hk) ? hr - 0.009 * (1.0 - hang / 2.8) : big;
		d = min(d, harc);
	}
	float aa = max(fwidth(r) * 1.2, 0.002);
	float line = 1.0 - smoothstep(-aa, aa, d);
	float halo = exp(-max(d, 0.0) * 26.0);
	float flick = 0.8 + 0.2 * sin(TIME * 23.0 + r * 31.0 + seed) * sin(TIME * 7.0 + an * 40.0);
	vec3 hot = mix(crimson * 1.5, molten * 1.4, 0.25 + 0.35 * flick * smoothstep(0.3, 1.0, draw));
	hot = mix(hot, whitehot * 2.6, flare);
	float burn = smoothstep(0.0, 0.55, life);
	vec3 col = hot * line * burn + crimson * (0.5 + 0.8 * flare) * halo * 0.35 * burn;
	float ember = (1.0 - burn) * line * smoothstep(0.0, 0.2, life) * (0.5 + 0.5 * sin(TIME * 9.0 + r * 40.0 + an * 70.0));
	col += crimson * 1.6 * ember;
	float scorch = (1.0 - smoothstep(0.82, 1.0, r)) * 0.5 * smoothstep(0.0, 0.35, draw) * smoothstep(0.0, 0.25, life);
	ALBEDO = col;
	ALPHA = clamp(scorch + line * 0.75 * burn + halo * 0.12 * burn, 0.0, 1.0);
}
"""

## The rift: the ground torn open in a wedge. Cracks (cell edges stretched outward plus three main fissures) run
## out to `front`, glowing white-gold at the root and the running front, crimson in the deep; the ground round
## them is charred. heat falls first (the glow), then life (the char).
const RIFT_SHADER := """
shader_type spatial;
render_mode unshaded, blend_premul_alpha, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;
uniform sampler2D noise_tex : repeat_enable, filter_linear_mipmap;
uniform sampler2D cell_tex : repeat_enable, filter_linear_mipmap;
uniform float front = 0.0;
uniform float heat = 1.0;
uniform float life = 1.0;
uniform float seed = 0.0;
uniform float span = 1.0;
uniform vec3 crimson : source_color = vec3(0.78, 0.035, 0.05);
uniform vec3 molten : source_color = vec3(1.0, 0.42, 0.07);
uniform vec3 whitehot : source_color = vec3(1.0, 0.86, 0.62);
void fragment() {
	float a = UV.x * 2.0 - 1.0;
	float r = UV.y;
	float n = texture(noise_tex, vec2(a * 0.55, r * 1.1) * span + seed).r;
	float side = 1.0 - smoothstep(0.55, 1.0, abs(a) + (n - 0.5) * 0.55);
	float tip = 1.0 - smoothstep(0.72, 1.0, r + (n - 0.5) * 0.4);
	float base = smoothstep(0.0, 0.1, r);
	float mask = side * tip * base;
	if (mask < 0.003) { discard; }
	vec2 cuv = vec2(a * 0.9 * (0.35 + r), r * 0.75) * span + vec2(seed, seed * 0.7);
	float e = texture(cell_tex, cuv).r;
	float e2 = texture(cell_tex, cuv * 2.4 + 0.37).r;
	float w = mix(0.035, 0.018, r);
	float crack = 1.0 - smoothstep(0.0, w, e);
	float fine = (1.0 - smoothstep(0.0, w * 0.7, e2)) * 0.6;
	float wig = (texture(noise_tex, vec2(r * 1.7 + seed, a * 0.2)).r - 0.5) * 0.35;
	float dm = min(min(abs(a + 0.52 - wig), abs(a - wig * 0.8)), abs(a - 0.52 - wig)) * (0.35 + r);
	float wm = 0.12 * (1.0 - 0.45 * r);
	float main_ = 1.0 - smoothstep(wm * 0.15, wm, dm);
	float glowband = (1.0 - smoothstep(wm, wm * 4.0, dm)) * 0.35;
	float lip = 1.0 - smoothstep(wm, wm * 3.2, dm);
	float near = exp(-dm * 9.0);
	float rv = 1.0 - smoothstep(front - 0.07, front, r);
	float fr = exp(-abs(r - front) * 22.0) * step(r, front + 0.03) * step(0.0, front) * step(front, 1.05);
	float cells = max(crack, fine) * rv * mask;
	float mn = main_ * rv * mask;
	float hm = mn * heat;
	float hc = cells * heat * (0.02 + 0.25 * near);
	vec3 em = crimson * 1.1 * hm + molten * 1.1 * hm * hm + whitehot * 0.8 * pow(hm, 3.0) * (1.0 - r * 0.85);
	em += crimson * 0.9 * glowband * rv * mask * heat;
	em += crimson * 0.8 * hc + molten * 0.6 * hc * hc;
	em += molten * 1.4 * fr * heat * mask * max(main_, crack);
	float cool = (1.0 - heat) * max(mn, cells * near) * smoothstep(0.0, 0.35, life) * (0.55 + 0.45 * sin(TIME * 5.0 + r * 23.0 + a * 9.0));
	em += crimson * 1.1 * cool;
	float scorch = mask * rv * (0.4 + 0.35 * smoothstep(0.3, 0.7, n)) + lip * rv * mask * 0.35 + cells * 0.3;
	scorch *= smoothstep(0.0, 0.25, life);
	ALBEDO = em;
	ALPHA = clamp(scorch * 0.85 + hm * 0.4, 0.0, 1.0) * smoothstep(0.0, 0.12, life);
}
"""

## Obsidian: black glass, lit by the scene (the fists' light, the rift's sweep), crimson veins (cell edges) hotter
## toward the root, a blood-red rim. crack widens the veins and turns them white before a shard breaks. On particle
## fragments COLOR.r carries the heat.
const SHARD_SHADER := """
shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx, cull_back;
uniform sampler2D cell_tex : repeat_enable, filter_linear_mipmap;
uniform float heat = 1.0;
uniform float crack = 0.0;
uniform bool particle = false;
uniform vec3 crimson : source_color = vec3(0.78, 0.035, 0.05);
uniform vec3 molten : source_color = vec3(1.0, 0.42, 0.07);
uniform vec3 whitehot : source_color = vec3(1.0, 0.86, 0.62);
varying vec3 lp;
void vertex() {
	lp = VERTEX;
}
void fragment() {
	float e = texture(cell_tex, lp.xz * 1.3 + vec2(lp.y * 0.55, lp.y * 0.3)).r;
	float e2 = texture(cell_tex, lp.zx * 2.7 + vec2(lp.y * 1.1, 0.3)).r;
	float vein = 1.0 - smoothstep(0.0, 0.016 + crack * 0.045, e);
	vein = max(vein, (1.0 - smoothstep(0.0, 0.01 + crack * 0.03, e2)) * 0.45);
	float hg = clamp((lp.y + 0.35) / 1.35, 0.0, 1.0);
	float root = 1.0 - hg;
	float h = heat;
	if (particle) { h *= COLOR.r; }
	ALBEDO = vec3(0.012, 0.009, 0.011);
	ROUGHNESS = 0.22 + 0.3 * vein;
	METALLIC = 0.0;
	SPECULAR = 0.35;
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);
	vec3 em = crimson * 1.8 * vein * (0.25 + 0.75 * root) + molten * 2.4 * vein * root * root * root + whitehot * 3.0 * crack * vein;
	em += crimson * fres * 0.12 * (0.4 + 0.6 * root);
	EMISSION = em * h;
}
"""

## A standing crescent of fire washing out along the ground (UV.x along it, UV.y up).
const WAVE_SHADER := """
shader_type spatial;
render_mode unshaded, blend_premul_alpha, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;
uniform sampler2D noise_tex : repeat_enable, filter_linear_mipmap;
uniform float life = 1.0;
uniform float seed = 0.0;
uniform vec3 crimson : source_color = vec3(0.78, 0.035, 0.05);
uniform vec3 molten : source_color = vec3(1.0, 0.42, 0.07);
uniform vec3 whitehot : source_color = vec3(1.0, 0.86, 0.62);
void fragment() {
	vec2 uv = UV;
	float e = smoothstep(0.0, 0.16, uv.x) * smoothstep(1.0, 0.84, uv.x);
	float n = texture(noise_tex, vec2(uv.x * 2.6 + seed, uv.y * 0.9 - TIME * 3.2)).r;
	float n2 = texture(noise_tex, vec2(uv.x * 5.0 - seed, uv.y * 1.7 - TIME * 4.4)).r;
	float f = (1.05 - uv.y * (1.25 - 0.45 * life)) * e + (n * 0.65 + n2 * 0.35 - 0.5) * 0.95;
	f *= 0.55 + 0.45 * life;
	float shell = smoothstep(0.1, 0.32, f);
	float fire = smoothstep(0.32, 0.56, f);
	float core = smoothstep(0.56, 0.86, f);
	vec3 col = crimson * 2.4 * clamp(fire - core, 0.0, 1.0) + molten * 3.0 * core + whitehot * 3.0 * smoothstep(0.85, 1.05, f);
	col += crimson * 1.4 * clamp(shell - fire, 0.0, 1.0);
	float a = clamp(shell * 0.7 + fire * 0.4, 0.0, 1.0);
	ALBEDO = col * life;
	ALPHA = a * life;
}
"""

## Heat haze: bends what is behind it with scrolling noise (Forward+, High and Ultra).
const HAZE_SHADER := """
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;
uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform sampler2D noise_tex : repeat_enable, filter_linear_mipmap;
uniform float strength = 0.025;
uniform float life = 1.0;
uniform bool round_mask = false;
void vertex() {
	if (round_mask) {
		MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
		MODELVIEW_MATRIX = MODELVIEW_MATRIX * mat4(vec4(length(MODEL_MATRIX[0].xyz), 0.0, 0.0, 0.0), vec4(0.0, length(MODEL_MATRIX[1].xyz), 0.0, 0.0), vec4(0.0, 0.0, length(MODEL_MATRIX[2].xyz), 0.0), vec4(0.0, 0.0, 0.0, 1.0));
	}
}
void fragment() {
	vec2 s = UV * vec2(1.6, 1.0);
	vec2 n = vec2(texture(noise_tex, s + vec2(0.0, -TIME * 1.7)).r, texture(noise_tex, s + vec2(0.37, -TIME * 2.2)).r) - 0.5;
	float m;
	if (round_mask) {
		m = clamp(1.0 - length(UV - 0.5) * 2.0, 0.0, 1.0);
	} else {
		m = smoothstep(0.0, 0.18, UV.x) * smoothstep(1.0, 0.82, UV.x) * smoothstep(1.0, 0.25, UV.y) * smoothstep(0.0, 0.1, UV.y);
	}
	m *= life;
	ALBEDO = texture(screen_tex, SCREEN_UV + n * strength * m).rgb;
	ALPHA = smoothstep(0.0, 0.25, m);
}
"""
