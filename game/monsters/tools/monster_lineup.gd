extends SceneTree
## Contact sheet of monsters on their in-game bodies (Monsters.build_rig, posed by Monsters.pose_rig: the very rig and
## animation the game uses): one row per kind (idle, walk, run, attack frames) in a lit studio, so every monster can be
## seen rigged and moving. Usage: -- out.png [kind ...]   (Data.ENEMIES keys; none: every kind). Through tools/_late.gd.
const CELL := 200

func _initialize():
	var args: Array = Array(OS.get_cmdline_user_args()).filter(func(x): return not str(x).begins_with("res://"))
	var kinds: Array = args.slice(1)
	if kinds.is_empty():
		kinds = Data.ENEMIES.keys()
	var root3 := Node3D.new()
	get_root().add_child(root3)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.08, 0.08, 0.09)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.55, 0.56, 0.6)
	e.ambient_light_energy = 0.75
	e.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.environment = e
	root3.add_child(env)
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-40, -35, 0)
	key.light_energy = 1.3
	key.shadow_enabled = true
	root3.add_child(key)
	var ground := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(30, 30)
	ground.mesh = pm
	ground.material_override = Mats.mat(Color(0.2, 0.21, 0.16), 0.95)
	root3.add_child(ground)
	var cam := Camera3D.new()
	cam.fov = 32
	root3.add_child(cam)
	var cols := 6
	var sheet := Image.create(CELL * cols, CELL * kinds.size(), false, Image.FORMAT_RGBA8)
	for r in kinds.size():
		var def: Dictionary = Data.ENEMIES[kinds[r]]
		var look: Dictionary = def["look"]
		var rig: Node3D = Monsters.build_rig(kinds[r])
		rig.set_meta("pers", {"zombie": "zombie", "skel_archer": "skeleton", "fallen": "fallen"}.get(kinds[r], "warrior"))
		root3.add_child(rig)
		rig.rotation_degrees.y = 200
		var h: float = float(look.get("height", 1.0)) * 1.8
		cam.transform = Transform3D(Basis(), Vector3(0.5 * h, 0.7 * h, 1.75 * h + 0.6)).looking_at(Vector3(0, h * 0.5, 0))
		var t := 0.0
		var ph := 0.0
		# [move, atk (or -1)]
		var poses := [[0.0, -1.0], [0.5, -1.0], [0.5, -1.0], [1.0, -1.0], [0.0, 0.35], [0.0, 0.62]]
		for c in cols:
			for f in 12:
				t += 1.0 / 30.0
				ph += (1.0 / 30.0) * 4.0 * poses[c][0] / maxf(h / 1.8, 0.5)
				Monsters.pose_rig(rig, {"time": t, "phase": ph, "move": poses[c][0], "atk": poses[c][1], "style": def["atk"], "zombie": kinds[r] == "zombie", "aggro": true}, float(look.get("height", look.get("size", 1.0))))
				await process_frame
			await RenderingServer.frame_post_draw
			var img := get_root().get_texture().get_image()
			var side := mini(img.get_width(), img.get_height())
			img = img.get_region(Rect2i((img.get_width() - side) / 2, (img.get_height() - side) / 2, side, side))
			img.resize(CELL, CELL)
			img.convert(Image.FORMAT_RGBA8)
			sheet.blit_rect(img, Rect2i(0, 0, CELL, CELL), Vector2i(c * CELL, r * CELL))
		rig.queue_free()
	sheet.save_png(args[0])
	print("saved")
	quit()
