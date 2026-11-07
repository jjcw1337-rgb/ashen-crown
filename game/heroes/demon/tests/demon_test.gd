extends SceneTree
## Demon class: his six skills (Molten Fists, Infernal Charge, Fault of the Pit, Brimstone Hurl, Hellgrip, Wrath of
## the Pit) each doing its own job (the Brand and its use, the charge's wind-up, run, stop and skid, the fault's
## warning, eruption and molten life, Hurl's use time and Twin Boulders, the chain's hook, drag, smash, miss and boss pull, the
## Crucible's damage taken and stored, its recast and eruption, Pit-born), the old saves' bindings carried over,
## his talents, save/load and the class swap. Prints [D] lines ("FAIL" marks a check that failed).
var g
var fails := 0
var DS        # Demon (his kit) and BrandFx, loaded at run time (a static reference compiles them before the Sfx autoload)
var BF
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
## One of his skill objects (Hero.kit).
func sk(h, id: String):
	return DS.skill(h, id)
## Until his last skill is over (every stage), so the next one can start.
func idle(h) -> void:
	for i in 400:
		var mid: bool = h.kit.values().any(func(s): return s.has_method("stage_done") and s.next != "")
		if h.atk_t < 0.0 and not mid and sk(h, "grip").chain.is_empty() and sk(h, "icharge").run.is_empty():
			return
		await process_frame
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
	DS = load("res://game/heroes/demon/demon.gd")
	BF = load("res://game/systems/combat/brand_fx.gd")
	while g.world == null or g._busy:
		await process_frame
	await g.start_game(false, "demon")
	var h = g.hero
	print("[D] class ", h.cls, " demon rig ", h.rig.has_meta("demon"), " mocap ", str(h.rig.get_meta("meshy", "")), " skills ", h.skill_list().map(func(s): return s["id"]))
	check(h.skill_list().map(func(s): return s["id"]) == ["fists", "icharge", "cslam", "hurl", "grip", "wrath"], "six skills in order")
	print("[D] stats str %d dex %d vit %d ene %d life %d mana %d weapon %s" % [h.str_, h.dex, h.vit, h.ene, h.max_life, h.max_mana, h.equipment["weapon"]["name"]])
	await g.travel(0, "sandbox", "start")
	while g._busy:
		await process_frame
	h.set_level(20)
	h.recalc()
	g.test_immortal = true
	var home: Vector3 = h.global_position
	# Molten Fists: the wedge ahead is hit and set alight; a Branded foe takes more and loses the Brand
	var en: Array = await pack(home + Vector3(0, 0, -2.2), 3)
	h._face(Vector3(0, 0, -1))
	var l0 := lives(en)
	h.mana = h.max_mana
	DS.brands(h).mark(en[1])
	await wait(0.1)
	check(DS.brands(h).has(en[1]) and BF.has(en[1]), "a Branded foe carries the mark (seen)")
	check(h.use_skill("fists", h.skill_aim("fists", en[1].global_position)), "Molten Fists cast")
	check(h.skill_cd("fists") == 0.0 and h.atk_dur > 1.8, "a heavy blow: no cooldown, a %.2f s use time" % h.atk_dur)
	await wait(1.0)
	check(lives(en) >= l0 - 0.5, "nothing struck during the wind-up")
	await wait(1.0)
	check(lives(en) < l0 - 1.0, "Molten Fists hurt the pack (%d)" % int(l0 - lives(en)))
	check(en.filter(func(e): return is_instance_valid(e) and e.burn_t > 0.0).size() >= 2, "and set them alight")
	check(not DS.brands(h).has(en[1]), "and used the Brand up")
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
	# Infernal Charge: the wind-up shows the line, then he runs it, bowling lesser foes aside
	en = await pack(home + Vector3(0, 0, -5.0), 3)
	h.global_position = home
	h._face(Vector3(0, 0, -1))
	l0 = lives(en)
	h.mana = h.max_mana
	for k in h.cds.keys():
		h.cds[k] = 0.0
	check(h.use_skill("icharge", home + Vector3(0, 0, -8.0)), "Infernal Charge cast")
	check(h.atk_style == "icharge_wind" and h.fxs.has("hellrunner"), "the wind-up first, the path burning on the ground")
	var moved_in_wind: float = 0.0
	await wait(0.2)
	moved_in_wind = home.distance_to(h.global_position)
	check(moved_in_wind < 0.3, "he hasn't moved during the wind-up (%.2f m)" % moved_in_wind)
	await wait(1.4)
	var went: float = home.distance_to(h.global_position)
	check(went > 6.0, "the charge carried him %.1f m (through the lesser foes)" % went)
	check(lives(en) < l0 - 1.0, "and bowled the pack (%d)" % int(l0 - lives(en)))
	check(sk(h, "icharge").run.is_empty() and h.atk_t < 0.0, "the skid ended it")
	# ... and a champion stops it: staggered and Branded
	en = await pack(home + Vector3(0, 0, -5.0), 1)
	en[0].champion = true
	h.global_position = home
	h._face(Vector3(0, 0, -1))
	for k in h.cds.keys():
		h.cds[k] = 0.0
	h.mana = h.max_mana
	check(h.use_skill("icharge", home + Vector3(0, 0, -9.0)), "a second charge at a champion")
	var saw_skid := false
	for i in 90:
		await process_frame
		if h.atk_style == "icharge_skid":
			saw_skid = true
	went = home.distance_to(h.global_position)
	check(went < 5.2 and went > 2.5, "it stopped him at the champion (%.1f m)" % went)
	check(saw_skid, "with the skid")
	check(is_instance_valid(en[0]) and DS.brands(h).has(en[0]), "and Branded it")
	# Fault of the Pit: a line across his aim erupts after its warning, then stays molten, burning and slowing
	h.global_position = home
	en = await pack(home + Vector3(0, 0, -3.0), 3)
	var off_en: Array = await pack(home + Vector3(0, 0, 1.5), 1)
	en = []
	for i in 3:
		var e = g.spawn_enemy("zombie", home + Vector3(-2.0 + i * 2.0, 0, -3.0), 20)
		e.aggro = false
		e.scripted = 99.0
		e.max_life = 5000.0
		e.life = 5000.0
		en.append(e)
	h._face(Vector3(0, 0, -1))
	l0 = lives(en)
	var o0 := lives(off_en)
	h.mana = h.max_mana
	for k in h.cds.keys():
		h.cds[k] = 0.0
	check(h.use_skill("cslam", h.global_position + Vector3(0, 0, -3.0)), "Fault of the Pit cast")
	var l_warn := l0
	for i in 200:
		await process_frame
		if not sk(h, "cslam").fault.is_empty():
			break
	check(not sk(h, "cslam").fault.is_empty() and not bool(sk(h, "cslam").fault["erupted"]), "the fault opens with a warning first")
	l_warn = lives(en)
	check(l_warn > l0 - 1.0, "nobody hurt during the warning")
	await wait(0.6)
	var l_er := lives(en)
	check(l_er < l0 - 1.0, "the eruption hurt everyone on the line (%d)" % int(l0 - l_er))
	check(en.filter(func(e): return is_instance_valid(e) and DS.brands(h).has(e)).size() == 3, "and Branded them")
	check(lives(off_en) > o0 - 1.0, "not the one behind him")
	check(h.fxs.has("fault") and (h.fxs["fault"]["plates"] as Array).size() > 0, "obsidian plates heaved up (%d)" % (h.fxs["fault"]["plates"] as Array).size() if h.fxs.has("fault") else 0)
	await wait(1.2)
	check(lives(en) < l_er - 1.0, "the molten fault keeps burning them (%d)" % int(l_er - lives(en)))
	check(en.any(func(e): return is_instance_valid(e) and e.slow_t > 0.0), "and slows them")
	await wait(4.0)
	check(sk(h, "cslam").fault.is_empty(), "then cools away")
	# Brimstone Hurl: a main skill the Path of Exile way (no cooldown, its data's use time is the limit); the boulder
	# lands at the aim, the core Brands, shards fly
	en = await pack(home + Vector3(0, 0, -7.0), 3)
	h.global_position = home
	h._face(Vector3(0, 0, -1))
	l0 = lives(en)
	h.mana = h.max_mana
	for k in h.cds.keys():
		h.cds[k] = 0.0
	check(h.use_skill("hurl", en[1].global_position), "Brimstone Hurl cast")
	check(h.skill_cd("hurl") == 0.0 and is_equal_approx(h.atk_dur, SkillSpec.use_time(h, "hurl")), "no cooldown, its data's use time (%.2f s)" % h.atk_dur)
	var thrown := false
	for i in 150:
		await process_frame
		if not (sk(h, "hurl").boulders as Array).is_empty():
			thrown = true
			break
	check(thrown, "a boulder is in the air")
	check(h.fxs.has("shatter") and (h.fxs["shatter"] as Array).size() > 0, "with its landing mark on the ground")
	await wait(1.0)
	check(lives(en) < l0 - 1.0, "it landed on the pack (%d)" % int(l0 - lives(en)))
	check(DS.brands(h).has(en[1]), "the direct hit is Branded")
	await idle(h)
	h.mana = h.max_mana
	check(h.use_skill("hurl", en[0].global_position), "and he throws again once the first throw is done")
	await idle(h)
	await wait(1.0)
	# Twin Boulders (the capstone): a second boulder lands beside the first
	h.talents["d_legion"] = 1
	h._talents_changed()
	en = await pack(home + Vector3(0, 0, -7.0), 1)
	var twin_en: Array = []          # out of the first boulder's reach, in the second's on either side
	var twin_gap := Skill.num("hurl", "twin_gap", 2.2)
	for x in [-twin_gap - 2.0, twin_gap + 2.0]:
		var e = g.spawn_enemy("zombie", home + Vector3(x, 0, -7.0), 20)
		e.aggro = false
		e.scripted = 99.0
		e.max_life = 5000.0
		e.life = 5000.0
		twin_en.append(e)
	h.global_position = home
	h._face(Vector3(0, 0, -1))
	var tw0 := lives(twin_en)
	h.mana = h.max_mana
	check(h.use_skill("hurl", home + Vector3(0, 0, -7.0)), "Twin Boulders: a cast")
	var gap := 0.0
	for i in 150:
		await process_frame
		var bs: Array = sk(h, "hurl").boulders
		if bs.size() >= 2:
			gap = (bs[0]["at"] as Vector3).distance_to(bs[1]["at"])
			break
	check(absf(gap - twin_gap) < 0.3, "two boulders in the air, %.1f m apart" % gap)
	await wait(1.2)
	check(lives(twin_en) < tw0 - 1.0, "the second landed beside the first (%d)" % int(tw0 - lives(twin_en)))
	h.talents.erase("d_legion")
	h._talents_changed()
	await idle(h)
	# Hellgrip: the chain hooks the first foe in its line, drags it in, hoists it and smashes it
	en = await pack(home + Vector3(0, 0, -6.0), 1)
	var behind: Array = await pack(home + Vector3(0, 0, -7.2), 1)
	en.append(g.spawn_enemy("zombie", home + Vector3(0, 0, -6.0), 20))
	for e in g.enemies_near(home, 30.0):
		e.aggro = false
		e.scripted = 99.0
		e.max_life = 5000.0
		e.life = 5000.0
	var first = null
	for e in g.enemies_near(home + Vector3(0, 0, -6.0), 0.5):
		first = e
	h.global_position = home
	h._face(Vector3(0, 0, -1))
	var vd0: float = home.distance_to(first.global_position)
	var vl: float = first.life
	h.mana = h.max_mana
	for k in h.cds.keys():
		h.cds[k] = 0.0
	check(h.use_skill("grip", home + Vector3(0, 0, -6.0)), "Hellgrip cast (no foe needed: the chain is a skillshot)")
	var hooked := false
	var min_d := 99.0
	var max_y := 0.0
	for i in 180:
		await process_frame
		if str(sk(h, "grip").chain.get("state", "")) == "drag":
			hooked = true
		if is_instance_valid(first):
			min_d = minf(min_d, home.distance_to(first.global_position))
			max_y = maxf(max_y, first.rig.position.y)
	check(hooked, "the chain hooked a foe")
	check(min_d < vd0 - 3.0, "and dragged it in (%.1f -> %.1f m)" % [vd0, min_d])
	check(max_y > 0.8, "hoisted it (%.2f m)" % max_y)
	check(is_instance_valid(first) and first.life < vl - 1.0 and first.rig.position.y < 0.05, "smashed it down (%d) and back on the ground" % int(vl - first.life))
	await idle(h)
	check(h.atk_t < 0.0 and sk(h, "grip").chain.is_empty() and not h.fxs.has("chain") and not h.fxs.has("grip"), "and it's over (nothing left of it)")
	await idle(h)
	# a miss: no foe, the chain comes back empty
	for e in g.enemies_near(home, 80.0):
		e.queue_free()
	await process_frame
	for k in h.cds.keys():
		h.cds[k] = 0.0
	h.mana = h.max_mana
	check(h.use_skill("grip", home + Vector3(0, 0, -6.0)), "a cast at nothing")
	await wait(1.6)
	check(h.atk_t < 0.0 and sk(h, "grip").chain.is_empty() and sk(h, "grip").victim == null, "the empty chain came back")
	await idle(h)
	# a boss drags him instead
	en = await pack(home + Vector3(0, 0, -6.0), 1)
	en[0].boss = true
	h.global_position = home
	for k in h.cds.keys():
		h.cds[k] = 0.0
	h.mana = h.max_mana
	h.use_skill("grip", home + Vector3(0, 0, -6.0))
	await wait(1.0)
	check(home.distance_to(h.global_position) > 3.0 and en[0].global_position.distance_to(home + Vector3(0, 0, -6.0)) < 1.2, "a boss stays put and he is dragged to it (%.1f m)" % home.distance_to(h.global_position))
	await idle(h)
	# Wrath of the Pit: the Crucible takes half and stores it, nothing stops him; the eruption; then Pit-born
	en = await pack(home + Vector3(0, 0, -4.0), 4)
	h.global_position = home
	h._face(Vector3(0, 0, -1))
	l0 = lives(en)
	h.mana = h.max_mana
	for k in h.cds.keys():
		h.cds[k] = 0.0
	check(h.use_skill("wrath", home), "Wrath of the Pit cast")
	check(sk(h, "wrath").holding(), "the Crucible holds him")
	await wait(0.5)      # (past the least a recast needs: its "min" 0.35 s at his pace, 0.42 s)
	g.test_immortal = false
	h.life = h.max_life
	var lb: float = h.life
	h.take_hit(200.0, home + Vector3(0, 0, -2), "melee", "fire")
	var took: float = lb - h.life
	var w = sk(h, "wrath")
	var h_heat: float = float(w.wrath.get("heat", 0.0))
	h.daze_t = 1.0
	await process_frame
	await process_frame
	g.test_immortal = true
	check(took > 1.0 and took <= 200.0 * (1.0 - h.res / 100.0) * 0.5 + 1.0, "it took half (%d of a 200 blow)" % int(took))
	check(h_heat > 1.0, "and stored it as heat (%d)" % int(h_heat))
	check(h.daze_t <= 0.0, "nothing stuns him in it")
	check(h.use_skill("wrath", home), "pressing V again ends it early")
	await wait(0.9)
	check(lives(en) < l0 - 1.0, "the eruption hurt the pack (%d)" % int(l0 - lives(en)))
	check(en.all(func(e): return not is_instance_valid(e) or e.stun_t > 0.0 or e.dead), "and froze them with fear")
	check(float(w.wrath.get("rain", -1.0)) > 0.0, "Pit-born: the rain has begun (%.1f s left)" % float(w.wrath.get("rain", -1.0)))
	check(h.buff_t > 0.0, "and his damage is up (%.1f s)" % h.buff_t)
	await wait(4.0)
	var meteors: int = int(w.wrath.get("n", 0))
	check(meteors >= 6, "meteors fell (%d so far)" % meteors)
	await wait(4.0)
	check(w.wrath.is_empty() and not w.pit, "the wrath ends by itself")
	# a Crucible left alone erupts by itself
	for k in h.cds.keys():
		h.cds[k] = 0.0
	h.mana = h.max_mana
	h.use_skill("wrath", home)
	await wait(3.6)
	check(float(sk(h, "wrath").wrath.get("rain", -1.0)) > 0.0, "a Crucible left alone erupts by itself")
	await wait(7.0)
	# old saves: the four old skills' bindings carry over
	var b := {"q": "hellclaw", "e": "summon", "r": "phase", "f": "pact", "lmb": "attack", "rmb": "block"}
	DS.migrate_binds(b)
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
	check(h.skill_cd("icharge") < 9.0 and h.skill_cost("icharge") < 12.0, "Stampede and Cheap Fury apply (cd %.1f, cost %.1f)" % [h.skill_cd("icharge"), h.skill_cost("icharge")])
	# save/load and the class swap
	g.save_game()
	await g.travel(0, "town", "start")
	while g._busy:
		await process_frame
	h.set_class("knight")
	check(h.cls == "knight" and h.kit.is_empty(), "switched to knight: demon state cleared, slots %s" % str(["Q", "E", "R", "F"].map(func(k): return h.bound(k))))
	g.load_game()
	check(h.cls == "demon" and h.rig.has_meta("demon") and h.net_gear().get("_cls") == "demon", "after load: class demon, rig demon, net class demon")
	print("[D] done, %d failed" % fails)
	quit()
