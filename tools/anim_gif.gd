extends SceneTree
## Renders an animation strip: hero walking a curve and fighting, monsters idling/shambling.
## Usage: -- outdir frames

var root3: Node3D
var cast: Array = []

func _initialize():
	var args := OS.get_cmdline_user_args()
	var outdir: String = args[0]
	var frames: int = int(args[1]) if args.size() > 1 else 72
	root3 = Node3D.new()
	get_root().add_child(root3)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.09, 0.1, 0.09)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.5, 0.55, 0.55)
	e.ambient_light_energy = 0.7
	e.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.environment = e
	root3.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, -30, 0)
	sun.light_energy = 1.4
	sun.shadow_enabled = true
	root3.add_child(sun)
	var ground := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(30, 30)
	ground.mesh = pm
	ground.material_override = Mats.mat(Color(0.2, 0.23, 0.16), 0.95)
	root3.add_child(ground)
	var cam := Camera3D.new()
	root3.add_child(cam)
	cam.transform = Transform3D(Basis(), Vector3(0, 4.2, 7.5)).looking_at(Vector3(0, 0.9, 0))
	cam.fov = 48
	# hero knight (plate) walking a curve
	var g := Knight.default_gear()
	g["armor"] = "plate"
	g["coif"] = true
	var hero := Knight.build(g)
	hero.set_meta("pers", "hero")
	root3.add_child(hero)
	var J: Dictionary = hero.get_meta("j")
	(J["grip_r"] as Node3D).add_child(Models.item_model({"base": "broad_sword", "rarity": 2}))
	var sh := Models.item_model({"base": "kite_shield", "rarity": 1})
	(J["mount_l"] as Node3D).add_child(sh)
	cast.append({"rig": hero, "kind": "hero"})
	var specs := [["zombie", Vector3(-2.6, 0, -0.5)], ["fallen", Vector3(2.4, 0, -0.8)], ["skel_archer", Vector3(-1.2, 0, -2.2)], ["spider", Vector3(1.4, 0, -2.6)], ["skel_archer", Vector3(3.6, 0, -3.2)]]
	for sp in specs:
		var d: Dictionary = Data.ENEMIES[sp[0]]
		var r: Node3D = Models.crawler(d["look"]) if d["rig"] == "crawler" else Models.humanoid(d["look"])
		var pers := "warrior"
		match sp[0]:
			"zombie": pers = "zombie"
			"skel_archer": pers = "skeleton"
			"fallen": pers = "fallen"
		r.set_meta("pers", pers)
		root3.add_child(r)
		r.position = sp[1]
		r.rotation.y = PI + randf_range(-0.4, 0.4)
		cast.append({"rig": r, "kind": sp[0], "home": sp[1]})
	await process_frame
	var fps := 15.0
	var phase := 0.0
	var zph := 0.0
	for f in frames:
		var t := f / fps
		# hero: walk a figure along an arc, then swing twice while stepping
		var u := t * 0.55
		var pos := Vector3(sin(u) * 1.6, 0, cos(u * 0.8) * 0.9 + 0.6)
		var nxt := Vector3(sin(u + 0.05) * 1.6, 0, cos((u + 0.05) * 0.8) * 0.9 + 0.6)
		var dir := nxt - pos
		hero.position = pos
		hero.rotation.y = atan2(-dir.x, -dir.z)
		var spd := dir.length() / 0.05 * 0.55
		phase += spd * 2.9 / fps
		var atk := -1.0
		var style := "over"
		var cyc := fmod(t, 3.2)
		if cyc > 1.8 and cyc < 2.4:
			atk = (cyc - 1.8) / 0.6
		elif cyc > 2.45 and cyc < 3.05:
			atk = (cyc - 2.45) / 0.6
			style = "back"
		Anim.pose(hero, {"time": t, "phase": phase, "move": clampf(spd / 4.8, 0.0, 1.0) * (0.75 if atk >= 0.0 else 1.0), "atk": atk, "style": style})
		for c in cast:
			if c["kind"] == "hero":
				continue
			var r: Node3D = c["rig"]
			var st := {"time": t + r.get_instance_id() % 7, "phase": 0.0, "move": 0.0}
			if c["kind"] == "zombie":
				zph += 1.9 * 2.9 / fps
				r.position = c["home"] + Vector3(sin(t * 0.3) * 0.6, 0, 0)
				r.rotation.y = PI * 0.5 if cos(t * 0.3) > 0.0 else -PI * 0.5
				st = {"time": t, "phase": zph, "move": 0.8, "zombie": true}
			if c["kind"] == "spider":
				r.rotation.y = PI + sin(t * 0.7) * 0.8
			if c["kind"] == "fallen" and fmod(t, 2.5) > 1.6:
				st["atk"] = (fmod(t, 2.5) - 1.6) / 0.85
				st["style"] = "over"
			Anim.pose(r, st)
		await process_frame
		await RenderingServer.frame_post_draw
		var img := get_root().get_texture().get_image()
		img.resize(800, 450, Image.INTERPOLATE_LANCZOS)
		img.save_png("%s/f%03d.png" % [outdir, f])
	print("frames done")
	quit()
