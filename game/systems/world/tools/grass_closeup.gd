extends SceneTree
## Close-up of every grass species side by side (one row of clumps per species, Grass.SPECIES order, left to
## right), lit like the moor, to judge the Blender clumps and their Meshy textures. Saves one frame.
##   xvfb-run -a godot --rendering-driver opengl3 --resolution 1280x720 --path . -s game/systems/world/tools/grass_closeup.gd -- out.png [lod] [dist]
var out := "grass_closeup.png"
var frames := 0

func _initialize() -> void:
	var a := OS.get_cmdline_user_args()
	if a.size() > 0: out = a[0]
	var lod := int(a[1]) if a.size() > 1 else 0
	var dist := float(a[2]) if a.size() > 2 else 4.0
	var GR: Script = load("res://game/systems/world/grass.gd")
	load("res://game/systems/bodies/mats.gd").ensure_globals()
	RenderingServer.global_shader_parameter_set("wind_strength", 0.25)
	var test := a[3] if a.size() > 3 else ""
	if test == "wind":
		RenderingServer.global_shader_parameter_set("wind_strength", 0.9)
		RenderingServer.global_shader_parameter_set("wind_gust", 1.0)
		RenderingServer.global_shader_parameter_set("wind_phase", 37.0)
	var root := Node3D.new()
	get_root().add_child(root)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.5, 0.56, 0.62)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.55, 0.6, 0.65)
	e.ambient_light_energy = 0.55
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.environment = e
	root.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-38, -35, 0)
	sun.light_energy = 1.25
	sun.light_color = Color(1.0, 0.93, 0.82)
	sun.shadow_enabled = true
	root.add_child(sun)
	var ground := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(30, 30)
	ground.mesh = pm
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color(0.09, 0.1, 0.05)
	gm.roughness = 1.0
	ground.material_override = gm
	root.add_child(ground)
	var mats: Array = GR.material(GR.ACT1, true)
	if lod == 1:
		# LOD1 normally takes over only past Grass.LOD_BAND: hand it over at once for the close-up
		mats = [mats[0].duplicate(), mats[1].duplicate()]
		(mats[1] as ShaderMaterial).set_shader_parameter("lod_band", Vector2(-2.0, -1.0))
	var keys: Array = GR.SPECIES.keys()
	for i in keys.size():
		for k in 3:
			var m: Mesh = GR.glb_mesh(keys[i], k % 2, lod)
			if m == null:
				m = GR.mesh(keys[i], k % 2, lod)
			var mm := MultiMesh.new()
			mm.transform_format = MultiMesh.TRANSFORM_3D
			mm.use_custom_data = true
			mm.mesh = m
			mm.instance_count = 1
			mm.set_instance_transform(0, Transform3D(Basis(Vector3.UP, k * 2.1), Vector3((i - keys.size() / 2.0 + 0.5) * 0.9, 0, (k - 1) * 0.75)))
			if test == "custom":
				mm.set_instance_custom_data(0, Color(randf() * 0.5, randf(), randf(), 0.0))
			else:
				mm.set_instance_custom_data(0, Color(0.0, 0.0, 0.5, 0.0))
			var mmi := MultiMeshInstance3D.new()
			mmi.multimesh = mm
			mmi.material_override = mats[lod]
			root.add_child(mmi)
	var cam := Camera3D.new()
	cam.fov = 36.0
	var pos := Vector3(0, dist * 0.72, dist)
	cam.transform = Transform3D(Basis.looking_at(Vector3(0, 0.15, 0) - pos, Vector3.UP), pos)
	# the shader thins grass by its distance from this point (the game camera's)
	RenderingServer.global_shader_parameter_set("grass_cam", pos)
	root.add_child(cam)

func _process(_d: float) -> bool:
	frames += 1
	if frames == 8:
		var img: Image = get_root().get_texture().get_image()
		img.save_png(out)
		print("[GC] saved ", out)
		quit()
	return false
