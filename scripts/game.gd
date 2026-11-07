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
## Day and night in Act I's camp (DayNight): the hour moves the sun or moon (this light), the sky, the mist and the
## lamps. lamp_mul and fire_mul scale the "flicker" lights (lanterns and candles, and fires) for the hour.
var day_night: DayNight
var lamp_mul := 1.0
var fire_mul := 1.0
var cam_pivot: Node3D
var cam: Camera3D
var hero: Hero
var net: Net
var steam: SteamLink            # co-op through Steam: friends join your world (steam_link.gd); ok is false without Steam
var weather: Weather
var grass_field: GrassField   # the grass's touch and wind (grass_field.gd)
var sky_mat: ProceduralSkyMaterial
var space_sky: ShaderMaterial      # the island camp's sky (CampIsland.space_sky)
var zoom_max := 1.3                # the scroll wheel's furthest out (further over the World-Tree Island)
## The orbit camera (jj, 2026-11-04: "allow the player to use mouse and rotate around it from all views"): zoomed out
## past the game's own view (zoom > ORBIT_ZOOM, the World-Tree Island), dragging with the middle mouse button (or Alt
## and the left) turns the camera round and tilts it, down past the island's edge to its underside; the view also
## drifts from the hero to the island's middle the further out it is. Zoomed back in, it eases home to the game's
## own angle. Any zone that raises zoom_max gets it.
const ORBIT_ZOOM := 1.32
var orbit_yaw := 0.0
var orbit_pitch := 0.0             # added to the camera's own elevation (radians, + = higher)
var _orbit_drag := false

func _orbit_input(ev: InputEvent) -> bool:
	if ev is InputEventMouseButton:
		var mb := ev as InputEventMouseButton
		var orb := mb.button_index == MOUSE_BUTTON_MIDDLE or (mb.button_index == MOUSE_BUTTON_LEFT and mb.alt_pressed)
		if orb and zoom > ORBIT_ZOOM:
			_orbit_drag = mb.pressed
			return true
		if not mb.pressed and (mb.button_index == MOUSE_BUTTON_MIDDLE or mb.button_index == MOUSE_BUTTON_LEFT):
			_orbit_drag = false
	elif ev is InputEventMouseMotion and _orbit_drag:
		var mm := ev as InputEventMouseMotion
		orbit_yaw = wrapf(orbit_yaw - mm.relative.x * 0.006, -PI, PI)
		orbit_pitch = clampf(orbit_pitch - mm.relative.y * 0.005, deg_to_rad(-80.0), deg_to_rad(38.0))
		return true
	return false

## The camera's place round its pivot: the game's offset, turned by the orbit.
func _orbit_offset(off: Vector3) -> Vector3:
	if absf(orbit_yaw) < 0.0001 and absf(orbit_pitch) < 0.0001:
		return off
	var flat := Vector2(off.z, off.y)
	var elev := atan2(flat.y, flat.x) + orbit_pitch
	var d := off.length()
	var o := Vector3(0, sin(elev) * d, cos(elev) * d)
	return Basis(Vector3.UP, orbit_yaw) * o
var ui: UI
var quests: Quests          # the quest log (quests.gd), per character and run
var vignette: ColorRect
var loading: ColorRect
var loading_lbl: Label
var loading_art: TextureRect     # the destination's painting behind the loading words (set_loading_art)
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
## Battlegrounds (battlegrounds.gd): the server's raid logic (only on a `--server` run), whether this game is a
## player in a raid, and that player's stash as the server last reported it.
var bg: Battlegrounds
var bg_mode := false:
	set(v):
		var was := bg_mode
		bg_mode = v
		# the Battlegrounds' gear rules come and go with the raid (Hero.pvp_scaled)
		if was != v and hero != null and is_instance_valid(hero):
			hero.recalc()
			hero.life = hero.max_life
var net_joining := false     # a co-op join sent, no welcome yet (on_net_failed then goes back to the co-op screen)
var bg_raid := {}               # the round as the raid server last said (Net.cl_bg_raid): state, t, open portals...
var bg_roster: Array = []       # the antechamber's matchup (Net.cl_bg_roster): [{pid, cls, lvl}], this player too
var bg_gained := -1             # ... items brought out of it (-1: no extraction; the news told back at the camp)
var bg_wait_until := 0         # turned away late in a round: when (ticks msec) the next raid lets players in
var bg_refusal := ""           # why the raid server last turned us away ("closed", "refused")
## The camp's stash, one for every character on this PC (SharedStash; a tool script's own file under -s).
var stash: SharedStash
## Characters and the stash in Nakama (cloud_saves.gd), in builds with BuildEnv.cloud() on; null otherwise.
var cloud: CloudSaves
var sandbox: Sandbox = null     # the admins' Battlegrounds sandbox (sandbox.gd) while one is open
var paused := false
var match_instance
var lobby_client
var arena_mode := false
var arena_state := {}
var party_join_ticket := ""
var party_join_pending := false
var hovered = null
var ground_pt := Vector3.ZERO
var lmb_held := false
var lmb_repeat := 0.0
var rmb_held := false
const BIND_KEYCODES := {"Q": KEY_Q, "E": KEY_E, "R": KEY_R, "F": KEY_F, "G": KEY_G, "V": KEY_V}
var exit_grace := 0.0
var test_block := false        # a tool holding the guard up (game/heroes/archer/tools/fire_range.gd's "block" take)
var waypoints_known := ["town"]
var boss_killed := false
## Always 0: Act I is the only act (the story's A2 and A3 are cut). Kept because saves and tools still set it.
var difficulty := 0
## Developer tools (the Escape menu's Admin column): only for the admins. On when running from
## the Godot editor (or a local debug run), for an account with the admin role (Nakama, tools/admin_role.sh;
## CloudSaves turns it on after signing in), or when this PC holds a valid admin key (AdminKey: signed with the owner's private key, so it can't be made up or shared by editing a file).
## Off for everyone else in every production build.
var admin_name := AdminKey.holder()
var dev_tools := OS.has_feature("editor") or admin_name != "" or (BuildEnv.env() == "local" and OS.has_feature("debug"))
var account_id := ""            # this player's Nakama account (CloudSaves), shown in the Admin column to be made an admin
var account_admin := false      # the account has the admin role (Nakama, tools/admin_role.sh): the admin tools on
var played_s := 0.0          # seconds this character has been played (saved); the clock trees regrow on (Harvest)
var harvest_saved := {}      # "<run>:<act>:<zone>" -> Harvest.to_save() (the felled trees and when they regrow)
var tp_link := {}
var xp_bonus_t := 0.0
var shops := {}
var rng := RandomNumberGenerator.new()
var shot_path := ""
var shot_spawn := ""
var shot_zone := "town"
var shot_frames := 0
var death_t := -1.0
var spectating := 0             # Battlegrounds: the fallen hero's camera follows this player (peer id; 0 = no one)
var _spec_lost := 0.0           # ... how long the one watched has been down
var _spec_over := 0.0           # ... how long since the round ended (then the crypt sends them home)
var _t := 0.0
var _busy := false

func _ready() -> void:
	rng.randomize()
	if OS.is_debug_build():
		for e in Data.check_waypoints():
			push_warning("Waypoints: " + e)
	Mats.ensure_globals()
	var args := OS.get_cmdline_user_args()
	for i in args.size():
		if args[i] == "--shot" and i + 1 < args.size():
			shot_path = args[i + 1]
		if args[i] == "--spawn" and i + 1 < args.size():
			shot_spawn = args[i + 1]
		if args[i] == "--zone" and i + 1 < args.size():
			shot_zone = args[i + 1]
		if args[i] == "--render-scale" and i + 1 < args.size():
			render_scale_arg = float(args[i + 1])
	quality = _initial_quality()
	if args.has("--server"):
		sound_on = false
		Sfx.set_muted(true)
	else:
		set_sound(bool(_load_setting("audio", "sound_on", true)))
	click_move = bool(_load_setting("controls", "click_move", false))
	_setup_env()
	weather = Weather.new()
	weather.name = "Weather"
	add_child(weather)
	grass_field = GrassField.new()
	grass_field.name = "GrassField"
	grass_field.movers_fn = _grass_movers
	add_child(grass_field)
	_setup_camera()
	_setup_post()
	get_window().size_changed.connect(apply_render_scale)
	quests = Quests.new(self)
	ui = UI.new()
	add_child(ui)
	ui.setup(self)
	net = Net.new()
	add_child(net)
	net.setup(self)
	steam = SteamLink.new()
	steam.name = "SteamLink"
	add_child(steam)
	steam.setup(self)
	hero = Hero.new()
	hero.name = "Hero"
	add_child(hero)
	hero.setup(self)
	hero.new_character()
	hero.died.connect(_on_hero_died)
	hero.leveled.connect(_on_level)
	ui.bind_hero(hero)
	if not args.has("--server"):
		lobby_client = load("res://game/ui/lobby/lobby_client.gd").new()
		add_child(lobby_client)
		lobby_client.setup(self)
	if not args.has("--server"):
		stash = SharedStash.new(SharedStash.TEST_PATH if get_tree().get_script() != null else SharedStash.PATH)
	if BuildEnv.cloud() and not args.has("--server") and shot_path == "" and not args.has("--kpi"):
		cloud = CloudSaves.new(self)
		add_child(cloud)
		if stash != null:
			stash.pushed = func(d: Dictionary): cloud.push_stash(d)
		_cloud_start()
	if Telemetry.wanted():
		add_child(Telemetry.new(self))      # player telemetry and error reports (scripts/telemetry.gd)
	if Kpi.start(self):
		return       # the official performance KPIs (scripts/kpi.gd): a scripted scenario, measured, then quit
	if args.has("--server"):
		Enemy.server_nopose = not args.has("--pose")      # nobody sees a server's bodies (Enemy.server_nopose)
		# the Battlegrounds' dedicated server: `godot --headless --path . -- --server [--port N]`
		var pi := args.find("--port")
		var port := int(args[pi + 1]) if pi >= 0 and pi + 1 < args.size() else Net.PORT
		if args.has("--match-config"):
			match_instance = load("res://scripts/match_instance.gd").new()
			add_child(match_instance)
			await match_instance.start(self, args[args.find("--match-config") + 1], port)
		else:
			await Battlegrounds.start_server(self, port)
		return
	if shot_path != "":
		ui.hide_title()
		playing = true
		var ci := OS.get_cmdline_user_args().find("--class")
		if ci >= 0 and ci + 1 < OS.get_cmdline_user_args().size():
			hero.set_class(OS.get_cmdline_user_args()[ci + 1])
		await load_zone(0, shot_zone, shot_spawn if shot_spawn != "" else "start")
		return
	# No world is built behind the title (Blaine, 2026-11-06): the camp it used to build at every start froze the
	# screen ~1 s and was built again by start_game anyway. The home screen's models load on the loader's threads;
	# whatever is chosen there (a lobby, Sandbox) loads its own zone.
	_busy = true
	_boot_preload()
	_bury_lost_raiders()
	_stash_start()
	await _await_preloads()
	_busy = false
	# (the tools/ test harness still finds the camp built when the title comes up: its scripts wait for a world)
	if _harness_camp():
		await load_zone(0, "town", "start")
	ui.show_title()
	_release_preloads()

# ---------------------------------------------------------------- intro
## (no trailer any more, Blaine 2026-11-06: tools still wait on these, always false)
var _intro_playing := false
var _intro_skip := false

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
	if hero and hero.phased and bg == null:
		# (a dedicated server's own hero stays phased: it's how monsters ignore it)
		hero.phased = false
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
	Telemetry.crumb("level", {"level": l})
	ui.big_message("Level %d" % l)
	if hero.run != null:
		ui.message("Stronger: your attributes rise with every level  ·  camp chests bring skills, rites and gems", Color(1, 0.85, 0.4))
	else:
		ui.message("+5 stat points (press C)  ·  +1 rite point (press N)", Color(1, 0.85, 0.4))

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
	day_night = DayNight.new()
	day_night.name = "DayNight"
	day_night.game = self
	add_child(day_night)
	apply_quality(quality)

## Snow over every outdoor area, falling snow, colder light. Nothing is snowy now: kept for a later map.
func is_snowy() -> bool:
	return false

## The zone's song and ambience. Act I's forest outside the camp (the Verdant Reach): soft trees in the breeze
## instead of the wind.
func zone_music() -> void:
	# on the title screen (and the class picker over it) the hero select's theme plays, not the camp's song
	if not playing and ui != null and ui.title_panel != null and ui.title_panel.visible:
		Sfx.play_music("select")
		return
	if world == null:
		return
	# the camp after dark: tonight's night bed (DayNight, one of five in turn), once the bed exists
	var night_bed := cur_zone == "town" and day_night != null and day_night.on and day_night.night > 0.5
	# the Verdant Reach (the Battlegrounds) has no song: its forest bed alone, not the old synthesized drone, which
	# played under the whole match as a hum and hiss (Blaine, 2026-11-06)
	var song := "" if cur_zone == Battlegrounds.ZONE else cur_zone
	Sfx.play_music(song, "forest" if world.oak_forest and cur_zone != "town" and not indoor() else ("night_forest" if night_bed else ""),
			day_night.night_take() if night_bed else 0)

## The Arena's hall (the Arena and the Sandbox) is indoors; every other zone is under the sky.
func indoor() -> bool:
	return cur_zone == "arena" or cur_zone == Sandbox.ZONE

func _zone_env(kind: String) -> void:
	var inside := kind == "arena" or kind == Sandbox.ZONE
	var snowy := is_snowy() and not inside
	RenderingServer.global_shader_parameter_set("snow_amt", 1.0 if snowy else 0.0)
	weather.set_snow(snowy, quality)
	env.glow_intensity = 0.7
	env.glow_bloom = 0.06
	sun.shadow_blur = 1.5
	grade_look = ""
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
		if kind == Battlegrounds.ZONE:
			# the Hollow Crypt is darker: a smaller circle round the hero, the torches and candles do the rest
			env.ambient_light_energy = 0.55
			env.tonemap_exposure = 1.25
			hero.light.light_energy = 2.0
			hero.light.omni_range = 11.0
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
		if kind == Battlegrounds.ZONE:
			# the Verdant Reach (BgForest): a bright, lush, golden afternoon (Blaine, 2026-11-06: "brighter, more lively").
			# A warm low-ish sun, a deep blue sky, a fill strong enough that the shade under the oaks stays green,
			# saturated colour, a golden haze between the trees, and glow enough for the fireflies, the mushrooms'
			# light and the shrines (ForestLife) to bloom; the camps' coloured lights still read in the shade
			sky_mat.sky_top_color = Color(0.26, 0.5, 0.86)
			sky_mat.sky_horizon_color = Color(0.86, 0.86, 0.72)
			sky_mat.ground_horizon_color = Color(0.5, 0.56, 0.38)
			env.ambient_light_energy = 0.98
			env.tonemap_exposure = 1.14
			env.fog_light_color = Color(0.8, 0.78, 0.58)
			env.fog_density = 0.0032
			env.fog_sky_affect = 0.4
			env.fog_height_density = 0.02
			env.adjustment_saturation = 1.16
			env.adjustment_contrast = 1.06
			env.volumetric_fog_density = 0.009
			env.volumetric_fog_albedo = Color(0.98, 0.9, 0.7)
			env.volumetric_fog_emission = Color(0.02, 0.018, 0.01)
			env.glow_intensity = 0.85
			env.glow_bloom = 0.08
			sun.light_color = Color(1.0, 0.92, 0.77)
			sun.light_energy = 1.32
			sun.shadow_blur = 2.0
			hero.light.light_energy = 0.7
		elif kind == "town" and world.theme.get("forest_camp", false):
			# Act I's camp deep in the old forest: late dusk under the canopy. Cool blue-green light
			# and low mist between the trees, so the bonfire, the lanterns and the rune stones glow
			sky_mat.sky_top_color = Color(0.1, 0.13, 0.17)
			sky_mat.sky_horizon_color = Color(0.24, 0.29, 0.31)
			sky_mat.ground_horizon_color = Color(0.2, 0.24, 0.25)
			# Graphics plan, phase 1 (retuned on a real GPU, 2026-11-01): the first pass (ambient 0.3, moon 0.38,
			# volumetric fog 0.03) was judged in the cloud's software OpenGL renderer and came out far too dark in
			# Forward+, where the volumetric fog, SSAO and SSIL all take light away. A moonlit fill you can see by,
			# thinner mist, and the fire, lanterns and forge still the brightest things (their lights, Grade)
			env.ambient_light_energy = 0.62
			env.tonemap_exposure = 1.5
			env.fog_light_color = Color(0.2, 0.26, 0.29)
			env.fog_density = 0.009
			env.fog_height = 1.2
			env.fog_height_density = 0.1
			env.adjustment_saturation = 0.97
			env.adjustment_contrast = 1.05
			env.volumetric_fog_density = 0.014
			env.volumetric_fog_albedo = Color(0.62, 0.7, 0.72)
			env.volumetric_fog_emission = Color(0.016, 0.022, 0.028)
			env.glow_intensity = 0.95
			env.glow_bloom = 0.1
			sun.light_color = Color(0.58, 0.7, 0.92)
			sun.light_energy = 0.6
			sun.shadow_blur = 2.2
			hero.light.light_energy = 1.7
			hero.light.omni_range = 12.0
			grade_look = "forest_camp"
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
	# the World-Tree Island (CampIsland): real space round the camp instead of the forest's dusk sky; the light keeps
	# the camp's own day (DayNight), its fill a colour now that the sky is black
	var island: bool = kind == "town" and world.island_r > 0.0 and not inside
	if island:
		if space_sky == null:
			space_sky = CampIsland.space_sky()
		env.sky.sky_material = space_sky
		env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		env.ambient_light_color = Color(0.52, 0.58, 0.68)
		env.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
		env.fog_sky_affect = 0.0
	else:
		env.sky.sky_material = sky_mat
	zoom_max = 2.2 if island else 1.3
	zoom = minf(zoom, zoom_max)
	_apply_grade()
	# the camp runs through the day (DayNight); every other zone keeps its own hour
	day_night.enable(kind == "town" and world.theme.get("forest_camp", false) and not inside)

# ---------------------------------------------------------------- grade (graphics plan, phase 1)
## The zone's look from Grade.LOOKS ("" = none): the colour-grading LUT, the vignette and grain, and the hero's rim
## light. The shadow budget (Grade.pick_shadows) runs in _process for any zone whose lights join Grade.SHADOW_GROUP.
var grade_look := ""
var rim: OmniLight3D
var _grade_t := 0.0

func _apply_grade() -> void:
	var lk := Grade.look(grade_look)
	env.adjustment_color_correction = Grade.lut(grade_look) if Grade.grades(lk) else null
	if vignette:
		var vm := vignette.material as ShaderMaterial
		vm.set_shader_parameter("strength", float(lk.get("vignette", 0.6)))
		vm.set_shader_parameter("grain", float(lk.get("grain", 0.0)))
	# the rim: the look's own (the camp), else the zone's kind (Grade.RIMS) so he reads against the ground everywhere
	var rd: Dictionary = lk.get("rim", Grade.RIMS.get(_rim_kind(), {}))
	# the OpenGL renderer (Safe Mode, the browser) ignores a light's cull mask, so there the rim would light the
	# ground round him too: Forward+ only
	if rd.is_empty() or not is_forward():
		if rim:
			rim.visible = false
		return
	if rim == null:
		rim = OmniLight3D.new()
		rim.light_cull_mask = Grade.RIM_LAYER
		rim.shadow_enabled = false
		rim.omni_attenuation = 1.2
		rim.light_specular = 0.6
		add_child(rim)
	rim.visible = true
	rim.light_color = rd["color"]
	rim.light_energy = rd["energy"]
	rim.omni_range = rd["range"]
	_grade_t = 0.0

## Which of Grade.RIMS lights the hero's edge in this zone (when its look has no rim of its own).
func _rim_kind() -> String:
	if world == null:
		return "dusk"
	if not sun.visible:
		return "inside"
	return "dusk"

## Every frame: keeps the rim light behind the hero (away from the camera, above his shoulders); every
## Grade.PICK_EVERY seconds re-picks which lights cast shadows and tags the hero's meshes for the rim.
func _update_grade(delta: float) -> void:
	if hero == null or world == null:
		return
	if rim and rim.visible:
		var away := -cam.global_transform.basis.z
		away.y = 0.0
		away = away.normalized() if away.length() > 0.01 else Vector3(0, 0, -1)
		rim.global_position = hero.global_position + away * 1.6 + Vector3(0, 2.3, 0)
	_grade_t -= delta
	if _grade_t > 0.0:
		return
	_grade_t = Grade.PICK_EVERY
	Grade.pick_shadows(get_tree(), hero.global_position, quality)
	if rim and rim.visible:
		Grade.tag_hero(hero)

const SUN_DEFAULT := Vector3(-52, -38, 0)
## Every zone starts from the default sun, sky floor and view distance (_zone_env then sets its own light).
func _reset_sky() -> void:
	sun.rotation_degrees = SUN_DEFAULT
	sky_mat.ground_bottom_color = Color(0.16, 0.18, 0.15)
	sky_mat.sun_angle_max = 30.0
	cam.far = 300.0

const SETTINGS_PATH := "user://settings.cfg"
const QUALITY_NAMES := ["Low", "Medium", "High", "Ultra"]

## Graphics presets. Integrated laptop GPUs are the usual trouble: volumetric fog and SSIL are
## kept to High and above, and the whole game also runs on the OpenGL renderer (Safe Mode).
func apply_quality(q: int) -> void:
	# Browsers (WebGL) can't allocate the High/Ultra shadow maps; the 3D view goes blank.
	quality = clampi(q, 0, max_quality())
	q = quality
	var forward := is_forward()
	# ambient occlusion: indoors from Medium, outdoors only on Ultra. Godot's SSAO only darkens ambient light, and the
	# outdoor zones are lit by the sun, the moon and fires: without it the camp, the moor and the arena come out the
	# same (fixed-step screenshots: brightness within 0.1-1%, differences no bigger than between two identical runs)
	# while it cost ~7 ms of the GPU frame at High; in the crypt it shows (4.7% darker corners), so indoors keep it
	# (nightly 2026-11-02, docs/nightly/perf/runs/2026-11-02.md)
	env.ssao_enabled = forward and (q >= 3 or (q >= 1 and indoor()))
	env.ssao_radius = 1.2
	env.ssao_intensity = 2.2
	# screen-space indirect light: Ultra only. At High (medium quality, half size) it cost 6-8 ms of the GPU frame
	# (the crypt: 26.6 -> 18.4 ms) and changed nothing that shows: fixed-step screenshots of the camp, moor, crypt,
	# fort and arena with and without it differ no more than two identical runs, brightness within 0.5% (nightly
	# 2026-11-02, docs/nightly/perf/runs/2026-11-02.md)
	env.ssil_enabled = q >= 3 and forward
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
	# LOD switches are kept under a pixel of error (1.0) and half a pixel on Ultra. 0 on Ultra turned LODs off
	# altogether for every model that has them (the statues, the grass's own LODs aside)
	get_viewport().mesh_lod_threshold = 0.5 if q >= 3 else 1.0
	if sun:
		# smooth hand-over between cascades (High and Ultra), then the cascades fitted to the camera
		sun.directional_shadow_blend_splits = q >= 2
		_fit_shadows(true)
	for g in get_tree().get_nodes_in_group("grass"):
		if not g.has_meta("grass3d"):
			(g as MultiMeshInstance3D).visibility_range_end = [32.0, 45.0, 60.0, 95.0][q]
	Grass.apply_quality(self, q)
	apply_render_scale()

## How many pixels the 3D view may draw at most on Low and Medium (High and Ultra draw every pixel). The UI is
## always drawn at the window's full size. A Retina Mac's window has four times the pixels of its size in points
## and the game drew the 3D into all of them: an M5 Pro in the camp ran a steady 21 fps on Medium and 29 on Low
## (telemetry, triage 2026-11-02) where a 1080p screen runs 79 / 94. A 1080p window on Medium is under its cap (unchanged).
const RENDER_PIXEL_CAP := [1600 * 900, 1920 * 1080]
var render_scale_arg := -1.0     # --render-scale N: a fixed 3D scale (KPI comparisons; 2.0 = a Retina screen's cost)

## The 3D view's resolution for the preset and the window, upscaled with FSR 1 (bilinear in Compatibility).
func apply_render_scale() -> void:
	var vp := get_viewport()
	if vp == null or DisplayServer.get_name() == "headless":
		return
	var px := float(get_window().size.x * get_window().size.y)
	var s := 1.0
	if render_scale_arg > 0.0:
		s = render_scale_arg
	elif quality < RENDER_PIXEL_CAP.size() and px > RENDER_PIXEL_CAP[quality]:
		s = clampf(sqrt(RENDER_PIXEL_CAP[quality] / px), 0.5, 1.0)
		if s > 0.9:
			s = 1.0    # (a few percent isn't worth the softening)
	vp.scaling_3d_scale = s
	vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_FSR if s < 1.0 and is_forward() else Viewport.SCALING_3D_MODE_BILINEAR
	vp.fsr_sharpness = 0.3

## Directional shadow cascades fitted to what the camera can see (visual overhaul, stage 1; docs/visual/AUDIT.md).
## The isometric camera looks down from ~24 m: nothing nearer than ~10 m or farther than ~35 m (45 m zoomed out) is
## on screen. Godot's default splits (10/20/50% of 70 m) spent two of the four cascades on empty air in front of the
## lens and the last on ground past the top of the screen, so one 2048 cascade (2.5 cm a texel) covered the whole play
## area; Low and Medium's two splits put it all in one cascade 63 m deep (11 cm a texel). Fitted, the hero stands in
## the middle of his own cascade (2.0 cm on High, 1.0 cm on Ultra, 4.8 cm on Low/Medium), and nothing beyond the view
## is drawn into the shadow maps. Distances follow the zoom.
const SHADOW_FIT_4 := [48.0, 0.3474, 0.6105, 0.7895]   # max distance (m) at zoom 1, then the three split fractions
const SHADOW_FIT_2 := [46.0, 0.6374]
var _shadow_hold := false      # the minimap capture sets its own shadow distance for a few frames
var _shadow_reach := -2.0

func _fit_shadows(force := false) -> void:
	if sun == null or cam == null or _shadow_hold:
		return
	var reach := snappedf(clampf(cam.position.length() / CAM_OFFSET.length(), 0.6, 2.0), 0.05)
	if is_equal_approx(reach, _shadow_reach) and not force:
		return
	_shadow_reach = reach
	if sun.directional_shadow_mode == DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS:
		sun.directional_shadow_max_distance = float(SHADOW_FIT_4[0]) * reach
		sun.directional_shadow_split_1 = float(SHADOW_FIT_4[1])
		sun.directional_shadow_split_2 = float(SHADOW_FIT_4[2])
		sun.directional_shadow_split_3 = float(SHADOW_FIT_4[3])
	else:
		sun.directional_shadow_max_distance = float(SHADOW_FIT_2[0]) * reach
		sun.directional_shadow_split_1 = float(SHADOW_FIT_2[1])

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
uniform float night = 0.0;         // the Wraith's Eternal Night: violet dark closing in from the edges (EternalNightFx.set_night)
uniform float grain = 0.0;         // film grain (Grade.LOOKS): a faint flicker of light and dark specks, new every 1/24 s
float ghash(vec2 p){ return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453); }
void fragment(){
	vec2 uv = UV - 0.5;
	uv.x *= 1.3;
	float v = smoothstep(0.3, 0.85, length(uv));
	float n = smoothstep(0.1, 0.62, length(uv)) * night;
	vec3 col = mix(vec3(0.0), vec3(0.05, 0.02, 0.1), n);
	float a = clamp(v * strength + n * 0.82, 0.0, 1.0);
	if (grain > 0.0) {
		// grain as a light or dark speck over the scene: white or black at a small alpha
		float g = ghash(floor(FRAGCOORD.xy) + floor(TIME * 24.0) * vec2(17.13, 31.71));
		float s = (g - 0.5) * 2.0;
		vec3 cs = vec3(step(0.0, s));          // a light or a dark speck
		float as_ = abs(s) * grain;
		float ao = as_ + a * (1.0 - as_);      // the speck laid over the vignette
		col = (cs * as_ + col * a * (1.0 - as_)) / max(ao, 1e-4);
		a = ao;
	}
	COLOR = vec4(col, a);
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
	# a destination's painting behind the words (set_loading_art; only the Hollow Crypt has one), dimmed so the
	# words read, fading to black at the bottom
	loading_art = TextureRect.new()
	loading_art.set_anchors_preset(Control.PRESET_FULL_RECT)
	loading_art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	loading_art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	loading_art.modulate = Color(0.62, 0.62, 0.62)
	loading_art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	loading_art.visible = false
	loading.add_child(loading_art)
	var art_fade := TextureRect.new()
	var agt := GradientTexture2D.new()
	var agr := Gradient.new()
	agr.set_color(0, Color(0, 0, 0, 0.0))
	agr.set_color(1, Color(0, 0, 0, 0.85))
	agt.gradient = agr
	agt.fill_from = Vector2(0, 0.45)
	agt.fill_to = Vector2(0, 1)
	art_fade.texture = agt
	art_fade.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art_fade.stretch_mode = TextureRect.STRETCH_SCALE
	art_fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	art_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	loading_art.add_child(art_fade)
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
	match zone:
		"town": return str(Data.ACTS[act]["town"])
		Battlegrounds.ZONE: return Battlegrounds.map_title()
		"arena": return "The Proving Arena"
		Sandbox.ZONE: return Sandbox.TITLE
	return ""

## The zone's felled trees into the save's record (the host's forest is the one that counts in co-op).
func _harvest_key() -> String:
	return "%d:%d:%s" % [difficulty, cur_act, str(cur_zone)]

func _store_harvest() -> void:
	if world == null or net.is_client():
		return
	var h := Harvest.of(world)
	if h == null:
		return
	var d := h.to_save()
	if d.is_empty():
		harvest_saved.erase(_harvest_key())
	else:
		harvest_saved[_harvest_key()] = d

func _restore_harvest() -> void:
	var h := Harvest.of(world)
	if h == null or net.is_client():
		return
	h.from_save(harvest_saved.get(_harvest_key(), {}), played_s)

## The boot's files (ResCache, "boot" scope): the home screen's models, read on the loader's threads at boot.
## Released once the title is up (the title's own nodes hold them).
const TITLE_MODELS := ["res://assets/models/title/gate.glb", "res://assets/models/title/arcade.glb",
	"res://assets/models/title/colossus.glb", "res://assets/models/title/crown.glb"]
var _zone_scope := ""

func _boot_preload() -> void:
	ResCache.prepare("boot", TITLE_MODELS)

## Waits (a frame at a time, so the screen stays alive) until the boot's files are in, at most max_s.
func _await_preloads(max_s := 30.0) -> void:
	await ResCache.wait_ready(get_tree(), "boot", max_s, func(f: float): loading_lbl.text = "Loading... %d%%" % int(100.0 * f))

func _release_preloads() -> void:
	ResCache.release("boot")

func load_zone(act: int, zone: String, spawn: String, at = null) -> void:
	if _busy:
		return
	_busy = true
	net.broadcast_goto(act, zone, spawn, at)
	loading_lbl.text = ("Descending into %s..." if zone == Battlegrounds.ZONE else "Entering %s...") % zone_title(act, zone)
	set_loading_art(zone)
	loading.visible = true
	# the zone's recorded files on the loader's threads (ResCache), while the old zone goes; the build waits for them
	var scope := "zone:%s:%d" % [zone, Time.get_ticks_usec()]
	ResCache.prepare(scope, ZonePreloadData.PATHS.get(ZonePreload.key(difficulty, zone), []))
	await get_tree().process_frame
	await get_tree().process_frame
	if world:
		_store_harvest()
		# the hero's lingering skill effects (Hero.fxs) live in this zone's fx_root: drop them with it, as a puppet's
		# are (Hero.net_zone_reset); Molten Fists' update touched its freed nodes every frame after a trip
		if hero != null:
			SkillFx.clear(hero)
		world.queue_free()
		world = null
		hovered = null
		await get_tree().process_frame
	ResCache.release(_zone_scope)          # (the zone left: its files go unless the new one lists them too)
	_zone_scope = scope
	await ResCache.wait_ready(get_tree(), scope, 20.0)
	Telemetry.crumb("enter", {"to": zone, "run": difficulty})
	ui.close_all()             # (a trader, a stash or a waypoint list belongs to the zone being left)
	cur_act = act
	cur_zone = zone
	World.detail = quality
	world = World.new()
	world.name = "World"
	world.oak_forest = true                # Act I's old forest: its grass, leaf litter and birds
	world.living_grass = true              # the living grass everywhere outdoors
	add_child(world)
	# the seed: the camp's 4200, every other zone 4193 (as when the story's zones sat between them in the sum)
	world.build(act, zone, 4200 + act * 101 + (0 if zone == "town" else -7))
	ResCache.prepare(scope, _monster_paths())     # (on the threads while the minimap is drawn)
	_restore_harvest()
	_reset_sky()
	_end_underworld_now()
	_zone_env(zone)
	_grass_zone(zone)
	apply_quality(quality)
	await _capture_map(zone)
	# a waypoint's own arrival spot ("waypoint_<id>"), else the zone's main waypoint, else the start
	var sp: Vector3 = world.spawns.get(spawn, world.spawns.get("waypoint", world.spawns["start"]) if spawn.begins_with("waypoint") else world.spawns["start"])
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
			var se = spawn_enemy(es["kind"], p, int(es["level"]), es["champ"], champ_name, int(es["pack"]))
			if se != null and (es.has("life_k") or es.has("dmg_k")):
				# a camp's own tuning (Camps: its boss against run characters)
				se.max_life *= float(es.get("life_k", 1.0))
				se.life = se.max_life
				var dk := float(es.get("dmg_k", 1.0))
				se.dmg = [se.dmg[0] * dk, se.dmg[1] * dk]
				se.xp = int(se.xp * float(es.get("xp_k", 1.0)))
	if OS.get_cmdline_user_args().has("--preload-record"):
		ZonePreload.record(world, difficulty, zone)
	if zone == "town":
		_stock_shops()
		if not tp_link.is_empty():
			_make_portal(world.spawns["portal"], "back")
	ui.set_zone(zone_title(act, zone))
	# Act I outdoors: birds over the forest (birds.gd). Not over the Battlegrounds: in its bright afternoon their
	# flapping shadows pulsed over the ground and a flock bursting from the trees fluttered every half minute, with
	# the birds themselves hard to see from the camera, so it read as a glitch (Blaine, 2026-11-06)
	if world.oak_forest and not indoor() and not net.server:
		if zone != Battlegrounds.ZONE:
			var birds := Birds.new()
			birds.game = self
			birds.name = "birds"
			world.add_child(birds)
		# the camp's ravens on the roofs and the ground (camp_ravens.gd)
		if zone == "town" and world.has_meta("roosts"):
			CampRavens.add_to(world)
			CampSocial.add_to(world)
	# the class's skill effects played once, unseen, under the loading screen: no freeze on a first cast (SkillWarm)
	await SkillWarm.run(self)
	# the monsters that can still turn up here (MonsterWarm), the windows and the sheet's portrait, drawn once
	await MonsterWarm.run(self)
	await ui.warm_windows()
	zone_music()
	loading.visible = false
	_busy = false
	net.host_zone_loaded()
	_start_watch()
	if playing and shot_path == "":
		save_game()

## The zone's monsters' models, loaded on worker threads while the minimap is drawn (load_zone): each first load
## of a kind's model was 23-34 ms on the main thread (nightly 2026-11-03).
func _monster_paths() -> Array:
	var kinds := {}
	for es in (world.enemy_spawns if not net.is_client() else []):
		kinds[str(es["kind"])] = true
	for k in MonsterWarm.kinds(self):       # (and what can still turn up here: MonsterWarm builds those)
		kinds[k] = true
	var out: Array = []
	for k in kinds:
		for p in Enemy.model_paths(k):
			if not out.has(p):
				out.append(p)
	return out

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
	me.ambient_light_color = Color(0.62, 0.65, 0.6)
	me.ambient_light_energy = 0.75
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
	_shadow_hold = true
	sun.directional_shadow_max_distance = 400.0
	add_child(vp)
	mc.current = true
	for i in 3:
		await get_tree().process_frame
	var img := vp.get_texture().get_image()
	vp.queue_free()
	sun.directional_shadow_max_distance = old_shadow
	_shadow_hold = false
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

## The living grass (Act I, outdoors): its wind for the zone, and its touch on.
func _grass_zone(zone: String) -> void:
	if grass_field == null or world == null:
		return
	grass_field.enabled = (world.oak_forest or world.living_grass) and not indoor() and not net.server
	var w := "default"
	if indoor():
		w = "calm"
	elif zone == "town":
		w = "camp"
	grass_field.set_wind(w, 0.05)
	grass_field.center = hero.global_position if hero else Vector3.ZERO

## Everyone who parts the grass: the hero and partners, their pets and summoned demons, and the monsters.
func _grass_movers() -> Array:
	var out: Array = []
	if world == null:
		return out
	var heroes: Array = [hero] if hero else []
	heroes.append_array(net.puppets())
	for h in heroes:
		if not is_instance_valid(h):
			continue
		out.append(h)
		for b in h.beasts:
			out.append(b)
	for e in world.enemies_root.get_children():
		out.append(e)
	return out

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

## Every knight in the area: yours plus your partners'.
func all_heroes() -> Array:
	var out := [hero]
	if net.active:
		out.append_array(net.puppets())
	if sandbox != null:
		out.append_array(sandbox.bot_heroes())
	return out

## Monsters go after the nearest knight that is still standing.
func target_for(e: Node3D) -> Hero:
	if sandbox != null:
		return sandbox.nearest_hero(e.global_position)
	if not net.active:
		return hero
	var best: Hero = hero
	var bd := INF
	for h in all_heroes():
		if h.dead or (h.puppet and not h.net_has) or (net.server and h == hero):
			continue
		var d: float = h.global_position.distance_squared_to(e.global_position)
		if h.invis_t > 0.0 or h.net_invis:
			d += 1e6       # unseen (a Shadow Phial): the monster goes for anyone it can see first
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
	# chosen while the camp was still building behind the title: let it finish first
	while _busy:
		await get_tree().process_frame
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
		played_s = 0.0
		harvest_saved = {}
		quests.from_save({})
		waypoints_known = ["town"]
		boss_killed = false
		tp_link = {}
		await load_zone(0, "town", "new_player")
		ui.open_dialog(Data.VENDORS["elder"], "Welcome to the Forsaken Wilds, %s. The gates are barred: the moor beyond them belongs to the dead now. Trade with our folk, then step onto the waypoint at the heart of the camp. It takes you down to the Battlegrounds, where the camps of the old forest hold skills, rites and gems for whoever can take them." % ("restless one" if hero.is_wraith() else ("pact-bound one" if hero.is_warlock() else "crusader")), [["I will", func(): pass]])
	ui.refresh()

## Co-op from the title screen. Your last character is used if you have one.
func start_host(id := "") -> void:
	await start_game(not list_characters().is_empty(), "knight", id)
	var err := net.host()
	if err != OK:
		ui.big_message("Could not host")
		ui.message("Another program may be using port %d" % Net.PORT, Color(1, 0.5, 0.4))
	else:
		ui.message("Hosting! Your partner can now pick Join Co-op Game", Color(0.5, 1.0, 0.5))

func start_join(ip: String, id := "") -> void:
	while _busy:
		await get_tree().process_frame
	Sfx.play("click")
	net.stop_listening()
	ui.hide_title()
	playing = true
	var chars := list_characters()
	char_id = id if id != "" else (str(chars[0]["id"]) if not chars.is_empty() else new_char_id())
	if Survivors.is_survivor(char_id):
		# the Arena with a saved survivor: its real skills, passives, level and gear (Survivors.load_into)
		if not Survivors.load_into(self, char_id):
			on_net_failed("That survivor's save could not be read.")
			return
	elif not load_game():
		char_name = default_name(hero.cls)
		hero.new_character()
	net_joining = true      # (until the host welcomes us: Net.cl_welcome)
	var addr: Array = Battlegrounds.parse_address(ip)      # "host" or "host:port" (the online co-op server)
	loading_lbl.text = "Joining game at %s..." % ip
	loading.visible = true
	if net.join(str(addr[0]), int(addr[1])) != OK:
		on_net_failed("Could not connect to that game.")
		return
	await get_tree().create_timer(8.0).timeout
	if net.is_client() and net.players.is_empty() and loading.visible and not _busy:
		net.shutdown()
		on_net_failed(net.join_failure("No answer from %s. Check the host's game is running and Windows Firewall allowed it." % ip))

## A friend's world through Steam (SteamLink: their invite or "Join Game"): our chosen character joins the friend
## `owner` (a Steam ID) the way a LAN join does, over Steam's relay.
func start_join_steam(owner: int) -> void:
	while _busy:
		await get_tree().process_frame
	Sfx.play("click")
	net.stop_listening()
	ui.hide_title()
	playing = true
	var chars := list_characters()
	var id: String = ui.home.sel if ui.home != null and ui.home.sel != "" else ""
	char_id = id if id != "" else (str(chars[0]["id"]) if not chars.is_empty() else new_char_id())
	if not load_game():
		char_name = default_name(hero.cls)
		hero.new_character()
	net_joining = true      # (until the host welcomes us: Net.cl_welcome)
	loading_lbl.text = "Joining your friend's world..."
	loading.visible = true
	var p: MultiplayerPeer = steam.client_peer(owner)
	if p == null or net.join_with(p) != OK:
		on_net_failed("Steam couldn't connect to your friend's world.")
		return
	await get_tree().create_timer(15.0).timeout
	if net.is_client() and net.players.is_empty() and loading.visible and not _busy:
		net.shutdown()
		on_net_failed(net.join_failure("Your friend's world didn't answer. Ask them to invite you again."))

## Into a raid (the lobby browser hands over its match server's address): the raider is a fresh run character
## (RunBuild, level 0) of `cls`, or of character `id`'s class when none is given; that character's save isn't touched.
func start_battlegrounds(addr: String, id: String, cls := "") -> void:
	while _busy:
		await get_tree().process_frame
	await _start_run_raid(addr, id, cls)

func _start_run_raid(addr: String, id: String, cls: String) -> void:
	Telemetry.crumb("raid", {"server": addr, "run": true})
	bg_refusal = ""
	bg_wait_until = 0
	Sfx.play("click")
	net.stop_listening()
	if cls == "" and id != "":
		var d := read_save(char_dir + id + ".json", false)
		cls = str(d.get("hero", {}).get("cls", "")) if d is Dictionary else ""
	if not Data.CLASSES.has(cls):
		cls = hero.cls if hero != null and Data.CLASSES.has(hero.cls) else "archer"
	char_id = ""
	char_name = Data.CLASSES[cls]["name"]
	bg_gained = -1
	if run_results_open:
		ui.run_ui.close(true)      # (a new run from the last one's results)
	run_results_open = false
	run_survived = false
	hero.set_class(cls)
	hero.start_run()
	ui.hide_title()
	ui.close_all()
	playing = true
	bg_mode = true
	bg_raid = {}
	bg_roster = []
	var a: Array = Battlegrounds.parse_address(addr)
	_save_setting("battlegrounds", "address", addr.strip_edges())
	_save_setting("battlegrounds", "class", cls)
	if cloud != null and not await cloud.ensure():
		_bg_abort("Could not sign in to your account (%s)." % cloud.nk.last_error)
		return
	loading_lbl.text = "Entering %s..." % Battlegrounds.map_title()
	set_loading_art(Battlegrounds.ZONE)
	loading.visible = true
	if net.join(a[0], int(a[1])) != OK:
		on_net_failed("Could not reach the Battlegrounds server.")
		return
	await get_tree().create_timer(8.0).timeout
	if bg_mode and net.is_client() and loading.visible and not _busy and cur_zone != Battlegrounds.ZONE:
		net.shutdown()
		on_net_failed(net.join_failure("No answer from the Battlegrounds server at %s." % a[0]))

## The raid server turned us away (Net.cl_bg_refused): too late into the round, or the account. For a closed raid,
## the join failure says when the next one opens (Net.join_failure, bg_wait_text).
func bg_refused(why: String, secs: float) -> void:
	bg_refusal = why
	bg_wait_until = Time.get_ticks_msec() + int((secs + 1.5) * 1000.0) if why == "closed" else 0

func bg_wait_text() -> String:
	var s := maxi(0, (bg_wait_until - Time.get_ticks_msec()) / 1000)
	return "%d:%02d" % [s / 60, s % 60]

## The painting behind the loading screen's words: the Hollow Crypt's on the way down into it (Data.WAYPOINT_BATTLEGROUNDS
## "wide"), black for every other zone, as it always was.
func set_loading_art(zone: String) -> void:
	if loading_art == null:
		return
	var tex: Texture2D = null
	if zone == Battlegrounds.ZONE:
		for b in Data.WAYPOINT_BATTLEGROUNDS:
			var p := str(b.get("wide", ""))
			if p != "" and ResourceLoader.exists(p):
				tex = load(p)
				break
	loading_art.texture = tex
	loading_art.visible = tex != null

## The server let us out: what we carry is ours, saved to the character as it is.
## The crypt never let us in (sign-in failed before the character was marked in_raid): back to the Battlegrounds
## screen, the character as it was; from the camp's waypoint, the hero simply hasn't left.
func _bg_abort(msg: String) -> void:
	if lobby_client != null and lobby_client.match_id != "":
		lobby_client.finished(msg)
		return
	bg_mode = false
	loading.visible = false
	if net.active:
		net.shutdown()
	await exit_to_title()
	ui.open_battlegrounds()
	ui.big_message("Couldn't enter the crypt")
	ui.message(msg, Color(1, 0.6, 0.4))

func bg_extracted(gained: Array) -> void:
	if hero.run != null:
		# a run character made it out: the results, with Save Character (Survivors); the server confirmed the exit
		# (Net.sv_extract checks the portal is open and the player at it)
		run_survived = true
		Sfx.play("portal")
		ui.big_message("Extracted!")
		await get_tree().create_timer(1.0).timeout
		_leave_battlegrounds()
		return
	bg_mode = false
	bg_gained = gained.size()
	save_game()
	ui.big_message("Extracted!")
	ui.message("%s made it out with %d new item%s" % [char_name, gained.size(), "" if gained.size() == 1 else "s"], Color(0.6, 1.0, 0.6))
	Sfx.play("portal")
	await get_tree().create_timer(2.0).timeout
	_leave_battlegrounds()

## The local hero fell in the crypt: everything on them goes to the server to drop where they fell.
func _bg_fell() -> void:
	var items := []
	for slot in hero.equipment:
		if hero.equipment[slot] != null:
			items.append(hero.equipment[slot])
	for it in hero.inventory + hero.belt:
		if it != null:
			items.append(it)
	if hero.gold > 0:
		items.append(Items.gold(hero.gold))
	if net.is_client():
		net.send_bg_died(items)
	ui.big_message("%s has fallen" % char_name)
	ui.message("Everything %s wore and carried lies where they fell. Their strength remains." % char_name, Color(1, 0.45, 0.35), 6.0)

## What a hero keeps after dying in the crypt: levels, stats, talents, the camp's stash, and nothing else but a
## plain weapon of their class (so they can walk back into the world). The save is written at once.
static func strip_save(h: Dictionary) -> Dictionary:
	var cls := str(h.get("cls", "knight"))
	var eq := {}
	for slot in Items.EQUIP_SLOTS:
		eq[slot] = null
	eq["weapon"] = Items.make(str(Data.CLASSES.get(cls, {}).get("weapon", "hand_axe" if cls == "demon" else "short_sword")))
	var inv := []
	inv.resize(40)
	h["equipment"] = eq
	h["inventory"] = inv
	h["belt"] = [null, null, null, null]
	h["gold"] = 0
	return h

func bg_strip() -> void:
	if char_id == "":
		return
	if hero.dead:
		hero.respawn(hero.global_position)
	var h := strip_save(hero.to_save())
	hero.equipment = h["equipment"]
	hero.inventory = h["inventory"]
	hero.belt = h["belt"]
	hero.gold = 0
	hero.refresh_gear()
	hero.recalc()
	bg_mode = false
	save_game()
	print("[BG] character ", char_id, " died in the crypt and lost everything it carried")

## The results window's Return: to the title and the lobby browser (a run character is never saved as a
## single-player character; a survivor was saved by its own button).
func run_return() -> void:
	ui.run_ui.close(true)
	run_results_open = false
	run_survived = false
	bg_mode = false
	if lobby_client != null:
		lobby_client.match_id = ""
		lobby_client.room = {}
	await exit_to_title()
	hero.new_character()      # (the run is over: what was on the hero is gone unless it was saved as a survivor)
	if lobby_client != null:
		lobby_client.open("battlegrounds")
	else:
		ui.open_battlegrounds()

## Save Character on the results (once per run: Survivors.save keys on the run's uid).
func run_save_survivor() -> Array:
	if hero.run == null or not run_survived:
		return ["", false]
	return Survivors.save(hero, char_name)

## Characters whose game closed while they were in a raid died there: they lose what they carried.
func _bury_lost_raiders() -> void:
	if _testing():
		return
	for c in list_characters():
		var p := char_dir + str(c["id"]) + ".json"
		var d = JSON.parse_string(FileAccess.get_file_as_string(p))
		if d is Dictionary and bool(d.get("in_raid", false)):
			d["hero"] = strip_save(d.get("hero", {}))
			d["in_raid"] = false
			var f := FileAccess.open(p, FileAccess.WRITE)
			if f:
				f.store_string(JSON.stringify(d))
				f.close()
			if cloud != null:
				cloud.push(str(c["id"]), d)
			ui.message("%s fell in %s and lost everything they carried" % [str(c["name"]), Battlegrounds.map_title()], Color(1, 0.5, 0.4), 6.0)

## Out of the crypt, extracted, fallen or cut off: a raid taken from the title screen ends on its Battlegrounds
## window; one taken from the camp's waypoint (bg_from_waypoint) ends back on the dais, see _bg_home_camp.
## A run's results are showing (RunUI.open_results) until the player returns to the lobby browser (run_return).
var run_survived := false
var run_results_open := false

func _leave_battlegrounds() -> void:
	if not bg_mode and char_id == "" and not playing:
		return
	if hero.run != null and MpMode.RUNS and not run_results_open:
		# a run ends on its results: survived (Save Character) or fallen (nothing to keep); the raid's connection
		# closes, the world stays behind the window until the player goes back to the lobby browser
		run_results_open = true
		bg_mode = false
		if net.active:
			net.shutdown()
		if hero.dead:
			run_survived = false
		death_t = -1.0
		ui.death_panel.visible = false
		spectate_stop()
		ui.set_boss(null)
		ui.close_all()
		ui.run_ui.open_results(run_survived)
		return
	var fell := hero.dead and bg_mode
	if fell:
		bg_strip()
	bg_mode = false
	bg_raid = {}
	bg_roster = []
	await exit_to_title()
	ui.open_battlegrounds()

func on_net_failed(msg: String) -> void:
	if steam != null:
		steam.close_world()
	if lobby_client != null and lobby_client.match_id != "":
		lobby_client.finished(msg)
		return
	party_join_ticket = ""
	if party_join_pending:
		party_join_pending = false
		net_joining = false
		loading.visible = false
		ui.message(msg + " Your solo adventure is still open.", Color(1, 0.7, 0.45), 7.0)
		return
	if net_joining:
		# a co-op join that never got in: back to the co-op screen
		net_joining = false
		ui.big_message("Couldn't join")
		ui.message(msg, Color(1, 0.6, 0.4))
		loading.visible = false
		await exit_to_title()
		ui.open_join()
		return
	if bg_mode:
		ui.big_message("The raid is closing" if bg_wait_until > Time.get_ticks_msec() else "Left the Battlegrounds")
		ui.message(msg, Color(1, 0.6, 0.4))
		loading.visible = false
		_leave_battlegrounds()
		return
	ui.big_message("Co-op ended")
	ui.message(msg, Color(1, 0.6, 0.4))
	loading.visible = false
	if playing:
		await load_zone(cur_act, "town", "start")
		if hero.dead:
			hero.respawn(hero.global_position)

## Testing switches (the Escape menu's Admin column, only while dev_tools is on). They change nothing else
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

## Signs in to Nakama and syncs the characters (the first run uploads every local one); the title screen then
## shows what came down from other devices.
func _cloud_start() -> void:
	await get_tree().process_frame
	if await cloud.sync() and ui.title_idle() and not playing:
		_bury_lost_raiders()
		_stash_start()
		ui.show_title()

# ---------------------------------------------------------------- the shared stash (SharedStash)
## Where the stash opens: the camp's chest; never in the Battlegrounds, the sandbox or on a server.
func stash_allowed() -> bool:
	return stash != null and sandbox == null and not net.server and not bg_mode

## The bag's item `inv_idx` into the stash's tab (or the first tab with room). Three saves: the character with the
## item stamped (still in the bag), the stash with it, the character without it. A crash after the first leaves it
## only in the bag; after the second, in both, stamped alike, and SharedStash.reconcile keeps the stash's copy.
func stash_deposit(inv_idx: int, tab: int) -> bool:
	if not stash_allowed() or inv_idx < 0 or inv_idx >= hero.inventory.size():
		return false
	var it = hero.inventory[inv_idx]
	if not (it is Dictionary):
		return false
	stash.fresh()
	var t := tab
	var slot := stash.free_slot(t)
	if slot < 0:
		for k in SharedStash.TABS:
			slot = stash.free_slot(k)
			if slot >= 0:
				t = k
				break
	if slot < 0:
		ui.message("The stash is full", Color(1, 0.6, 0.4))
		return false
	SharedStash.stamp(it)
	save_game()
	stash.tabs[t][slot] = it
	if not stash.save():
		stash.tabs[t][slot] = null
		ui.message("The stash couldn't be saved", Color(1, 0.5, 0.4))
		return false
	hero.inventory[inv_idx] = null
	save_game()
	return true

## A stash item into the bag: the character is saved first (with the item), then the stash (without it).
func stash_withdraw(tab: int, slot: int) -> bool:
	if not stash_allowed():
		return false
	stash.fresh()
	var it = stash.tabs[tab][slot]
	if not (it is Dictionary):
		return false
	var j := hero.inventory.find(null)
	if j < 0:
		ui.message("Your bag is full", Color(1, 0.6, 0.4))
		return false
	hero.inventory[j] = it
	save_game()
	stash.tabs[tab][slot] = null
	stash.save()
	return true

## The loaded hero against the stash: a copy a crash left behind is taken out, and a character's own stash from
## before the shared one moves in (stamped and saved first, so it can't come in twice).
func _stash_fix_hero() -> void:
	if stash == null:
		return
	stash.fresh()
	var h := {"equipment": hero.equipment, "inventory": hero.inventory, "belt": hero.belt, "stash": hero.stash}
	var n := stash.reconcile(h)
	var old := hero.stash.filter(func(x): return x is Dictionary)
	if not old.is_empty():
		for it in old:
			if not it.has("uid"):
				SharedStash.stamp(it)
		save_game()
		stash.adopt(hero.stash)
		n += stash.reconcile(h)
	if n > 0:
		hero.recalc()
		save_game()

## Every character file against the stash, before any is played (start, after a cloud sync): their old stashes
## move in, and copies a crash left behind come out.
func _stash_start() -> void:
	if stash == null or _testing():
		return
	stash.fresh()
	for c in list_characters():
		var p := char_dir + str(c["id"]) + ".json"
		var d = JSON.parse_string(FileAccess.get_file_as_string(p))
		if not (d is Dictionary) or not (d.get("hero") is Dictionary):
			continue
		var h: Dictionary = d["hero"]
		var changed := false
		var old: Array = h.get("stash", []) if h.get("stash") is Array else []
		var stamped := false
		for it in old:
			if it is Dictionary and not it.has("uid"):
				SharedStash.stamp(it)
				stamped = true
		if stamped:
			_write_char(p, str(c["id"]), d)
		if old.any(func(x): return x is Dictionary):
			stash.adopt(old)
		if stash.reconcile(h) > 0:
			changed = true
		if changed:
			_write_char(p, str(c["id"]), d)

## A stash chest opening (jj: "the lock really unlocked, opening the stash is a big deal"). The chest's parts split
## off the Meshy model in Blender: "lock" (the padlock) and "lid" (with its hasp; pivot on the back hinge). Opening:
## the padlock rattles, springs open with a clank and sparks and drops to hang askew; then the lid heaves back
## past LID_OPEN and settles, a warm light floods up out of it, motes and a soft beam rise, and the camera bumps for
## the one who opened it. Shutting: the lid drops, the lock swings back. Chests without the parts only glow.
const LID_OPEN := -102.0
func chest_lid(t: Inter, open: bool, mine := true) -> void:
	if not is_instance_valid(t):
		return
	var lid: Node3D = t.find_child("lid", true, false) as Node3D
	var lock: Node3D = t.find_child("lock", true, false) as Node3D
	var lift: float = float(t.get_meta("lift", 0.0))         # (a chest on a dais, Battlegrounds._stash_chest)
	var top: Vector3 = t.global_position + Vector3(0, 0.75 + lift, 0)
	var root: Node3D = world.fx_root if world != null else t
	if lock != null:
		if not lock.has_meta("rest"):
			lock.set_meta("rest", [lock.position, lock.rotation_degrees])
		var rest: Array = lock.get_meta("rest")
		var lt := lock.create_tween()
		if open:
			# a rattle, then the shackle springs: it drops and swings open on the hasp
			for k in 3:
				lt.tween_property(lock, "rotation_degrees:z", float(rest[1].z) + (9.0 if k % 2 == 0 else -9.0), 0.04)
			lt.tween_property(lock, "position", (rest[0] as Vector3) + Vector3(0, -0.07, 0.03), 0.08)
			lt.parallel().tween_property(lock, "rotation_degrees", (rest[1] as Vector3) + Vector3(18, 0, 38), 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		else:
			lt.tween_property(lock, "position", rest[0], 0.2)
			lt.parallel().tween_property(lock, "rotation_degrees", rest[1], 0.2)
		# the shackle (its own part on the rebuilt chest): it springs open on its hinge leg as the lock gives
		var sh: Node3D = lock.find_child("shackle", true, false) as Node3D
		if sh != null:
			sh.create_tween().tween_property(sh, "rotation_degrees:z", 55.0 if open else 0.0, 0.12 if open else 0.2).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	if lid != null:
		var tw := lid.create_tween()
		if open:
			tw.tween_interval(0.26 if lock != null else 0.0)
			tw.tween_property(lid, "rotation_degrees:x", LID_OPEN * 1.12, 0.32).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
			tw.tween_property(lid, "rotation_degrees:x", LID_OPEN, 0.18).set_trans(Tween.TRANS_SINE)
		else:
			tw.tween_property(lid, "rotation_degrees:x", 0.0, 0.22).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	var glow: OmniLight3D = t.get_node_or_null("lid_glow")
	if open and glow == null:
		# (jj: "real shadows from the light") the light rises out of the open chest just over its rim, so its walls,
		# the raised lid and whoever stands at it throw real shadows over the floor; first in the shadow budget
		glow = OmniLight3D.new()
		glow.name = "lid_glow"
		glow.light_color = Camps.chest_col("lid")
		glow.omni_range = 8.0
		glow.omni_attenuation = 1.1
		glow.light_energy = 0.0
		glow.shadow_enabled = true
		glow.shadow_blur = 1.2
		glow.shadow_bias = 0.06
		glow.position = Vector3(0, 1.02 + lift, 0.15)
		glow.set_meta("shadow_pri", true)
		glow.add_to_group(Grade.SHADOW_GROUP)
		t.add_child(glow)
	if glow != null:
		var gt := glow.create_tween()
		if open:
			gt.tween_interval(0.3)
			gt.tween_property(glow, "light_energy", 6.0, 0.15)
			gt.tween_property(glow, "light_energy", 3.0, 0.6)
			# and it flickers like the fire in it
			var fl := glow.create_tween().set_loops()
			fl.tween_interval(1.1)
			fl.tween_callback(func():
				if is_instance_valid(glow) and bool(t.get_meta("lid_open", false)):
					glow.create_tween().tween_property(glow, "light_energy", randf_range(2.5, 3.5), 0.09))
			fl.tween_interval(0.09)
			glow.set_meta("flicker", fl)
		else:
			if glow.has_meta("flicker"):
				(glow.get_meta("flicker") as Tween).kill()
				glow.remove_meta("flicker")
			gt.tween_property(glow, "light_energy", 0.0, 0.3)
	if open:
		# the raid's chest has its own sound, lock, lid and fire in one (jj; "chest_raid_open", tools/audio/spec.py)
		var raid_snd: bool = bool(t.data.get("raid", false)) and Sfx.bank.has("chest_raid_open")
		if raid_snd:
			Sfx.play_at("chest_raid_open", top)
		else:
			Sfx.play_at("chest_unlock" if Sfx.bank.has("chest_unlock") else "anvil", top + Vector3(0, -0.2, 0.4), -6.0, 1.25)
		# the unlock: sparks at the hasp
		Fx.burst(root, t.global_position + Vector3(0, 0.6 + lift, 0.6), Camps.chest_col("spark"), 14, 2.2, 0.018, 0.45, false, -6.0, 70.0, Vector3(0, 0.4, 1))
		var raid: bool = bool(t.data.get("raid", false))
		Fx.later(t, 0.26, func():
			if not raid_snd:
				Sfx.play_at("chest_open" if Sfx.bank.has("chest_open") else "portcullis" if Sfx.bank.has("portcullis") else "inv_click", top, -8.0, 1.4)
			if not raid:
				# the camp's chest: a warm breath of light
				Fx.flash(root, top, Color(1.0, 0.72, 0.35), 3.0, 0.5, 4.0)
				Fx.burst(root, top, Color(1.0, 0.6, 0.25, 0.8), 16, 1.2, 0.04, 1.2, true, 1.0, 25.0)
			if mine and hero != null and hero.global_position.distance_to(t.global_position) < 6.0:
				add_shake(0.18))
	if open:
		_burst_seals(t)
	t.set_meta("lid_open", open)

## The gold wolf seals tear off the chest as it opens (jj): each flies out from its face, spinning and climbing,
## trailing gold sparks, flares and burns out in the air; the seals' light dies with them.
func _burst_seals(t: Inter) -> void:
	var seals := t.find_children("seal_*", "MeshInstance3D", true, false)
	if seals.is_empty() or world == null:
		return
	var root: Node3D = world.fx_root
	var c := t.global_position
	var flash_c: Color = Camps.chest_col("seal_flash")
	var spark_c: Color = Camps.chest_col("seal_spark")
	var trail_c: Color = Camps.chest_col("seal_trail")
	for i in seals.size():
		var s: MeshInstance3D = seals[i]
		var delay := 0.08 + i * 0.05
		Fx.later(t, delay, func():
			if not is_instance_valid(s):
				return
			var gp := s.global_transform
			s.get_parent().remove_child(s)
			root.add_child(s)
			s.global_transform = gp
			var sm := s.material_override as ShaderMaterial
			if sm:
				sm.set_shader_parameter("energy", 2.6)
			var out := Vector3(s.global_position.x - c.x, 0, s.global_position.z - c.z)
			out = out.normalized() if out.length() > 0.01 else Vector3(0, 0, 1)
			Fx.flash(root, s.global_position, flash_c, 1.6, 0.3, 3.0)
			Fx.burst(root, s.global_position, spark_c, 16, 2.4, 0.025, 0.5, false, -4.0, 50.0, out)
			Fx.aura(s, trail_c, 14, 0.3, 0.018, 0.45, -0.5, 0.05, 40.0, Vector3.ZERO, false)
			var v := out * randf_range(3.0, 4.2) + Vector3(0, randf_range(3.2, 4.5), 0)
			var w := Vector3(randf_range(-9, 9), randf_range(-12, 12), randf_range(-9, 9))
			InfernalFx.fly(s, v, w, 1.15, -7.0, true)
			var s_ref: WeakRef = weakref(s)      # (it frees itself at the end of its flight: no strong capture)
			Fx.later(root, 1.0, func():
				var seal: Node3D = s_ref.get_ref() as Node3D
				if seal != null:
					Fx.flash(root, seal.global_position, flash_c, 4.0, 0.4, 4.0)
					Fx.burst(root, seal.global_position, spark_c, 22, 2.0, 0.03, 0.6, false, -3.0, 180.0)))
	var gl: OmniLight3D = t.find_child("seal_glow", true, false) as OmniLight3D
	if gl:
		var tw := gl.create_tween()
		tw.tween_property(gl, "light_energy", 5.0, 0.12)
		tw.tween_property(gl, "light_energy", 0.0, 0.9)

func _write_char(p: String, id: String, d: Dictionary) -> void:
	var f := FileAccess.open(p, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(d))
		f.close()
	if cloud != null:
		cloud.push(id, d)

func save_game() -> void:
	if arena_mode or sandbox != null: return # Practice and Arena use a temporary copy; only escrow settlement changes owned items.
	if hero != null and hero.run != null:
		return      # (a run character is saved only as a survivor, at a successful exit: Survivors)
	if char_id == "" and not _testing():
		return
	_store_harvest()
	var raid_admitted: bool = bg_mode and (lobby_client == null or lobby_client.match_id == "" or lobby_client.admitted)
	var d := {"hero": hero.to_save(), "in_raid": raid_admitted, "act": cur_act, "waypoints": waypoints_known, "boss": boss_killed,
		"difficulty": 0, "quests": quests.to_save(), "harvest": {"t": played_s, "zones": harvest_saved}, "name": char_name, "played": int(Time.get_unix_time_from_system() * 1000.0)}
	var old_lobby_save: Dictionary = load("res://game/ui/lobby/lobby_stakes.gd").read(save_path())
	d["lobby_receipts"] = old_lobby_save.get("lobby_receipts", [])
	d["lobby_locked"] = old_lobby_save.get("lobby_locked", [])
	DirAccess.make_dir_recursive_absolute(char_dir)
	if not write_save(save_path(), d):
		push_warning("could not save " + save_path())
	if cloud != null and not _testing():
		cloud.push(char_id, d)

## How many earlier saves are kept beside each character's (<id>.json.bak1 is the newest).
const SAVE_BACKUPS := 3

## Writes a save safely (from the saves branch of 2026-10-29, now that it autosaves every minute): to <path>.tmp,
## read back and checked, and only then swapped in, the saves before it kept as .bak1 to .bak3. A crash, a closed
## window or a full disk mid-save never costs the character.
func write_save(path: String, d: Dictionary) -> bool:
	var txt := JSON.stringify(d)
	var tmp := path + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(txt)
	f.flush()
	var ok := f.get_error() == OK
	f.close()
	if not ok or FileAccess.get_file_as_string(tmp) != txt:
		return false
	if FileAccess.file_exists(path):
		for i in range(SAVE_BACKUPS - 1, 0, -1):
			_replace("%s.bak%d" % [path, i], "%s.bak%d" % [path, i + 1])
		_replace(path, path + ".bak1")
	return _replace(tmp, path)

## Moves a over b (b removed first: renaming onto an existing file fails on Windows).
func _replace(a: String, b: String) -> bool:
	if not FileAccess.file_exists(a):
		return false
	if FileAccess.file_exists(b):
		DirAccess.remove_absolute(b)
	return DirAccess.rename_absolute(a, b) == OK

## Reads a save, falling back to a finished .tmp and then the backups, newest first, when the save itself is missing
## or damaged; {} when there's nothing usable. `save_recovered` names the copy it came from.
var save_recovered := ""
func read_save(path: String, record_recovery := true) -> Dictionary:
	if record_recovery:
		save_recovered = ""
	for p in [path, path + ".tmp"] + range(1, SAVE_BACKUPS + 1).map(func(i): return "%s.bak%d" % [path, i]):
		if not FileAccess.file_exists(p):
			continue
		# A truncated candidate is expected here: parse quietly, then try its backup.
		var parser := JSON.new()
		if parser.parse(FileAccess.get_file_as_string(p)) != OK:
			continue
		var d = parser.data
		if typeof(d) == TYPE_DICTIONARY and typeof(d.get("hero")) == TYPE_DICTIONARY:
			if record_recovery and p != path:
				save_recovered = p.get_file()
			return d
	return {}

func load_game() -> bool:
	var d := read_save(save_path())
	if d.is_empty():
		return false
	if save_recovered != "":
		write_save(save_path(), d.duplicate(true))      # (the save was damaged or cut short: the good copy back in its place)
		push_warning("save recovered from " + save_recovered)
	hero.from_save(d.get("hero", {}))
	char_name = str(d.get("name", default_name(hero.cls)))
	if char_name != "":
		net.my_name = char_name
	cur_act = int(d.get("act", 0))
	waypoints_known = d.get("waypoints", ["town"])
	boss_killed = d.get("boss", false)
	difficulty = 0           # (a save from the story's A2 or A3 plays on in Act I)
	quests.from_save(d.get("quests", {}))
	var hv: Dictionary = d.get("harvest", {}) if d.get("harvest") is Dictionary else {}
	played_s = float(hv.get("t", 0.0))
	harvest_saved = (hv.get("zones", {}) as Dictionary).duplicate(true) if hv.get("zones") is Dictionary else {}
	if not bg_mode:
		_stash_fix_hero()        # (last: it may save, and a save writes everything loaded above)
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
		var d := read_save(char_dir + fn, false)
		if d.is_empty():
			continue
		var h: Dictionary = d.get("hero", {})
		out.append({"id": fn.get_basename(), "name": str(d.get("name", "")), "cls": str(h.get("cls", "knight")),
			"level": int(h.get("level", 1)), "difficulty": int(d.get("difficulty", 0)), "act": int(d.get("act", 0)),
			"played": int(d.get("played", 0)), "gold": int(h.get("gold", 0)),
			"carried": _count_items(h.get("equipment", {})) + _count_items(h.get("inventory", [])) + _count_items(h.get("belt", []))})
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a["played"]) > int(b["played"]))
	return out

## What a saved character wears, for the title screen's figure: Hero.net_gear()'s shape (equipment plus
## "_cls" and "_helm"), read from the save without changing it. {} when the save can't be read.
## How many items a saved equipment Dictionary or inventory/belt Array holds (empty slots don't count).
static func _count_items(v) -> int:
	var n := 0
	for it in (v.values() if v is Dictionary else (v if v is Array else [])):
		if it is Dictionary and not (it as Dictionary).is_empty():
			n += 1
	return n

func character_gear(id: String) -> Dictionary:
	var path := char_dir + id + ".json"
	if id == "" or not FileAccess.file_exists(path):
		return {}
	var d := read_save(path, false)
	if d.is_empty():
		return {}
	var h: Dictionary = d.get("hero", {}) if d.get("hero") is Dictionary else {}
	var g: Dictionary = (h.get("equipment", {}) as Dictionary).duplicate(true) if h.get("equipment") is Dictionary else {}
	g["_cls"] = str(h.get("cls", "knight"))
	g["_helm"] = bool(h.get("show_helm", true))
	return g

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
	if id != "":
		for sfx in [".json", ".json.tmp"] + range(1, SAVE_BACKUPS + 1).map(func(i): return ".json.bak%d" % i):
			if FileAccess.file_exists(char_dir + id + sfx):
				DirAccess.remove_absolute(char_dir + id + sfx)
	if cloud != null:
		cloud.remove(id)

func new_char_id() -> String:
	return "%d_%04d" % [int(Time.get_unix_time_from_system()), randi() % 10000]

func default_name(cls: String) -> String:
	var names: Dictionary = {"knight": ["Aldric", "Bertrand", "Cedric", "Godfrey", "Roland"], "wraith": ["Morwen", "Vesper", "Sable", "Ysolde", "Nyx"],
		"demon": ["Azrak", "Vorgath", "Malrok", "Ixtar", "Baelor"], "warlock": ["Fizzwick", "Nimbleroot", "Grimble", "Tobbin", "Wendle"]}
	var pool: Array = names.get(cls, names["knight"])
	return str(pool[randi() % pool.size()])

## The waypoint window's Battlegrounds card (Data.WAYPOINT_BATTLEGROUNDS): the lobby browser's Battlegrounds.
func waypoint_battleground(_id: String) -> void:
	if lobby_client != null:
		lobby_client.open("battlegrounds")

## Back to the title screen to pick another character (the pause menu's "Save and Exit to Title").
func exit_to_title(save_current := true) -> void:
	var leaving_practice := sandbox != null
	if steam != null:
		steam.close_world()      # (friends see our world gone)
	if lobby_client != null and lobby_client.match_id != "":
		if bg_mode and not lobby_client.admitted:
			bg_mode = false
			load_game()
		lobby_client.match_id = ""
		lobby_client.room = {}
	if arena_mode:
		arena_mode = false
		arena_state = {}
		if sandbox == null: load_game()
	if sandbox != null:
		# out of the sandbox first: the character as it was outside
		sandbox.shutdown()
		sandbox = null
		char_id = _sandbox_char
		_sandbox_char = ""
		if char_id != "" and not load_game(): char_id = ""
	if bg_mode and not hero.dead:
		bg_strip()           # leaving a raid without extracting is dying there (it saves)
	elif save_current and not leaving_practice:
		save_game()
	bg_mode = false
	bg_raid = {}
	bg_roster = []
	bg_gained = -1
	net_joining = false
	# nothing of the character that was playing carries on: its death screen still to come, its portal,
	# its experience bonus, the admin switches
	death_t = -1.0
	ui.death_panel.visible = false
	spectate_stop()
	ui.set_boss(null)
	tp_link = {}
	xp_bonus_t = 0.0
	test_immortal = false
	test_onehit = false
	test_stamina = false
	test_allskills = false
	test_fast = false
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
	while _busy:
		await get_tree().process_frame       # (a zone still loading would swallow ours)
	if _harness_camp():
		await load_zone(0, "town", "start")  # (the test harness: see _ready)
	else:
		unload_world()                     # (no world behind the title: see _ready)
	ui.show_title()

## The tools/ harness (a SceneTree script) still gets the camp behind the title, as before 2026-11-06: ~170 test
## scripts wait for a world at boot. `-- --real-boot` gives a tool the real start (tools/boot_flow_test.gd).
func _harness_camp() -> bool:
	return get_tree().get_script() != null and not OS.get_cmdline_user_args().has("--real-boot")

## Leave the current zone with nothing in its place (back to the title). load_zone does the same before it builds.
func unload_world() -> void:
	if world == null:
		return
	_store_harvest()
	if hero != null:
		SkillFx.clear(hero)
	world.queue_free()
	world = null
	hovered = null
	cur_zone = ""
	ResCache.release(_zone_scope)
	_zone_scope = ""

# ---------------------------------------------------------------- shops
func _stock_shops() -> void:
	var V: Dictionary = Data.VENDORS
	var lvl := maxi(hero.level, 1) + 1
	var r := RandomNumberGenerator.new()
	r.randomize()
	var smith := [Items.make("woodsman_axe")]     # a spare felling axe, always on the smith's rack
	for i in 13:
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
	if hero.run != null and not _run_pickup_ok(g):
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
		if Items.is_material(it):
			claim_material(it, g.global_position)
		else:
			Sfx.play("pickup")
		if hovered == g:
			hovered = null
		net.item_gone(g)
		g.queue_free()
		ui.refresh()
	else:
		ui.message("Inventory is full", Color(1, 0.4, 0.3))

## Co-op: the host handed us an item we picked up.
## An item thrown on the camp's bonfire (UI._burn): the flames flare and roar up, and it's gone.
func burned(it: Dictionary) -> void:
	Sfx.play("burn_item", 0.0, randf_range(0.95, 1.05))
	var fire: Inter = null
	for t in world.interactables:
		if is_instance_valid(t) and t.kind == "bonfire":
			fire = t
	if fire:
		var at := fire.global_position + Vector3(0, 0.8, 0)
		Fx.burst(world.fx_root, at, Color(1.0, 0.45, 0.08, 0.9), 40, 4.0, 0.22, 0.9, false, 3.0, 35.0)
		Fx.burst(world.fx_root, at + Vector3(0, 0.6, 0), Color(1.0, 0.8, 0.35, 0.8), 24, 3.0, 0.1, 0.7, false, 2.0, 25.0)
		Fx.flash(world.fx_root, at, Color(1.0, 0.55, 0.2), 6.0, 0.5, 8.0)

## A Hollow Sloth's material picked up: its colour bursts up and round the hero, a bright crystal ting,
## and its name is announced.
func claim_material(it: Dictionary, at: Vector3) -> void:
	var col: Color = Data.BASES[it["base"]]["color"]
	Sfx.play("relic_ting", 0.0, randf_range(0.97, 1.03))
	Fx.burst(world.fx_root, at + Vector3(0, 0.4, 0), col, 40, 4.5, 0.12, 0.9, true, -2.0)
	Fx.pillar(world.fx_root, at, col, 1.0)
	Fx.ring(world.fx_root, hero.global_position, 1.6, col, 0.6)
	Fx.flash(world.fx_root, at + Vector3(0, 1.0, 0), col, 4.0, 0.5, 6.0)
	ui.big_message("✦ " + it["name"] + " ✦")
	ui.message("You claim the %s" % it["name"], col)
	quests.on_pick(str(it["base"]))

func receive_item(it: Dictionary, pos: Vector3) -> void:
	if hero.run != null:
		_run_receive(it, pos)
		return
	if it["base"] == "gold":
		var amt := int(it["count"] * (1.0 + hero.gf / 100.0))
		hero.gold += amt
		Sfx.play("gold")
		Fx.number(world.fx_root, pos + Vector3(0, 1, 0), "+%d gold" % amt, Color(1, 0.85, 0.4))
	elif hero.add_to_inventory(it):
		if Items.is_material(it):
			claim_material(it, pos)
		else:
			Sfx.play("pickup")
	else:
		ui.message("Inventory is full", Color(1, 0.4, 0.3))
		net.request_drop(it, hero.global_position)
	ui.refresh()

# ---------------------------------------------------------------- run characters (multiplayer, RunBuild)

## Multiplayer's rules for loot and gear: a Battlegrounds raid, on its players' games and on the server.
func run_rules() -> bool:
	return MpMode.RUNS and (bg_mode or (net.server and cur_zone == Battlegrounds.ZONE))

## The classes of everyone in the raid, so its loot fits them (RunBuild.random_gear).
func raid_classes() -> Array:
	var out := []
	if not net.server and hero != null:
		out.append(hero.cls)
	for p in net.players.values():
		var h = p.get("hero")
		if h != null and is_instance_valid(h) and not out.has(h.cls):
			out.append(h.cls)
	return out

## A camp tier from a monster's level (camps set their monsters' levels by tier: Camps.MON_LEVEL).
static func tier_of_level(lvl: int) -> int:
	return 1 if lvl <= 2 else (2 if lvl <= 7 else (3 if lvl <= 12 else 4))

## A camp's chest: sealed until the camp falls; the first to open it rolls its loot for everyone; a run character then
## takes its own upgrade (one of three, once per camp and round).
func _camp_chest(t: Inter) -> void:
	var camp := Camps.by_id(world, str(t.data["camp"]))
	var left := Camps.alive(world, camp)
	if left > 0:
		ui.message("%s still stands: %d to go" % [camp.get("name", "The camp"), left], Color(1, 0.6, 0.45))
		Sfx.play("deny")
		return
	if not t.used:
		_open_chest(t)
		if net.active:
			net.inter_used(t)
	if hero.run == null:
		return
	var key := Camps.offer_key(self, camp)
	if hero.run.offers.has(key) and not hero.run.offer_open(key):
		ui.message("You took this camp's upgrade", Color(0.8, 0.8, 0.85))
		return
	ui.close_all()
	ui.run_ui.open_offer(key, int(camp.get("tier", 1)), str(camp.get("name", "")))

## A monster died on this peer (Enemy.die_visual): was it its camp's last? Then the camp falls here: the chest
## unseals, and a run character who fought there (within Camps.SHARE_R) gets the camp's experience.
func camp_check(e: Enemy) -> void:
	var camp := Camps.by_pack(world, e.pack_id)
	if camp.is_empty() or camp["cleared"]:
		return
	if e.boss and int(camp["tier"]) >= 4 and not net.is_client():
		# the boss is down: what it summoned and the rest of its camp wither with it (Mossbeard's mushrooms grow back
		# while he lives), so a boss camp always ends with its boss
		for o in world.enemies_root.get_children():
			if o is Enemy and o != e and not o.dead and o.pack_id == e.pack_id:
				o.take_damage(o.life * 10.0 + 99999.0, 0.0, o.global_position + Vector3(0.5, 0, 0), 0.0, false)
	if camp["cleared"] or Camps.alive(world, camp) > 0:
		return      # (a withered member's own death may have finished the camp already)
	camp["cleared"] = true
	var ch = camp.get("chest_node")
	if ch != null and is_instance_valid(ch):
		Fx.pillar(world.fx_root, ch.global_position, Color(1.0, 0.82, 0.4), 1.2)
		Fx.burst(world.fx_root, ch.global_position + Vector3(0, 0.8, 0), Color(1, 0.85, 0.5), 30, 3.0, 0.1, 0.8, true, -3.0)
	if net.server or hero == null or hero.dead:
		return
	var near := Vector2(hero.global_position.x - camp["pos"].x, hero.global_position.z - camp["pos"].z).length() < float(camp["r"]) + Camps.SHARE_R
	if not near:
		return
	var tier := int(camp["tier"])
	ui.big_message("✦ %s cleared ✦" % camp["name"])
	ui.message("Its chest is open: gear for the taking and an upgrade of your own", Color(1, 0.85, 0.45), 4.0)
	Sfx.play("relic_ting")
	if hero.run != null:
		hero.run.camps += 1
		if tier >= 4:
			hero.run.bosses += 1
		hero.add_xp(int(RunBuild.CAMP_XP.get(tier, 60)))

## Before a run character takes something off the ground: gear for an occupied slot opens the swap window
## instead (RunUI.open_swap), gear for someone else and full consumables are refused, gold is passed by.
func _run_pickup_ok(g: GroundItem) -> bool:
	var it: Dictionary = g.item
	var b: Dictionary = Data.BASES.get(str(it.get("base", "")), {})
	if b.is_empty() or str(b["slot"]) in ["gold", "ring", "amulet", "belt", "material", "resource", "tool"]:
		ui.message("Run characters can't carry that", Color(1, 0.6, 0.45))
		return false
	if str(b["slot"]) == "potion":
		if not hero.belt.any(func(x): return x == null or (x["base"] == it["base"] and int(x.get("count", 1)) < RunBuild.STACK)):
			ui.message("Your %d consumable slots are full" % RunBuild.BELT, Color(1, 0.6, 0.45))
			return false
		return true
	if not RunBuild.wearable(it, hero.cls):
		ui.message("A %s can't use that" % Data.CLASSES[hero.cls]["name"], Color(1, 0.6, 0.45))
		return false
	if hero.equipment.get(RunBuild.gear_slot(it)) != null:
		ui.run_ui.open_swap(it, g)
		return false
	return true

## The swap window's Equip: take the piece off the ground (the host grants it to a client) and wear it; what it
## replaces is dropped where the hero stands, for anyone to take.
var run_swapping := false
func run_swap(it: Dictionary, g: Node) -> void:
	if not is_instance_valid(g) or g.is_queued_for_deletion():
		ui.message("Someone took it first", Color(1, 0.6, 0.45))
		return
	if net.is_client():
		run_swapping = true
		g.set_meta("pending", true)
		net.request_pickup(g)
		return
	if hovered == g:
		hovered = null
	net.item_gone(g)
	g.queue_free()
	_run_wear(it)

func _run_wear(it: Dictionary) -> void:
	var old = hero.run_wear(it)
	if old != null:
		drop_item(old, hero.global_position)
	ui.refresh()

## A client's grant from the host (Net.cl_grant) for a run character: a swap in progress wears it; else as a pickup;
## anything that can't be taken goes back on the ground.
func _run_receive(it: Dictionary, pos: Vector3) -> void:
	if str(it.get("base", "")) == "gold":
		return
	if run_swapping and Items.is_equip(it) and RunBuild.wearable(it, hero.cls):
		run_swapping = false
		_run_wear(it)
		return
	if hero.add_to_inventory(it):
		Sfx.play("pickup")
	else:
		net.request_drop(it, hero.global_position)
	ui.refresh()

## Drop one of a consumable stack (the build window's right-click): it lands at the hero's feet.
func run_drop_belt(i: int) -> void:
	if i < 0 or i >= hero.belt.size() or hero.belt[i] == null:
		return
	var it: Dictionary = hero.belt[i]
	var one := it.duplicate(true)
	one["count"] = 1
	it["count"] = int(it.get("count", 1)) - 1
	if int(it["count"]) <= 0:
		hero.belt[i] = null
	drop_item(one, hero.global_position)
	hero.stats_changed.emit()

## Take a camp offer's choice (RunUI's upgrade window): once per camp (RunBuild.claim).
func run_claim(key: String, i: int) -> Dictionary:
	if hero.run == null:
		return {}
	var c := hero.run.claim(key, i, hero.binds)
	if not c.is_empty():
		# the chest's consumables for this player (RunTalents.roll_consumables): to the belt, the rest at his feet
		for base in hero.run.offers[key].get("loot", []):
			if Data.BASES.has(str(base)):
				var it := Items.potion(str(base))
				if not hero.add_to_inventory(it):
					drop_item(it, hero.global_position)
		hero.run_changed()
		ui.refresh()
	return c

## A deep camp's rare reward: a class unique (its own effect: a free roll, a ward) for one of the raid's classes, in a
## slot run characters wear, with no level to meet.
func _run_class_unique(at: Vector3) -> void:
	var classes := raid_classes()
	var pool := Data.UNIQUES.keys().filter(func(k): return Data.UNIQUES[k].has("cls") and classes.has(str(Data.UNIQUES[k]["cls"])) \
		and RunBuild.wearable(Items.make_unique(k), str(Data.UNIQUES[k]["cls"])))
	if pool.is_empty():
		return
	var it := Items.make_unique(pool[rng.randi() % pool.size()])
	it["req"] = 0
	drop_item(it, at)

## A run's loot roll (the monsters and camp chests): gear for the raid's classes at the camp's tier, or a potion;
## never gold, rings or amulets.
func _run_loot(at: Vector3, tier: int, good: bool, always := false) -> void:
	var r := rng.randf()
	if good or r < (0.5 if always else 0.32):
		drop_item(RunBuild.random_gear(tier, rng, raid_classes()), at)
	elif always or r < 0.55:
		drop_item(Items.potion("hp_potion" if rng.randf() < 0.7 else "mp_potion"), at)

## Somewhere else: alone, straight there; in a co-op party, everyone is asked first and the party goes
## only when all agree (Net.ask_trip, the ready check), then `travel_now` takes the whole party.
func travel(act: int, zone: String, spawn: String, at = null, clear_tp := false) -> void:
	if net.party_size() > 1:
		net.ask_trip(act, zone, spawn, at, clear_tp)
		return
	travel_now(act, zone, spawn, at, clear_tp)

func travel_now(act: int, zone: String, spawn: String, at = null, clear_tp := false) -> void:
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
	elif t.kind == "bell":
		Sfx.play_at("anvil", t.global_position, 0.0, 0.6)
		if net.server and bg != null:
			var who := "Someone"
			var pid := multiplayer.get_remote_sender_id()
			if net.players.has(pid):
				who = str(net.players[pid]["name"])
			bg.start_prep(who)

## A class unique (Data.UNIQUES with "cls": the hard-won level-20 rewards with the raid's item effects) for one of
## the classes of the heroes near (a raid's players, the party, or the hero), so what drops is someone's to wear.
func _drop_class_unique(at: Vector3) -> void:
	var want := []
	for hh in get_tree().get_nodes_in_group("hero") + net.puppets():
		if hh is Hero and is_instance_valid(hh) and not (net.server and hh == hero) and hh.global_position.distance_to(at) < 40.0:
			want.append(hh.cls)
	var pool := Data.UNIQUES.keys().filter(func(k): return Data.UNIQUES[k].has("cls") and (want.is_empty() or want.has(Data.UNIQUES[k]["cls"])))
	if pool.is_empty():
		pool = Data.UNIQUES.keys().filter(func(k): return Data.UNIQUES[k].has("cls"))
	var it := Items.make_unique(pool[rng.randi() % pool.size()])
	drop_item(it, at)
	ui.message("%s!" % it["name"], Color(0.85, 0.66, 0.38))

func _open_chest(t: Inter) -> void:
	t.used = true
	Sfx.play("equip")
	var gold := bool(t.data.get("gold", false))
	Fx.burst(world.fx_root, t.global_position + Vector3(0, 0.8, 0), Color(1, 0.85, 0.5), 60 if gold else 24, 5.0 if gold else 3.0, 0.1, 0.8, true, -4.0)
	if gold:
		Fx.pillar(world.fx_root, t.global_position, Color(1.0, 0.8, 0.3), 1.6)
	if net.is_client():
		return
	if run_rules():
		# a run's chest: gear and potions at the camp's tier (the first roll always gear); the upgrade is each
		# player's own (Game._camp_chest)
		var tier := int(t.data.get("tier", tier_of_level(world.level)))
		for i in int(Camps.CHEST_ROLLS.get(tier, 2)):
			_run_loot(t.global_position, tier, i == 0, true)
		drop_item(Items.potion("hp_potion"), t.global_position)      # (every camp's chest heals: a run lives on its belt)
		if rng.randf() < float(Camps.UNIQUE_CHANCE.get(tier, 0.0)):
			_run_class_unique(t.global_position)
		return
	var n := 7 if gold else rng.randi_range(2, 4)
	for i in n:
		if gold and i == 0:
			_drop_class_unique(t.global_position)     # the golden chest's own reward: a class unique
			continue
		_drop_loot_roll(t.global_position, world.level, gold and i < 3)

## A chest a boss guards (data "guard": its Data.ENEMIES kind; the Battlegrounds' golden chest): sealed while that
## boss lives within 40 m. Every peer works it out from the monsters it has, so the server (which refuses a sealed
## chest's sv_inter) and each client agree, a late joiner too (a dead boss isn't in its list).
func chest_sealed(t: Inter) -> bool:
	if t.data.has("camp"):
		return Camps.alive(world, Camps.by_id(world, str(t.data["camp"]))) > 0
	var guard := str(t.data.get("guard", ""))
	if guard == "" or world == null or t.data.get("unsealed", false):
		return false
	if net.active and not net.is_host:
		# the server decides (Net.sv_inter); a player who joined after the guard fell never saw it happen
		for e in world.enemies_root.get_children():
			if e is Enemy and not e.dead and e.kind == guard:
				return true
		return false
	return true

## A boss's death breaks the seal on the chests it guards, wherever it falls (luring it off doesn't open them), on
## every peer: the host's death path and a client's Net.cl_enemy_die both reach Enemy.die_visual. A new round's zone
## starts sealed again.
func guard_fell(kind: String) -> void:
	if world == null:
		return
	for c in world.interactables:
		if c is Inter and str(c.data.get("guard", "")) == kind:
			c.data["unsealed"] = true

## A camp vendor's own talk: the elder's news, a trader's greeting and Trade.
func _vendor_talk(t: Inter) -> void:
	var role: String = t.data.get("role", "")
	if role == "auction":
		ui.open_dialog(t.label, "Elixirs, friend: the finest brews in the Wilds, and the rarest. The hall holds every coin until the hammer falls.",
			[["See the auctions", func(): AuctionUI.open(ui, ui.auction_panel)], ["Leave", func(): pass]])
		return
	if role == "elder":
		var txt := "The gates stay barred: nothing good comes out of the moor now. If you want a fight, the waypoint takes you down to the Battlegrounds. Raise your shield against arrows there: a good block turns them aside."
		ui.open_dialog(t.label, txt, [["Farewell", func(): pass]])
	else:
		var sh: Array = shops.get(role, ["", []])
		var lines := {"smith": "Need a blade, or something to stop one?", "armor": "Leather, mail or plate. All of it has seen worse than you.", "alch": "Potions for the body, trinkets for the soul.", "gamble": "Fortune favours the bold. Every piece is a mystery until you pay."}
		var btns := [["Trade", func(): ui.open_shop(role, sh[0], sh[1], t, lines.get(role, ""))]]
		if role == "armor":
			btns.append(["Enchant armor", func(): ui.open_enchant(t.label)])
		btns.append(["Leave", func(): pass])
		ui.open_dialog(t.label, lines.get(role, ""), btns)

func _interact(t: Inter) -> void:
	match t.kind:
		"tree":
			# a harvestable tree (Harvest): walk up, and the hero sets to it with an axe
			hero.start_chop(t)
		"furnace":
			# Halvar's furnace (Furnace): temper a weapon over felled wood
			if t is Furnace:
				Sfx.play("bonfire_open", -10.0, 0.8)
				ui.open_furnace(t)
		"extract":
			if not bool(t.data.get("open", false)):
				ui.message("The portal is dark. It opens later in the raid.", Color(0.8, 0.8, 0.9))
			elif bg_mode and net.is_client() and not hero.dead:
				ui.message("Extracting...", Color(0.6, 0.85, 1.0))
				net.request_extract()
		"vendor":
			ui.trade_with = t
			Sfx.play("click")
			var rest := func(): _vendor_talk(t)
			# a quest to hand in or on offer comes before their trade (Quests.talk)
			if not quests.talk(str(t.data.get("role", "")), t.label, rest):
				rest.call()
		"stash":
			ui.open_stash()
			if ui.stash_panel.visible:
				ui.trade_with = t
				Sfx.play("equip")
				chest_lid(t, true)
		"bonfire":
			ui.open_burn()
			ui.trade_with = t
			Sfx.play("bonfire_open")
		"waypoint":
			var wp_id: String = t.data.get("wp", "town")
			if not waypoints_known.has(wp_id):
				waypoints_known.append(wp_id)
				ui.message("Waypoint activated", Color(0.5, 0.7, 1.0))
				Sfx.play("portal")
			ui.open_waypoints(t)
		"portal":
			Sfx.play("portal")
			if t.data.get("dir", "") == "town":
				travel(cur_act, "town", "portal")
			else:
				var link := tp_link
				travel(int(link.get("act", 0)), link.get("zone", "town"), "start", link.get("pos"), true)
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
			quests.progress("flower")
			if net.active:
				net.inter_used(t)
		"chest":
			if t.data.has("camp"):
				_camp_chest(t)
				return
			if t.used:
				return
			if chest_sealed(t):
				ui.message("Thorns bind it shut. Old Mossbeard's magic holds while he lives.", Color(0.6, 1.0, 0.5))
				Sfx.play("deny")
				return
			_open_chest(t)
			if net.active:
				net.inter_used(t)
		"bell":
			# the antechamber's bell: the server starts the countdown (Net.sv_inter -> use_inter_remote)
			Sfx.play("anvil", -2.0, 0.6)
			if bg_mode and net.is_client():
				if str(bg_raid.get("state", "")).begins_with("lobby"):
					net.inter_used(t)
				else:
					ui.message("The raid is already under way", Color(0.8, 0.8, 0.9))

func travel_waypoint(dest: Dictionary) -> void:
	Sfx.play("portal")
	travel(cur_act, dest["zone"], "waypoint")

## Available activities are rebuilt from content data, never from a second UI-only list.
func waypoint_activities() -> Array:
	var entries: Array = Data.WAYPOINT_ACTIVITIES.duplicate(true)
	var result := []
	var seen := {}
	for entry in entries:
		var id := str(entry.get("id", ""))
		if id == "" or seen.has(id) or not Data.waypoint_available(entry, Time.get_unix_time_from_system()):
			continue
		if not waypoint_activity_valid(entry):
			continue
		seen[id] = true
		result.append(entry)
	return result

func waypoint_activity_valid(entry: Dictionary) -> bool:
	if str(entry.get("name", "")) == "": return false
	var zone := str(entry.get("zone", ""))
	return str(entry.get("group", "")) in ["pve", "daily"] and str(entry.get("route", "")) == "zone" and not Data.waypoint_act(int(entry.get("run", -1))).is_empty() and zone in Data.WAYPOINT_ZONES

func waypoint_activity(id: String) -> Dictionary:
	for entry in waypoint_activities():
		if str(entry["id"]) == id:
			return entry
	return {}

## Used both by the card and immediately before travel, so stale buttons cannot bypass locks.
func waypoint_activity_lock(entry: Dictionary) -> String:
	if entry.is_empty(): return "This activity is no longer available."
	if bg_mode or _busy or not playing or hero == null or hero.dead: return "Cannot travel right now."
	var run := int(entry["run"])
	if not act_unlocked(run): return "Unlock this act first."
	if entry.has("requires_waypoint") and not waypoint_known(run, str(entry["requires_waypoint"])):
		return "Discover this act's wilderness waypoint first."
	if hero.level < int(entry.get("level", 1)): return "Requires level %d" % int(entry["level"])
	return ""

func waypoint_activity_go(id: String) -> void:
	var entry := waypoint_activity(id)
	var reason := waypoint_activity_lock(entry)
	if reason != "":
		ui.message(reason, Color(1.0, 0.6, 0.45))
		return
	ui.close_all()
	Sfx.play("portal")
	travel(0, str(entry["zone"]), str(entry.get("spawn", "start")))

# ---------------------------------------------------------------- the waypoint network (Data.WAYPOINT_ACTS)
## Is act `run` open? Act I, the only act, always is.
func act_unlocked(run: int) -> bool:
	return run == 0 and not Data.waypoint_act(run).is_empty()

## True where the developer tools are (the owner's: see dev_tools).
func dev_tools_on() -> bool:
	return dev_tools

## Has this character touched waypoint `id` of act `run`?
func waypoint_known(run: int, id: String) -> bool:
	return run == 0 and waypoints_known.has(id)

## Take waypoint `id` of act `run`: travel to its zone, arriving by its stone. Only waypoints this character has
## touched.
func waypoint_go(run: int, id: String) -> void:
	var p := Data.waypoint_point(run, id)
	if _busy or p.is_empty() or not act_unlocked(run) or not waypoint_known(run, id):
		return
	var zone: String = p["zone"]
	if zone != cur_zone or id != _at_waypoint():
		Sfx.play("portal")
		travel(cur_act, zone, "waypoint_" + id)

## The waypoint stone the hero stands at, if any ("" if none).
func _at_waypoint() -> String:
	if world == null or hero == null:
		return ""
	for it in world.interactables:
		if is_instance_valid(it) and it.kind == "waypoint" and it.global_position.distance_to(hero.global_position) < 4.5:
			return str(it.data.get("wp", "town"))
	return ""

func _make_portal(p: Vector3, dir: String) -> Inter:
	var it := Inter.new()
	it.kind = "portal"
	it.label = "Town Portal" if dir == "town" else "Portal to " + zone_title(int(tp_link.get("act", 0)), tp_link.get("zone", "town"))
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
	if bg_mode:
		ui.message("No portals out of the Battlegrounds: find an Extraction Portal", Color(1.0, 0.8, 0.4))
		return
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
	# (a run character takes a kill's full worth at any level: its curve is RunBuild.xp_for)
	var lvl_ratio := 1.0 if hero.run != null else clampf(1.0 - (hero.level - lvl) * 0.08, 0.2, 1.3)
	if hero.run != null:
		bonus *= 1.0 + hero.talent("xp_pct") / 100.0
	hero.add_xp(int(xp * lvl_ratio * bonus))

func on_enemy_killed(e: Enemy) -> void:
	quests.on_kill(e)
	gain_kill_xp(e.xp, e.level)
	net.share_xp(e.xp, e.level)
	var drops := 0 if e.def.get("no_loot", false) else 1
	if e.champion:
		drops = 3
	if e.boss:
		drops = 7
	for i in drops:
		_drop_loot_roll(e.global_position, e.level, e.boss or (e.champion and i == 0))
	if e.def.has("drop") and not run_rules():
		# a Hollow Sloth's own material
		drop_item(Items.make(e.def["drop"], 0, 1), e.global_position)
	if e.def.get("trophy", false) and not run_rules():
		# the Hollow Sloth: a heap of gold (its unique comes from its loot table, below)
		for i in 3:
			drop_item(Items.gold(int(rng.randf_range(40, 70) * (1.0 + e.level * 0.6))), e.global_position)
		ui.message("%s is slain" % e.display_name, Color(0.55, 0.9, 0.95))
	if e.def.get("class_unique", false) and not run_rules():
		_drop_class_unique(e.global_position)
	_boss_loot(e)
	if e.boss:
		# a boss is a camp's: its loot, and the Extraction Portals are the way out (no story ending, and no pillar of
		# light: it read as a portal that went nowhere, Blaine 2026-11-06)
		boss_killed = true
		ui.set_boss(null)
		ui.big_message(e.display_name + " has fallen")
		add_shake(0.8)

## The local hero rose again (any path: the death screen, co-op, a zone change): the death screen goes.
func on_local_respawn() -> void:
	death_t = -1.0
	ui.death_panel.visible = false
	spectate_stop()

## Co-op: the host's game reports the boss fell (no story ending, as in on_enemy_killed).
func boss_down_remote(e: Enemy) -> void:
	boss_killed = true
	ui.set_boss(null)
	ui.big_message(e.display_name + " has fallen")
	add_shake(0.8)

func on_boss_aggro(e: Enemy) -> void:
	net.boss_aggro(e)
	ui.set_boss(e)
	Sfx.play("roar")
	add_shake(0.5)

func _drop_loot_roll(at: Vector3, lvl: int, good: bool) -> void:
	if run_rules():
		_run_loot(at, tier_of_level(lvl), good)
		return
	var r := rng.randf()
	if good or r < 0.3:
		var it := Items.random_drop(lvl, hero.mf + (100 if good else 0), rng, good)
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
## The camera swings in on `n` for `dur` seconds, zoomed by `z` (screenshot tools use it; no boss does any more).
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
	if arena_mode:
		death_t = -1.0
		return
	Telemetry.crumb("died", {"bg": bg_mode})
	death_t = 2.0
	if sandbox != null:
		sandbox.hero_died(hero)
	elif bg_mode:
		_bg_fell()
	ui.set_boss(null)

## Battlegrounds: fallen in the crypt, the hero watches the living (the camera follows them; Tab or the arrow keys
## switch) until they leave. Whoever they watch falls, the camera stays over the body a moment and moves on; whoever
## leaves, it moves on at once. When the round ends the crypt sends them home.
func spectate_start() -> void:
	spectating = 0
	_spec_over = 0.0
	spectate_next(1)
	ui.spectate_panel.visible = true
	Telemetry.crumb("spectate", {"watching": ui.spectate_name()})

func spectate_stop() -> void:
	spectating = 0
	ui.spectate_panel.visible = false

## The living players one could watch, in a fixed order.
func spectate_targets() -> Array:
	var ids: Array = net.players.keys()
	ids.sort()
	return ids.filter(func(pid):
		var h = net.players[pid]["hero"]
		return is_instance_valid(h) and not h.dead and h.visible and h.net_has)

func spectate_next(dir: int) -> void:
	var ids := spectate_targets()
	var i := ids.find(spectating)
	if ids.is_empty():
		spectating = 0
	elif i < 0:
		spectating = int(ids[0])
	else:
		spectating = int(ids[posmod(i + dir, ids.size())])
	_spec_lost = 0.0
	ui.update_spectate()

## The hero being watched (null when no one is).
func spectate_hero() -> Node3D:
	if spectating == 0 or not bg_mode or not net.players.has(spectating):
		return null
	var h = net.players[spectating]["hero"]
	return h if is_instance_valid(h) else null

func _update_spectate(dt: float) -> void:
	if not ui.spectate_panel.visible:
		return
	var h := spectate_hero()
	if h == null or h.dead or not h.visible:
		_spec_lost += dt
		if h == null or _spec_lost > 2.5 or spectating == 0:
			spectate_next(1)
	if str(bg_raid.get("state", "")) == "reset":
		_spec_over += dt
		if _spec_over > 4.0:
			ui.message("The crypt has collapsed: the round is over", Color(1, 0.6, 0.4))
			spectate_stop()
			respawn()
			return
	ui.update_spectate()

func respawn() -> void:
	if arena_mode: return
	if sandbox != null:
		# the sandbox: back on your feet at once, nothing lost
		hero.respawn(sandbox.spawn_point())
		return
	if bg_mode:
		# no coming back from the crypt
		_leave_battlegrounds()
		return
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
	if ui.invite_btn != null:
		ui.invite_btn.visible = steam != null and steam.ok and not net.is_client() and not net.server and not bg_mode \
			and not arena_mode and (lobby_client == null or lobby_client.match_id == "")
	Engine.time_scale = 1.0
	lmb_held = false
	rmb_held = false
	if paused and hero != null:
		hero.cmd_wasd(Vector3.ZERO)     # (in co-op the game runs on under the menu: he mustn't walk on)
		hero.sprint = false

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
## The interactable under the mouse ray (origin o, direction d): the one the ray passes closest to, within its
## "pick" reach (1.1 m) of its "pick_y" point (1 m up). The closest, not the first in the list: a neighbour's reach
## overlapping a trader's no longer steals the click (jj: Agnes couldn't be clicked from some sides).
func pick_inter(o: Vector3, d: Vector3) -> Inter:
	var best: Inter = null
	var bd := INF
	for it in world.interactables:
		if not is_instance_valid(it) or (it.kind == "flower" and it.used):
			continue
		var c2: Vector3 = it.global_position + Vector3(0, float(it.get_meta("pick_y")) if it.has_meta("pick_y") else 1.0, 0)
		var dist := (c2 - o).cross(d).length()
		if dist < (float(it.get_meta("pick")) if it.has_meta("pick") else 1.1) and dist < bd:
			bd = dist
			best = it
	return best

func pick_enemy(o: Vector3, d: Vector3) -> Enemy:
	var best: Enemy = null
	var best_d := 1e9
	for e in world.enemies_root.get_children():
		if not (e is Enemy) or e.dead or e.is_queued_for_deletion() or e.pvp_hidden:
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
	if world == null or net.server:
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
		best = pick_inter(o, d)
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
	elif hovered is Harvest.HTree:
		var tr: Harvest.HTree = hovered
		if tr.state == "stand":
			ui.show_target("%s  ·  %s" % [tr.label, "Chop" if hero.chop_axe()[0] != "" else "Needs an axe"], tr.hp / tr.max_hp, Color(0.78, 0.62, 0.4))
		else:
			ui.show_target("%s stump" % tr.label, 0.0, Color(0.55, 0.5, 0.42))
	elif hovered is Inter:
		ui.show_target(hovered.label, 1.0, Color(0.85, 0.75, 0.5))
		ui.target_bar.visible = false
	else:
		ui.hide_target()

## Dev cheat (not in production builds, or with the dev tools): typing "maxout" while playing makes the current
## character as strong as it gets: level 99, its stat points spread over its class's stats, every talent point spent
## (the class's auto build), a million gold, full potions and a bag of the best gear (equip what you like). Saved.
var _typed := ""
func _cheat_keys(ev: InputEvent) -> void:
	if not (ev is InputEventKey and ev.pressed and not ev.echo) or not playing or hero == null:
		return
	var ch := String.chr(ev.unicode) if ev.unicode > 0 else ""
	if ch == "":
		return
	_typed = (_typed + ch.to_lower()).right(12)
	if _typed.ends_with("maxout") and (dev_tools_on() or BuildEnv.env() != "production"):
		_typed = ""
		max_out()

## Admin (the Escape menu's Admin column, only with dev tools; Blaine's progression spec): this character to level 20
## (and 10,000 gold each press) with its stats spent and its talents auto-built, every skill it has at 20, and a solid
## class baseline of level-20 gear for PvP testing (rare items on every slot, the class's own weapon). Safe to press
## again: its own pieces (marked "boost") stay, any other equipped item moves to the bag (kept equipped if the bag
## is full, never destroyed), and the same gear is never handed out twice.
## The Veilmother's Locket ("phial"): a Shadow Phial at the start of each raid, in the belt (or the bag), never more
## than the locket gives.
func give_raid_phials() -> void:
	var n := int(hero.stats.get("phial", 0))
	if n <= 0:
		return
	var have := 0
	for b in hero.belt:
		if b is Dictionary and b["base"] == "shadow_phial":
			have += int(b.get("count", 1))
	if have >= n:
		return
	var it := Items.potion("shadow_phial")
	it["count"] = n - have
	for i in hero.belt.size():
		if hero.belt[i] is Dictionary and hero.belt[i]["base"] == "shadow_phial":
			hero.belt[i]["count"] = n
			ui.refresh()
			return
	for i in hero.belt.size():
		if hero.belt[i] == null:
			hero.belt[i] = it
			ui.refresh()
			ui.message("A Shadow Phial in your belt (the Veilmother's Locket)", Color(0.7, 0.6, 1.0))
			return
	hero.add_to_inventory(it)
	ui.refresh()

## A boss's own loot (the items rework: rewards from hard content, not tiny drop chances; Data.BOSS_LOOT): its first
## kill by this character always drops one of its uniques (its "boss_drop" if it has one); after that each kill has
## BOSS_LOOT_CHANCE, and every kill without one raises the next by BOSS_LOOT_LUCK (Hero.boss_luck, saved).
const BOSS_LOOT_CHANCE := 0.35
const BOSS_LOOT_LUCK := 0.15

func _boss_loot(e: Enemy) -> void:
	var table: Array = Data.BOSS_LOOT.get(e.kind, [])
	if table.is_empty() or sandbox != null:
		return
	var misses := int(hero.boss_luck.get(e.kind, -1))
	var chance := 1.0 if misses < 0 else BOSS_LOOT_CHANCE + BOSS_LOOT_LUCK * misses
	if rng.randf() >= chance:
		hero.boss_luck[e.kind] = misses + 1
		return
	hero.boss_luck[e.kind] = 0
	var uid: String = str(e.def["boss_drop"]) if misses < 0 and e.def.has("boss_drop") else str(table[rng.randi() % table.size()])
	var bu := Items.make_unique(uid)
	drop_item(bu, e.global_position)
	ui.message("%s dropped %s!" % [e.display_name, bu["name"]], Color(0.85, 0.66, 0.38))

## Practice uses a temporary hero. Preserve the saved character and restore it when leaving.
var _sandbox_char := ""

var _sandbox_from_title := false

func _begin_sandbox(cls: String, online: bool) -> void:
	_sandbox_from_title = not playing
	if playing: save_game()
	_sandbox_char = char_id if playing else ""
	char_id = ""
	if paused: toggle_pause()
	ui.hide_title()
	ui.close_all()
	net.stop_listening()
	playing = true
	hero.run = null
	sandbox = Sandbox.new(self)
	sandbox.online = online
	sandbox.pick_me["cls"] = cls if Data.CLASSES.has(cls) else "knight"
	sandbox.pick_bot["cls"] = sandbox.pick_me["cls"]
	add_child(sandbox)
	Sandbox.outfit(self, hero, sandbox.pick_me["cls"], 20, "geared")

func open_sandbox(cls := "") -> void:
	if sandbox != null or _busy: return
	if net.active or bg_mode or arena_mode or (lobby_client != null and not lobby_client.room.is_empty()):
		ui.message("Leave your current match or lobby before entering Sandbox.")
		return
	_begin_sandbox(hero.cls if cls == "" else cls, false)
	await load_zone(0, Sandbox.ZONE, "start")
	ui.refresh()
	ui.big_message(Sandbox.TITLE)
	ui.message("Practice only. Your saved characters are unchanged.", Color(0.6, 0.85, 1.0))

func start_sandbox_join(address: String, ticket_character: String) -> void:
	while _busy: await get_tree().process_frame
	if sandbox != null or net.active: return
	_begin_sandbox(ticket_character.trim_prefix("sandbox_"), true)
	# This identifier is used only for admission; save_game is suppressed throughout practice.
	char_id = ticket_character
	char_name = str(Data.CLASSES[hero.cls]["name"])
	arena_mode = true
	arena_state = {"phase": "waiting"}
	net_joining = true
	loading_lbl.text = "Joining Sandbox..."
	loading.visible = true
	var address_parts := Battlegrounds.parse_address(address)
	if net.join(str(address_parts[0]), int(address_parts[1])) != OK:
		on_net_failed("Could not connect to Sandbox.")
		return
	await get_tree().create_timer(12).timeout
	if sandbox != null and sandbox.online and net.is_client() and not net.welcomed:
		net.shutdown()
		on_net_failed("Sandbox did not answer in time.")

func close_sandbox() -> void:
	if sandbox == null or _busy: return
	var title := _sandbox_from_title or sandbox.online
	if sandbox.online: net.shutdown()
	arena_mode = false
	arena_state = {}
	sandbox.shutdown()
	sandbox = null
	char_id = _sandbox_char
	_sandbox_char = ""
	if char_id != "":
		if load_game():
			hero.refresh_gear()
			hero.recalc()
		else:
			char_id = ""
			title = true
	if title:
		await exit_to_title(false)
		lobby_client.open("sandbox")
		return
	if hero.dead: hero.respawn(hero.global_position)
	death_t = -1.0
	await load_zone(0, "town", "start")
	hero.life = hero.max_life
	hero.mana = hero.max_mana
	ui.refresh()

const BOOST_SLOTS := ["weapon", "armor", "helm", "gloves", "boots", "belt", "ring1", "ring2", "amulet"]

func go_level_20() -> void:
	if not dev_tools:
		return
	hero.boosted = true       # (saved: the raid server lets only admins raid with a boosted character)
	if hero.level < 20:
		hero.set_level(20)
	var c: Dictionary = Data.CLASSES.get(hero.cls, {})
	var tot := float(int(c.get("str", 1)) + int(c.get("dex", 1)) + int(c.get("vit", 1)) + int(c.get("ene", 1)))
	var pts := hero.stat_points
	var a := int(pts * int(c.get("str", 1)) / tot)
	var b := int(pts * int(c.get("dex", 1)) / tot)
	var v := int(pts * int(c.get("vit", 1)) / tot)
	hero.str_ += a
	hero.dex += b
	hero.vit += v
	hero.ene += pts - a - b - v
	hero.stat_points = 0
	hero.talents = Talents.auto_build(hero.cls, hero.free_talent_points(), hero.talents)
	hero._talents_changed()
	var r := RandomNumberGenerator.new()
	r.seed = hash(hero.cls + ":boost20")       # (the same baseline every time)
	var slots := BOOST_SLOTS.duplicate()
	if hero.cls == "knight":
		slots.append("shield")
	var given := 0
	for slot in slots:
		var cur = hero.equipment.get(slot)
		if cur is Dictionary and bool((cur as Dictionary).get("boost", false)):
			continue
		var base := _boost_base(slot)
		if base == "":
			continue
		var it := Items.generate(base, 20, 2, r)
		it["boost"] = true
		if cur is Dictionary and not (cur as Dictionary).is_empty():
			if not hero.add_to_inventory(cur):
				continue          # (no room for what's there: it stays on)
		hero.equipment[slot] = it
		given += 1
	hero.gold += 10000
	hero.refresh_gear()
	hero.recalc()
	hero.life = hero.max_life
	hero.mana = hero.max_mana
	if char_id != "":
		save_game()
	ui.refresh()
	ui.message("Level 20: rites learned, %d piece%s of level-20 gear on, +10,000 gold" % [given, "" if given == 1 else "s"], Color(0.6, 1.0, 0.6))

## The best base for a slot at level 20 that this class can wear (its own weapon kind: bows for the ranger, canes for
## the plague doctor, the drumstick for Doug...).
func _boost_base(slot: String, h: Hero = null, max_lvl := 20) -> String:
	if h == null:
		h = hero
	var want := "ring" if slot in ["ring1", "ring2"] else slot
	var mine: String = str(Data.CLASSES.get(h.cls, {}).get("weapon", ""))
	var kind := str(Data.BASES.get(mine, {}).get("kind", "")) if mine != "" else ""
	var held = h.equipment.get("weapon")
	if kind == "" and held is Dictionary:
		kind = str(Data.BASES.get(held["base"], {}).get("kind", ""))     # no weapon of its own (the knight): the kind in hand
	var best := ""
	var bl := -1
	for k in Data.BASES:
		var bd: Dictionary = Data.BASES[k]
		if str(bd.get("slot", "")) != want or int(bd.get("lvl", 1)) > max_lvl:
			continue
		var owner := str(bd.get("cls", ""))
		if owner != "" and owner != h.cls:
			continue
		if want == "weapon" and kind != "" and str(bd.get("kind", "")) != kind:
			continue
		# (a tie goes to the class's own weapon: Doug's drumstick over a slower club)
		if int(bd.get("lvl", 1)) > bl or (int(bd.get("lvl", 1)) == bl and owner == h.cls):
			bl = int(bd.get("lvl", 1))
			best = k
	return best

func max_out() -> void:
	hero.boosted = true
	hero.set_level(99)
	var c: Dictionary = Data.CLASSES.get(hero.cls, {})
	var tot := float(int(c.get("str", 1)) + int(c.get("dex", 1)) + int(c.get("vit", 1)) + int(c.get("ene", 1)))
	var pts := hero.stat_points
	hero.str_ += int(pts * int(c.get("str", 1)) / tot)
	hero.dex += int(pts * int(c.get("dex", 1)) / tot)
	hero.vit += int(pts * int(c.get("vit", 1)) / tot)
	hero.ene += pts - int(pts * int(c.get("str", 1)) / tot) - int(pts * int(c.get("dex", 1)) / tot) - int(pts * int(c.get("vit", 1)) / tot)
	hero.stat_points = 0
	hero.talents = Talents.auto_build(hero.cls, hero.free_talent_points(), hero.talents)
	hero._talents_changed()
	hero.gold += 1000000
	hero.belt = [Items.potion("hp_potion"), Items.potion("hp_potion"), Items.potion("mp_potion"), Items.potion("rejuv")]
	for b in hero.belt:
		b["count"] = 20
	var r := RandomNumberGenerator.new()
	r.randomize()
	var n := 0
	for i in 60:
		if n >= 16:
			break
		var it := Items.random_drop(99, 2000.0, r, true)
		if Items.is_material(it) or int(it.get("rarity", 0)) < 2:
			continue
		if hero.add_to_inventory(it):
			n += 1
	hero.recalc()
	hero.life = hero.max_life
	hero.mana = hero.max_mana
	ui.refresh()
	save_game()
	ui.big_message("MAXED OUT")
	ui.message("Level 99, every rite, a million gold and %d pieces of the best gear in your bag" % n, Color(1.0, 0.85, 0.4), 6.0)

func _unhandled_input(ev: InputEvent) -> void:
	if not playing or _busy or world == null or loading.visible:
		return      # (the title and its screens, and a zone loading: nothing in the game takes keys or clicks)
		# (nor behind the loading screen while a join waits for its server: the camp behind it would send the
		# skills' and clicks' messages down a link not yet connected; triage 2026-11-04)
	_cheat_keys(ev)
	if _orbit_input(ev):
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
				elif not click_move and hero.bound("lmb") == "attack" and not (hovered is GroundItem or hovered is Inter) \
						and (wasd_dir().length() > 0.1 or not (hovered is Enemy)):
					# Path of Exile controls: the click attacks toward the pointer where he stands (or as the
					# keys carry him); a foe clicked while standing still is walked up to and struck
					hero.target = null
					hero.swipe_attack(_attack_aim())
				else:
					_click_world()
		elif ev.button_index == MOUSE_BUTTON_RIGHT:
			if ev.pressed and not paused:
				rmb_held = true
				_use_bind("rmb", true)
		elif ev.button_index == MOUSE_BUTTON_WHEEL_UP and ev.pressed:
			zoom = clampf(zoom - 0.08, 0.6, zoom_max)
		elif ev.button_index == MOUSE_BUTTON_WHEEL_DOWN and ev.pressed:
			zoom = clampf(zoom + 0.08, 0.6, zoom_max)
	if ev is InputEventKey and ev.pressed and not ev.echo:
		if paused and ev.keycode != KEY_ESCAPE:
			return       # (paused: only Esc, which resumes)
		if ui.spectate_panel.visible and ev.keycode in [KEY_TAB, KEY_LEFT, KEY_RIGHT]:
			spectate_next(-1 if ev.keycode == KEY_LEFT or (ev.keycode == KEY_TAB and ev.shift_pressed) else 1)
			return
		match ev.keycode:
			KEY_ESCAPE:
				if not ui.close_all():
					toggle_pause()
			KEY_I, KEY_B, KEY_K, KEY_N when hero.run != null:
				# a run character's one build window (RunUI): skills, spellbook, passives, gear, consumables
				if ui.run_ui.mode == "build":
					ui.run_ui.close()
				else:
					ui.close_all()
					ui.run_ui.open_build()
			KEY_I, KEY_B:
				ui.toggle(ui.inv_panel)
			KEY_C:
				ui.toggle(ui.char_panel)
			KEY_T:
				cast_town_portal()
			KEY_SPACE:
				dodge_roll()
			KEY_1, KEY_2, KEY_3, KEY_4:
				hero.drink(ev.keycode - KEY_1)
			KEY_G, KEY_V when hero.run != null:
				pass      # (a run has five slots: right mouse and Q E R F)
			KEY_Q, KEY_E, KEY_R, KEY_F, KEY_G, KEY_V:
				if not ui.skills_hotkey(OS.get_keycode_string(ev.keycode)):
					_use_bind(OS.get_keycode_string(ev.keycode), true)
			KEY_K:
				ui.toggle(ui.skills_panel)
			KEY_N:
				ui.toggle(ui.talent_panel)
			KEY_J:
				ui.toggle(ui.quest_panel)
			KEY_F3:
				ui.show_fps = not ui.show_fps
			KEY_F2:
				set_sound(not sound_on)
				ui.message("Sound " + ("on" if sound_on else "off"), Color(0.8, 0.85, 1.0))
				ui.update_sound_btn()
			KEY_F8:
				if dev_tools and not paused:
					toggle_pause()          # (the admin tools are in the Escape menu)
			KEY_M:
				ui.minimap.visible = not ui.minimap.visible
			KEY_TAB:
				ui.minimap.visible = true
				ui.minimap.set_big(not ui.minimap.big)

func _input(ev: InputEvent) -> void:
	if ev is InputEventMouseButton and ev.button_index == MOUSE_BUTTON_LEFT and not ev.pressed:
		lmb_held = false
	if ev is InputEventMouseButton and ev.button_index == MOUSE_BUTTON_RIGHT and not ev.pressed:
		rmb_held = false

## Controls: Path of Exile 2's by default (WASD moves, left click attacks toward the pointer, right click a skill,
## Space rolls); `click_move` (pause menu, saved) brings back clicking the ground to walk there.
var click_move := false
var roll_sprint := false

## The movement keys as a flat direction on the ground (W = up the screen).
func wasd_dir() -> Vector3:
	var v := Vector3.ZERO
	if Input.is_key_pressed(KEY_W): v.z -= 1
	if Input.is_key_pressed(KEY_S): v.z += 1
	if Input.is_key_pressed(KEY_A): v.x -= 1
	if Input.is_key_pressed(KEY_D): v.x += 1
	return v.normalized() if v.length() > 0.1 else Vector3.ZERO

## Space: roll the way the keys point, or toward the pointer with no key held.
func dodge_roll() -> void:
	if hero == null or hero.arena_waiting() or paused or ui.any_panel_open():
		return
	var d := wasd_dir()
	if d.length() < 0.1:
		_update_hover()
		d = hero.dir_to(ground_pt)
	if Dodge.start(hero, d):
		roll_sprint = true

func set_click_move(on: bool) -> void:
	click_move = on
	_save_setting("controls", "click_move", on)

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

## The left click's swing: at the foe under the pointer, else at a foe close to the pointer's line within reach,
## else toward the pointer (the same melee help a short directional skill gets, Hero.skill_aim).
func _attack_aim() -> Vector3:
	if hovered is Enemy:
		return hovered.global_position
	var dir := hero.dir_to(ground_pt)
	var best = hero._assist_pick(dir, hero.reach() + 1.5, Hero.AIM_CONE_MELEE)
	if best != null and not hero.has_bow():
		return best.global_position
	# a bow shoots at the pointer (Archer.shoot has its own help near the point)
	return ground_pt if hero.has_bow() else hero.global_position + dir * (hero.reach() + 1.0)

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
## Autosave (Blaine, 2026-11-05: a host leaving or a crash must never cost loot): the character is saved every
## AUTOSAVE_EVERY seconds while playing and when the window is closed (it was saved only on zone changes, boss kills
## and the menu's Save and Exit, so a Cmd+Q lost everything since the last zone). Not in a raid, an arena match or
## the sandbox, which keep their own rules.
const AUTOSAVE_EVERY := 60.0
var _autosave_t := 0.0

func can_autosave() -> bool:
	return playing and not _busy and not bg_mode and not arena_mode and sandbox == null and char_id != "" \
		and shot_path == "" and net != null and not net.server and hero != null

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST and can_autosave():
		save_game()

func _process(delta: float) -> void:
	ResCache.pump()                  # (collects what the loader's threads finished)
	_autosave_t += delta
	if _autosave_t >= AUTOSAVE_EVERY:
		_autosave_t = 0.0
		if can_autosave():
			save_game()
	if arena_mode:
		Battlegrounds.sync_proxies(self)
	if (arena_mode or bg_mode) and net.active and not net.server:
		ServerRules.client_tick(self, delta)      # (the build the server's copy of this player deals its skills with)
	elif net.server and bg != null:
		Battlegrounds.sync_proxies(self)      # (the server's own stand-ins: what players' skills run here strike)
	if bg_mode:
		Battlegrounds.sync_proxies(self)
		Battlegrounds.hud(self, delta)
	elif ui != null and ui.hud.get_node_or_null("bg_hud") != null:
		ui.hud.get_node("bg_hud").visible = false
	if not net.is_client():
		Camps.leash(self, delta)
	_t += delta
	var real_dt := delta / maxf(Engine.time_scale, 0.01)
	_watchdog(real_dt)
	if net.server:
		Kpi.server_tick(real_dt)
	else:
		Kpi.step(real_dt)
	if world == null:
		return
	xp_bonus_t = maxf(0.0, xp_bonus_t - delta)
	if playing and not paused:
		played_s += delta
	exit_grace = maxf(0.0, exit_grace - delta)
	_drop_stale()
	_update_grade(real_dt)
	if Engine.time_scale < 1.0 and Time.get_ticks_msec() > _hitstop_until:
		Engine.time_scale = 1.0
	if playing and not _busy and loading.visible and hero != null:
		hero.cmd_wasd(Vector3.ZERO)      # (keys held as the loading screen came up don't walk him on behind it)
		hero.blocking = false
	if playing and not paused and not _busy and not loading.visible:
		_update_hover()
		hero.cursor = _cursor_aim()     # the pointer aims everything (see Hero's aiming notes)
		hero.blocking = (skill_held("block") or test_block) and not ui.any_panel_open()
		for slot in Hero.BIND_SLOTS:
			if slot != "lmb" and slot_held(slot):
				_use_bind(slot, false)
		# Shift sprints; so does Space held on after a dodge roll (Path of Exile 2).
		if not Input.is_key_pressed(KEY_SPACE):
			roll_sprint = false
		hero.sprint = Input.is_key_pressed(KEY_SHIFT) or (roll_sprint and hero.roll_t < 0.0)
		var wasd := wasd_dir()
		hero.cmd_wasd(wasd)
		if lmb_held and not hero.dead:
			lmb_repeat -= delta
			if lmb_repeat <= 0.0:
				lmb_repeat = 0.12
				if hero.bound("lmb") not in ["attack", ""] and (hovered is Enemy or Input.is_key_pressed(KEY_SHIFT)):
					_use_bind("lmb", false)
				elif click_move == false and hero.bound("lmb") == "attack" and (wasd_dir().length() > 0.1 or not (hovered is Enemy)) \
						and not (hovered is GroundItem or hovered is Inter) and hero.target == null:
					# held: keep swinging toward the pointer (the keys move him)
					hero.swipe_attack(_attack_aim())
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
					# each zone names its arrival spots after where you came from ("from_town", "from_wild", ...)
					travel(cur_act, to, "from_" + cur_zone)
					break
	if death_t > 0.0:
		death_t -= delta
		if death_t <= 0.0 and playing:
			if bg_mode:
				spectate_start()
			else:
				ui.death_panel.visible = true
	_update_spectate(real_dt)
	if hero and world:
		var look_ahead := Vector3.ZERO
		if playing and not hero.dead and shot_path == "":
			var mp := get_viewport().get_mouse_position() / get_viewport().get_visible_rect().size - Vector2(0.5, 0.5)
			look_ahead = Vector3(mp.x, 0, mp.y) * 2.0
		var goal: Vector3 = hero.global_position + look_ahead
		var watched := spectate_hero()
		if watched != null:
			goal = watched.global_position
		var fw := 0.0
		if focus_node != null:
			focus_t += real_dt
			if focus_t >= focus_len or not is_instance_valid(focus_node):
				focus_node = null
			else:
				fw = smoothstep(0.0, 0.6, focus_t) * (1.0 - smoothstep(focus_len - 0.7, focus_len, focus_t))
				goal = goal.lerp(focus_node.global_position + Vector3(0, 0.6, 0), fw)
		# far out over the island the view turns round its middle rather than the hero
		if world.island_r > 0.0 and zoom > 1.3:
			goal = goal.lerp(Vector3(world.island_c.x, 0, world.island_c.y), smoothstep(1.3, zoom_max, zoom))
		if zoom <= ORBIT_ZOOM and not _orbit_drag:
			orbit_yaw = lerp_angle(orbit_yaw, 0.0, clampf(real_dt * 3.0, 0.0, 1.0))
			orbit_pitch = lerpf(orbit_pitch, 0.0, clampf(real_dt * 3.0, 0.0, 1.0))
		cam_target = cam_target.lerp(goal, clampf(real_dt * 5.0, 0.0, 1.0))
		weather.follow(cam_target)
		cam_pivot.position = cam_target
		if not playing:
			cam_pivot.position = hero.global_position + Vector3(sin(_t * 0.12) * 3.0, 0, cos(_t * 0.1) * 1.5)
		shake = maxf(0.0, shake - real_dt * 2.2)
		var sh := Vector3(randf_range(-1, 1), randf_range(-1, 1), 0) * shake * shake * 0.35
		cam.position = _orbit_offset(CAM_OFFSET * zoom * lerpf(1.0, focus_zoom, fw)) + sh
		cam.basis = Basis.looking_at(Vector3(0, 1.0, 0) - cam.position, Vector3.UP)    # (turned by the orbit, if any)
		_fit_shadows()
		RenderingServer.global_shader_parameter_set("player_pos", watched.global_position if watched != null else hero.global_position)
		if grass_field:
			grass_field.center = cam_target
			grass_field.cam_pos = cam.global_position
	_update_underworld(real_dt)
	for l in get_tree().get_nodes_in_group("flicker"):
		var lt := l as OmniLight3D
		var b: float = lt.get_meta("base", 1.0) * (fire_mul if lt.has_meta("fire") else lamp_mul)
		var id := float(lt.get_instance_id() % 100)
		if lt.has_meta("fire"):
			# a real fire's light: slow breathing, quicker licks and a ragged flutter, never in step with another
			lt.light_energy = b * (0.8 + 0.09 * sin(_t * 3.1 + id) + 0.07 * sin(_t * 8.7 + id * 1.7) + 0.05 * sin(_t * 17.3 + id * 2.9) + 0.03 * sin(_t * 31.0 + id * 4.1))
		else:
			lt.light_energy = b * (0.85 + 0.1 * sin(_t * 9.0 + id) + 0.07 * sin(_t * 23.0 + id * 2.3))
	if shot_path != "" and not _busy and world:
		shot_frames += 1
		if shot_frames == 50:
			_shot_setup()
		if _perf_step():
			return
		if shot_frames == (320 if OS.get_cmdline_user_args().has("--spill") else 150 if OS.get_cmdline_user_args().has("--inv") else (120 if OS.get_cmdline_user_args().has("--dragtest") else (62 if OS.get_cmdline_user_args().has("--snowtest") else 90))):
			var img := get_viewport().get_texture().get_image()
			img.save_png(shot_path)
			print("saved ", shot_path)
			get_tree().quit()

## Performance capture for any build (an exported game too), e.g.
##   AshenCrown.exe -- --shot grass.png --zone bg --perf 12 --quality 2 --grassspot
## --grassspot stands the hero in open grass off the road, --perf N walks him in a loop for N seconds
## measuring every frame, then writes <shot>.txt (frame times, draw calls, primitives, GPU) and the shot.
var _perf := {}
func _perf_step() -> bool:
	var args := OS.get_cmdline_user_args()
	var pi := args.find("--perf")
	if pi < 0:
		return false
	if _perf.is_empty():
		var qi := args.find("--quality")
		if qi >= 0 and qi + 1 < args.size():
			set_quality(int(args[qi + 1]))
		if args.has("--grassspot"):
			var spot := _open_grass_spot()
			hero.global_position = spot
			cam_target = spot
		_perf = {"centre": hero.global_position, "t": 0.0, "frames": [], "dc": 0.0, "prims": 0.0, "objs": 0.0, "n": 0,
			"secs": float(args[pi + 1]) if pi + 1 < args.size() and args[pi + 1].is_valid_float() else 10.0, "t0": 0,
			"gpu": 0.0, "cpu": 0.0, "boot_ms": Time.get_ticks_msec()}
		RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(), true)
		return true
	var dt := get_process_delta_time()
	if shot_frames < 70:
		return true   # settle (shaders compiled, field running)
	if int(_perf["t0"]) == 0:
		_perf["t0"] = Time.get_ticks_usec()
	_perf["t"] = float(_perf["t"]) + dt
	var a := float(_perf["t"]) * 0.9
	hero.global_position = (_perf["centre"] as Vector3) + Vector3(cos(a), 0, sin(a)) * 3.0
	(_perf["frames"] as Array).append(dt * 1000.0)
	_perf["dc"] = float(_perf["dc"]) + Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
	_perf["prims"] = float(_perf["prims"]) + Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)
	_perf["objs"] = float(_perf["objs"]) + Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)
	_perf["n"] = int(_perf["n"]) + 1
	var vp_rid := get_viewport().get_viewport_rid()
	_perf["gpu"] = float(_perf["gpu"]) + RenderingServer.viewport_get_measured_render_time_gpu(vp_rid)
	_perf["cpu"] = float(_perf["cpu"]) + RenderingServer.viewport_get_measured_render_time_cpu(vp_rid)
	if float(_perf["t"]) < float(_perf["secs"]):
		return true
	var fr: Array = _perf["frames"]
	fr.sort()
	var n := maxi(1, int(_perf["n"]))
	var wall := float(Time.get_ticks_usec() - int(_perf["t0"])) / 1e6
	var worst1 := 0.0
	var k := maxi(1, int(fr.size() * 0.01))
	for i in k:
		worst1 += float(fr[fr.size() - 1 - i])
	worst1 /= k
	var grass_n := 0
	for gr in get_tree().get_nodes_in_group("grass"):
		grass_n += (gr as MultiMeshInstance3D).multimesh.instance_count if gr.has_meta("grass3d") and int(gr.get_meta("grass3d")) == 0 else 0
	var lines := [
		"Ashen Crown perf: zone %s, preset %s, %s, %s" % [shot_zone, QUALITY_NAMES[quality], "Forward+" if is_forward() else "Compatibility", RenderingServer.get_video_adapter_name()],
		"resolution %s, %d frames in %.1f s" % [get_viewport().get_visible_rect().size, n, wall],
		"average %.1f fps (%.2f ms), median %.2f ms, 1%% low %.1f fps (%.2f ms)" % [n / wall, wall * 1000.0 / n, float(fr[fr.size() / 2]), 1000.0 / worst1, worst1],
		"draw calls %.0f, primitives %.0f, objects %.0f (per frame)" % [float(_perf["dc"]) / n, float(_perf["prims"]) / n, float(_perf["objs"]) / n],
		"3D grass clumps in the zone: %d" % grass_n,
		"gpu %.2f ms per frame (busy %.0f%%), render cpu %.2f ms, engine start to zone ready %d ms" % [float(_perf["gpu"]) / n, 100.0 * float(_perf["gpu"]) / n / (wall * 1000.0 / n), float(_perf["cpu"]) / n, int(_perf["boot_ms"])],
		"video memory %.0f MB (textures %.0f MB, buffers %.0f MB), static memory %.0f MB" % [Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1e6, Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED) / 1e6, Performance.get_monitor(Performance.RENDER_BUFFER_MEM_USED) / 1e6, Performance.get_monitor(Performance.MEMORY_STATIC) / 1e6],
	]
	var f := FileAccess.open(shot_path.get_basename() + ".txt", FileAccess.WRITE)
	for l in lines:
		print("[PERF] ", l)
		if f:
			f.store_line(l)
	if f:
		f.close()
	var img := get_viewport().get_texture().get_image()
	img.save_png(shot_path)
	print("saved ", shot_path)
	get_tree().quit()
	return true

## The grassiest open spot near the hero: 9-16 m off the road, nothing solid within 4 m.
func _open_grass_spot() -> Vector3:
	var start: Vector3 = hero.global_position
	var best := start
	var best_s := -1.0
	var r := RandomNumberGenerator.new()
	r.seed = 77
	for i in 600:
		var p := start + Vector3(r.randf_range(-40, 40), 0, r.randf_range(-40, 40))
		var d: float = world.path_dist(p.x, p.z)
		if d < 9.0 or d > 16.0 or world.is_blocked(p.x, p.z) or world.is_near_obstacle(p, 4.0):
			continue
		if world.dirt_at(p.x, p.z) + world.cobble_at(p.x, p.z) > 0.05:
			continue
		var sc := 40.0 - p.distance_to(start)
		if sc > best_s:
			best_s = sc
			best = p
	best.y = world.height_at(best.x, best.z)
	return best

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
	if args.has("--guard-fight") and cur_zone == "town":
		# the camp's guards (CampGuard) against a few zombies loose in the camp
		for i in 4:
			var ze := spawn_enemy("zombie", Vector3(-6.0 + i * 3.5, 0, -6.0), 3)
			if ze != null:
				ze.aggro = true
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
