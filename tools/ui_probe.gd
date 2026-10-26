extends SceneTree
var g
func _initialize():
	g = (load("res://main.tscn") as PackedScene).instantiate()
	get_root().add_child(g)
	_run()
func wait(n: int) -> void:
	for i in n:
		await process_frame
func _walk(n: Node, out: Array) -> void:
	if n is Control and (n as Control).is_visible_in_tree():
		var r: Rect2 = (n as Control).get_global_rect()
		if r.has_point(Vector2(550, 300)):
			out.append("%s %s %s" % [n.get_path(), n.get_class(), r])
	for c in n.get_children():
		_walk(c, out)
func _run() -> void:
	await wait(30)
	while g._busy:
		await wait(5)
	await g.start_game(false)
	g.ui.close_all()
	g.ui.toggle(g.ui.inv_panel)
	await wait(5)
	var out := []
	_walk(get_root(), out)
	for o in out:
		print("[P] ", o)
	quit()
