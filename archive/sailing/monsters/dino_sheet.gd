extends SceneTree
## Contact sheet of a dinosaur's motion (theropod.gd): rows of the walk, the run and its two attacks.
##   godot --path . -s tools/dino_sheet.gd -- out.png raptor|trex [side|34]
const CELL := 300

func _initialize():
	await process_frame
	var T = load("res://scripts/theropod.gd")
	var a := OS.get_cmdline_user_args()
	var out: String = a[0]
	var kind: String = a[1] if a.size() > 1 else "raptor"
	var view: String = a[2] if a.size() > 2 else "side"
	var root3 := Node3D.new()
	get_root().add_child(root3)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.3, 0.33, 0.36)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.75, 0.74, 0.72)
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
	pm.size = Vector2(60, 60)
	ground.mesh = pm
	root3.add_child(ground)
	var rig: Node3D = T.build(kind)
	root3.add_child(rig)
	var hip: float = rig.get_meta("dino_hip")
	var span := hip * 4.2
	var cam := Camera3D.new()
	cam.fov = 34
	root3.add_child(cam)
	var cpos := Vector3(span * 1.9, hip * 1.1, 0.0) if view == "side" else Vector3(span * 1.3, span * 0.8, -span * 1.3)
	cam.transform = Transform3D(Basis(), cpos).looking_at(Vector3(0, hip * 0.9, 0))
	var attacks := ["feral_lunge", "feral_swipe"] if kind == "raptor" else ["bear_roar", "bear_maul"]
	var rows := [["walk", 1.0], ["run", 1.6], [attacks[0], 0.0], [attacks[1], 0.0]]
	var sheet := Image.create(CELL * 6, CELL * rows.size(), false, Image.FORMAT_RGBA8)
	for r in rows.size():
		for c in 6:
			var v := c / 6.0
			var st := {"time": 1.0 + c * 0.37, "phase": 0.0, "move": 0.0, "atk": -1.0, "style": ""}
			if rows[r][0] in ["walk", "run"]:
				st["move"] = rows[r][1]
				st["phase"] = v * T.STRIDE * 1.6
			else:
				st["atk"] = 0.08 + v * 0.84
				st["style"] = rows[r][0]
			T.pose(rig, st, hip)
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
