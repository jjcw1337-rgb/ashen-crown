extends SceneTree
## Walk (left) vs sprint (right) comparison frames. Usage: -- outdir frames

func _initialize():
	var args := OS.get_cmdline_user_args()
	var outdir: String = args[0]
	var frames: int = int(args[1])
	var root3 := Node3D.new()
	get_root().add_child(root3)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.09, 0.1, 0.09)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.5, 0.55, 0.55)
	e.ambient_light_energy = 0.75
	e.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.environment = e
	root3.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-45, -60, 0)
	sun.light_energy = 1.4
	sun.shadow_enabled = true
	root3.add_child(sun)
	var ground := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(30, 30)
	ground.mesh = pm
	ground.material_override = Mats.mat(Color(0.2, 0.23, 0.16), 0.95)
	root3.add_child(ground)
	var cam := Camera3D.new()
	root3.add_child(cam)
	cam.transform = Transform3D(Basis(), Vector3(4.2, 2.4, 3.2)).looking_at(Vector3(0, 0.95, -0.2))
	cam.fov = 42
	var rigs := []
	var shields := []
	var rests := []
	for i in 2:
		var g := Knight.default_gear()
		g["armor"] = "chain"
		g["coif"] = true
		var r := Knight.build(g)
		r.set_meta("pers", "hero")
		root3.add_child(r)
		r.position = Vector3(-0.9 + i * 1.8, 0, -i * 1.2)
		r.rotation.y = -PI * 0.5 + 0.35
		var J: Dictionary = r.get_meta("j")
		(J["grip_r"] as Node3D).add_child(Models.item_model({"base": "broad_sword", "rarity": 0}))
		var sh := Models.item_model({"base": "kite_shield", "rarity": 0})
		(J["mount_l"] as Node3D).add_child(sh)
		sh.position = Vector3(-0.03, 0, 0)
		rigs.append(r)
		shields.append(sh)
		rests.append(sh.transform)
	await process_frame
	var fps := 20.0
	var ph := [0.0, 0.0]
	for f in frames:
		var t := f / fps
		for i in 2:
			var m := 1.0 if i == 0 else 1.3
			var spd := 4.8 if i == 0 else 7.7
			ph[i] += spd * 2.9 / m / fps
			Anim.pose(rigs[i], {"time": t, "phase": ph[i], "move": m})
			shields[i].transform = rests[i]
			var run := Anim.run_factor(m)
			if run > 0.0:
				var bob := sin(ph[i] * 2.0) * 0.025
				var tgt: Transform3D = rigs[i].global_transform * Transform3D(Basis(Vector3.UP, 0.55) * Basis(Vector3.RIGHT, -0.15), Vector3(-0.2, 1.2 + bob, -0.36))
				shields[i].global_transform = shields[i].global_transform.interpolate_with(tgt, run * 0.8)
		await process_frame
		await RenderingServer.frame_post_draw
		var img := get_root().get_texture().get_image()
		img.resize(800, 450, Image.INTERPOLATE_LANCZOS)
		img.save_png("%s/r%03d.png" % [outdir, f])
	print("frames done")
	quit()
