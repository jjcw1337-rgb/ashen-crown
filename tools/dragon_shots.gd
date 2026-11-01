extends SceneTree
## Screenshots of the dragon classes. Needs a display.
##   godot --path . -s tools/dragon_shots.gd -- outdir wyrm|serpent|wyvern   # in the camp: idle, walk, run, the three
##                                                                           # attack blows, block (game camera, zoomed in)
##   godot --path . -s tools/dragon_shots.gd -- outdir picker                # the class picker centred on each dragon
var g
var out := ""

func _initialize():
	g = (load("res://main.tscn") as PackedScene).instantiate()
	get_root().add_child(g)
	_run()

func _snap(nm: String) -> void:
	await process_frame
	await process_frame
	get_root().get_texture().get_image().save_png(out + "/" + nm + ".png")
	print("[DS] ", nm)

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	out = args[0]
	var what: String = args[1] if args.size() > 1 else "wyrm"
	while g.world == null or g._busy or g._intro_playing:
		g._intro_skip = true
		await process_frame
	if what == "picker":
		while not g.ui.title_panel.visible:
			await process_frame
		g.ui.open_class_picker()
		var st = g.ui.class_stage
		await create_timer(2.5).timeout
		await _snap("picker_knight")
		for c in ["wyrm", "serpent", "wyvern"]:
			st.go_to(c)
			await create_timer(2.2).timeout
			await _snap("picker_" + c)
			# its signature (the tail spin) at the impact
			st._sig_t[c] = 0.0
			st._hit_done[c] = false
			await create_timer(float(ClassStage.SIGNATURE[c][1]) * 0.47).timeout
			await _snap("picker_" + c + "_spin")
		quit()
		return
	await g.start_game(false, what)
	g.apply_quality(0)           # Low: software GL in CI is slow
	g.ui.close_all()
	g.playing = false            # keep the real keyboard off the hero
	g.test_immortal = true
	for e in g.world.enemies_root.get_children():
		e.queue_free()
	g.zoom = 0.6
	var h = g.hero
	h._face(Vector3(1, 0, 0.6))
	await create_timer(1.5).timeout
	await _snap(what + "_idle")
	h.direct_dir = Vector3(1, 0, 0.35)
	await create_timer(1.0).timeout
	await _snap(what + "_walk")
	h.sprint = true
	await create_timer(0.7).timeout
	await _snap(what + "_run")
	await create_timer(0.23).timeout
	await _snap(what + "_run2")
	h.sprint = false
	h.direct_dir = Vector3.ZERO
	await create_timer(1.0).timeout
	var ahead: Vector3 = h.global_position + Vector3(2.0, 0, 0.8)
	for k in 3:
		h.swipe_attack(ahead, false)
		await create_timer(h.atk_dur * Anim.impact_at(h.atk_style) * 0.9).timeout
		await _snap(what + "_attack%d" % (k + 1))
		await create_timer(maxf(0.1, h.atk_dur * 0.75)).timeout
	await create_timer(0.6).timeout
	h.blocking = true
	await create_timer(0.6).timeout
	await _snap(what + "_block")
	h.blocking = false
	quit()
