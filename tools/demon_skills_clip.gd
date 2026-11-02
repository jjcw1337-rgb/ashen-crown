extends SceneTree
## Frames of each Demon skill cast into a pack on the moor, for the preview video and contact sheet. Needs a
## display (xvfb) and --fixed-fps 30 so the frames are 1/30 s apart whatever the render takes:
##   xvfb-run -a godot --rendering-driver opengl3 --path . --resolution 1280x720 --fixed-fps 30 \
##     -s tools/demon_skills_clip.gd -- <outdir> [fists|icharge|cslam|hurl|grip|wrath|all, or a list: hurl,wrath] [close|game]
## (In a container where tool scripts hit "Identifier not found: Sfx", go through tools/_late.gd.)
## Writes <outdir>/<skill>_<view>_NNN.png.
var g
const SKILLS := ["fists", "icharge", "cslam", "hurl", "grip", "wrath"]
const SECS := {"fists": 2.2, "icharge": 3.0, "cslam": 5.6, "hurl": 3.2, "grip": 4.0, "wrath": 6.5}
func _initialize():
	g = (load("res://main.tscn") as PackedScene).instantiate()
	get_root().add_child(g)
	_run()
func wait(s: float) -> void:
	await create_timer(s).timeout
func _run() -> void:
	var args: Array = Array(OS.get_cmdline_user_args()).filter(func(x): return not str(x).begins_with("res://"))
	var out: String = args[0]
	var which: String = args[1] if args.size() > 1 else "all"
	var view: String = args[2] if args.size() > 2 else "close"
	while g.world == null or g._busy or g._intro_playing:
		g._intro_skip = true
		await process_frame
	g.apply_quality(0)
	await g.start_game(false, "demon")
	g.ui.close_all()
	await g.load_zone(0, "wild", "road")
	g.ui.close_all()
	var h = g.hero
	h.level = 20          # (not set_level: its level-up light would be in the frames)
	h.recalc()
	h.mana = h.max_mana
	g.test_immortal = true
	g.zoom = 0.62
	g.ui.visible = false     # just the scene
	(g.vignette.material as ShaderMaterial).set_shader_parameter("strength", 0.0)
	# software GL under xvfb: the Low preset, no shadows and no multisampling make the frames bearable
	g.apply_quality(0)
	g.sun.shadow_enabled = false
	get_root().msaa_3d = Viewport.MSAA_DISABLED
	var close := Camera3D.new()
	close.fov = 38
	get_root().add_child(close)
	var skills: Array = SKILLS if which == "all" else Array(which.split(","))
	for sk in skills:
		# a pack standing ahead of him (-z), not yet roused
		for e in g.enemies_near(h.global_position, 60.0):
			e.queue_free()
		await process_frame
		var home: Vector3 = h.global_position
		var foes := []
		var n := 3 if sk != "wrath" else 5
		if sk == "grip":
			n = 1
		var dist: float = {"fists": 2.6, "icharge": 6.0, "cslam": 3.0, "hurl": 7.5, "grip": 5.5, "wrath": 5.0}[sk]
		for i in n:
			var p := home + Vector3(-1.1 * (n - 1) * 0.5 + i * 1.1, 0, -dist - absf(i - (n - 1) * 0.5) * 0.6)
			if sk == "wrath":
				p = home + Vector3(cos(i * 1.3) * 4.5, 0, -2.5 - absf(sin(i * 1.3)) * 4.0)
			p = g.world.free_spot_near(p, 0.5)
			var e = g.spawn_enemy("zombie", p, 24)      # tough enough to stand through a skill
			e.aggro = false
			e.scripted = 99.0
			e.max_life = 4000.0
			e.life = 4000.0
			foes.append(e)
		h._face(Vector3(0, 0, -1))
		await wait(0.4)
		for k in h.cds.keys():
			h.cds[k] = 0.0
		h.mana = h.max_mana
		var aim: Vector3 = foes[n / 2].global_position
		if sk == "icharge":
			aim = home + Vector3(0, 0, -9.0)
		var frames: int = int(SECS[sk] * 30)
		var cast_at := 8
		for f in frames:
			if f == cast_at:
				h.use_skill(sk, h.skill_aim(sk, aim) if Data.skill_def(sk).get("aim", "facing") == "facing" else aim)
			if view == "close":
				close.current = true
				# a three-quarter view from his right, in front; it stays put for the charge and the wrath
				var c: Vector3 = home if sk in ["icharge", "wrath"] else h.global_position
				var off := Vector3(4.2, 2.4, -1.6)
				var look := c + Vector3(0, 1.2, -2.0)
				if sk == "wrath":
					off = Vector3(9.0, 5.5, 1.0)
					look = c + Vector3(0, 1.4, -3.0)
				elif sk == "grip":
					# from the side, back far enough for the chain's whole reach and the hoist
					c = home
					off = Vector3(6.8, 3.6, -2.4)
					look = c + Vector3(0, 1.5, -2.9)
				elif sk in ["icharge", "cslam", "hurl"]:
					off = Vector3(5.2, 3.4, 1.2)
					look = c + Vector3(-0.3, 0.8, -2.6)
				close.global_transform = Transform3D(Basis(), c + off).looking_at(look)
			else:
				g.cam.current = true
			await process_frame
			await RenderingServer.frame_post_draw
			get_root().get_texture().get_image().save_png("%s/%s_%s_%03d.png" % [out, sk, view, f])
		# back home, whole again
		load("res://scripts/demon_skills.gd").clear(h)
		h.global_position = home
		h.life = h.max_life
		await wait(0.8)
	quit()
