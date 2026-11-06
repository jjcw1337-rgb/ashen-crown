extends SceneTree
## The Warlock's three directions (WarlockHex, WarlockHarrowFx): every new skill on monsters spawned for it, the
## curses' ticks and their rules, fear, the crows, the drain and the shield, and every rite key.
##   godot --headless --path . -s tools/warlock_hex_test.gd   (run with --fixed-fps 60 for steady timings)
var g
var fails := 0

func ok(c: bool, what: String) -> void:
	print("[WH] " + ("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1

func _initialize():
	BuildEnv.forced = {"env": "local", "cloud": "0"}
	g = (load("res://main.tscn") as PackedScene).instantiate()
	g.char_dir = "user://gate/warlock_hex/"
	g.old_save = g.char_dir + "absent.json"
	get_root().add_child(g)
	current_scene = g
	_run()

func secs(t: float) -> void:
	await create_timer(t).timeout

## A fresh row of zombies in front of him, tough enough to live through every test.
func foes(h, n: int, at := Vector3(5, 0, 0), spread := 1.4) -> Array:
	for e in g.enemies_near(h.global_position, 30.0):
		e.queue_free()
	await process_frame
	var out := []
	for i in n:
		var p: Vector3 = h.global_position + at + Vector3(0, 0, (i - (n - 1) * 0.5) * spread)
		var e = g.spawn_enemy("zombie", g.world.free_spot_near(p, 0.5), 3)
		e.max_life = 100000.0
		e.life = e.max_life
		e.aggro = false
		out.append(e)
	await process_frame
	return out

func cast(h, id: String, at: Vector3) -> bool:
	h.mana = h.max_mana
	h.cds[id] = 0.0
	h.atk_t = -1.0
	var r: bool = h.use_skill(id, at)
	return r

func lost(es: Array) -> float:
	var t := 0.0
	for e in es:
		if is_instance_valid(e):
			t += e.max_life - e.life
	return t

func _run() -> void:
	while g.world == null or g._busy:
		await process_frame
	await g.start_game(false, "warlock")
	var h = g.hero
	g.test_allskills = true
	g.test_immortal = true
	await g.travel(0, "wild", "start")
	while g._busy:
		await process_frame
	h.level = 15
	h.recalc()
	var hex = load("res://scripts/warlock_hex.gd")
	var ids: Array = hex.IDS
	var known: Array = h.skill_list().map(func(s): return s["id"])
	ok(ids.all(func(i): return known.has(i)), "all %d new skills are the Warlock's (%d in all)" % [ids.size(), known.size()])
	ok(ids.all(func(i): return RunBuild.skill_pool("warlock").any(func(s): return s["id"] == i)), "every new skill can be drawn in a run")

	# ---- Corruption
	var es: Array = await foes(h, 3)
	var e = es[1]
	ok(cast(h, "w_corruption", e.global_position), "Corruption casts")
	await secs(0.6)
	ok(hex.curses_on(h, e) == 1, "Corruption is on the foe (%d curse)" % hex.curses_on(h, e))
	ok(h.fxs.has("hx_mark_%d" % e.get_instance_id()), "its mark shows on the foe")
	var l0 := lost([e])
	await secs(2.0)
	var per2 := lost([e]) - l0
	ok(per2 > 0.0, "Corruption ticks (%.0f in 2 s)" % per2)
	var expect: float = hex.amount(h, "w_corruption", float(hex.CURSES["w_corruption"][0])) / 10.0 * 2.0
	ok(absf(per2 - expect) < expect * 0.5 + 2.0, "about 240%% spell over 10 s (%.0f vs %.0f expected)" % [per2, expect])
	cast(h, "w_unending", e.global_position)
	await secs(0.6)
	cast(h, "w_leeching", e.global_position)
	await secs(0.6)
	ok(hex.curses_on(h, e) == 3, "three curses stack on one foe (%d)" % hex.curses_on(h, e))
	h.life = h.max_life * 0.5
	var life0: float = h.life
	await secs(2.0)
	ok(h.life > life0, "Leeching Curse heals him (%+.0f)" % (h.life - life0))
	ok(hex.afflicted(h, e) > 3.0, "the foe has been cursed without a break for %.1f s" % hex.afflicted(h, e))
	# Malediction grows with curses
	var e2 = es[2]
	l0 = lost([e2])
	cast(h, "w_malediction", e2.global_position)
	await secs(1.0)
	var lone := lost([e2]) - l0
	l0 = lost([e])
	var dots_before := lost([e])
	cast(h, "w_malediction", e.global_position)
	await secs(1.0)
	var cursed_hit := lost([e]) - l0
	ok(cursed_hit > lone * 1.8, "Malediction hits a thrice-cursed foe much harder (%.0f vs %.0f)" % [cursed_hit, lone])
	# Reckoning copies the others
	cast(h, "w_corruption", e.global_position)
	await secs(0.6)
	cast(h, "w_reckoning", e.global_position)
	await secs(0.6)
	l0 = lost([e])
	await secs(2.0)
	var with_reck := lost([e]) - l0
	ok(hex.curses_on(h, e) == 4, "Reckoning is a fourth curse (%d: %s)" % [hex.curses_on(h, e), str(h.wl["dots"].filter(func(x): return x["e"] == e).map(func(x): return x["id"]))])
	ok(with_reck > per2 * 1.6, "Reckoning roughly doubles the curses' damage (%.0f in 2 s)" % with_reck)
	# Festering Hex: bursts and stuns every 5 s
	var e0 = es[0]
	cast(h, "w_festering", e0.global_position)
	var stunned := false
	for i in 70:
		await secs(0.1)
		if e0.stun_t > 0.0:
			stunned = true
			break
	ok(stunned, "Festering Hex bursts and stuns within 5 s")
	# dot_flat, dot_dur, dot_echo, dot_heal
	h.tfx["dot_flat"] = 5.0
	h.tfx["dot_dur"] = 50.0
	var e3 = (await foes(h, 1))[0]
	cast(h, "w_corruption", e3.global_position)
	await secs(0.6)
	var d: Dictionary = hex._dot(h, e3, "w_corruption")
	ok(not d.is_empty() and float(d["t"]) > 13.5, "Slow Decay: the curse lasts 50%% longer (%.1f s left)" % (float(d["t"]) if not d.is_empty() else 0.0))
	ok(not d.is_empty() and hex._tick_amount(h, d) > float(d["per"]) + 4.9, "Lingering Rot: +5 a tick")
	h.tfx["dot_echo"] = 1.0
	l0 = lost([e3])
	cast(h, "w_corruption", e3.global_position)
	await secs(0.55)
	ok(lost([e3]) - l0 >= float(d["per"]), "Echoing Corruption: the refresh ticks at once")
	h.tfx["dot_heal"] = 100.0
	h.life = h.max_life * 0.5
	life0 = h.life
	await secs(1.1)
	ok(h.life > life0, "Vile Mending heals on a tick")
	for k in ["dot_flat", "dot_dur", "dot_echo", "dot_heal"]:
		h.tfx.erase(k)

	# ---- Fear
	es = await foes(h, 4, Vector3(4, 0, 0), 1.0)
	e = es[0]
	ok(cast(h, "w_terrify", e.global_position), "Terrify casts")
	await secs(0.5)
	ok(hex.feared(h, e) and e.stun_t > 0.0, "the foe is frozen in terror")
	ok(h.fxs.has("hx_mark_%d" % e.get_instance_id()) and h.fxs["hx_mark_%d" % e.get_instance_id()]["terror"] != null, "the terror mark shows")
	var bonus: float = hex.amount(h, "w_corruption", 1.0, e) / hex.amount(h, "w_corruption", 1.0)
	ok(absf(bonus - 1.2) < 0.01, "feared foes take 20%% more from his spells (x%.2f)" % bonus)
	h.tfx["dmg_feared"] = 10.0
	ok(absf(hex.amount(h, "w_corruption", 1.0, e) / hex.amount(h, "w_corruption", 1.0) - 1.3) < 0.01, "Nightmare Fuel adds to it")
	h.tfx.erase("dmg_feared")
	# Paralysing Terror, Dread Harvest
	h.tfx["fear_root"] = 1.0
	await secs(1.6)
	ok(not hex.feared(h, e) and e.slow_t > 0.0, "Paralysing Terror roots the foe as the fear ends")
	h.tfx.erase("fear_root")
	h.tfx["fear_kill"] = 1.0
	cast(h, "w_terrify", es[1].global_position)
	await secs(0.5)
	h.mana = 10.0
	h.cds["w_terrify"] = 8.0
	es[1].take_damage(1e9, 0.0, h.global_position, 0.0, false)
	await secs(0.2)
	ok(h.mana >= 24.0 and float(h.cds["w_terrify"]) < 6.5, "Dread Harvest: a foe dying afraid gives mana and time back (mana %.0f, cd %.1f)" % [h.mana, float(h.cds["w_terrify"])])
	h.tfx.erase("fear_kill")
	# Dark Wind bounces
	es = await foes(h, 5, Vector3(5, 0, 0), 1.8)
	var l5 := es.map(func(x): return x.life)
	ok(cast(h, "w_darkwind", es[0].global_position), "Dark Wind casts")
	await secs(1.6)
	var struck := 0
	for i in es.size():
		if es[i].life < l5[i]:
			struck += 1
	ok(struck >= 4, "Dark Wind's crow struck %d of 5" % struck)
	# the Scarecrow Effigy
	es = await foes(h, 4, Vector3(10, 0, 0), 1.0)
	var spot: Vector3 = es[0].global_position + Vector3(-1.0, 0, 0)
	ok(cast(h, "w_effigy", spot), "the Effigy is planted")
	await secs(1.0)
	var feared_n: int = es.filter(func(x): return hex.feared(h, x)).size()
	ok(feared_n == 3, "it frightened the first three to come near (%d)" % feared_n)
	ok(h.fxs.keys().any(func(k): return str(k).begins_with("hx_effigy_")), "the scarecrow stands")
	# Crowstorm
	es = await foes(h, 3, Vector3(9, 0, 0), 1.2)
	var start: Vector3 = h.global_position
	ok(cast(h, "w_crowstorm", es[1].global_position), "Crowstorm casts")
	await secs(1.7)
	ok(h.global_position.distance_to(start) > 4.0, "he blinked (%.1f m)" % h.global_position.distance_to(start))
	ok(h.fxs.has("hx_storm"), "the storm of crows whirls round him")
	ok(es.filter(func(x): return hex.feared(h, x)).size() >= 1, "everything near as he landed is frightened")
	l0 = lost(es)
	await secs(2.0)
	ok(lost(es) - l0 > 0.0, "the storm hurts what's near (%.0f)" % (lost(es) - l0))
	await secs(3.5)
	ok(not h.fxs.has("hx_storm"), "the storm ends")

	# ---- Drain
	es = await foes(h, 3, Vector3(3, 0, 0), 1.2)
	h.life = h.max_life * 0.5
	life0 = h.life
	l0 = lost(es)
	cast(h, "w_leechbolt", es[1].global_position)
	await secs(0.8)
	ok(lost(es) > l0 and h.life > life0, "Leech Bolt hurts and heals (%.0f / %+.0f)" % [lost(es) - l0, h.life - life0])
	h.life = h.max_life * 0.5
	life0 = h.life
	cast(h, "w_harvest", h.global_position)
	await secs(1.2)
	var hit3: int = es.filter(func(x): return x.life < x.max_life).size()
	ok(hit3 == 3 and h.life >= life0 + h.max_life * 0.11, "Bountiful Harvest strikes all three and heals 12%% (%+.0f)" % (h.life - life0))
	# Blood Ward: healing past full becomes a shield, which soaks a blow
	h.tfx["overheal_shield"] = 20.0
	h.life = h.max_life
	hex.heal(h, h.max_life * 0.5)
	var sh: float = hex.shield(h)
	ok(absf(sh - h.max_life * 0.2) < 1.0, "Blood Ward: overflow becomes a shield, capped at 20%% (%.0f)" % sh)
	ok(h.fxs.has("hx_shield"), "the shield shows")
	g.test_immortal = false
	var lb: float = h.life
	h.take_hit(sh * 0.5, h.global_position + Vector3(2, 0, 0), "melee", "phys")
	ok(hex.shield(h) < sh and h.life >= lb - 1.0, "the shield soaks a blow first (%.0f left)" % hex.shield(h))
	g.test_immortal = true
	h.tfx.erase("overheal_shield")
	# Soul Feast
	es = await foes(h, 4, Vector3(4, 0, 0), 1.2)
	h.life = h.max_life
	h.wl["shield"] = 0.0
	l0 = lost(es)
	ok(cast(h, "w_soulfeast", h.global_position), "Soul Feast casts")
	await secs(1.0)
	ok(h.fxs.has("hx_feast") and (h.fxs["hx_feast"]["beams"] as Dictionary).size() >= 3, "beams reach every foe near (%d)" % ((h.fxs["hx_feast"]["beams"] as Dictionary).size() if h.fxs.has("hx_feast") else 0))
	await secs(2.4)
	ok(lost(es) > l0, "the feast drains them (%.0f)" % (lost(es) - l0))
	ok(hex.shield(h) > 0.0, "at full life the feast hardens into a shield (%.0f)" % hex.shield(h))
	await secs(0.5)
	ok(not h.fxs.has("hx_feast"), "the feast's beams are gone when it ends")

	# ---- rites in the run's pool
	var pool := RunBuild.passive_pool("warlock")
	var rites := pool.filter(func(p): return str(p["id"]).begins_with("w_r_"))
	ok(rites.size() == 14, "all 14 new rites are in the Warlock's pool (%d)" % rites.size())
	var r := RunBuild.new()
	var binds := {}
	r.add_skill("w_terrify", binds)
	var offerable := func(rb: RunBuild, id: String) -> bool:
		for i in 60:
			for c in rb.roll_offer("warlock", 4, "k%d" % i, binds):
				if c["id"] == id:
					return true
		return false
	ok(offerable.call(r, "w_r_paralysis"), "a Fear rite is offered once he has a Fear skill")
	ok(not offerable.call(r, "w_r_echo"), "a Corruption rite isn't, without a curse")
	r.passives["w_r_haunt"] = 2
	ok(is_equal_approx(float(r.fx("warlock").get("fear_dur", 0.0)), 0.4), "Haunting's stacks add up (0.4 s)")

	# ---- clean up
	await g.travel(0, "town", "start")
	while g._busy:
		await process_frame
	ok(h.wl.get("dots", []).is_empty() and h.wl.get("effigies", []).is_empty() and not h.fxs.keys().any(func(k): return str(k).begins_with("hx_") and k != "hx_shield"), "a zone change leaves nothing behind but his shield (%s)" % str(h.fxs.keys()))
	print("[WH] done, %d failed" % fails)
	quit(1 if fails > 0 else 0)
