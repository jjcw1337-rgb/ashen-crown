extends SceneTree
## Wraith class: new game, every skill (cast, cooldown, mana, its effect and damage, no errors), Soul Siphon's
## tether and slow, Shadowstep's blink and mist, Haunting Grasp's hold, Phantom Assault's phantoms, Eternal Night's
## four stages, old saves' bindings carried over, save/load keeps the class, knight still works. Prints [W] lines.
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
	print("[W] %s %s" % ["ok  " if ok else "FAIL", what])
func lives(en: Array) -> float:
	var t := 0.0
	for e in en:
		if is_instance_valid(e):
			t += e.life
	return t
func foes(h) -> Array:
	return g.enemies_near(h.global_position, 12.0)
func pack(h, n: int, at: Vector3) -> Array:
	for e in g.enemies_near(h.global_position, 40.0):
		e.queue_free()
	await process_frame
	var out := []
	for i in n:
		var e = g.spawn_enemy("zombie", at + Vector3(-1.0 + i * 1.0, 0, 0), 18)     # tough enough to survive a blow at level 20
		e.aggro = false
		out.append(e)
	await process_frame
	return out
func _run() -> void:
	while g.world == null or g._busy:
		await process_frame
	await g.start_game(false, "wraith")
	var h = g.hero
	check(h.cls == "wraith" and h.rig.has_meta("wraith"), "class wraith on the mocap rig")
	var ids: Array = h.skill_list().map(func(s): return s["id"])
	check(ids == ["rend", "siphon", "step", "grasp", "phantom", "night"], "skills %s" % [ids])
	check(["Q", "E", "R", "F", "G", "V"].map(func(k): return h.bound(k)) == ids, "bound Q E R F G V")
	check(h.rig.get("shots") is Dictionary and (h.rig.get("shots") as Dictionary).has("night_fall"), "the rig has a clip per skill")
	print("[W] stats str %d dex %d vit %d ene %d life %d mana %d" % [h.str_, h.dex, h.vit, h.ene, h.max_life, h.max_mana])
	await g.travel(0, "wild", "start")
	while g._busy:
		await process_frame
	h.set_level(20)
	h.mana = h.max_mana
	g.test_immortal = true
	# --- Spectral Rend: the lunge, two rakes, the souls' healing
	var en: Array = await pack(h, 3, h.global_position + Vector3(0, 0, -3.5))
	h._face(Vector3(0, 0, -1))
	var p0: Vector3 = h.global_position
	var l0 := lives(en)
	h.life = h.max_life * 0.5
	var ok: bool = h.use_skill("rend", h.skill_aim("rend", en[1].global_position))
	await wait(0.5)
	check(ok and h.atk_skill == "rend" and h.atk_style == "rend", "Spectral Rend casts on its own clip")
	check(h.global_position.distance_to(p0) > 0.8, "it lunged %.2f m at the pack" % h.global_position.distance_to(p0))
	await wait(1.2)
	var d_rend := l0 - lives(en)
	check(d_rend > 0.0, "two rakes dealt %d" % int(d_rend))
	check(h.life > h.max_life * 0.5, "the souls healed him (%d of %d)" % [int(h.life), int(h.max_life)])
	check(h.wr.get("rend2", false) == true, "the second rake landed")
	# --- Soul Siphon: a tether on one foe, ticks, heals, slows, ends
	en = await pack(h, 1, h.global_position + Vector3(0, 0, -5.0))
	h._face(Vector3(0, 0, -1))
	h.mana = h.max_mana
	h.life = h.max_life * 0.5
	l0 = lives(en)
	ok = h.use_skill("siphon", h.skill_aim("siphon", en[0].global_position))
	await wait(0.9)
	check(ok and h.wr.has("tether") and h.wr["tether"]["victim"] == en[0], "Soul Siphon latched its tether")
	check(en[0].slow_t > 0.0 and en[0].slow_amt > 0.4, "the victim is slowed")
	check(h.cds["siphon"] > 0.0, "it is on cooldown (%.1f s)" % h.cds["siphon"])
	await wait(2.6)
	var d_sip := l0 - lives(en)
	check(d_sip > 0.0 and not h.wr.has("tether"), "it drained %d over its hold and let go" % int(d_sip))
	check(h.life > h.max_life * 0.5, "the drain healed him")
	check(h.use_skill("siphon", h.global_position + Vector3(0, 0, 40)) == false, "no foe in reach: it does not cast")
	# --- Shadowstep: the blink to the cursor, the mist, the strike, the shade
	en = await pack(h, 2, h.global_position + Vector3(0, 0, -6.0))
	h.cds["step"] = 0.0
	h.mana = h.max_mana
	p0 = h.global_position
	l0 = lives(en)
	ok = h.use_skill("step", en[0].global_position + Vector3(0.5, 0, 0.3))
	await wait(0.45)
	check(ok and h.global_position.distance_to(p0) > 3.0 and h.veil_t > 0.0, "Shadowstep blinked %.1f m and he is mist for %.2f s" % [h.global_position.distance_to(p0), h.veil_t])
	g.test_immortal = false
	var life_b: float = h.life
	h.take_hit(50.0, h.global_position + Vector3(1, 0, 0))
	check(is_equal_approx(h.life, life_b), "a blow passes through the mist")
	g.test_immortal = true
	await wait(1.0)
	check(lives(en) < l0, "the spin's strike and the shade hurt the pack (%d)" % int(l0 - lives(en)))
	check(h.veil_t <= 0.0, "the mist has gone")
	# --- Haunting Grasp: hands round the cursor, damage, held
	en = await pack(h, 3, h.global_position + Vector3(0, 0, -6.0))
	h.mana = h.max_mana
	l0 = lives(en)
	ok = h.use_skill("grasp", en[1].global_position)
	await wait(1.0)
	check(ok and lives(en) < l0, "Haunting Grasp seized the pack (%d)" % int(l0 - lives(en)))
	var held := 0
	for e in en:
		if is_instance_valid(e) and e.stun_t > 1.0:
			held += 1
	check(held >= 2, "%d of 3 are held" % held)
	await wait(0.6)
	# --- Phantom Assault: three phantoms down the line, each foe once each
	en = await pack(h, 3, h.global_position + Vector3(0, 0, -4.0))
	h._face(Vector3(0, 0, -1))
	h.mana = h.max_mana
	l0 = lives(en)
	ok = h.use_skill("phantom", h.skill_aim("phantom", en[1].global_position))
	await wait(0.45)
	check(ok and h.wr.has("phantoms") and (h.wr["phantoms"] as Array).size() == 3, "three phantoms split off him")
	await wait(1.4)
	check(lives(en) < l0 and not h.wr.has("phantoms"), "they tore through the pack (%d) and are gone" % int(l0 - lives(en)))
	# --- Eternal Night: four stages, the dark, the scream's fear, the ticks, the collapse, the buff
	en = await pack(h, 3, h.global_position + Vector3(0, 0, -3.0))
	h.mana = h.max_mana
	l0 = lives(en)
	ok = h.use_skill("night", h.global_position)
	await wait(0.3)
	check(ok and h.wr.has("night") and h.atk_style == "night_rise" and h.veil_t > 0.0, "Eternal Night: he rises, untouchable")
	check(float(h.rig.get("hover")) > 0.16 + 0.5, "he hangs high (hover %.2f)" % float(h.rig.get("hover")))
	var stages := {}
	for i in 120:
		await wait(0.05)
		if h.wr.has("night"):
			stages[h.atk_style] = true
		else:
			break
	check(stages.has("night_scream") and stages.has("night_hold") and stages.has("night_fall"), "it went through its stages %s" % [stages.keys()])
	await wait(1.0)
	check(not h.wr.has("night") and h.atk_t < 0.0, "and ended")
	check(lives(en) < l0 * 0.7, "the night fed on the pack (%d of %d)" % [int(l0 - lives(en)), int(l0)])
	check(h.buff_t > 5.0, "+40%% damage after (%.1f s)" % h.buff_t)
	check(is_equal_approx(float(h.rig.get("hover")), 0.16) and h.veil_t <= 0.0, "he is down and solid again")
	check(h.cds["night"] > 30.0, "its cooldown is long (%.0f s)" % h.cds["night"])
	# --- old saves: the old skill ids on the bar become the new ones
	var b := {"lmb": "attack", "rmb": "block", "Q": "reap", "E": "wail", "R": "shade", "F": "host", "G": "", "V": ""}
	(load("res://scripts/wraith_skills.gd") as GDScript).call("migrate_binds", b)    # loaded at run time: a static reference compiles it before Sfx exists
	check(b["Q"] == "rend" and b["E"] == "siphon" and b["R"] == "step" and b["F"] == "grasp", "old bindings migrate %s" % [b])
	var sv: Dictionary = h.to_save()
	sv["binds"] = {"lmb": "attack", "rmb": "block", "Q": "reap", "E": "wail", "R": "shade", "F": "host", "G": "", "V": ""}
	sv["talents"] = {"w_scythe": 3, "w_focus": 3, "w_harvest": 2}
	h.from_save(sv)
	check(h.bound("Q") == "rend" and h.bound("F") == "grasp" and h.talents.get("w_scythe", 0) == 3, "an old Wraith save loads with its bindings and talents")
	# --- the class survives save/load, the knight still works
	g.save_game()
	h.set_class("knight")
	check(not h.rig.has_meta("wraith") and h.wr.is_empty(), "switched to knight: nothing of the Wraith's lingers")
	g.load_game()
	check(h.cls == "wraith" and h.rig.has_meta("wraith"), "after load: wraith again")
	await g.start_game(false, "knight")
	check(h.cls == "knight" and h.level == 1, "new knight: level 1")
	print("[W] done, %d failed" % fails)
	quit()
