extends SceneTree
## The camp's traders: names, the smith working inside his forge (his clips pinned, so he never
## strides out of it), nameplates over the vendors, the trade window headed by the trader (portrait,
## tabs, priced goods, buying from a tab), and walking away closing it. Prints [V] lines.
var g
var fails := 0

func _initialize():
	g = (load("res://main.tscn") as PackedScene).instantiate()
	get_root().add_child(g)
	_run()

func check(ok: bool, what: String) -> void:
	if not ok:
		fails += 1
	print("[V] %s %s" % ["ok  " if ok else "FAIL", what])

func _vendor(role: String) -> Inter:
	for it in g.world.interactables:
		if it.kind == "vendor" and it.data.get("role", "") == role:
			return it
	return null

func _run() -> void:
	while g.world == null or g._busy:
		g._intro_skip = true
		await process_frame
	await g.start_game(false, "knight")
	while g._busy:
		await process_frame
	check(g.zone_title(0, "town") == "The Forsaken Wilds", "the camp is " + g.zone_title(0, "town"))
	var smith := _vendor("smith")
	var alch := _vendor("alch")
	check(smith.label == "Halvar Emberhammer" and alch.label == "Agnes Grimwood", "the smith %s, the alchemist %s" % [smith.label, alch.label])
	# inside his forge, behind the anvil, and he stays there through his work
	var sh: Dictionary = ForestCamp.SHOPS[1]
	var at: Vector2 = sh["at"]
	var din: float = Vector2(smith.global_position.x, smith.global_position.z).distance_to(at)
	check(din < (sh["half"] as Vector2).y * ForestCamp.STALL_SCALE * 0.6, "the smith stands inside his forge (%.2f m from its centre)" % din)
	var sk: Skeleton3D = smith.model.find_child("Skeleton3D", true, false)
	var hips := sk.find_bone("Hips")
	var far := 0.0
	var played := {}
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 14000:
		await process_frame
		played[smith.anim.current_animation] = true
		var hp: Vector3 = sk.global_transform * sk.get_bone_global_pose(hips).origin
		far = maxf(far, Vector2(hp.x - smith.global_position.x, hp.z - smith.global_position.z).length())
	check(far < 0.6 and played.has("Heavy_Hammer_Swing") and not played.has("Catching_Breath"), "he hammers at the anvil, never wandering out (hips at most %.2f m off, clips %s)" % [far, played.keys()])
	# nameplates over the vendors
	g.hero.global_position = g.world.free_spot_near(smith.global_position + Vector3(sin(smith.home_yaw), 0, cos(smith.home_yaw)) * 4.0, 0.4)
	await process_frame
	await process_frame
	var plate = g.ui.plates.plates.get(smith)
	check(plate != null and plate.visible and plate.mouse_filter == Control.MOUSE_FILTER_IGNORE, "a click-through nameplate over the smith")
	# trade: click him from across the camp (the hero walks to his stall's front and talks), then Trade
	g.hero.global_position = g.world.free_spot_near(smith.global_position + Vector3(sin(smith.home_yaw), 0, cos(smith.home_yaw)) * 10.0, 0.4)
	g.ui.close_all()           # Captain Roth's welcome
	g.hero.cmd_target(smith)
	var t2 := Time.get_ticks_msec()
	while not (g.ui.dialog_panel.visible and g.ui.dialog_name.text == smith.label) and Time.get_ticks_msec() - t2 < 8000:
		await process_frame
	check(g.ui.dialog_panel.visible, "clicked from 10 m off, the hero reaches him behind his anvil and he talks")
	for b in g.ui.dialog_btns.get_children():
		if b is Button and (b as Button).text == "Trade":
			(b as Button).pressed.emit()
	await process_frame
	var ui = g.ui
	check(ui.shop_panel.visible and ui.shop_who.text == smith.label and ui.shop_role.text == "BLACKSMITH", "the trade window is headed by %s (%s)" % [ui.shop_who.text, ui.shop_role.text])
	check(ui.shop_face.get_child_count() == 1 and ui.shop_face.get_child(0) is VendorUI.Portrait, "with his portrait")
	var tabs: Array = ui.shop_tabs.get_children().map(func(b): return b.text)
	check(tabs.size() >= 3 and tabs[0] == "All", "tabs %s" % [tabs])
	var cell: Panel = ui.shop_grid.get_child(0)
	check((cell.get_node("price") as Label).text.ends_with(" g"), "goods are priced (%s)" % (cell.get_node("price") as Label).text)
	# a tab shows only its kind, and buying from it buys what's shown
	var tab: String = tabs[2]
	for b in ui.shop_tabs.get_children():
		if b.text == tab:
			b.pressed.emit()
	await process_frame
	var kinds := {}
	for i in ui.shop_view:
		kinds[ui.shop_kind(ui.shop_items[i])] = true
	check(kinds.keys() == [tab], "the %s tab shows only %s" % [tab, kinds.keys()])
	g.hero.gold = 100000
	var want: Dictionary = ui.shop_items[ui.shop_view[0]]
	ui._buy(0)
	var got = g.hero.inventory.filter(func(x): return x != null and x["name"] == want["name"])
	check(not got.is_empty(), "bought %s from the %s tab" % [want["name"], tab])
	# walk away: the trade closes
	g.hero.cmd_move(g.hero.global_position + Vector3(sin(smith.home_yaw), 0, cos(smith.home_yaw)) * 10.0)
	var t1 := Time.get_ticks_msec()
	while ui.shop_panel.visible and Time.get_ticks_msec() - t1 < 5000:
		await process_frame
	var d: float = g.hero.global_position.distance_to(smith.global_position)
	check(not ui.shop_panel.visible and not ui.inv_panel.visible, "walking away (%.1f m) closes the trade" % d)
	# and the stash's window closes the same way
	var chest: Inter = null
	for it in g.world.interactables:
		if it.kind == "stash":
			chest = it
	g.hero.global_position = g.world.free_spot_near(chest.global_position + Vector3(0, 0, 2.0), 0.4)
	g._interact(chest)
	await process_frame
	g.hero.global_position = chest.global_position + Vector3(0, 0, 9.0)
	await process_frame
	await process_frame
	check(not ui.stash_panel.visible, "stepping away from the stash closes it")
	print("[V] done, %d failed" % fails)
	quit()
