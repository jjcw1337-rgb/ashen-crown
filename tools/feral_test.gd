extends SceneTree
## The Feral (feral.gd): packs cling to oak trunks deep in the Act I forest; come close and they come down
## the trunk, surround you, lunge one at a time, back off and claw. Prints [F] lines.
var g

func _initialize():
	g = (load("res://main.tscn") as PackedScene).instantiate()
	get_root().add_child(g)
	_run()

func wait(s: float) -> void:
	await create_timer(s).timeout

func _ferals() -> Array:
	return g.world.enemies_root.get_children().filter(func(e) -> bool: return e.kind == "feral" and not e.dead)

func _run() -> void:
	while g.world == null or g._busy:
		g._intro_skip = true
		await process_frame
	await g.start_game(false, "knight")
	g.difficulty = 0
	await g.load_zone(0, "wild", "start")
	await wait(0.5)
	var fs := _ferals()
	var packs := {}
	var perched := 0
	var road := []
	for e in fs:
		packs[e.pack_id] = int(packs.get(e.pack_id, 0)) + 1
		if e.perch_h > 0.0:
			perched += 1
		road.append(snappedf(g.world.path_dist(e.global_position.x, e.global_position.z), 1.0))
	var anim_ok: bool = fs.size() > 0 and fs[0].rig.has_meta("feral")
	print("[F] ferals %d in %d packs %s, perched %d, up %.1f m, metres from the road %s, baked animations %s" % [fs.size(), packs.size(), packs.values(), perched,
		(fs[0].global_position.y - g.world.height_at(fs[0].global_position.x, fs[0].global_position.z)) if fs.size() > 0 else 0.0, road, anim_ok])
	if fs.is_empty():
		quit()
		return
	# walk up to a pack
	var e0 = fs[0]
	var pack: int = e0.pack_id
	g.test_immortal = false
	var life0: float = g.hero.life
	g.hero.global_position = e0.global_position + (e0.perch_dir * 7.0)
	g.hero.global_position.y = g.world.height_at(g.hero.global_position.x, g.hero.global_position.z)
	var down_at := -1.0
	var lunges := 0
	var swipes := 0
	var backs := 0
	var hits := 0
	var t := 0.0
	var t0 := Time.get_ticks_msec()
	var seen := {}
	var hero_life: float = g.hero.life
	while t < 14.0:
		await process_frame
		t = (Time.get_ticks_msec() - t0) / 1000.0
		var mates: Array = _ferals().filter(func(e) -> bool: return e.pack_id == pack)
		if down_at < 0.0 and mates.all(func(e) -> bool: return e.perch_h <= 0.0):
			down_at = t
		for e in mates:
			var key: String = str(e.get_instance_id()) + e.atk_style + str(e.atk_t >= 0.0) + e.f_state
			if seen.has(key):
				continue
			seen[key] = true
			if e.atk_style == "feral_lunge" and e.atk_t >= 0.0:
				lunges += 1
			if e.atk_style == "feral_swipe" and e.atk_t >= 0.0:
				swipes += 1
			if e.f_state == "back":
				backs += 1
		if g.hero.life < hero_life:
			hits += 1
		hero_life = g.hero.life
		g.hero.life = g.hero.max_life
		hero_life = g.hero.life
	print("[F] all down after %.1f s; lunges %d, backed off %d, claw swipes %d, hits on the hero %d" % [down_at, lunges, backs, swipes, hits])
	var e1 = _ferals().filter(func(e) -> bool: return e.pack_id == pack)
	var spread := []
	for e in e1:
		var d: Vector3 = e.global_position - g.hero.global_position
		spread.append(int(rad_to_deg(atan2(d.x, d.z))))
	spread.sort()
	print("[F] around the hero at angles ", spread, " still up: ", e1.filter(func(e) -> bool: return e.perch_h > 0.0).map(func(e) -> String: return "%s %.1f m away" % [e.atk_style, e.global_position.distance_to(g.hero.global_position)]))
	# outrun them: after 6 s out of reach they give up and head home
	var dir: Vector3 = (g.hero.global_position - e1[0].global_position)
	dir.y = 0
	dir = dir.normalized()
	var away: Vector3 = g.hero.global_position + dir * 12.0
	var t1 := Time.get_ticks_msec()
	var last := t1
	var gave_up := -1.0
	while (Time.get_ticks_msec() - t1) / 1000.0 < 10.0:
		# sprinting off at 6 m/s (no walls in the way: the test moves him directly)
		var now := Time.get_ticks_msec()
		away += dir * 6.0 * (now - last) / 1000.0
		last = now
		g.hero.global_position = Vector3(away.x, g.world.height_at(away.x, away.z), away.z)
		g.hero.life = g.hero.max_life
		await process_frame
		if gave_up < 0.0 and _ferals().filter(func(e) -> bool: return e.pack_id == pack).all(func(e) -> bool: return not e.aggro):
			gave_up = (Time.get_ticks_msec() - t1) / 1000.0
	print("[F] outrun: the pack gave up after %.1f s; speed %.1f (hero walks 4.8); scale %.2f" % [gave_up, e0.speed, Feral.SCALE])
	quit()
