extends SceneTree
## Contact sheet of the Hollow Sloth's motion (sloth.gd) from the side: rows of the walk, the run, rising
## and looking about, the roar, the sweep, the slam and the pounce.
##   godot --path . -s tools/sloth_sheet.gd -- out.png [front] [fire|ice|storm]
const CELL := 240

func _initialize():
	var args := OS.get_cmdline_user_args()
	var out: String = args[0]
	var front := args.size() > 1 and args[1] == "front"
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
	# a 1.8 m post for scale (the hero's height)
	var post := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.12, 1.8, 0.12)
	post.mesh = bm
	post.position = Vector3(0, 0.9, 2.2)
	post.material_override = Mats.mat(Color(0.8, 0.2, 0.15), 0.6)
	root3.add_child(post)
	var cam := Camera3D.new()
	cam.fov = 34
	root3.add_child(cam)
	var eye := Vector3(0.5, 2.2, -9.0) if front else Vector3(9.0, 2.0, 0.4)
	cam.transform = Transform3D(Basis(), eye).looking_at(Vector3(0, 1.5, 0))
	# loaded at run time: a static reference compiles sloth.gd before the Sfx autoload exists
	var SL = load("res://scripts/sloth.gd")
	var variant := ""
	for a in args:
		if a in ["fire", "ice", "storm"]:
			variant = a
	var rig: Node3D = SL.build(variant)
	root3.add_child(rig)
	var rows := [["sloth_walk", [0.0, 0.17, 0.33, 0.5, 0.67, 0.83]], ["sloth_run", [0.0, 0.17, 0.33, 0.5, 0.67, 0.83]],
		["sloth_rise", [0.0, 0.3, 0.6, 1.0]], ["sloth_look", [0.15, 0.4, 0.65, 0.9]], ["sloth_stare", [0.5]], ["sloth_roar", [0.1, 0.3, 0.6]],
		["sloth_sniff", [0.5]], ["sloth_sweep", [0.15, 0.35, 0.47, 0.6, 0.8]], ["sloth_slam", [0.2, 0.4, 0.5, 0.6, 0.75]], ["sloth_pounce", [0.2, 0.4, 0.5, 0.62, 0.8]]]
	# lay the rows out six cells wide
	var cells := []
	for r in rows:
		for v in r[1]:
			cells.append([r[0], v])
	var cols := 6
	var nrows := int(ceil(cells.size() / float(cols)))
	var sheet := Image.create(CELL * cols, CELL * nrows, false, Image.FORMAT_RGBA8)
	for i in cells.size():
		var style: String = cells[i][0]
		var v: float = cells[i][1]
		var st := {"time": 1.0 + i * 0.3, "phase": 0.0, "move": 0.0, "atk": -1.0, "style": style}
		if style in ["sloth_walk", "sloth_run"]:
			st["move"] = 1.0
			st["phase"] = v * SL.STRIDE * 1.6 / 1.7 * (1.5 if style == "sloth_run" else 1.0)
		else:
			st["atk"] = v
		SL.pose(rig, st, 1.7)
		for f in 3:
			await process_frame
		await RenderingServer.frame_post_draw
		var img := get_root().get_texture().get_image()
		var side := mini(img.get_width(), img.get_height())
		img = img.get_region(Rect2i((img.get_width() - side) / 2, (img.get_height() - side) / 2, side, side))
		img.resize(CELL, CELL)
		img.convert(Image.FORMAT_RGBA8)
		sheet.blit_rect(img, Rect2i(0, 0, CELL, CELL), Vector2i((i % cols) * CELL, (i / cols) * CELL))
	sheet.save_png(out)
	print("saved")
	quit()
