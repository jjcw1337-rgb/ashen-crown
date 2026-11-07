extends SceneTree
## Screenshot of the waypoint window: Act I's tab with the camp's waypoint, or the Battlegrounds tab.
## Needs a display. Usage: godot -s game/maps/camp/tools/waypoint_shot.gd -- out.png [bg] (bg: the Battlegrounds tab)
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
	g.waypoints_known = ["town"]
	g.ui.open_waypoints()
	var wp = g.ui.wp_panel
	if args.size() > 1 and args[1] == "bg":
		wp.sel_group = "battlegrounds"
		wp._fill()
	for f in 20:
		await process_frame
	# hover the camp's waypoint
	var rows: Array = wp.route_box.get_children()
	if rows.size() > 0 and args.size() <= 1:
		(rows[0] as Control).mouse_entered.emit()
		Input.warp_mouse((rows[0] as Control).get_global_rect().get_center())
	for f in 8:
		await process_frame
	await RenderingServer.frame_post_draw
	get_root().get_texture().get_image().save_png(args[0])
	print("[S] saved")
	quit()
