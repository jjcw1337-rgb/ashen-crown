extends SceneTree
## Starts a new game, saves a screenshot, presses the F8 testing kit, saves another.
## Usage: godot --path . -s tools/kit_shot.gd -- <out_dir>
var g
func _initialize():
	g = (load("res://main.tscn") as PackedScene).instantiate()
	get_root().add_child(g)
	_run()
func _run() -> void:
	var out: String = OS.get_cmdline_user_args()[0]
	while g.world == null or g._busy:
		await process_frame
	await g.start_game(false)
	g.ui.close_all()
	await create_timer(3.0).timeout
	get_root().get_texture().get_image().save_png(out + "/kit_before.png")
	g.give_test_gear()
	await create_timer(3.0).timeout
	get_root().get_texture().get_image().save_png(out + "/kit_after.png")
	print("[KS] quality ", g.quality, " forward ", g.is_forward())
	quit()
