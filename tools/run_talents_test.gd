extends SceneTree
## A run's talents, gems and consumables do what their cards say (RunTalents, Blaine 2026-11-06): each proc tried in
## a real zone on real monsters with a real hero. Prints [TAL] lines; `godot --headless --path . -s tools/run_talents_test.gd`.
var g
var fails := 0
var RB
var RT

func _initialize():
	g = (load("res://main.tscn") as PackedScene).instantiate()
	get_root().add_child(g)
	RB = load("res://game/items/run_build.gd")
	RT = load("res://game/items/run_talents.gd")
	_run()

func check(ok: bool, what: String) -> void:
	if not ok:
		fails += 1
	print("[TAL] %s %s" % ["ok  " if ok else "FAIL", what])

func _run() -> void:
	while g.world == null or g._busy:
		g._intro_skip = true
		await process_frame
	await g.start_game(false, "archer")
	await g.load_zone(0, "sandbox", "start")
	var h = g.hero
	await _data(h)
	await _archer(h)
	await _plague(h)
	await _generic(h)
	await _gems(h)
	await _consumables(h)
	await _offers(h)
	await _skills(h)
	print("[TAL] done, %d failure(s)" % fails)
	quit(1 if fails > 0 else 0)

## A fresh run of `cls` with only these talents (id: stacks), and foes cleared away.
func _fresh(h, cls: String, talents: Dictionary, gems := []) -> void:
	for e in g.world.enemies_root.get_children():
		e.queue_free()
	await process_frame
	h.set_class(cls)
	h.start_run()
	h.run.passives = talents.duplicate()
	h.run.gems = gems.duplicate()
	h.set_level(10)
	h.run_changed()
	h.life = h.max_life
	h.global_position = g.world.spawn_pos if "spawn_pos" in g.world else h.global_position

func _foe(h, off: Vector3, kind := "zombie", life := 400.0):
	var p: Vector3 = h.global_position + off
	p.y = g.world.height_at(p.x, p.z)
	var e = g.spawn_enemy(kind, p, 5, false, "", 0)
	e.max_life = life
	e.life = life
	e.scripted = true          # (it stands still: the test aims at it)
	return e

func _hit(h, e, mult := 1.0, src := "attack") -> void:
	h._hit_enemy(e, mult, 0.0, src)

func _data(h) -> void:
	# every talent and gem is well formed: its text fills, its proc is one RunTalents knows, its theme is its class's
	var procs := ["more_vs_low", "momentum", "heal_on_kill", "explode_on_kill", "undying", "thorns", "berserk", "echo",
		"more_vs_big", "frenzy", "ignite_on_hit", "spread_burn_on_death", "more_vs_burning", "nth_shot", "more_vs_chilled",
		"chill_on_hit", "shards_on_death", "freeze_after", "chain_on_hit", "bolt_on_crit", "more_vs_marked", "ricochet",
		"more_vs_poisoned", "heal_on_dot", "necrosis", "spread_on_hit", "spread_on_death", "cloud_on_death", "ignite_on_crit",
		"nth_hit_bolt", "hunger", "mark_reset", "bloodlust", "speed_on_kill"]
	var bad := []
	for t in RT.TALENTS + RT.GEMS:
		var txt: String = RT.text_of(t, 1)
		if txt.contains("{") or txt == "":
			bad.append("%s text '%s'" % [t["id"], txt])
		if t.has("proc") and not procs.has(t["proc"]):
			bad.append("%s proc %s" % [t["id"], t["proc"]])
		if t.has("theme") and str(t["theme"]) != "" and t["cls"] != "any" and RT.theme_def(str(t["cls"]).split(",")[0], t["theme"]).is_empty():
			bad.append("%s theme %s" % [t["id"], t["theme"]])
	check(bad.is_empty(), "every talent and gem is well formed (%d talents, %d gems) %s" % [RT.TALENTS.size(), RT.GEMS.size(), str(bad)])
	for cls in ["archer", "plague", "knight", "wraith", "demon", "doug", "serpent", "wyvern"]:
		var pool: Array = RB.passive_pool(cls)
		var by := [0, 0, 0]
		var themed := {}
		for p in pool:
			by[int(p["rarity"])] += 1
			if str(p.get("theme", "")) != "":
				themed[p["theme"]] = int(themed.get(p["theme"], 0)) + 1
		check(by[2] >= 6 and by[1] >= 8 and themed.size() >= 2 and themed.size() <= 3, "%s: talents by rarity %s, by direction %s" % [cls, str(by), str(themed)])
	var t: Dictionary = RT.TALENTS.filter(func(x): return x["id"] == "x_momentum")[0]
	check(RT.text_of(t, 2, 1).contains("4 → 8"), "a stacking talent's card shows the change: " + RT.text_of(t, 2, 1))

func _archer(h) -> void:
	# Kindling: burns hotter and longer
	await _fresh(h, "archer", {"a_kindling": 2})
	var e = _foe(h, Vector3(3, 0, 0))
	load("res://scripts/hero.gd").striker = h
	e.ignite(10.0, 3.0, "fire")
	check(is_equal_approx(e.burn_dps, 13.0) and is_equal_approx(e.burn_t, 4.5), "Kindling x2: a 10/s 3 s burn becomes %.1f/s %.1f s" % [e.burn_dps, e.burn_t])
	# Fire-Tipped: plain shots ignite
	await _fresh(h, "archer", {"a_firetip": 1})
	e = _foe(h, Vector3(3, 0, 0))
	_hit(h, e)
	check(e.burn_t > 0.0, "Fire-Tipped: a plain shot sets its foe burning")
	# Conflagration: burning foes take more
	await _fresh(h, "archer", {"a_conflag": 1})
	e = _foe(h, Vector3(3, 0, 0))
	check(is_equal_approx(RT.hit_mult(h, e, "attack"), 1.0), "Conflagration: no bonus on a foe not burning")
	e.ignite(5.0, 3.0, "fire")
	check(is_equal_approx(RT.hit_mult(h, e, "attack"), 1.3), "Conflagration: +30%% on a burning foe (%.2f)" % RT.hit_mult(h, e, "attack"))
	# Wildfire: a burning foe that dies sets the others alight
	await _fresh(h, "archer", {"a_wildfire": 1})
	e = _foe(h, Vector3(3, 0, 0), "zombie", 30.0)
	var o = _foe(h, Vector3(5, 0, 1))
	e.ignite(5.0, 3.0, "fire")
	_hit(h, e, 50.0)
	await process_frame
	check(e.dead and o.burn_t > 0.0, "Wildfire: the burning foe's death sets its neighbour burning (dead %s, burn %.1f)" % [e.dead, o.burn_t])
	# Rimed Arrows chill, Frostbite more vs chilled, Absolute Zero freezes on the 4th hit
	await _fresh(h, "archer", {"a_glacial": 1, "a_frostbite": 2, "a_zero": 1})
	e = _foe(h, Vector3(3, 0, 0), "zombie", 100000.0)
	_hit(h, e)
	check(e.chill_t > 0.0, "Rimed Arrows: a plain shot chills")
	check(is_equal_approx(RT.hit_mult(h, e, "attack"), 1.3), "Frostbite x2: +30%% on a chilled foe (%.2f)" % RT.hit_mult(h, e, "attack"))
	for i in 4:
		_hit(h, e, 0.01)
	check(e.stun_t > 1.0, "Absolute Zero: the 4th hit on a chilled foe freezes it (stun %.2f)" % e.stun_t)
	# Ice Shards: a chilled foe that dies shatters into its neighbours
	await _fresh(h, "archer", {"a_shards": 1})
	e = _foe(h, Vector3(3, 0, 0), "zombie", 30.0)
	o = _foe(h, Vector3(4.5, 0, 1))
	e.chill(0.3, 3.0)
	var l0: float = o.life
	_hit(h, e, 50.0)
	await process_frame
	check(o.life < l0 and o.chill_t > 0.0, "Ice Shards: the neighbour is hurt and chilled (%.0f -> %.0f)" % [l0, o.life])
	# Forked Shots: plain shots arc to two more
	await _fresh(h, "archer", {"a_forked": 1})
	e = _foe(h, Vector3(3, 0, 0), "zombie", 100000.0)
	var o1 = _foe(h, Vector3(5, 0, 1))
	var o2 = _foe(h, Vector3(7, 0, -1))
	_hit(h, e)
	check(o1.life < o1.max_life and o2.life < o2.max_life, "Forked Shots: lightning leaps to the two nearest")
	# Ricochet
	await _fresh(h, "archer", {"a_ricochet": 1})
	e = _foe(h, Vector3(3, 0, 0), "zombie", 100000.0)
	o1 = _foe(h, Vector3(6, 0, 2))
	_hit(h, e)
	check(o1.life < o1.max_life, "Ricochet: the shot glances on to the next foe")
	_hit(h, e, 1.0, "pierce")
	# Overcharge: crits call a bolt (force a crit)
	await _fresh(h, "archer", {"a_overcharge": 1})
	e = _foe(h, Vector3(3, 0, 0), "zombie", 100000.0)
	o1 = _foe(h, Vector3(4, 0, 0.5))
	RT.on_hit(h, e, 50.0, true, "attack")
	check(o1.life < o1.max_life, "Overcharge: a critical hit's bolt strikes around its foe")
	# Quarry: the marked foe
	await _fresh(h, "archer", {"a_quarry": 1})
	e = _foe(h, Vector3(3, 0, 0))
	h.mark = e
	h.mark_t = 5.0
	check(is_equal_approx(RT.hit_mult(h, e, "attack"), 1.3), "Quarry: +30% on the foe shot last")
	# Phoenix Quiver: every 5th shot looses a Fire Arrow
	await _fresh(h, "archer", {"a_phoenix": 1})
	h.run.skills.append("pierce")
	var arrows0: int = h.arrows.size()
	h.atk_aim = h.global_position + Vector3(8, 0, 0)
	for i in 5:
		RT.on_shot(h)
	check(h.arrows.size() == arrows0 + 1 and h.arrows[-1]["pierce"], "Phoenix Quiver: the 5th shot looses a free Fire Arrow")
	# Pack Leader: the wolf hits harder (through the talent key)
	await _fresh(h, "archer", {"a_packleader": 1})
	check(h.talent("wolf_dmg") == 100.0 and h.talent("wolf_heal") == 2.0, "Pack Leader: the wolf's talent keys reach the hero")

func _plague(h) -> void:
	# Necrosis grows the poison; Septic more vs poisoned; Contagion passes poison on death; Pandemic's cloud
	await _fresh(h, "plague", {"p_necrosis": 1, "p_septic": 2})
	var e = _foe(h, Vector3(3, 0, 0), "zombie", 100000.0)
	Plague.poison(h, e, "toxic", 5.0)
	check(RT.poisoned(h, e) and is_equal_approx(RT.hit_mult(h, e, "attack"), 1.3), "Septic Wounds x2: +30% on a poisoned foe")
	check(RT.poison_mult(h, 0.0) == 1.0 and is_equal_approx(RT.poison_mult(h, 3.0), 1.6) and is_equal_approx(RT.poison_mult(h, 30.0), 2.6),
		"Necrosis: poison grows 20%% a second to +160%% (%.2f, %.2f)" % [RT.poison_mult(h, 3.0), RT.poison_mult(h, 30.0)])
	await _fresh(h, "plague", {"p_contagion": 1})
	e = _foe(h, Vector3(3, 0, 0), "zombie", 30.0)
	var o1 = _foe(h, Vector3(5, 0, 1))
	var o2 = _foe(h, Vector3(3, 0, 3))
	Plague.poison(h, e, "toxic", 5.0)
	_hit(h, e, 50.0)
	await process_frame
	check(e.dead and RT.poisoned(h, o1) and RT.poisoned(h, o2), "Contagion: the poisoned foe's death passes its poison to its neighbours")
	await _fresh(h, "plague", {"p_pandemic": 1})
	e = _foe(h, Vector3(3, 0, 0), "zombie", 30.0)
	o1 = _foe(h, Vector3(4.5, 0, 1))
	Plague.poison(h, e, "toxic", 5.0)
	var l0: float = o1.life
	_hit(h, e, 50.0)
	await process_frame
	check(o1.life < l0 and RT.poisoned(h, o1), "Pandemic: the death's plague cloud hurts and poisons the neighbour")
	await _fresh(h, "plague", {"p_carrier": 1})
	e = _foe(h, Vector3(3, 0, 0), "zombie", 100000.0)
	o1 = _foe(h, Vector3(5, 0, 1))
	Plague.poison(h, e, "toxic", 5.0)
	_hit(h, e)
	check(RT.poisoned(h, o1), "Plague Carrier: a cane blow passes the poison on")
	await _fresh(h, "plague", {"p_toxblood": 1})
	h.life = h.max_life * 0.5
	var lf: float = h.life
	RT.on_dot(h, null, 100.0)
	check(is_equal_approx(h.life, lf + 8.0), "Toxic Blood: 8% of the poison's damage heals")
	await _fresh(h, "plague", {"p_double": 1, "p_volatile": 1})
	h.run.skills.append("toxic")
	check(h.talent("vial_twin") == 1.0 and h.talent("vial_burst") == 80.0, "Double Dose and Volatile Reagents reach the vial's code")
	var vial := Plague.skill(h, "toxic") as PestilenceVial
	var n0: int = vial.flights.size()
	h.atk_aim = h.global_position + Vector3(6, 0, 0)
	vial.impact()
	check(vial.flights.size() == n0 + 2, "Double Dose: two vials fly")

func _generic(h) -> void:
	await _fresh(h, "archer", {"x_execute": 1, "x_giant": 2})
	var e = _foe(h, Vector3(3, 0, 0))
	e.life = e.max_life * 0.2
	check(is_equal_approx(RT.hit_mult(h, e, "attack"), 1.6), "Executioner: +60% under a quarter of its life")
	e.champion = true
	check(is_equal_approx(RT.hit_mult(h, e, "attack"), 1.6 * 1.4), "Giant Slayer x2: +40% on a champion")
	# Momentum stacks on kills and runs out
	await _fresh(h, "archer", {"x_momentum": 1})
	var d0: float = h.talent("dmg")
	for i in 3:
		e = _foe(h, Vector3(3 + i, 0, 0), "zombie", 10.0)
		_hit(h, e, 50.0)
		await process_frame
	check(is_equal_approx(h.talent("dmg"), d0 + 12.0), "Momentum: three kills, +12%% damage (%.0f)" % (h.talent("dmg") - d0))
	RT.tick(h, 9.0)
	check(is_equal_approx(h.talent("dmg"), d0), "Momentum: it runs out")
	# Vampiric heals on kill
	await _fresh(h, "archer", {"x_vampire": 2})
	h.life = h.max_life * 0.5
	var lf: float = h.life
	e = _foe(h, Vector3(3, 0, 0), "zombie", 10.0)
	_hit(h, e, 50.0)
	await process_frame
	check(h.life >= lf + h.max_life * 0.059, "Vampiric x2: a kill heals 6%")
	# Chain Reaction: kills explode
	await _fresh(h, "archer", {"x_chain": 1})
	e = _foe(h, Vector3(3, 0, 0), "zombie", 200.0)
	var o = _foe(h, Vector3(4.5, 0, 1), "zombie", 1000.0)
	_hit(h, e, 500.0)
	await process_frame
	check(o.life < 1000.0, "Chain Reaction: the dead explode into their neighbours (%.0f)" % o.life)
	# Undying refuses a killing blow, once in its time
	await _fresh(h, "archer", {"x_undying": 1})
	h.take_hit(h.max_life * 5.0, h.global_position + Vector3(1, 0, 0), "melee", "fire")
	check(not h.dead and h.life >= h.max_life * 0.3, "Undying: the killing blow leaves %.0f%% life" % (h.life / h.max_life * 100.0))
	h.take_hit(h.max_life * 5.0, h.global_position + Vector3(1, 0, 0), "melee", "fire")
	check(h.dead, "Undying: not twice in its time")
	h.dead = false
	# Retribution: the attacker takes it back
	await _fresh(h, "archer", {"x_thorns": 1})
	e = _foe(h, Vector3(1.2, 0, 0), "zombie", 1000.0)
	h.take_hit(50.0, e.global_position, "melee", "phys")
	check(e.life < 1000.0, "Retribution: the monster that struck takes the blow back (%.0f)" % e.life)
	# Glass Cannon is stats
	await _fresh(h, "archer", {"x_glass": 1})
	check(h.talent("dmg") >= 35.0 and h.talent("life_pct") <= -20.0, "Glass Cannon: +35% damage, -20% life")
	# Echo brings a cooldown back (try many times: 25%)
	await _fresh(h, "archer", {"x_echo": 1})
	var back := 0
	for i in 200:
		h.cds["snare"] = 5.0
		RT.on_cooldown(h, "snare")
		if h.cds["snare"] == 0.0:
			back += 1
	check(back > 25 and back < 80, "Echo: about a quarter of cooldowns come back (%d of 200)" % back)
	# Berserker grows as life falls
	await _fresh(h, "archer", {"x_berserk": 1})
	e = _foe(h, Vector3(3, 0, 0))
	h.life = h.max_life
	var full: float = RT.hit_mult(h, e, "attack")
	h.life = h.max_life * 0.2
	check(is_equal_approx(full, 1.0) and is_equal_approx(RT.hit_mult(h, e, "attack"), 1.45), "Berserker: +45% at a fifth of life")

func _gems(h) -> void:
	await _fresh(h, "archer", {}, ["ruby", "ruby", "jade"])
	check(is_equal_approx(h.talent("dmg"), 12.0) and is_equal_approx(h.talent("burn_pct"), 30.0) and is_equal_approx(h.talent("life_pct"), 10.0), "gems' stats add up (two rubies and a jade)")
	await _fresh(h, "archer", {}, ["tempest"])
	var e = _foe(h, Vector3(3, 0, 0), "zombie", 100000.0)
	var o = _foe(h, Vector3(4, 0, 0.5))
	for i in 8:
		_hit(h, e, 0.01)
	check(o.life < o.max_life, "Eye of the Tempest: the 8th hit's bolt")
	await _fresh(h, "archer", {}, ["hunger"])
	for i in 5:
		e = _foe(h, Vector3(3, 0, 0), "zombie", 10.0)
		_hit(h, e, 50.0)
		await process_frame
	check(is_equal_approx(h.run.hunger, 5.0) and is_equal_approx(RT.hit_mult(h, _foe(h, Vector3(3, 0, 0)), "attack"), 1.05), "Hunger Stone: five kills, +5% for the run")
	var d: Dictionary = h.run.to_dict()
	check(RB.from_dict(d).hunger == 5.0 and RB.from_dict(d).gems == ["hunger"], "gems and the Hunger Stone are saved")
	await _fresh(h, "archer", {}, ["phoenix"])
	h.take_hit(h.max_life * 5.0, h.global_position + Vector3(1, 0, 0), "melee", "fire")
	check(not h.dead and h.life >= h.max_life * 0.55, "Phoenix Ember: rises once")
	h.take_hit(h.max_life * 5.0, h.global_position + Vector3(1, 0, 0), "melee", "fire")
	check(h.dead, "Phoenix Ember: only once a run")
	h.dead = false
	# the Seer's Eye and the Crown Shard change the offers
	await _fresh(h, "archer", {}, ["seer"])
	check(h.run.roll_offer("archer", 2, "seer_probe", h.binds).size() == 4, "Seer's Eye: four choices")
	await _fresh(h, "archer", {}, ["crownshard"])
	var tot := 0
	for k in 40:
		for c in h.run.roll_offer("archer", 1, "crown%d" % k, h.binds):
			tot += int(c["rarity"])
	await _fresh(h, "archer", {}, [])
	var tot0 := 0
	for k in 40:
		for c in h.run.roll_offer("archer", 1, "crown%d" % k, h.binds):
			tot0 += int(c["rarity"])
	check(tot > tot0, "Shard of the Crown: offers are rarer (%d vs %d)" % [tot, tot0])
	# a chest's gem: rolled once, found when it opens
	await _fresh(h, "archer", {}, [])
	var found := 0
	for k in 30:
		var o2: Dictionary = h.run.offer_for("archer", "gemprobe%d" % k, 4, h.binds)
		if str(o2["gem"]) != "":
			found += 1
	check(found == 30 and h.run.gems.size() == 30, "a boss chest always holds a gem (%d of 30)" % found)

func _consumables(h) -> void:
	await _fresh(h, "archer", {})
	h.belt = [null, null, null, null]
	check(h.add_to_inventory(load("res://game/items/items.gd").potion("elixir_fury")), "an elixir goes on the belt")
	var d0: float = h.talent("dmg")
	h.drink(0)
	check(is_equal_approx(h.talent("dmg"), d0 + 30.0), "Elixir of Fury: +30% damage")
	RT.tick(h, 21.0)
	check(is_equal_approx(h.talent("dmg"), d0), "Elixir of Fury: runs out after 20 s")
	h.add_to_inventory(load("res://game/items/items.gd").potion("flask_frost"))
	var e = _foe(h, Vector3(5, 0, 0), "zombie", 100000.0)
	h.cursor = e.global_position
	h.drink(0)
	await create_timer(1.0).timeout
	check(e.life < e.max_life and e.stun_t > 0.5, "Frost Flask: thrown at the pointer, it hurts and freezes (stun %.2f)" % e.stun_t)
	h.add_to_inventory(load("res://game/items/items.gd").potion("scroll_ward"))
	h.drink(0)
	check(h.ward >= h.max_life * 0.39, "Scroll of Warding: a ward of 40%% of life (%.0f)" % h.ward)
	var lvl: int = h.level
	h.add_to_inventory(load("res://game/items/items.gd").potion("tome_insight"))
	h.drink(0)
	check(h.xp > 0 or h.level > lvl, "Tome of Insight: experience")
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var kinds := {}
	for i in 200:
		for c in RT.roll_consumables(1 + i % 4, rng):
			kinds[c] = true
	check(kinds.size() >= 10, "chests hand out the consumables' variety (%d kinds)" % kinds.size())

func _offers(h) -> void:
	# offers: 1-3 skills while skills are left, the build's themes pull, rarities 0-3
	await _fresh(h, "archer", {})
	var skills_seen := {}
	var epic := 0
	for k in 60:
		var o: Array = h.run.roll_offer("archer", 4, "probe%d" % k, h.binds)
		var n := o.filter(func(c): return c["kind"] == "skill").size()
		skills_seen[n] = true
		epic += o.filter(func(c): return int(c["rarity"]) == 2).size()
		if n < 1 or n > 3:
			check(false, "offer %d holds %d skills" % [k, n])
	check(skills_seen.size() >= 2 and epic > 10, "offers hold 1-3 skills (%s) and boss chests offer rares (%d)" % [str(skills_seen.keys()), epic])
	# pull: a frost build is offered frost more often than a fresh one
	var frost_fresh := 0
	for k in 80:
		for c in h.run.roll_offer("archer", 2, "pull%d" % k, h.binds):
			if c["theme"] == "frost":
				frost_fresh += 1
	h.run.skills = ["volley"]
	h.run.passives = {"a_biting": 3, "a_frostbite": 2}
	var frost_built := 0
	for k in 80:
		for c in h.run.roll_offer("archer", 2, "pull%d" % k, h.binds):
			if c["theme"] == "frost":
				frost_built += 1
	check(frost_built > frost_fresh * 1.3, "a frost build is offered frost more often (%d vs %d)" % [frost_built, frost_fresh])

## Cast one of a run's skills at `at` and let it play out.
func _cast(h, id: String, at: Vector3, secs := 2.5) -> bool:
	if not h.run.skills.has(id):
		h.run.skills.append(id)
	for k in h.cds.keys():
		h.cds[k] = 0.0
	h.cds[id] = 0.0
	h.mana = h.max_mana
	h.atk_t = -1.0
	h.cursor = at
	var ok: bool = h.use_skill(id, at)
	await create_timer(secs).timeout
	return ok

func _skills(h) -> void:
	# the archer's run skills
	await _fresh(h, "archer", {})
	var fan := [_foe(h, Vector3(5, 0, -1.5), "zombie", 5000.0), _foe(h, Vector3(5, 0, 0), "zombie", 5000.0), _foe(h, Vector3(5, 0, 1.5), "zombie", 5000.0)]
	var ok: bool = await _cast(h, "a_multishot", h.global_position + Vector3(5, 0, 0))
	check(ok and fan.all(func(e): return e.life < e.max_life), "Scatter Shot: the fan strikes three foes side by side")
	await _fresh(h, "archer", {})
	var line := [_foe(h, Vector3(4, 0, 0), "zombie", 5000.0), _foe(h, Vector3(7, 0, 0), "zombie", 5000.0), _foe(h, Vector3(10, 0, 0), "zombie", 5000.0)]
	ok = await _cast(h, "a_glacial", h.global_position + Vector3(10, 0, 0))
	check(ok and line.all(func(e): return e.life < e.max_life and e.chill_t > 0.0), "Glacial Shard: pierces the line and chills each")
	await _fresh(h, "archer", {})
	var e1 = _foe(h, Vector3(6, 0, 0), "zombie", 5000.0)
	var e2 = _foe(h, Vector3(7.5, 0, 1.5), "zombie", 5000.0)
	ok = await _cast(h, "a_explosive", e1.global_position)
	check(ok and e1.life < e1.max_life and e2.life < e2.max_life and e2.burn_t > 0.0, "Blast Arrow: bursts on the first foe, burning its neighbour")
	await _fresh(h, "archer", {})
	e1 = _foe(h, Vector3(6, 0, 0), "zombie", 5000.0)
	e2 = _foe(h, Vector3(9, 0, 2), "zombie", 5000.0)
	var e3 = _foe(h, Vector3(11, 0, -2), "zombie", 5000.0)
	ok = await _cast(h, "a_stormshot", e1.global_position)
	check(ok and e1.life < e1.max_life and e2.life < e2.max_life and e3.life < e3.max_life, "Storm Shot: lightning leaps on from its foe")
	await _fresh(h, "archer", {})
	e1 = _foe(h, Vector3(8, 0, 0), "zombie", 5000.0)
	ok = await _cast(h, "a_mark", e1.global_position, 0.8)
	var l0: float = e1.life
	h._hit_enemy(e1, 1.0, 0.0, "attack")
	var marked: float = l0 - e1.life
	e1.remove_meta("hunted_until")
	l0 = e1.life
	h._hit_enemy(e1, 1.0, 0.0, "attack")
	check(ok and h.mark == e1 and marked > 0.0, "Hunter's Mark: the foe is marked and the wolf sent (%.0f marked vs %.0f plain)" % [marked, l0 - e1.life])
	await _fresh(h, "archer", {})
	var area := [_foe(h, Vector3(9, 0, 0), "zombie", 5000.0), _foe(h, Vector3(10, 0, 2), "zombie", 5000.0)]
	ok = await _cast(h, "a_barrage", h.global_position + Vector3(9.5, 0, 1), 3.0)
	check(ok and area.all(func(e): return e.max_life - e.life > 0.0), "Arrow Storm: the rain strikes everything in it")
	# the plague doctor's
	await _fresh(h, "plague", {})
	var near := [_foe(h, Vector3(2, 0, 0), "zombie", 5000.0), _foe(h, Vector3(-2, 0, 2), "zombie", 5000.0)]
	ok = await _cast(h, "p_miasma", h.global_position, 1.5)
	check(ok and near.all(func(e): return RT.poisoned(h, e)), "Miasma: everything round him is poisoned")
	await _fresh(h, "plague", {})
	e1 = _foe(h, Vector3(7, 0, 0), "zombie", 5000.0)
	e2 = _foe(h, Vector3(9, 0, 2), "zombie", 5000.0)
	ok = await _cast(h, "p_spread", e1.global_position, 1.8)
	check(ok and RT.poisoned(h, e1) and RT.poisoned(h, e2), "Contagion: the cursed foe's plague leaps to its neighbour")
	await _fresh(h, "plague", {})
	e1 = _foe(h, Vector3(6, 0, 0), "zombie", 5000.0)
	e2 = _foe(h, Vector3(6.5, 0, 1), "zombie", 5000.0)
	h.life = h.max_life * 0.4
	var lf: float = h.life
	ok = await _cast(h, "p_leech", e1.global_position, 3.0)
	check(ok and RT.poisoned(h, e1) and h.life > lf + h.max_life * 0.03, "Leech Jar: the pool poisons and heals him (%.0f -> %.0f)" % [lf, h.life])
	# skill upgrades
	await _fresh(h, "archer", {"a_up_fan": 1})
	var a0: int = h.arrows.size()
	await _cast(h, "a_multishot", h.global_position + Vector3(6, 0, 0), 0.05)
	await create_timer(0.9).timeout
	check(h.arrows.size() >= a0 + 7 or h.talent("multishot_more") == 2.0, "Wide Fan: seven arrows (%d in the air)" % (h.arrows.size() - a0))
	await _fresh(h, "archer", {"a_up_death": 1})
	e1 = _foe(h, Vector3(6, 0, 0), "zombie", 30.0)
	await _cast(h, "a_mark", e1.global_position, 0.8)
	h.cds["a_mark"] = 6.0
	h._hit_enemy(e1, 50.0, 0.0, "attack")
	await process_frame
	check(e1.dead and h.cds["a_mark"] == 0.0 and h.talent("dmg") >= 25.0, "Marked for Death: the marked kill readies the mark and gives +25%")
	await _fresh(h, "plague", {"p_up_epidemic": 1})
	e1 = _foe(h, Vector3(6, 0, 0), "zombie", 40.0)
	e2 = _foe(h, Vector3(9, 0, 3), "zombie", 5000.0)
	await _cast(h, "p_spread", e1.global_position, 0.6)
	h._hit_enemy(e1, 80.0, 0.0, "attack")
	await create_timer(0.3).timeout
	check(e1.dead and (Plague.skill(h, "p_spread") as Contagion).curses.has(e2.get_instance_id()), "Epidemic: the curse leaps to the next foe when its host dies")
	# the knight's
	await _fresh(h, "knight", {})
	var spin := [_foe(h, Vector3(2, 0, 0), "zombie", 5000.0), _foe(h, Vector3(-2, 0, 1), "zombie", 5000.0)]
	h.run.skills.append("k_judgment")
	ok = await _cast(h, "k_whirl", h.global_position, 1.5)
	check(ok and spin.all(func(e): return e.life < e.max_life and load("res://game/heroes/knight/shared/holy_brands.gd").count(e) >= 2), "Blade Storm: strikes all round twice, branding them")
	l0 = spin[0].life
	ok = await _cast(h, "k_judgment", spin[0].global_position, 1.5)
	var branded_hit: float = l0 - spin[0].life
	check(ok and load("res://game/heroes/knight/shared/holy_brands.gd").count(spin[0]) == 0 and branded_hit > 0.0, "Judgment: the pillar spends the brands (%.0f)" % branded_hit)
	await _fresh(h, "knight", {})
	var near2 = _foe(h, Vector3(2.5, 0, 0), "zombie", 5000.0)
	ok = await _cast(h, "k_aegis", h.global_position, 1.0)
	check(ok and h.ward > h.max_life * 0.3 and near2.taunt == h, "Aegis: a ward of a third of his life, and the foe turns on him (ward %.0f of %.0f, taunt %s)" % [h.ward, h.max_life, str(near2.taunt)])
	h.take_hit(h.max_life * 0.2, near2.global_position, "melee", "fire")
	await create_timer(5.5).timeout
	check(near2.life < near2.max_life, "Aegis: it bursts for what it soaked")
	await _fresh(h, "knight", {})
	var low = _foe(h, Vector3(6, 0, 0), "zombie", 1000.0)
	low.life = 12.0
	h.cds["k_rites"] = 0.0
	ok = await _cast(h, "k_rites", low.global_position, 1.5)
	check(ok and low.dead and h.cds["k_rites"] == 0.0, "Last Rites: the execute kills and the leap is ready again (ok %s dead %s life %.0f cd %.1f dist %.1f)" % [ok, low.dead, low.life, h.cds["k_rites"], h.global_position.distance_to(low.global_position)])
	# the Wraith's
	await _fresh(h, "wraith", {})
	var dmk = _foe(h, Vector3(5, 0, 0), "zombie", 5000.0)
	ok = await _cast(h, "r_deathmark", dmk.global_position, 0.9)
	check(ok and dmk.has_meta("deathmark"), "Death Mark: the foe is marked")
	h._hit_enemy(dmk, 5.0, 0.0, "attack")
	var before_pop: float = dmk.life
	await create_timer(3.0).timeout
	check(not dmk.has_meta("deathmark") and dmk.life < before_pop, "Death Mark: it tears out what it stored (%.0f -> %.0f)" % [before_pop, dmk.life])
	await _fresh(h, "wraith", {})
	var wail := [_foe(h, Vector3(3, 0, 0), "zombie", 5000.0), _foe(h, Vector3(-3, 0, 2), "zombie", 5000.0)]
	ok = await _cast(h, "r_wail", h.global_position, 1.2)
	check(ok and wail.all(func(e): return e.life < e.max_life and e.slow_t > 0.0), "Banshee Wail: strikes, terrifies and slows all round")
	await _fresh(h, "wraith", {})
	var reap := [_foe(h, Vector3(0, 0, -3), "zombie", 5000.0), _foe(h, Vector3(1.5, 0, -3.5), "zombie", 5000.0)]
	h._face(Vector3(0, 0, -1))
	h.life = h.max_life * 0.5
	lf = h.life
	ok = await _cast(h, "r_reap", h.global_position + Vector3(0, 0, -4), 1.5)
	check(ok and reap.all(func(e): return e.life < e.max_life) and h.life > lf, "Reaping Crescent: reaps the arc in front and heals")
	# the Demon's
	var DS = load("res://game/heroes/demon/demon.gd")
	await _fresh(h, "demon", {})
	var vic := [_foe(h, Vector3(8, 0, 0), "zombie", 5000.0), _foe(h, Vector3(9, 0, 1.5), "zombie", 5000.0)]
	ok = await _cast(h, "d_volcano", vic[0].global_position, 3.5)
	check(ok and vic.all(func(e): return e.life < e.max_life), "Volcano: its meteors fall on the foes round it")
	await _fresh(h, "demon", {})
	var br = _foe(h, Vector3(4, 0, 0), "zombie", 5000.0)
	var plain = _foe(h, Vector3(-6, 0, 0), "zombie", 5000.0)
	DS.brands(h).mark(br)
	ok = await _cast(h, "d_detonate", h.global_position, 1.2)
	check(ok and br.life < br.max_life and not DS.brands(h).has(br) and is_equal_approx(plain.life, plain.max_life), "Hellbrand Detonation: the Branded foe erupts, the Brand spent, the unbranded spared")
	await _fresh(h, "demon", {})
	var d0: float = h.talent("dmg")
	var l0p: float = h.life
	ok = await _cast(h, "d_pact", h.global_position, 1.0)
	check(ok and h.life < l0p and is_equal_approx(h.talent("dmg"), d0 + 35.0) and h.talent("ls") >= 6.0, "Blood Pact: life paid for +35% damage and life steal")
	# Doug's
	await _fresh(h, "doug", {})
	var crowd := [_foe(h, Vector3(7, 0, 0), "zombie", 5000.0), _foe(h, Vector3(8, 0, 1.5), "zombie", 5000.0), _foe(h, Vector3(6.5, 0, -1.5), "zombie", 5000.0)]
	ok = await _cast(h, "u_barrage", crowd[0].global_position, 2.0)
	check(ok and crowd.all(func(e): return e.life < e.max_life), "Pie Barrage: a pie for every foe round the pointer")
	await _fresh(h, "doug", {})
	ok = await _cast(h, "u_bonanza", h.global_position, 1.2)
	var peels_n: int = (load("res://game/heroes/doug/doug.gd").skill(h, "peels").peels as Array).size()
	check(ok and peels_n >= 8, "Banana Bonanza: a ring of eight peels (%d)" % peels_n)
	await _fresh(h, "doug", {})
	var far = _foe(h, Vector3(11, 0, 0), "zombie", 5000.0)
	var p0: Vector3 = h.global_position
	ok = await _cast(h, "u_cannon", far.global_position, 2.0)
	check(ok and h.global_position.distance_to(p0) > 7.0 and far.life < far.max_life, "Human Cannonball: he flies to the pointer and flattens what's there")
	# the Frost Serpent's
	await _fresh(h, "serpent", {})
	var tomb := [_foe(h, Vector3(7, 0, 0), "zombie", 5000.0), _foe(h, Vector3(8.2, 0, 1.2), "zombie", 5000.0)]
	ok = await _cast(h, "s_tomb", tomb[0].global_position, 0.9)
	check(ok and tomb.all(func(e): return e.stun_t > 0.0 and is_equal_approx(e.life, e.max_life)), "Glacial Tomb: the foe and the one beside it are sealed (stunned, not yet hurt)")
	await create_timer(1.8).timeout
	check(tomb.all(func(e): return e.life < e.max_life), "Glacial Tomb: the tomb shatters on them")
	await _fresh(h, "serpent", {})
	var coil := [_foe(h, Vector3(2.5, 0, 0), "zombie", 5000.0), _foe(h, Vector3(-2.5, 0, 1.5), "zombie", 5000.0)]
	coil[1].chill(0.5, 5.0)
	ok = await _cast(h, "s_coil", h.global_position, 1.6)
	var c0: float = coil[0].max_life - coil[0].life
	var c1: float = coil[1].max_life - coil[1].life
	check(ok and c0 > 0.0 and c1 > 0.0 and coil.all(func(e): return e.slow_t > 0.0), "Crushing Coil: crushes all round and slows them (%.0f, chilled %.0f)" % [c0, c1])
	await _fresh(h, "serpent", {})
	var lance := [_foe(h, Vector3(0, 0, -4), "zombie", 5000.0), _foe(h, Vector3(0.4, 0, -8), "zombie", 5000.0)]
	lance[1].chill(0.5, 5.0)
	h._face(Vector3(0, 0, -1))
	ok = await _cast(h, "s_lance", h.global_position + Vector3(0, 0, -9), 0.95)
	check(ok and lance.all(func(e): return e.life < e.max_life) and lance[0].chill_t > 0.0 and lance[1].stun_t > 0.0, "Rime Lance: the line chills the first and freezes the one already chilled")
	# the Storm Wyvern's
	await _fresh(h, "wyvern", {})
	var dfar = _foe(h, Vector3(10, 0, 0), "zombie", 5000.0)
	var dp0: Vector3 = h.global_position
	ok = await _cast(h, "v_dive", dfar.global_position, 0.9)
	check(ok and h.global_position.distance_to(dp0) > 7.0 and dfar.life < dfar.max_life and dfar.stun_t > 0.0, "Thunder Dive: it flies to the pointer, strikes and stuns (moved %.1f m)" % h.global_position.distance_to(dp0))
	await create_timer(0.6).timeout
	check(h.rig == null or (is_zero_approx(h.rig.position.y) and not h.rig.has_meta("fly")), "Thunder Dive: down on its feet after")
	await _fresh(h, "wyvern", {})
	var under := [_foe(h, Vector3(8, 0, 0), "zombie", 5000.0), _foe(h, Vector3(9, 0, 2), "zombie", 5000.0)]
	ok = await _cast(h, "v_cloud", under[0].global_position, 4.8)
	var cl_hurt: float = under.reduce(func(acc, e): return acc + (e.max_life - e.life), 0.0)
	check(ok and cl_hurt > 0.0 and (h.kit["v_cloud"].clouds as Array).is_empty(), "Thunderhead: its bolts strike beneath it, then it's gone (%.0f dealt)" % cl_hurt)
	await _fresh(h, "wyvern", {})
	var gale = _foe(h, Vector3(0, 0, -3), "zombie", 5000.0)
	var behind = _foe(h, Vector3(0, 0, 4), "zombie", 5000.0)
	gale.scripted = false
	h._face(Vector3(0, 0, -1))
	var gp0: Vector3 = gale.global_position
	ok = await _cast(h, "v_gale", h.global_position + Vector3(0, 0, -5), 1.0)
	check(ok and gale.life < gale.max_life and gale.slow_t > 0.0 and is_equal_approx(behind.life, behind.max_life), "Gale Wings: the cone ahead is struck and slowed, the one behind spared (pushed %.1f m)" % gale.global_position.distance_to(gp0))
	# every run skill is in its class's pool and reads its theme
	for cls in ["archer", "plague", "serpent", "wyvern"]:
		var ids: Array = RB.skill_pool(cls).map(func(s): return s["id"])
		var run_ids: Array = load("res://game/systems/data/data.gd").run_skills_for(cls).map(func(s): return s["id"])
		check(run_ids.all(func(i): return ids.has(i) and RT.SKILL_THEMES.has(i)), "%s: run skills in the pool with their themes (%d skills to find)" % [cls, ids.size()])
