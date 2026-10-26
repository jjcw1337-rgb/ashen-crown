extends SceneTree
## Demon class: all four skills, the 3-demon limit, Underworld Phase, save/load, class swap.
var g
func _initialize():
	g = (load("res://main.tscn") as PackedScene).instantiate()
	get_root().add_child(g)
	_run()
func _run() -> void:
	while g.world == null or g._busy:
		await process_frame
	await g.start_game(false, "demon")
	var h = g.hero
	print("[D] class ", h.cls, " demon rig ", h.rig.has_meta("demon"), " skills ", h.skill_list().map(func(s): return s["id"]))
	print("[D] stats str %d dex %d vit %d ene %d life %d mana %d weapon %s shield %s" % [h.str_, h.dex, h.vit, h.ene, h.max_life, h.max_mana, h.equipment["weapon"]["name"], str(h.equipment["shield"])])
	await g.travel(0, "wild", "start")
	while g._busy:
		await process_frame
	h.level = 12
	h.recalc()
	g.test_immortal = true
	var en: Array = g.enemies_near(h.global_position, 60.0)
	if en.size() > 0:
		h.global_position = en[0].global_position + Vector3(1.6, 0, 0)
	var lives := func():
		var t := 0.0
		for e in g.world.get_node("Enemies").get_children():
			t += e.life
		return t
	h.mana = h.max_mana
	var l0: float = lives.call()
	h.use_skill("hellclaw", en[0].global_position)
	await create_timer(1.0).timeout
	print("[D] hellclaw damage ", int(l0 - lives.call()))
	for i in 4:
		h.mana = h.max_mana
		h.cds["summon"] = 0.0
		var ok: bool = h.use_skill("summon", h.global_position + Vector3(0, 0, -2))
		await create_timer(0.8).timeout
		print("[D] summon #%d ok=%s minions=%d slots=%s" % [i + 1, ok, h.minions.size(), str(h.minions.map(func(m): return m.slot))])
	var alive: Array = g.enemies_near(h.global_position, 80.0)
	alive.sort_custom(func(a, b): return a.global_position.distance_to(h.global_position) < b.global_position.distance_to(h.global_position))
	if alive.size() > 0:
		h.global_position = alive[0].global_position + Vector3(3.0, 0, 0)
	await create_timer(0.5).timeout
	l0 = lives.call()
	var near: int = g.enemies_near(h.global_position, 9.0).size()
	await create_timer(2.5).timeout
	print("[D] monsters within leash: ", near, " minion targets: ", h.minions.map(func(m): return m.target != null), " rise: ", h.minions.map(func(m): return snappedf(m.rise, 0.1)))
	await create_timer(2.5).timeout
	var kills := 0
	for e in g.world.get_node("Enemies").get_children():
		if e.dead: kills += 1
	print("[D] minions fighting: damage in 5s ", int(l0 - lives.call()), " kills so far ", kills)
	g.test_immortal = false
	h.mana = h.max_mana
	h.use_skill("phase", h.global_position)
	await create_timer(0.8).timeout
	var lf: float = h.life
	h.take_hit(50.0, h.global_position + Vector3(1, 0, 0))
	var aggro := 0
	for e in g.enemies_near(h.global_position, 15.0):
		if e.aggro: aggro += 1
	print("[D] phased=", h.phased, " underworld=", snappedf(g.underworld, 0.01), " under_amt global=", RenderingServer.global_shader_parameter_get("under_amt"), " hit taken=", h.life < lf, " aggro monsters=", aggro)
	await create_timer(6.0).timeout
	print("[D] after phase: phased=", h.phased, " underworld=", snappedf(g.underworld, 0.01))
	g.test_immortal = true
	h.mana = h.max_mana
	var lf2: float = h.life
	h.use_skill("pact", h.global_position)
	await create_timer(0.9).timeout
	print("[D] pact: life paid=", int(lf2 - h.life), " buff=", snappedf(h.buff_t, 0.1), " empowered minions=", h.minions.filter(func(m): return m.empowered > 0.0).size())
	g.save_game()
	await g.travel(0, "town", "start")
	while g._busy:
		await process_frame
	await create_timer(1.0).timeout
	print("[D] after travel: minions kept=", h.minions.filter(func(m): return is_instance_valid(m)).size(), " near hero=", h.minions.filter(func(m): return is_instance_valid(m) and m.global_position.distance_to(h.global_position) < 6.0).size())
	h.set_class("knight")
	print("[D] switched to knight: minions=", h.minions.size(), " slots ", g.ui.skill_slots.map(func(s): return (s.get_node("glyph") as Control).get("id")))
	g.load_game()
	print("[D] after load: class ", h.cls, " demon rig ", h.rig.has_meta("demon"), " net class ", h.net_gear().get("_cls"))
	quit()
