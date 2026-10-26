extends SceneTree
## Lineup of skeleton skins. Usage: -- out.png [aim]

func _initialize():
	var args := OS.get_cmdline_user_args()
	var out: String = args[0]
	var aim := args.size() > 1 and args[1] == "aim"
	var root3 := Node3D.new()
	get_root().add_child(root3)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.03, 0.03, 0.035)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.45, 0.48, 0.55)
	e.ambient_light_energy = 0.55
	e.tonemap_mode = Environment.TONE_MAPPER_ACES
	e.tonemap_exposure = 1.15
	env.environment = e
	root3.add_child(env)
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-35, -30, 0)
	key.light_energy = 1.0
	key.light_color = Color(0.8, 0.85, 1.0)
	key.shadow_enabled = true
	root3.add_child(key)
	for x in [-3.0, 3.0]:
		var t := OmniLight3D.new()
		t.light_color = Color(1.0, 0.6, 0.3)
		t.light_energy = 2.2
		t.omni_range = 8.0
		t.position = Vector3(x, 2.4, 2.0)
		root3.add_child(t)
	var ground := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(30, 30)
	ground.mesh = pm
	ground.material_override = Mats.world(Color(0.24, 0.23, 0.21), Color(0.16, 0.15, 0.14), 0.9, 1.4, 0.0, Props.MOSS, false)
	root3.add_child(ground)
	var cam := Camera3D.new()
	root3.add_child(cam)
	var names := ["archer", "archer_fire", "archer_ice"] if not args.has("old") else ["bone", "grave", "charred", "hooded"]
	var letters := ["Main", "Fire", "Ice"] if not args.has("old") else ["A", "B", "C", "D"]
	var rigs := []
	for i in names.size():
		var r := SkeletonModel.build(names[i])
		root3.add_child(r)
		r.position = Vector3((i - (names.size() - 1) * 0.5) * 1.3, 0, -absf(i - 1) * 0.3)
		r.rotation_degrees.y = 200
		rigs.append(r)
		var l := Label3D.new()
		l.text = SkeletonModel.VARIANTS[names[i]]["name"]
		l.font_size = 44
		l.outline_size = 14
		l.pixel_size = 0.0032
		l.modulate = Color(0.95, 0.82, 0.55)
		l.position = r.position + Vector3(0, 2.15, 0)
		l.visible = not args.has("face") and not args.has("face0") and not args.has("face1") and not args.has("face2")
		l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		root3.add_child(l)
	cam.transform = Transform3D(Basis(), Vector3(0.7, 1.5, 3.5)).looking_at(Vector3(0.05, 1.12, 0))
	cam.fov = 45
	if args.has("close"):
		cam.transform = Transform3D(Basis(), Vector3(0.1, 1.4, 2.75)).looking_at(Vector3(0.0, 1.02, 0))
		cam.fov = 42
	var fi := -1
	for k in 3:
		if args.has("face%d" % k):
			fi = k
	if fi >= 0:
		args.append("face")
		for r in rigs:
			r.visible = r == rigs[fi]
		rigs[fi].position = Vector3.ZERO
		rigs[fi].rotation_degrees.y = 205
	if args.has("face"):
		cam.transform = Transform3D(Basis(), Vector3(0.22, 1.82, 0.85)).looking_at(Vector3(0.0, 1.62, 0))
		cam.fov = 38
	for f in 12:
		for i in rigs.size():
			var st := {"time": 2.0 + i * 1.3 + f / 30.0, "phase": 0.0, "move": 0.0}
			if aim:
				st["atk"] = 0.62
				st["style"] = "bow"
			Anim.pose(rigs[i], st)
		await process_frame
	await RenderingServer.frame_post_draw
	get_root().get_texture().get_image().save_png(out)
	print("saved ", out)
	quit()
