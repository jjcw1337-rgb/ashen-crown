extends SceneTree
## Demon class: his six skills (Molten Fists, Infernal Charge, Cataclysm Slam, Brimstone Hurl, Hellgrip, Wrath of
## the Pit) each dealing damage and leaving what they should, the old saves' bindings carried over, his talents,
## save/load and the class swap. Prints [D] lines ("FAIL" marks a check that failed).
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
	print("[D] %s %s" % ["ok  " if ok else "FAIL", what])
func lives(en: Array) -> float:
	var t := 0.0
	for e in en:
		if is_instance_valid(e):
			t += e.life
	return t
func pack(at: Vector3, n: int, lvl := 20) -> Array:
	for e in g.enemies_near(at, 80.0):
		e.queue_free()
	await process_frame
	var out := []
	for i in n:
		var e = g.spawn_enemy("zombie", at + Vector3(-1.0 + i * 1.0, 0, 0), lvl)
		e.aggro = false
		e.scripted = 99.0
		e.max_life = 5000.0
		e.life = 5000.0
		out.append(e)
	await process_frame
	return out
func _run() -> void:
	while g.world == null or g._busy:
		await process_frame
	await g.start_game(false, "demon")
	var h = g.hero
	print("[D] class ", h.cls, " demon rig ", h.rig.has_meta("demon"), " mocap ", str(h.rig.get_meta("meshy", "")), " skills ", h.skill_list().map(func(s): return s["id"]))
	check(h.skill_list().map(func(s): return s["id"]) == ["fists", "icharge", "cslam", "hurl", "grip", "wrath"], "six skills in order")
	print("[D] stats str %d dex %d vit %d ene %d life %d mana %d weapon %s" % [h.str_, h.dex, h.vit, h.ene, h.max_life, h.max_mana, h.equipment["weapon"]["name"]])
	await g.travel(0, "wild", "start")
	while g._busy:
		await process_frame
	h.set_level(20)
	h.recalc()
	g.test_immortal = true
	var home: Vector3 = h.global_position
	# Molten Fists: the wedge ahead is hit and set alight
	var en: Array = await pack(home + Vector3(0, 0, -2.2), 3)
	h._face(Vector3(0, 0, -1))
	var l0 := lives(en)
	h.mana = h.max_mana
	check(h.use_skill("fists", h.skill_aim("fists", en[1].global_position)), "Molten Fists cast")
	check(h.skill_cd("fists") == 0.0 and h.atk_dur > 1.8, "a heavy blow: no cooldown, a %.2f s use time" % h.atk_dur)
	await wait(1.0)
	check(lives(en) >= l0 - 0.5, "nothing struck during the wind-up")
	await wait(1.0)
	check(lives(en) < l0 - 1.0, "Molten Fists hurt the pack (%d)" % int(l0 - lives(en)))
	check(en.filter(func(e): return is_instance_valid(e) and e.burn_t > 0.0).size() >= 2, "and set them alight")
	# ... and the dodge roll cancels the wind-up: no blow
	en = await pack(home + Vector3(0, 0, -2.2), 3)
	h.global_position = home
	h._face(Vector3(0, 0, -1))
	l0 = lives(en)
	h.mana = h.max_mana
	h.use_skill("fists", h.skill_aim("fists", en[1].global_position))
	await wait(0.5)
	check(Dodge.start(h, Vector3(1, 0, 0)), "dodged out of the wind-up")
	await wait(1.6)
	check(lives(en) >= l0 - 0.5, "the dodge cancelled the blow")
	# Infernal Charge: he covers ground, bowls them and leaves lava that keeps burning them
	en = await pack(home + Vector3(0, 0, -5.0), 3)
	h.global_position = home
	h._face(Vector3(0, 0, -1))
	l0 = lives(en)
	h.mana = h.max_mana
	for k in h.cds.keys():
		h.cds[k] = 0.0
	check(h.use_skill("icharge", home + Vector3(0, 0, -8.0)), "Infernal Charge cast")
	await wait(1.3)
	var went: float = home.distance_to(h.global_position)
	check(went > 4.0, "the charge carried him %.1f m" % went)
	var l1 := lives(en)
	check(l1 < l0 - 1.0, "and bowled the pack (%d)" % int(l0 - l1))
	check(h.dm.has("lava"), "lava lies on the ground (%d patches)" % (h.dm["lava"] as Array).size())
	var decals: int = g.world.fx_root.get_children().filter(func(c): return c is MeshInstance3D and c.mesh == DemonFx._disc_mesh()).size()
	check(decals >= 4, "and is seen: %d lava decals under his trail" % decals)
	for e in en:
		if is_instance_valid(e):
			e.global_position = (h.dm["lava"][0] as Dictionary)["p"]
	await wait(1.2)
	check(lives(en) < l1 - 1.0, "the trail burns whoever stands in it (%d)" % int(l1 - lives(en)))
	await wait(4.0)
	check(not h.dm.has("lava"), "and cools away")
	# Cataclysm Slam: the ring, then the fissures erupt further out
	h.global_position = home
	en = await pack(home + Vector3(0, 0, -2.0), 2)
	var far_en: Array = []
	for i in 2:
		var e = g.spawn_enemy("zombie", home + Vector3(-1.0 + i * 2.0, 0, -6.0), 20)
		e.aggro = false
		e.scripted = 99.0
		e.max_life = 5000.0
		e.life = 5000.0
		far_en.append(e)
	h._face(Vector3(0, 0, -1))
	l0 = lives(en)
	var f0 := lives(far_en)
	h.mana = h.max_mana
	for k in h.cds.keys():
		h.cds[k] = 0.0
	check(h.use_skill("cslam", h.global_position + Vector3(0, 0, -2.0)), "Cataclysm Slam cast")
	await wait(h.atk_dur * Anim.impact_at("cslam") + 0.3)      # (its use time is its data's: the blow lands then)
	check(lives(en) < l0 - 1.0, "the slam hurt the near pack (%d)" % int(l0 - lives(en)))
	check(h.dm.has("fissures") or lives(far_en) < f0 - 1.0, "fissures race out")
	await wait(2.0)
	check(lives(far_en) < f0 - 1.0, "and their eruptions reached the far pack (%d)" % int(f0 - lives(far_en)))
	check(not h.dm.has("fissures"), "and the fissures are spent")
	# Brimstone Hurl: the boulder lands on the aim point, splashes and leaves a pool
	en = await pack(home + Vector3(0, 0, -7.0), 3)
	h.global_position = home
	h._face(Vector3(0, 0, -1))
	l0 = lives(en)
	h.mana = h.max_mana
	for k in h.cds.keys():
		h.cds[k] = 0.0
	check(h.use_skill("hurl", en[1].global_position), "Brimstone Hurl cast")
	await wait(0.95)
	check(h.dm.has("boulders") or lives(en) < l0, "a boulder is in the air")
	await wait(1.4)
	check(lives(en) < l0 - 1.0, "it splashed on the pack (%d)" % int(l0 - lives(en)))
	check(h.dm.has("lava") and (h.dm["lava"] as Array).any(func(p): return str(p["s"]) == "hurl"), "and left a pool")
	# Hellgrip: one foe seized, lifted, smashed; the rest shocked
	en = await pack(home + Vector3(0, 0, -2.2), 3)
	h.global_position = home
	h._face(Vector3(0, 0, -1))
	l0 = lives(en)
	var v = DemonSkills.grip_pick(h, en[1].global_position)
	check(v != null, "Hellgrip finds a foe ahead")
	var vl: float = v.life
	h.mana = h.max_mana
	for k in h.cds.keys():
		h.cds[k] = 0.0
	check(h.use_skill("grip", en[1].global_position), "Hellgrip cast")
	await wait(0.9)
	var lifted: bool = is_instance_valid(v) and v.rig.position.y > 0.8
	check(lifted, "the foe is hoisted up (%.2f m)" % (v.rig.position.y if is_instance_valid(v) else 0.0))
	await wait(1.6)
	check(is_instance_valid(v) and v.life < vl - 1.0 and v.rig.position.y < 0.05, "smashed down (%d) and back on the ground" % int(vl - v.life))
	check(lives(en) - (v.life if is_instance_valid(v) else 0.0) < l0 - vl - 0.5, "the shockwave hit the others")
	check(is_instance_valid(v) and v.burn_t > 0.0, "and it burns")
	for e in g.enemies_near(home, 80.0):
		e.queue_free()
	await process_frame
	check(not h.use_skill("grip", home + Vector3(0, 0, -2.0)), "no foe in reach: Hellgrip is refused")
	# Wrath of the Pit: the roar and the stomp, then meteors for 7 s, +40% damage meanwhile
	en = await pack(home + Vector3(0, 0, -4.0), 4)
	h.global_position = home
	h._face(Vector3(0, 0, -1))
	l0 = lives(en)
	h.mana = h.max_mana
	for k in h.cds.keys():
		h.cds[k] = 0.0
	check(h.use_skill("wrath", home), "Wrath of the Pit cast")
	await wait(3.0)
	check(h.dm.has("wrath") and float(h.dm["wrath"]["rain"]) > 0.0, "the rain has begun (%.1f s left)" % (float(h.dm["wrath"]["rain"]) if h.dm.has("wrath") else 0.0))
	check(h.buff_t > 0.0, "and his damage is up (%.1f s)" % h.buff_t)
	await wait(4.0)
	var meteors: int = int(h.dm["wrath"]["n"]) if h.dm.has("wrath") else 0
	check(meteors >= 6, "meteors fell (%d so far)" % meteors)
	check(lives(en) < l0 - 1.0, "and hurt the pack (%d)" % int(l0 - lives(en)))
	await wait(4.0)
	check(not h.dm.has("wrath"), "the wrath ends by itself")
	# old saves: the four old skills' bindings carry over
	var b := {"q": "hellclaw", "e": "summon", "r": "phase", "f": "pact", "lmb": "attack", "rmb": "block"}
	DemonSkills.migrate_binds(b)
	check(b["q"] == "fists" and b["e"] == "icharge" and b["r"] == "cslam" and b["f"] == "hurl", "old bindings migrated: %s" % str(b))
	var old: Dictionary = h.to_save()
	old["binds"] = {"q": "hellclaw", "e": "summon", "r": "phase", "f": "pact", "g": "", "v": "", "lmb": "attack", "rmb": "block"}
	old["talents"] = {"d_sear": 2, "d_legion": 1, "d_furnace": 1, "gone_talent": 3}
	h.from_save(old)
	check(h.bound("q") == "fists" and h.bound("f") == "hurl", "an old save's bar: Q %s F %s" % [h.bound("q"), h.bound("f")])
	check(not h.talents.has("gone_talent"), "unknown talents dropped: %s" % str(h.talents))
	# talents
	h.new_character()
	h.set_level(60)
	h.auto_talents()
	check(h.talent("fists_wide") == 1.0 and h.talent("hurl_twin") == 1.0 and h.talent("wrath_double") == 1.0, "the auto build takes all three capstones")
	check(h.skill_cd("icharge") < 7.0 and h.skill_cost("icharge") < 12.0, "Stampede and Cheap Fury apply (cd %.1f, cost %.1f)" % [h.skill_cd("icharge"), h.skill_cost("icharge")])
	# save/load and the class swap
	g.save_game()
	await g.travel(0, "town", "start")
	while g._busy:
		await process_frame
	h.set_class("knight")
	check(h.cls == "knight" and h.dm.is_empty(), "switched to knight: demon state cleared, slots %s" % str(["Q", "E", "R", "F"].map(func(k): return h.bound(k))))
	g.load_game()
	check(h.cls == "demon" and h.rig.has_meta("demon") and h.net_gear().get("_cls") == "demon", "after load: class demon, rig demon, net class demon")
	print("[D] done, %d failed" % fails)
	quit()
