extends SceneTree
## Screenshots of the Demon: close-up, Hellfire Claw, summoned demons, the Underworld, Blood Pact.
## Needs a display: xvfb-run godot --rendering-driver opengl3 --path . -s tools/demon_shot.gd -- <out_dir>
var g
func _initialize():
	g = (load("res://main.tscn") as PackedScene).instantiate()
	get_root().add_child(g)
	_run()
func snap(out: String, nm: String) -> void:
	get_root().get_texture().get_image().save_png(out + "/d_" + nm + ".png")
func _run() -> void:
	var out: String = OS.get_cmdline_user_args()[0]
	while g.world == null or g._busy or g._intro_playing:
		await process_frame
	await g.start_game(false, "demon")
	g.ui.close_all()
	var h = g.hero
	h.level = 12
	h.recalc()
	g.test_immortal = true
	g.zoom = 0.6
	await create_timer(1.2).timeout
	h._face(Vector3(0, 0, 1))
	await create_timer(0.5).timeout
	snap(out, "close")
	h._face(Vector3(0.6, 0, 1))
	await create_timer(0.4).timeout
	snap(out, "close2")
	h.mana = h.max_mana
	h.use_skill("hellclaw", h.global_position + Vector3(0, 0, -3))
	await create_timer(0.42).timeout
	snap(out, "claw")
	await create_timer(0.6).timeout
	for i in 3:
		h.mana = h.max_mana
		h.cds["summon"] = 0.0
		h._face(Vector3([-1.0, 0.0, 1.0][i], 0, -1))
		h.use_skill("summon", h.global_position)
		await create_timer(0.45).timeout
		if i == 0:
			snap(out, "summoning")
		await create_timer(0.4).timeout
	await create_timer(1.5).timeout
	snap(out, "minions")
	await g.travel(0, "wild", "start")
	while g._busy:
		await process_frame
	g.zoom = 0.8
	await create_timer(2.0).timeout
	snap(out, "wild_normal")
	h.mana = h.max_mana
	h.use_skill("phase", h.global_position)
	await create_timer(1.6).timeout
	snap(out, "underworld")
	await create_timer(5.0).timeout
	snap(out, "erupt")
	await create_timer(1.0).timeout
	h.mana = h.max_mana
	h.use_skill("pact", h.global_position)
	await create_timer(0.7).timeout
	snap(out, "pact")
	quit()
