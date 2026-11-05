extends SceneTree
## Frames of a raven (Raven) in a little studio: sitting and doing each of its acts, taking off, flying, landing.
## Needs a display; run with --fixed-fps 30.
##   godot --path . --fixed-fps 30 -s tools/raven_sheet.gd -- <outdir> [side|front|34]

func _initialize():
	_run()

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var out: String = args[0] if args.size() > 0 else "/tmp/raven"
	var view: String = args[1] if args.size() > 1 else "34"
	DirAccess.make_dir_recursive_absolute(out)
	var root := Node3D.new()
	get_root().add_child(root)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.55, 0.6, 0.65)
	env.environment.ambient_light_color = Color(0.7, 0.7, 0.75)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	root.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, 30, 0)
	root.add_child(sun)
	var fl := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(40, 40)
	fl.mesh = pm
	root.add_child(fl)
	var rv := Raven.make()
	root.add_child(rv)
	rv.perch_at(Vector3.ZERO, 0.0, true)
	var cam := Camera3D.new()
	cam.fov = 30
	root.add_child(cam)
	var dirs := {"side": Vector3(2.2, 0.5, 0), "front": Vector3(0, 0.5, 2.2), "34": Vector3(1.6, 1.0, 1.6)}
	var f := 0
	# each act, 1.2 s apart
	for a in ["look", "peck", "preen", "shake", "stretch", "caw", "hop", "settle"]:
		rv.act = a
		rv.act_t = 0.0
		rv.act_dur = {"look": 1.4, "preen": 2.6, "shake": 0.7, "stretch": 1.8, "caw": 1.6, "hop": 0.42, "settle": 1.0, "peck": 1.1}[a]
		rv._next_act = 99.0
		for i in 12:
			rv.tick(1.0 / 30.0)
			if a == "hop" and i == 0:
				pass
			if i == int(rv.act_dur * 15.0) or i == 6:
				cam.global_transform = Transform3D(Basis(), rv.global_position + dirs[view]).looking_at(rv.global_position + Vector3(0, 0.22, 0), Vector3.UP)
				await process_frame
				await RenderingServer.frame_post_draw
				get_root().get_texture().get_image().save_png("%s/rv_%03d_%s.png" % [out, f, a])
				f += 1
	# off and away, and in to land
	rv.fly_to(Vector3(0, 0, 9), true)
	var steps := int((Raven.TAKEOFF_T + rv.fdur) * 30.0) + 20
	for i in steps:
		rv.tick(1.0 / 30.0)
		if i % 6 == 0:
			var c: Vector3 = rv.global_position
			cam.global_transform = Transform3D(Basis(), c + dirs[view] * 1.3).looking_at(c + Vector3(0, 0.15, 0), Vector3.UP)
			await process_frame
			await RenderingServer.frame_post_draw
			get_root().get_texture().get_image().save_png("%s/rv_%03d_%s.png" % [out, f, rv.state])
			f += 1
	print("[R] frames ", f)
	quit()
