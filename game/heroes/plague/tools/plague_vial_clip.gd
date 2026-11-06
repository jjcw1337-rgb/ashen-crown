extends SceneTree
## Frames of Pestilence Vial (the Plague Doctor's Q, PlagueVialFx) for previews and the gameplay video. Needs a
## display (xvfb) and --fixed-fps 30 so the frames are 1/30 s apart whatever the render takes:
##   xvfb-run -a godot --rendering-driver opengl3 --path . --resolution 1280x720 --fixed-fps 30 \
##     -s game/heroes/plague/tools/plague_vial_clip.gd -- <outdir> [close|game|fight|hand] [seconds] [throws] [quality]
##  close: a low three-quarter view beside the landing spot: the throw, the vial tumbling in, the shatter, the pool
##  hand:  close on him: the vial plucked, its liquid sloshing as he throws
##  game:  the game's own camera, no HUD, throws at a standing pack
##  fight: the game's camera with the HUD, a pack that comes at him, `throws` throws as the cooldown allows
## Writes <outdir>/f_NNN.png.
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
	var secs: float = float(args[2]) if args.size() > 2 else (8.0 if view == "fight" else 3.0)
	var throws: int = int(args[3]) if args.size() > 3 else (5 if view == "fight" else 1)
	var quality: int = int(args[4]) if args.size() > 4 else 0
	while g.world == null or g._busy or g._intro_playing:
		g._intro_skip = true
		await process_frame
	g.apply_quality(0)
	await g.start_game(false, "plague")
	g.ui.close_all()
	await g.load_zone(0, "wild", "road")
	g.ui.close_all()
	var h = g.hero
	h.level = 20
	h.recalc()
	h.mana = h.max_mana
	g.test_immortal = true
	g.zoom = 0.62 if view != "fight" else 0.8
	g.ui.visible = view == "fight"
	(g.vignette.material as ShaderMaterial).set_shader_parameter("strength", 0.0 if view != "fight" else 0.6)
	g.apply_quality(quality)
	if quality == 0:
		g.sun.shadow_enabled = false
		get_root().msaa_3d = Viewport.MSAA_DISABLED
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
		var p := home + Vector3(-1.2 * (n - 1) * 0.5 + i * 1.2, 0, -7.5 - absf(i - (n - 1) * 0.5) * 0.5)
		if view == "fight":
			p = home + Vector3(cos(i * 1.05) * 4.0, 0, -8.0 - absf(sin(i * 1.05)) * 3.0)
		p = g.world.free_spot_near(p, 0.5)
		var e = g.spawn_enemy("zombie" if i % 3 != 2 else "fallen", p, 24)
		e.max_life = 4000.0
		e.life = 4000.0
		if view != "fight":
			e.aggro = false
			e.scripted = 99.0
		foes.append(e)
	h._face(Vector3(0, 0, -1))
	await wait(0.6)
	var frames: int = int(secs * 30)
	var gap: int = 50            # the cooldown's 1.6 s, plus a beat
	var next_throw := 8
	var thrown := 0
	var land := home + Vector3(0, 0, -7.5)
	for f in frames:
		if f == next_throw and thrown < throws:
			h.cds["toxic"] = 0.0
			h.mana = h.max_mana
			var live := foes.filter(func(e): return is_instance_valid(e) and not e.dead)
			var aim: Vector3 = land
			if not live.is_empty():
				live.sort_custom(func(a, b): return a.global_position.distance_to(h.global_position) < b.global_position.distance_to(h.global_position))
				aim = live[thrown % live.size()].global_position
			if view == "fight":
				# lead them a little: where they're walking to
				aim += (h.global_position - aim).normalized() * 0.9
			h.cursor = aim
			h.use_skill("toxic", h.skill_aim("toxic", aim))
			if thrown == 0:
				land = aim
			thrown += 1
			next_throw = f + gap
		match view:
			"close":
				cam.current = true
				cam.fov = 42
				var c: Vector3 = land
				cam.global_transform = Transform3D(Basis(), c + Vector3(4.6, 2.4, 3.2)).looking_at(c + Vector3(-0.6, 0.5, 1.6))
			"hand":
				cam.current = true
				cam.fov = 36
				var c2: Vector3 = h.global_position
				cam.global_transform = Transform3D(Basis(), c2 + Vector3(2.4, 1.9, -1.6)).looking_at(c2 + Vector3(0, 1.3, -0.4))
			_:
				g.cam.current = true
		await process_frame
		await RenderingServer.frame_post_draw
		get_root().get_texture().get_image().save_png("%s/f_%03d.png" % [out, f])
	quit()
