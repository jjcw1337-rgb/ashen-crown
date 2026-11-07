extends SceneTree
## Frames of each Wraith skill cast into a pack in the Arena's hall, for the preview video and contact sheet. Needs a
## display (xvfb) and --fixed-fps 30 so the frames are 1/30 s apart whatever the render takes:
##   xvfb-run -a godot --rendering-driver opengl3 --path . --resolution 1280x720 --fixed-fps 30 \
##     -s game/heroes/wraith/tools/wraith_skills_clip.gd -- <outdir> [rend|siphon|step|grasp|phantom|night|all] [close|game]
## Writes <outdir>/<skill>_<view>_NNN.png.
var g
const SKILLS := ["rend", "siphon", "step", "grasp", "phantom", "night"]
const SECS := {"rend": 2.0, "siphon": 3.8, "step": 2.2, "grasp": 3.2, "phantom": 2.6, "night": 6.6}
func _initialize():
	g = (load("res://main.tscn") as PackedScene).instantiate()
	get_root().add_child(g)
	_run()
func wait(s: float) -> void:
	await create_timer(s).timeout
func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var out: String = args[0]
	var which: String = args[1] if args.size() > 1 else "all"
	var view: String = args[2] if args.size() > 2 else "close"
	while g.world == null or g._busy or g._intro_playing:
		g._intro_skip = true
		await process_frame
	await g.start_game(false, "wraith")
	g.ui.close_all()
	await g.load_zone(0, "sandbox", "start")
	g.ui.close_all()
	var h = g.hero
	h.level = 20          # (not set_level: its level-up light would be in the frames)
	h.recalc()
	h.mana = h.max_mana
	g.test_immortal = true
	g.zoom = 0.62
	g.ui.visible = false     # just the scene
	(g.vignette.material as ShaderMaterial).set_shader_parameter("strength", 0.0)    # no vignette, but the night's grade still shows
	# software GL under xvfb: the Low preset, no shadows and no multisampling make the frames bearable
	g.apply_quality(0)
	g.sun.shadow_enabled = false
	get_root().msaa_3d = Viewport.MSAA_DISABLED
	var close := Camera3D.new()
	close.fov = 38
	get_root().add_child(close)
	var skills: Array = SKILLS if which == "all" else [which]
	for sk in skills:
		# a pack standing ahead of him (-z), not yet roused
		for e in g.enemies_near(h.global_position, 60.0):
			e.queue_free()
		await process_frame
		var home: Vector3 = h.global_position
		var foes := []
		var n := 3 if sk != "siphon" else 1
		var dist := 3.6 if sk in ["rend", "phantom", "night"] else 5.5
		for i in n:
			var p := home + Vector3(-1.1 + i * 1.1, 0, -dist - absf(i - 1) * 0.5)
			p = g.world.free_spot_near(p, 0.5)
			var e = g.spawn_enemy("zombie", p, 24 if sk == "night" else 14)      # tough enough to stand through a skill
			e.aggro = false
			e.scripted = 99.0       # they stand there for the camera
			foes.append(e)
		h._face(Vector3(0, 0, -1))
		await wait(0.4)
		for k in h.cds.keys():
			h.cds[k] = 0.0
		h.mana = h.max_mana
		h.life = h.max_life * 0.6
		var aim: Vector3 = foes[n / 2].global_position
		if sk == "step":
			aim = foes[0].global_position + Vector3(0.0, 0, 1.0)
		var frames: int = int(SECS[sk] * 30)
		var cast_at := 8
		for f in frames:
			if f == cast_at:
				h.use_skill(sk, h.skill_aim(sk, aim) if sk in ["rend", "siphon", "phantom"] else aim)
			if view == "close":
				close.current = true
				# a three-quarter view from his right, in front; it stays put for the blink and the night
				var c: Vector3 = h.global_position if sk in ["rend", "siphon", "grasp", "phantom"] else home
				var off := Vector3(3.2, 1.8, -2.2)
				var look := c + Vector3(0, 1.0, -1.6)
				if sk == "night":
					off = Vector3(7.0, 3.6, -1.0)
					look = c + Vector3(0, 1.5, -1.5)
				elif sk in ["grasp", "phantom", "siphon"]:
					off = Vector3(4.2, 2.3, 0.4)
					look = c + Vector3(0, 0.9, -2.4)
				elif sk == "step":
					off = Vector3(5.0, 2.8, 0.6)
					look = c + Vector3(0, 0.9, -2.6)
				close.global_transform = Transform3D(Basis(), c + off).looking_at(look)
			else:
				g.cam.current = true
			await process_frame
			await RenderingServer.frame_post_draw
			get_root().get_texture().get_image().save_png("%s/%s_%s_%03d.png" % [out, sk, view, f])
		# back home, whole again
		h.global_position = home
		h.life = h.max_life
		await wait(0.8)
	quit()
