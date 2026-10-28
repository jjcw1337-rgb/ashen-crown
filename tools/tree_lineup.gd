extends SceneTree
## The oak kinds side by side with the knight for scale, under game-like light. Needs a display.
## Usage: -- out.png [iso|low]
func _initialize():
	_run()

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var out: String = args[0]
	var view: String = args[1] if args.size() > 1 else "iso"
	Mats.ensure_globals()
	var root3 := Node3D.new()
	get_root().add_child(root3)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.2, 0.24, 0.26)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.55, 0.6, 0.62)
	e.ambient_light_energy = 0.7
	e.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.environment = e
	root3.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, -40, 0)
	sun.light_energy = 1.25
	sun.shadow_enabled = true
	root3.add_child(sun)
	var ground := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(60, 60)
	ground.mesh = pm
	ground.material_override = Mats.mat(Color(0.2, 0.26, 0.14), 0.95)
	root3.add_child(ground)
	var meshes := [Flora.oak(9), Flora.oak_model(1), Flora.oak_model(2), Flora.oak_model(3)]
	for i in meshes.size():
		var mi := MeshInstance3D.new()
		mi.mesh = meshes[i]
		mi.position = Vector3(-10.5 + i * 7.0, 0, 0)
		root3.add_child(mi)
	var k: Node3D = Knight.build_meshy() if Knight.meshy_ok() else Knight.build(Knight.default_gear())
	root3.add_child(k)
	k.position = Vector3(-7.0, 0, 2.5)
	Anim.pose(k, {"time": 0.0})
	var cam := Camera3D.new()
	root3.add_child(cam)
	if view == "low":
		cam.fov = 40
		cam.transform = Transform3D(Basis(), Vector3(0, 3.2, 21)).looking_at(Vector3(0, 3.0, 0))
	else:
		cam.fov = 40
		cam.transform = Transform3D(Basis(), Vector3(0, 17, 17)).looking_at(Vector3(0, 1.5, 0))
	for f in 20:
		await process_frame
	await RenderingServer.frame_post_draw
	get_root().get_texture().get_image().save_png(out)
	quit()
