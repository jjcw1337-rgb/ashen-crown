extends SceneTree
## Frames of the monsters' heavy blows (Enemy.special_fx: a boss's slam, nova and summoning, the bear's maul) in the
## Arena's hall, from the game camera, for before/after comparisons of their effects. Needs a display and --fixed-fps 30:
##   xvfb-run -a godot --path . --rendering-driver vulkan --resolution 960x540 --fixed-fps 30 \
##     -s tools/visual_audit/special_shots.gd -- outdir kind:event[,kind:event...] [--every 3] [--secs 1.2] [--quality 2]
## Writes outdir/<kind>_<event>_<NNN>.png every --every frames from the blow.
var g

func _initialize():
	g = (load("res://main.tscn") as PackedScene).instantiate()
	get_root().add_child(g)
	_run()

func _arg(args: PackedStringArray, key: String, def: String) -> String:
	var i := args.find(key)
	return args[i + 1] if i >= 0 and i + 1 < args.size() else def

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var out: String = args[0]
	var shots: PackedStringArray = args[1].split(",")
	var every := int(_arg(args, "--every", "3"))
	var secs := float(_arg(args, "--secs", "1.2"))
	var q := int(_arg(args, "--quality", "2"))
	DirAccess.make_dir_recursive_absolute(out)
	while g.world == null or g._busy or g._intro_playing:
		g._intro_skip = true
		await process_frame
	g.apply_quality(q)
	await g.start_game(false, "knight")
	g.ui.close_all()
	await g.load_zone(0, "sandbox", "start")
	g.apply_quality(q)
	g.ui.close_all()
	g.test_immortal = true
	g.zoom = 0.85
	g.ui.visible = false
	var h = g.hero
	for spec in shots:
		var kind := spec.get_slice(":", 0)
		var ev := spec.get_slice(":", 1)
		for e in g.enemies_near(h.global_position, 60.0):
			e.queue_free()
		await process_frame
		var at: Vector3 = g.world.free_spot_near(h.global_position + Vector3(0, 0, -5.5), 1.0)
		var e = g.spawn_enemy(kind, at, 12)
		e.aggro = false
		e.scripted = 99.0
		await create_timer(0.6).timeout
		var frames := int(secs * 30.0)
		for f in frames + 2:
			if f == 2:
				e.special_fx(ev)
			await process_frame
			await RenderingServer.frame_post_draw
			if f >= 2 and (f - 2) % every == 0:
				get_root().get_texture().get_image().save_png("%s/%s_%s_%03d.png" % [out, kind, ev, f - 2])
		e.queue_free()
		await create_timer(0.8).timeout
	print("[SPECIAL] done")
	quit()
