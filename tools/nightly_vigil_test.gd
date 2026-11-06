extends SceneTree
## The Last Flame (scripts/vigil.gd), played solo (the host's code is the same in co-op and on the co-op server):
## the camp's Vigil Gate takes the hero down, the sanctum is built (altar, three breaches, the way back), the flame
## kindles, wave 1's monsters walk to the flame and hurt it while the hero keeps away, every wave is cleared past
## the tenth (gold by the flame, the flame mends; a unique at the tenth; it's endless: the eleventh comes, bigger and
## stronger), the flame goes out in the twelfth: 11 waves held, the game's best (FlameBoard, the test file); the
## flame relights; a second vigil is lost (the wave crumbles with no xp), a death rises by the altar, and the
## portal leads back to the camp.
##   godot --headless --path . -s tools/nightly_vigil_test.gd
var g
var fails := 0

func _initialize():
	g = (load("res://main.tscn") as PackedScene).instantiate()
	get_root().add_child(g)
	current_scene = g
	_run()

func check(ok: bool, what: String) -> void:
	if not ok:
		fails += 1
	print("[V] " + ("ok   " if ok else "FAIL ") + what)

func until(f: Callable, t: float) -> bool:
	var end := Time.get_ticks_msec() + int(t * 1000.0)
	while Time.get_ticks_msec() < end:
		if f.call():
			return true
		await process_frame
	return false

func secs(t: float) -> void:
	await create_timer(t).timeout

func _inter(kind: String):
	for t in g.world.interactables:
		if is_instance_valid(t) and t.kind == kind:
			return t
	return null

func _wave_mons() -> Array:
	return g.world.enemies_root.get_children().filter(func(e): return "pvp_pid" in e and not e.dead and e.pvp_pid == 0)

func _run() -> void:
	Engine.max_fps = 60
	while g.world == null or g._busy:
		g._intro_skip = true
		await process_frame
	await g.start_game(false, "knight")
	g.ui.close_all()
	g.test_immortal = true
	if g.cur_zone != "town":
		await g.load_zone(0, "town", "start")
	# the camp's gate
	var gate = _inter("vigil_gate")
	check(gate != null and g.world.spawns.has("from_vigil"), "the camp has the Vigil Gate (%s)" % (str(gate.global_position) if gate else "none"))
	if gate == null:
		_done()
		return
	check(not g.world.solid_at(gate.global_position.x, gate.global_position.z), "the gate stands on open ground")
	g.hero.global_position = g.world.free_spot_near(gate.global_position, 1.5)
	g._interact(gate)
	check(await until(func(): return g.cur_zone == "vigil" and not g._busy, 30.0), "the gate leads down to the Last Flame")
	var v = g.world.get_meta("vigil") if g.world.has_meta("vigil") else null
	check(v != null and v.flame != null and v.state == "idle", "the vigil waits (idle) with its flame")
	if v == null:
		_done()
		return
	check(g.indoor() and g.zone_title(0, "vigil") == "The Last Flame", "an indoor sanctum called %s" % g.zone_title(0, "vigil"))
	check(_inter("vigil") != null and _inter("vigil_exit") != null, "the altar and the way back are there")
	var reach := true
	for gp in v.GATES:
		var path: PackedVector3Array = g.world.find_path(gp, v.CENTER + Vector3(0, 0, 2.6))
		reach = reach and path.size() > 0
	check(reach, "every breach has a way to the altar")
	check(g.hero.global_position.distance_to(v.START) < 4.0, "the hero arrives by the altar")
	check(_wave_mons().is_empty(), "no monsters before the vigil")
	# kindle it, and keep away: the dead must go for the flame
	g._interact(_inter("vigil"))
	check(v.state == "count" and v.life == v.max_life and v.max_life > 0.0, "the flame kindles (%d life)" % v.max_life)
	g.hero.global_position = g.world.free_spot_near(Vector3(0, 0, 23.0), 1.0)
	check(await until(func(): return v.state == "wave" and v.wave == 1, 12.0), "wave 1 comes")
	check(await until(func(): return _wave_mons().size() >= 3, 8.0), "monsters pour out of the breaches (%d)" % _wave_mons().size())
	check(await until(func(): return v.life < v.max_life, 45.0), "they go for the flame and hurt it (%d/%d)" % [v.life, v.max_life])
	# clear every wave, past the authored ten
	DirAccess.remove_absolute(FlameBoard.TEST_PATH)
	var gold0 := _gold_on_floor()
	var xp0: int = g.hero.xp
	var sizes := {}
	for n in range(1, v.WAVES.size() + 2):
		if not await until(func(): return v.state == "wave" and v.wave == n, 20.0):
			check(false, "wave %d began" % n)
			break
		var peak := 0
		var champ := false
		var bar := false
		sizes[n] = v.left
		while v.state == "wave":
			bar = bar or (g.ui.boss_ref != null and is_instance_valid(g.ui.boss_ref) and g.ui.boss_ref.champion)
			v._spawn_t = 0.0
			for e in _wave_mons():
				peak = maxi(peak, _wave_mons().size())
				champ = champ or e.champion
				e.take_damage(1e7, 0.0, g.hero.global_position, 0.0, false)
			await process_frame
		if n in [5, 10]:
			check(champ and bar, "wave %d had its champion, its life bar on screen" % n)
		check(v.state == "break" and v.wave == n, "wave %d held (at most %d on the floor)" % [n, peak])
		if n == v.WAVES.size():
			await secs(0.5)
			check(_uniques_on_floor() >= 1, "ten waves held: a unique for the vigil")
		v.t = 0.3
	check(int(sizes.get(11, 0)) > int(sizes.get(10, 0)) and v.wave_level(11) > v.wave_level(10),
		"it's endless: wave 11 comes, bigger (%d foes vs %d) and stronger (level %d vs %d)" % [sizes.get(11, 0), sizes.get(10, 0), v.wave_level(11), v.wave_level(10)])
	var d30: Dictionary = v.wave_def(30)
	var n30 := 0
	for f in d30["foes"]:
		n30 += int(f[1])
	check(n30 > int(sizes.get(11, 0)) and d30.has("champs") and v.wave_level(30) > v.wave_level(11) + 8, "and wave 30 is far worse (%d foes, %d champions, level %d)" % [n30, d30.get("champs", []).size(), v.wave_level(30)])
	await secs(1.0)
	check(_gold_on_floor() > gold0 + 9, "gold lies by the flame (%d piles)" % (_gold_on_floor() - gold0))
	check(g.hero.xp > xp0, "the kills gave experience")
	# the flame goes out in the twelfth: eleven held, this game's best
	v.t = 0.1
	check(await until(func(): return v.state == "wave" and v.wave == 12, 10.0), "wave 12 comes")
	v.flame_hit(v.life + 10.0, Vector3.ZERO)
	await process_frame
	check(v.state == "lost" and v.held == 11, "the flame goes out in wave 12: %d waves held" % v.held)
	await secs(0.3)
	check(FlameBoard.best(g) == 11 and FlameBoard.best_record(g).get("party", 0) == 1, "the game keeps its best: %s" % str(FlameBoard.best_record(g)))
	check(g.ui.hud.get_node_or_null("vigil_hud") != null and str(g.ui.hud.get_node("vigil_hud").get_child(0).text).contains("11 waves held"), "the HUD says so")
	v.t = 0.2
	check(await until(func(): return v.state == "idle" and v.life == v.max_life, 5.0), "the flame relights")
	check(str(g.ui.hud.get_node("vigil_hud").get_child(0).text).contains("your best: 11"), "and shows the best to beat")
	# a second vigil, lost
	g._interact(_inter("vigil"))
	v.t = 0.1
	check(await until(func(): return v.state == "wave" and _wave_mons().size() >= 2, 10.0), "a new vigil begins")
	# a bone archer's arrow hits the flame
	var la: float = v.life
	var pr = load("res://scripts/projectile.gd").new()
	g.world.fx_root.add_child(pr)
	pr.launch(g, "arrow", v.CENTER + Vector3(0.3, 1.35, -7.0), v.CENTER + Vector3(0, 1.1, 0), 40.0)
	await secs(1.0)
	check(v.life <= la - 39.0, "an arrow shot at the flame hurts it (%d -> %d)" % [la, v.life])
	# a log from the moor feeds it
	v.life = v.max_life * 0.5
	g.hero.add_to_inventory(Items.make("oak_log", 0, 1))
	var l0: float = v.life
	g._interact(_inter("vigil"))
	check(g.hero.count_of("oak_log") == 0 and absf(v.life - l0 - v.max_life * 0.08) < 1.0, "an oak log feeds the flame (+8%%: %d -> %d)" % [l0, v.life])
	g._interact(_inter("vigil"))
	check(absf(v.life - l0 - v.max_life * 0.08) < 1.0, "and with no log left, nothing more")
	var xp1: int = g.hero.xp
	v.flame_hit(v.life + 10.0, Vector3.ZERO)
	await process_frame
	check(v.state == "lost" and v.flame.dead, "the flame goes out: the vigil is lost")
	check(FlameBoard.best(g) == 11, "a worse vigil leaves the best alone")
	await secs(0.5)
	check(_wave_mons().is_empty() and g.hero.xp == xp1, "its wave crumbles to ash (no experience)")
	check(not v.flame_fx.visible, "the fire is out")
	v.t = 0.2
	check(await until(func(): return v.state == "idle" and v.flame_fx.visible, 5.0), "and burns again")
	# a death rises by the altar
	g.test_immortal = false
	g.hero.global_position = g.world.free_spot_near(Vector3(0, 0, -30.0), 1.0)
	for i in 10:
		if not g.hero.dead:
			g.hero.take_hit(999999.0, g.hero.global_position + Vector3(1, 0, 0))
	check(g.hero.dead, "the hero fell")
	g.respawn()
	await secs(0.5)
	check(not g.hero.dead and g.cur_zone == "vigil" and g.hero.global_position.distance_to(v.START) < 4.0, "and rose by the Last Flame")
	g.test_immortal = true
	# the way back
	var ex = _inter("vigil_exit")
	g.hero.global_position = g.world.free_spot_near(ex.global_position, 1.0)
	g._interact(ex)
	check(await until(func(): return g.cur_zone == "town" and not g._busy, 30.0), "the portal leads back to the camp")
	check(g.hero.global_position.distance_to(g.world.spawns["from_vigil"]) < 3.0, "by the Vigil Gate")
	g.save_game()
	_done()

func _gold_on_floor() -> int:
	return g.world.items_root.get_children().filter(func(i): return "item" in i and i.item.get("base", "") == "gold").size()

func _uniques_on_floor() -> int:
	return g.world.items_root.get_children().filter(func(i): return "item" in i and int(i.item.get("rarity", 0)) >= 3).size()

func _done() -> void:
	print("[V] done, %d failed" % fails)
	g.queue_free()
	for i in 8:
		await process_frame
	quit(1 if fails else 0)
