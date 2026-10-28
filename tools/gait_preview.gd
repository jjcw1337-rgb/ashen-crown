extends SceneTree
## Renders the knight's run cycle with the old gait (left) and the knight gait (right) for a GIF.
## Needs a display (xvfb). Usage: -- outdir [move] [view: front|side|34]
func _initialize():
	_run()

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var out: String = args[0]
	var mv: float = float(args[1]) if args.size() > 1 else 1.15
	var view: String = args[2] if args.size() > 2 else "34"
	var meshy: bool = args.size() > 3 and args[3] == "meshy"
	var frames: int = int(args[4]) if args.size() > 4 else 48
	var root3 := Node3D.new()
	get_root().add_child(root3)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.32, 0.36, 0.4)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.6, 0.62, 0.65)
	e.ambient_light_energy = 0.7
	e.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.environment = e
	root3.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-45, -30, 0)
	sun.light_energy = 1.3
	sun.shadow_enabled = true
	root3.add_child(sun)
	var ground := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(30, 30)
	ground.mesh = pm
	ground.material_override = Mats.mat(Color(0.25, 0.27, 0.2), 0.95)
	root3.add_child(ground)
	var rigs := []
	for i in 2:
		var r: Node3D = Knight.build_meshy() if meshy else Knight.build(Knight.default_gear())
		r.set("fixed_dt", 1.0 / 30.0)
		r.set_meta("pers", "hero")
		if i == 1:
			r.set_meta("gait", "knight")
		root3.add_child(r)
		r.position = Vector3(-0.75 + i * 1.5, 0, 0)
		var J: Dictionary = r.get_meta("j")
		(J["grip_r"] as Node3D).add_child(Models.item_model({"base": "broad_sword", "rarity": 0}))
		var s := Models.item_model({"base": "kite_shield", "rarity": 0})
		(J["mount_l"] as Node3D).add_child(s)
		rigs.append(r)
	var cam := Camera3D.new()
	cam.fov = 40
	root3.add_child(cam)
	var cp := Vector3(2.4, 1.9, -3.4)
	if view == "front":
		cp = Vector3(0, 1.6, -4.2)
	elif view == "side":
		cp = Vector3(4.6, 1.5, 0)
	var dt := 1.0 / 30.0
	var phase := 0.0
	var travel := [0.0, 0.0]
	for f in frames:
		var T := f * dt
		phase += dt * 9.5 * mv
		for i in rigs.size():
			# move the rigs so the hair and cape springs feel the speed, then keep them framed
			(rigs[i] as Node3D).position.z -= mv * 4.0 * dt
		for r in rigs:
			Anim.pose(r, {"time": 2.0 + T, "phase": phase, "move": mv})
		var cz: float = (rigs[0] as Node3D).position.z
		cam.transform = Transform3D(Basis(), cp + Vector3(0, 0, cz)).looking_at(Vector3(0, 0.95, cz))
		await process_frame
		await RenderingServer.frame_post_draw
		get_root().get_texture().get_image().save_png("%s/g%03d.png" % [out, f])
	quit()
