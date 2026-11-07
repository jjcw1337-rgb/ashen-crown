extends SceneTree
var DS = null      # Doug (his kit), loaded at run time (a static reference compiles its Sfx before the autoload)
## Doug's skills (game/heroes/doug/, his skill objects), one by one beside a pack of zombies: the pie flies, lands on the nearest and Pies
## it (stunned and slowed); peels land and a monster that walks onto one slips (stunned); the slide carries him ~7 m
## and strikes what's in the way; Doppel-Doug hides him (hidden_t) and a double runs off; the pins strike several;
## the bounce lands him at the cursor and launches those round him; the clown car speeds him up, rams, and its six
## mini clowns pie the nearest. Every skill's data follows the PoE rules (skill_spec_test checks those).
## Run: godot --headless --path . --fixed-fps 60 -s tools/_late.gd -- res://game/heroes/doug/tests/doug_test.gd
var g
var fails := 0
func _initialize():
	DS = load("res://game/heroes/doug/doug.gd")
	g = (load("res://main.tscn") as PackedScene).instantiate()
	get_root().add_child(g)
	_run()
func check(ok: bool, what: String) -> void:
	print("[D] ", "ok   " if ok else "FAIL ", what)
	if not ok:
		fails += 1
func secs(t: float) -> void:
	# game time, not the wall clock: headless with --fixed-fps 60 runs faster than real time
	for i in int(t * 60.0):
		await process_frame
func pack(at: Vector3, n: int) -> Array:
	for e in g.world.enemies_root.get_children():
		e.queue_free()
	await process_frame
	var out := []
	for i in n:
		var e = g.spawn_enemy("zombie", at + Vector3((i - n * 0.5) * 1.3, 0, randf_range(-0.4, 0.4)), 1)
		e.max_life = 5000.0
		e.life = 5000.0
		e.speed = 0.0          # they stand where they're put: a lobbed pie is a skill shot, and a hit reaction would stop his next cast
		out.append(e)
	return out
func cast(id: String, aim: Vector3) -> void:
	var h = g.hero
	# the last move finished first (hitstop on a hit slows the game's time, so a frame count can come up short)
	var n := 0
	while h.atk_skill != "" and n < 600:
		await process_frame
		n += 1
	for k in h.cds.keys():
		h.cds[k] = 0.0
	h.mana = h.max_mana
	var ok = h.use_skill(id, aim)
	if not ok:
		print("[D] (", id, " not cast: atk ", h.atk_skill, " at ", h.atk_t, " of ", h.atk_dur, " can_act ", h.can_act(), " stun ", h.get("daze_t"), ")")
func _run() -> void:
	while g.world == null or g._busy:
		await process_frame
	await g.start_game(false, "doug")
	g.ui.close_all()
	await g.travel(0, "sandbox", "start")
	while g._busy:
		await process_frame
	var h = g.hero
	h.set_level(20)
	g.test_immortal = true
	check(h.cls == "doug" and h.rig.has_meta("doug"), "Doug's body")
	check(str(h.binds.get("rmb", "")) == "pie" and str(h.binds.get("Q", "")) == "peels" and str(h.binds.get("V", "")) == "car", "the pie on the right mouse, peels..car on Q..V (%s)" % str(h.binds))
	var at: Vector3 = h.global_position + Vector3(0, 0, -6)
	h._face(Vector3(0, 0, -1))
	# pie
	var en := await pack(at, 3)
	var l0: float = en[1].life
	await cast("pie", en[1].global_position)
	await secs(1.6)
	check(en[1].life < l0, "the pie hit the one it was thrown at (%d)" % int(l0 - en[1].life))
	check(en[1].stun_t > 0.0 or en[1].slow_t > 0.0, "and Pied it (stunned or slowed)")
	# peels
	en = await pack(h.global_position + Vector3(0, 0, -14), 1)
	h._face(Vector3(0, 0, -1))
	await cast("peels", h.global_position + Vector3(0, 0, -5))
	await secs(1.0)
	var peels: Array = DS.skill(h, "peels").peels
	check(peels.size() == 3, "three peels down")
	if peels.is_empty():
		print("[D] done, %d failed" % fails)
		quit()
		return
	var p0: Vector3 = peels[0]["p"]
	en[0].global_position = p0 + Vector3(0.3, 0, 0)
	en[0].stun_t = 0.0
	await secs(0.3)
	check(en[0].stun_t > 0.0 and peels.size() == 2, "a monster stepped on one and slipped")
	# slide
	en = await pack(h.global_position + Vector3(0, 0, -4), 1)
	var start: Vector3 = h.global_position
	h._face(Vector3(0, 0, -1))
	l0 = en[0].life
	await cast("slide", h.global_position + Vector3(0, 0, -7))
	await secs(1.2)
	check(h.global_position.distance_to(start) > 4.5, "slid %.1f m" % h.global_position.distance_to(start))
	check(en[0].life < l0, "and struck the one in the way")
	# doppel
	en = await pack(h.global_position + Vector3(0, 0, -5), 2)
	for e in en:
		e.aggro = true
	await cast("doppel", h.global_position + Vector3(8, 0, 0))
	await secs(0.6)
	check(h.hidden_t > 0.0, "Doppel-Doug: hidden (%.1f s)" % h.hidden_t)
	check(not DS.skill(h, "doppel").double.is_empty() or h.fxs.has("double"), "and a double runs off")
	await secs(1.0)
	check(not en[0].aggro or not en[1].aggro, "the monsters lost him")
	await secs(1.5)
	# juggle
	en = await pack(h.global_position + Vector3(0, 0, -6), 4)
	var lives0: Array = en.map(func(e): return e.life)
	await cast("juggle", en[1].global_position)
	await secs(2.4)
	var struck := 0
	for i in en.size():
		if en[i].life < lives0[i]:
			struck += 1
	check(struck >= 2, "the pins struck %d of them" % struck)
	# bounce
	en = await pack(h.global_position + Vector3(0, 0, -8), 3)
	var to: Vector3 = h.global_position + Vector3(0, 0, -8)
	await cast("bounce", to)
	await secs(1.9)
	check(Vector2(h.global_position.x - to.x, h.global_position.z - to.z).length() < 2.5, "bounced to the cursor (%.1f m off)" % Vector2(h.global_position.x - to.x, h.global_position.z - to.z).length())
	check(en.any(func(e): return e.stun_t > 0.0 or e.life < 5000.0), "and the belly-flop hit those round him")
	# car
	en = await pack(h.global_position + Vector3(0, 0, -5), 6)
	await cast("car", h.global_position)
	await secs(0.8)
	check(DS.unstoppable(h) and DS.pace(h) > 1.5, "driving the clown car (x%.1f)" % DS.pace(h))
	await secs(5.0)
	check(not DS.unstoppable(h), "it ended")
	check(en.filter(func(e): return e.life < 5000.0).size() >= 4, "the mini clowns pied the nearest (%d hit)" % en.filter(func(e): return e.life < 5000.0).size())
	print("[D] done, %d failed" % fails)
	quit()
