extends SceneTree
## The Gauntlet of Kings (scripts/gauntlet.gd), played solo (the host's code is the same in co-op and on the co-op
## server): the camp's Gauntlet Gate takes the hero down, the throne hall is built (gong, Throne Gate, three offerings,
## the way back), the gong starts the clock, the first king comes through the gate, notices the hero and fights him
## (its life bar up), each king's fall lights a trophy and opens the offerings (Wrath wounds the next king, Greed makes
## it stronger and drops a hoard, Mercy heals and gives a life back), all four fall (a unique, the record saved), the
## gong can be struck again; a second run is lost when a hero falls with no lives left (the king crumbles, no xp), the
## fallen rise at the hall's door, and the portal leads back to the camp.
##   godot --headless --path . -s tools/nightly_gauntlet_test.gd
var g
var fails := 0

func _initialize():
	g = (load("res://main.tscn") as PackedScene).instantiate()
	get_root().add_child(g)
	_run()

func check(ok: bool, what: String) -> void:
	if not ok:
		fails += 1
	print("[G] " + ("ok   " if ok else "FAIL ") + what)

func until(f: Callable, t: float) -> bool:
	var end := Time.get_ticks_msec() + int(t * 1000.0)
	while Time.get_ticks_msec() < end:
		if f.call():
			return true
		await process_frame
	return false

func secs(t: float) -> void:
	await create_timer(t).timeout

func _inter(kind: String, i := -1):
	for t in g.world.interactables:
		if is_instance_valid(t) and t.kind == kind and (i < 0 or int(t.data.get("i", -1)) == i):
			return t
	return null

func _mons() -> Array:
	return g.world.enemies_root.get_children().filter(func(e): return "pvp_pid" in e and not e.dead and e.pvp_pid == 0)

func _kill(gt) -> void:
	if gt.boss != null and is_instance_valid(gt.boss) and not gt.boss.dead:
		gt.boss.take_damage(1e9, 0.0, g.hero.global_position, 0.0, false)

func _run() -> void:
	Engine.max_fps = 60
	while g.world == null or g._busy:
		g._intro_skip = true
		await process_frame
	await g.start_game(false, "knight")
	g.ui.close_all()
	g.test_immortal = true
	g.hero.set_level(12)
	if g.cur_zone != "town":
		await g.load_zone(0, "town", "start")
	var f0 := FileAccess.open("user://gauntlet_record_test.json", FileAccess.WRITE)
	if f0 != null:
		f0.store_string("{}")
		f0 = null
	# the camp's gate
	var gate = _inter("gauntlet_gate")
	check(gate != null and g.world.spawns.has("from_gauntlet"), "the camp has the Gauntlet Gate (%s)" % (str(gate.global_position) if gate else "none"))
	if gate == null:
		_done()
		return
	check(not g.world.solid_at(gate.global_position.x, gate.global_position.z), "the gate stands on open ground")
	check(g.world.find_path(g.world.spawns["start"], gate.global_position).size() > 0, "it can be walked to from the camp's middle")
	check(_inter("vigil_gate") != null, "the Vigil Gate is still there")
	g.hero.global_position = g.world.free_spot_near(gate.global_position, 1.5)
	g._interact(gate)
	check(await until(func(): return g.cur_zone == "gauntlet" and not g._busy, 30.0), "the gate leads down to the Gauntlet of Kings")
	var gt = g.world.get_meta("gauntlet") if g.world.has_meta("gauntlet") else null
	check(gt != null and gt.state == "idle", "the hall waits (idle)")
	if gt == null:
		_done()
		return
	check(g.indoor() and g.zone_title(0, "gauntlet") == "The Gauntlet of Kings", "an indoor hall called %s" % g.zone_title(0, "gauntlet"))
	check(_inter("gauntlet") != null and _inter("gauntlet_exit") != null and _inter("gauntlet_boon", 0) != null and _inter("gauntlet_boon", 1) != null and _inter("gauntlet_boon", 2) != null, "the gong, three offerings and the way back are there")
	check(g.world.find_path(gt.GATE, gt.CENTER).size() > 0 and g.world.find_path(gt.START, gt.CENTER).size() > 0, "the Throne Gate and the door both reach the floor")
	check(g.hero.global_position.distance_to(gt.START) < 4.0, "the hero arrives at the hall's door")
	check(_mons().is_empty(), "no monsters before the gong")
	# an offering before any king is refused
	g._interact(_inter("gauntlet_boon", 0))
	check(gt.state == "idle" and gt.boon == -1, "no offering can be taken before a run")
	# the gong
	g._interact(_inter("gauntlet"))
	check(gt.state == "count" and gt.lives == gt.LIVES and gt.king == 0, "the gong starts a run (%d lives)" % gt.lives)
	g._interact(_inter("gauntlet"))
	check(gt.state == "count", "a second strike changes nothing")
	g.hero.global_position = g.world.free_spot_near(gt.CENTER + Vector3(0, 0, 4), 1.0)
	check(await until(func(): return gt.state == "fight" and gt.boss != null, 10.0), "the first king comes through the Throne Gate")
	var k0 = gt.boss
	check(k0 != null and k0.kind == "trex" and k0.boss, "it is Gorehide the Tyrant (%s)" % (k0.kind if k0 else "none"))
	check(g.ui.boss_ref == k0, "its life bar is on screen")
	check(await until(func(): return k0.aggro, gt.NUDGE_SECS + 3.0), "it notices the hero")
	var l0: float = g.hero.life
	g.test_immortal = false
	g.hero.max_life = 1e7
	g.hero.life = 1e7
	l0 = g.hero.life
	check(await until(func(): return g.hero.life < l0, 25.0), "it comes for him and hurts him (%d)" % (l0 - g.hero.life))
	g.test_immortal = true
	g.hero.recalc()
	g.hero.life = g.hero.max_life
	await secs(0.3)
	check(not gt.clock(gt.run_t).is_empty() and gt.run_t > 1.0, "the clock runs (%s)" % gt.clock(gt.run_t))
	var t_kill: float = gt.run_t
	var xp0: int = g.hero.xp
	_kill(gt)
	check(await until(func(): return gt.state == "boon", 3.0), "the king falls: the offerings open")
	check(gt.splits.size() == 1 and absf(float(gt.splits[0]) - t_kill) < 1.0, "its split is kept (%s)" % str(gt.splits))
	check(g.hero.xp > xp0, "it gave experience")
	await secs(0.2)
	check(gt._trophies[0].visible and not gt._trophies[1].visible, "its trophy fire is lit")
	check(gt._orbs[1][0].visible, "the offerings glow")
	check(not g.boss_killed, "a king isn't the act's boss (no act victory)")
	# Wrath: the next king comes in wounded
	g._interact(_inter("gauntlet_boon", 1))
	check(gt.state == "count" and gt.boon == 1, "the Offering of Wrath is taken")
	g._interact(_inter("gauntlet_boon", 2))
	check(gt.boon == 1, "only one offering per king")
	check(await until(func(): return gt.state == "fight" and gt.boss != null, 10.0), "the second king comes")
	var k1 = gt.boss
	check(k1.kind == "sloth_fire" and absf(k1.life / k1.max_life - gt.WRATH) < 0.02, "Cinderhide comes in wounded (%d%% life)" % int(100.0 * k1.life / k1.max_life))
	check(g.ui.boss_ref == k1, "its life bar is on screen (a Sloth isn't a boss elsewhere)")
	await secs(3.0)
	check(k1.sloth != null and k1.sloth.state == "hunt", "it hunts (%s)" % (k1.sloth.state if k1.sloth else "-"))
	_kill(gt)
	check(await until(func(): return gt.state == "boon", 3.0), "the second king falls")
	# Greed: stronger, but a hoard
	g._interact(_inter("gauntlet_boon", 2))
	check(await until(func(): return gt.state == "fight" and gt.boss != null, 10.0), "the third king comes")
	var k2 = gt.boss
	var base_life: float = Data.ENEMIES["hermit"]["life"] * (1.0 + 0.3 * (k2.level - 1)) * g.run_mult("boss_life") * gt.KINGS[2]["life"]
	check(k2.kind == "hermit" and absf(k2.max_life / base_life - gt.GREED_LIFE) < 0.05 and gt.greed == 1, "Old Mossbeard comes greedy (life x%.2f)" % (k2.max_life / base_life))
	await secs(6.0)
	var shrooms: int = _mons().filter(func(e): return e.kind == "spore_shroom").size()
	print("[G] his mushrooms: %d" % shrooms)
	var gold0 := _gold_on_floor()
	_kill(gt)
	check(await until(func(): return gt.state == "boon", 3.0), "the third king falls")
	await secs(1.0)
	check(_gold_on_floor() >= gold0 + 3, "Greed's hoard lies where he fell (%d piles)" % (_gold_on_floor() - gold0))
	check(_mons().is_empty(), "his mushrooms wither with him")
	# Mercy: healed, and a life back
	g.hero.life = g.hero.max_life * 0.3
	var lv0: int = gt.lives
	g._interact(_inter("gauntlet_boon", 0))
	check(gt.lives == lv0 + 1 and g.hero.life >= g.hero.max_life - 0.5, "the Offering of Mercy heals him and gives a life back (%d)" % gt.lives)
	check(await until(func(): return gt.state == "fight" and gt.boss != null, 10.0), "the last king comes")
	var k3 = gt.boss
	check(k3.kind == "ice_troll", "Hrimgar the Frostbound")
	await secs(1.0)
	var u0 := _uniques_on_floor()
	_kill(gt)
	check(await until(func(): return gt.state == "won", 3.0), "all four kings fall: the gauntlet is won")
	await secs(1.0)
	check(gt.record > 0.0 and absf(gt.record - float(gt.splits[-1])) < 0.5, "the record is set (%s by %s)" % [gt.clock(gt.record), gt.record_by])
	check(FileAccess.file_exists("user://gauntlet_record_test.json") and FileAccess.get_file_as_string("user://gauntlet_record_test.json").contains("secs"), "and saved")
	check(_uniques_on_floor() > u0, "a unique for the victor")
	check(gt._trophies[3].visible, "every trophy burns")
	gt.t = 0.2
	check(await until(func(): return gt.state == "idle", 5.0), "the gong can be struck again")
	# a second run, lost: a fall with no lives left
	g._interact(_inter("gauntlet"))
	gt.t = 0.1
	check(await until(func(): return gt.state == "fight" and gt.boss != null, 6.0) and gt.splits.is_empty(), "a new run begins")
	var k4 = gt.boss
	gt.lives = 1
	g.test_immortal = false
	for i in 10:
		if not g.hero.dead:
			g.hero.take_hit(999999.0, g.hero.global_position + Vector3(1, 0, 0))
	await process_frame
	await process_frame
	check(g.hero.dead and gt.lives == 0 and gt.state == "fight", "a fall spends a life (%d left)" % gt.lives)
	g.respawn()
	await secs(0.5)
	check(not g.hero.dead and g.cur_zone == "gauntlet" and g.hero.global_position.distance_to(gt.START) < 4.0, "the fallen rise at the hall's door")
	var xp1: int = g.hero.xp
	for i in 10:
		if not g.hero.dead:
			g.hero.take_hit(999999.0, g.hero.global_position + Vector3(1, 0, 0))
	await process_frame
	await process_frame
	check(gt.state == "lost", "a fall with no lives left ends the run")
	await secs(0.5)
	check((not is_instance_valid(k4) or k4.dead) and _mons().is_empty() and g.hero.xp == xp1, "the king crumbles (no experience)")
	g.respawn()
	g.test_immortal = true
	await secs(0.3)
	gt.t = 0.2
	check(await until(func(): return gt.state == "idle", 5.0), "and the gong waits again")
	# the way back
	var ex = _inter("gauntlet_exit")
	g.hero.global_position = g.world.free_spot_near(ex.global_position, 1.0)
	g._interact(ex)
	check(await until(func(): return g.cur_zone == "town" and not g._busy, 30.0), "the portal leads back to the camp")
	check(g.hero.global_position.distance_to(g.world.spawns["from_gauntlet"]) < 3.0, "by the Gauntlet Gate")
	g.save_game()
	_done()

func _gold_on_floor() -> int:
	return g.world.items_root.get_children().filter(func(i): return "item" in i and i.item.get("base", "") == "gold").size()

func _uniques_on_floor() -> int:
	return g.world.items_root.get_children().filter(func(i): return "item" in i and int(i.item.get("rarity", 0)) >= 3).size()

func _done() -> void:
	print("[G] done, %d failed" % fails)
	quit()
