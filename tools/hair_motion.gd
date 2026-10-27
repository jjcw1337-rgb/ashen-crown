extends SceneTree
## Renders frames of the knight running, stopping and turning so the long hair's sway and the
## wind can be checked. Needs a display (xvfb). Usage: -- outdir
var out := ""
func _initialize():
	out = OS.get_cmdline_user_args()[0]
	_run()

func _run() -> void:
	var root3 := Node3D.new()
	get_root().add_child(root3)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.36, 0.42, 0.46)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.55, 0.58, 0.6)
	e.ambient_light_energy = 0.7
	e.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.environment = e
	root3.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-42, -30, 0)
	sun.light_energy = 1.4
	sun.shadow_enabled = true
	root3.add_child(sun)
	var ground := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(60, 60)
	ground.mesh = pm
	ground.material_override = Mats.mat(Color(0.24, 0.26, 0.18), 0.95)
	root3.add_child(ground)
	var rig := Knight.build(Knight.default_gear())
	root3.add_child(rig)
	var cam := Camera3D.new()
	cam.fov = 40
	root3.add_child(cam)
	var fixed := 1.0 / 30.0
	rig.set("fixed_dt", fixed)
	var phase := 0.0
	var frame := 0
	var yaw := 0.0
	var spd := 0.0
	while true:
		await process_frame
		var dt := fixed
		var T := frame * fixed
		if T > 7.0:
			break
		# 0-1 s stand in the wind, 1-3.2 s run, then stop, 4.2-5 s turn round, stand
		var want := 4.2 if (T > 1.0 and T < 3.2) else 0.0
		spd = move_toward(spd, want, dt * 14.0)
		if T > 4.2 and T < 5.0:
			yaw += dt * PI / 0.8
		rig.rotation.y = yaw
		var fwd := -rig.global_transform.basis.z
		rig.position += fwd * spd * dt
		phase += dt * spd * 2.2
		Anim.pose(rig, {"time": T, "phase": phase, "move": spd / 3.6, "dt": dt})
		var c := rig.position + Vector3(1.6, 1.75, 1.5)
		cam.transform = Transform3D(Basis(), c).looking_at(rig.position + Vector3(0, 1.45, 0))
		if frame % 2 == 0:
			await RenderingServer.frame_post_draw
			get_root().get_texture().get_image().save_png("%s/f%04d.png" % [out, frame / 2])
		frame += 1
	print("frames ", frame / 2)
	quit()
