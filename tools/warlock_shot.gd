extends SceneTree
## Screenshots of the Warlock: idle, Drain Life forking through a pack, Blight Bolt's pool,
## Soul Shackles. Needs a display (xvfb on Linux).
## godot --rendering-driver opengl3 --path . -s tools/warlock_shot.gd -- <out_dir>
var g
func _initialize():
	g = (load("res://main.tscn") as PackedScene).instantiate()
	get_root().add_child(g)
	_run()
func snap(out: String, nm: String) -> void:
	get_root().get_texture().get_image().save_png(out + "/wl_" + nm + ".png")
func _run() -> void:
	var out: String = OS.get_cmdline_user_args()[0]
	while g.world == null or g._busy or g._intro_playing:
		await process_frame
	await g.start_game(false, "warlock")
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
	await g.travel(0, "wild", "start")
	while g._busy:
		await process_frame
	g.ui.close_all()
	var best = null
	var bn := -1
	for e in g.enemies_near(h.global_position, 400.0):
		var n: int = g.enemies_near(e.global_position, 5.5).size()
		if n > bn:
			bn = n
			best = e
	h.global_position = best.global_position + Vector3(5.5, 0, 2.0)
	await create_timer(0.8).timeout
	h.mana = h.max_mana
	h.use_skill("drain", best.global_position)
	await create_timer(0.55).timeout
	snap(out, "drain")
	await create_timer(1.0).timeout
	h.mana = h.max_mana
	var foes: Array = g.enemies_near(h.global_position, 12.0)
	if foes.size() > 0:
		h.use_skill("blight", foes[0].global_position)
		await create_timer(0.9).timeout
		snap(out, "blight")
	await create_timer(0.6).timeout
	h.mana = h.max_mana
	h.use_skill("shackles", h.global_position)
	await create_timer(0.55).timeout
	snap(out, "shackles")
	quit()
