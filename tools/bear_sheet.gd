extends SceneTree
## Contact sheet of the Forsaken Bear's motion (bear.gd): rows of the walk, the rear-and-roar and the maul.
##   godot --path . -s tools/bear_sheet.gd -- out.png [side|34]
const CELL := 300

func _initialize():
	# bear.gd reaches the Sfx autoload: load it at run time, once the tree (and its autoloads) is up
	await process_frame
	var Bear = load("res://scripts/bear.gd")
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
	e.ambient_light_color = Color(0.75, 0.74, 0.72)
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
	cam.fov = 34
	root3.add_child(cam)
	var cpos := Vector3(7.5, 1.6, 0.0) if view == "side" else Vector3(5.2, 3.0, -5.2)
	cam.transform = Transform3D(Basis(), cpos).looking_at(Vector3(0, 1.0, 0))
	var rig: Node3D = Bear.build()
	root3.add_child(rig)
	var rows := [["walk", [0.0, 0.17, 0.33, 0.5, 0.67, 0.83]], ["bear_roar", [0.1, 0.22, 0.3, 0.45, 0.7, 0.88]], ["bear_maul", [0.15, 0.3, 0.4, 0.48, 0.6, 0.85]]]
	var sheet := Image.create(CELL * 6, CELL * rows.size(), false, Image.FORMAT_RGBA8)
	for r in rows.size():
		for c in 6:
			var v: float = rows[r][1][c]
			var st := {"time": 1.0 + c * 0.37, "phase": 0.0, "move": 0.0, "atk": -1.0, "style": ""}
			if rows[r][0] == "walk":
				st["move"] = 1.0
				st["phase"] = v * Bear.STRIDE * 1.6 / 1.6
			else:
				st["atk"] = v
				st["style"] = rows[r][0]
			Bear.pose(rig, st, 1.6)
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
