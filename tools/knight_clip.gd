extends SceneTree
## Preview clip of the knight (Meshy body): idle in the wind, run with the knight gait, stop.
## Needs a display (xvfb). Usage: -- outdir [close]
func _initialize():
	_run()

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var out: String = args[0]
	var close: bool = args.size() > 1 and args[1] == "close"
	var side: bool = args.size() > 1 and args[1] == "side"
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
	sun.rotation_degrees = Vector3(-42, -150, 0)
	sun.light_energy = 1.3
	sun.shadow_enabled = true
	root3.add_child(sun)
	var ground := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(80, 80)
	ground.mesh = pm
	ground.material_override = Mats.mat(Color(0.25, 0.27, 0.2), 0.95)
	root3.add_child(ground)
	var r: Node3D = Knight.build_meshy()
	r.set_meta("pers", "hero")
	r.set_meta("gait", "knight")
	r.set("fixed_dt", 1.0 / 30.0)
	root3.add_child(r)
	var J: Dictionary = r.get_meta("j")
	(J["grip_r"] as Node3D).add_child(Models.item_model({"base": "short_sword", "rarity": 0}))
	var cam := Camera3D.new()
	cam.fov = 30 if close else 38
	root3.add_child(cam)
	var dt := 1.0 / 30.0
	var phase := 0.0
	var spd := 0.0
	var n := 90 if close else 150
	for f in n:
		var T := f * dt
		var want := 0.0
		if close or side or (T > 1.2 and T < 3.8):
			want = 4.4
		spd = move_toward(spd, want, dt * 12.0)
		var mv := spd / 3.8
		r.position.z -= spd * dt
		phase += dt * 9.5 * mv
		Anim.pose(r, {"time": 2.0 + T, "phase": phase, "move": mv})
		var c := r.position
		var off := Vector3(1.0, 1.75, -1.3) if close else (Vector3(4.2, 1.3, -0.3) if side else Vector3(2.6, 2.1, -3.2))
		cam.transform = Transform3D(Basis(), c + off).looking_at(c + Vector3(0, 1.45 if close else 1.05, 0))
		await process_frame
		await RenderingServer.frame_post_draw
		get_root().get_texture().get_image().save_png("%s/c%03d.png" % [out, f])
	quit()
