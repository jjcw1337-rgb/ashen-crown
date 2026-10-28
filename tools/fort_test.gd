extends SceneTree
## Grubb's fort (Act I lair): the fort is built (gatehouse, palisade, towers, huts), the hero can walk
## from the start through the gate to Grubb, and the guards and the dead fight each other at the gate
## without the hero (no xp or loot for their kills). Then the A3 lair is still the crypt.
var g
func _initialize():
	g = (load("res://main.tscn") as PackedScene).instantiate()
	get_root().add_child(g)
	_run()
func wait(s: float) -> void:
	await create_timer(s).timeout
func count(name: String) -> int:
	return g.world.props_root.get_children().filter(func(n): return n.has_meta("fort") and n.get_meta("fort") == name).size()
func _run() -> void:
	while g.world == null or g._busy:
		g._intro_skip = true
		await process_frame
	await g.start_game(false, "knight")
	g.ui.close_all()
	await g.load_zone(0, "lair", "start")
	var w = g.world
	print("[F] fort %s outdoor %s: gatehouse %d palisade %d towers %d huts %d" % [w.fort, not g.indoor(), count("gatehouse"), count("palisade"), count("tower"), count("hut")])
	var boss = null
	for e in w.enemies_root.get_children():
		if e is Enemy and e.boss:
			boss = e
	var path: PackedVector3Array = w.find_path(w.spawns["start"], boss.global_position)
	var gp := Fort.gate_pos()
	# walk the path (from the start) in short steps: it must pass through the gate's arch
	var via_gate := false
	var prev: Vector3 = w.spawns["start"]
	for p in path:
		for k in 40:
			var q: Vector3 = prev.lerp(p, k / 40.0)
			if Vector2(q.x, q.z).distance_to(gp) < 3.0:
				via_gate = true
		prev = p
	print("[F] path start -> Grubb: %d steps, through the gate %s" % [path.size(), via_gate])
	g.test_immortal = true
	var xp0: int = g.hero.xp
	var guards := []
	var dead := []
	for e in w.enemies_root.get_children():
		if e is Enemy and e.global_position.distance_to(Vector3(gp.x, 0, gp.y)) < 32.0 and e.kind in ["goblin_guard", "zombie"]:
			(guards if e.kind == "goblin_guard" else dead).append(e)
	await wait(9.0)
	var hurt := guards.filter(func(e): return not is_instance_valid(e) or e.dead or e.life < e.max_life).size() + dead.filter(func(e): return not is_instance_valid(e) or e.dead or e.life < e.max_life).size()
	var rival_kills := (guards + dead).filter(func(e): return is_instance_valid(e) and e.dead and e.killed_by_rival).size()
	print("[F] at the gate: %d guards, %d zombies; hurt or dead after 9 s: %d, killed by rivals: %d, hero xp unchanged %s" % [guards.size(), dead.size(), hurt, rival_kills, g.hero.xp == xp0])
	g.difficulty = 2
	await g.load_zone(0, "lair", "start")
	print("[F] A3 lair: fort %s indoor %s" % [g.world.fort, g.indoor()])
	# leave the test save on Act I for the other tests
	g.difficulty = 0
	await g.load_zone(0, "town", "start")
	g.save_game()
	quit()
