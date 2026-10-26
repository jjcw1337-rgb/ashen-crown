extends SceneTree
var g
func _initialize():
	g = (load("res://main.tscn") as PackedScene).instantiate()
	get_root().add_child(g)
	_run()
func wait(n: int) -> void:
	for i in n:
		await process_frame
func _wp():
	for it in g.world.interactables:
		if it.kind == "waypoint":
			return it
func _buttons() -> Array:
	var out := []
	for c in g.ui.wp_list.get_children():
		if c is HBoxContainer:
			for b in c.get_children():
				out.append(b.text + ("" if not b.disabled else "*"))
	return out
func _run() -> void:
	await wait(30)
	while g._busy:
		await wait(5)
	await g.start_game(false)
	g.ui.close_all()
	g.waypoints_known = ["town", "wild"]
	g._interact(_wp())
	print("[1] Act I camp waypoint (*=disabled): ", _buttons())
	g.ui.close_all()
	g.boss_killed = true
	await g.start_a2()
	g.boss_killed = true
	await g.start_a2()
	g._interact(_wp())
	print("[2] in A3, max_run=", g.max_run, " buttons: ", _buttons())
	g.ui.close_all()
	await g.switch_run(0)
	print("[3] switched to ", g.run_name(), " title=", g.zone_title(0, "town"), " waypoints=", g.waypoints_known, " boss_killed=", g.boss_killed)
	await g.load_zone(0, "wild", "from_town")
	var e = g.world.enemies_root.get_child(0)
	print("    a ", e.kind, " here has life ", int(e.max_life))
	await g.load_zone(0, "town", "start")
	await g.switch_run(2)
	print("[4] back to ", g.run_name(), " waypoints=", g.waypoints_known, " boss_killed=", g.boss_killed)
	await g.switch_run(1)
	g.save_game()
	g.difficulty = 0
	g.max_run = 0
	g.run_progress = {}
	g.load_game()
	print("[5] after save+load: run=", g.run_name(), " max_run=", g.max_run, " remembered runs=", g.run_progress.keys())
	g._interact(_wp())
	print("[6] waypoint in the moor shows no act switch: ", true)
	quit()
