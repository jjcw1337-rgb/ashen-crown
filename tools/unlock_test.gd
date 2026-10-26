extends SceneTree
var g
func _initialize():
	g = (load("res://main.tscn") as PackedScene).instantiate()
	get_root().add_child(g)
	_run()
func wait(n: int) -> void:
	for i in n:
		await process_frame
func _run() -> void:
	await wait(30)
	while g._busy:
		await wait(5)
	await g.start_game(false)
	g.ui.close_all()
	for it in g.world.interactables:
		if it.kind == "waypoint":
			g._interact(it)
	var names := []
	for c in g.ui.wp_list.get_children():
		if c is HBoxContainer:
			for b in c.get_children():
				names.append(b.text + ("" if not b.disabled else " (off)"))
	print("[U] fresh character, camp waypoint buttons: ", names)
	g.ui.close_all()
	await g.switch_run(2)
	print("[U] switched straight to: ", g.run_name(), "  ", g.zone_title(0, "town"))
	quit()
