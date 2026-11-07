extends SceneTree
## Waypoint rules: Act I is the only act; an untouched waypoint can't be taken; a touched one travels, arriving
## by its own stone; the window closes when you walk away from the stone.
## godot --headless --path . -s game/maps/camp/tests/waypoint_test.gd
var g
var fails := 0
func ok(cond: bool, what: String) -> void:
	print("[W] ", "ok   " if cond else "FAIL ", what)
	if not cond:
		fails += 1

func _initialize():
	g = (load("res://main.tscn") as PackedScene).instantiate()
	get_root().add_child(g)
	_run()

func _settle() -> void:
	for f in 4:
		await process_frame
	while g._busy:
		await process_frame

func _run() -> void:
	while g.world == null or g._busy or g._intro_playing:
		await process_frame
	var errs: Array = Data.check_waypoints()
	ok(errs.is_empty(), "Data.WAYPOINT_ACTS checks out " + str(errs))
	await g.start_game(false, "knight")
	await _settle()
	g.waypoints_known = ["town"]
	ok(Data.WAYPOINT_ACTS.size() == 1 and g.act_unlocked(0) and not g.act_unlocked(1), "Act I is the only act, and open")
	ok(g.waypoint_known(0, "town") and not g.waypoint_known(0, "nowhere"), "the camp waypoint is known, an untouched one is not")
	g.waypoint_go(0, "nowhere")
	await _settle()
	ok(g.cur_zone == "town" and not g._busy, "an untouched waypoint can't be taken (still in %s)" % g.cur_zone)
	g.waypoint_go(1, "town")
	await _settle()
	ok(g.difficulty == 0 and g.cur_zone == "town", "no other act to enter")
	var home = null
	for it in g.world.interactables:
		if is_instance_valid(it) and it.kind == "waypoint":
			home = it
	g.hero.global_position = g.world.free_spot_near(home.global_position + Vector3(0, 0, 14), 1.0) if home != null else g.hero.global_position
	g.waypoint_go(0, "town")
	await _settle()
	var ws = null
	for it in g.world.interactables:
		if is_instance_valid(it) and it.kind == "waypoint":
			ws = it
	ok(g.cur_zone == "town" and ws != null and g.hero.global_position.distance_to(ws.global_position) < 5.0, "a touched waypoint travels there, arriving beside its own stone")
	ok(g.world.spawns.has("waypoint_town"), "each stone registers its own arrival spot")
	# the window: opened from the stone, closes when the hero walks off
	var stone = null
	for it in g.world.interactables:
		if is_instance_valid(it) and it.kind == "waypoint":
			stone = it
	ok(stone != null, "the camp has a waypoint stone")
	if stone:
		g.hero.global_position = stone.global_position + Vector3(2, 0, 0)
		g.ui.open_waypoints(stone)
		await process_frame
		ok(g.ui.wp_panel.visible, "the window opens at the stone")
		g.hero.global_position = stone.global_position + Vector3(9, 0, 0)
		for f in 3:
			await process_frame
		ok(not g.ui.wp_panel.visible, "walking away closes it")
		g.hero.global_position = stone.global_position + Vector3(2, 0, 0)
		g.ui.open_waypoints(stone)
		await process_frame
		var cover: Control = g.ui.wp_panel.cover
		var ev := InputEventMouseButton.new()
		ev.button_index = MOUSE_BUTTON_LEFT
		ev.pressed = true
		cover.gui_input.emit(ev)
		await process_frame
		ok(not g.ui.wp_panel.visible, "clicking off the window closes it")
	print("[W] done, %d failed" % fails)
	quit(1 if fails > 0 else 0)
