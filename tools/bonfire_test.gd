extends SceneTree
## The camp's bonfire (UI.open_burn): clicking it opens the fire beside the inventory; right-clicking an item
## (or dragging it onto the flames) burns it for good with its sound; anything rare asks first; walking
## away closes it. And a click on an inventory item plays its pick-up sound. Prints [F] lines.
var g
var fails := 0

func _initialize():
	g = (load("res://main.tscn") as PackedScene).instantiate()
	get_root().add_child(g)
	_run()

func check(ok: bool, what: String) -> void:
	if not ok:
		fails += 1
	print("[F] %s %s" % ["ok  " if ok else "FAIL", what])

func _run() -> void:
	while g.world == null or g._busy:
		g._intro_skip = true
		await process_frame
	await g.start_game(false, "knight")
	g.ui.close_all()
	var sfx = get_root().get_node("Sfx")
	var fire: Inter = null
	for t in g.world.interactables:
		if t.kind == "bonfire":
			fire = t
	check(fire != null, "the camp's bonfire can be clicked")
	if fire == null:
		quit()
		return
	g.hero.global_position = fire.global_position + Vector3(0, 0, fire.radius + 0.5)
	g._interact(fire)
	await process_frame
	check(g.ui.burn_panel.visible and g.ui.inv_panel.visible and g.ui.shop_mode == "burn", "it opens the fire beside the inventory")
	# a plain item: right-click burns it at once
	g.hero.inventory[0] = Items.make("short_sword", 0, 1)
	var n0: int = int(sfx.counts.get("burn_item", 0))
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_RIGHT
	ev.pressed = true
	g.ui._inv_click(0, ev)
	await process_frame
	check(g.hero.inventory[0] == null and int(sfx.counts.get("burn_item", 0)) == n0 + 1, "right-click: it burns, with its sound")
	# dragged onto the flames
	g.hero.inventory[1] = Items.make("club", 0, 1)
	g.ui.drag_idx = 1
	g.ui._finish_drag(["fire", null])
	await process_frame
	check(g.hero.inventory[1] == null, "dragged onto the fire: it burns")
	# a rare one asks first; Keep keeps it, Burn burns it
	var rare := Items.generate("broad_sword", 10, 2, RandomNumberGenerator.new())
	g.hero.inventory[2] = rare
	g.ui._inv_click(2, ev)
	await process_frame
	var asked: bool = g.ui.dialog_panel.visible and g.hero.inventory[2] == rare
	var keep: Button = null
	for b in g.ui.dialog_btns.get_children():
		if b is Button and (b as Button).text == "Keep it":
			keep = b
	if keep:
		keep.pressed.emit()
	await process_frame
	var kept: bool = g.hero.inventory[2] == rare
	g.ui._inv_click(2, ev)
	await process_frame
	for b in g.ui.dialog_btns.get_children():
		if b is Button and (b as Button).text == "Burn it":
			(b as Button).pressed.emit()
	await process_frame
	check(asked and kept and g.hero.inventory[2] == null, "a rare one asks first (Keep keeps it, Burn burns it)")
	# a click on an inventory item: its pick-up sound
	g.hero.inventory[3] = Items.make("short_sword", 0, 1)
	var c0: int = int(sfx.counts.get("inv_click", 0))
	var lev := InputEventMouseButton.new()
	lev.button_index = MOUSE_BUTTON_LEFT
	lev.pressed = true
	g.ui._inv_click(3, lev)
	await process_frame
	g.ui.drag_idx = -1
	check(int(sfx.counts.get("inv_click", 0)) == c0 + 1, "clicking an item in the inventory plays its sound")
	# walking away closes the fire
	g.ui.open_burn()
	g.ui.trade_with = fire
	g.hero.global_position = fire.global_position + Vector3(0, 0, fire.radius + 6.0)
	for i in 3:
		await process_frame
	check(not g.ui.burn_panel.visible, "walking away closes it")
	print("[F] done, %d failed" % fails)
	quit()
