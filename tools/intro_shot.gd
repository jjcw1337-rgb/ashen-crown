extends SceneTree
## Starts the game normally (intro included), grabs a frame mid-intro, then skips and grabs the title.
var g
func _initialize():
	g = (load("res://main.tscn") as PackedScene).instantiate()
	get_root().add_child(g)
	_run()
func _run() -> void:
	await create_timer(6.0).timeout
	get_root().get_texture().get_image().save_png(OS.get_cmdline_user_args()[0] + "/intro_a.png")
	print("[I] intro playing: ", g._intro_playing)
	var ev := InputEventKey.new()
	ev.keycode = KEY_SPACE
	ev.pressed = true
	Input.parse_input_event(ev)
	await create_timer(12.0).timeout
	get_root().get_texture().get_image().save_png(OS.get_cmdline_user_args()[0] + "/intro_b.png")
	print("[I] after skip, intro playing: ", g._intro_playing, "  title visible: ", g.ui.title_panel.visible)
	quit()
