extends SceneTree
## The loot list (game/ui/loot_list/): holding Ctrl lists the items on the ground nearby, nearest first, none past
## its range; a click on a row sends the hero to pick that item up; releasing Ctrl hides it.
##   godot --path . --resolution 1600x900 -s tools/_late.gd -- res://game/ui/loot_list/tests/loot_list_test.gd [shot.png]
var g
var fails := 0
func _initialize():
	g = (load("res://main.tscn") as PackedScene).instantiate()
	get_root().add_child(g)
	_run()
func check(ok: bool, what: String) -> void:
	print("[LOOT] ", "ok   " if ok else "FAIL ", what)
	if not ok:
		fails += 1
func frames(n: int) -> void:
	for i in n:
		await process_frame
func ctrl(on: bool) -> void:
	var e := InputEventKey.new()
	e.keycode = KEY_CTRL
	e.physical_keycode = KEY_CTRL
	e.pressed = on
	Input.parse_input_event(e)
func _run() -> void:
	while g.world == null or g._busy:
		await process_frame
	await g.start_game(false, "knight")
	g.ui.close_all()
	await g.load_zone(0, Sandbox.ZONE, "start")      # (the Arena hall: open stone floor)
	await frames(10)
	var h = g.hero
	var hp: Vector3 = h.global_position
	var near_it := Items.make("short_sword")
	var far_it := Items.make("short_sword")
	var mid_it := Items.make("buckler") if Data.BASES.has("buckler") else Items.make("short_sword")
	g.drop_item(near_it, hp + Vector3(2.0, 0, 0))
	g.drop_item(mid_it, g.world.free_spot_near(hp + Vector3(-5.0, 0, 0), 1.5))
	g.drop_item(far_it, hp + Vector3(40.0, 0, 0))
	await frames(90)
	var ll: LootList = g.ui.loot_list
	check(ll != null and not ll.visible, "hidden without Ctrl")
	ctrl(true)
	await frames(30)
	check(ll.visible, "Ctrl shows it")
	var items: Array = ll.nearby()
	check(items.size() >= 2 and (items[0].global_position - hp).length() < (items[1].global_position - hp).length(), "nearest first (%d listed)" % items.size())
	var far_g = g.world.items_root.get_children().filter(func(x): return x is GroundItem and is_same(x.item, far_it))
	var far_d: float = (far_g[0].global_position - hp).length() if not far_g.is_empty() else 999.0
	check(far_d > LootList.RANGE and not items.any(func(x): return is_same(x.item, far_it)), "nothing past its range (the far one at %.0f m)" % far_d)
	var row: Button = null
	for b in ll.rows.get_children():
		if b is Button and b.has_meta("item") and is_same(b.get_meta("item").item, mid_it):
			row = b
	check(row != null and row.text.contains("m"), "a row per item, with its distance (%s)" % (row.text if row else "-"))
	if OS.get_cmdline_user_args().size() > 1:
		await RenderingServer.frame_post_draw
		get_root().get_texture().get_image().save_png(OS.get_cmdline_user_args()[-1])
	var before: int = g.world.items_root.get_children().filter(func(x): return x is GroundItem).size()
	if row:
		row.pressed.emit()
	ctrl(false)
	await frames(400)
	var after: int = g.world.items_root.get_children().filter(func(x): return x is GroundItem).size()
	check(not g.world.items_root.get_children().any(func(x): return x is GroundItem and is_same(x.item, mid_it)), "a click: the hero walks over and picks it up (%d -> %d on the ground)" % [before, after])
	check(not ll.visible, "released: hidden")
	print("[LOOT] done, %d failed" % fails)
	quit()
