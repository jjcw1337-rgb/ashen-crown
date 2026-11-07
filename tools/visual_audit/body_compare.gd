extends SceneTree
## Two copies of the armoured knight's mocap body side by side (left: the game's knight_mocap.glb, right: a candidate),
## idling as the game drives him, under the moor's dusk light with the hero's own light and the dusk rim light (Grade.RIMS)
## each, for material comparisons. Needs a display; the candidate must be imported (`godot --headless --import`).
##   xvfb-run -a godot --path . --rendering-driver vulkan --resolution 1600x900 -s tools/visual_audit/body_compare.gd -- \
##     out.png res://path/candidate.glb [close|game|back]
func _initialize():
	_run()

func _body(root3: Node3D, glb: String, x: float) -> Node3D:
	var r: Node3D = Knight.build_mocap(glb)
	r.set_meta("pers", "hero")
	r.set_meta("gait", "knight")
	r.set("fixed_dt", 1.0 / 30.0)
	root3.add_child(r)
	r.position = Vector3(x, 0, 0)
	var J: Dictionary = r.get_meta("j")
	(J["grip_r"] as Node3D).add_child(Models.item_model({"base": "short_sword", "rarity": 0}))
	var sh := Models.item_model({"base": "kite_shield", "rarity": 0})
	(J["mount_l"] as Node3D).add_child(sh)
	sh.position = Vector3(-0.03, 0, 0)
	# the hero's own light (Hero: warm, over his head) and the zone's rim (Game._update_grade: behind him)
	var l := OmniLight3D.new()
	l.light_color = Color(1.0, 0.85, 0.65)
	l.light_energy = 0.9
	l.omni_range = 10.0
	l.omni_attenuation = 1.6
	l.position = Vector3(x, 3.2, 0.5)
	root3.add_child(l)
	return r

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var out: String = args[0]
	var cand: String = args[1]
	var view: String = args[2] if args.size() > 2 else "close"
	Mats.ensure_globals()
	var root3 := Node3D.new()
	get_root().add_child(root3)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.12, 0.14, 0.15)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.42, 0.47, 0.55)
	e.ambient_light_energy = 0.5
	e.tonemap_mode = Environment.TONE_MAPPER_ACES
	e.glow_enabled = true
	env.environment = e
	root3.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-34, -38, 0)
	sun.light_color = Color(1.0, 0.78, 0.56)
	sun.light_energy = 1.1
	sun.shadow_enabled = true
	root3.add_child(sun)
	var ground := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(30, 30)
	ground.mesh = pm
	ground.material_override = Mats.mat(Color(0.2, 0.21, 0.16), 0.95)
	root3.add_child(ground)
	var a := _body(root3, KnightBody.MOCAP_GLB, -0.95)
	var b := _body(root3, cand, 0.95)
	var cam := Camera3D.new()
	root3.add_child(cam)
	match view:
		"game":
			cam.fov = 36
			cam.transform = Transform3D(Basis(), Vector3(0, 17, 16.5) * 0.62 + Vector3(0, 1.0, 0)).looking_at(Vector3(0, 1.0, 0))
		"back":
			cam.fov = 34
			cam.transform = Transform3D(Basis(), Vector3(0.6, 1.9, -4.4)).looking_at(Vector3(0, 1.05, 0))
		_:
			cam.fov = 34
			cam.transform = Transform3D(Basis(), Vector3(0.8, 1.7, 4.6)).looking_at(Vector3(0, 1.0, 0))
	# the rim behind each body, away from the camera (as Game._update_grade places it)
	var away := -cam.global_transform.basis.z
	away.y = 0.0
	away = away.normalized()
	var rd: Dictionary = Grade.RIMS["dusk"]
	for x in [-0.95, 0.95]:
		var rim := OmniLight3D.new()
		rim.light_color = rd["color"]
		rim.light_energy = rd["energy"]
		rim.omni_range = rd["range"]
		rim.omni_attenuation = 1.2
		rim.light_specular = 0.6
		rim.position = Vector3(x, 2.3, 0) + away * 1.6
		root3.add_child(rim)
	for f in 40:
		var st := {"time": 2.0 + f / 30.0}
		Anim.pose(a, st)
		Anim.pose(b, st)
		await process_frame
	await RenderingServer.frame_post_draw
	get_root().get_texture().get_image().save_png(out)
	print("[BODY] saved ", out)
	quit()
