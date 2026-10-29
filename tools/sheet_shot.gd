extends SceneTree
## Screenshot of the character sheet (C) with points to spend and a hovered attribute's tooltip.
## Needs a display. Usage: godot -s tools/sheet_shot.gd -- out.png [class]
var g
func _initialize():
	g = (load("res://main.tscn") as PackedScene).instantiate()
	get_root().add_child(g)
	_run()

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	while g.world == null or g._busy or g._intro_playing:
		await process_frame
	await g.start_game(false, args[1] if args.size() > 1 else "knight")
	while g._busy:
		await process_frame
	g.ui.close_all()
	var h = g.hero
	h.set_level(7)
	h.stat_points = 5
	h.recalc()
	g.ui.toggle(g.ui.char_panel)
	for f in 6:
		await process_frame
	# hover Strength's row so its tooltip shows
	var row: Control = (g.ui.char_labels["str"] as Control).get_parent().get_parent()
	row.mouse_entered.emit()
	for f in 6:
		await process_frame
	g.ui.tooltip.position = row.get_global_rect().position + Vector2(row.size.x + 30, 0)
	await process_frame
	await RenderingServer.frame_post_draw
	get_root().get_texture().get_image().save_png(args[0])
	print("[S] saved")
	quit()
