extends SceneTree
## The camp's grand waypoint alone, on a flagstone floor under the forest camp's dusk light, from the game's camera
## (or closer), for fast iteration on its look without building the whole camp. Needs a display:
##   xvfb-run -a godot --rendering-driver opengl3 --fixed-fps 30 --path . -s game/maps/camp/tools/waypoint_lab.gd -- outdir [frames] [step] [view] [quality]
## view: game (the game camera over a hero at the arrival spot) | ref (lower and closer, like the concept picture) |
## close (the crystal and the floor) | high (from above). Saves outdir/lab_NN.png (one frame by default, after it
## has woken and settled).
var grand: Node3D
var hero: Node3D
var _t := 0.0

func _initialize():
	_run()

func _run() -> void:
	# the autoloads (Sfx) exist only after the first frame; the game's scripts are loaded then, by hand
	await process_frame
	var WG = load("res://game/maps/camp/waypoint_grand.gd")
	var MatsS = load("res://scripts/mats.gd")
	var PropsS = load("res://scripts/props.gd")
	var GradeS = load("res://scripts/grade.gd")
	var InfS = load("res://scripts/infernal_fx.gd")
	var a := OS.get_cmdline_user_args()
	var out: String = a[0] if a.size() > 0 else "/tmp/wplab"
	var frames := int(a[1]) if a.size() > 1 else 1
	var step := int(a[2]) if a.size() > 2 else 3
	var view: String = a[3] if a.size() > 3 else "game"
	var quality := int(a[4]) if a.size() > 4 else 0
	DirAccess.make_dir_recursive_absolute(out)
	InfS.force_tier = quality
	var root := Node3D.new()
	root.name = "World"
	get_root().add_child(root)
	# --- the camp's dusk (Game._zone_env, the forest camp branch) and its graphics preset's post effects
	var env := Environment.new()
	var sky := Sky.new()
	var sm := ProceduralSkyMaterial.new()
	sm.sky_top_color = Color(0.1, 0.13, 0.17)
	sm.sky_horizon_color = Color(0.24, 0.29, 0.31)
	sm.ground_bottom_color = Color(0.16, 0.18, 0.15)
	sm.ground_horizon_color = Color(0.2, 0.24, 0.25)
	sky.sky_material = sm
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.62
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_white = 6.0
	env.tonemap_exposure = 1.5
	env.fog_enabled = true
	env.fog_light_color = Color(0.2, 0.26, 0.29)
	env.fog_density = 0.009
	env.fog_sky_affect = 0.6
	env.fog_height = 1.2
	env.fog_height_density = 0.1
	env.glow_enabled = true
	env.glow_intensity = 0.95
	env.glow_bloom = 0.1
	env.glow_hdr_threshold = 1.1
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SOFTLIGHT
	env.adjustment_enabled = true
	env.adjustment_saturation = 0.97
	env.adjustment_contrast = 1.05
	env.adjustment_color_correction = GradeS.lut("forest_camp")
	var forward := RenderingServer.get_rendering_device() != null
	env.ssao_enabled = quality >= 1 and forward
	env.ssil_enabled = quality >= 2 and forward
	env.ssr_enabled = quality >= 3 and forward
	env.volumetric_fog_enabled = quality >= 2 and forward
	env.volumetric_fog_density = 0.014
	env.volumetric_fog_albedo = Color(0.62, 0.7, 0.72)
	env.volumetric_fog_emission = Color(0.016, 0.022, 0.028)
	var we := WorldEnvironment.new()
	we.environment = env
	root.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-52, -38, 0)
	sun.light_color = Color(0.58, 0.7, 0.92)
	sun.light_energy = 0.6
	sun.shadow_enabled = true
	sun.shadow_blur = 2.2
	root.add_child(sun)
	# --- the ground: the camp's cobbles (World's terrain is replaced by a flagstone slab)
	var floor_m: ShaderMaterial = MatsS.world(Color(0.2, 0.2, 0.19), Color(0.13, 0.13, 0.12), 0.9, 1.1, 0.35, PropsS.MOSS, false)
	var fl := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(60, 60)
	fl.mesh = pm
	fl.material_override = floor_m
	root.add_child(fl)
	# --- the waypoint and a hero-sized figure at the arrival spot (the real one is the game's knight)
	grand = WG.build()
	root.add_child(grand)
	hero = Node3D.new()
	hero.add_to_group("hero")
	root.add_child(hero)
	hero.position = Vector3(0, 0, 3.2)
	var body := MeshInstance3D.new()
	var cm := CapsuleMesh.new()
	cm.radius = 0.3
	cm.height = 1.75
	body.mesh = cm
	body.material_override = MatsS.mat(Color(0.3, 0.1, 0.08), 0.7)
	body.position = Vector3(0, 0.9 + 0.36 * 0.6, 0)
	hero.add_child(body)
	var hl := OmniLight3D.new()
	hl.light_energy = 1.7
	hl.omni_range = 12.0
	hl.light_color = Color(1.0, 0.9, 0.75)
	hl.position = Vector3(0, 2.5, 1.0)
	hero.add_child(hl)
	RenderingServer.global_shader_parameter_set("player_pos", hero.position)
	# --- the camera
	var cam := Camera3D.new()
	root.add_child(cam)
	var focus := hero.position + Vector3(0, 1.0, 0)
	match view:
		"ref":
			focus = Vector3(0, 1.2, 0.5)
			cam.position = focus + Vector3(0, 11.5, 15.0)
			cam.fov = 40.0
		"close":
			focus = Vector3(0, 1.6, 0)
			cam.position = focus + Vector3(0, 5.5, 7.5)
			cam.fov = 36.0
		"high":
			focus = Vector3(0, 0.5, 0)
			cam.position = focus + Vector3(0, 22.0, 8.0)
			cam.fov = 36.0
		_:
			cam.position = focus + Vector3(0, 17.0, 16.5)
			cam.fov = 36.0
	cam.look_at(focus, Vector3.UP)
	cam.current = true
	get_root().msaa_3d = Viewport.MSAA_2X
	# a Game-less run: Grade's shadow picking is the game's; here the nearest two shadow lights get shadows
	for f in 6:
		await process_frame
	var lights := get_nodes_in_group(GradeS.SHADOW_GROUP)
	for n in lights:
		(n as Light3D).shadow_enabled = false
	# wake it: the hero stands on the arrival spot from the start, so wait out the wake (about 3 s)
	for f in 60:
		await process_frame
	for i in frames:
		for f in step:
			await process_frame
		await RenderingServer.frame_post_draw
		get_root().get_texture().get_image().save_png("%s/lab_%02d.png" % [out, i])
		print("[L] saved frame ", i)
	quit()
