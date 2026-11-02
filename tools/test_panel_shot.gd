extends SceneTree
## Screenshot of the Escape menu with its Admin column. Needs a display (xvfb).
var g
func _initialize():
	g = (load("res://main.tscn") as PackedScene).instantiate()
	get_root().add_child(g)
	_run()
func _run() -> void:
	var out: String = OS.get_cmdline_user_args()[0]
	while g.world == null or g._busy or g._intro_playing:
		await process_frame
	await g.start_game(false)
	g.ui.close_all()
	g.dev_tools = true
	g.toggle_pause()
	await create_timer(1.0).timeout
	get_root().get_texture().get_image().save_png(out + "/test_panel.png")
	quit()
