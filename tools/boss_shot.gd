extends SceneTree
## Ashen King showcase next to a knight. Usage: -- out.png [atk]
func _initialize():
	var args := OS.get_cmdline_user_args()
	var root3 := Node3D.new()
	get_root().add_child(root3)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.02, 0.018, 0.02)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.4, 0.42, 0.5)
	e.ambient_light_energy = 0.5
	e.tonemap_mode = Environment.TONE_MAPPER_ACES
	e.glow_enabled = true
	env.environment = e
	root3.add_child(env)
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-40, -35, 0)
	key.light_energy = 0.8
	key.shadow_enabled = true
	root3.add_child(key)
	var t := OmniLight3D.new()
	t.light_color = Color(1.0, 0.55, 0.3)
	t.light_energy = 2.5
	t.omni_range = 9.0
	t.position = Vector3(2.5, 3.0, 2.5)
	root3.add_child(t)
	var ground := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(30, 30)
	ground.mesh = pm
	ground.material_override = Mats.world(Color(0.22, 0.2, 0.19), Color(0.14, 0.13, 0.12), 0.9, 1.4, 0.0, Props.MOSS, false)
	root3.add_child(ground)
	var king := SkeletonModel.build("king")
	king.scale = Vector3.ONE * 1.85
	root3.add_child(king)
	king.rotation_degrees.y = 200
	var hero := Knight.build(Knight.default_gear())
	root3.add_child(hero)
	hero.position = Vector3(1.6, 0, 1.2)
	hero.rotation_degrees.y = 150
	var sword := Models.item_model(Items.make_unique("cinderbrand"))
	root3.add_child(sword)
	sword.position = Vector3(-1.5, 0.9, 1.0)
	sword.rotation_degrees = Vector3(90, 30, 0)
	var cam := Camera3D.new()
	root3.add_child(cam)
	cam.transform = Transform3D(Basis(), Vector3(0.6, 2.4, 5.2)).looking_at(Vector3(0.1, 1.6, 0))
	cam.fov = 45
	if args.has("face"):
		cam.transform = Transform3D(Basis(), Vector3(0.25, 3.5, 1.6)).looking_at(Vector3(0.0, 3.05, 0))
		cam.fov = 40
	for f in 12:
		var st := {"time": 2.0 + f / 30.0, "phase": 0.0, "move": 0.0}
		if args.has("atk"):
			st["atk"] = 0.3
			st["style"] = "over"
		Anim.pose(king, st)
		Anim.pose(hero, {"time": 1.0 + f / 30.0, "phase": 0.0, "move": 0.0})
		await process_frame
	await RenderingServer.frame_post_draw
	get_root().get_texture().get_image().save_png(args[0])
	print("saved")
	quit()
