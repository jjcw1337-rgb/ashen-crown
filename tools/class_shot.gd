extends SceneTree
## Screenshots of the New Game class picker and the Wraith's action bar. Needs a display.
var g
func _initialize():
	g = (load("res://main.tscn") as PackedScene).instantiate()
	get_root().add_child(g)
	_run()
func _run() -> void:
	var out: String = OS.get_cmdline_user_args()[0]
	while g.world == null or g._busy or g._intro_playing or not g.ui.title_panel.visible:
		await process_frame
	g.ui.class_panel.visible = true
	await create_timer(1.0).timeout
	get_root().get_texture().get_image().save_png(out + "/class_pick.png")
	await g.start_game(false, "wraith")
	g.ui.close_all()
	g.hero.level = 10
	await create_timer(1.0).timeout
	get_root().get_texture().get_image().save_png(out + "/wraith_hud.png")
	quit()
