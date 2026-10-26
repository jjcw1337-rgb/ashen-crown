extends SceneTree
## Close-up renders of the skinned warrior. Usage: -- out.png lineup|action

func _initialize():
	var args := OS.get_cmdline_user_args()
	var out: String = args[0]
	var mode: String = args[1] if args.size() > 1 else "lineup"
	var root3 := Node3D.new()
	get_root().add_child(root3)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	var sky := Sky.new()
	var sm := ProceduralSkyMaterial.new()
	sm.sky_top_color = Color(0.26, 0.3, 0.31)
	sm.sky_horizon_color = Color(0.44, 0.47, 0.44)
	sm.ground_bottom_color = Color(0.16, 0.18, 0.15)
	sm.ground_horizon_color = Color(0.44, 0.47, 0.44)
	sky.sky_material = sm
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.08, 0.09, 0.085)
	e.sky = sky
	e.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	e.ambient_light_energy = 0.6
	e.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	e.tonemap_mode = Environment.TONE_MAPPER_ACES
	e.tonemap_exposure = 1.1
	env.environment = e
	root3.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-40, -35, 0)
	sun.light_energy = 1.3
	sun.shadow_enabled = true
	root3.add_child(sun)
	var warm := OmniLight3D.new()
	warm.light_color = Color(1.0, 0.6, 0.3)
	warm.light_energy = 2.5
	warm.omni_range = 9.0
	warm.position = Vector3(-3, 2.2, 3)
	root3.add_child(warm)
	var ground := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(40, 40)
	ground.mesh = pm
	ground.material_override = Mats.mat(Color(0.2, 0.22, 0.16), 0.95)
	root3.add_child(ground)
	var cam := Camera3D.new()
	root3.add_child(cam)
	var kits := [
		["quilted", "", "", null, "short_sword", "buckler", 0],
		["leather", "gloves", "boots", "cap", "hand_axe", "buckler", 1],
		["chain", "gloves", "boots", null, "broad_sword", "kite_shield", 1],
		["plate", "gauntlets", "greaves", "great_helm", "war_hammer", "tower_shield", 0],
		["ornate", "gauntlets", "greaves", null, "runeblade", "aegis", 2],
	]
	var rigs := []
	var i := 0
	for k in kits:
		var g := Knight.default_gear()
		g["armor"] = k[0]
		g["gloves"] = k[1]
		g["boots"] = k[2]
		g["coif"] = k[0] in ["chain", "plate", "ornate"] and k[3] == null and k[0] != "ornate"
		if k[0] == "ornate":
			g["steel"] = Color(0.75, 0.74, 0.72)
			g["trim"] = Color(0.95, 0.75, 0.35)
			g["cloth"] = Color(0.12, 0.18, 0.45)
			g["cape"] = Color(0.08, 0.12, 0.32)
		if k[0] == "leather":
			g["cape"] = null
		var r := Knight.build(g)
		root3.add_child(r)
		var J: Dictionary = r.get_meta("j")
		var w := Models.item_model({"base": k[4], "rarity": k[6]})
		(J["grip_r"] as Node3D).add_child(w)
		var s := Models.item_model({"base": k[5], "rarity": k[6]})
		(J["mount_l"] as Node3D).add_child(s)
		s.position = Vector3(-0.03, 0, 0)
		if k[3] != null:
			var hm := Models.item_model({"base": k[3], "rarity": 0})
			(J["head"] as Node3D).add_child(hm)
			hm.position = Vector3(0, 0.092, 0.006)
		rigs.append(r)
		i += 1
	if mode == "lineup":
		for j in rigs.size():
			rigs[j].position = Vector3((j - 2) * 1.25, 0, 0)
			rigs[j].rotation_degrees.y = 180 + (j - 2) * -8
		cam.transform = Transform3D(Basis(), Vector3(0, 1.45, 5.6)).looking_at(Vector3(0, 1.0, 0))
		cam.fov = 44
	else:
		var poses := [
			{"atk": 0.33, "style": "over"}, {"atk": 0.5, "style": "back"}, {"block": 1.0},
			{"move": 1.0, "phase": 1.2}, {"atk": 0.45, "style": "side"},
		]
		for j in rigs.size():
			rigs[j].position = Vector3((j - 2) * 1.5, 0, 0)
			rigs[j].rotation_degrees.y = 150 + j * 8
			var st: Dictionary = poses[j].duplicate()
			st["time"] = 1.0
			Anim.pose(rigs[j], st)
		cam.transform = Transform3D(Basis(), Vector3(0, 1.8, 6.2)).looking_at(Vector3(0, 1.0, 0))
		cam.fov = 46
	for f in 10:
		for j in rigs.size():
			if mode == "lineup":
				Anim.pose(rigs[j], {"time": 0.0})
		await process_frame
	await RenderingServer.frame_post_draw
	get_root().get_texture().get_image().save_png(out)
	print("saved ", out)
	quit()
