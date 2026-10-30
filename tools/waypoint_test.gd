extends SceneTree
## Waypoint network rules: sealed acts and untouched waypoints can't be taken; taken ones travel
## (same act and across acts); the window closes when you walk away from the stone.
## godot --headless --path . -s tools/waypoint_test.gd
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
	await g.start_game(false, "knight")
	await _settle()
	g.max_run = 0
	g.waypoints_known = ["town"]
	g.run_progress = {}
	ok(g.act_unlocked(0) and not g.act_unlocked(1), "only Act I is open at the start")
	ok(g.waypoint_known(0, "town") and not g.waypoint_known(0, "wild"), "the camp waypoint is known, the moor's is not")
	g.waypoint_go(0, "wild")
	await _settle()
	ok(g.cur_zone == "town", "an untouched waypoint can't be taken (still in %s)" % g.cur_zone)
	g.waypoint_go(1, "town")
	await _settle()
	ok(g.difficulty == 0, "a sealed act can't be entered")
	g.waypoints_known.append("wild")
	g.waypoint_go(0, "wild")
	await _settle()
	ok(g.cur_zone == "wild", "a touched waypoint travels there (now in %s)" % g.cur_zone)
	g.max_run = 1
	g.waypoint_go(1, "town")
	await _settle()
	ok(g.difficulty == 1 and g.cur_zone == "town", "an open act: switched to %s, %s" % [g.run_name(), g.cur_zone])
	ok(g.waypoint_known(0, "wild"), "Act I keeps its moor waypoint after leaving")
	g.waypoint_go(0, "wild")
	await _settle()
	ok(g.difficulty == 0 and g.cur_zone == "wild", "back across acts straight to Act I's moor waypoint")
	# the window: opened from the stone, closes when the hero walks off
	var stone = null
	for it in g.world.interactables:
		if is_instance_valid(it) and it.kind == "waypoint":
			stone = it
	ok(stone != null, "the moor has a waypoint stone")
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
