extends SceneTree
## Contact sheet of the archer's wolf (spirit_beast.gd's body, Lion.pose): rows of its run, its pounce
## ("feral_lunge") and its bite ("feral_swipe"). Needs a display.   godot --path . -s tools/wolf_sheet.gd -- out.png [side|34]
const CELL := 260

func _initialize():
	await process_frame
	var a := OS.get_cmdline_user_args()
	var out: String = a[0]
	var view: String = a[1] if a.size() > 1 else "side"
	var root3 := Node3D.new()
	get_root().add_child(root3)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.3, 0.33, 0.36)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.8, 0.78, 0.75)
	e.ambient_light_energy = 1.0
	e.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.environment = e
	root3.add_child(env)
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-40, -35, 0)
	key.light_energy = 1.6
	key.shadow_enabled = true
	root3.add_child(key)
	var ground := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(30, 30)
	ground.mesh = pm
	ground.material_override = Mats.mat(Color(0.3, 0.32, 0.24), 0.95)
	root3.add_child(ground)
	var cam := Camera3D.new()
	cam.fov = 30
	root3.add_child(cam)
	var cpos := Vector3(5.2, 1.0, 0.0) if view == "side" else Vector3(3.6, 2.0, -3.6)
	cam.transform = Transform3D(Basis(), cpos).looking_at(Vector3(0, 0.6, 0))
	var SB = load("res://scripts/spirit_beast.gd")
	var LionS = load("res://scripts/lion.gd")
	var rig: Node3D = LionS.build(SB.WOLF_GLB, 1.0)
	root3.add_child(rig)
	var rows := [["run", [0.0, 0.17, 0.33, 0.5, 0.67, 0.83]], ["feral_lunge", [0.1, 0.25, 0.4, 0.55, 0.7, 0.9]], ["feral_swipe", [0.1, 0.22, 0.32, 0.45, 0.6, 0.85]]]
	var sheet := Image.create(CELL * 6, CELL * rows.size(), false, Image.FORMAT_RGBA8)
	for r in rows.size():
		for c in 6:
			var v: float = rows[r][1][c]
			var st := {"time": 1.0 + c * 0.37, "phase": 0.0, "move": 0.0, "atk": -1.0, "style": ""}
			if rows[r][0] == "run":
				st["move"] = 1.2
				st["phase"] = v * TAU
			else:
				st["atk"] = v
				st["style"] = rows[r][0]
			LionS.pose(rig, st, 1.2)
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
