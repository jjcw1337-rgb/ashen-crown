extends SceneTree
## Clip of the crusader drawing his sword from the hip scabbard, holding guard, and sheathing it
## (the knight's WeaponCarry motion in Anim). Needs a display: -- outdir [side]
func _initialize():
	_run()

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var out: String = args[0]
	var root3 := Node3D.new()
	get_root().add_child(root3)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.32, 0.35, 0.4)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.8, 0.8, 0.85)
	e.ambient_light_energy = 1.1
	e.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.environment = e
	root3.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-40, -35, 0)
	sun.light_energy = 1.6
	root3.add_child(sun)
	var ground := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(20, 20)
	ground.mesh = pm
	ground.material_override = Mats.mat(Color(0.25, 0.27, 0.2), 0.95)
	root3.add_child(ground)
	var r: Node3D = Knight.build_meshy(true)
	r.set_meta("pers", "hero")
	r.set_meta("gait", "knight")
	root3.add_child(r)
	var J: Dictionary = r.get_meta("j")
	var sword := Models.item_model({"base": "long_sword", "rarity": 0})
	(J["grip_r"] as Node3D).add_child(sword)
	var hide := StandardMaterial3D.new()
	hide.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	hide.albedo_color = Color(0, 0, 0, 0)
	var set_hilt := func(show: bool):
		for mi in r.find_children("*", "MeshInstance3D", true, false):
			var m = (mi as MeshInstance3D).mesh
			if m:
				for si in m.get_surface_count():
					var mat = m.surface_get_material(si)
					if mat and mat.resource_name == "Hilt":
						(mi as MeshInstance3D).set_surface_override_material(si, null if show else hide)
	var cam := Camera3D.new()
	cam.fov = 32
	root3.add_child(cam)
	var side := args.has("side")
	cam.transform = Transform3D(Basis(), Vector3(2.4, 1.6, -2.6) if not side else Vector3(3.4, 1.3, -0.2)).looking_at(Vector3(0, 1.05, 0))
	var dt := 1.0 / 30.0
	var n := 96
	for f in n:
		var T := f * dt
		# 0-0.3 s relaxed, draw 0.85 s, hold guard to 1.9 s, sheathe 0.9 s, relaxed
		var d := 0.0
		if T < 0.3:
			d = 0.0
		elif T < 1.15:
			d = (T - 0.3) / 0.85
		elif T < 1.9:
			d = 1.0
		elif T < 2.8:
			d = 1.0 - (T - 1.9) / 0.9
		var in_hand := d >= 0.38
		sword.visible = in_hand
		set_hilt.call(not in_hand)
		Anim.pose(r, {"time": 2.0 + T, "phase": 0.0, "move": 0.0, "draw": clampf(d, 0.0, 1.0), "draw_motion": "knight"})
		await process_frame
		await RenderingServer.frame_post_draw
		get_root().get_texture().get_image().save_png("%s/d%03d.png" % [out, f])
	quit()
