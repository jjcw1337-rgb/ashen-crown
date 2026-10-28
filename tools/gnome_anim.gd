extends SceneTree
## Contact sheet of the gnome Warlock's motion (the hero's animation on his rig): idle, walk, run,
## the three swings, a spell cast, holding Drain Life and taking a hit. The first cell of the first
## row stands him next to the knight for scale. Usage: -- out.png [cols]
const CELL := 220

func _initialize():
	var args := OS.get_cmdline_user_args()
	var cols := int(args[1]) if args.size() > 1 else 6
	var root3 := Node3D.new()
	get_root().add_child(root3)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.05, 0.045, 0.05)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.55, 0.55, 0.6)
	e.ambient_light_energy = 0.8
	e.tonemap_mode = Environment.TONE_MAPPER_ACES
	e.glow_enabled = true
	env.environment = e
	root3.add_child(env)
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-45, -30, 0)
	key.light_energy = 1.3
	root3.add_child(key)
	var ground := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(20, 20)
	ground.mesh = pm
	ground.material_override = Mats.mat(Color(0.2, 0.19, 0.18), 0.95)
	root3.add_child(ground)
	var w := Warlock.build(Warlock.default_gear())
	w.set_meta("pers", "hero")
	root3.add_child(w)
	w.rotation_degrees.y = 210
	var J: Dictionary = w.get_meta("j")
	(J["grip_r"] as Node3D).add_child(Models.item_model({"base": "short_sword", "rarity": 1}))
	var knight := Knight.build(Knight.default_gear())
	root3.add_child(knight)
	knight.position = Vector3(1.1, 0, -0.3)
	knight.rotation_degrees.y = 210
	knight.visible = false
	var cam := Camera3D.new()
	root3.add_child(cam)
	cam.transform = Transform3D(Basis(), Vector3(1.0, 1.7, 2.9)).looking_at(Vector3(0, 0.75, 0))
	cam.fov = 34
	# [label, style, seconds, move, atk override]
	var rows := [["idle", "", 2.0, 0.0], ["walk", "", 1.0, 1.0], ["run", "", 0.8, 1.3], ["swing 1", "over", 0.6, 0.0],
		["swing 2", "back", 0.6, 0.0], ["swing 3", "thrust", 0.6, 0.0], ["cast", "cast", 0.8, 0.0], ["drain", "drain", 1.0, 0.0], ["hit", "hit", 0.6, 0.0]]
	var sheet := Image.create(CELL * cols, CELL * rows.size(), false, Image.FORMAT_RGBA8)
	var t := 0.0
	var ph := 0.0
	for r in rows.size():
		var row: Array = rows[r]
		var dur: float = row[2]
		var mv: float = row[3]
		knight.visible = r == 0
		var steps := 30 * int(ceil(dur))
		var sample := 0
		for f in steps + 1:
			var u := float(f) / steps
			var dt := dur / steps
			t += dt
			ph += dt * (mv * 4.5) * 2.9 / maxf(mv, 0.6) * float(w.get_meta("stride")) if mv > 0.0 else 0.0
			var st := {"time": t, "phase": ph, "move": mv}
			match row[1]:
				"drain":
					st["atk"] = 0.6
					st["style"] = "cast"
				"hit":
					st["hit"] = 1.0 - u
				"":
					pass
				_:
					st["atk"] = u
					st["style"] = row[1]
			Anim.pose(w, st)
			Warlock.animate(w, t, mv, 1.0 if row[1] == "drain" else 0.0)
			Anim.pose(knight, {"time": t, "phase": 0.0, "move": 0.0})
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
	sheet.save_png(args[0])
	print("saved")
	quit()
