extends SceneTree
## The Act I oaks as the game builds them (Flora.oak_model: model + wind shader + leaf clusters), the current ones in
## the back row and candidates in the front row, with the knight for scale, under the moor's dusk light. Needs a display.
##   xvfb-run -a godot --path . --rendering-driver vulkan --resolution 1600x900 -s tools/visual_audit/oak_compare.gd -- \
##     out.png <candidate dir, res://...> [iso|low|game] [leaf clusters for the candidates, -1 = the game's]
## The candidate dir holds oak1.glb, oak2.glb, oak3.glb (imported: run `godot --headless --import` first).
func _initialize():
	_run()

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var out: String = args[0]
	var cand: String = args[1]
	var view: String = args[2] if args.size() > 2 else "iso"
	var leaf_n := int(args[3]) if args.size() > 3 else -1
	Mats.ensure_globals()
	var root3 := Node3D.new()
	get_root().add_child(root3)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.16, 0.19, 0.2)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.5, 0.56, 0.6)
	e.ambient_light_energy = 0.55
	e.tonemap_mode = Environment.TONE_MAPPER_ACES
	e.ssao_enabled = true
	env.environment = e
	root3.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-38, -35, 0)
	sun.light_color = Color(1.0, 0.86, 0.7)
	sun.light_energy = 1.3
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 60.0
	root3.add_child(sun)
	var ground := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(80, 80)
	ground.mesh = pm
	ground.material_override = Mats.mat(Color(0.17, 0.21, 0.12), 0.95)
	root3.add_child(ground)
	for k in 3:
		var old := MeshInstance3D.new()
		old.mesh = Flora.oak_model(k + 1)
		old.position = Vector3(-9.0 + k * 9.0, 0, -6.0)
		root3.add_child(old)
		var path := "%s/oak%d.glb" % [cand, k + 1]
		if ResourceLoader.exists(path):
			var nw := MeshInstance3D.new()
			nw.mesh = Flora.oak_model(k + 1, path, leaf_n)
			nw.position = Vector3(-9.0 + k * 9.0, 0, 6.0)
			root3.add_child(nw)
	var kn: Node3D = Knight.build_meshy() if Knight.meshy_ok() else Knight.build(Knight.default_gear())
	root3.add_child(kn)
	kn.position = Vector3(-4.5, 0, 9.0)
	Anim.pose(kn, {"time": 0.0})
	var cam := Camera3D.new()
	root3.add_child(cam)
	cam.fov = 40
	match view:
		"low":
			cam.transform = Transform3D(Basis(), Vector3(0, 2.6, 30)).looking_at(Vector3(0, 3.2, 0))
		"game":
			# the game's own camera: CAM_OFFSET (0, 17, 16.5) at fov 36, zoom 1, on the front row
			cam.fov = 36
			cam.transform = Transform3D(Basis(), Vector3(0, 17, 22.5)).looking_at(Vector3(0, 1.0, 6.0))
		_:
			cam.transform = Transform3D(Basis(), Vector3(0, 19, 27)).looking_at(Vector3(0, 2.0, 0))
	for f in 24:
		await process_frame
	await RenderingServer.frame_post_draw
	get_root().get_texture().get_image().save_png(out)
	print("[OAKS] saved ", out)
	quit()
