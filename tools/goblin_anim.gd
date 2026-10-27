extends SceneTree
## Contact sheet of King Grubb's motion: each row is one action (walk, idle, swing, slam, bomb
## throw, scoop, stagger, cackle, coin-biting idle), sampled across its length.
## Usage: -- out.png [cols]
const CELL := 220

func _initialize():
	var args := OS.get_cmdline_user_args()
	var cols := int(args[1]) if args.size() > 1 else 8
	var root3 := Node3D.new()
	get_root().add_child(root3)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.05, 0.045, 0.05)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.5, 0.5, 0.55)
	e.ambient_light_energy = 0.7
	e.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.environment = e
	root3.add_child(env)
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-45, -30, 0)
	key.light_energy = 1.2
	root3.add_child(key)
	var ground := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(20, 20)
	ground.mesh = pm
	ground.material_override = Mats.mat(Color(0.2, 0.19, 0.18), 0.95)
	root3.add_child(ground)
	var king := Goblin.build("mutant")
	root3.add_child(king)
	king.rotation_degrees.y = 215
	var cam := Camera3D.new()
	root3.add_child(cam)
	cam.transform = Transform3D(Basis(), Vector3(1.8, 3.2, 7.2)).looking_at(Vector3(0, 1.6, 0))
	cam.fov = 40
	# [label, style, seconds, moving, aggro]
	var rows := [["walk", "", 1.0, true, true], ["idle", "", 2.0, false, true], ["swing", "smash", 1.3, false, true],
		["slam", "slam", 1.25, false, true], ["bomb", "lob", 1.25, false, true], ["scoop", "scoop", 1.25, false, true],
		["stagger", "burst", 1.25, false, true], ["cackle", "cackle", 1.25, false, true], ["coin", "", 2.2, false, false]]
	var sheet := Image.create(CELL * cols, CELL * rows.size(), false, Image.FORMAT_RGBA8)
	var t := 0.0
	var ph := 0.0
	for r in rows.size():
		var row: Array = rows[r]
		var dur: float = row[2]
		var steps := 30 * int(ceil(dur))
		var sample := 0
		for f in steps + 1:
			var u := float(f) / steps
			t += dur / steps
			if row[3]:
				ph += dur / steps * 7.0
			var st := {"time": t, "phase": ph, "move": 1.0 if row[3] else 0.0, "aggro": row[4]}
			if row[1] != "" and u <= 1.0:
				st["atk"] = u
				st["style"] = row[1]
			Anim.pose(king, st)
			await process_frame
			if sample < cols and f >= int(float(sample) / max(cols - 1, 1) * steps):
				await RenderingServer.frame_post_draw
				var img := get_root().get_texture().get_image()
				var side := mini(img.get_width(), img.get_height())
				img = img.get_region(Rect2i((img.get_width() - side) / 2, (img.get_height() - side) / 2, side, side))
				img.resize(CELL, CELL)
				img.convert(Image.FORMAT_RGBA8)
				sheet.blit_rect(img, Rect2i(0, 0, CELL, CELL), Vector2i(sample * CELL, r * CELL))
				sample += 1
		print("[G] ", row[0])
	sheet.save_png(args[0])
	print("saved")
	quit()
