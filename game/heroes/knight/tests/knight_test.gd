extends SceneTree
## The Knight on the hero template (knight_skills.gd): every skill of his is a Skill object in his kit, reading its
## numbers from his codex; his rules make what they act on through Skill.make and the server checks it (server_ok);
## his stuns go to players through the server; Holy Brands mark and Judgment spends them, their look an event; Aegis's
## ward bursts for what it soaked; Charge's Relentless and Last Rites' kill come back through Skill.give; his bodies
## build. Damage numbers are the reference's (tools/hero_reference.gd knight). Prints [K] lines.
## Through tools/_late.gd: godot --headless --path . -s tools/_late.gd -- res://game/heroes/knight/tests/knight_test.gd
var g
var fails := 0

func _initialize():
	g = (load("res://main.tscn") as PackedScene).instantiate()
	get_root().add_child(g)
	_run()

func check(ok: bool, what: String) -> void:
	if not ok:
		fails += 1
	print("[K] %s %s" % ["ok  " if ok else "FAIL", what])

func wait(s: float) -> void:
	await create_timer(s).timeout

func _foe(h, off: Vector3, life := 5000.0) -> Enemy:
	var p: Vector3 = h.global_position + off
	p.y = g.world.height_at(p.x, p.z)
	var e: Enemy = g.spawn_enemy("zombie", p, 5, false, "", 0)
	e.max_life = life
	e.life = life
	e.scripted = true
	return e

func _clear() -> void:
	for e in g.world.enemies_root.get_children():
		e.queue_free()
	await process_frame

func _cast(h, id: String, at: Vector3, secs := 1.6) -> bool:
	for k in h.cds.keys():
		h.cds[k] = 0.0
	h.mana = h.max_mana
	h.atk_t = -1.0
	var ok: bool = h.use_skill(id, at)
	await wait(secs)
	return ok

func _run() -> void:
	while g.world == null or g._busy:
		g._intro_skip = true
		await process_frame
	await g.start_game(false, "knight")
	g.test_immortal = true
	g.test_allskills = true
	await g.load_zone(0, "bg", "start")
	await _clear()
	var h = g.hero
	h.start_run()
	h.set_level(12)
	h.run_changed()
	var ids := ["cleave", "nova", "charge", "cry", "k_whirl", "k_aegis", "k_judgment", "k_rites"]
	for id in ids:
		if Data.run_skills_for("knight").any(func(s): return s["id"] == id) and not h.run.skills.has(id):
			h.run.skills.append(id)
	# his kit: one object per skill, every one of his a KnightSkill with its numbers in the codex
	var m = ClassSkills.of("knight")
	var kinds := {}
	for id in ids:
		var s = m.skill(h, id)
		kinds[id] = s.get_script().get_global_name() if s != null else "none"
	check(ids.all(func(id): return h.kit.has(id) and h.kit[id] is KnightSkill), "every skill of his is an object in his kit (%s)" % str(kinds))
	check(ids.all(func(id): return Data.skill_def(id).get("k", {}) is Dictionary and not (Data.skill_def(id).get("k", {}) as Dictionary).is_empty()), "every one has its numbers in his codex (\"k\")")
	check(is_equal_approx(h.kit["cleave"].val("dmg", -1.0), 160.0) and is_equal_approx(Skill.num("k_judgment", "brand_max", -1.0), 5.0), "and reads them (Holy Slam 160%, brands up to 5)")
	check(ServerRules.CLASSES.has("knight"), "his skills run on the match server (ServerRules.CLASSES)")
	# the server's checks: what his game says it made must be near where the server has him, within his numbers
	var p0: Vector3 = h.global_position
	check(h.kit["cleave"].server_ok("slam", {"p": p0 + Vector3(3, 0, 0)}) and not h.kit["cleave"].server_ok("slam", {"p": p0 + Vector3(40, 0, 0)}), "the server takes a slam within a leap of him, not one 40 m off")
	check(not h.kit["nova"].server_ok("nova", {"p": p0 + Vector3(20, 0, 0)}) and not h.kit["cry"].server_ok("cry", {}), "nor a nova far from him, nor a cry with no place")
	var wd := {"n": 99}
	check(h.kit["k_whirl"].server_ok("whirl", wd) and int(wd["n"]) == 2, "Blade Storm's turns are held to his build's (asked 99, made %d)" % int(wd["n"]))
	var bd := {"p": p0, "x": 1e9}
	check(h.kit["k_aegis"].server_ok("burst", bd) and float(bd["x"]) < h.max_life * 2.0, "Aegis's burst no bigger than his ward could soak (%.0f)" % float(bd["x"]))
	var dd := {"p": p0, "d": Vector3(3, 0, 4)}
	check(h.kit["charge"].server_ok("dash", dd) and is_equal_approx((dd["d"] as Vector3).length(), 1.0) and not h.kit["charge"].server_ok("dash", {"p": p0, "d": Vector3.ZERO}), "a dash's way is made a direction; none is refused")
	check(h.kit["k_judgment"].server_ok("pillar", {"g": p0 + Vector3(12, 0, 0)}) and not h.kit["k_judgment"].server_ok("pillar", {"g": p0 + Vector3(30, 0, 0)}), "a pillar within his reach, not past it")
	# Holy Slam: the blow lands where the blade comes down, stunning (a monster here; a player: through the server)
	await _clear()
	var e1 := _foe(h, Vector3(4, 0, 0))
	h._face(Vector3(1, 0, 0))
	var ok := await _cast(h, "cleave", e1.global_position, 1.4)
	check(ok and e1.life < e1.max_life and e1.stun_t > 0.0, "Holy Slam leaps on the foe, hits and stuns it (%.0f, stun %.1f)" % [e1.max_life - e1.life, e1.stun_t])
	check(is_zero_approx(h.kit["cleave"].reach - 1.25) or h.kit["cleave"].reach <= 1.25, "and its blade lands at most 1.25 m ahead of him")
	# Holy Brands: blows of a run knight with Judgment brand; their look is an event, once while it shows
	await _clear()
	var shown := [0]
	g.net.fx_tap = func(w: Dictionary):
		if str(w.get("s", "")) == "k_judgment" and str(w.get("e", "")) == "brand":
			shown[0] += 1
	var e2 := _foe(h, Vector3(2, 0, 0))
	for i in 3:
		h._hit_enemy(e2, 0.1, 0.0, "attack")
	check(HolyBrands.count(e2) == 3 and shown[0] == 1, "three blows: three Holy Brands on the foe, its look sent once (%d brands, %d looks)" % [HolyBrands.count(e2), shown[0]])
	for i in 6:
		h._hit_enemy(e2, 0.1, 0.0, "attack")
	check(HolyBrands.count(e2) == 5, "no more than five (%d)" % HolyBrands.count(e2))
	var l2: float = e2.life
	ok = await _cast(h, "k_judgment", e2.global_position, 1.6)
	check(ok and HolyBrands.count(e2) == 0 and e2.life < l2 and e2.burn_t > 0.0, "Judgment spends them, strikes and sets it burning (%.0f)" % (l2 - e2.life))
	g.net.fx_tap = Callable()
	# Charge: the rules' dash strikes each once; Relentless's time comes back through give
	await _clear()
	var e3 := _foe(h, Vector3(3, 0, 0))
	var e4 := _foe(h, Vector3(5.5, 0, 0.3))
	h.tfx["charge_cdr"] = 1.0
	h.cds["nova"] = 5.0
	h.mana = h.max_mana
	ok = h.use_skill("charge", h.global_position + Vector3(9, 0, 0))
	await wait(0.8)
	h.tfx.erase("charge_cdr")
	check(ok and e3.life < e3.max_life and e4.life < e4.max_life and e3.stun_t > 0.0 and h.kit["charge"].run.is_empty() and h.charge_t < 0.0, "Charge smashes both in the way, stuns them, and ends")
	check(h.cds.get("nova", 5.0) < 4.0, "Relentless: each one smashed took time off his other cooldowns (Holy Nova %.1f s)" % h.cds.get("nova", 5.0))
	# Battle Cry: his battle buff here, everything near stunned
	await _clear()
	var e5 := _foe(h, Vector3(3, 0, 0))
	h.buff_t = 0.0
	ok = await _cast(h, "cry", h.global_position, 0.9)
	check(ok and h.buff_t > 10.0 and e5.stun_t > 1.0, "Battle Cry: his battle buff (%.1f s) and the foe near stunned (%.1f s)" % [h.buff_t, e5.stun_t])
	# Aegis: the ward on his own game; struck, it bursts for what it soaked
	await _clear()
	var e6 := _foe(h, Vector3(2.5, 0, 0))
	ok = await _cast(h, "k_aegis", h.global_position, 0.8)
	var w0: float = h.ward
	check(ok and w0 > h.max_life * 0.3 and e6.taunt == h, "Aegis: a ward of a third of his life (%.0f of %.0f) and the foe turns on him" % [w0, h.max_life])
	var l6: float = e6.life
	g.test_immortal = false       # (a real blow, past the ward: his life is full and the ward takes most of it)
	h.life = h.max_life
	h.take_hit(w0 * 1.6 + 20.0, e6.global_position, "melee")
	g.test_immortal = true
	await wait(0.3)
	check(h.kit["k_aegis"].held.is_empty() and e6.life < l6, "broken, it bursts on the foe for what it soaked (%.0f)" % (l6 - e6.life))
	# Last Rites: a kill readies it again
	await _clear()
	var e7 := _foe(h, Vector3(4, 0, 0), 30.0)
	h._face(Vector3(1, 0, 0))
	ok = await _cast(h, "k_rites", e7.global_position, 1.3)
	check(ok and e7.dead and is_zero_approx(float(h.cds.get("k_rites", 1.0))), "Last Rites: the kill makes it ready again (cooldown %.1f)" % float(h.cds.get("k_rites", 1.0)))
	# Blade Storm: two turns, a beat apart
	await _clear()
	var e8 := _foe(h, Vector3(2, 0, 0))
	ok = await _cast(h, "k_whirl", h.global_position, 0.0)
	var hits := 0
	var last: float = e8.life
	for i in 120:
		await process_frame
		if e8.life < last:
			hits += 1
			last = e8.life
	check(ok and hits == 2, "Blade Storm strikes all round, then again a beat later (%d blows, %.0f)" % [hits, e8.max_life - e8.life])
	# his bodies: the crusader on the mocap skeleton builds where its model loads; the shared procedural body anywhere
	var mb: Node3D = KnightBody.build_mocap()
	check(mb != null and mb.has_meta("j") and str(mb.get_meta("meshy")) == "mocap", "his mocap body builds (KnightBody: the crusader on the shared builder)")
	mb.free()
	var pb: Node3D = Knight.build(Knight.default_gear())
	check(pb != null and pb.has_meta("j"), "the shared procedural body builds")
	pb.free()
	print("[K] done, %d failed" % fails)
	quit()
