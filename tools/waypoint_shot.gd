extends SceneTree
## Screenshot of the waypoint window: Act I with its wilderness waypoint bound, A2 open, A3 sealed.
## Needs a display. Usage: godot -s tools/waypoint_shot.gd -- out.png [run to show]
var g
func _initialize():
	g = (load("res://main.tscn") as PackedScene).instantiate()
	get_root().add_child(g)
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
	if args.size() > 1:
		wp.sel_run = int(args[1])
		wp._fill()
	for f in 20:
		await process_frame
	# hover the wilderness waypoint
	var rows: Array = wp.route_box.get_children()
	if rows.size() > 1 and args.size() <= 1:
		(rows[1] as Control).mouse_entered.emit()
		Input.warp_mouse((rows[1] as Control).get_global_rect().get_center())
	for f in 8:
		await process_frame
	await RenderingServer.frame_post_draw
	get_root().get_texture().get_image().save_png(args[0])
	print("[S] saved")
	quit()
