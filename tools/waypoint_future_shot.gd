extends SceneTree
## Mock-up of the waypoint window with room to grow: sample Acts IV-V and an Ancient Levels group
## (screenshot only; nothing is added to the game). godot -s tools/waypoint_future_shot.gd -- out.png [ancient]
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
	var wp = g.ui.wp_panel
	var acts: Array = Data.WAYPOINT_ACTS.duplicate(true)
	if args.has("many"):
		acts[0]["points"] = [{"id": "town", "zone": "town", "kind": "camp"}, {"id": "wild", "zone": "wild", "kind": "wild"},
			{"id": "w3", "zone": "w3", "kind": "wild", "name": "Blackroot Hollow"}, {"id": "w4", "zone": "w4", "kind": "road", "name": "The Old Toll Bridge"},
			{"id": "w5", "zone": "w5", "kind": "wild", "name": "Weeping Fen"}, {"id": "w6", "zone": "w6", "kind": "city", "name": "Ruins of Carrow"}]
		g.waypoints_known = ["town", "wild", "w3", "w4"]
	acts.append({"run": 3, "group": "acts", "tab": "IV", "name": "Act IV", "art": "res://assets/textures/ui/wp_act3.png", "boss": "ashen_king", "points": [{"id": "town", "zone": "town", "kind": "camp"}]})
	acts.append({"run": 4, "group": "acts", "tab": "V", "name": "Act V", "art": "res://assets/textures/ui/wp_act3.png", "boss": "ashen_king", "points": [{"id": "town", "zone": "town", "kind": "camp"}]})
	acts.append({"run": 10, "group": "ancient", "tab": "✦", "name": "The Sunken Vault", "art": "res://assets/textures/ui/wp_act1.png", "boss": "goblin_king", "points": [{"id": "town", "zone": "town", "kind": "camp"}]})
	acts.append({"run": 11, "group": "ancient", "tab": "✦", "name": "Ember Halls", "art": "res://assets/textures/ui/wp_act3.png", "boss": "ashen_king", "points": [{"id": "town", "zone": "town", "kind": "camp"}]})
	wp.acts_override = acts
	g.ui.open_waypoints()
	if args.has("ancient"):
		wp.sel_group = "ancient"
		wp.sel_run = 10
		wp._fill()
	for f in 20:
		await process_frame
	await RenderingServer.frame_post_draw
	get_root().get_texture().get_image().save_png(args[0])
	print("[S] saved")
	quit()
