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
	await g.load_zone(0, "wild", "from_town")
	var e1 = g.world.enemies_root.get_child(0)
	var a1 := [e1.kind, e1.max_life, e1.dmg[1], e1.armor, e1.xp]
	var lvl0: int = g.hero.level
	g.boss_killed = true
	g.ui.show_victory(0)
	await g.start_a2()
	print("[A] after A2 start: zone=", g.cur_zone, " title=", g.zone_title(0, "town"), " waypoints=", g.waypoints_known, " boss_killed=", g.boss_killed, " victory hidden=", not g.ui.victory_panel.visible, " level kept=", g.hero.level == lvl0)
	await g.load_zone(0, "wild", "from_town")
	var e2 = null
	for e in g.world.enemies_root.get_children():
		if e.kind == a1[0]:
			e2 = e
			break
	print("[B] ", a1[0], " Act I life/dmg/armor/xp=", a1.slice(1), "  A2=", [e2.max_life, e2.dmg[1], e2.armor, e2.xp])
	var r := RandomNumberGenerator.new()
	r.seed = 3
	var it := Items.generate("broad_sword", 10, 1, r)
	var before := [Items.damage_of(it), it["affixes"]]
	var it2 := Items.empower(it.duplicate(true), 5.0)
	print("[C] sword before=", before, " after=", [Items.damage_of(it2), it2["affixes"]], " tooltip line=", Items.tooltip(it2)[2][0])
	var n0: int = g.world.items_root.get_child_count()
	for i in 40:
		g._drop_loot_roll(g.hero.global_position, 10, true)
	var powered := 0
	var total := 0
	for gi in g.world.items_root.get_children():
		if gi is GroundItem and Data.BASES[gi.item["base"]]["slot"] not in ["gold", "potion"]:
			total += 1
			if float(gi.item.get("power", 1.0)) == 5.0:
				powered += 1
	print("[D] A2 drops with x5 stats: ", powered, "/", total)
	g.save_game()
	g.difficulty = 0
	g.load_game()
	print("[E] difficulty saved+loaded=", g.difficulty)
	quit()
