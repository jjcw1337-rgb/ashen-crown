extends SceneTree
## The three Fallen (fallen_skirmisher, fallen_reaver, fallen_stalker): each is in the roster with its own
## model, spawns through Game.spawn_enemy, notices and closes on the hero its own way, uses its own
## signature attack, lands each blow once and only in its window, recovers, takes hits and dies, and
## doesn't get stuck; then all three together. Prints [F] lines.
var g
var fails := 0
const KINDS := ["fallen_skirmisher", "fallen_reaver", "fallen_stalker"]
const ATTACK := {"fallen_skirmisher": "skirm_lunge", "fallen_reaver": "reaver_cleave", "fallen_stalker": "stalk_hook"}

func _initialize():
	g = (load("res://main.tscn") as PackedScene).instantiate()
	get_root().add_child(g)
	_run()

func wait(s: float) -> void:
	await create_timer(s).timeout

func check(ok: bool, what: String) -> void:
	if not ok:
		fails += 1
	print("[F] %s %s" % ["ok  " if ok else "FAIL", what])

func _clear() -> void:
	for e in g.world.enemies_root.get_children():
		e.queue_free()
	await process_frame

func _run() -> void:
	while g.world == null or g._busy:
		g._intro_skip = true
		await process_frame
	# the roster
	var MM = load("res://scripts/meshy_monster.gd")
	for k in KINDS:
		var d: Dictionary = Data.ENEMIES.get(k, {})
		check(not d.is_empty() and MM.ok(str(d.get("mesh", ""))) and d["atk"] == ATTACK[k], "%s in the roster with its model and %s" % [k, ATTACK[k]])
	var act_foes: Array = Data.act_info(0, 0)["foes"]
	check(KINDS.all(func(k): return k in act_foes) and not ("fallen" in act_foes), "Act I's foes are the three Fallen: %s" % [act_foes])
	await g.start_game(false, "demon")
	g.difficulty = 0
	await g.load_zone(0, "wild", "start")
	await wait(0.3)
	g.hero.set_level(15)
	var at: Vector3 = g.world.spawns["road"]
	var silhouettes := {}
	for k in KINDS:
		await _clear()
		g.hero.global_position = Vector3(at.x, g.world.height_at(at.x, at.z), at.z)
		g.hero.life = g.hero.max_life
		g.test_immortal = false
		var e: Enemy = g.spawn_enemy(k, at + Vector3(0, 0, 9.0), 3)
		check(e != null and e.rig.has_meta("gait"), "%s spawns through Game.spawn_enemy with its own run (%s)" % [k, e.rig.get_meta("gait") if e and e.rig.has_meta("gait") else "?"])
		silhouettes[k] = e.height
		var attacks := 0
		var hits := 0
		var hits_this := 0
		var max_hits_one := 0
		var noticed := -1.0
		var moved := 0.0
		var last := e.global_position
		var recovered := false
		var was_atk := false
		var life: float = g.hero.life
		var t := 0.0
		var side_moves := 0.0
		var sp_seen := {}
		while t < 16.0 and attacks < 3:
			await wait(0.05)
			t += 0.05
			if e.aggro and noticed < 0.0:
				noticed = t
			moved += e.global_position.distance_to(last)
			var to_h: Vector3 = g.hero.global_position - e.global_position
			to_h.y = 0
			var step: Vector3 = e.global_position - last
			step.y = 0
			if to_h.length() > 0.1 and step.length() > 0.001:
				side_moves += absf(step.normalized().cross(to_h.normalized()).y) * step.length()
			last = e.global_position
			var att: bool = e.special == ATTACK[k]
			if att:
				sp_seen[e.special] = true
			if att and not was_atk:
				attacks += 1
				hits_this = 0
			if not att and was_atk:
				max_hits_one = maxi(max_hits_one, hits_this)
				recovered = recovered or e.atk_t < 0.0
			was_atk = att
			if g.hero.life < life - 0.5:
				hits += 1
				hits_this += 1
			life = g.hero.life
			g.hero.life = maxf(g.hero.life, g.hero.max_life * 0.5)
			life = g.hero.life
		check(noticed >= 0.0, "%s notices the hero (after %.1f s)" % [k, noticed])
		check(attacks >= 1 and sp_seen.size() == 1, "%s uses its own attack: %d x %s in %.1f s" % [k, attacks, ATTACK[k], t])
		check(hits >= 1, "%s lands blows: %d" % [k, hits])
		check(max_hits_one <= 1, "%s hits at most once per attack (worst %d)" % [k, max_hits_one])
		check(recovered, "%s recovers after attacking" % k)
		check(moved > 2.0, "%s moves (%.1f m), not stuck" % [k, moved])
		if k == "fallen_stalker":
			check(side_moves > 3.0, "the Stalker comes in sideways (%.1f m of lateral movement)" % side_moves)
		# it takes hits and dies
		var l0: float = e.life
		e.take_damage(5.0, 0.0, g.hero.global_position, 0.0, false)
		check(e.life < l0, "%s takes damage (%.0f -> %.0f)" % [k, l0, e.life])
		e.take_damage(9999.0, 0.0, g.hero.global_position, 0.0, false)
		await wait(0.5)
		check(e.dead or not is_instance_valid(e), "%s dies" % k)
	# all three at once
	await _clear()
	g.hero.global_position = Vector3(at.x, g.world.height_at(at.x, at.z), at.z)
	g.test_immortal = true
	var es := []
	for i in KINDS.size():
		es.append(g.spawn_enemy(KINDS[i], at + Vector3(cos(i * 2.1), 0, sin(i * 2.1)) * 8.0, 3))
	var seen := {}
	var t2 := 0.0
	while t2 < 12.0:
		await wait(0.05)
		t2 += 0.05
		for e in es:
			if is_instance_valid(e) and e.special != "":
				seen[e.special] = true
	check(seen.size() == 3, "together, all three attacks are used: %s" % [seen.keys()])
	check(silhouettes["fallen_reaver"] > silhouettes["fallen_skirmisher"] + 0.2, "three sizes: %s" % [silhouettes])
	print("[F] done, %d failed" % fails)
	quit()
