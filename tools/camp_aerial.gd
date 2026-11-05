extends SceneTree
## A high three-quarter view over the whole Act I camp (the palisade ring, the waypoint, the shops), by day, for concept
## paintovers. Needs a display.
##   godot --path . --resolution 1920x1080 -s tools/_late.gd -- res://tools/camp_aerial.gd out.png [height 38] [hour 11]

var g

func _initialize():
	g = (load("res://main.tscn") as PackedScene).instantiate()
	get_root().add_child(g)
	_run()

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var out: String = args[1] if args.size() > 1 else "/tmp/camp_aerial.png"
	var hgt: float = float(args[2]) if args.size() > 2 else 38.0
	while g.world == null or g._busy or g._intro_playing:
		g._intro_skip = true
		await process_frame
	await g.start_game(false, "knight")
	while g._busy:
		await process_frame
	g.ui.close_all()
	g.ui.visible = false
	if g.day_night != null:
		g.day_night.fixed = float(args[3]) if args.size() > 3 else 11.0
	var cam := Camera3D.new()
	cam.fov = 50
	cam.far = 600.0
	get_root().add_child(cam)
	cam.current = true
	var at := Vector3(ForestCamp.CENTER.x, 0, ForestCamp.CENTER.y)
	cam.global_transform = Transform3D(Basis(), at + Vector3(0, hgt, hgt * 1.05)).looking_at(at + Vector3(0, 0, -4), Vector3.UP)
	if args.size() > 4 and args[4] == "edge":
		# from out in the void, level with the cliff: the underside, the roots, the falls
		cam.global_transform = Transform3D(Basis(), at + Vector3(18, 6, 78)).looking_at(at + Vector3(0, -14, 20), Vector3.UP)
	if args.size() > 4 and args[4] == "game":
		# the game's own camera zoomed right out (Game.CAM_OFFSET x 2.2) from the south of the square
		cam.fov = 40
		var hp := at + Vector3(0, 0, 14)
		cam.global_transform = Transform3D(Basis(), hp + Vector3(0, 17.0, 16.5) * 2.2).looking_at(hp, Vector3.UP)
	if args.size() > 4 and args[4].begins_with("at:"):
		# the game's camera at zoom 1 over a spot: at:x,z
		var xz := args[4].substr(3).split(",")
		var hp2 := Vector3(float(xz[0]), 0, float(xz[1]))
		g.hero.global_position = hp2 + Vector3(0, 0, 3)
		cam.fov = 40
		cam.global_transform = Transform3D(Basis(), hp2 + Vector3(0, 17.0, 16.5)).looking_at(hp2, Vector3.UP)
	if args.has("nounder"):
		var isl = g.world.get_node_or_null("island")
		for c in isl.get_children():
			if c.name == "underside":
				c.visible = false
	for i in 40:
		await process_frame
	await RenderingServer.frame_post_draw
	get_root().get_texture().get_image().save_png(out)
	print("[CA] ", out)
	quit()
