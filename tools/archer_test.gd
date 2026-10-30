extends SceneTree
## The archer (archer.gd): starts with a bow and shoots from range (an arrow, not a swing); Piercing Shot goes
## through a line; Volley rains on an area; Snare Trap holds the first enemy on it; Spirit Beast hunts beside
## him; only he can use bows; his talents and the class picker. Prints [A] lines.
var g
var fails := 0

func _initialize():
	g = (load("res://main.tscn") as PackedScene).instantiate()
	get_root().add_child(g)
	_run()

func check(ok: bool, what: String) -> void:
	if not ok:
		fails += 1
	print("[A] %s %s" % ["ok  " if ok else "FAIL", what])

func wait(s: float) -> void:
	await create_timer(s).timeout

func _foe(at: Vector3) -> Enemy:
	var e: Enemy = g.spawn_enemy("zombie", at, 3)
	e.set_process(false)          # a target that stands still
	return e

func _run() -> void:
	while g.world == null or g._busy:
		g._intro_skip = true
		await process_frame
	await g.start_game(false, "archer")
	g.test_immortal = true
	await g.load_zone(0, "wild", "start")
	for e in g.world.enemies_root.get_children():
		e.queue_free()
	await process_frame
	var h = g.hero
	h.level = 12
	h.recalc()
	h.mana = h.max_mana
	check(h.cls == "archer" and h.has_bow() and h.equipment["weapon"]["base"] == "short_bow", "a new archer has his Short Bow")
	check(h.reach() > 10.0, "he attacks from range (%.0f m)" % h.reach())
	var fwd: Vector3 = -h.rig.global_transform.basis.z
	var p0: Vector3 = h.global_position
	# a plain shot at a foe 9 m off: an arrow flies and hits
	var e1 := _foe(g.world.free_spot_near(p0 + fwd * 9.0, 1.0))
	var l1: float = e1.life
	h.swipe_attack(e1.global_position)
	var flew := false
	for i in 60:
		await process_frame
		flew = flew or not h.arrows.is_empty()
	check(flew and e1.life < l1, "the bow shot: an arrow flew 9 m and hit (%.0f -> %.0f)" % [l1, e1.life])
	e1.take_damage(99999.0, 0.0, p0, 0.0, false)
	# Piercing Shot through three in a line
	# his wolf waits this part out, so only his arrows hit
	for b in h.beasts:
		b.queue_free()
	h.beasts.clear()
	h.beast_down_t = 9999.0
	var line := []
	for k in 3:
		line.append(_foe(p0 + fwd * (5.0 + k * 2.5)))
	var lives := line.map(func(e): return e.life)
	h.cds["pierce"] = 0.0
	h.use_skill("pierce", p0 + fwd * 12.0)
	for i in 70:
		await process_frame
	var pierced := 0
	for k in 3:
		if line[k].life < lives[k]:
			pierced += 1
	check(pierced == 3, "Fire Arrow went through all three in a line (%d hit)" % pierced)
	check(line.all(func(e) -> bool: return e.burn_t > 0.0), "and set them all alight (burning %s)" % [line.map(func(e): return snappedf(e.burn_t, 0.1))])
	for e in line:
		e.take_damage(99999.0, 0.0, p0, 0.0, false)
	# Volley: everything in the ring takes several hits
	var at: Vector3 = p0 + fwd * 8.0
	var pack := []
	for k in 3:
		pack.append(_foe(at + Vector3(cos(k * 2.1), 0, sin(k * 2.1)) * 2.0))
	var lv := pack.map(func(e): return e.life)
	h.cds["volley"] = 0.0
	h.mana = h.max_mana
	h.use_skill("volley", at)
	await wait(2.0)
	var rained := 0
	for k in 3:
		if pack[k].life < lv[k]:
			rained += 1
	check(rained == 3, "Frost Volley rained on all three (%d hit)" % rained)
	check(pack.all(func(e) -> bool: return e.chill_t > 0.0 and e.chill_k > 0.3), "and chilled them (%.0f%% slower)" % (pack[0].chill_k * 100.0))
	for e in pack:
		e.take_damage(99999.0, 0.0, p0, 0.0, false)
	# Snare Trap: set, an enemy walks on, it's held fast
	h.cds["snare"] = 0.0
	h.mana = h.max_mana
	var trap_at: Vector3 = p0 + fwd * 6.0
	h.use_skill("snare", trap_at)
	await wait(0.6)
	var set_ok: bool = h.snares.size() == 1
	var e2 := _foe(trap_at + Vector3(3, 0, 0))
	var l2: float = e2.life
	var by := _foe(trap_at + Vector3(-4.0, 0, 1.0))
	var lb: float = by.life
	e2.global_position = trap_at
	await wait(0.3)
	check(set_ok and h.snares.is_empty() and e2.stun_t > 2.0 and e2.life < l2, "Snare Trap: set, sprung by the enemy on it (held %.1f s, hurt %s)" % [e2.stun_t, e2.life < l2])
	check(by.life < lb and by.stun_t > 0.0, "Storm Snare's lightning leapt into one nearby (hurt, stunned %.1f s)" % by.stun_t)
	e2.take_damage(99999.0, 0.0, p0, 0.0, false)
	by.take_damage(99999.0, 0.0, p0, 0.0, false)
	h.beast_down_t = 0.0
	await wait(0.3)
	# Spirit Beast: it comes, mauls a foe, and the buff is on
	h.cds["beast"] = 0.0
	h.mana = h.max_mana
	h.use_skill("beast", p0)
	await wait(0.9)
	var e3 := _foe(p0 + fwd * 4.0)
	var l3: float = e3.life
	await wait(3.0)
	check(h.beasts.size() == 1 and h.buff_t > 0.0 and e3.life < l3, "Spirit Beast: out, hunting (foe %.0f -> %.0f), +damage buff %.1f s" % [l3, e3.life, h.buff_t])
	# bows are his alone
	await g.start_game(false, "knight")
	g.hero.inventory[0] = Items.make("long_bow", 0, 1)
	g.hero.equip_from_inventory(0)
	check(g.hero.equipment["weapon"]["base"] != "long_bow", "a knight can't draw a bow")
	# talents and the class picker
	check(Talents.trees("archer").size() == 3 and Talents.AUTO["archer"].size() == 21, "three talent trees, an auto build of 21")
	print("[A] done, %d failed" % fails)
	quit()
