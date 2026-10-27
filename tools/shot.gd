extends SceneTree
## Renders a model showcase to a PNG. Usage: godot -s tools/shot.gd -- out.png mode

func _initialize():
	var args := OS.get_cmdline_user_args()
	var out := args[0] if args.size() > 0 else "res://shot.png"
	var mode := args[1] if args.size() > 1 else "chars"
	var root3 := Node3D.new()
	get_root().add_child(root3)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.16, 0.18, 0.17)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.5, 0.55, 0.55)
	e.ambient_light_energy = 0.6
	e.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.environment = e
	root3.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, -35, 0)
	sun.light_energy = 1.6
	sun.shadow_enabled = true
	root3.add_child(sun)
	var ground := MeshInstance3D.new()
	var pm := PlaneMesh.new(); pm.size = Vector2(40, 40)
	ground.mesh = pm
	ground.material_override = Mats.mat(Color(0.25, 0.28, 0.2), 0.95)
	root3.add_child(ground)
	var cam := Camera3D.new()
	root3.add_child(cam)
	if mode == "chars":
		var looks := [
			{"skin": Color(0.78,0.6,0.48), "cloth": Color(0.45,0.08,0.06), "armor": Color(0.62,0.63,0.66), "head":"human", "hair": Color(0.2,0.12,0.06), "beard": Color(0.2,0.12,0.06), "cape": Color(0.4,0.05,0.04)},
		]
		var x := -6.0
		var hero := Models.humanoid(looks[0])
		root3.add_child(hero); hero.position = Vector3(x+4,0,2); hero.rotation_degrees.y = 160
		var J: Dictionary = hero.get_meta("j")
		var sw := Models.item_model({"base":"broad_sword","rarity":2})
		(J["grip_r"] as Node3D).add_child(sw)
		var shd := Models.item_model({"base":"kite_shield","rarity":1})
		(J["mount_l"] as Node3D).add_child(shd)
		var hl := Models.item_model({"base":"great_helm","rarity":0})
		(J["head"] as Node3D).add_child(hl); hl.position = Vector3(0,0.07*1.0,0)
		x += 2.2
		for k in ["fallen","zombie","skel_archer","mummy","scarab","spider","lizardman","imp","hell_knight","doom_caster"]:
			var d: Dictionary = Data.ENEMIES[k]
			var r: Node3D = Models.crawler(d["look"]) if d["rig"] == "crawler" else Models.humanoid(d["look"])
			root3.add_child(r)
			r.position = Vector3(x, 0, 0); r.rotation_degrees.y = 180
			x += 2.2
		cam.transform = Transform3D(Basis(), Vector3(6, 3.5, 9)).looking_at(Vector3(6, 1.0, 0))
		cam.fov = 60
	else:
		var keys := Data.BASES.keys()
		var i := 0
		for k in keys:
			var rar := i % 4
			var it := {"base": k, "rarity": rar if rar < 3 else 2, "count": 120}
			if k == "falchion": it = {"base": k, "rarity": 3, "unique": "emberfang"}
			if k == "runeblade": it = {"base": k, "rarity": 3, "unique": "dawnbreaker"}
			if k == "kite_shield": it = {"base": k, "rarity": 3, "unique": "wardens_wall"}
			var m := Models.item_model(it)
			var holder := Node3D.new()
			root3.add_child(holder)
			holder.add_child(m)
			var col := i % 9
			var row := i / 9
			holder.position = Vector3(col * 1.0 - 4.0, 0.7, row * 1.0 - 2.0)
			var slot: String = Data.BASES[k]["slot"]
			if slot == "weapon": m.rotation_degrees = Vector3(-60, 0, 0); holder.position.y = 0.4
			elif slot == "shield": m.rotation_degrees = Vector3(0, 0, 0)
			else: m.scale = Vector3(2.5,2.5,2.5) if slot in ["ring","amulet","potion","gold","gloves","boots","belt"] else Vector3(1.6,1.6,1.6)
			i += 1
		cam.transform = Transform3D(Basis(), Vector3(0, 4.0, 5.0)).looking_at(Vector3(0, 0.3, 0.6))
		cam.fov = 55
	for f in 8:
		await process_frame
	await RenderingServer.frame_post_draw
	var img := get_root().get_texture().get_image()
	img.save_png(out)
	print("saved ", out)
	quit()
