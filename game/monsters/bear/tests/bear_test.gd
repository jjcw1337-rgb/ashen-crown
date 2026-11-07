extends SceneTree
## The Forsaken Bear (bear.gd, BearBrain): one stands in a Verdant Reach camp; one put in a glade of the Verdant
## Reach (nothing else about) wanders its home ground and rears up to roar now and then; it notices a hero, roars once, charges,
## mauls (damage and a knockback); led more than 30 m from home it gives up and goes back. Prints [B] lines.
var g
var fails := 0

func _initialize():
	g = (load("res://main.tscn") as PackedScene).instantiate()
	get_root().add_child(g)
	_run()

func wait(s: float) -> void:
	await create_timer(s).timeout

func check(ok: bool, what: String) -> void:
	if not ok:
		fails += 1
	print("[B] %s %s" % ["ok  " if ok else "FAIL", what])

func _bears() -> Array:
	return g.world.enemies_root.get_children().filter(func(e) -> bool: return e is Enemy and e.kind == "bear" and not e.dead)

## Puts the hero at p on the ground.
func _place(p: Vector3) -> void:
	g.hero.global_position = Vector3(p.x, g.world.height_at(p.x, p.z), p.z)
	g.cam_target = g.hero.global_position

func _run() -> void:
	while g.world == null or g._busy:
		g._intro_skip = true
		await process_frame
	# no shield: a knight's passive block can take a maul whole
	await g.start_game(false, "demon")
	check(BgForest.CAMPS.any(func(c): return (c["foes"] as Array).any(func(f): return str(f["kind"]) == "bear")), "a bear stands in one of the Verdant Reach's camps")
	await g.load_zone(0, Battlegrounds.ZONE, "start")
	await wait(0.5)
	for e in g.world.enemies_root.get_children():
		e.free()
	var st: Vector3 = g.world.spawns["start"]
	g.spawn_enemy("bear", g.world.free_spot_near(st + (Vector3.ZERO - st).normalized() * 30.0, 3.0), 5, false, "", 901)
	await wait(0.3)
	var bs := _bears()
	check(bs.size() == 1, "a bear in a glade of the Verdant Reach (%d)" % bs.size())
	check(bs.size() > 0 and bs[0].rig.has_meta("bear"), "the Meshy bear body")
	if bs.is_empty():
		print("[B] done, %d failed" % fails)
		quit()
		return
	var b: Enemy = bs[0]
	# everything else stays put so nothing interferes
	for e in g.world.enemies_root.get_children():
		if e is Enemy and e != b:
			e.set_process(false)
	# idle: the hero far away; it wanders inside its ground and rears up to roar
	_place(b.home + Vector3(0, 0, 45))
	g.hero.set_process(false)
	b.b_idle_t = 2.0
	var far := 0.0
	var moved := 0.0
	var roared := false
	var last := b.global_position
	var t := 0.0
	while t < 24.0:
		await wait(0.1)
		t += 0.1
		moved += b.global_position.distance_to(last)
		last = b.global_position
		far = maxf(far, b.global_position.distance_to(b.home))
		if b.special == "bear_roar":
			roared = true
		# its roar timer, brought forward while it stands still (in play it's every 14-26 s)
		if not roared and b.move_amt < 0.3 and b.b_idle_t > 0.5 and t > 3.0:
			b.b_idle_t = 0.05
	check(moved > 1.0 and far < 13.0, "wanders its ground: walked %.1f m, at most %.1f m from home" % [moved, far])
	check(roared, "rears up and roars while wandering")
	# a hero comes near: it roars once, charges, mauls
	g.hero.set_process(true)
	g.hero.set_level(20)
	g.test_immortal = false
	b.special = ""
	b.atk_t = -1.0
	await wait(1.6)
	var to_b: Vector3 = b.global_position - b.home
	to_b.y = 0
	# 7 m off, on open ground it can see
	var spot: Vector3 = b.global_position + Vector3(7.0, 0, 0)
	for k in 16:
		var a: float = TAU * k / 16.0
		var q: Vector3 = b.global_position + Vector3(cos(a), 0, sin(a)) * 7.0
		if not g.world.is_blocked(q.x, q.z) and g.world.los(b.global_position, q):
			spot = q
			break
	_place(spot)
	var life0: float = g.hero.life
	var noticed := false
	var roar_first := false
	var mauls := 0
	var knocked := 0.0
	var was_maul := false
	t = 0.0
	while t < 14.0 and mauls < 2:
		await wait(0.05)
		t += 0.05
		if b.aggro and not noticed:
			noticed = true
			roar_first = b.special == "bear_roar" or b.b_roared
		var m: bool = b.special == "bear_maul"
		if m and not was_maul:
			mauls += 1
		was_maul = m
		knocked = maxf(knocked, g.hero.knock_v.length())
		# the hero stands still and lets it come
		g.hero.global_position.y = g.world.height_at(g.hero.global_position.x, g.hero.global_position.z)
	check(noticed and roar_first, "notices the hero and roars first")
	check(mauls >= 1, "charges in and mauls (%d mauls in %.1f s)" % [mauls, t])
	check(g.hero.life < life0, "the maul hurts: life %.0f -> %.0f" % [life0, g.hero.life])
	check(knocked > 2.0, "and throws the hero back (knock %.1f m/s)" % knocked)
	# led away: the fight has dragged it 32 m from home (put there, with the hero beside it): it gives up
	g.test_immortal = true
	var away: Vector3 = g.world.free_spot_near(b.home + Vector3(32.0, 0, 0), 3.0)
	for k in 16:
		var q: Vector3 = b.home + Vector3(cos(TAU * k / 16.0), 0, sin(TAU * k / 16.0)) * 32.0
		if not g.world.is_blocked(q.x, q.z):
			away = q
			break
	b.global_position = Vector3(away.x, g.world.height_at(away.x, away.z), away.z)
	_place(away + Vector3(2.0, 0, 0))
	b.aggro = true
	b.b_roared = true
	var gave_up := false
	var dmax: float = b.global_position.distance_to(b.home)
	t = 0.0
	while t < 3.0 and not gave_up:
		await wait(0.1)
		t += 0.1
		if not b.aggro:
			gave_up = true
	# and walks off, leaving the hero standing there
	_place(away + Vector3(6.0, 0, 6.0))
	var d_out := b.global_position.distance_to(b.home)
	await wait(6.0)
	var d_back := b.global_position.distance_to(b.home)
	check(gave_up, "gives up when led %.0f m from home (after %.1f s)" % [dmax, t])
	check(d_back < d_out - 3.0, "and heads home: %.0f m -> %.0f m" % [d_out, d_back])
	print("[B] done, %d failed" % fails)
	quit()
