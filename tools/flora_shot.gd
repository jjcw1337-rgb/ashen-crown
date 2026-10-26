extends SceneTree
## Current vs new vegetation, side by side. Usage: -- out.png [game|close]

func _initialize():
	var args := OS.get_cmdline_user_args()
	var out: String = args[0]
	var mode: String = args[1] if args.size() > 1 else "game"
	var root3 := Node3D.new()
	get_root().add_child(root3)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	var sky := Sky.new()
	var sm := ProceduralSkyMaterial.new()
	sm.sky_top_color = Color(0.26, 0.3, 0.31)
	sm.sky_horizon_color = Color(0.44, 0.47, 0.44)
	sm.ground_bottom_color = Color(0.16, 0.18, 0.15)
	sm.ground_horizon_color = Color(0.44, 0.47, 0.44)
	sky.sky_material = sm
	e.background_mode = Environment.BG_SKY
	e.sky = sky
	e.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	e.ambient_light_energy = 0.48
	e.tonemap_mode = Environment.TONE_MAPPER_ACES
	e.tonemap_white = 6.0
	e.tonemap_exposure = 1.05
	e.fog_enabled = true
	e.fog_light_color = Color(0.36, 0.4, 0.37)
	e.fog_density = 0.008
	e.adjustment_enabled = true
	e.adjustment_saturation = 0.86
	e.adjustment_contrast = 1.06
	env.environment = e
	root3.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-52, -38, 0)
	sun.light_color = Color(0.86, 0.88, 0.9)
	sun.light_energy = 0.85
	sun.shadow_enabled = true
	sun.shadow_blur = 1.5
	sun.directional_shadow_max_distance = 70.0
	root3.add_child(sun)
	Mats.ensure_globals()
	var ground := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(80, 80)
	ground.mesh = pm
	ground.material_override = Mats.world(Color(0.2, 0.22, 0.12), Color(0.13, 0.14, 0.08), 0.95, 1.2, 0.0, Props.MOSS, false)
	root3.add_child(ground)
	var rng := RandomNumberGenerator.new()
	rng.seed = 4
	# ---- current (left)
	var old_grass: Mesh = Props.grass_mesh(6, 0.3).duplicate()
	var gm := ShaderMaterial.new()
	gm.shader = Mats.shader("grass")
	for k in World.MOOR_GRASS.keys():
		gm.set_shader_parameter(k, World.MOOR_GRASS[k])
	old_grass.surface_set_material(0, gm)
	var xo := []
	for i in 5200:
		var x := rng.randf_range(-14, -0.4)
		var z := rng.randf_range(-9, 9)
		var s := rng.randf_range(0.7, 1.35)
		xo.append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(s, s * rng.randf_range(0.8, 1.3), s)), Vector3(x, -0.02, z)))
	Props.multimesh(root3, old_grass, xo, false)
	_place(root3, Props.bake(Props.pine(2)), Vector3(-6.5, 0, -3.5), 1.1)
	_place(root3, Props.bake(Props.pine(3)), Vector3(-10.5, 0, -1.0), 0.95)
	_place(root3, Props.bake(Props.dead_tree(11)), Vector3(-3.0, 0, 0.5), 1.0)
	_place(root3, Props.bake(Props.oak(12)), Vector3(-9.0, 0, 4.5), 1.0)
	_place(root3, Props.bake(Props.bush(3)), Vector3(-4.5, 0, 4.0), 1.1)
	# ---- new (right)
	var gmat := Flora.grass_mat(World.MOOR_GRASS)
	var clumps := [Flora.grass_clump(1), Flora.grass_clump(2, 15, 0.36), Flora.grass_clump(3, 11, 0.3), Flora.grass_clump(4, 12, 0.33, 2), Flora.grass_clump(5, 12, 0.33, 3)]
	var groups := [[], [], [], [], []]
	for i in 4200:
		var x := rng.randf_range(0.4, 14)
		var z := rng.randf_range(-9, 9)
		var s := rng.randf_range(0.75, 1.3)
		var k := i % 3
		if rng.randf() < 0.07:
			k = 3 + (i % 2)
		groups[k].append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(s, s * rng.randf_range(0.85, 1.25), s)), Vector3(x, -0.02, z)))
	for k in groups.size():
		var mmi := Props.multimesh(root3, clumps[k], groups[k], false)
		mmi.material_override = gmat
	var ferns := []
	for i in 26:
		ferns.append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * rng.randf_range(0.8, 1.3)), Vector3(rng.randf_range(1.5, 13), 0, rng.randf_range(-8, 8))))
	Props.multimesh(root3, Flora.fern(1), ferns, true)
	_place(root3, Flora.pine(2), Vector3(6.5, 0, -3.5), 1.0)
	_place(root3, Flora.pine(3), Vector3(10.5, 0, -1.0), 0.9)
	_place(root3, Flora.dead_tree(11), Vector3(3.0, 0, 0.5), 1.0)
	_place(root3, Flora.oak(12), Vector3(9.0, 0, 4.5), 0.95)
	_place(root3, Flora.bush(3), Vector3(4.5, 0, 4.0), 1.1)
	for side in [-1, 1]:
		var l := Label3D.new()
		l.text = "Current" if side < 0 else "New"
		l.font_size = 72
		l.outline_size = 18
		l.pixel_size = 0.01
		l.modulate = Color(1.0, 0.86, 0.55)
		l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		l.no_depth_test = true
		l.position = Vector3(side * 7.0, 8.5 if mode == "game" else 6.8, -5.0)
		root3.add_child(l)
	var div := MeshInstance3D.new()
	div.mesh = Geo.box(0.06, 0.02, 20)
	div.material_override = Mats.mat(Color(0.9, 0.75, 0.4), 0.5, 0.0, Color(0.9, 0.75, 0.4), 0.6)
	root3.add_child(div)
	var cam := Camera3D.new()
	root3.add_child(cam)
	if mode == "game":
		cam.fov = 36
		cam.transform = Transform3D(Basis(), Vector3(0, 17.0 * 1.25, 16.5 * 1.25 + 1.0)).looking_at(Vector3(0, 1.0, 1.0))
	else:
		cam.fov = 50
		cam.transform = Transform3D(Basis(), Vector3(0, 3.2, 12.5)).looking_at(Vector3(0, 2.4, 0))
	for f in 6:
		await process_frame
	await RenderingServer.frame_post_draw
	get_root().get_texture().get_image().save_png(out)
	print("saved ", out)
	quit()

func _place(parent: Node3D, mesh: Mesh, p: Vector3, s: float) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.position = p
	mi.scale = Vector3.ONE * s
	mi.rotation.y = p.x * 0.7
	parent.add_child(mi)
