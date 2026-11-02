extends SceneTree
## The Battlegrounds floors from the game camera (bg_floors.gd): builds the raid map offline, prints its size, its
## bosses, stairs and portals, and saves the Ossuary, both lower floors' arrivals and their boss halls.
##   godot --path . --resolution 1600x900 -s tools/bg_floors_shots.gd -- <out prefix>
var g
func _initialize():
	g = (load("res://main.tscn") as PackedScene).instantiate()
	get_root().add_child(g)
	_run()
func shot(p: String, at: Vector3, wait := 1.5) -> void:
	g.hero.global_position = g.world.free_spot_near(at, 2.0)
	g.cam_target = g.hero.global_position
	g.cam_pivot.position = g.hero.global_position
	await create_timer(wait).timeout
	await RenderingServer.frame_post_draw
	get_root().get_texture().get_image().save_png(p)
func _run():
	while g.world == null or g._busy or g._intro_playing or not g.ui.title_panel.visible:
		g._intro_skip = true
		await process_frame
	var out: String = OS.get_cmdline_user_args()[0]
	await g.start_game(false, "knight")
	g.ui.close_all()
	g.test_immortal = true
	var t0 := Time.get_ticks_msec()
	await g.load_zone(0, "bg", "start")
	print("[F] bg zone built in %d ms, floor rects %d, bounds %s, enemies %d" % [Time.get_ticks_msec() - t0, g.world.floor_rects.size(), g.world.bounds, g.world.enemies_root.get_child_count()])
	var BF = load("res://scripts/bg_floors.gd")
	var kinds := {}
	for e in g.world.enemies_root.get_children():
		kinds[e.kind] = kinds.get(e.kind, 0) + 1
	print("[F] enemies ", kinds)
	var stairs: Array = g.world.interactables.filter(func(t): return t.kind == "descend")
	var gold: Array = g.world.interactables.filter(func(t): return t.kind == "chest" and t.data.get("gold", false))
	print("[F] stairs %d, golden chest %d, portals %d" % [stairs.size(), gold.size(), g.world.interactables.filter(func(t): return t.kind == "extract").size()])
	print("[F] sealed while hermit lives: ", g.chest_sealed(gold[0]) if not gold.is_empty() else "-")
	var a: Dictionary = g.world.get_meta("bg_arrive")
	var o2: Vector2 = BF.origin(2)
	var o3: Vector2 = BF.origin(3)
	for e in g.world.enemies_root.get_children():
		e.set_process(false)
	await shot(out + "_f1.png", Vector3(0, 0, 0))
	await shot(out + "_f2_arrive.png", a[2])
	await shot(out + "_f2_boss.png", Vector3(o2.x + 8, 0, o2.y + 6))
	await shot(out + "_f3_arrive.png", a[3])
	await shot(out + "_f3_grove.png", Vector3(o3.x, 0, o3.y - 6))
	await shot(out + "_f3_thornway.png", Vector3(o3.x - 42, 0, o3.y))
	quit()
