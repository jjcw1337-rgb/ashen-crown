extends SceneTree
## The gnome Warlock running past the camera, one row of frames over a couple of strides: his
## pixie dust trails behind him, the hat hops and the weapon waves overhead. A second row is a
## close-up of the hat (red horns). Usage: -- out.png [cols]
const CELL := 330

func _initialize():
	var args := OS.get_cmdline_user_args()
	var cols := int(args[1]) if args.size() > 1 else 8
	var root3 := Node3D.new()
	get_root().add_child(root3)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.07, 0.07, 0.08)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.5, 0.52, 0.55)
	e.ambient_light_energy = 0.7
	e.tonemap_mode = Environment.TONE_MAPPER_ACES
	e.glow_enabled = true
	env.environment = e
	root3.add_child(env)
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-50, -30, 0)
	key.light_energy = 1.1
	key.shadow_enabled = true
	root3.add_child(key)
	var ground := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(40, 40)
	ground.mesh = pm
	ground.material_override = Mats.mat(Color(0.16, 0.2, 0.11), 0.95)
	root3.add_child(ground)
	# the walker: a holder that moves, like the Hero node, with the rig on it
	var host := Node3D.new()
	root3.add_child(host)
	var w := Warlock.build(Warlock.default_gear())
	w.set_meta("pers", "hero")
	host.add_child(w)
	w.rotation_degrees.y = -90   # running toward +X, his right side (the raised weapon) to the camera
	var J: Dictionary = w.get_meta("j")
	(J["grip_r"] as Node3D).add_child(Models.item_model({"base": "short_sword", "rarity": 1}))
	var cam := Camera3D.new()
	root3.add_child(cam)
	cam.fov = 40
	var sheet := Image.create(CELL * cols, CELL * 2, false, Image.FORMAT_RGBA8)
	var t := 0.0
	var ph := 0.0
	var mv := 0.0
	var speed := 4.5
	var stride: float = w.get_meta("stride")
	var dt := 1.0 / 30.0
	for f in 50 + cols * 4:
		t += dt
		mv = move_toward(mv, 1.0, 0.1)
		ph += dt * speed * mv * 2.9 / maxf(mv, 0.6) * stride
		host.position.x += speed * mv * dt
		Anim.pose(w, {"time": t, "phase": ph, "move": mv})
		Warlock.animate(w, t, mv, 0.0, ph, true)
		cam.transform = Transform3D(Basis(), host.position + Vector3(-0.6, 1.8, 3.0)).looking_at(host.position + Vector3(-0.5, 0.75, 0))
		await process_frame
		if f >= 50 and (f - 50) % 4 == 0:
			await RenderingServer.frame_post_draw
			_grab(sheet, (f - 50) / 4, 0)
	# the hat close-up, standing
	for f in 30:
		t += dt
		mv = move_toward(mv, 0.0, 0.1)
		Anim.pose(w, {"time": t, "phase": ph, "move": mv})
		Warlock.animate(w, t, mv, 0.0, ph, true)
		await process_frame
	var head: Vector3 = (J["head"] as Node3D).global_position
	for c in cols:
		w.rotation_degrees.y = 90 + c * 360.0 / cols
		cam.transform = Transform3D(Basis(), head + Vector3(0.0, 0.5, 1.6)).looking_at(head + Vector3(0, 0.25, 0))
		for k in 3:
			t += dt
			Anim.pose(w, {"time": t, "phase": ph, "move": 0.0})
			Warlock.animate(w, t, 0.0, 0.0, ph, true)
			await process_frame
		await RenderingServer.frame_post_draw
		_grab(sheet, c, 1)
	sheet.save_png(args[0])
	print("saved")
	quit()

func _grab(sheet: Image, c: int, r: int) -> void:
	var img := get_root().get_texture().get_image()
	var side := mini(img.get_width(), img.get_height())
	img = img.get_region(Rect2i((img.get_width() - side) / 2, (img.get_height() - side) / 2, side, side))
	img.resize(CELL, CELL)
	img.convert(Image.FORMAT_RGBA8)
	sheet.blit_rect(img, Rect2i(0, 0, CELL, CELL), Vector2i(c * CELL, r * CELL))
