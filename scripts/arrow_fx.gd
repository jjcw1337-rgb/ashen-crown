class_name ArrowFx
extends RefCounted
## The Archer's arrow effects, data-driven per arrow kind (PRESETS), so every bow skill gets the same treatment
## with its own identity (docs/archer_vfx_standard.md): a new skill is mostly a new preset.
## Everything here only DRAWS: it is called from ArcherFx (the "loose" event, the draw charge) and from
## Archer.update (the flight, each foe pierced, the end of the flight) on the caster's game and on his
## puppet's alike, so partners see the same arrow from the one "loose" event. Nothing here touches gameplay.
##
## The fire is SIMULATED, not painted: Mantaflow fire and smoke (tools/blender/fx/fire_sims.py) rendered into
## flipbooks (tools/fx_flipbook.py, assets/textures/fx/real_*.png). The flame sheets carry the sim's flame (R) and
## flame x temperature (G); FIRE_SHADER turns them into light through a blackbody curve (Kelvin), so the colour is
## the sim's own temperature: white-yellow where it is thick and hot, orange, then deep red where it thins. The
## smoke sheets carry an RGB lightmap (lit from the right / above / the left in Blender) and SMOKE_SHADER relights
## them in light() with the game's real lights: the sun, the fire's own OmniLights, shadows. Embers and sparks are
## points of blackbody light cooling as they fly (STREAK_SHADER, stretched along their velocity); the heat haze
## bends what is behind (HAZE_SHADER, Forward+); the burn mark is a Decal (soot albedo, a blistered normal map, ember
## cracks that cool); the flight's light casts shadows.
##
## A kind's preset:
##   "model"    the Meshy arrow (assets/models/arrows/<model>.glb, Archer._arrow_mesh)
##   "heat"     {head, char}: the arrowhead glowing with heat and the shaft charring behind it (HEAT_SHADER overlay)
##   "flame"    {amount, life, size, energy, t}: sim flames wrapped round the head and blown back along the shaft
##   "wisps"    {amount, life, size}: scraps of flame torn off and left behind in the air
##   "smoke"    {amount, life, size, col, alpha}: the smoke trail, lit by the scene
##   "embers"   {amount, life, size, t}: glowing embers drifting off on the turbulence
##   "sparks"   {amount, life, size, speed, t}: hot sparks shed in flight
##   "light"    {t, energy, range, shadow}: the moving light (Kelvin; at most LIGHT_CAP arrows lit at once)
##   "haze"     {amount, size, strength}: heat distortion behind the head (Forward+ only, never on Low / web)
##   "release" / "draw" / "pierce" / "end" / "burn": the moments, below
##   "surfaces" {grass, stone, dirt, wood, dark}: how the end of the flight meets the ground (ArrowFx.surface)
##   "sounds"   {cast, release, pierce, end}: [name, dB, pitch] layers, through SkillFx.snd / Sfx.play_at

const TEX := {"flame": "res://assets/textures/fx/real_flame.png", "burst_fire": "res://assets/textures/fx/real_burst_fire.png",
	"burst_smoke": "res://assets/textures/fx/real_burst_smoke.png", "smoke": "res://assets/textures/fx/real_smoke.png",
	"scorch": "res://assets/textures/fx/real_scorch.png", "scorch_n": "res://assets/textures/fx/real_scorch_n.png",
	"scorch_e": "res://assets/textures/fx/real_scorch_e.png"}
## where the source sits in each sim's frame (of the card's height from its middle), so a card's origin is the fire's
const PIVOT := {"flame": 0.40, "burst_fire": 0.29, "burst_smoke": 0.29, "smoke": 0.38}
const LIGHT_CAP := 3
const SUBSTEPS := 4
const BURST_START := 4.0
const BURN_LIGHT_CAP := 4

const PRESETS := {
	## Fire Arrow: a pitch-soaked arrow on fire. Real flames (the sim) wrapped round the head and blown back along
	## the shaft, the head glowing and the shaft charring, torn scraps of flame, a trail of lit smoke, embers on the
	## turbulence and sparks; its light moves over the ground and casts shadows. Through a foe: a gout of fire out of
	## his back and the burn on him; where the flight ends: a fireball, smoke rolling up, sparks bouncing, embers,
	## a scorch, and the ground answering (grass smoulders, stone throws sparks, dirt kicks up dust, wood catches).
	"fire": {
		"model": "fire",
		"heat": {"head": 1.0, "char": 1.0},
		"flame": {"amount": 12, "life": 0.4, "size": [0.4, 0.7], "energy": 4.0, "t": [1000.0, 2400.0]},
		"wisps": {"amount": 72, "life": 0.15, "size": [0.36, 0.56]},
		"smoke": {"amount": 120, "life": 1.7, "size": [0.35, 1.1], "col": Color(0.36, 0.34, 0.33), "alpha": 0.55},
		"embers": {"amount": 36, "life": [0.6, 1.6], "size": 0.018, "t": [1900.0, 850.0]},
		"sparks": {"amount": 18, "life": [0.15, 0.4], "size": 0.01, "speed": 3.0, "t": [2400.0, 1100.0]},
		"light": {"t": 2600.0, "energy": 3.0, "range": 7.5, "shadow": true},
		"haze": {"amount": 8, "size": 0.75, "strength": 0.022},
		"release": {"light": 1.2, "sparks": 12},
		"draw": {"amount": 8, "energy": 3.5},
		"pierce": {"light": 5.0, "sparks": 26, "embers": 18, "smoke": 4, "fireball": 1.5},
		"end": {"light": 7.0, "t": 2700.0, "fireball": 3.4, "sparks": 40, "embers": 40, "smoke": 8, "scorch": 2.6},
		"burn": {"amount": 22, "embers": 16, "smoke": 7, "light": 2.4},
		## how the end meets the ground: flames left burning (count, life), embers that settle, how sparks bounce,
		## dust, the smoke's colour, the scorch's size and how long its embers glow, a fire that keeps going
		"surfaces": {
			"grass": {"flames": 9, "flame_life": 2.6, "settle": true, "bounce": 0.15, "friction": 0.9, "smoke_col": Color(0.59, 0.57, 0.55), "smoke": 10, "scorch": 1.25, "glow": 4.0, "ring": true},
			"stone": {"flames": 0, "flame_life": 0.0, "settle": false, "bounce": 0.55, "friction": 0.15, "smoke_col": Color(0.24, 0.22, 0.22), "smoke": 6, "scorch": 0.85, "glow": 0.0, "spark_mul": 1.8, "chips": true},
			"dirt": {"flames": 3, "flame_life": 1.1, "settle": false, "bounce": 0.3, "friction": 0.6, "smoke_col": Color(0.34, 0.31, 0.28), "smoke": 7, "scorch": 1.0, "glow": 1.5, "dust": Color(0.36, 0.3, 0.23)},
			"wood": {"flames": 4, "flame_life": 1.6, "settle": true, "bounce": 0.25, "friction": 0.7, "smoke_col": Color(0.42, 0.39, 0.36), "smoke": 8, "scorch": 0.9, "glow": 6.0, "keep": 7.0},
			"dark": {"flames": 3, "flame_life": 1.2, "settle": false, "bounce": 0.3, "friction": 0.6, "smoke_col": Color(0.28, 0.27, 0.25), "smoke": 7, "scorch": 1.0, "glow": 2.0, "dust": Color(0.12, 0.11, 0.1)},
		},
		"sounds": {"cast": [["fuse", -13.0, 1.15]], "release": [["fireball", -4.0, 1.08], ["burn_item", -14.0, 1.25]],
			"pierce": [["impact_flesh", -4.0, 1.0], ["fire_erupt", -9.0, 1.45]], "end": [["boom", -7.0, 1.15], ["fire_erupt", -4.0, 0.9]]},
	},
	## the plain war arrow: no fire; sparks on the hit
	"war": {"model": "war", "sounds": {"pierce": [["impact_flesh", -6.0, 1.0]]}},
}

static var _shaders := {}
static var _tex := {}
static var _noise: Texture2D
static var _lights := 0
static var _burn_lights := 0

static func preset(kind: String) -> Dictionary:
	return PRESETS.get(kind, PRESETS["war"])

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
		"fire": s.code = FIRE_SHADER % [soft_u, BLACKBODY, soft_f]
		"smoke": s.code = SMOKE_SHADER % [soft_u, soft_f]
		"streak": s.code = STREAK_SHADER % BLACKBODY
		"haze": s.code = HAZE_SHADER
		"heat": s.code = HEAT_SHADER % [Mats.NOISE_LIB, BLACKBODY]
		"scorch": s.code = SCORCH_SHADER
	_shaders[key] = s
	return s

## The colour of a blackbody at k Kelvin (linear, red channel 1), as the shaders' blackbody().
static func blackbody(k: float) -> Color:
	var t := k / 100.0
	var g := clampf(0.39008158 * log(t) - 0.63184144, 0.0, 1.0)
	var b := 0.0 if k <= 1900.0 else clampf(0.54320679 * log(t - 10.0) - 1.19625409, 0.0, 1.0)
	return Color(1.0, pow(g, 2.2), pow(b, 2.2))

## Which ground a point is: a zone may answer itself (meta "surface_fn", the proof range), else the paving and
## earth masks, the grass, indoors.
static func surface(game, p: Vector3) -> String:
	var w = game.world
	if w == null:
		return "dirt"
	if w.has_meta("surface_fn"):
		return str((w.get_meta("surface_fn") as Callable).call(p))
	if game.has_method("indoor") and game.indoor():
		return "stone"
	if w.cobble_at(p.x, p.z) > 0.45 or (int(w.run) == 1 and str(w.kind) == "lair"):
		return "stone"
	if w.dirt_at(p.x, p.z) > 0.45:
		return "dirt"
	if w.oak_forest and w.grass_ground(p.x, p.z) > 0.35:
		return "grass"
	return "dirt"

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
	pm.color_ramp = _ramp([Color(1, 1, 1, 1), Color(1, 1, 1, 1), Color(1, 1, 1, 0)])
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
	pm.color_ramp = _ramp([Color(1, 1, 1, 0), Color(1, 1, 1, 1), Color(1, 1, 1, 0)])
	pm.scale_curve = _curve_tex([[0.0, 0.6], [1.0, 1.4]])
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
	lt.shadow_enabled = shadow
	lt.shadow_bias = 0.08
	lt.shadow_normal_bias = 1.5
	lt.light_size = 0.15
	lt.set_meta("base", energy)
	return lt

static func flicker(t: float, seed_v: float) -> float:
	return 0.82 + 0.1 * sin(t * 23.0 + seed_v) * sin(t * 7.3 + seed_v * 2.1) + 0.06 * sin(t * 41.0 + seed_v * 3.7) + 0.05 * sin(t * 13.1 + seed_v)

# ---------------------------------------------------------------- the projectile
## The burning arrow of this kind, ready to be placed and flown (`fly` every frame). Its state is in metas.
## The flames on the head ride the arrow (local); the trail (wisps, smoke, embers, sparks, haze) is emitted in the
## world from emitters that `fly` keeps on the head, so it stays behind in the air and dies off after the flight.
static func projectile(kind: String, game) -> Node3D:
	var p := preset(kind)
	var root: Node3D = Archer._arrow_mesh(str(p.get("model", "war")), p.has("flame"))
	root.set_meta("kind", kind)
	root.set_meta("age", 0.0)
	if not p.has("flame"):
		return root
	var lite := cheap(game)
	var div := 2 if lite else 1
	if p.has("heat"):
		var hm := ShaderMaterial.new()
		hm.shader = shader("heat")
		hm.set_shader_parameter("heat", float(p["heat"]["head"]))
		hm.set_shader_parameter("char_amt", float(p["heat"]["char"]))
		for mi in root.find_children("*", "MeshInstance3D", true, false):
			(mi as MeshInstance3D).material_overlay = hm
	# the flames wrapped round the head, blown back along the shaft
	var f: Dictionary = p["flame"]
	var sz: Array = f["size"]
	var tt: Array = f["t"]
	var fl := flip_particles("flame", int(f["amount"]), float(f["life"]), Vector2(sz[0], sz[1]), 1, float(f["energy"]), Vector2(tt[0], tt[1]))
	fl.local_coords = true
	fl.name = "Flames"
	var fpm := fl.process_material as ParticleProcessMaterial
	fpm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	fpm.emission_box_extents = Vector3(0.02, 0.02, 0.07)
	fpm.anim_speed_min = 0.35
	fpm.anim_speed_max = 0.55
	fpm.color_ramp = _ramp([Color(1, 1, 1, 0), Color(1, 1, 1, 1), Color(1, 1, 1, 0.8), Color(1, 1, 1, 0)])
	fpm.scale_curve = _curve_tex([[0.0, 0.55], [0.3, 1.0], [1.0, 0.75]])
	fl.position = Vector3(0, 0, -0.5)
	root.add_child(fl)
	var trail: Array = []
	var fx_root: Node3D = game.world.fx_root
	# torn scraps of flame left in the air, rising as they burn out
	if p.has("wisps"):
		var wd: Dictionary = p["wisps"]
		var ws: Array = wd["size"]
		# the flame's tail: torn tongues lying along the flight (axis 2: their velocity), dragged back off the head,
		# overlapping into one tapering tail that burns out within a couple of metres
		var wi := flip_particles("flame", int(wd["amount"]) / div, float(wd["life"]), Vector2(ws[0], ws[1]), 2, float(f["energy"]) * 0.75, Vector2(tt[0], tt[1] * 0.9))
		var wpm := wi.process_material as ParticleProcessMaterial
		wpm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
		wpm.emission_sphere_radius = 0.03
		wpm.particle_flag_align_y = true
		wpm.direction = Vector3(0, 0, 1)      # set to the flight's back in `fly`
		wpm.spread = 6.0
		wpm.initial_velocity_min = 0.0
		wpm.initial_velocity_max = 9.0
		wpm.gravity = Vector3(0, 1.5, 0)
		wpm.damping_min = 10.0
		wpm.damping_max = 14.0
		wpm.anim_speed_min = 0.06
		wpm.anim_speed_max = 0.12
		wpm.color_ramp = _ramp([Color(1, 1, 1, 0.8), Color(1, 1, 1, 0.45), Color(1, 1, 1, 0)])
		wpm.scale_curve = _curve_tex([[0.0, 1.0], [0.5, 0.6], [1.0, 0.2]])
		wi.name = "Wisps"
		trail.append(wi)
	if p.has("smoke"):
		var sd: Dictionary = p["smoke"]
		var ss: Array = sd["size"]
		var sm := flip_particles("smoke", int(sd["amount"]) / div, float(sd["life"]), Vector2(ss[0], ss[1]))
		var spm := sm.process_material as ParticleProcessMaterial
		spm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
		spm.emission_sphere_radius = 0.08
		spm.direction = Vector3.UP
		spm.spread = 60.0
		spm.initial_velocity_min = 0.1
		spm.initial_velocity_max = 0.5
		spm.gravity = Vector3(0, 0.45, 0)
		spm.damping_min = 0.5
		spm.damping_max = 1.0
		spm.angle_min = -180.0
		spm.angle_max = 180.0
		spm.angular_velocity_min = -25.0
		spm.angular_velocity_max = 25.0
		spm.anim_offset_max = 0.15
		spm.lifetime_randomness = 0.35
		spm.turbulence_enabled = true
		spm.turbulence_noise_strength = 0.6
		spm.turbulence_noise_scale = 2.0
		spm.turbulence_influence_min = 0.05
		spm.turbulence_influence_max = 0.15
		var sc: Color = sd["col"]
		spm.color_ramp = _ramp([Color(1, 1, 1, 0), Color(1, 1, 1, float(sd["alpha"])), Color(1, 1, 1, float(sd["alpha"]) * 0.6), Color(1, 1, 1, 0)])
		spm.scale_curve = _curve_tex([[0.0, 0.35], [0.35, 0.8], [1.0, 1.25]])
		var smm := sm.material_override as ShaderMaterial
		smm.set_shader_parameter("tint", sc)
		smm.set_shader_parameter("glow", 0.5)
		sm.name = "Smoke"
		trail.append(sm)
	if p.has("embers"):
		var ed: Dictionary = p["embers"]
		var el: Array = ed["life"]
		var et: Array = ed["t"]
		var em := streaks(int(ed["amount"]) / div, Vector2(el[0], el[1]), float(ed["size"]), 1.6, Vector2(et[0], et[1]), 1.0)
		var epm := em.process_material as ParticleProcessMaterial
		epm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
		epm.emission_sphere_radius = 0.12
		epm.direction = Vector3.UP
		epm.spread = 180.0
		epm.initial_velocity_min = 0.3
		epm.initial_velocity_max = 1.4
		epm.gravity = Vector3(0, 0.35, 0)
		epm.damping_min = 0.6
		epm.damping_max = 1.6
		epm.turbulence_enabled = true
		epm.turbulence_noise_strength = 2.5
		epm.turbulence_noise_scale = 1.4
		epm.turbulence_noise_speed_random = 0.4
		epm.turbulence_influence_min = 0.2
		epm.turbulence_influence_max = 0.5
		em.name = "Embers"
		trail.append(em)
	if p.has("sparks"):
		var kd: Dictionary = p["sparks"]
		var kl: Array = kd["life"]
		var kt: Array = kd["t"]
		var sp := streaks(int(kd["amount"]) / div, Vector2(kl[0], kl[1]), float(kd["size"]), 7.0, Vector2(kt[0], kt[1]), 1.6)
		var kpm := sp.process_material as ParticleProcessMaterial
		kpm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
		kpm.emission_sphere_radius = 0.05
		kpm.direction = Vector3.UP
		kpm.spread = 180.0
		kpm.initial_velocity_min = float(kd["speed"]) * 0.4
		kpm.initial_velocity_max = float(kd["speed"])
		kpm.gravity = Vector3(0, -6.0, 0)
		kpm.damping_min = 1.0
		kpm.damping_max = 2.0
		sp.name = "Sparks"
		trail.append(sp)
	if p.has("haze") and shimmer_ok() and not lite:
		var hd: Dictionary = p["haze"]
		var hz := haze(int(hd["amount"]), 0.45, float(hd["size"]), float(hd["strength"]))
		hz.name = "Haze"
		trail.append(hz)
	# the arrow covers ~1 m a frame: what it sheds in the air (the torn flame and the smoke) is split over SUBSTEPS
	# emitters that `fly` spreads along the stretch it crossed, so the trail is continuous, not beads a metre apart
	var spread: Array = []
	for e in trail:
		var pe := e as GPUParticles3D
		if str(pe.name) == "Smoke" or str(pe.name) == "Wisps":
			pe.amount = maxi(1, pe.amount / SUBSTEPS)
			for k in SUBSTEPS - 1:
				var c := pe.duplicate() as GPUParticles3D
				c.set_meta("sub", float(k + 1) / SUBSTEPS)
				spread.append(c)
			pe.set_meta("sub", 1.0)
	trail.append_array(spread)
	for e in trail:
		(e as GPUParticles3D).emitting = false    # `fly` starts them once they are on the head
		fx_root.add_child(e)
	root.set_meta("trail", trail)
	if p.has("light") and _lights < LIGHT_CAP:
		var l: Dictionary = p["light"]
		var lt := fire_light(float(l["t"]), float(l["energy"]), float(l["range"]), bool(l["shadow"]) and not lite)
		lt.position = Vector3(0, 0.12, -0.2)
		lt.name = "Light"
		root.add_child(lt)
		_lights += 1
		lt.tree_exited.connect(func(): _lights = maxi(0, _lights - 1))
	return root

## Every frame of the flight (Archer.update, both games): the trail's emitters follow the head (they emit in the
## world, so what they shed stays in the air behind it), the head heats and the shaft chars, the light flickers.
static func fly(_a: Dictionary, n: Node3D, delta: float, _game) -> void:
	var age: float = float(n.get_meta("age", 0.0)) + delta
	n.set_meta("age", age)
	if not n.has_meta("trail"):
		return
	var head: Vector3 = n.global_transform * Vector3(0, 0, -0.42)
	var prev: Vector3 = n.get_meta("prev_head", head)
	if not n.has_meta("prev_head"):
		# the tongues torn off are thrown back along the flight
		for e in n.get_meta("trail"):
			var pw := e as GPUParticles3D
			if is_instance_valid(pw) and str(pw.name).begins_with("Wisps"):
				(pw.process_material as ParticleProcessMaterial).direction = n.global_transform.basis.z
	n.set_meta("prev_head", head)
	for e in n.get_meta("trail"):
		var pe := e as GPUParticles3D
		if not is_instance_valid(pe):
			continue
		pe.global_position = prev.lerp(head, float(pe.get_meta("sub", 1.0)))
		if not pe.emitting:
			pe.emitting = true
	var t: float = Time.get_ticks_msec() / 1000.0
	var lt := n.get_node_or_null("Light") as OmniLight3D
	if lt != null:
		lt.light_energy = float(lt.get_meta("base")) * flicker(t, float(n.get_instance_id() % 97)) * smoothstep(0.0, 0.06, age)

## The flight is over: the trail stops shedding and is left to burn out and drift away where it lies.
static func end_flight(a: Dictionary) -> void:
	var n = a.get("node")
	if n == null or not is_instance_valid(n) or not (n as Node3D).has_meta("trail"):
		return
	for e in (n as Node3D).get_meta("trail"):
		var pe := e as GPUParticles3D
		if is_instance_valid(pe):
			pe.emitting = false
			Fx._free_later(pe, pe.lifetime + 0.3)
	(n as Node3D).remove_meta("trail")

# ---------------------------------------------------------------- the release
## The arrow leaving the bow: its flames whip round with the shot, a few sparks fly off the string, a breath of
## smoke, a pop of light on his hands.
static func release(h: Hero, kind: String, from: Vector3, dir: Vector3) -> void:
	var p := preset(kind)
	if not p.has("release"):
		return
	var r: Dictionary = p["release"]
	var root: Node3D = h.game.world.fx_root
	var lite := cheap(h.game)
	_pop_light(root, from, 2600.0, float(r["light"]), 0.25, 4.0, false)
	var sp := streaks(int(r["sparks"]) / (2 if lite else 1), Vector2(0.15, 0.4), 0.013, 6.0, Vector2(2300, 1100), 1.6)
	var pm := sp.process_material as ParticleProcessMaterial
	pm.direction = dir + Vector3(0, 0.3, 0)
	pm.spread = 35.0
	pm.initial_velocity_min = 2.0
	pm.initial_velocity_max = 5.0
	pm.gravity = Vector3(0, -7.0, 0)
	_one_shot(root, sp, from, 0.6)
	var sm := flip_particles("smoke", 2 if lite else 3, 1.2, Vector2(0.3, 0.55))
	var spm := sm.process_material as ParticleProcessMaterial
	spm.direction = -dir + Vector3(0, 0.6, 0)
	spm.spread = 30.0
	spm.initial_velocity_min = 0.3
	spm.initial_velocity_max = 0.8
	spm.gravity = Vector3(0, 0.4, 0)
	spm.angle_max = 360.0
	spm.color_ramp = _ramp([Color(1, 1, 1, 0), Color(1, 1, 1, 0.35), Color(1, 1, 1, 0)])
	spm.scale_curve = _curve_tex([[0.0, 0.5], [1.0, 1.3]])
	(sm.material_override as ShaderMaterial).set_shader_parameter("tint", Color(0.16, 0.15, 0.14))
	_one_shot(root, sm, from, 1.4)
	_sounds(h, p, "release")
	SkillFx.shake(h, 0.08)

# ---------------------------------------------------------------- the draw
## The nocked arrow burning in his hands while he draws (ArcherFx.update, every frame of the shot, on the puppet too):
## the pitch on the head catches and grows with the draw (`k` 0..1), the flames standing up from it, the light on
## his hands and face rising. Cleared at the release.
static func draw_charge(h: Hero, kind: String, k: float) -> void:
	var w: Node3D = h.weapon_node
	if w == null or not is_instance_valid(w) or not w.has_meta("nocked"):
		return
	var p := preset(kind)
	if not p.has("draw"):
		return
	var d: Dictionary = p["draw"]
	var arrow: Node3D = w.get_meta("nocked")
	var ch := arrow.get_node_or_null("Charge") as Node3D
	if ch == null:
		ch = Node3D.new()
		ch.name = "Charge"
		arrow.add_child(ch)
		# the nocked arrow's head (the bow's own arrow mesh: its head toward -z)
		ch.position = Vector3(0, 0, -0.36)
		var fl := flip_particles("flame", int(d["amount"]), 0.45, Vector2(0.16, 0.3), 0, float(d["energy"]), Vector2(1000, 2300))
		fl.local_coords = true      # it rides the arrow as he raises the bow (the cards still stand up the world)
		var pm := fl.process_material as ParticleProcessMaterial
		pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
		pm.emission_sphere_radius = 0.03
		pm.anim_speed_min = 0.4
		pm.anim_speed_max = 0.6
		pm.color_ramp = _ramp([Color(1, 1, 1, 0), Color(1, 1, 1, 1), Color(1, 1, 1, 0)])
		fl.name = "Flames"
		ch.add_child(fl)
		var em := streaks(6 if cheap(h.game) else 12, Vector2(0.5, 1.0), 0.02, 1.5, Vector2(1800, 900))
		var epm := em.process_material as ParticleProcessMaterial
		epm.direction = Vector3.UP
		epm.spread = 40.0
		epm.initial_velocity_min = 0.3
		epm.initial_velocity_max = 0.9
		epm.gravity = Vector3(0, 0.6, 0)
		epm.turbulence_enabled = true
		epm.turbulence_noise_strength = 2.0
		epm.turbulence_influence_min = 0.2
		epm.turbulence_influence_max = 0.4
		em.name = "Embers"
		ch.add_child(em)
		var lt := fire_light(2500.0, 0.7, 2.6, false)
		lt.position = Vector3(0, 0.15, -0.1)
		lt.name = "Light"
		ch.add_child(lt)
	var kk := clampf(k, 0.0, 1.0)
	var fl2 := ch.get_node("Flames") as GPUParticles3D
	fl2.amount_ratio = 0.35 + 0.65 * kk
	fl2.scale = Vector3.ONE    # (the particles scale themselves; the node stays unscaled)
	(fl2.material_override as ShaderMaterial).set_shader_parameter("alpha_mul", 0.4 + 0.6 * kk)
	(ch.get_node("Light") as OmniLight3D).light_energy = 0.7 * (0.35 + 0.65 * kk) * flicker(Time.get_ticks_msec() / 1000.0, 3.0)
	ch.visible = arrow.visible

static func end_draw(h: Hero) -> void:
	var w: Node3D = h.weapon_node
	if w == null or not is_instance_valid(w) or not w.has_meta("nocked"):
		return
	var ch := (w.get_meta("nocked") as Node3D).get_node_or_null("Charge")
	if ch != null:
		ch.queue_free()

# ---------------------------------------------------------------- a foe pierced
## The arrow goes through: sparks and a splash of burning pitch where it enters, a gout of fire out of his back
## along the arrow's line rolling up into smoke, embers, a pop of light on him and round him.
static func pierce(h: Hero, kind: String, e: Node3D, dir: Vector3) -> void:
	var p := preset(kind)
	var root: Node3D = h.game.world.fx_root
	var at: Vector3 = e.global_position + Vector3(0, 0.9 * float(e.get("height")), 0)
	if not p.has("pierce"):
		Fx.sparks(root, at, Color(0.9, 0.85, 0.7))
		_sounds(h, p, "pierce", at)
		return
	var pc: Dictionary = p["pierce"]
	var lite := cheap(h.game)
	var div := 2 if lite else 1
	var r: float = float(e.get("radius"))
	var entry := at - dir * (r + 0.05)
	var exit := at + dir * (r + 0.1)
	_pop_light(root, at, 2700.0, float(pc["light"]), 0.4, 6.0, false)
	# the gout out of his back: the sim's fireball, small, thrown along the line
	_fireball(root, exit + dir * 0.25, float(pc["fireball"]), 0.9, dir * 2.2, not lite, false)
	# sparks out of the entry, back along the line, and out of the exit, forward
	var sp := streaks(int(pc["sparks"]) / div, Vector2(0.2, 0.55), 0.011, 7.0, Vector2(2400, 1100), 1.8)
	var pm := sp.process_material as ParticleProcessMaterial
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = 0.08
	pm.direction = dir + Vector3(0, 0.25, 0)
	pm.spread = 28.0
	pm.initial_velocity_min = 3.0
	pm.initial_velocity_max = 9.0
	pm.gravity = Vector3(0, -9.0, 0)
	pm.damping_min = 0.5
	pm.damping_max = 1.5
	_one_shot(root, sp, exit, 0.8)
	var sp2 := streaks(int(pc["sparks"]) / (2 * div), Vector2(0.1, 0.3), 0.012, 5.0, Vector2(2200, 1100), 1.5)
	var pm2 := sp2.process_material as ParticleProcessMaterial
	pm2.direction = -dir + Vector3(0, 0.4, 0)
	pm2.spread = 50.0
	pm2.initial_velocity_min = 1.5
	pm2.initial_velocity_max = 4.0
	pm2.gravity = Vector3(0, -9.0, 0)
	_one_shot(root, sp2, entry, 0.5)
	var em := streaks(int(pc["embers"]) / div, Vector2(0.6, 1.4), 0.018, 1.6, Vector2(1900, 850))
	var epm := em.process_material as ParticleProcessMaterial
	epm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	epm.emission_sphere_radius = 0.2
	epm.direction = dir + Vector3(0, 0.6, 0)
	epm.spread = 50.0
	epm.initial_velocity_min = 1.0
	epm.initial_velocity_max = 3.5
	epm.gravity = Vector3(0, 0.3, 0)
	epm.damping_min = 1.5
	epm.damping_max = 3.0
	epm.turbulence_enabled = true
	epm.turbulence_noise_strength = 2.5
	epm.turbulence_influence_min = 0.2
	epm.turbulence_influence_max = 0.5
	_one_shot(root, em, exit, 1.6)
	_smoke_puffs(root, exit + Vector3(0, 0.2, 0), int(pc["smoke"]) / div, Color(0.3, 0.28, 0.27), 0.35, 2.0, Vector2(0.5, 1.0), dir * 0.6)
	_sounds(h, p, "pierce", at)
	SkillFx.hitstop(h, 0.03)

## A foe set alight: the sim's flames climbing his body, embers going up, smoke off the top, a little light that
## breathes with the fire (one per foe, at most BURN_LIGHT_CAP lit); when the burn runs out the flames sink, the
## smoke goes on a moment longer.
static func burn(game, e: Node3D, kind: String, dur: float) -> void:
	var p := preset(kind)
	if not p.has("burn") or not is_instance_valid(e):
		return
	var b: Dictionary = p["burn"]
	var old := e.get_node_or_null("fire_burn") as Node3D
	if old != null:
		old.set_meta("until", maxf(float(old.get_meta("until", 0.0)), Time.get_ticks_msec() / 1000.0 + dur))
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
	var fl := flip_particles("flame", int(b["amount"]) / div, 0.7, Vector2(0.75, 1.25), 0, 4.5, Vector2(950, 2250))
	(fl.material_override as ShaderMaterial).set_shader_parameter("soft", 0.06)   # flames hug the body
	var pm := fl.process_material as ParticleProcessMaterial
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(rad * 0.5, hgt * 0.6, rad * 0.5)
	pm.anim_speed_min = 0.3
	pm.anim_speed_max = 0.5
	pm.gravity = Vector3(0, 0.6, 0)
	pm.color_ramp = _ramp([Color(1, 1, 1, 0), Color(1, 1, 1, 1), Color(1, 1, 1, 0.7), Color(1, 1, 1, 0)])
	pm.scale_curve = _curve_tex([[0.0, 0.6], [0.3, 1.0], [1.0, 0.7]])
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
	spm.color_ramp = _ramp([Color(1, 1, 1, 0), Color(1, 1, 1, 0.45), Color(1, 1, 1, 0.25), Color(1, 1, 1, 0)])
	spm.scale_curve = _curve_tex([[0.0, 0.4], [1.0, 1.4]])
	(sm.material_override as ShaderMaterial).set_shader_parameter("tint", Color(0.2, 0.19, 0.18))
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
	root.set_meta("until", Time.get_ticks_msec() / 1000.0 + dur)
	# counts itself down (the enemy's burn_t is gameplay; this only has to end near the same time) and breathes the light
	var tm := Timer.new()
	tm.wait_time = 0.05
	tm.autostart = true
	root.add_child(tm)
	var seed_v := float(e.get_instance_id() % 89)
	tm.timeout.connect(func():
		if not is_instance_valid(root):
			return
		var now := Time.get_ticks_msec() / 1000.0
		var left: float = float(root.get_meta("until")) - now
		if lt != null and is_instance_valid(lt):
			lt.light_energy = float(b["light"]) * flicker(now, seed_v) * clampf(left / 0.6, 0.0, 1.0)
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

# ---------------------------------------------------------------- the end of the flight
## Where the flight ends (its range run out, or a wall): the pitch bursts into a fireball (the sim: fire swelling
## open and rolling up into smoke), its light flashing over the ground and the foes and dying down to the fire left
## burning; sparks and embers flung out and falling, smoke rising, and the ground answering in its own way.
static func finish(h: Hero, kind: String, pos: Vector3, dir: Vector3, wall: bool) -> void:
	var p := preset(kind)
	if not p.has("end"):
		return
	var en: Dictionary = p["end"]
	var root: Node3D = h.game.world.fx_root
	var gy: float = h.game.world.height_at(pos.x, pos.z)
	var g := Vector3(pos.x, gy, pos.z)
	var lite := cheap(h.game)
	var div := 2 if lite else 1
	var surf := surface(h.game, g)
	var sf: Dictionary = (p.get("surfaces", {}) as Dictionary).get(surf, {})
	# the arrow drives into the ground short of where it would have flown on: the fire bursts there, low
	var at := g + Vector3(0, 0.25, 0) - dir * 0.2
	# the light: a flash with shadows, dying down to the glow of what is left burning
	var keep: float = float(sf.get("flame_life", 1.0))
	var lt := fire_light(float(en["t"]), float(en["light"]), 11.0, not lite)
	root.add_child(lt)
	lt.global_position = at + Vector3(0, 0.9, 0)
	var seed_v := randf() * 50.0
	var start := Time.get_ticks_msec() / 1000.0
	var base: float = float(en["light"])
	var tl := lt.create_tween()
	tl.tween_method(func(v: float):
		var now := Time.get_ticks_msec() / 1000.0
		var age := now - start
		var flash := exp(-age * 5.0)
		var glow := 0.22 * clampf(1.0 - (age - 0.3) / maxf(keep + 0.6, 0.3), 0.0, 1.0)
		lt.light_energy = base * (flash + glow) * flicker(now, seed_v)
		lt.light_color = blackbody(lerpf(float(en["t"]) + 300.0, float(en["t"]) - 350.0, clampf(age / 1.2, 0.0, 1.0))), 0.0, 1.0, keep + 1.2)
	tl.tween_callback(lt.queue_free)
	_fireball(root, at, float(en["fireball"]), 1.6, Vector3(0, 0.8, 0), not lite, true)
	# sparks: flung out and up, falling, bouncing or skittering on the ground by what it is
	var spark_n: int = int(float(en["sparks"]) * float(sf.get("spark_mul", 1.0))) / div
	var sp := streaks(spark_n, Vector2(0.4, 1.3), 0.011, 6.0, Vector2(2400, 1000), 1.8)
	var pm := sp.process_material as ParticleProcessMaterial
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = 0.2
	pm.direction = Vector3(dir.x * 0.5, 1.0, dir.z * 0.5)
	pm.spread = 75.0
	pm.initial_velocity_min = 2.5
	pm.initial_velocity_max = 8.5
	pm.gravity = Vector3(0, -9.8, 0)
	pm.damping_min = 0.2
	pm.damping_max = 1.0
	_collide(pm, float(sf.get("bounce", 0.3)), float(sf.get("friction", 0.5)), 0.01)
	var sp_node := _one_shot(root, sp, at, 1.6)
	_ground_collider(sp_node, g)
	# embers: drifting up on the heat and floating down; on grass and wood they settle and glow on the ground
	var em := streaks(int(en["embers"]) / div, Vector2(1.0, 2.6 if sf.get("settle", false) else 1.8), 0.018, 1.4, Vector2(1900, 800))
	var epm := em.process_material as ParticleProcessMaterial
	epm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	epm.emission_sphere_radius = 0.4
	epm.direction = Vector3.UP
	epm.spread = 70.0
	epm.initial_velocity_min = 1.0
	epm.initial_velocity_max = 4.0
	epm.gravity = Vector3(0, -1.6 if sf.get("settle", false) else 0.2, 0)
	epm.damping_min = 1.0
	epm.damping_max = 2.5
	epm.turbulence_enabled = true
	epm.turbulence_noise_strength = 2.5
	epm.turbulence_noise_scale = 1.6
	epm.turbulence_influence_min = 0.15
	epm.turbulence_influence_max = 0.45
	if sf.get("settle", false):
		_collide(epm, 0.0, 1.0, 0.012)
	var em_node := _one_shot(root, em, at, 3.0)
	if sf.get("settle", false):
		_ground_collider(em_node, g)
	# smoke rolling up and drifting off, its colour from what burns
	_smoke_puffs(root, at + Vector3(0, 0.4, 0), int(sf.get("smoke", en["smoke"])) / div, sf.get("smoke_col", Color(0.13, 0.12, 0.11)), 0.55, 3.6, Vector2(0.9, 2.0), Vector3(0, 0.5, 0))
	# dust thrown up from dry ground, low and spreading
	if sf.has("dust"):
		var dust := flip_particles("smoke", 6 / div, 1.6, Vector2(0.8, 1.6))
		var dpm := dust.process_material as ParticleProcessMaterial
		dpm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_RING
		dpm.emission_ring_axis = Vector3.UP
		dpm.emission_ring_radius = 0.6
		dpm.emission_ring_inner_radius = 0.2
		dpm.emission_ring_height = 0.1
		dpm.direction = Vector3(0, 0.25, 0)
		dpm.spread = 180.0
		dpm.flatness = 0.8
		dpm.radial_velocity_min = 1.5
		dpm.radial_velocity_max = 3.5
		dpm.gravity = Vector3(0, -0.3, 0)
		dpm.damping_min = 2.0
		dpm.damping_max = 3.0
		dpm.angle_max = 360.0
		dpm.anim_offset_max = 0.2
		dpm.color_ramp = _ramp([Color(1, 1, 1, 0), Color(1, 1, 1, 0.55), Color(1, 1, 1, 0)])
		dpm.scale_curve = _curve_tex([[0.0, 0.5], [1.0, 1.4]])
		(dust.material_override as ShaderMaterial).set_shader_parameter("tint", sf["dust"])
		_one_shot(root, dust, g + Vector3(0, 0.15, 0), 2.0)
	if sf.get("chips", false) and not lite:
		Fx._slam_chunks(root, g)
	# flames left on the ground (grass smoulders in a ring, wood catches, dirt burns out at once, stone not at all)
	var nfl: int = int(sf.get("flames", 0)) / div
	if nfl > 0:
		var gf := flip_particles("flame", nfl, float(sf.get("flame_life", 1.0)), Vector2(0.45, 1.0), 0, 3.5, Vector2(950, 2200))
		var gpm := gf.process_material as ParticleProcessMaterial
		gpm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_RING if sf.get("ring", false) else ParticleProcessMaterial.EMISSION_SHAPE_BOX
		gpm.emission_ring_axis = Vector3.UP
		gpm.emission_ring_radius = 1.1
		gpm.emission_ring_inner_radius = 0.3
		gpm.emission_ring_height = 0.0
		gpm.emission_box_extents = Vector3(0.45, 0.0, 0.45)
		gpm.anim_speed_min = 0.25 * float(sf.get("flame_life", 1.0))
		gpm.anim_speed_max = 0.4 * float(sf.get("flame_life", 1.0))
		gpm.lifetime_randomness = 0.5
		gpm.color_ramp = _ramp([Color(1, 1, 1, 0), Color(1, 1, 1, 1), Color(1, 1, 1, 0.6), Color(1, 1, 1, 0)])
		gpm.scale_curve = _curve_tex([[0.0, 0.4], [0.2, 1.0], [1.0, 0.25]])
		gf.explosiveness = 0.85
		var gfn := _one_shot(root, gf, Vector3(g.x, g.y + 0.02, g.z), float(sf.get("flame_life", 1.0)) + 0.4)
		gfn.global_position = Vector3(g.x, g.y - 0.05, g.z)
	# wood catches: a small fire keeps going where the arrow struck, with its own light and smoke
	if float(sf.get("keep", 0.0)) > 0.0:
		_keep_burning(h.game, root, g + dir * 0.2, float(sf["keep"]), lite)
	# the burn mark: soot, a blistered normal, ember cracks cooling
	_scorch(h.game, root, g, dir, float(en["scorch"]) * float(sf.get("scorch", 1.0)), float(sf.get("glow", 1.0)))
	# the heat bending the air over it
	if shimmer_ok() and not lite:
		var hz := haze(5, 1.1, 1.6, 0.024)
		var hpm := hz.process_material as ParticleProcessMaterial
		hpm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
		hpm.emission_sphere_radius = 0.5
		hpm.gravity = Vector3(0, 1.4, 0)
		hz.explosiveness = 0.6
		_one_shot(root, hz, at + Vector3(0, 0.5, 0), 1.4)
	GrassField.impulse(g, 2.8 if surf == "grass" else 2.2, 0.9 if surf == "grass" else 0.6, 0.5)
	_sounds(h, p, "end", at)
	SkillFx.shake(h, 0.14 if wall else 0.1)

## The sim's fireball: the fire layer (additive, its own temperature) over the smoke layer (lit by the scene),
## played once over `life` seconds, `size` metres across, drifting by `drift` m/s; with `second`, a smaller
## mirrored one a beat later so the shape is never the same twice.
static func _fireball(root: Node3D, at: Vector3, size: float, life: float, drift: Vector3, smoke: bool, second: bool) -> void:
	if tex("burst_fire") == null:
		return
	smoke = smoke and tex("burst_smoke") != null
	for k in (2 if second else 1):
		var s := size * (1.0 if k == 0 else 0.62)
		var off := Vector3(randf_range(-0.25, 0.25), 0.1, randf_range(-0.25, 0.25)) * float(k) * size * 0.3
		var delay := 0.07 * k
		var flip := randf() < 0.5
		if smoke:
			var sq := _flip_card("burst_smoke", s, flip)
			var sm := sq.material_override as ShaderMaterial
			sm.set_shader_parameter("tint", Color(0.28, 0.27, 0.25))
			sm.set_shader_parameter("density", 0.95)
			sm.set_shader_parameter("glow", 1.0)
			root.add_child(sq)
			sq.global_position = at + off
			_play_card(sq, life * 1.5, delay, drift * 0.6)
		var fq := _flip_card("burst_fire", s, flip)
		var fm := fq.material_override as ShaderMaterial
		fm.set_shader_parameter("energy", 0.9)
		fm.render_priority = 1      # the fire over its own smoke
		fm.set_shader_parameter("t_lo", 950.0)
		fm.set_shader_parameter("t_hi", 2200.0)
		root.add_child(fq)
		fq.global_position = at + off
		_play_card(fq, life * 1.5, delay, drift * 0.6)

## One camera-facing card of a sim sequence (a MeshInstance3D, its frame set by `_play_card`).
static func _flip_card(key: String, size: float, flip: bool) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2.ONE
	mi.mesh = q
	mi.scale = Vector3.ONE * size
	var fire := key == "flame" or key == "burst_fire"
	var m := ShaderMaterial.new()
	m.shader = shader("fire" if fire else "smoke")
	m.set_shader_parameter("atlas", tex(key))
	m.set_shader_parameter("pivot", float(PIVOT.get(key, 0.0)))
	m.set_shader_parameter("loop_anim", 0.0)
	m.set_shader_parameter("flip", 1.0 if flip else 0.0)
	m.set_shader_parameter("frame", 0.0)
	if fire:
		m.set_shader_parameter("axis_mode", 0.0)
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.extra_cull_margin = 4.0
	return mi

static func _play_card(mi: MeshInstance3D, life: float, delay: float, drift: Vector3) -> void:
	var m := mi.material_override as ShaderMaterial
	mi.visible = delay <= 0.0
	var tw := mi.create_tween().set_parallel(true)
	if delay > 0.0:
		tw.tween_callback(func(): mi.visible = true).set_delay(delay)
	# the sim's first frames are the gout still round as it leaves the emitter: start once it has burst open
	tw.tween_method(func(v: float): m.set_shader_parameter("frame", v), BURST_START, 63.0, life).set_delay(delay)
	tw.tween_property(mi, "global_position", mi.global_position + drift * life, life).set_delay(delay).set_ease(Tween.EASE_OUT)
	tw.tween_method(func(v: float): m.set_shader_parameter("alpha_mul", v), 1.0, 0.0, life * 0.25).set_delay(delay + life * 0.75)
	Fx._free_later(mi, delay + life + 0.05)

## A few puffs of smoke (the sim's), lit by the scene, rising and spreading.
static func _smoke_puffs(root: Node3D, at: Vector3, n: int, col: Color, alpha: float, life: float, size: Vector2, push: Vector3) -> void:
	if n <= 0:
		return
	var sm := flip_particles("smoke", n, life, size)
	var pm := sm.process_material as ParticleProcessMaterial
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = 0.35
	pm.direction = (Vector3.UP + push).normalized()
	pm.spread = 35.0
	pm.initial_velocity_min = 0.5
	pm.initial_velocity_max = 1.4
	pm.gravity = Vector3(0, 0.35, 0)
	pm.damping_min = 0.4
	pm.damping_max = 0.9
	pm.angle_max = 360.0
	pm.angular_velocity_min = -18.0
	pm.angular_velocity_max = 18.0
	pm.lifetime_randomness = 0.3
	pm.anim_offset_max = 0.1
	pm.turbulence_enabled = true
	pm.turbulence_noise_strength = 0.8
	pm.turbulence_noise_scale = 2.5
	pm.turbulence_influence_min = 0.03
	pm.turbulence_influence_max = 0.1
	pm.color_ramp = _ramp([Color(1, 1, 1, 0), Color(1, 1, 1, alpha), Color(1, 1, 1, alpha * 0.55), Color(1, 1, 1, 0)])
	pm.scale_curve = _curve_tex([[0.0, 0.45], [0.4, 0.85], [1.0, 1.3]])
	sm.explosiveness = 0.75
	(sm.material_override as ShaderMaterial).set_shader_parameter("tint", col)
	(sm.material_override as ShaderMaterial).set_shader_parameter("glow", 0.7)
	_one_shot(root, sm, at, life + 0.3)

## Wood catches: a little fire burning on where it struck for `secs`, its light breathing, smoke going up.
static func _keep_burning(_game, root: Node3D, at: Vector3, secs: float, lite: bool) -> void:
	var n := Node3D.new()
	root.add_child(n)
	n.global_position = at
	var fl := flip_particles("flame", 4 if lite else 7, 0.9, Vector2(0.5, 0.95), 0, 3.5, Vector2(950, 2200))
	var pm := fl.process_material as ParticleProcessMaterial
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(0.18, 0.02, 0.12)
	pm.anim_speed_min = 0.3
	pm.anim_speed_max = 0.45
	pm.color_ramp = _ramp([Color(1, 1, 1, 0), Color(1, 1, 1, 1), Color(1, 1, 1, 0.7), Color(1, 1, 1, 0)])
	pm.scale_curve = _curve_tex([[0.0, 0.5], [0.25, 1.0], [1.0, 0.6]])
	n.add_child(fl)
	var sm := flip_particles("smoke", 3 if lite else 6, 2.4, Vector2(0.45, 1.0))
	var spm := sm.process_material as ParticleProcessMaterial
	spm.direction = Vector3.UP
	spm.spread = 12.0
	spm.initial_velocity_min = 0.5
	spm.initial_velocity_max = 0.9
	spm.gravity = Vector3(0.15, 0.25, 0)
	spm.angle_max = 360.0
	spm.color_ramp = _ramp([Color(1, 1, 1, 0), Color(1, 1, 1, 0.35), Color(1, 1, 1, 0.2), Color(1, 1, 1, 0)])
	spm.scale_curve = _curve_tex([[0.0, 0.4], [1.0, 1.5]])
	(sm.material_override as ShaderMaterial).set_shader_parameter("tint", Color(0.17, 0.16, 0.15))
	sm.position = Vector3(0, 0.45, 0)
	n.add_child(sm)
	var em := streaks(6 if lite else 10, Vector2(0.8, 1.8), 0.022, 1.4, Vector2(1800, 850))
	var epm := em.process_material as ParticleProcessMaterial
	epm.direction = Vector3.UP
	epm.spread = 25.0
	epm.initial_velocity_min = 0.6
	epm.initial_velocity_max = 1.6
	epm.gravity = Vector3(0, 0.5, 0)
	epm.turbulence_enabled = true
	epm.turbulence_noise_strength = 2.0
	epm.turbulence_influence_min = 0.15
	epm.turbulence_influence_max = 0.35
	em.position = Vector3(0, 0.2, 0)
	n.add_child(em)
	var lt := fire_light(2500.0, 1.4, 4.5, false)
	lt.position = Vector3(0, 0.45, 0)
	n.add_child(lt)
	var start := Time.get_ticks_msec() / 1000.0
	var tw := n.create_tween()
	tw.tween_method(func(v: float):
		var now := Time.get_ticks_msec() / 1000.0
		var left := secs - (now - start)
		var k := clampf(left / 1.5, 0.0, 1.0)
		lt.light_energy = 1.1 * flicker(now, 7.0) * k
		fl.amount_ratio = maxf(0.2, k), 0.0, 1.0, secs)
	tw.tween_callback(func():
		fl.emitting = false
		em.emitting = false
		sm.emitting = false)
	Fx._free_later(n, secs + 2.8)

## The burn mark: a Decal (Forward+ / Mobile) projected on whatever is there (ground, grass, planks): soot, a
## blistered char normal, and ember cracks (`glow` seconds to cool from orange to dark). Compatibility: a lit quad.
static func _scorch(_game, root: Node3D, g: Vector3, dir: Vector3, size: float, glow: float) -> void:
	var alb := tex("scorch")
	if alb == null:
		return
	var yaw := atan2(-dir.z, dir.x) + randf_range(-0.4, 0.4)
	if rd_ok():
		var d := Decal.new()
		d.size = Vector3(size * 1.25, 0.6, size)
		d.texture_albedo = alb
		d.texture_normal = tex("scorch_n")
		d.texture_emission = tex("scorch_e") if glow > 0.0 else null
		d.emission_energy = 0.0
		d.albedo_mix = 1.0
		d.normal_fade = 0.3
		d.upper_fade = 0.4
		d.lower_fade = 0.4
		d.cull_mask = 1
		root.add_child(d)
		d.global_position = g + Vector3(0, 0.1, 0)
		d.rotation.y = yaw
		var tw := d.create_tween().set_parallel(true)
		if glow > 0.0:
			# the cracks cool: bright at once, fading over `glow` seconds
			tw.tween_method(func(v: float): d.emission_energy = 5.0 * v * v, 1.0, 0.0, glow).set_ease(Tween.EASE_OUT)
		tw.tween_property(d, "albedo_mix", 0.0, 4.0).set_delay(maxf(glow, 1.5) + 4.0)
		Fx._free_later(d, maxf(glow, 1.5) + 8.2)
		return
	var mi := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(size * 1.25, size)
	q.orientation = PlaneMesh.FACE_Y
	mi.mesh = q
	var m := ShaderMaterial.new()
	m.shader = shader("scorch")
	m.set_shader_parameter("tex", alb)
	m.set_shader_parameter("ntex", tex("scorch_n"))
	m.set_shader_parameter("etex", tex("scorch_e"))
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mi)
	mi.global_position = Vector3(g.x, g.y + 0.04, g.z)
	mi.rotation.y = yaw
	var tw2 := mi.create_tween().set_parallel(true)
	tw2.tween_method(func(v: float): m.set_shader_parameter("glow", v), 1.0 if glow > 0.0 else 0.0, 0.0, maxf(glow, 0.1))
	tw2.tween_method(func(v: float): m.set_shader_parameter("alpha_mul", v), 1.0, 0.0, 4.0).set_delay(maxf(glow, 1.5) + 4.0)
	Fx._free_later(mi, maxf(glow, 1.5) + 8.2)

## kept for callers of the old API: a burn mark along dir
static func scorch(game, g: Vector3, dir: Vector3, length: float, _width: float) -> void:
	_scorch(game, game.world.fx_root, g, dir, length, 1.5)

# ---------------------------------------------------------------- sounds
## The preset's layers for a moment: flat on the caster, positional from the puppet or from a place.
static func _sounds(h: Hero, p: Dictionary, when: String, at := Vector3.INF) -> void:
	var snd: Dictionary = p.get("sounds", {})
	for s in snd.get(when, []):
		if at != Vector3.INF:
			Sfx.play_at(str(s[0]), at, float(s[1]), float(s[2]))
		else:
			SkillFx.snd(h, str(s[0]), float(s[1]), float(s[2]))

static func sounds(h: Hero, kind: String, when: String) -> void:
	_sounds(h, preset(kind), when)

# ---------------------------------------------------------------- pieces
## A one-shot burst of these particles at pos, freed after `secs`.
static func _one_shot(root: Node3D, p: GPUParticles3D, pos: Vector3, secs: float) -> GPUParticles3D:
	p.one_shot = true
	if p.explosiveness <= 0.0:
		p.explosiveness = 0.92
	root.add_child(p)
	p.global_position = pos
	p.emitting = true
	Fx._free_later(p, secs + p.lifetime)
	return p

static func _pop_light(root: Node3D, pos: Vector3, t: float, energy: float, dur: float, rng: float, shadow: bool) -> void:
	var lt := fire_light(t, energy, rng, shadow)
	root.add_child(lt)
	lt.global_position = pos + Vector3(0, 0.3, 0)
	var tw := lt.create_tween()
	tw.tween_property(lt, "light_energy", 0.0, dur).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_EXPO)
	tw.tween_callback(lt.queue_free)

## Particles that land: bounce and friction, a collision box under the ground (`_ground_collider`).
static func _collide(pm: ParticleProcessMaterial, bounce: float, friction: float, _radius: float) -> void:
	pm.collision_mode = ParticleProcessMaterial.COLLISION_RIGID
	pm.collision_bounce = bounce
	pm.collision_friction = friction
	pm.collision_use_scale = false
	pm.particle_flag_damping_as_friction = false

## The ground under a burst as a particle collider (its top at the ground's height), freed with the particles.
static func _ground_collider(p: GPUParticles3D, g: Vector3) -> void:
	p.collision_base_size = 0.01
	var c := GPUParticlesCollisionBox3D.new()
	c.size = Vector3(14, 2, 14)
	p.add_child(c)
	c.global_position = Vector3(g.x, g.y - 1.0 + 0.02, g.z)

static func _ramp(cols: Array) -> GradientTexture1D:
	var g := Gradient.new()
	g.set_color(0, cols[0])
	g.set_color(1, cols[cols.size() - 1])
	for i in range(1, cols.size() - 1):
		g.add_point(float(i) / (cols.size() - 1), cols[i])
	var gt := GradientTexture1D.new()
	gt.gradient = g
	return gt

static func _curve_tex(pts: Array) -> CurveTexture:
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
uniform float alpha_mul = 1.0;
uniform float soft = 0.25;
%s
%s
%s
varying float v_frame;
varying vec4 v_col;
varying float v_flip;
void vertex(){
	float s = length(MODEL_MATRIX[0].xyz);
	vec3 c = MODEL_MATRIX[3].xyz;
	vec3 up = axis_mode > 1.5 ? normalize(MODEL_MATRIX[1].xyz) : (axis_mode > 0.5 ? normalize(MODEL_MATRIX[2].xyz) : normalize(vec3(0.0, 1.0, 0.0) + lean));
	vec3 to_cam = normalize(INV_VIEW_MATRIX[3].xyz - c);
	vec3 side = cross(up, to_cam);
	float sl = length(side);
	float k = smoothstep(0.1, 0.4, sl);
	vec3 side_n = normalize(mix(INV_VIEW_MATRIX[0].xyz, sl > 0.0001 ? side / sl : INV_VIEW_MATRIX[0].xyz, k));
	vec3 up_n = normalize(mix(INV_VIEW_MATRIX[1].xyz, up, k));
	vec3 n = normalize(cross(side_n, up_n));
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(vec4(side_n * s, 0.0), vec4(up_n * s, 0.0), vec4(n * s, 0.0), vec4(c, 1.0));
	VERTEX.y += pivot;
	v_frame = INSTANCE_CUSTOM.z * grid * grid + frame;
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
	float lin = pow(r, 2.4);
	float tm = clamp(v.g / max(v.r, 0.004), 0.0, 1.0);
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
// the fire under young smoke lights it from inside and below (blackbody), fading as the puff ages
uniform vec4 glow_col : source_color = vec4(1.0, 0.36, 0.06, 1.0);
uniform float glow = 0.0;
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
	float sp = INSTANCE_CUSTOM.x;
	vec3 r = INV_VIEW_MATRIX[0].xyz;
	vec3 u = INV_VIEW_MATRIX[1].xyz;
	vec3 r2 = r * cos(sp) + u * sin(sp);
	vec3 u2 = -r * sin(sp) + u * cos(sp);
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(vec4(r2 * s, 0.0), vec4(u2 * s, 0.0), vec4(INV_VIEW_MATRIX[2].xyz * s, 0.0), vec4(c, 1.0));
	VERTEX.y += pivot;
	v_frame = INSTANCE_CUSTOM.z * grid * grid + frame;
	v_col = COLOR;
	v_spin = sp;
	v_age = clamp(max(INSTANCE_CUSTOM.y, frame / 24.0), 0.0, 1.0);
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
	ALBEDO = tint.rgb * v_col.rgb;
	// the sim's domain walls never show: the sheet fades out toward a circle inside the card
	float rm = 1.0 - smoothstep(0.3, 0.5, length(UV - vec2(0.5)));
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
		+ (0.12 + 0.3 * (1.0 - v_lm.g)) * max(-l2.y, 0.0);
	float avg = (v_lm.r + v_lm.g + v_lm.b) / 3.0;
	lit += avg * (max(LIGHT.z, 0.0) * 0.6 + max(-LIGHT.z, 0.0) * wrap);
	DIFFUSE_LIGHT += LIGHT_COLOR * ATTENUATION * lit / PI;
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
%s
varying float v_age;
varying float v_rand;
varying float v_a;
void vertex(){
	float s = length(MODEL_MATRIX[0].xyz);
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
	float lum = energy * 4.0 * pow(kel / 1500.0, 3.0);
	ALBEDO = blackbody(kel) * lum * (glow * 0.3 + core * 1.3);
	ALPHA = clamp(v_a * (glow * 0.6 + core), 0.0, 1.0);
}
"""

## Heat haze: the solid scene behind the card bent by two drifting layers of a normal-mapped noise, strongest in the
## middle, fading in and out with the particle (drawn before the other see-through things, render_priority -20).
const HAZE_SHADER := """
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;
uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform sampler2D noise_tex : hint_normal, filter_linear, repeat_enable;
uniform float strength = 0.02;
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
	vec2 n1 = texture(noise_tex, UV * 0.9 + vec2(v_seed, -TIME * 0.9)).xy * 2.0 - 1.0;
	vec2 n2 = texture(noise_tex, UV * 1.9 + vec2(-v_seed * 3.0, -TIME * 1.7)).xy * 2.0 - 1.0;
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
