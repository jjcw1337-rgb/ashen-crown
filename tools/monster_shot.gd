extends SceneTree
## Stages monsters next to the hero on the moor and grabs a strip of frames as they close in and
## attack (the hero is immortal). Usage: -- out.png kind [kind ...]   e.g. -- z.png zombie zombie fallen
var g
func _initialize():
	g = (load("res://main.tscn") as PackedScene).instantiate()
	get_root().add_child(g)
	_run()
func _run() -> void:
	var args := OS.get_cmdline_user_args()
	while g.world == null or g._busy:
		g._intro_skip = true
		await process_frame
	await g.start_game(false, "knight")
	g.ui.close_all()
	await g.load_zone(0, "wild", "road")
	g.ui.close_all()
	g.test_immortal = true
	g.zoom = 0.6
	var h = g.hero
	for e in g.enemies_near(h.global_position, 40.0):
		e.queue_free()
	await process_frame
	var kinds: Array = args.slice(1)
	for i in kinds.size():
		var a := TAU * i / kinds.size() + 0.4
		var p: Vector3 = g.world.free_spot_near(h.global_position + Vector3(cos(a), 0, sin(a)) * 4.5, 0.6)
		var e = g.spawn_enemy(kinds[i], p, 1)
		e.aggro = true
	var cols := 5
	var cell := Vector2i(560, 400)
	var sheet := Image.create(cell.x * cols, cell.y, false, Image.FORMAT_RGBA8)
	for c in cols:
		await create_timer(0.55).timeout
		await RenderingServer.frame_post_draw
		var img := get_root().get_texture().get_image()
		var w := img.get_width()
		var hh := img.get_height()
		img = img.get_region(Rect2i(w / 2 - 420, hh / 2 - 330, 840, 600))
		img.resize(cell.x, cell.y)
		img.convert(Image.FORMAT_RGBA8)
		sheet.blit_rect(img, Rect2i(Vector2i.ZERO, cell), Vector2i(c * cell.x, 0))
	sheet.save_png(args[0])
	print("saved")
	quit()
