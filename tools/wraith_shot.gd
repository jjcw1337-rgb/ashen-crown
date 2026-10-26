extends SceneTree
## Screenshots of the Wraith: idle, Soul Reap, Banshee Wail, Spectral Host. Needs a display (xvfb).
## godot --rendering-driver opengl3 --path . -s tools/wraith_shot.gd -- <out_dir>
var g
func _initialize():
	g = (load("res://main.tscn") as PackedScene).instantiate()
	get_root().add_child(g)
	_run()
func snap(out: String, nm: String) -> void:
	get_root().get_texture().get_image().save_png(out + "/w_" + nm + ".png")
func _run() -> void:
	var out: String = OS.get_cmdline_user_args()[0]
	while g.world == null or g._busy or g._intro_playing:
		await process_frame
	await g.start_game(false, "wraith")
	g.ui.close_all()
	var h = g.hero
	h.level = 12
	h.recalc()
	g.test_immortal = true
	g.zoom = 0.62
	await create_timer(1.5).timeout
	h._face(Vector3(0, 0, 1))
	await create_timer(0.6).timeout
	snap(out, "idle")
	h.mana = h.max_mana
	h.use_skill("reap", h.global_position + Vector3(0, 0, -3))
	await create_timer(0.5).timeout
	snap(out, "reap")
	await create_timer(0.8).timeout
	h.mana = h.max_mana
	h.use_skill("wail", h.global_position)
	await create_timer(0.42).timeout
	snap(out, "wail")
	await create_timer(1.0).timeout
	h.mana = h.max_mana
	h.use_skill("host", h.global_position)
	await create_timer(1.6).timeout
	snap(out, "host")
	h.cmd_move(h.global_position + Vector3(4, 0, 2))
	await create_timer(0.5).timeout
	snap(out, "move")
	quit()
