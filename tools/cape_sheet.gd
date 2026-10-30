extends SceneTree
## Contact sheet of the armoured knight's cloak (knight_rig.gd `_sway_cloak`) from behind and the side:
## standing in the wind, starting to run, running, stopping, and a sharp turn, sampled through the
## motion with the springs stepped at 30 fps. Needs a display.
## Usage: godot --path . -s tools/cape_sheet.gd -- out.png [side]
const CELL := 220
const COLS := 8

func _initialize():
	_run()

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var out: String = args[0]
	var side: bool = args.has("side")
	var root3 := Node3D.new()
	get_root().add_child(root3)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.3, 0.34, 0.38)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.62, 0.64, 0.68)
	e.ambient_light_energy = 0.75
	e.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.environment = e
	root3.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-38, 25, 0)
	sun.light_energy = 1.3
	root3.add_child(sun)
	var ground := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(200, 200)
	ground.mesh = pm
	ground.material_override = Mats.mat(Color(0.25, 0.27, 0.2), 0.95)
	root3.add_child(ground)
	var r: Node3D = Knight.build_meshy(true)
	r.set_meta("pers", "hero")
	r.set_meta("gait", "knight")
	r.set("fixed_dt", 1.0 / 30.0)
	root3.add_child(r)
	var cam := Camera3D.new()
	cam.fov = 34
	root3.add_child(cam)
	var dt := 1.0 / 30.0
	var phase := 0.0
	var spd := 0.0
	# the script: [seconds, speed wanted, yaw rate (rad/s), label]; frames to keep every `every` steps
	var acts := [[2.0, 0.0, 0.0, "idle"], [1.0, 4.4, 0.0, "start"], [1.2, 4.4, 0.0, "run"], [1.2, 0.0, 0.0, "stop"], [1.0, 4.4, 3.0, "turn"], [1.0, 0.0, 0.0, "settle"]]
	var shots := []
	var every := 4
	var f := 0
	for a in acts:
		var steps := int(a[0] / dt)
		for s in steps:
			spd = move_toward(spd, a[1], dt * 12.0)
			r.rotation.y += float(a[2]) * dt
			var fwd := -r.global_transform.basis.z
			r.position += fwd * spd * dt
			var mv := spd / 3.8
			phase += dt * 9.5 * mv
			Anim.pose(r, {"time": 2.0 + f * dt, "phase": phase, "move": mv})
			var c := r.position
			var back := r.global_transform.basis.z
			var rt := r.global_transform.basis.x
			var eye := c + (rt * 3.4 + Vector3(0, 1.3, 0) + back * 0.4 if side else back * 2.6 + rt * 1.3 + Vector3(0, 1.8, 0))
			cam.transform = Transform3D(Basis(), eye).looking_at(c + Vector3(0, 1.1, 0))
			await process_frame
			if f % every == 0:
				await RenderingServer.frame_post_draw
				var img := get_root().get_texture().get_image()
				var sz := mini(img.get_width(), img.get_height())
				img = img.get_region(Rect2i((img.get_width() - sz) / 2, (img.get_height() - sz) / 2, sz, sz))
				img.resize(CELL, CELL)
				img.convert(Image.FORMAT_RGBA8)
				shots.append(img)
			f += 1
	var rows := int(ceil(shots.size() / float(COLS)))
	var sheet := Image.create(CELL * COLS, CELL * rows, false, Image.FORMAT_RGBA8)
	for i in shots.size():
		sheet.blit_rect(shots[i], Rect2i(0, 0, CELL, CELL), Vector2i((i % COLS) * CELL, (i / COLS) * CELL))
	sheet.save_png(out)
	print("saved %d frames" % shots.size())
	quit()
