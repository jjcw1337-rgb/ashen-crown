extends SceneTree
## Contact sheet of the arena lion's motion (lion.gd) from the side: rows of the trot, the pounce and
## the maul.   godot --path . -s tools/lion_sheet.gd -- out.png
const CELL := 260

func _initialize():
	var out: String = OS.get_cmdline_user_args()[0]
	var root3 := Node3D.new()
	get_root().add_child(root3)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.08, 0.08, 0.09)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.6, 0.58, 0.55)
	e.ambient_light_energy = 0.8
	e.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.environment = e
	root3.add_child(env)
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-40, -35, 0)
	key.light_energy = 1.4
	root3.add_child(key)
	var ground := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(30, 30)
	ground.mesh = pm
	ground.material_override = Mats.mat(Color(0.45, 0.38, 0.26), 0.95)
	root3.add_child(ground)
	var cam := Camera3D.new()
	cam.fov = 30
	root3.add_child(cam)
	cam.transform = Transform3D(Basis(), Vector3(4.6, 1.4, 0.4)).looking_at(Vector3(0, 0.8, 0))
	var rig := Lion.build()
	root3.add_child(rig)
	var rows := [["trot", [0.0, 0.17, 0.33, 0.5, 0.67, 0.83]], ["feral_lunge", [0.1, 0.3, 0.45, 0.55, 0.7, 0.9]], ["feral_swipe", [0.1, 0.22, 0.3, 0.4, 0.6, 0.66]]]
	var sheet := Image.create(CELL * 6, CELL * rows.size(), false, Image.FORMAT_RGBA8)
	for r in rows.size():
		for c in 6:
			var v: float = rows[r][1][c]
			var st := {"time": 1.0 + c * 0.2, "phase": 0.0, "move": 0.0, "atk": -1.0, "style": ""}
			if rows[r][0] == "trot":
				st["move"] = 1.0
				st["phase"] = v * Lion.STRIDE * Lion.SCALE * 1.6 / 1.2
			else:
				st["atk"] = v
				st["style"] = rows[r][0]
			Lion.pose(rig, st, 1.2)
			for f in 3:
				await process_frame
			await RenderingServer.frame_post_draw
			var img := get_root().get_texture().get_image()
			var side := mini(img.get_width(), img.get_height())
			img = img.get_region(Rect2i((img.get_width() - side) / 2, (img.get_height() - side) / 2, side, side))
			img.resize(CELL, CELL)
			img.convert(Image.FORMAT_RGBA8)
			sheet.blit_rect(img, Rect2i(0, 0, CELL, CELL), Vector2i(c * CELL, r * CELL))
	sheet.save_png(out)
	print("saved")
	quit()
