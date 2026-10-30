extends Node3D
## Root of the game: environment, camera, zones, input, combat glue, saving.

## Each character is its own save, CHAR_DIR/<id>.json. SAVE_PATH is the single save from before characters;
## it is copied in once as the first character (and left in place for older builds).
const CHAR_DIR := "user://characters/"
const SAVE_PATH := "user://ashen_crown_save.json"
## Headless tools (godot -s tools/x.gd) save to their own file so they never touch a player's save.
const TEST_SAVE_PATH := "user://ashen_crown_test_save.json"
const CAM_OFFSET := Vector3(0, 17.0, 16.5)

var world: World
## The character being played (its save is CHAR_DIR + char_id + ".json") and its name.
var char_id := ""
var char_name := ""
## Where characters live (tools/char_test.gd points these at its own folder to test the real thing).
var char_dir := CHAR_DIR
var old_save := SAVE_PATH
var env: Environment
var world_env: WorldEnvironment
var sun: DirectionalLight3D
var cam_pivot: Node3D
var cam: Camera3D
var hero: Hero
var net: Net
var weather: Weather
var sky_mat: ProceduralSkyMaterial
var ui: UI
var vignette: ColorRect
var loading: ColorRect
var loading_lbl: Label
var quality := 2
var zoom := 1.0
var cam_target := Vector3.ZERO
## A short cinematic look at something (a boss's entrance and death, focus_on): the camera
## glides over and in, holds, and glides back. Play goes on meanwhile.
var focus_node: Node3D = null
var focus_t := 0.0
var focus_len := 0.0
var focus_zoom := 1.0
var shake := 0.0
var cur_act := 0
var cur_zone := "town"
var playing := false
var paused := false
var hovered = null
var ground_pt := Vector3.ZERO
var lmb_held := false
var lmb_repeat := 0.0
var rmb_held := false
const BIND_KEYCODES := {"Q": KEY_Q, "E": KEY_E, "R": KEY_R, "F": KEY_F, "G": KEY_G, "V": KEY_V}
var exit_grace := 0.0
var waypoints_known := ["town"]
var boss_killed := false
var difficulty := 0          # 0 = Act I, 1 = A2, 2 = A3: Act I again with tougher monsters and loot each time
var max_run := 0             # highest of those reached; any of them can be picked at the camp waypoint
## TESTING: unlock Act I, A2 and A3 at the camp waypoint from the start. Set to false to
## go back to unlocking them by beating each final boss.
const UNLOCK_ALL_ACTS := true
var run_progress := {}       # per run: its waypoints and whether its boss is dead
var tp_link := {}
var xp_bonus_t := 0.0
var shops := {}
var rng := RandomNumberGenerator.new()
var shot_path := ""
var shot_spawn := ""
var shot_zone := "town"
var shot_frames := 0
var death_t := -1.0
var _t := 0.0
var _busy := false

func _ready() -> void:
	rng.randomize()
	Mats.ensure_globals()
	var args := OS.get_cmdline_user_args()
	for i in args.size():
		if args[i] == "--shot" and i + 1 < args.size():
			shot_path = args[i + 1]
		if args[i] == "--spawn" and i + 1 < args.size():
			shot_spawn = args[i + 1]
		if args[i] == "--zone" and i + 1 < args.size():
			shot_zone = args[i + 1]
		if args[i] == "--run" and i + 1 < args.size():
			difficulty = int(args[i + 1])
	quality = _initial_quality()
	set_sound(bool(_load_setting("audio", "sound_on", true)))
	_setup_env()
	weather = Weather.new()
	weather.name = "Weather"
	add_child(weather)
	_setup_camera()
	_setup_post()
	ui = UI.new()
	add_child(ui)
	ui.setup(self)
	net = Net.new()
	add_child(net)
	net.setup(self)
	hero = Hero.new()
	hero.name = "Hero"
	add_child(hero)
	hero.setup(self)
	hero.new_character()
	hero.died.connect(_on_hero_died)
	hero.leveled.connect(_on_level)
	ui.bind_hero(hero)
	if shot_path != "":
		ui.hide_title()
		playing = true
		var ci := OS.get_cmdline_user_args().find("--class")
		if ci >= 0 and ci + 1 < OS.get_cmdline_user_args().size():
			hero.set_class(OS.get_cmdline_user_args()[ci + 1])
		await load_zone(0, shot_zone, shot_spawn if shot_spawn != "" else "start")
		return
	await _play_intro()
	await load_zone(0, "town", "start")
	ui.show_title()

# ---------------------------------------------------------------- intro
const INTRO_PATH := "res://assets/intro.ogv"
var _intro_playing := false
var _intro_skip := false

## The trailer plays full screen when the game opens; any key or click skips it.
## Left out of the browser build (too big a download for a test page) and headless runs.
func _play_intro() -> void:
	if OS.has_feature("web") or DisplayServer.get_name() == "headless" or not ResourceLoader.exists(INTRO_PATH):
		return
	var layer := CanvasLayer.new()
	layer.layer = 100
	add_child(layer)
	var bg := ColorRect.new()
	bg.color = Color.BLACK
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(bg)
	var box := AspectRatioContainer.new()
	box.ratio = 16.0 / 9.0
	box.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(box)
	var vp := VideoStreamPlayer.new()
	vp.stream = load(INTRO_PATH)
	vp.expand = true
	vp.volume = 1.0 if sound_on else 0.0
	box.add_child(vp)
	var hint := Label.new()
	hint.text = "Press any key to skip"
	hint.add_theme_font_size_override("font_size", 16)
	hint.add_theme_color_override("font_color", Color(0.85, 0.75, 0.6, 0.0))
	hint.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	hint.offset_left = -260
	hint.offset_top = -50
	hint.offset_right = -28
	hint.offset_bottom = -20
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	layer.add_child(hint)
	_intro_skip = false
	_intro_playing = true
	vp.play()
	var t := 0.0
	while vp.is_playing() and not _intro_skip:
		await get_tree().process_frame
		t += get_process_delta_time()
		hint.add_theme_color_override("font_color", Color(0.85, 0.75, 0.6, clampf((t - 1.5) * 0.8, 0.0, 0.55)))
	_intro_playing = false
	vp.stop()
	# a short fade from black into the title screen
	var tw := create_tween()
	tw.tween_property(bg, "color:a", 0.0, 0.6)
	box.queue_free()
	hint.queue_free()
	await tw.finished
	layer.queue_free()

# ---------------------------------------------------------------- the Underworld (Demon: Phase)
## While the Demon is phased, the act is seen from the Underworld: the same place and the same
## monsters, but drained to bone and violet, the ground veined with soul-light and crimson rune
## rings, souls rising everywhere. Unlike A3 nothing is burning: it is cold, dead and luminous.
var underworld := 0.0
var _under_target := 0.0
var _under_layer: CanvasLayer
var _under_rect: ColorRect
var _soul_field: GPUParticles3D
var _env_saved := {}

func set_underworld(on: bool) -> void:
	_under_target = 1.0 if on else 0.0

func _end_underworld_now() -> void:
	if hero and hero.phased:
		hero.phased = false
		hero.phase_t = 0.0
	if underworld > 0.0 or _under_target > 0.0:
		_under_target = 0.0
		underworld = 0.0
		_apply_underworld()
	if _soul_field and is_instance_valid(_soul_field):
		_soul_field.queue_free()
	_soul_field = null

func _update_underworld(delta: float) -> void:
	if underworld == _under_target and underworld == 0.0:
		return
	underworld = move_toward(underworld, _under_target, delta * 2.2)
	_apply_underworld()

func _apply_underworld() -> void:
	var u := underworld
	if _under_layer == null:
		_under_layer = CanvasLayer.new()
		_under_layer.layer = 0
		add_child(_under_layer)
		_under_rect = ColorRect.new()
		_under_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
		_under_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var sm := ShaderMaterial.new()
		var sh := Shader.new()
		sh.code = DemonFx.UNDERWORLD_SHADER
		sm.shader = sh
		_under_rect.material = sm
		_under_layer.add_child(_under_rect)
	_under_rect.visible = u > 0.001
	(_under_rect.material as ShaderMaterial).set_shader_parameter("amt", u)
	RenderingServer.global_shader_parameter_set("under_amt", u)
	if world != null:
		var lit := u > 0.3
		for e in world.enemies_root.get_children():
			if e is Enemy:
				e.set_soul_lit(lit)
	if u > 0.001 and _env_saved.is_empty():
		_env_saved = {"sat": env.adjustment_saturation, "con": env.adjustment_contrast, "fog": env.fog_light_color,
			"fogd": env.fog_density, "exp": env.tonemap_exposure, "amb": env.ambient_light_energy}
	if not _env_saved.is_empty():
		env.adjustment_saturation = lerpf(_env_saved["sat"], 0.7, u)
		env.adjustment_contrast = lerpf(_env_saved["con"], 1.18, u)
		env.fog_light_color = (_env_saved["fog"] as Color).lerp(Color(0.16, 0.05, 0.24), u)
		env.fog_density = lerpf(_env_saved["fogd"], _env_saved["fogd"] * 1.5 + 0.004, u)
		env.tonemap_exposure = lerpf(_env_saved["exp"], _env_saved["exp"] * 1.1, u)
		env.ambient_light_energy = lerpf(_env_saved["amb"], _env_saved["amb"] * 0.7, u)
		if u <= 0.0:
			_env_saved = {}
	if world != null:
		if u > 0.001 and (_soul_field == null or not is_instance_valid(_soul_field)):
			_soul_field = DemonFx.soul_field()
			world.fx_root.add_child(_soul_field)
		if _soul_field and is_instance_valid(_soul_field):
			_soul_field.emitting = u > 0.4
			_soul_field.global_position = hero.global_position

func _on_level(l: int) -> void:
	ui.big_message("Level %d" % l)
	ui.message("+5 stat points (press C)  ·  +1 talent point (press N)", Color(1, 0.85, 0.4))

# ---------------------------------------------------------------- environment
func _setup_env() -> void:
	world_env = WorldEnvironment.new()
	env = Environment.new()
	var sky := Sky.new()
	var sm := ProceduralSkyMaterial.new()
	sky_mat = sm
	sm.sky_top_color = Color(0.26, 0.3, 0.31)
	sm.sky_horizon_color = Color(0.44, 0.47, 0.44)
	sm.ground_bottom_color = Color(0.16, 0.18, 0.15)
	sm.ground_horizon_color = Color(0.44, 0.47, 0.44)
	sm.sun_angle_max = 30.0
	sky.sky_material = sm
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_white = 6.0
	env.fog_enabled = true
	env.glow_enabled = true
	env.glow_intensity = 0.7
	env.glow_bloom = 0.06
	env.glow_hdr_threshold = 1.1
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SOFTLIGHT
	env.adjustment_enabled = true
	world_env.environment = env
	add_child(world_env)
	sun = DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-52, -38, 0)
	sun.shadow_enabled = true
	sun.shadow_blur = 1.5
	sun.shadow_normal_bias = 1.6
	sun.shadow_bias = 0.06
	sun.directional_shadow_max_distance = 70.0
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	add_child(sun)
	apply_quality(quality)

## A3: set the camp and the moor ablaze, with smoke columns rising beyond the trees.
func _set_fires() -> void:
	var r := RandomNumberGenerator.new()
	r.seed = 99 + ["town", "wild", "lair"].find(cur_zone)
	var lit := 0
	for bp in world.burn_points:
		var pos: Vector3 = bp[0]
		var sz: float = bp[1]
		if cur_zone == "wild" and r.randf() < 0.35:
			continue
		var with_light := lit < (8 if quality >= 2 else 4)
		Props.fire(world.fx_root, pos, sz, Color(1.0, 0.45, 0.12), with_light, false, true)
		if with_light:
			lit += 1
		if r.randf() < 0.45:
			weather.make_smoke(world.fx_root, pos + Vector3(0, 1.0, 0), 0.6 + sz * 0.3)
	var b: Rect2 = world.bounds
	for i in 10:
		var t := float(i) / 10.0
		var edge := r.randi() % 4
		var p := Vector3.ZERO
		match edge:
			0: p = Vector3(lerpf(b.position.x, b.end.x, r.randf()), 0, b.position.y - r.randf_range(8, 22))
			1: p = Vector3(lerpf(b.position.x, b.end.x, r.randf()), 0, b.end.y + r.randf_range(8, 22))
			2: p = Vector3(b.position.x - r.randf_range(8, 22), 0, lerpf(b.position.y, b.end.y, r.randf()))
			_: p = Vector3(b.end.x + r.randf_range(8, 22), 0, lerpf(b.position.y, b.end.y, r.randf()))
		p.y = world.height_at(p.x, p.z)
		weather.make_smoke(world.fx_root, p, r.randf_range(1.6, 2.6))
		Props.fire(world.fx_root, p + Vector3(0, 0.6, 0), 2.2, Color(1.0, 0.42, 0.1), false, false, false)

## Snow over every outdoor area, falling snow, colder light. (A2 was winter until it became the Imperial
## Road and Aurelia, which are warm; nothing is snowy now, kept for a later act.)
func is_snowy() -> bool:
	return false

## The crypt (A3's lair) is underground; every other zone, Grubb's fort and Aurelia included, is under the sky.
func indoor() -> bool:
	return cur_zone == "lair" and not (world != null and (world.fort or world.run == 1))

func _zone_env(kind: String) -> void:
	var inside := kind == "lair" and not (world.fort or world.run == 1)
	var snowy := is_snowy() and not inside
	var ashen := difficulty >= 2 and not inside
	RenderingServer.global_shader_parameter_set("snow_amt", 1.0 if snowy else 0.0)
	RenderingServer.global_shader_parameter_set("ash_amt", 1.0 if ashen else 0.0)
	weather.set_snow(snowy, quality)
	weather.set_ash(ashen, quality)
	env.glow_intensity = 0.7
	env.glow_bloom = 0.06
	sky_mat.sky_top_color = Color(0.26, 0.3, 0.31)
	sky_mat.sky_horizon_color = Color(0.44, 0.47, 0.44)
	sky_mat.ground_horizon_color = Color(0.44, 0.47, 0.44)
	if inside:
		env.background_mode = Environment.BG_COLOR
		env.background_color = Color(0.0, 0.0, 0.0)
		# lit enough to read the room and the monsters at the edge of the screen: a cool
		# ambient fill under the warm torches, and a wider light around the hero
		env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		env.ambient_light_color = Color(0.44, 0.45, 0.52)
		env.ambient_light_energy = 0.95
		env.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
		env.tonemap_exposure = 1.45
		env.fog_light_color = Color(0.06, 0.06, 0.07)
		env.fog_density = 0.006
		env.fog_height_density = 0.0
		env.adjustment_saturation = 0.92
		env.adjustment_contrast = 1.04
		env.volumetric_fog_density = 0.018
		env.volumetric_fog_albedo = Color(0.5, 0.48, 0.45)
		env.volumetric_fog_emission = Color(0.0, 0.0, 0.0)
		sun.visible = false
		hero.light.light_energy = 2.6
		hero.light.omni_range = 17.0
	else:
		env.background_mode = Environment.BG_SKY
		env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
		env.ambient_light_energy = 0.55 if kind == "town" else 0.48
		env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
		env.tonemap_exposure = 1.05
		env.fog_light_color = Color(0.36, 0.4, 0.37)
		env.fog_density = 0.008 if kind == "town" else 0.011
		env.fog_sky_affect = 0.6
		env.fog_height = 1.5
		env.fog_height_density = 0.06 if kind == "town" else 0.09
		env.adjustment_saturation = 0.86
		env.adjustment_contrast = 1.06
		env.volumetric_fog_density = 0.018 if kind == "town" else 0.024
		env.volumetric_fog_albedo = Color(0.72, 0.78, 0.74)
		env.volumetric_fog_emission = Color(0.03, 0.035, 0.035)
		sun.visible = true
		sun.light_color = Color(0.86, 0.88, 0.9)
		sun.light_energy = 0.85 if kind == "town" else 0.75
		hero.light.light_energy = 0.9
		hero.light.omni_range = 10.0
		if kind == "town" and world.theme.get("forest_camp", false):
			# Act I's camp deep in the old forest: late dusk under the canopy. Cool blue-green light
			# and low mist between the trees, so the bonfire, the lanterns and the rune stones glow
			sky_mat.sky_top_color = Color(0.1, 0.13, 0.17)
			sky_mat.sky_horizon_color = Color(0.24, 0.29, 0.31)
			sky_mat.ground_horizon_color = Color(0.2, 0.24, 0.25)
			env.ambient_light_energy = 0.6
			env.tonemap_exposure = 1.15
			env.fog_light_color = Color(0.2, 0.26, 0.28)
			env.fog_density = 0.012
			env.fog_height = 1.2
			env.fog_height_density = 0.12
			env.adjustment_saturation = 0.9
			env.adjustment_contrast = 1.1
			env.volumetric_fog_density = 0.028
			env.volumetric_fog_albedo = Color(0.6, 0.7, 0.72)
			env.volumetric_fog_emission = Color(0.012, 0.02, 0.024)
			env.glow_intensity = 0.85
			env.glow_bloom = 0.08
			sun.light_color = Color(0.6, 0.72, 0.9)
			sun.light_energy = 0.62
			hero.light.light_energy = 1.0
		if difficulty == 1 and kind != "town":
			# A2, the Imperial Road and Aurelia: a warm late afternoon, low golden sun, dusty haze
			sky_mat.sky_top_color = Color(0.34, 0.42, 0.55)
			sky_mat.sky_horizon_color = Color(0.78, 0.62, 0.45)
			sky_mat.ground_horizon_color = Color(0.5, 0.4, 0.3)
			env.ambient_light_energy = 0.62
			env.tonemap_exposure = 1.12
			env.fog_light_color = Color(0.6, 0.5, 0.38)
			env.fog_density = 0.006
			env.fog_height_density = 0.04
			env.adjustment_saturation = 0.98
			env.adjustment_contrast = 1.08
			env.volumetric_fog_density = 0.012
			env.volumetric_fog_albedo = Color(0.9, 0.78, 0.62)
			env.volumetric_fog_emission = Color(0.04, 0.03, 0.02)
			sun.light_color = Color(1.0, 0.82, 0.6)
			sun.light_energy = 1.05
		if snowy:
			# overcast winter: pale sky, cold light, snow bouncing light back up
			sky_mat.sky_top_color = Color(0.5, 0.55, 0.62)
			sky_mat.sky_horizon_color = Color(0.72, 0.75, 0.8)
			sky_mat.ground_horizon_color = Color(0.72, 0.75, 0.8)
			env.ambient_light_energy = 0.5
			env.tonemap_exposure = 0.88
			env.fog_light_color = Color(0.62, 0.67, 0.76)
			env.fog_density = 0.0025
			env.fog_height_density = 0.0
			env.adjustment_saturation = 0.82
			env.adjustment_contrast = 1.12
			env.volumetric_fog_density = 0.004
			env.volumetric_fog_albedo = Color(0.85, 0.88, 0.95)
			env.volumetric_fog_emission = Color(0.0, 0.0, 0.0)
			sun.light_color = Color(0.8, 0.86, 1.0)
			sun.light_energy = 0.7
			hero.light.light_energy = 1.1
		if ashen:
			# everything burning: smoke-red sky, a dim orange sun, embers blooming in the dark
			sky_mat.sky_top_color = Color(0.16, 0.06, 0.04)
			sky_mat.sky_horizon_color = Color(0.62, 0.24, 0.09)
			sky_mat.ground_horizon_color = Color(0.4, 0.15, 0.06)
			env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
			env.ambient_light_color = Color(0.62, 0.55, 0.5)
			env.ambient_light_energy = 0.5
			env.tonemap_exposure = 1.08
			env.fog_light_color = Color(0.3, 0.2, 0.15)
			env.fog_density = 0.004
			env.fog_height_density = 0.02
			env.adjustment_saturation = 0.92
			env.adjustment_contrast = 1.12
			env.volumetric_fog_density = 0.012
			env.volumetric_fog_albedo = Color(0.6, 0.4, 0.3)
			env.volumetric_fog_emission = Color(0.05, 0.012, 0.0)
			env.glow_intensity = 1.0
			env.glow_bloom = 0.12
			sun.light_color = Color(1.0, 0.74, 0.55)
			sun.light_energy = 0.6
			hero.light.light_energy = 1.0
			_set_fires()

const SETTINGS_PATH := "user://settings.cfg"
const QUALITY_NAMES := ["Low", "Medium", "High", "Ultra"]

## Graphics presets. Integrated laptop GPUs are the usual trouble: volumetric fog and SSIL are
## kept to High and above, and the whole game also runs on the OpenGL renderer (Safe Mode).
func apply_quality(q: int) -> void:
	# Browsers (WebGL) can't allocate the High/Ultra shadow maps; the 3D view goes blank.
	quality = clampi(q, 0, max_quality())
	q = quality
	var forward := is_forward()
	env.ssao_enabled = q >= 1 and forward
	env.ssao_radius = 1.2
	env.ssao_intensity = 2.2
	env.ssil_enabled = q >= 2 and forward
	env.ssil_intensity = 0.8
	env.ssr_enabled = q >= 3 and forward
	env.volumetric_fog_enabled = q >= 2 and forward
	env.volumetric_fog_length = 70.0
	env.volumetric_fog_detail_spread = 2.0
	env.volumetric_fog_ambient_inject = 0.4
	sun.shadow_enabled = true
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS if q >= 2 else DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	RenderingServer.directional_shadow_atlas_set_size(4096 if q >= 2 else 2048, true)
	get_viewport().msaa_3d = Viewport.MSAA_8X if q >= 3 else (Viewport.MSAA_4X if q >= 2 else Viewport.MSAA_2X)
	get_viewport().screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED
	if OS.has_feature("web"):
		# no multisampling or FXAA in the browser's WebGL renderer
		get_viewport().msaa_3d = Viewport.MSAA_DISABLED
	# Ultra: real bounce light, finer shadows and effects, no simplifying of distant meshes
	var ultra := q >= 3 and forward
	env.sdfgi_enabled = ultra
	if ultra:
		env.sdfgi_use_occlusion = true
		env.sdfgi_cascades = 4
		env.sdfgi_min_cell_size = 0.2
		env.sdfgi_energy = 0.9
		env.sdfgi_bounce_feedback = 0.5
		env.ssr_max_steps = 96
	RenderingServer.directional_soft_shadow_filter_set_quality(RenderingServer.SHADOW_QUALITY_SOFT_ULTRA if q >= 3 else (RenderingServer.SHADOW_QUALITY_SOFT_HIGH if q >= 2 else RenderingServer.SHADOW_QUALITY_SOFT_LOW))
	RenderingServer.positional_soft_shadow_filter_set_quality(RenderingServer.SHADOW_QUALITY_SOFT_HIGH if q >= 3 else RenderingServer.SHADOW_QUALITY_SOFT_LOW)
	if q >= 3:
		RenderingServer.directional_shadow_atlas_set_size(8192, true)
	RenderingServer.environment_set_ssao_quality(RenderingServer.ENV_SSAO_QUALITY_ULTRA if q >= 3 else RenderingServer.ENV_SSAO_QUALITY_MEDIUM, true, 0.5, 2, 50.0, 300.0)
	RenderingServer.environment_set_ssil_quality(RenderingServer.ENV_SSIL_QUALITY_HIGH if q >= 3 else RenderingServer.ENV_SSIL_QUALITY_MEDIUM, true, 0.5, 4, 50.0, 300.0)
	RenderingServer.environment_set_volumetric_fog_volume_size(160 if q >= 3 else 96, 128 if q >= 3 else 64)
	get_viewport().mesh_lod_threshold = 0.0 if q >= 3 else 1.0
	if sun:
		sun.directional_shadow_max_distance = 90.0 if q >= 3 else 70.0
	for g in get_tree().get_nodes_in_group("grass"):
		(g as MultiMeshInstance3D).visibility_range_end = [32.0, 45.0, 60.0, 95.0][q]

func max_quality() -> int:
	return 1 if OS.has_feature("web") else 3

func is_forward() -> bool:
	return RenderingServer.get_rendering_device() != null

func set_quality(q: int) -> void:
	apply_quality(q)
	_save_setting("graphics", "quality", quality)

## Settings live together in one file, so load it before writing one value back.
func _save_setting(section: String, key: String, value: Variant) -> void:
	var cf := ConfigFile.new()
	cf.load(SETTINGS_PATH)
	cf.set_value(section, key, value)
	cf.save(SETTINGS_PATH)

func _load_setting(section: String, key: String, default: Variant) -> Variant:
	var cf := ConfigFile.new()
	if cf.load(SETTINGS_PATH) == OK:
		return cf.get_value(section, key, default)
	return default

# ---------------------------------------------------------------- sound
var sound_on := true

func set_sound(on: bool) -> void:
	sound_on = on
	Sfx.set_muted(not on)
	_save_setting("audio", "sound_on", on)

## Saved setting if there is one, otherwise High on a dedicated graphics card and Medium on
## integrated laptop graphics.
func _initial_quality() -> int:
	var cf := ConfigFile.new()
	if cf.load(SETTINGS_PATH) == OK and cf.has_section_key("graphics", "quality"):
		return int(cf.get_value("graphics", "quality"))
	if OS.has_feature("web"):
		return 1
	if not is_forward():
		return 2
	if RenderingServer.get_video_adapter_type() != RenderingDevice.DEVICE_TYPE_DISCRETE_GPU:
		return 1
	# recent gaming cards get Ultra straight away
	var gpu := RenderingServer.get_video_adapter_name().to_upper()
	for tag in ["RTX 30", "RTX 40", "RTX 50", "RX 68", "RX 69", "RX 7", "RX 9", "ARC B"]:
		if gpu.contains(tag):
			return 3
	return 2

func renderer_info() -> String:
	return "%s  ·  %s" % [RenderingServer.get_video_adapter_name(), "Vulkan" if is_forward() else "OpenGL (Safe Mode)"]

# ---------------------------------------------------------------- black-screen watchdog
## Some GPU drivers render the high-end effects as a black screen. For a few seconds after
## each outdoor zone loads, sample the middle of the screen; if it is almost all black,
## step the graphics setting down and remember it.
var _watch_t := -1.0
var _watch_next := 0.0
var _dark_hits := 0

func _start_watch() -> void:
	if not is_forward() or indoor() or DisplayServer.get_name() == "headless":
		_watch_t = -1.0
		return
	_watch_t = 0.0
	_watch_next = 1.5
	_dark_hits = 0

func _watchdog(delta: float) -> void:
	if _watch_t < 0.0 or _busy or paused or world == null:
		return
	_watch_t += delta
	if _watch_t < _watch_next:
		return
	_watch_next += 1.0
	if _watch_t > 12.0:
		_watch_t = -1.0
		return
	if _screen_dark_fraction() > 0.92:
		_dark_hits += 1
	else:
		_dark_hits = 0
	if _dark_hits < 3:
		return
	if quality > 0:
		set_quality(quality - 1)
		ui.big_message("Display problem detected")
		ui.message("Graphics lowered to %s for this computer" % QUALITY_NAMES[quality], Color(1, 0.85, 0.4))
		_start_watch()
	else:
		_watch_t = -1.0
		ui.big_message("Display problem detected")
		ui.message("Please start the game with \"Ashen Crown (Safe Mode)\"", Color(1, 0.6, 0.4))

func _screen_dark_fraction() -> float:
	var img := get_viewport().get_texture().get_image()
	if img == null or img.is_empty():
		return 0.0
	var w := img.get_width()
	var h := img.get_height()
	img = img.get_region(Rect2i(int(w * 0.3), int(h * 0.25), int(w * 0.4), int(h * 0.45)))
	img.resize(32, 32, Image.INTERPOLATE_NEAREST)
	var dark := 0
	for y in 32:
		for x in 32:
			if img.get_pixel(x, y).get_luminance() < 0.03:
				dark += 1
	return dark / 1024.0

func _setup_camera() -> void:
	cam_pivot = Node3D.new()
	add_child(cam_pivot)
	cam = Camera3D.new()
	cam.fov = 36.0
	cam.near = 0.5
	cam.far = 300.0
	cam_pivot.add_child(cam)
	cam.position = CAM_OFFSET
	cam.basis = Basis.looking_at(Vector3(0, 1.0, 0) - CAM_OFFSET, Vector3.UP)
	RenderingServer.global_shader_parameter_set("occlude_k", CAM_OFFSET.z / CAM_OFFSET.y)

func _setup_post() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 1
	add_child(layer)
	vignette = ColorRect.new()
	vignette.set_anchors_preset(Control.PRESET_FULL_RECT)
	vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sm := ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = """
shader_type canvas_item;
uniform float strength = 0.6;
void fragment(){
	vec2 uv = UV - 0.5;
	uv.x *= 1.3;
	float v = smoothstep(0.3, 0.85, length(uv));
	COLOR = vec4(0.0, 0.0, 0.0, v * strength);
}
"""
	sm.shader = sh
	vignette.material = sm
	layer.add_child(vignette)
	var layer2 := CanvasLayer.new()
	layer2.layer = 50
	add_child(layer2)
	loading = ColorRect.new()
	loading.set_anchors_preset(Control.PRESET_FULL_RECT)
	loading.color = Color(0, 0, 0, 1)
	loading.mouse_filter = Control.MOUSE_FILTER_STOP
	loading.visible = false
	layer2.add_child(loading)
	loading_lbl = Label.new()
	loading_lbl.set_anchors_preset(Control.PRESET_CENTER)
	loading_lbl.add_theme_font_size_override("font_size", 28)
	loading_lbl.add_theme_color_override("font_color", Color(0.86, 0.72, 0.44))
	loading_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	loading_lbl.offset_left = -400
	loading_lbl.offset_right = 400
	loading.add_child(loading_lbl)

# ---------------------------------------------------------------- zones
func zone_title(act: int, zone: String) -> String:
	var a: Dictionary = Data.act_info(act, difficulty)
	var tag: String = ["", "  ·  A2", "  ·  A3"][clampi(difficulty, 0, 2)]
	match zone:
		"town": return a["town"] + tag
		"wild": return a["wild"] + tag
		"lair": return ("Throne of the Ashen King" if difficulty >= 2 else a["lair"]) + tag
	return ""

## The current run's multipliers on Act I (Data.RUNS).
func run_mult(key: String, d: int = -1) -> float:
	return float(Data.RUNS[clampi(difficulty if d < 0 else d, 0, Data.RUNS.size() - 1)][key])

func xp_mult() -> float:
	return run_mult("xp")

func loot_mult() -> float:
	return run_mult("loot")

## How a run compares to Act I, in words, for banners and the victory panel.
func run_note(d: int) -> String:
	if d <= 0:
		return "Monsters and loot at their normal strength."
	var x := func(v: float) -> String: return ("%d" % int(round(v))) if v >= 10.0 else ("%.1f" % v).trim_suffix(".0")
	return "Monsters have %s times the life and %s times the damage of Act I. Every item they drop is %s times stronger." % [x.call(run_mult("life", d)), x.call(run_mult("dmg", d)), x.call(run_mult("loot", d))]

func run_name(d: int = -1) -> String:
	if d < 0:
		d = difficulty
	return ["Act I", "A2", "A3"][clampi(d, 0, 2)]

func run_banner() -> void:
	ui.big_message(run_name() + " begins")
	ui.message(("The Ashen King has risen. " if difficulty >= 2 else "") + run_note(difficulty), Color(1.0, 0.45, 0.2) if difficulty >= 2 else Color(1.0, 0.55, 0.3))

func boss_kind() -> String:
	return "ashen_king" if difficulty >= 2 else world.boss_spawn["kind"]

## After the final boss falls: everyone starts over at the camp one step harder, keeping their knight.
func start_a2() -> void:
	if net.is_client():
		net.request_a2()
		return
	_store_progress()
	difficulty = mini(difficulty + 1, 2)
	max_run = maxi(max_run, difficulty)
	boss_killed = false
	waypoints_known = ["town"]
	run_progress.erase(str(difficulty))
	tp_link = {}
	ui.victory_panel.visible = false
	ui.set_boss(null)
	if hero.dead:
		hero.respawn(hero.global_position)
	hero.life = hero.max_life
	hero.mana = hero.max_mana
	net.next_goto_new_run = true
	await load_zone(cur_act, "town", "start")
	run_banner()

func _store_progress() -> void:
	run_progress[str(difficulty)] = {"waypoints": waypoints_known.duplicate(), "boss": boss_killed}

func _restore_progress(d: int) -> void:
	var p: Dictionary = run_progress.get(str(d), {})
	waypoints_known = p.get("waypoints", ["town"]).duplicate()
	boss_killed = p.get("boss", false)

## Waypoint in camp: switch to Act I, A2 or A3 (any you have reached). Each keeps its own progress.
func switch_run(d: int) -> void:
	if net.is_client():
		net.request_switch(d)
		return
	if d == difficulty or d > max_run or d < 0 or _busy:
		return
	_store_progress()
	difficulty = d
	_restore_progress(d)
	tp_link = {}
	ui.set_boss(null)
	Sfx.play("portal")
	await load_zone(cur_act, "town", "start")
	run_switched_banner()

func run_switched_banner() -> void:
	ui.big_message(run_name())
	ui.message(("The Ashen King's reign. " if difficulty >= 2 else "") + run_note(difficulty), Color(1.0, 0.7, 0.4))

func load_zone(act: int, zone: String, spawn: String, at = null) -> void:
	if _busy:
		return
	_busy = true
	net.broadcast_goto(act, zone, spawn, at)
	loading_lbl.text = "Entering %s..." % zone_title(act, zone)
	loading.visible = true
	await get_tree().process_frame
	await get_tree().process_frame
	if world:
		world.queue_free()
		world = null
		hovered = null
		await get_tree().process_frame
	cur_act = act
	cur_zone = zone
	World.detail = quality
	world = World.new()
	world.name = "World"
	world.oak_forest = difficulty == 0     # Act I: the moor is an oak forest (A2/A3 keep their own look)
	world.fort = difficulty == 0           # Act I: the lair is Grubb's goblin fort, outdoors (A3 keeps the crypt)
	world.run = difficulty                 # A2 builds its own road and Aurelia
	add_child(world)
	world.build(act, zone, 4200 + act * 101 + ["town", "wild", "lair"].find(zone) * 7)
	_end_underworld_now()
	_zone_env(zone)
	apply_quality(quality)
	await _capture_map(zone)
	var sp: Vector3 = world.spawns.get(spawn, world.spawns["start"])
	if at != null:
		sp = at
	sp.y = world.height_at(sp.x, sp.z)
	hero.global_position = sp
	hero.target = null
	hero.path = PackedVector3Array()
	hero.moving = false
	cam_target = sp
	cam_pivot.position = sp
	exit_grace = 1.0
	for es in (world.enemy_spawns if not net.is_client() else []):
		if es.has("perch"):
			# a Feral on its tree: exactly where it was placed, clinging to the trunk
			var fe := spawn_enemy(es["kind"], es["pos"], int(es["level"]), false, "", int(es["pack"]))
			if fe:
				var tr := Vector3(float(es["perch"][0]), 0, float(es["perch"][1]))
				fe.perch_on(tr, fe.global_position - tr)
			continue
		for i in int(es["count"]):
			var p: Vector3 = world.free_spot_near(es["pos"], 3.0)
			var champ_name := ""
			if es["champ"]:
				champ_name = "%s%s the %s" % [Data.CHAMP_PREFIX[rng.randi() % Data.CHAMP_PREFIX.size()], Data.CHAMP_SUFFIX[rng.randi() % Data.CHAMP_SUFFIX.size()], Data.ENEMIES[es["kind"]]["name"]]
			spawn_enemy(es["kind"], p, int(es["level"]), es["champ"], champ_name, int(es["pack"]))
	if not world.boss_spawn.is_empty() and not net.is_client():
		spawn_enemy(boss_kind(), world.boss_spawn["pos"], world.level + 1, false, "", 999)
	if zone == "town":
		_stock_shops()
		if not tp_link.is_empty():
			_make_portal(world.spawns["portal"], "back")
	ui.set_zone(zone_title(act, zone))
	# Act I outdoors: birds over the forest (birds.gd)
	if world.oak_forest and not indoor():
		var birds := Birds.new()
		birds.game = self
		birds.name = "birds"
		world.add_child(birds)
	# Act I outside the camp (the forest moor, Grubb's fort): soft trees in the breeze instead of the wind
	Sfx.play_music("fort" if zone == "lair" and world.fort else zone, "forest" if world.oak_forest and zone != "town" and not indoor() else "")
	loading.visible = false
	_busy = false
	net.host_zone_loaded()
	_start_watch()
	if playing and shot_path == "":
		save_game()

## Photographs the freshly built zone from straight above for the minimap.
func _capture_map(zone: String) -> void:
	var b: Rect2 = world.bounds.grow(6.0)
	if DisplayServer.get_name() == "headless":
		ui.minimap.set_map(null, b, zone != "town")
		return
	var ppm := clampf(1600.0 / maxf(b.size.x, b.size.y), 3.0, 9.0)
	var vp := SubViewport.new()
	vp.size = Vector2i(int(b.size.x * ppm), int(b.size.y * ppm))
	vp.own_world_3d = false
	vp.world_3d = get_viewport().world_3d
	vp.msaa_3d = Viewport.MSAA_DISABLED if OS.has_feature("web") else Viewport.MSAA_4X
	vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	var mc := Camera3D.new()
	mc.projection = Camera3D.PROJECTION_ORTHOGONAL
	mc.keep_aspect = Camera3D.KEEP_HEIGHT
	mc.size = b.size.y
	mc.near = 1.0
	mc.far = 500.0
	mc.position = Vector3(b.get_center().x, 220.0, b.get_center().y)
	mc.basis = Basis(Vector3.RIGHT, -PI * 0.5)
	var me := Environment.new()
	me.background_mode = Environment.BG_COLOR
	me.background_color = Color(0.03, 0.03, 0.03)
	me.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	me.ambient_light_color = Color(0.62, 0.65, 0.6) if zone != "lair" else Color(0.55, 0.55, 0.6)
	me.ambient_light_energy = 0.75 if zone != "lair" else 1.1
	me.tonemap_mode = Environment.TONE_MAPPER_ACES
	me.tonemap_exposure = 1.1
	mc.environment = me
	vp.add_child(mc)
	var was_hero := hero.visible
	hero.visible = false
	var allies := net.puppets()
	for a in allies:
		a.visible = false
	RenderingServer.global_shader_parameter_set("player_pos", Vector3(0, -9999, 0))
	var grass := get_tree().get_nodes_in_group("grass")
	for gr in grass:
		(gr as GeometryInstance3D).visibility_range_end = 0.0
	var old_shadow := sun.directional_shadow_max_distance
	sun.directional_shadow_max_distance = 400.0
	add_child(vp)
	mc.current = true
	for i in 3:
		await get_tree().process_frame
	var img := vp.get_texture().get_image()
	vp.queue_free()
	sun.directional_shadow_max_distance = old_shadow
	hero.visible = was_hero
	for a in allies:
		if is_instance_valid(a):
			a.visible = a.net_has
	apply_quality(quality)
	var tex: Texture2D = null
	if img and not img.is_empty():
		img.generate_mipmaps()
		tex = ImageTexture.create_from_image(img)
	ui.minimap.set_map(tex, b, zone != "town")

func spawn_enemy(kind: String, p: Vector3, lvl: int, champ := false, champ_name := "", pack := 0, from_net := false) -> Enemy:
	if net.is_client() and not from_net:
		return null
	var e := Enemy.new()
	world.enemies_root.add_child(e)
	e.global_position = Vector3(p.x, world.height_at(p.x, p.z), p.z)
	e.pack_id = pack
	e.setup(self, kind, maxi(1, lvl), champ, champ_name)
	e.home = e.global_position
	if net.active and net.is_host:
		net.on_spawn(e)
	return e

## Via's bandit ambush (World.ambushes): when any hero comes near, the bandits spring from behind the
## rocks onto the road (Enemy.leap_from), bowmen stay on the crests. Host only; the spawns replicate.
func _check_ambushes() -> void:
	if net.is_client() or world == null or world.ambushes.is_empty():
		return
	for am in world.ambushes:
		if am["done"]:
			continue
		for h in all_heroes():
			if is_instance_valid(h) and not h.dead and h.global_position.distance_to(am["pos"]) < float(am["radius"]):
				am["done"] = true
				_spring_ambush(am)
				break

func _spring_ambush(am: Dictionary) -> void:
	ui.big_message("Ambush!")
	Sfx.play("battle_cry", -6.0, 0.8)
	add_shake(0.2)
	var land: Vector3 = am["land"]
	for es in am["spawns"]:
		for i in int(es["count"]):
			var from: Vector3 = es["pos"] + Vector3(rng.randf_range(-1.6, 1.6), 0, rng.randf_range(-1.6, 1.6))
			var e := spawn_enemy(es["kind"], from, int(es["level"]), es["champ"], ("%s, %s" % [Data.ENEMIES[es["kind"]]["name"], es["name"]]) if es.has("name") else "", int(es["pack"]))
			if e == null:
				continue
			if str(es["kind"]).ends_with("archer"):
				e.aggro = true
			else:
				var to := land.lerp(from, 0.25) + Vector3(rng.randf_range(-2.5, 2.5), 0, rng.randf_range(-2.5, 2.5))
				e.leap_from(e.global_position, to)

## Every knight in the area: yours plus your partners'.
func all_heroes() -> Array:
	var out := [hero]
	if net.active:
		out.append_array(net.puppets())
	return out

## Monsters go after the nearest knight that is still standing.
func target_for(e: Node3D) -> Hero:
	if not net.active:
		return hero
	var best: Hero = hero
	var bd := INF
	for h in all_heroes():
		if h.dead or (h.puppet and not h.net_has):
			continue
		var d: float = h.global_position.distance_squared_to(e.global_position)
		if d < bd:
			bd = d
			best = h
	return best

func enemies_near(p: Vector3, r: float) -> Array:
	var out := []
	if world == null:
		return out
	var r2 := r * r
	for e in world.enemies_root.get_children():
		if e is Enemy and not e.dead:
			var d: Vector3 = e.global_position - p
			if d.x * d.x + d.z * d.z <= r2:
				out.append(e)
	return out

# ---------------------------------------------------------------- start / save
## cont: play the character `id` (the last one played when empty); otherwise a new `cls` called `nm`.
func start_game(cont: bool, cls := "knight", id := "", nm := "") -> void:
	Sfx.play("click")
	ui.hide_title()
	playing = true
	if cont:
		var chars := list_characters()
		char_id = id if id != "" else (str(chars[0]["id"]) if not chars.is_empty() else "")
	else:
		char_id = new_char_id()
		char_name = nm.strip_edges().substr(0, 18) if nm.strip_edges() != "" else default_name(cls)
	if cont and load_game():
		await load_zone(cur_act, "town", "start")
	else:
		if cont:
			# nothing to continue: a new knight
			char_id = new_char_id()
			char_name = default_name(cls)
		net.my_name = char_name
		hero.set_class(cls)
		hero.new_character()
		difficulty = 0
		max_run = 0
		run_progress = {}
		waypoints_known = ["town"]
		boss_killed = false
		tp_link = {}
		if UNLOCK_ALL_ACTS:
			max_run = 2
		await load_zone(0, "town", "start")
		ui.open_dialog(Data.VENDORS[0]["elder"], "Welcome to the Forsaken Wilds, %s. Since the goblin king Grubb tunnelled into the old crypt to loot the dead, the dead walk Cairnfell Moor and the Fallen raid our roads. He sits on a mountain of stolen gold down there and calls himself king. Trade with our folk, then head out through the north gate. End him, and the moor may yet heal." % ("restless one" if hero.is_wraith() else ("pact-bound one" if hero.is_warlock() else "crusader")), [["I will", func(): pass]])
	ui.refresh()

## Co-op from the title screen. Your last character is used if you have one.
func start_host() -> void:
	await start_game(not list_characters().is_empty())
	var err := net.host()
	if err != OK:
		ui.big_message("Could not host")
		ui.message("Another program may be using port %d" % Net.PORT, Color(1, 0.5, 0.4))
	else:
		ui.message("Hosting! Your partner can now pick Join Co-op Game", Color(0.5, 1.0, 0.5))

func start_join(ip: String) -> void:
	Sfx.play("click")
	net.stop_listening()
	ui.hide_title()
	playing = true
	var chars := list_characters()
	char_id = str(chars[0]["id"]) if not chars.is_empty() else new_char_id()
	if not load_game():
		char_name = default_name(hero.cls)
		hero.new_character()
	loading_lbl.text = "Joining game at %s..." % ip
	loading.visible = true
	if net.join(ip) != OK:
		on_net_failed("Could not connect to that game.")
		return
	await get_tree().create_timer(8.0).timeout
	if net.is_client() and net.players.is_empty() and loading.visible and not _busy:
		net.shutdown()
		on_net_failed("No answer from %s. Check the host's game is running and Windows Firewall allowed it." % ip)

func on_net_failed(msg: String) -> void:
	ui.big_message("Co-op ended")
	ui.message(msg, Color(1, 0.6, 0.4))
	loading.visible = false
	if playing:
		await load_zone(cur_act, "town", "start")
		if hero.dead:
			hero.respawn(hero.global_position)

## Testing switches (F8 panel, only while UNLOCK_ALL_ACTS is on). They change nothing else
## and are never saved.
var test_immortal := false
var test_onehit := false
var test_stamina := false   # infinite stamina: sprint forever
var test_allskills := false # every skill usable regardless of level
var test_fast := false      # super speed: the hero moves TEST_FAST times as fast
const TEST_FAST := 4.0

## Headless tools save to TEST_SAVE_PATH, unless they moved the character folder.
func _testing() -> bool:
	return get_tree().get_script() != null and char_dir == CHAR_DIR

func save_path() -> String:
	return TEST_SAVE_PATH if _testing() else char_dir + char_id + ".json"

func save_game() -> void:
	if char_id == "" and not _testing():
		return
	_store_progress()
	var d := {"hero": hero.to_save(), "act": cur_act, "waypoints": waypoints_known, "boss": boss_killed, "difficulty": difficulty,
		"max_run": max_run, "runs": run_progress, "name": char_name, "played": int(Time.get_unix_time_from_system() * 1000.0)}
	DirAccess.make_dir_recursive_absolute(char_dir)
	var f := FileAccess.open(save_path(), FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(d))

func load_game() -> bool:
	if not FileAccess.file_exists(save_path()):
		return false
	var f := FileAccess.open(save_path(), FileAccess.READ)
	if f == null:
		return false
	var d = JSON.parse_string(f.get_as_text())
	if typeof(d) != TYPE_DICTIONARY:
		return false
	hero.from_save(d.get("hero", {}))
	char_name = str(d.get("name", default_name(hero.cls)))
	if char_name != "":
		net.my_name = char_name
	cur_act = int(d.get("act", 0))
	waypoints_known = d.get("waypoints", ["town"])
	boss_killed = d.get("boss", false)
	difficulty = int(d.get("difficulty", 0))
	max_run = maxi(int(d.get("max_run", 0)), difficulty)
	if UNLOCK_ALL_ACTS:
		max_run = 2
	run_progress = d.get("runs", {})
	return true

## Every saved character, the last played first: [{id, name, cls, level, difficulty, act, played}].
func list_characters() -> Array:
	if not _testing():
		_adopt_old_save()
	var out := []
	var dir := DirAccess.open(char_dir)
	if dir == null:
		return out
	for fn in dir.get_files():
		if not fn.ends_with(".json"):
			continue
		var f := FileAccess.open(char_dir + fn, FileAccess.READ)
		if f == null:
			continue
		var d = JSON.parse_string(f.get_as_text())
		if typeof(d) != TYPE_DICTIONARY:
			continue
		var h: Dictionary = d.get("hero", {})
		out.append({"id": fn.get_basename(), "name": str(d.get("name", "")), "cls": str(h.get("cls", "knight")),
			"level": int(h.get("level", 1)), "difficulty": int(d.get("difficulty", 0)), "act": int(d.get("act", 0)),
			"played": int(d.get("played", 0))})
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a["played"]) > int(b["played"]))
	return out

## The save from before characters becomes the first character (once; the old file stays for older builds).
func _adopt_old_save() -> void:
	if FileAccess.file_exists(char_dir + ".adopted") or not FileAccess.file_exists(old_save):
		return
	DirAccess.make_dir_recursive_absolute(char_dir)
	var src := FileAccess.open(old_save, FileAccess.READ)
	var d = JSON.parse_string(src.get_as_text()) if src else null
	if typeof(d) == TYPE_DICTIONARY:
		var h: Dictionary = d.get("hero", {})
		d["name"] = default_name(str(h.get("cls", "knight")))
		d["played"] = int(FileAccess.get_modified_time(old_save)) * 1000
		var f := FileAccess.open(char_dir + new_char_id() + ".json", FileAccess.WRITE)
		if f:
			f.store_string(JSON.stringify(d))
	var mark := FileAccess.open(char_dir + ".adopted", FileAccess.WRITE)
	if mark:
		mark.store_string("1")

func delete_character(id: String) -> void:
	if id != "" and FileAccess.file_exists(char_dir + id + ".json"):
		DirAccess.remove_absolute(char_dir + id + ".json")

func new_char_id() -> String:
	return "%d_%04d" % [int(Time.get_unix_time_from_system()), randi() % 10000]

func default_name(cls: String) -> String:
	var names: Dictionary = {"knight": ["Aldric", "Bertrand", "Cedric", "Godfrey", "Roland"], "wraith": ["Morwen", "Vesper", "Sable", "Ysolde", "Nyx"],
		"demon": ["Azrak", "Vorgath", "Malrok", "Ixtar", "Baelor"], "warlock": ["Fizzwick", "Nimbleroot", "Grimble", "Tobbin", "Wendle"]}
	var pool: Array = names.get(cls, names["knight"])
	return str(pool[randi() % pool.size()])

## Back to the title screen to pick another character (the pause menu's "Save and Exit to Title").
func exit_to_title() -> void:
	save_game()
	if paused:
		toggle_pause()
	if net.active:
		net.shutdown()
	playing = false
	ui.close_all()
	if hero.dead:
		hero.respawn(hero.global_position)
	hero.new_character()
	char_id = ""
	await load_zone(0, "town", "start")
	ui.show_title()

# ---------------------------------------------------------------- shops
func _stock_shops() -> void:
	var V: Dictionary = Data.VENDORS[cur_act]
	var lvl := maxi(hero.level, 1) + 1
	var r := RandomNumberGenerator.new()
	r.randomize()
	var smith := []
	for i in 14:
		var b := Items.pick_base(lvl + 2, r, "weapon" if i < 9 else "shield")
		smith.append(Items.generate(b, lvl, 1 if r.randf() < 0.4 else 0, r))
	var armor := []
	for s in ["helm", "armor", "gloves", "boots", "belt", "helm", "armor", "boots", "gloves", "armor", "belt", "helm"]:
		var b2 := Items.pick_base(lvl + 2, r, s)
		armor.append(Items.generate(b2, lvl, 1 if r.randf() < 0.35 else 0, r))
	var alch := [Items.potion("hp_potion"), Items.potion("mp_potion"), Items.potion("rejuv")]
	for i in 4:
		alch.append(Items.generate("ring" if i < 2 else "amulet", lvl, 1, r))
	var gamble := []
	for s in ["ring", "amulet", "weapon", "weapon", "shield", "helm", "armor", "gloves", "boots", "belt", "ring", "weapon"]:
		var gb := Items.pick_base(lvl + 4, r, s)
		var it := Items.make(gb, 0, lvl)
		it["name"] = "? " + Data.BASES[gb]["name"]
		gamble.append(it)
	shops = {"smith": [V["smith"] + "'s Forge", smith], "armor": [V["armor"] + "'s Armory", armor], "alch": [V["alch"] + "'s Remedies", alch], "gamble": [V["gamble"] + "'s Table", gamble]}

# ---------------------------------------------------------------- interaction
func on_reach_target(t) -> void:
	if not is_instance_valid(t):
		return
	if t is GroundItem:
		_pickup(t)
	elif t is Inter:
		_interact(t)

func _pickup(g: GroundItem) -> void:
	if not is_instance_valid(g) or g.is_queued_for_deletion():
		return
	if net.is_client():
		if not g.has_meta("pending"):
			g.set_meta("pending", true)
			net.request_pickup(g)
		return
	var it: Dictionary = g.item
	if it["base"] == "gold":
		var amt := int(it["count"] * (1.0 + hero.gf / 100.0))
		hero.gold += amt
		Sfx.play("gold")
		Fx.number(world.fx_root, g.global_position + Vector3(0, 1, 0), "+%d gold" % amt, Color(1, 0.85, 0.4))
		if hovered == g:
			hovered = null
		net.item_gone(g)
		g.queue_free()
		ui.refresh()
		return
	if hero.add_to_inventory(it):
		Sfx.play("pickup")
		if hovered == g:
			hovered = null
		net.item_gone(g)
		g.queue_free()
		ui.refresh()
	else:
		ui.message("Inventory is full", Color(1, 0.4, 0.3))

## Co-op: the host handed us an item we picked up.
func receive_item(it: Dictionary, pos: Vector3) -> void:
	if it["base"] == "gold":
		var amt := int(it["count"] * (1.0 + hero.gf / 100.0))
		hero.gold += amt
		Sfx.play("gold")
		Fx.number(world.fx_root, pos + Vector3(0, 1, 0), "+%d gold" % amt, Color(1, 0.85, 0.4))
	elif hero.add_to_inventory(it):
		Sfx.play("pickup")
	else:
		ui.message("Inventory is full", Color(1, 0.4, 0.3))
		net.request_drop(it, hero.global_position)
	ui.refresh()

func travel(act: int, zone: String, spawn: String, at = null, clear_tp := false) -> void:
	if net.is_client():
		net.request_travel(act, zone, spawn, at, clear_tp)
		return
	if clear_tp:
		tp_link = {}
	load_zone(act, zone, spawn, at)

## Shrine or chest used by someone else (or a chest opened for a partner on the host).
func use_inter_remote(t: Inter) -> void:
	if t.kind == "shrine":
		t.used = true
		var orb := t.get_node_or_null("Model/orb")
		if orb:
			orb.visible = false
		var l := t.get_node_or_null("Model/light")
		if l:
			l.visible = false
		Fx.pillar(world.fx_root, t.global_position, Color(1, 0.9, 0.6), 1.0)
	elif t.kind == "flower":
		_pick_flower(t)
	elif t.kind == "chest":
		_open_chest(t)

func _open_chest(t: Inter) -> void:
	t.used = true
	Sfx.play("equip")
	Fx.burst(world.fx_root, t.global_position + Vector3(0, 0.8, 0), Color(1, 0.85, 0.5), 24, 3.0, 0.1, 0.8, true, -4.0)
	if net.is_client():
		return
	var n := rng.randi_range(2, 4)
	for i in n:
		_drop_loot_roll(t.global_position, world.level, false)

func _interact(t: Inter) -> void:
	match t.kind:
		"lanista":
			ui.trade_with = t
			# Varro, by Aurelia's arena: his games are A2's boss fight (games.gd)
			var g = world.get_meta("games") if world.has_meta("games") else null
			if g == null:
				return
			var txt := "Well now. A fighter, by the look of you, and a long way from home. The crowd's grown tired of farmers and debtors. Step onto my sand: three bouts, lions, gladiators, the beasts of my pit, and then Aurelius, who has never lost. Win, and the purse is yours. Lose... well. The lions eat either way."
			var btns := [["Enter the games", func():
				if net.is_client():
					net.request_games()
				else:
					g.begin()], ["Not today", func(): pass]]
			if g.state == "closed" and boss_killed:
				# the games run again for a hero who has won them (and for one whose save beat the old A2)
				txt = "Back again? Aurelius has mended, and he wants your blood more than my purse. The lions are hungry, the stands are full. Step onto my sand and do it all again."
			elif g.state != "closed":
				txt = "The games are on! Get onto the sand, the crowd is waiting."
				btns = [["Farewell", func(): pass]]
			ui.open_dialog(t.label, txt, btns)
		"vendor":
			ui.trade_with = t
			var role: String = t.data.get("role", "")
			if role == "elder":
				var txt := "The crypt lies at the far end of Cairnfell Moor. Bone archers and the restless dead guard the way. Raise your shield against their arrows: a good block turns them aside. And Grubb guards his gold like his life: rip open one of his sacks and his goblins come running for it. Get to the gold before they bring it back to him."
				if difficulty == 1 and not boss_killed:
					txt = "The old Imperial Road runs north to Aurelia. Bandits hold it now, the city too. Watch the pass where the rocks close in: they like to leave a wagon on its side and wait for travellers to stop and look. In Aurelia a man named Varro runs games in the old arena. They say his champion has never lost."
				elif difficulty >= 2 and not boss_killed:
					txt = "Something worse than Grubb sits on his stolen throne in the old crypt. They call him the Ashen King. His bone archers hold the moor, and he carries a blade that burns. Kill him and take it."
				if boss_killed:
					txt = "Grubb is dead and his gold is ours, and the moor already feels lighter. The Wilds owe you a debt it cannot pay. Rest a while, crusader."
				ui.open_dialog(t.label, txt, [["Farewell", func(): pass]])
			else:
				var sh: Array = shops.get(role, ["", []])
				var lines := {"smith": "Need a blade, or something to stop one?", "armor": "Leather, mail or plate. All of it has seen worse than you.", "alch": "Potions for the body, trinkets for the soul.", "gamble": "Fortune favours the bold. Every piece is a mystery until you pay."}
				var btns := [["Trade", func(): ui.open_shop(role, sh[0], sh[1], t, lines.get(role, ""))]]
				if role == "armor":
					btns.append(["Enchant armor", func(): ui.open_enchant(t.label)])
				btns.append(["Leave", func(): pass])
				ui.open_dialog(t.label, lines.get(role, ""), btns)
			Sfx.play("click")
		"stash":
			ui.open_stash()
			ui.trade_with = t
			Sfx.play("equip")
		"waypoint":
			var wp_id: String = t.data.get("wp", "town")
			if not waypoints_known.has(wp_id):
				waypoints_known.append(wp_id)
				ui.message("Waypoint activated", Color(0.5, 0.7, 1.0))
				Sfx.play("portal")
			ui.open_waypoints([
				{"label": Data.act_info(cur_act, difficulty)["town"], "zone": "town", "known": true},
				{"label": Data.act_info(cur_act, difficulty)["wild"], "zone": "wild", "known": waypoints_known.has("wild")},
			], difficulty, (net.party_max_run if net.is_client() else max_run) if cur_zone == "town" else -1)
		"portal":
			Sfx.play("portal")
			if t.data.get("dir", "") == "town":
				travel(cur_act, "town", "portal")
			else:
				var link := tp_link
				travel(int(link.get("act", 0)), link.get("zone", "wild"), "start", link.get("pos"), true)
		"shrine":
			if t.used:
				return
			t.used = true
			var orb := t.get_node_or_null("Model/orb")
			if orb:
				orb.visible = false
			var l := t.get_node_or_null("Model/light")
			if l:
				l.visible = false
			var typ: String = t.data.get("type", "healing")
			Sfx.play("levelup")
			Fx.pillar(world.fx_root, t.global_position, Color(1, 0.9, 0.6), 1.0)
			match typ:
				"healing":
					hero.life = hero.max_life
					hero.mana = hero.max_mana
					ui.message("Healing Shrine: fully restored", Color(1, 0.5, 0.4))
				"fury":
					hero.buff_t = 45.0
					ui.message("Fury Shrine: +40% damage for 45 seconds", Color(1, 0.7, 0.3))
				"armor":
					hero.buff_t = 45.0
					ui.message("Armor Shrine: +40% defense for 45 seconds", Color(0.5, 0.7, 1.0))
				"experience":
					xp_bonus_t = 90.0
					ui.message("Experience Shrine: +50% experience for 90 seconds", Color(0.8, 0.5, 1.0))
			if net.active:
				net.inter_used(t)
		"flower":
			if t.used:
				return
			_pick_flower(t)
			xp_bonus_t = maxf(xp_bonus_t, 300.0)
			Sfx.play("levelup", -6.0, 1.15)
			ui.message("Sunstar Bloom: +50% experience for 5 minutes", Color(1.0, 0.8, 0.35))
			if net.active:
				net.inter_used(t)
		"chest":
			if t.used:
				return
			_open_chest(t)
			if net.active:
				net.inter_used(t)

func travel_waypoint(dest: Dictionary) -> void:
	Sfx.play("portal")
	travel(cur_act, dest["zone"], "waypoint")

func _make_portal(p: Vector3, dir: String) -> Inter:
	var it := Inter.new()
	it.kind = "portal"
	it.label = "Town Portal" if dir == "town" else "Portal to " + zone_title(int(tp_link.get("act", 0)), tp_link.get("zone", "wild"))
	it.radius = 1.4
	it.data = {"dir": dir}
	world.add_child(it)
	it.global_position = Vector3(p.x, world.height_at(p.x, p.z), p.z)
	var m := Fx.portal_model()
	m.name = "Model"
	it.add_child(m)
	world.interactables.append(it)
	return it

func cast_town_portal() -> void:
	if cur_zone == "town":
		ui.message("You are already in town", Color(0.6, 0.7, 1.0))
		return
	if hero.dead:
		return
	var fwd := -hero.rig.global_transform.basis.z
	var p := world.free_spot_near(hero.global_position + fwd * 2.0, 1.0)
	if net.is_client():
		net.request_portal(p)
		return
	open_town_portal_at(p)

func open_town_portal_at(p: Vector3) -> void:
	for it in world.interactables:
		if is_instance_valid(it) and it.kind == "portal" and it.has_meta("dyn") and it.data.get("dir", "") == "town" and not it.has_meta("boss"):
			world.interactables.erase(it)
			it.queue_free()
			break
	tp_link = {"act": cur_act, "zone": cur_zone, "pos": p}
	var t := _make_portal(p, "town")
	t.set_meta("dyn", true)
	Sfx.play("portal")
	Fx.burst(world.fx_root, p + Vector3(0, 1.4, 0), Color(0.4, 0.6, 1.0), 40, 3.0, 0.12, 1.0, true, 0.0)
	net.portal_created(t)

## A Sunstar Bloom picked (by anyone): it is gone, in a puff of golden motes.
func _pick_flower(t: Inter) -> void:
	t.used = true
	t.label = ""
	var m := t.get_node_or_null("Model")
	if m:
		m.visible = false
	Fx.burst(world.fx_root, t.global_position + Vector3(0, 0.5, 0), Color(1.0, 0.82, 0.35), 30, 2.2, 0.07, 1.1, true, 1.5)

# ---------------------------------------------------------------- kills & loot
func gain_kill_xp(xp: int, lvl: int) -> void:
	var bonus := 1.5 if xp_bonus_t > 0.0 else 1.0
	var lvl_ratio := clampf(1.0 - (hero.level - lvl) * 0.08, 0.2, 1.3)
	hero.add_xp(int(xp * lvl_ratio * bonus))

func on_enemy_killed(e: Enemy) -> void:
	gain_kill_xp(e.xp, e.level)
	net.share_xp(e.xp, e.level)
	var drops := 0 if e.def.get("no_loot", false) else 1
	if e.champion:
		drops = 3
	if e.boss:
		drops = 7
	for i in drops:
		_drop_loot_roll(e.global_position, e.level, e.boss or (e.champion and i == 0))
	if e.def.has("boss_drop"):
		var bu := Items.make_unique(e.def["boss_drop"])
		if difficulty >= 1:
			Items.empower(bu, loot_mult())
		drop_item(bu, e.global_position)
		ui.message("%s dropped %s!" % [e.display_name, bu["name"]], Color(0.85, 0.66, 0.38))
	if e.boss:
		boss_killed = true
		ui.set_boss(null)
		ui.big_message(e.display_name + " has fallen")
		add_shake(0.8)
		Fx.pillar(world.fx_root, e.global_position, Color(1.0, 0.3, 0.2), 2.0)
		var ptl := _make_portal(world.free_spot_near(e.global_position + Vector3(0, 0, 3.5), 1.0), "town")
		ptl.label = "Portal to " + Data.act_info(cur_act, difficulty)["town"]
		ptl.set_meta("boss", true)
		net.portal_created(ptl)
		save_game()
		await get_tree().create_timer(3.5).timeout
		ui.show_victory(difficulty)
		Sfx.play("levelup")

## Co-op: the host's game reports the boss fell.
func boss_down_remote(e: Enemy) -> void:
	boss_killed = true
	ui.set_boss(null)
	ui.big_message(e.display_name + " has fallen")
	add_shake(0.8)
	Fx.pillar(world.fx_root, e.global_position, Color(1.0, 0.3, 0.2), 2.0)
	save_game()
	await get_tree().create_timer(3.5).timeout
	ui.show_victory(difficulty)
	Sfx.play("levelup")

func on_boss_aggro(e: Enemy) -> void:
	net.boss_aggro(e)
	ui.set_boss(e)
	ui.big_message(e.display_name)
	Sfx.play("roar")
	add_shake(0.5)

func _drop_loot_roll(at: Vector3, lvl: int, good: bool) -> void:
	var r := rng.randf()
	if good or r < 0.3:
		var it := Items.random_drop(lvl, hero.mf + (100 if good else 0), rng, good)
		if difficulty >= 1:
			Items.empower(it, loot_mult())
		drop_item(it, at)
	elif r < 0.62:
		drop_item(Items.gold(int(rng.randf_range(4, 12) * (1.0 + lvl * 0.6))), at)
	elif r < 0.78:
		var pk := "hp_potion" if rng.randf() < 0.6 else ("mp_potion" if rng.randf() < 0.8 else "rejuv")
		drop_item(Items.potion(pk), at)

func drop_item(it: Dictionary, at: Vector3) -> void:
	if net.is_client():
		net.request_drop(it, at)
		return
	var g := GroundItem.new()
	world.items_root.add_child(g)
	var to := world.free_spot_near(at, 1.8)
	g.setup(it, at + Vector3(0, 1.0, 0), to)
	if net.active:
		net.on_item_dropped(g, it, at, to)
	if int(it.get("rarity", 0)) >= 2:
		Sfx.play("levelup", -12.0, 1.6)

# ---------------------------------------------------------------- feedback
func focus_on(n: Node3D, dur: float, z := 0.55) -> void:
	focus_node = n
	focus_t = 0.0
	focus_len = dur
	focus_zoom = z

func add_shake(v: float) -> void:
	shake = minf(1.0, shake + v)

var _hitstop_until := 0
func hitstop(t: float) -> void:
	_hitstop_until = Time.get_ticks_msec() + int(t * 1000.0)
	Engine.time_scale = 0.08

func _on_hero_died() -> void:
	death_t = 2.0
	ui.set_boss(null)

func respawn() -> void:
	hero.gold = int(hero.gold * 0.9)
	if net.active:
		var ally := net.alive_ally()
		if ally:
			hero.respawn(world.free_spot_near(ally.global_position, 2.0))
			ui.message("You rise beside %s" % net.players.get(ally.peer_id, {"name": "your ally"})["name"], Color(0.6, 0.8, 1.0))
			return
		if net.is_client():
			hero.respawn(hero.global_position)
			net.travel_cool = 0.0
			net.request_travel(cur_act, "town", "start", null)
			return
	await load_zone(cur_act, "town", "start")
	hero.respawn(hero.global_position)

func toggle_pause() -> void:
	paused = not paused
	get_tree().paused = paused and not net.active
	ui.pause_panel.visible = paused
	Engine.time_scale = 1.0
	lmb_held = false

# ---------------------------------------------------------------- input
func _ground_from_ray(o: Vector3, d: Vector3) -> Vector3:
	var h := 0.0
	var p := o
	for i in 4:
		if absf(d.y) < 0.0001:
			break
		var t := (h - o.y) / d.y
		p = o + d * t
		h = world.height_at(p.x, p.z)
	return p

func _drop_stale() -> void:
	if hovered != null and (not is_instance_valid(hovered) or hovered.is_queued_for_deletion()):
		hovered = null
	if hero and hero.target != null and (not is_instance_valid(hero.target) or hero.target.is_queued_for_deletion()):
		hero.target = null

## The point on segment a-b closest to the ray (o, unit d).
static func _ray_closest(o: Vector3, d: Vector3, a: Vector3, b: Vector3) -> Vector3:
	var u := b - a
	var w := a - o
	var uu := u.dot(u)
	var ud := u.dot(d)
	var den := uu - ud * ud
	if den < 1e-6:
		return a
	var t := clampf((ud * w.dot(d) - w.dot(u)) / den, 0.0, 1.0)
	return a + u * t

## The monster under a camera ray (nearest first): each is a capsule from its feet to the top
## of its head, so a tall boss is clickable all over.
func pick_enemy(o: Vector3, d: Vector3) -> Enemy:
	var best: Enemy = null
	var best_d := 1e9
	for e in world.enemies_root.get_children():
		if not (e is Enemy) or e.dead or e.is_queued_for_deletion():
			continue
		var a: Vector3 = e.global_position + Vector3(0, 0.2, 0)
		var b: Vector3 = e.global_position + Vector3(0, maxf(e.top() - 0.2, 0.5), 0)
		var c := _ray_closest(o, d, a, b)
		var dist := (c - o).cross(d).length()
		var rad: float = e.radius + 0.3 + (0.2 if e.boss else 0.0)
		if dist < rad:
			var along := (c - o).dot(d)
			if along < best_d:
				best_d = along
				best = e
	return best

func _update_hover() -> void:
	_drop_stale()
	if world == null:
		return
	var mp := get_viewport().get_mouse_position()
	var o := cam.project_ray_origin(mp)
	var d := cam.project_ray_normal(mp)
	ground_pt = _ground_from_ray(o, d)
	var best = pick_enemy(o, d)
	if best == null:
		for g in world.items_root.get_children():
			if g is GroundItem and g._toss >= 1.0 and not g.is_queued_for_deletion():
				var lp: Vector3 = g.global_position + Vector3(0, 0.75, 0)
				var dist2 := (lp - o).cross(d).length()
				var dg := Vector2(ground_pt.x - g.global_position.x, ground_pt.z - g.global_position.z).length()
				if (dist2 < 0.35 and g.label.visible) or dg < 0.55:
					best = g
					break
	if best == null:
		for it in world.interactables:
			if not is_instance_valid(it) or (it.kind == "flower" and it.used):
				continue
			var c2: Vector3 = it.global_position + Vector3(0, 1.0, 0)
			if (c2 - o).cross(d).length() < 1.1:
				best = it
				break
	if hovered != best:
		if is_instance_valid(hovered) and hovered is GroundItem:
			hovered.set_hover(false, Input.is_key_pressed(KEY_ALT))
		hovered = best
		if hovered is GroundItem:
			hovered.set_hover(true, true)
	if is_instance_valid(hovered) and hovered is Enemy:
		var col := Color(1, 1, 1)
		if hovered.champion:
			col = Color(0.45, 0.6, 1.0)
		if hovered.boss:
			col = Color(0.85, 0.66, 0.38)
		ui.target_bar.visible = true
		ui.show_target(hovered.display_name, hovered.life / hovered.max_life, col)
	elif hovered is Inter:
		ui.show_target(hovered.label, 1.0, Color(0.85, 0.75, 0.5))
		ui.target_bar.visible = false
	else:
		ui.hide_target()

func _unhandled_input(ev: InputEvent) -> void:
	if not playing:
		return
	if ev is InputEventMouseButton:
		if ev.button_index == MOUSE_BUTTON_LEFT:
			if ev.pressed and not paused:
				lmb_held = true
				lmb_repeat = 0.12
				_update_hover()
				# a skill other than Attack on left mouse casts on a foe (or anywhere with Shift);
				# clicking the ground, an item or an NPC still walks there
				if hero.bound("lmb") not in ["attack", ""] and (hovered is Enemy or Input.is_key_pressed(KEY_SHIFT)):
					_use_bind("lmb", true)
				else:
					_click_world()
		elif ev.button_index == MOUSE_BUTTON_RIGHT:
			if ev.pressed and not paused:
				rmb_held = true
				_use_bind("rmb", true)
		elif ev.button_index == MOUSE_BUTTON_WHEEL_UP and ev.pressed:
			zoom = clampf(zoom - 0.08, 0.6, 1.3)
		elif ev.button_index == MOUSE_BUTTON_WHEEL_DOWN and ev.pressed:
			zoom = clampf(zoom + 0.08, 0.6, 1.3)
	if ev is InputEventKey and ev.pressed and not ev.echo:
		match ev.keycode:
			KEY_ESCAPE:
				if not ui.close_all():
					toggle_pause()
			KEY_I, KEY_B:
				ui.toggle(ui.inv_panel)
			KEY_C:
				ui.toggle(ui.char_panel)
			KEY_T:
				cast_town_portal()
			KEY_1, KEY_2, KEY_3, KEY_4:
				hero.drink(ev.keycode - KEY_1)
			KEY_Q, KEY_E, KEY_R, KEY_F, KEY_G, KEY_V:
				if not ui.skills_hotkey(OS.get_keycode_string(ev.keycode)):
					_use_bind(OS.get_keycode_string(ev.keycode), true)
			KEY_K:
				ui.toggle(ui.skills_panel)
			KEY_N:
				ui.toggle(ui.talent_panel)
			KEY_F3:
				ui.show_fps = not ui.show_fps
			KEY_F2:
				set_sound(not sound_on)
				ui.message("Sound " + ("on" if sound_on else "off"), Color(0.8, 0.85, 1.0))
				ui.update_sound_btn()
			KEY_F8:
				if UNLOCK_ALL_ACTS:
					ui.toggle(ui.test_panel)
			KEY_M:
				ui.minimap.visible = not ui.minimap.visible
			KEY_TAB:
				ui.minimap.visible = true
				ui.minimap.set_big(not ui.minimap.big)

func _input(ev: InputEvent) -> void:
	if _intro_playing and ((ev is InputEventKey and ev.pressed and not ev.echo) or (ev is InputEventMouseButton and ev.pressed)):
		_intro_skip = true
		get_viewport().set_input_as_handled()
		return
	if ev is InputEventMouseButton and ev.button_index == MOUSE_BUTTON_LEFT and not ev.pressed:
		lmb_held = false
	if ev is InputEventMouseButton and ev.button_index == MOUSE_BUTTON_RIGHT and not ev.pressed:
		rmb_held = false

func cast_slot(i: int) -> void:
	cast_skill(hero.bound(Hero.BIND_KEYS[i]))

## Is this bar slot's button (mouse button or hotkey) being held right now?
func slot_held(slot: String) -> bool:
	match slot:
		"lmb": return lmb_held
		"rmb": return rmb_held
	return BIND_KEYCODES.has(slot) and Input.is_key_pressed(BIND_KEYCODES[slot])

## Is any button the skill is bound to being held? (Block, Drain Life's channel, held Attack)
func skill_held(id: String) -> bool:
	for slot in Hero.BIND_SLOTS:
		if hero.bound(slot) == id and slot_held(slot):
			return true
	return false

func _cursor_aim() -> Vector3:
	return hovered.global_position if hovered is Enemy else ground_pt

## A bar slot was pressed (first) or is still held (repeat): cast what's bound there. Attack swings
## at the cursor, Block is held (see _process), anything else is cast; held, it recasts whenever it
## is ready again, without the "recharging" and "no mana" messages.
func _use_bind(slot: String, first: bool) -> void:
	if hero == null or hero.dead or ui.any_panel_open():
		return
	var id := hero.bound(slot)
	match id:
		"", "block":
			return
		"attack":
			_update_hover()
			hero.swipe_attack(_cursor_aim())
			return
	if first or hero.skill_ready(id):
		cast_skill(id)

func cast_skill(id: String) -> void:
	if not playing or hero.dead:
		return
	_update_hover()
	var cursor := ground_pt
	if hovered is Enemy:
		cursor = hovered.global_position
	hero.use_skill(id, hero.skill_aim(id, cursor))

func _click_world() -> void:
	_update_hover()
	_drop_stale()
	if hero.dead:
		return
	if hovered is Enemy or hovered is GroundItem or hovered is Inter:
		hero.cmd_target(hovered)
	else:
		hero.cmd_move(ground_pt)
		Fx.burst(world.fx_root, ground_pt + Vector3(0, 0.05, 0), Color(1.0, 0.85, 0.5, 0.6), 6, 1.2, 0.08, 0.35, true, 0.0, 90.0)

# ---------------------------------------------------------------- loop
func _process(delta: float) -> void:
	_t += delta
	var real_dt := delta / maxf(Engine.time_scale, 0.01)
	_watchdog(real_dt)
	if world == null:
		return
	xp_bonus_t = maxf(0.0, xp_bonus_t - delta)
	exit_grace = maxf(0.0, exit_grace - delta)
	_drop_stale()
	if Engine.time_scale < 1.0 and Time.get_ticks_msec() > _hitstop_until:
		Engine.time_scale = 1.0
	if playing and not paused and not _busy:
		_update_hover()
		_check_ambushes()
		hero.blocking = skill_held("block") and not ui.any_panel_open()
		for slot in Hero.BIND_SLOTS:
			if slot != "lmb" and slot_held(slot):
				_use_bind(slot, false)
		hero.sprint = Input.is_key_pressed(KEY_SHIFT)
		if Input.is_key_pressed(KEY_SPACE):
			hero.swipe_attack(hero.aim_ahead(hero.reach() + 1.5))
		var wasd := Vector3.ZERO
		if Input.is_key_pressed(KEY_W): wasd.z -= 1
		if Input.is_key_pressed(KEY_S): wasd.z += 1
		if Input.is_key_pressed(KEY_A): wasd.x -= 1
		if Input.is_key_pressed(KEY_D): wasd.x += 1
		hero.cmd_wasd(wasd)
		if lmb_held and not hero.dead:
			lmb_repeat -= delta
			if lmb_repeat <= 0.0:
				lmb_repeat = 0.12
				if hero.bound("lmb") not in ["attack", ""] and (hovered is Enemy or Input.is_key_pressed(KEY_SHIFT)):
					_use_bind("lmb", false)
				elif hovered is Enemy:
					if hero.target != hovered:
						hero.cmd_target(hovered)
				elif hero.target == null or not (hero.target is Enemy):
					if not (hovered is GroundItem or hovered is Inter):
						hero.cmd_move(ground_pt, world.los(hero.global_position, ground_pt))
		var show_all := Input.is_key_pressed(KEY_ALT)
		for g in world.items_root.get_children():
			if g is GroundItem and g != hovered:
				g.set_hover(false, show_all)
				if g.item["base"] == "gold" and g._toss >= 1.0 and not hero.dead:
					if g.global_position.distance_to(hero.global_position) < 1.0:
						_pickup(g)
		if exit_grace <= 0.0 and not hero.dead:
			for ex in world.exits:
				var dd: Vector3 = ex["pos"] - hero.global_position
				if Vector2(dd.x, dd.z).length() < ex["radius"]:
					var to: String = ex["to"]
					var spawn := "start"
					if cur_zone == "town" and to == "wild":
						spawn = "from_town"
					elif cur_zone == "wild" and to == "town":
						spawn = "from_wild"
					elif cur_zone == "lair" and to == "wild":
						spawn = "from_lair"
					travel(cur_act, to, spawn)
					break
	if death_t > 0.0:
		death_t -= delta
		if death_t <= 0.0:
			ui.death_panel.visible = true
	if hero and world:
		var look_ahead := Vector3.ZERO
		if playing and not hero.dead and shot_path == "":
			var mp := get_viewport().get_mouse_position() / get_viewport().get_visible_rect().size - Vector2(0.5, 0.5)
			look_ahead = Vector3(mp.x, 0, mp.y) * 2.0
		var goal: Vector3 = hero.global_position + look_ahead
		var fw := 0.0
		if focus_node != null:
			focus_t += real_dt
			if focus_t >= focus_len or not is_instance_valid(focus_node):
				focus_node = null
			else:
				fw = smoothstep(0.0, 0.6, focus_t) * (1.0 - smoothstep(focus_len - 0.7, focus_len, focus_t))
				goal = goal.lerp(focus_node.global_position + Vector3(0, 0.6, 0), fw)
		cam_target = cam_target.lerp(goal, clampf(real_dt * 5.0, 0.0, 1.0))
		weather.follow(cam_target)
		cam_pivot.position = cam_target
		if not playing:
			cam_pivot.position = hero.global_position + Vector3(sin(_t * 0.12) * 3.0, 0, cos(_t * 0.1) * 1.5)
		shake = maxf(0.0, shake - real_dt * 2.2)
		var sh := Vector3(randf_range(-1, 1), randf_range(-1, 1), 0) * shake * shake * 0.35
		cam.position = CAM_OFFSET * zoom * lerpf(1.0, focus_zoom, fw) + sh
		RenderingServer.global_shader_parameter_set("player_pos", hero.global_position)
	_update_underworld(real_dt)
	for l in get_tree().get_nodes_in_group("flicker"):
		var lt := l as OmniLight3D
		var b: float = lt.get_meta("base", 1.0)
		var id := float(lt.get_instance_id() % 100)
		lt.light_energy = b * (0.85 + 0.1 * sin(_t * 9.0 + id) + 0.07 * sin(_t * 23.0 + id * 2.3))
	if shot_path != "" and not _busy and world:
		shot_frames += 1
		if shot_frames == 50:
			_shot_setup()
		if shot_frames == (320 if OS.get_cmdline_user_args().has("--spill") else 150 if OS.get_cmdline_user_args().has("--inv") else (120 if OS.get_cmdline_user_args().has("--dragtest") else (62 if OS.get_cmdline_user_args().has("--snowtest") else 90))):
			var img := get_viewport().get_texture().get_image()
			img.save_png(shot_path)
			print("saved ", shot_path)
			get_tree().quit()

## For automated screenshots: stage a fight near the hero.
func _shot_setup() -> void:
	var args := OS.get_cmdline_user_args()
	if args.has("--bigmap"):
		ui.minimap.set_big(true)
	if args.has("--inv"):
		var r := RandomNumberGenerator.new()
		r.seed = 5
		hero.level = 14
		hero.equipment["weapon"] = Items.make_unique("emberfang")
		hero.equipment["shield"] = Items.make_unique("wardens_wall")
		hero.equipment["helm"] = Items.generate("great_helm", 14, 2, r)
		hero.equipment["armor"] = Items.generate("chain_mail", 14, 1, r)
		hero.equipment["gloves"] = Items.generate("gauntlets", 14, 1, r)
		hero.equipment["boots"] = Items.make_unique("stormstride")
		hero.equipment["belt"] = Items.generate("war_belt", 14, 0, r)
		hero.equipment["ring1"] = Items.make_unique("ninth_sun")
		hero.equipment["amulet"] = Items.generate("amulet", 14, 2, r)
		for i in 14:
			hero.inventory[i * 2 + (i / 5)] = Items.random_drop(12, 300, r)
		hero.show_helm = not args.has("--nohelm")
		hero.recalc()
		hero.refresh_gear()
		ui.inv_panel.visible = true
		ui.char_panel.visible = true
		ui.refresh()
		ui._hover(ui.equip_cells["weapon"], true, "equipped")
	if args.has("--archers"):
		zoom = 0.6
		for i in 3:
			var ep := world.free_spot_near(hero.global_position + Vector3(-2.0 + i * 2.0, 0, -2.6 - absf(i - 1) * 0.6), 0.5)
			var a := spawn_enemy("skel_archer", ep, 2)
			a.aggro = true
	if args.has("--hudtest"):
		hero.level = 7
		hero.recalc()
		hero.xp = int(Data.xp_for_level(7) * 0.42)
		hero.stamina = hero.max_stamina * 0.62
		hero.stamina_rest = -99.0
		hero.cds["cleave"] = 0.6
		ui.refresh()
	if args.has("--dragtest"):
		ui.toggle(ui.inv_panel)
		hero.inventory[0] = Items.make_unique("emberfang")
		hero.inventory[1] = Items.make_unique("ninth_sun")
		hero.inventory[11] = Items.potion("hp_potion")
		ui.refresh()
		await get_tree().create_timer(2.5).timeout
		if not args.has("--nodrag"):
			ui.drag_hold = true
			ui.drag_idx = 0
			ui._start_drag(0)
			Input.warp_mouse(Vector2(640, 470))
		if not args.has("--nofx"):
			ui.click_fx(ui.inv_cells[1])
	if args.has("--snowtest"):
		var back := Vector3(0, 0, 1)
		for k in 14:
			var pp := hero.global_position + back * (0.6 + k * 0.42) + Vector3(sin(k * 0.5) * 0.3, 0, 0)
			pp.y = world.height_at(pp.x, pp.z)
			weather.footstep(world.fx_root, pp, 0.0, 1.0 if k % 2 == 0 else -1.0)
		hero.breath.restart()
	if args.has("--zoomout"):
		zoom = 1.3
	if args.has("--zoomin"):
		zoom = 0.6
		ui.close_all()
	if args.has("--enchtest"):
		hero.equipment["helm"] = Items.generate("great_helm", 12, 1, rng)
		hero.equipment["helm"]["ench"] = 6
		hero.equipment["boots"] = Items.generate("greaves", 12, 0, rng)
		hero.equipment["boots"]["ench"] = 2
		hero.gold = 25000
		hero.recalc()
		hero.refresh_gear()
		ui.open_enchant("Hedda")
		ui._enchant("armor")
	if args.has("--god"):
		hero.vit = 2000000
		hero.recalc()
		hero.life = hero.max_life
	if args.has("--spill"):
		# King Grubb: burst his first sack
		for x in enemies_near(hero.global_position, 80.0):
			if x.boss and x.hoard != null:
				x.aggro = true
				x.life = x.max_life * 0.74
	if args.has("--fight"):
		var e := enemies_near(hero.global_position, 80.0)
		for x in e:
			if x.boss:
				e = [x]
				break
		if e.size() > 0:
			var tgt: Enemy = e[0]
			hero.global_position = world.free_spot_near(tgt.global_position + Vector3(0, 0, 2.2), 0.5)
			hero.cmd_target(tgt)
		hero.blocking = OS.get_cmdline_user_args().has("--block")
