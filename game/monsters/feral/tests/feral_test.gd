extends SceneTree
## The Feral (feral.gd): a pack clings to an oak trunk in the Verdant Reach (put there by the test, as the old moor
## placed them); come close and they come down the trunk, surround you, lunge one at a time, back off and claw.
## Prints [F] lines.
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
	await g.load_zone(0, Battlegrounds.ZONE, "start")
	await wait(0.5)
	for e in g.world.enemies_root.get_children():
		e.free()
	# three of them on the trunk of the tree nearest a spot 30 m in from the glade, each on its own side
	var st: Vector3 = g.world.spawns["start"]
	var want := st + (Vector3.ZERO - st).normalized() * 30.0
	# (one with open ground 7 m out on its +x side, where the hero walks up: the first Feral clings on that side)
	var tr := Vector2.INF
	for q in g.world.tree_pts:
		var out := Vector3(q.x + 7.0, 0, q.y)
		if g.world.is_blocked(out.x, out.z) or not g.world.los(Vector3(q.x + 0.8, 0, q.y), out):
			continue
		if tr == Vector2.INF or q.distance_to(Vector2(want.x, want.z)) < tr.distance_to(Vector2(want.x, want.z)):
			tr = q
	var trunk := Vector3(tr.x, 0, tr.y)
	# on the bark: just outside the trunk's footprint (the Reach's oaks are thicker than the moor's were)
	var bark := 0.45
	for o in g.world.obstacles:
		if float(o[1]) > 0.0 and (o[0] as Vector2).distance_to(tr) < 0.05:
			bark = float(o[1]) + 0.05
	for i in 3:
		var a := TAU * i / 3.0
		var fe: Enemy = g.spawn_enemy("feral", trunk + Vector3(cos(a), 0, sin(a)) * bark, 3, false, "", 777)
		if fe:
			fe.perch_on(trunk, fe.global_position - trunk)
	await wait(0.3)
	var fs := _ferals()
	var packs := {}
	var perched := 0
	for e in fs:
		packs[e.pack_id] = int(packs.get(e.pack_id, 0)) + 1
		if e.perch_h > 0.0:
			perched += 1
	var anim_ok: bool = fs.size() > 0 and fs[0].rig.has_meta("feral")
	var vars := {}
	for e in fs:
		vars[e.rig.get_meta("variant", 0)] = int(vars.get(e.rig.get_meta("variant", 0), 0)) + 1
	print("[F] models in use: ", vars)
	print("[F] ferals %d in %d packs %s, perched %d, up %.1f m, baked animations %s" % [fs.size(), packs.size(), packs.values(), perched,
		(fs[0].global_position.y - g.world.height_at(fs[0].global_position.x, fs[0].global_position.z)) if fs.size() > 0 else 0.0, anim_ok])
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
