extends SceneTree
## The Hollow Matron: Mourners, the heart's flight and shuffle, hollow damage, a wrong
## Mourner's wail, crushing the heart (exposed), the next cycle, the phase floors, and cleanup
## on her death.
var g
func _initialize():
	g = (load("res://main.tscn") as PackedScene).instantiate()
	get_root().add_child(g)
	_run()
func wait(s: float) -> void:
	await create_timer(s).timeout
func _run() -> void:
	while g.world == null or g._busy:
		await process_frame
	await g.start_game(false, "knight")
	g.ui.close_all()
	await g.load_zone(0, "lair", "start")
	var h = g.hero
	h.level = 10
	h.recalc()
	g.test_immortal = true
	var boss = null
	for e in g.world.enemies_root.get_children():
		if e is Enemy and e.boss:
			boss = e
	for e in g.enemies_near(boss.global_position, 18.0):
		if not e.boss:
			e.queue_free()
	var hm: Matron = boss.heart
	print("[M] boss %s has a heart: %s" % [boss.kind, hm != null])
	h.global_position = g.world.free_spot_near(boss.global_position + Vector3(0, 0, 4.0), 1.0)
	await wait(0.6)
	print("[M] aggro %s state %s mourners %d" % [boss.aggro, hm.state, hm.mourners.size()])
	await wait(2.0)
	print("[M] after the rip: state %s carrier %s" % [hm.state, hm.carrier != null])
	var carrier: Enemy = hm.carrier
	await wait(5.0)
	print("[M] after the shuffle: state %s, carrier beating %s, others silent %s" % [hm.state, carrier.beat == "on", hm.mourners.filter(func(m): return m != carrier and m.beat != "").is_empty()])
	# hollow: a hit does a quarter
	var l0: float = boss.life
	var dealt: float = boss.take_damage(100.0, 0.0, h.global_position, 0.0, false)
	print("[M] hollow hit: dealt %.1f of %.1f (taken %.2f)" % [dealt, 100.0 * 100.0 / (100.0 + boss.armor * 0.6), boss.taken])
	# a wrong Mourner wails and raises a zombie
	var zombies0: int = g.world.enemies_root.get_children().filter(func(e): return e is Enemy and e.kind == "zombie" and not e.dead).size()
	var wrong: Enemy = hm.mourners.filter(func(m): return m != carrier)[0]
	wrong.take_damage(99999.0, 0.0, h.global_position, 0.0, false)
	await wait(0.2)
	var zombies1: int = g.world.enemies_root.get_children().filter(func(e): return e is Enemy and e.kind == "zombie" and not e.dead).size()
	print("[M] wrong Mourner: zombie raised %s, still hidden %s" % [zombies1 > zombies0, hm.state == "hidden"])
	# crush the heart
	l0 = boss.life
	carrier.take_damage(99999.0, 0.0, h.global_position, 0.0, false)
	await wait(0.2)
	print("[M] heart crushed: lost %.0f%% of max life, state %s, taken %.1f, stunned %s, mourners left %d" % [(l0 - boss.life) / boss.max_life * 100.0, hm.state, boss.taken, boss.stun_t > 0.0, hm.mourners.size()])
	dealt = boss.take_damage(100.0, 0.0, h.global_position, 0.0, false)
	print("[M] exposed hit: dealt %.1f" % dealt)
	await wait(Matron.EXPOSED_TIME + 0.5)
	print("[M] next cycle: state %s mourners %d (cycle %d) taken %.2f" % [hm.state, hm.mourners.size(), hm.cycle, boss.taken])
	# the phase floor: in cycle 1 nothing takes her below a third until the heart is crushed again
	await wait(2.0)
	boss.take_damage(boss.life * 10.0 + 99999.0, 0.0, h.global_position, 0.0, false)
	print("[M] phase floor: a huge hit in cycle 1 leaves her at %.0f%% (floor 33%%), alive %s" % [boss.life / boss.max_life * 100.0, not boss.dead])
	# her death (final cycle) clears the Mourners
	hm.cycle = 2
	var ms: Array = hm.mourners.duplicate()
	boss.taken = 1.0
	boss.take_damage(boss.life * 10.0 + 99999.0, 0.0, h.global_position, 0.0, false)
	await wait(0.3)
	print("[M] boss dead %s, mourners cleared %s, boss killed flag %s" % [boss.dead, ms.filter(func(m): return is_instance_valid(m) and not m.dead).is_empty(), g.boss_killed])
	quit()
