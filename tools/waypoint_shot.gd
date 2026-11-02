extends SceneTree
## Screenshot of the waypoint window: Act I with its wilderness waypoint bound, A2 open, A3 sealed.
## Needs a display. Usage: godot -s tools/waypoint_shot.gd -- out.png [run to show | bg]
## `bg` shows the Battlegrounds tab (the Hollow Crypt's card, hovered).
var g
func _initialize():
	g = (load("res://main.tscn") as PackedScene).instantiate()
	get_root().add_child(g)
	g._intro_skip = true          # (the trailer would play a minute first)
	g.set_quality(int(OS.get_cmdline_user_args()[OS.get_cmdline_user_args().find("quality") + 1]) if OS.get_cmdline_user_args().has("quality") else 0)
	_run()

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	while g.world == null or g._busy or g._intro_playing:
		await process_frame
	await g.start_game(false, "knight")
	while g._busy:
		await process_frame
	g.ui.close_all()
	g.max_run = 1
	g.waypoints_known = ["town", "wild"]
	g.run_progress["1"] = {"waypoints": ["town"], "boss": false}
	g.ui.open_waypoints()
	var wp = g.ui.wp_panel
	var bg := args.size() > 1 and args[1] == "bg"
	if bg:
		wp.sel_group = "battlegrounds"
		wp._fill()
	elif args.size() > 1:
		wp.sel_run = int(args[1])
		wp._fill()
	for f in 20:
		await process_frame
	var rows: Array = wp.route_box.get_children()
	if bg and not rows.is_empty():
		# hover the crypt's card
		(rows[0] as Control).mouse_entered.emit()
		Input.warp_mouse((rows[0] as Control).get_global_rect().get_center())
	elif rows.size() > 1 and args.size() <= 1:
		# hover the wilderness waypoint
		(rows[1] as Control).mouse_entered.emit()
		Input.warp_mouse((rows[1] as Control).get_global_rect().get_center())
	for f in (40 if bg else 8):      # (the Battlegrounds card's server probe answers within a couple of seconds)
		await process_frame
	await RenderingServer.frame_post_draw
	get_root().get_texture().get_image().save_png(args[0])
	print("[S] saved")
	quit()
