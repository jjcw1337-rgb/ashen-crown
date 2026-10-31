extends SceneTree
## Preview of the mocap knight (Knight.build_mocap) as the game drives him through Anim.pose.
## Needs a display (xvfb). Usage: -- outdir mode [side|front|34|back] [frames]
## modes: idle, run (stand, run, stop), attack (the three-swing combo standing), runattack (run into a swing),
##        block, turn (runs a circle), draw (sheathed run, stop, draw the sword, guard, holster)
func _initialize():
	_run()

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var out: String = args[0]
	var mode: String = args[1] if args.size() > 1 else "run"
	var view: String = args[2] if args.size() > 2 else "34"
	var n: int = int(args[3]) if args.size() > 3 else 120
	var root3 := Node3D.new()
	get_root().add_child(root3)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.3, 0.34, 0.38)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.7, 0.72, 0.76)
	e.ambient_light_energy = 0.8
	e.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.environment = e
	root3.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-42, -150, 0)
	sun.light_energy = 1.4
	sun.shadow_enabled = true
	root3.add_child(sun)
	var ground := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(120, 120)
	ground.mesh = pm
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color(0.25, 0.27, 0.2)
	gm.uv1_triplanar = true
	ground.material_override = gm
	root3.add_child(ground)
	# stripes so foot sliding shows
	for i in 60:
		var s := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(6, 0.005, 0.08)
		s.mesh = bm
		s.position = Vector3(0, 0.002, 4 - i * 1.0)
		var sm := StandardMaterial3D.new()
		sm.albedo_color = Color(0.4, 0.42, 0.33)
		s.material_override = sm
		root3.add_child(s)
	var archer := args.has("archer")
	# archer.gd uses the Sfx autoload: load it at run time (a static reference compiles it before Sfx exists)
	var AR: GDScript = load("res://scripts/archer.gd") if archer else null
	var r: Node3D = AR.call("build_body") if archer else Knight.build_mocap()
	r.set_meta("pers", "hero")
	r.set_meta("gait", "knight")
	r.set("fixed_dt", 1.0 / 30.0)
	root3.add_child(r)
	var J: Dictionary = r.get_meta("j")
	var sword := Models.item_model({"base": "long_bow" if args.has("longbow") else "short_bow", "rarity": 0}) if archer else Models.item_model({"base": "short_sword", "rarity": 0})
	if archer:
		var kind: String = Data.BASES["long_bow" if args.has("longbow") else "short_bow"]["kind"]
		var g: Node3D = J["grip_bow"]
		var hold: Dictionary = AR.get("BOW_HOLD")
		kind = AR.call("bow_key", kind)
		g.position = hold[kind][0]
		g.rotation_degrees = hold[kind][1]
		(J["grip_bow_at"] as Node3D).position = hold[kind][2]
		(J["grip_bow_at"] as Node3D).add_child(sword)
	else:
		(J["grip_r"] as Node3D).add_child(sword)
	if not archer:
		var sh := Models.item_model({"base": "kite_shield", "rarity": 0})
		(J["mount_l"] as Node3D).add_child(sh)
		sh.position = Vector3(-0.03, 0, 0)
	var cam := Camera3D.new()
	cam.fov = 34
	root3.add_child(cam)
	var dt := 1.0 / 30.0
	var phase := 0.0
	var spd := 0.0
	var yaw := 0.0
	for f in n:
		var T := f * dt
		var want := 0.0
		var st := {"time": 2.0 + T}
		match mode:
			"run":
				want = 4.8 if T > 0.8 and T < 3.4 else 0.0
			"turn":
				want = 4.8
				yaw += dt * 1.3
			"runattack":
				want = 4.8 if T < 1.6 else 0.0
				if T > 1.6 and T < 2.3:
					st["atk"] = (T - 1.6) / 0.7
					st["style"] = "swipe1"
			"attack":
				var k := fmod(T, 2.1)
				var idx := int(T / 2.1) % 3
				if archer:
					if k < 0.8:
						st["atk"] = k / 0.8
						st["style"] = "bow"
				elif k < 0.65:
					st["atk"] = k / 0.65
					st["style"] = ["swipe1", "swipe2", "swipe3"][idx]
			"shootwalk":
				# idle aimed, then walking slowed while he looses arrows (as the archer does in game), then stop
				want = 4.8 * 0.36 if T > 0.6 and T < 5.4 else 0.0
				var k2 := fmod(T, 0.96)
				if T > 0.6 and T < 5.6 and k2 < 0.96:
					st["atk"] = k2 / 0.96
					st["style"] = "bow"
				st["draw"] = 1.0
			"block":
				st["block"] = 1.0 if fmod(T, 2.0) < 1.2 else 0.0
			"tour":
				# a square run (turns each way), stop, a swing, a block, a hit, death
				if T < 6.0:
					want = 4.8
					var seg := int(T / 1.5)
					yaw = lerp_angle(yaw, [0.0, PI * 0.5, PI, -PI * 0.5][seg % 4], clampf(dt * 8.0, 0.0, 1.0))
				elif T > 6.6 and T < 7.3:
					st["atk"] = (T - 6.6) / 0.7
					st["style"] = "swipe2"
				elif T > 7.6 and T < 8.4:
					st["block"] = 1.0
				elif T > 8.6 and T < 9.0:
					st["hit"] = 1.0 - (T - 8.6) / 0.4
				elif T >= 9.2:
					st["dead"] = T - 9.2
			"draw":
				# run sheathed, stop, draw (0.85 s), stand in guard, holster (0.9 s)
				want = 4.8 if T > 0.5 and T < 2.2 else 0.0
				var dr := 0.0
				if T > 2.8 and T < 3.65:
					dr = (T - 2.8) / 0.85
				elif T >= 3.65 and T < 4.8:
					dr = 1.0
				elif T >= 4.8 and T < 5.7:
					dr = 1.0 - (T - 4.8) / 0.9
				st["draw"] = dr
				st["draw_motion"] = "knight"
				st["draw_dir"] = 1.0 if (T > 2.8 and T < 3.65) else (-1.0 if (T >= 4.8 and T < 5.7) else 0.0)
				var in_hand := dr >= 0.38
				sword.visible = in_hand
				for mi in r.find_children("*", "MeshInstance3D", true, false):
					var m := (mi as MeshInstance3D).mesh
					for si in (m.get_surface_count() if m != null else 0):
						var mat := m.surface_get_material(si)
						if mat != null and mat.resource_name == "Hilt":
							var hide := StandardMaterial3D.new()
							hide.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
							hide.albedo_color = Color(0, 0, 0, 0)
							(mi as MeshInstance3D).set_surface_override_material(si, hide if in_hand else null)
		spd = move_toward(spd, want, dt * 18.0)
		r.rotation.y = yaw
		r.position += -r.transform.basis.z * spd * dt
		var mv := spd / 4.8
		phase += dt * spd * 2.9 / maxf(mv, 0.6)
		st["phase"] = phase
		st["move"] = mv
		st["speed"] = spd
		Anim.pose(r, st)
		if archer:
			AR.call("pose_bow_on", r, sword, Data.BASES["long_bow" if args.has("longbow") else "short_bow"]["kind"], st)
			if f % 2 == 0 and f < 26 and sword.has_meta("strands"):
				var fing: Vector3 = (J["at_hand_r"] as Node3D).global_transform * Vector3(0, -0.06, 0)
				var sp: Dictionary = (AR.get("BOW_SPEC") as Dictionary)[AR.call("bow_key", Data.BASES["long_bow" if args.has("longbow") else "short_bow"]["kind"])]
				var nk: Vector3 = sword.global_transform * ((sp["rest"] as Vector3) + (sword.get_meta("draw_off", Vector3.ZERO) as Vector3))
				var lh: Vector3 = (J["at_hand_l"] as Node3D).global_position
				var gp: Vector3 = sword.global_transform * (sp["grip"] as Vector3)
				print("[H] f%d atk %.2f  nock-fingers %.3f m  grip-lefthand %.3f m" % [f, float(st.get("atk", -1.0)), nk.distance_to(fing), gp.distance_to(lh)])
		var c := r.position
		var off: Vector3 = {"side": Vector3(4.4, 1.2, 0.0), "front": Vector3(0.0, 1.4, -4.4), "back": Vector3(0.0, 1.6, 4.4), "34": Vector3(2.8, 2.0, -3.0), "game": Vector3(0, 17.0, 16.5) * 0.45}.get(view, Vector3(2.8, 2.0, -3.0))
		if view == "game":
			off = Vector3(0, 17.0, 16.5) * 0.45
		if mode == "turn":
			c = Vector3.ZERO
			off = Vector3(0, 9, 7)
		var look := Vector3(0, 0.95, 0)
		var closes := {"close": Vector3(2.2, 0.1, -2.0), "closeback": Vector3(-1.4, 0.3, 2.6), "closetop": Vector3(0.3, 1.6, -0.6)}
		if closes.has(view):
			# the hands and the string, close up (relative to the way he faces)
			off = r.transform.basis * (closes[view] as Vector3)
			look = Vector3(0, 1.25, 0)
		cam.transform = Transform3D(Basis(), c + off + (look - Vector3(0, 0.95, 0) if closes.has(view) else Vector3.ZERO)).looking_at(c + look)
		await process_frame
		await RenderingServer.frame_post_draw
		get_root().get_texture().get_image().save_png("%s/c%03d.png" % [out, f])
	quit()
