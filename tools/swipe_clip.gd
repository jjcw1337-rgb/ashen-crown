extends SceneTree
## Preview clip of the right-click combo (swipe1 -> swipe2 -> swipe3) on the Meshy knight, chained the
## way Hero does it (each swipe cut at 68% into the next), with the step-in and a sword trail.
## Needs a display (xvfb). Usage: -- outdir [bare|armored] [view: game|side|front] [judgment]
func _initialize():
	_run()

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var out: String = args[0]
	var variant: String = args[1] if args.size() > 1 and args[1] != "bare" else ""
	var view: String = args[2] if args.size() > 2 else "game"
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
	var r: Node3D = Knight.build_meshy(variant != "") if Knight.meshy_ok() else Knight.build(Knight.default_gear())
	r.set_meta("pers", "hero")
	r.set_meta("gait", "knight")
	r.set("fixed_dt", 1.0 / 30.0)
	root3.add_child(r)
	var J: Dictionary = r.get_meta("j")
	var sword := Models.item_model({"base": "broad_sword", "rarity": 0})
	(J["grip_r"] as Node3D).add_child(sword)
	if variant != "":
		var sh := Models.item_model({"base": "kite_shield", "rarity": 0})
		(J["mount_l"] as Node3D).add_child(sh)
	var trail := MeshInstance3D.new()
	var im := ImmediateMesh.new()
	trail.mesh = im
	var tm := StandardMaterial3D.new()
	tm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	tm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	tm.vertex_color_use_as_albedo = true
	tm.cull_mode = BaseMaterial3D.CULL_DISABLED
	trail.material_override = tm
	root3.add_child(trail)
	var pts: Array = []
	var cam := Camera3D.new()
	cam.fov = 40
	root3.add_child(cam)
	var dt := 1.0 / 60.0
	r.set("fixed_dt", dt)
	var fdir := Vector3(1, 0, 1).normalized() if view == "game" else Vector3(0, 0, -1)
	r.rotation.y = atan2(-fdir.x, -fdir.z)
	var H = load("res://scripts/hero.gd")
	var plan := []
	for k in ["swipe1", "swipe2", "swipe3"]:
		var L: Array = H.SWIPE_LUNGE[k]
		plan.append([k, H.SWIPE_DUR[k], 1.0 if k == "swipe3" else 0.68, L[2], [L[0], L[1]]])
	if args.has("judgment"):    # the knight's Q instead of the combo
		var LC: Array = H.SWIPE_LUNGE["cleave"]
		plan = [["cleave", 0.95, 1.0, LC[2], [LC[0], LC[1]]]]
	var seq: Array = []    # per frame: [style, a]
	for k in 2:
		for p in plan:
			var n := int(ceil(float(p[1]) * float(p[2]) / dt))
			for i in n:
				seq.append([p[0], float(i) * dt / float(p[1]), p])
		for i in 14:
			seq.append(["", -1.0, null])
	var f := 0
	var prev_a := 0.0
	var prev_style := ""
	for s in seq:
		var st: String = s[0]
		var a: float = s[1]
		if st != "":
			var L: Array = s[2][4]
			var a0 := prev_a if st == prev_style else 0.0
			var f0 := clampf((a0 - L[0]) / (L[1] - L[0]), 0.0, 1.0)
			var f1 := clampf((a - L[0]) / (L[1] - L[0]), 0.0, 1.0)
			r.position += fdir * (smoothstep(0.0, 1.0, f1) - smoothstep(0.0, 1.0, f0)) * float(s[2][3])
		if st == "cleave" and prev_a < 0.5 and a >= 0.5:    # Holy Slam's impact effects, as in Hero._impact
			var fw := -r.global_transform.basis.z
			var at := r.global_position + fw * 1.25
			Fx.holy_slam(root3, at, 2.6)
		prev_a = a
		prev_style = st
		Anim.pose(r, {"time": 2.0 + f * dt, "phase": 0.0, "move": 0.0, "atk": a, "style": st if st != "" else "over"})
		# trail along the blade
		im.clear_surfaces()
		if a >= 0.0:
			pts.push_front([sword.global_transform * Vector3(0, 0, -0.25), sword.global_transform * Vector3(0, 0, -1.0)])
			if pts.size() > 10:
				pts.pop_back()
		elif pts.size() > 0:
			pts.pop_back()
		if pts.size() >= 2:
			im.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
			for i in pts.size():
				var w := 1.0 - float(i) / pts.size()
				im.surface_set_color(Color(0.85, 0.9, 1.0, w * 0.5))
				im.surface_add_vertex(pts[i][0])
				im.surface_set_color(Color(0.85, 0.9, 1.0, w * 0.85))
				im.surface_add_vertex(pts[i][1])
			im.surface_end()
		var c := r.position
		var off := Vector3(0, 8.5, 8.25) if view == "game" else (Vector3(4.0, 1.3, 0.0) if view == "side" else Vector3(1.2, 1.6, -3.6))
		cam.fov = 24 if view == "game" else 40
		cam.transform = Transform3D(Basis(), c + off).looking_at(c + Vector3(0, 1.0, 0))
		await process_frame
		await RenderingServer.frame_post_draw
		get_root().get_texture().get_image().save_png("%s/s%03d.png" % [out, f])
		f += 1
	quit()
