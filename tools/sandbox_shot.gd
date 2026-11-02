extends SceneTree
## Screenshots of the admins' Battlegrounds sandbox: the panel, two bots fighting the player, a monster pack.
##   godot --path . --resolution 1600x900 -s tools/sandbox_shot.gd -- outdir
var g
func _initialize():
	g = (load("res://main.tscn") as PackedScene).instantiate()
	get_root().add_child(g)
	_run()
func _run() -> void:
	var out: String = OS.get_cmdline_user_args()[0]
	while g.world == null or g._busy or g._intro_playing:
		await process_frame
	await g.start_game(false, "knight")
	while g._busy:
		await process_frame
	g.ui.close_all()
	g.dev_tools = true
	g.test_immortal = true
	await g.open_sandbox()
	while g._busy:
		await process_frame
	var sb = g.sandbox
	sb.spawn_bot("demon", 20, "geared")
	sb.spawn_bot("archer", 20, "fresh")
	sb.spawn_pack("zombie", 4)
	for i in 240:
		await process_frame
	get_root().get_texture().get_image().save_png(out + "/sandbox_1.png")
	for i in 360:
		await process_frame
	get_root().get_texture().get_image().save_png(out + "/sandbox_2.png")
	quit()
