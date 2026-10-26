extends SceneTree
## Wraith class: new game, all four skills, spirits, save/load keeps the class, knight still works.
var g
func _initialize():
	g = (load("res://main.tscn") as PackedScene).instantiate()
	get_root().add_child(g)
	_run()
func wait(n: int) -> void:
	for i in n:
		await process_frame
func _run() -> void:
	while g.world == null or g._busy:
		await process_frame
	await g.start_game(false, "wraith")
	var h = g.hero
	print("[W] class ", h.cls, " wraith rig ", h.rig.has_meta("wraith"), " skills ", h.skill_list().map(func(s): return s["id"]))
	print("[W] stats str %d dex %d vit %d ene %d life %d mana %d shield %s" % [h.str_, h.dex, h.vit, h.ene, h.max_life, h.max_mana, str(h.equipment["shield"])])
	print("[W] ui slots ", g.ui.skill_slots.map(func(s): return (s.get_node("glyph") as Control).get("id")))
	await g.travel(0, "wild", "start")
	while g._busy:
		await process_frame
	h.level = 12
	h.recalc()
	h.mana = h.max_mana
	g.test_immortal = true
	var en: Array = g.enemies_near(h.global_position, 60.0)
	print("[W] enemies near: ", en.size())
	if en.size() > 0:
		h.global_position = en[0].global_position + Vector3(1.5, 0, 0)
	for id in ["reap", "wail", "shade", "host"]:
		h.mana = h.max_mana
		var aim: Vector3 = en[0].global_position if en.size() > 0 else h.global_position + Vector3(3, 0, 0)
		var lives := 0.0
		for e in en: lives += e.life
		var ok: bool = h.use_skill(id, aim)
		await create_timer(1.0).timeout
		var lives2 := 0.0
		for e in en: lives2 += e.life if is_instance_valid(e) else 0.0
		print("[W]   damage dealt by ", id, ": ", int(lives - lives2))
		print("[W] cast ", id, " ok=", ok, " cd=", snappedf(h.cds[id], 0.1), " spirits=", h.spirits.size(), " buff=", snappedf(h.buff_t, 0.1))
	await create_timer(4.0).timeout
	var dead := 0
	for e in g.world.get_node("Enemies").get_children():
		if e.dead: dead += 1
	print("[W] enemies killed so far: ", dead, " spirits ", h.spirits.size(), " hover y ", snappedf(h.rig.position.y, 0.01))
	g.save_game()
	h.set_class("knight")
	print("[W] switched to knight: rig wraith? ", h.rig.has_meta("wraith"), " slots ", g.ui.skill_slots.map(func(s): return (s.get_node("glyph") as Control).get("id")))
	g.load_game()
	print("[W] after load class ", h.cls, " rig wraith ", h.rig.has_meta("wraith"))
	await g.start_game(false, "knight")
	print("[W] new knight: ", h.cls, " lvl ", h.level, " str ", h.str_, " shield ", h.equipment["shield"] != null)
	quit()
