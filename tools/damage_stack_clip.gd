extends SceneTree
## Frames of the stacking damage number (DamageStack) over the knight: -- outdir
func _initialize():
	_run()

func _run() -> void:
	var out: String = OS.get_cmdline_user_args()[0]
	var root3 := Node3D.new()
	get_root().add_child(root3)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.3, 0.34, 0.38)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.8, 0.8, 0.85)
	env.environment = e
	root3.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-42, -150, 0)
	root3.add_child(sun)
	var holder := Node3D.new()
	root3.add_child(holder)
	var r: Node3D = Knight.build_meshy(true)
	holder.add_child(r)
	var ds := DamageStack.new()
	holder.add_child(ds)
	var cam := Camera3D.new()
	cam.fov = 40
	root3.add_child(cam)
	cam.transform = Transform3D(Basis(), Vector3(0, 6.5, 6.5)).looking_at(Vector3(0, 1.4, 0))
	var hits := {3: 12.0, 12: 9.0, 18: 15.0, 27: 11.0, 33: 22.0, 95: 8.0}
	for f in 120:
		if hits.has(f):
			ds.add(hits[f])
		Anim.pose(r, {"time": 2.0 + f / 30.0, "phase": 0.0, "move": 0.0, "hit": 1.0 if hits.has(f) else 0.0})
		await process_frame
		await RenderingServer.frame_post_draw
		get_root().get_texture().get_image().save_png("%s/c%03d.png" % [out, f])
	quit()
