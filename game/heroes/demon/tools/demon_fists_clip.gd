extends SceneTree
## Frames of Molten Fists ("Hellbrand", DemonFistsFx) for previews and the gameplay video. Needs a display (xvfb)
## and --fixed-fps 30 so the frames are 1/30 s apart whatever the render takes:
##   xvfb-run -a godot --rendering-driver opengl3 --path . --resolution 1280x720 --fixed-fps 30 \
##     -s tools/demon_fists_clip.gd -- <outdir> [close|front|game|fight] [tier 0-3] [seconds] [casts]
##  close: a three-quarter view from his right into a standing pack, one cast (the default)
##  front: low, from in front of him (the fangs and the gauntlets face the camera)
##  game:  the game's own camera, one cast, no HUD
##  fire:  close on his burning fists (the gather held) and a fire on the ground beside him: the fire alone
##  fight: the game's camera with the HUD, a pack that fights back, `casts` casts in a row (the gameplay video)
## tier forces InfernalFx's budget (default 2 = High; the OpenGL renderer has no heat haze). Writes <outdir>/f_NNN.png.
var g

func _initialize():
	g = (load("res://main.tscn") as PackedScene).instantiate()
	get_root().add_child(g)
	_run()

func wait(s: float) -> void:
	await create_timer(s).timeout

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var out: String = args[0]
	var view: String = args[1] if args.size() > 1 else "close"
	var tier: int = int(args[2]) if args.size() > 2 else 2
	var secs: float = float(args[3]) if args.size() > 3 else (6.0 if view == "fight" else 2.6)
	var casts: int = int(args[4]) if args.size() > 4 else (4 if view == "fight" else 1)
	while g.world == null or g._busy or g._intro_playing:
		g._intro_skip = true
		await process_frame
	g.apply_quality(0)
	await g.start_game(false, "demon")
	g.ui.close_all()
	await g.load_zone(0, "sandbox", "start")
	g.ui.close_all()
	var h = g.hero
	h.level = 20
	h.recalc()
	h.mana = h.max_mana
	g.test_immortal = true
	g.zoom = 0.62 if view != "fight" else 0.8
	g.ui.visible = view == "fight"
	(g.vignette.material as ShaderMaterial).set_shader_parameter("strength", 0.0 if view != "fight" else 0.6)
	# software GL under xvfb: the Low preset and no sun shadows keep the frames bearable; the effect's own
	# budget is forced separately
	g.apply_quality(0)
	g.sun.shadow_enabled = false
	get_root().msaa_3d = Viewport.MSAA_DISABLED
	InfernalFx.force_tier = tier
	var cam := Camera3D.new()
	cam.fov = 38
	get_root().add_child(cam)
	for e in g.enemies_near(h.global_position, 60.0):
		e.queue_free()
	await process_frame
	var home: Vector3 = h.global_position
	var foes := []
	var n := 3 if view != "fight" else 6
	for i in n:
		var p := home + Vector3(-1.1 * (n - 1) * 0.5 + i * 1.1, 0, -2.6 - absf(i - (n - 1) * 0.5) * 0.6)
		if view == "fight":
			p = home + Vector3(cos(i * 1.05) * 3.2, 0, -2.0 - absf(sin(i * 1.05)) * 2.2)
		p = g.world.free_spot_near(p, 0.5)
		var e = g.spawn_enemy("zombie" if i % 3 != 2 else "fallen", p, 24)
		e.max_life = 4000.0
		e.life = 4000.0
		if view != "fight":
			e.aggro = false
			e.scripted = 99.0
		foes.append(e)
	h._face(Vector3(0, 0, -1))
	# a moment to settle (and for InfernalFx.warm to compile its shaders)
	await wait(0.6)
	if view == "fire":
		DemonFistsFx.hold = true
		for e in foes:
			e.queue_free()
		foes.clear()
		InfernalFx.fire(g.world.fx_root, home + Vector3(1.6, g.world.height_at(home.x + 1.6, home.z - 1.0) - home.y, -1.0), 1.1, 50.0, tier)
		h.use_skill("fists", home + Vector3(0, 0, -3))
		casts = 0
	var frames: int = int(secs * 30)
	var gap: int = 26 if view == "fight" else 999
	var next_cast := 8
	var cast_n := 0
	for f in frames:
		if f == next_cast and cast_n < casts:
			for k in h.cds.keys():
				h.cds[k] = 0.0
			h.mana = h.max_mana
			var live := foes.filter(func(e): return is_instance_valid(e) and not e.dead)
			var aim: Vector3 = home + Vector3(0, 0, -3)
			if not live.is_empty():
				live.sort_custom(func(a, b): return a.global_position.distance_to(h.global_position) < b.global_position.distance_to(h.global_position))
				aim = live[0].global_position
			if view == "fight":
				# aim round the pack: the wedge sweeps a different part of it each time
				aim = h.global_position + (aim - h.global_position).rotated(Vector3.UP, [0.0, 0.5, -0.5, 0.2, -0.3][cast_n % 5])
			h.cursor = aim
			h.use_skill("fists", h.skill_aim("fists", aim))
			cast_n += 1
			next_cast = f + gap
		match view:
			"close":
				cam.current = true
				var c: Vector3 = h.global_position
				cam.global_transform = Transform3D(Basis(), c + Vector3(4.4, 2.5, -1.4)).looking_at(c + Vector3(0, 1.0, -2.0))
			"fire":
				cam.current = true
				var c3: Vector3 = h.global_position
				cam.fov = 40
				cam.global_transform = Transform3D(Basis(), c3 + Vector3(3.4, 2.3, -3.6)).looking_at(c3 + Vector3(0.8, 1.2, -0.6))
			"front":
				cam.current = true
				var c2: Vector3 = h.global_position
				cam.fov = 44
				cam.global_transform = Transform3D(Basis(), c2 + Vector3(2.6, 1.9, -6.2)).looking_at(c2 + Vector3(0, 1.0, -1.2))
			_:
				g.cam.current = true
		await process_frame
		await RenderingServer.frame_post_draw
		get_root().get_texture().get_image().save_png("%s/f_%03d.png" % [out, f])
	quit()
