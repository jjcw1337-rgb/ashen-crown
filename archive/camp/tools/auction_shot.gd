extends SceneTree
## Screenshots of the Gilded Hall (the camp's auction house, ForestCamp._auction_hall) from the game camera with the
## hero at its door, by day, and of its auction window (AuctionUI). Needs a display.
##   godot --path . -s tools/_late.gd -- res://tools/auction_shot.gd <outdir>

var g

func _initialize():
	g = (load("res://main.tscn") as PackedScene).instantiate()
	get_root().add_child(g)
	_run()

func wait(s: float) -> void:
	await create_timer(s).timeout

func shot(out: String, name: String) -> void:
	await process_frame
	await RenderingServer.frame_post_draw
	get_root().get_texture().get_image().save_png(out + "/" + name + ".png")
	print("[A] ", name)

func _run() -> void:
	var out: String = OS.get_cmdline_user_args()[-1]
	DirAccess.make_dir_recursive_absolute(out)
	while g.world == null or g._busy or g._intro_playing:
		g._intro_skip = true
		await process_frame
	await g.start_game(false, "knight")
	while g._busy:
		await process_frame
	g.ui.close_all()
	if g.day_night != null:
		g.day_night.fixed = 11.0      # by day
	var a: Vector2 = ForestCamp.AUCTION_AT
	var h = g.hero
	h.global_position = Vector3(a.x + 9.0, 0, a.y + 1.5)
	h._face(Vector3(-1, 0, -0.1))
	g.cam_target = h.global_position
	g.cam_pivot.position = h.global_position
	await wait(1.5)
	await shot(out, "hall")
	AuctionUI.open(g.ui, g.ui.auction_panel)
	await wait(0.6)
	await shot(out, "window")
	quit()
