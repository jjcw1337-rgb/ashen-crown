extends SceneTree
## A2 (the Imperial Road and Aurelia): the road is built in its stretches and its bandits spring their
## ambush when a hero reaches the pass; Aurelia has its arena, crowd and Varro; his deal opens the gate,
## stepping onto the sand starts the games, each stage follows the last once its fighters are dead,
## the champion calls adds as he weakens, and his death ends the act. Prints [A] lines.
var g
var fails := 0

var Aur    # aurelia.gd, loaded at run time (a static reference compiles it before the Sfx autoload exists)

func _initialize():
	g = (load("res://main.tscn") as PackedScene).instantiate()
	get_root().add_child(g)
	_run()

func wait(s: float) -> void:
	await create_timer(s).timeout

func check(ok: bool, what: String) -> void:
	if not ok:
		fails += 1
	print("[A] %s %s" % ["ok  " if ok else "FAIL", what])

func _kill_all(list: Array) -> void:
	for e in list:
		if is_instance_valid(e) and not e.dead:
			e.take_damage(99999.0, 0.0, g.hero.global_position, 0.0, false)

## Walk the hero toward to (re-ordering the move each second, as a held click would) until within near.
func _walk(to: Vector3, secs: float, near := 1.0) -> bool:
	var t0 := Time.get_ticks_msec()
	var last := -1
	while Time.get_ticks_msec() - t0 < secs * 1000.0:
		var sec := int((Time.get_ticks_msec() - t0) / 1000)
		if sec != last:
			last = sec
			g.hero.cmd_move(to)
		await process_frame
		var d: Vector3 = g.hero.global_position - to
		if Vector2(d.x, d.z).length() < near:
			return true
	return false

func _run() -> void:
	while g.world == null or g._busy:
		g._intro_skip = true
		await process_frame
	await g.start_game(false, "knight")
	Aur = load("res://scripts/aurelia.gd")
	g.test_immortal = true
	g.difficulty = 1
	# the road
	await g.load_zone(0, "wild", "start")
	var w = g.world
	check(w.run == 1 and w.bounds.size.y > 300.0, "A2 wild is the Imperial Road (%.0f m long)" % w.bounds.size.y)
	check(g.zone_title(0, "wild").begins_with("The Imperial Road"), "title: " + g.zone_title(0, "wild"))
	var paved: int = w.cobble_lines.size()
	check(paved > 20 and w.dirt_lines.size() > paved, "dirt trail then paving: %d paved, %d dirt" % [paved, w.dirt_lines.size()])
	var roman := {}
	for c in w.props_root.get_children():
		if c.has_meta("roman"):
			roman[c.get_meta("roman")] = int(roman.get(c.get_meta("roman"), 0)) + 1
	check(roman.has("aqueduct") and roman.has("arch"), "aqueduct and triumphal arch: %s" % [roman])
	check(w.exits.any(func(x): return x["to"] == "lair"), "an exit to Aurelia")
	var am: Dictionary = w.ambushes[0]
	var bandits_before: int = w.enemies_root.get_children().filter(func(e): return e is Enemy and e.global_position.distance_to(am["pos"]) < 20.0 and e.kind.begins_with("bandit")).size()
	g.hero.global_position = am["pos"] + Vector3(0, 0, 30)
	await wait(0.3)
	check(not am["done"], "no ambush from 30 m away")
	g.hero.global_position = am["pos"]
	# the leaps take ~1.5 s once spawned (spawning a dozen models can stall the first frames): give them 4
	var near: Array = []
	var on_road := 0
	for i in 20:
		await wait(0.2)
		near = w.enemies_root.get_children().filter(func(e): return e is Enemy and not e.dead and e.kind.begins_with("bandit") and e.global_position.distance_to(am["pos"]) < 16.0)
		on_road = near.filter(func(e): return w.path_dist(e.global_position.x, e.global_position.z) < 7.5).size()
		if on_road >= 5 and i >= 8:
			break
	check(am["done"] and bandits_before == 0 and near.size() >= 8 and on_road >= 5, "ambush: none there before (%d), %d bandits sprang out, %d of them down on the road" % [bandits_before, near.size(), on_road])
	var caps: Array = w.enemies_root.get_children().filter(func(e): return e is Enemy and e.champion and e.kind == "bandit" and e.global_position.distance_to(am["pos"]) < 25.0)
	check(caps.size() == 1, "the Bandit Captain sprang out with them (%d champion within 25 m)" % caps.size())
	# Aurelia
	await g.load_zone(0, "lair", "start")
	w = g.world
	check(w.has_meta("games") and not g.indoor(), "Aurelia: outdoors, with the games")
	var games = w.get_meta("games")
	check(games.lanista != null and games.lanista.kind == "lanista", "Varro is there")
	check(w.props_root.get_node("crowd").multimesh.instance_count > 400, "a crowd of %d" % w.props_root.get_node("crowd").multimesh.instance_count)
	var gp: Vector2 = Aur.floor_pt(Aur.GATES["life"], 1.04)
	check(w.solid_at(gp.x, gp.y, 0.3), "the Gate of Life is shut before the deal")
	# Varro stands in the open (nothing tall like a brazier within 2.5 m), a Meshy body, and the hero
	# walks to him from the city gate
	var vp: Vector3 = games.lanista.global_position
	var crowded := 0
	for prop in w.props_root.get_children():
		if prop is Node3D and str(prop.name).contains("brazier") and (prop as Node3D).global_position.distance_to(vp) < 2.5:
			crowded += 1
	check(crowded == 0 and games.lanista.rig != null and games.lanista.rig.has_meta("meshy_monster"), "Varro: in the open (%d braziers by him), the Meshy bandit" % crowded)
	g.hero.global_position = w.spawns["start"]
	var walked: bool = await _walk(vp + Vector3(0, 0, 1.6), 40.0)
	check(walked, "walked from the city gate to Varro (%.1f m off)" % g.hero.global_position.distance_to(vp))
	# he offers the games even to a hero whose save says the act's boss is dead (the old A2's Grubb)
	g.boss_killed = true
	g._interact(games.lanista)
	await process_frame
	var offers: bool = g.ui.dialog_btns.get_children().any(func(b): return b is Button and (b as Button).text == "Enter the games")
	check(g.ui.dialog_panel.visible and offers, "Varro offers the games (with the boss already killed once)")
	g.boss_killed = false
	games.begin()
	await process_frame
	check(games.state == "open" and not w.solid_at(gp.x, gp.y, 0.3), "the deal opens the gate")
	g.ui.close_all()
	var in_ok: bool = await _walk(Vector3(Aur.CENTRE.x, 0, Aur.CENTRE.y), 25.0, 6.0)
	check(in_ok, "walked through the Gate of Life onto the sand")
	await wait(0.5)
	check(games.state == "intro" and w.solid_at(gp.x, gp.y, 0.3), "stepping onto the sand shuts the gate")
	var seen := []
	for s in 3:
		var t0 := Time.get_ticks_msec()
		while Time.get_ticks_msec() - t0 < 15000:
			await process_frame
			if games.state == "stage" and games.stage == s:
				break
		seen.append("%d:%s" % [games.stage, ",".join(games.foes.map(func(e): return e.kind))])
		await wait(0.6)
		_kill_all(games.foes)
		await wait(0.3)
	check(seen.size() == 3 and seen[0].contains("lion") and seen[1].contains("gladiator"), "stages: %s" % [seen])
	for i in 600:
		await process_frame
		if games.state == "boss":
			break
	var boss = games.boss
	check(boss != null and is_instance_valid(boss) and boss.kind == "champion" and boss.boss, "the champion enters")
	for i in 900:
		await process_frame
		if games.bursts > 0:
			break
	check(games.bursts > 0, "the pit's spike traps burst during the champion's bout (%d)" % games.bursts)
	for i in 900:
		if i % 45 == 0 and games.charges == 0:
			# keep away from him across the sand
			var away: Vector3 = (boss.global_position - Vector3(Aur.CENTRE.x, 0, Aur.CENTRE.y)).normalized()
			g.hero.global_position = Vector3(Aur.CENTRE.x, 0, Aur.CENTRE.y) - away * 9.0
		await process_frame
		if games.charges > 0 and games.charge.is_empty():
			break
	check(games.charges > 0, "Aurelius charged (%d)" % games.charges)
	if not is_instance_valid(boss) or boss.dead:
		boss = games.boss
	boss.life = boss.max_life * 0.55
	await wait(0.4)
	var n1: int = w.enemies_root.get_children().filter(func(e): return e is Enemy and not e.dead and e.kind == "lion").size()
	boss.life = boss.max_life * 0.25
	await wait(0.4)
	var n2: int = w.enemies_root.get_children().filter(func(e): return e is Enemy and not e.dead and e.kind == "gladiator").size()
	check(games.adds == 2 and n1 >= 2 and n2 >= 2, "adds as he weakens: lions %d, gladiators %d" % [n1, n2])
	boss.take_damage(99999.0, 0.0, g.hero.global_position, 0.0, false)
	await wait(1.0)
	check(games.state == "won" and g.boss_killed and not w.solid_at(gp.x, gp.y, 0.3), "the champion falls: act won %s, gate open" % g.boss_killed)
	print("[A] done, %d failed" % fails)
	quit()
