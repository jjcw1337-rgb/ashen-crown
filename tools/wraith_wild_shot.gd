extends SceneTree
## Wraith walking into Cairnfell Moor: screenshots right after arriving and a few seconds later.
var g
func _initialize():
	g = (load("res://main.tscn") as PackedScene).instantiate()
	get_root().add_child(g)
	_run()
func _run() -> void:
	var out: String = OS.get_cmdline_user_args()[0]
	while g.world == null or g._busy or g._intro_playing:
		await process_frame
	await g.start_game(false, "wraith")
	g.ui.close_all()
	g.test_immortal = true
	await create_timer(1.0).timeout
	await g.travel(0, "wild", "start")
	while g._busy:
		await process_frame
	await create_timer(2.0).timeout
	get_root().get_texture().get_image().save_png(out + "/wild_a.png")
	g.hero.cmd_move(g.hero.global_position + Vector3(3, 0, -5))
	await create_timer(4.0).timeout
	get_root().get_texture().get_image().save_png(out + "/wild_b.png")
	print("[WW] quality ", g.quality, " hero visible ", g.hero.visible, " rig ", g.hero.rig != null)
	quit()
