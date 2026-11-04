extends SceneTree
## The Act I camp's guards (CampGuard): all three on their rounds with every clip and three attack slots, they move,
## one stops and turns to watch a hero walking up, and they fight a zombie loose in the camp (host: their blows
## land). Prints [G] lines. Run: godot --headless --path . -s tools/_late.gd -- res://tools/guard_test.gd
var g
var fails := 0

func _initialize():
	g = (load("res://main.tscn") as PackedScene).instantiate()
	get_root().add_child(g)
	_run()

func _ok(cond: bool, what: String) -> void:
	print("[G] %s %s" % ["ok  " if cond else "FAIL", what])
	if not cond:
		fails += 1

func _guards() -> Array:
	var out := []
	for c in g.world.props_root.get_children():
		if c is CampGuard:
			out.append(c)
	return out

func _run() -> void:
	while g.world == null or g._busy:
		g._intro_skip = true
		await process_frame
	await g.start_game(false, "knight")
	g.ui.close_all()
	while g._busy:
		await process_frame
	var gs := _guards()
	_ok(gs.size() == 3, "three guards in the camp (%d)" % gs.size())
	if gs.is_empty():
		quit(1)
		return
	var need := ["idle", "walk", "run", "combat_idle", "walk_fight", "walk_fight_back", "strafe_l", "strafe_r", "turn_l",
		"turn_r", "turn_l_combat", "turn_r_alert", "walk_turn_l", "walk_turn_r", "look", "look_long", "alert", "warmup",
		"extra", "walk_look", "walk_back", "hit", "death", "strike_1", "strike_2", "strike_3"]
	for gd in gs:
		var guard: CampGuard = gd
		var miss := []
		for c in need:
			if not guard.anim.has_animation(c):
				miss.append(c)
		_ok(miss.is_empty(), "%s has every clip %s" % [guard.def["id"], "" if miss.is_empty() else str(miss)])
		_ok((guard.def["slots"] as Array).size() == 3, "%s has three attack slots" % guard.def["id"])
		var shadows := true
		for n in guard.model.find_children("*", "GeometryInstance3D", true, false):
			if (n as GeometryInstance3D).cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF:
				shadows = false
		_ok(shadows, "%s casts shadows" % guard.def["id"])
		_ok(guard.head != null, "%s turns his head (HeadLook)" % guard.def["id"])
	# the hero out of the way: they walk their rounds
	g.hero.global_position = Vector3(0, 0, 40)
	var p0 := {}
	for gd in gs:
		p0[gd] = (gd as CampGuard).global_position
	var seen := {}
	for i in 600:
		await process_frame
		for gd in gs:
			seen[(gd as CampGuard).clip] = true
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 25000:
		await create_timer(0.1).timeout
		for gd in gs:
			seen[(gd as CampGuard).clip] = true
	var moved := 0
	for gd in gs:
		if (gd as CampGuard).global_position.distance_to(p0[gd]) > 1.5 or (gd as CampGuard).post_i != 0:
			moved += 1
	_ok(moved >= 2, "they walk their rounds (%d of 3 moved in 25 s); clips seen %s" % [moved, str(seen.keys())])
	var inside := true
	for gd in gs:
		var gp: Vector3 = (gd as CampGuard).global_position
		if Vector2(gp.x, gp.z).distance_to(ForestCamp.CENTER) > ForestCamp.RADIUS - 1.0:
			inside = false
	_ok(inside, "they stay inside the palisade")
	# a hero walking up to one: he stops and watches
	var w: CampGuard = gs[0]
	w.watch_cd = 0.0
	w.state = "post"
	w.turn_t = -1.0
	var back := Vector3(sin(w.yaw + PI), 0, cos(w.yaw + PI)) * 4.0
	g.hero.global_position = g.world.free_spot_near(w.global_position + back, 0.4)
	var watched := false
	for i in 30:
		await create_timer(0.1).timeout
		if w.state == "watch":
			watched = true
			break
	_ok(watched, "%s stops to watch a hero walking up behind him" % w.def["id"])
	await create_timer(2.5).timeout
	var hp: Vector3 = g.hero.global_position
	var face := Vector3(sin(w.yaw), 0, cos(w.yaw))
	var to := (hp - w.global_position)
	to.y = 0
	_ok(face.dot(to.normalized()) > 0.6, "... and turns to face them (%.2f)" % face.dot(to.normalized()))
	# the head waits for the turn about to finish before it takes the hero up
	for i in 20:
		if w.head.amount > 0.5:
			break
		await create_timer(0.1).timeout
	_ok(w.head.amount > 0.5, "... and follows them with his head (%.2f)" % w.head.amount)
	# a zombie loose in the camp: the nearest guard fights it
	g.hero.global_position = Vector3(0, 0, 40)
	var s: CampGuard = gs[2]
	var zp: Vector3 = g.world.free_spot_near(s.global_position + Vector3(3.0, 0, 0), 0.5)
	var z: Enemy = g.spawn_enemy("zombie", zp, 3)
	_ok(z != null, "a zombie in the camp")
	if z != null:
		var l0 := z.life
		var fought := false
		var struck := {}
		for i in 300:
			await create_timer(0.1).timeout
			for gd in gs:
				var guard: CampGuard = gd
				if guard.state == "fight":
					fought = true
				if guard.clip.begins_with("strike") or guard.clip.begins_with("strafe") or guard.clip == "walk_fight_back":
					struck[guard.clip] = true
			if not is_instance_valid(z) or z.dead:
				break
		_ok(fought, "a guard goes for it")
		_ok(not is_instance_valid(z) or z.dead or z.life < l0, "his blows land (%s)" % ("dead" if not is_instance_valid(z) or z.dead else "%d of %d" % [z.life, l0]))
		_ok(struck.size() >= 2, "he fights with his slots and footwork %s" % str(struck.keys()))
		await create_timer(3.0).timeout
		var back_on := 0
		for gd in gs:
			if (gd as CampGuard).state != "fight":
				back_on += 1
		_ok(back_on == 3, "back on their rounds once it's dead")
	print("[G] done, %d failed" % fails)
	quit(1 if fails > 0 else 0)
