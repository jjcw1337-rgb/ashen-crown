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
	g.boss_killed = true
	await g.start_a2()
	print("[1] after first finish: run=", g.run_name(), " title=", g.zone_title(0, "town"))
	g.boss_killed = true
	g.ui.show_victory(g.difficulty)
	print("[2] A2 victory button: ", (g.ui.victory_panel.find_child("a2btn", true, false) as Button).text)
	await g.start_a2()
	print("[3] after A2 finish: run=", g.run_name(), " title=", g.zone_title(0, "wild"), " waypoints=", g.waypoints_known)
	await g.load_zone(0, "lair", "start")
	var boss = null
	for e in g.world.enemies_root.get_children():
		if e.boss:
			boss = e
	print("[4] crypt: ", g.zone_title(0, "lair"), "  boss=", boss.display_name, " life=", int(boss.max_life), " hit=", int(boss.dmg[1]), " scale=", boss.rig.scale.x)
	var n0: int = g.world.items_root.get_child_count()
	boss.take_damage(1e9, 0.0, boss.global_position + Vector3(0, 0, 3), 0.0, false)
	await wait(10)
	var sword = null
	for gi in g.world.items_root.get_children():
		if gi is GroundItem and gi.item.get("unique", "") == "cinderbrand":
			sword = gi.item
	print("[5] boss dead=", boss.dead, " Cinderbrand dropped=", sword != null)
	if sword:
		print("    ", Items.tooltip(sword).slice(0, 12).map(func(l): return l[0]))
	var tt := Time.get_ticks_msec()
	while Time.get_ticks_msec() - tt < 4500:
		await wait(1)
	print("[6] victory: ", (g.ui.victory_panel.find_child("vtitle", true, false) as Label).text, " / ", (g.ui.victory_panel.find_child("a2btn", true, false) as Button).text)
	g.hero.equipment["weapon"] = sword
	g.hero.recalc()
	print("[6b] with Cinderbrand: attack speed x", snappedf(g.hero.aspd, 0.01), " life steal ", g.hero.ls, "%")
	await g.start_a2()
	print("[7] replay stays A3: ", g.run_name())
	var r := RandomNumberGenerator.new()
	var cnt := 0
	for i in 400:
		var it := Items.random_drop(30, 500, r, true)
		if it.get("unique", "") == "cinderbrand":
			cnt += 1
	print("[8] Cinderbrand from random drops (should be 0): ", cnt)
	quit()
