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
	g.ui.toggle(g.ui.inv_panel)
	var h = g.hero
	h.inventory[0] = Items.make_unique("emberfang")
	h.inventory[1] = Items.make("buckler")
	h.inventory[2] = Items.make("cap")
	g.ui.refresh()
	g.ui.click_fx(g.ui.inv_cells[0])
	await wait(30)
	var n0: int = g.world.items_root.get_child_count()
	g.ui.drag_idx = 0
	g.ui._start_drag(0)
	g.ui._finish_drag(["ground", null])
	await wait(60)
	var on_ground := false
	for gi in g.world.items_root.get_children():
		if gi is GroundItem and gi.item.get("unique", "") == "emberfang":
			on_ground = true
	print("[1] dragged Emberfang onto the ground: in bag=", h.inventory[0] != null, " on ground=", on_ground)
	g.ui.drag_idx = 1
	g.ui._start_drag(1)
	g.ui._finish_drag(["inv", 7])
	print("[2] dragged buckler to slot 8: slot2 empty=", h.inventory[1] == null, " slot8=", h.inventory[7]["name"] if h.inventory[7] else "none")
	g.ui.drag_idx = 2
	g.ui._start_drag(2)
	g.ui._finish_drag(["equip", "helm"])
	print("[3] dragged cap onto equipment: wearing helm=", h.equipment["helm"]["name"] if h.equipment["helm"] else "none")
	g.ui.drag_idx = 7
	g.ui._start_drag(7)
	g.ui._finish_drag(["ui", null])
	print("[4] dropped on a panel = cancelled, buckler still in slot 8: ", h.inventory[7] != null)
	quit()
