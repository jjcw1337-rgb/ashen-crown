extends SceneTree
## Frames of any class's skills cast into a pack on the moor, for before/after comparisons of skill effects.
## Needs a display and --fixed-fps 30 (frames 1/30 s apart whatever the render takes):
##   xvfb-run -a godot --path . --rendering-driver vulkan --resolution 960x540 --fixed-fps 30 \
##     -s tools/visual_audit/skill_shots.gd -- outdir class skill[:secs][,skill[:secs]...] [--quality 2] [--every 3] [--secs 1.6] [--view game|close]
## Writes outdir/<skill>_<NNN>.png every --every frames from the cast, for --secs seconds (or the skill's own :secs:
## a thrown bottle with a fuse needs longer than a slam). The game view keeps the HUD off and the
## real camera (zoomed in a little); the close view watches from his right, in front.
var g

func _initialize():
	g = (load("res://main.tscn") as PackedScene).instantiate()
	get_root().add_child(g)
	_run()

func wait(s: float) -> void:
	await create_timer(s).timeout

func _arg(args: PackedStringArray, key: String, def: String) -> String:
	var i := args.find(key)
	return args[i + 1] if i >= 0 and i + 1 < args.size() else def

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var out: String = args[0]
	var cls: String = args[1]
	var skills: PackedStringArray = args[2].split(",")
	var q := int(_arg(args, "--quality", "2"))
	var every := int(_arg(args, "--every", "3"))
	var secs := float(_arg(args, "--secs", "1.6"))
	var view := _arg(args, "--view", "game")
	DirAccess.make_dir_recursive_absolute(out)
	while g.world == null or g._busy or g._intro_playing:
		g._intro_skip = true
		await process_frame
	g.apply_quality(q)
	await g.start_game(false, cls)
	g.ui.close_all()
	await g.load_zone(0, "wild", "road")
	g.apply_quality(q)
	g.ui.close_all()
	var h = g.hero
	h.level = 20
	h.recalc()
	g.test_immortal = true
	g.zoom = 0.75
	g.ui.visible = false
	var close := Camera3D.new()
	close.fov = 40
	get_root().add_child(close)
	for spec in skills:
		var sk := spec.get_slice(":", 0)
		var sk_secs := float(spec.get_slice(":", 1)) if spec.contains(":") else secs
		for e in g.enemies_near(h.global_position, 60.0):
			e.queue_free()
		await process_frame
		var home: Vector3 = h.global_position
		var foes := []
		for i in 4:
			var p: Vector3 = g.world.free_spot_near(home + Vector3(-2.4 + i * 1.6, 0, -3.6 - absf(i - 1.5) * 0.7), 0.5)
			var e = g.spawn_enemy("zombie", p, 24)
			e.aggro = false
			e.scripted = 99.0
			e.max_life = 4000.0
			e.life = 4000.0
			foes.append(e)
		h._face(Vector3(0, 0, -1))
		await wait(0.5)
		for k in h.cds.keys():
			h.cds[k] = 0.0
		h.mana = h.max_mana
		var aim: Vector3 = foes[1].global_position
		var frames := int(sk_secs * 30.0)
		var cast_at := 4
		for f in frames + cast_at:
			if f == cast_at:
				var def: Dictionary = Data.skill_def(sk)
				h.use_skill(sk, h.skill_aim(sk, aim) if def.get("aim", "facing") == "facing" else aim)
			if view == "close":
				close.current = true
				close.global_transform = Transform3D(Basis(), home + Vector3(5.5, 3.6, 2.4)).looking_at(home + Vector3(0, 0.9, -1.8))
			else:
				g.cam.current = true
			await process_frame
			await RenderingServer.frame_post_draw
			if f >= cast_at and (f - cast_at) % every == 0:
				get_root().get_texture().get_image().save_png("%s/%s_%03d.png" % [out, sk, f - cast_at])
		h.global_position = home
		h.life = h.max_life
		await wait(0.6)
	print("[SKILLS] done")
	quit()
