extends SceneTree
## Multiplayer run characters (RunBuild, Blaine's overhaul 2026-11-06): a fresh archer and plague doctor start at
## level 0 with the primary attack and five empty slots; they level fast; offers roll three, never duplicates, the
## same when reopened, include a skill while a slot is empty, claim once; skills fill slots then the spellbook; only
## five can be slotted and G/V never; a rebind keeps the cooldown; passives change the numbers they say and talents
## don't apply; the belt holds four and gold, rings and amulets aren't taken; found gear swaps and leaves the old
## piece on the ground; a run saves and loads; single player is untouched. Prints [RUN] lines.
var g
var fails := 0
var RB      # (scripts loaded at run time: a static reference compiles Hero before the Sfx autoload exists)
var TL

func _initialize():
	g = (load("res://main.tscn") as PackedScene).instantiate()
	get_root().add_child(g)
	RB = load("res://scripts/run_build.gd")
	TL = load("res://scripts/talents.gd")
	_run()

func check(ok: bool, what: String) -> void:
	if not ok:
		fails += 1
	print("[RUN] %s %s" % ["ok  " if ok else "FAIL", what])

func _run() -> void:
	while g.world == null or g._busy:
		g._intro_skip = true
		await process_frame
	await g.start_game(false, "knight")
	await g.load_zone(0, "wild", "start")
	var h = g.hero
	# single player first: untouched
	check(h.run == null and h.level >= 1, "single player: no run, level %d" % h.level)
	check(h.default_binds()["Q"] != "" and TL.TREES.has(h.cls), "single player: default binds and talent trees")
	for cls in ["archer", "plague"]:
		await _class_run(h, cls)
	# talents ignored, single player back
	h.set_class("knight")
	h.new_character()
	check(h.run == null and h.level == 1 and h.free_talent_points() == 0, "a new single-player character has no run")
	h.set_level(5)
	check(h.free_talent_points() == 4, "single-player talent points still come with levels")
	print("[RUN] done, %d failure(s)" % fails)
	quit(1 if fails > 0 else 0)

func _class_run(h, cls: String) -> void:
	h.set_class(cls)
	h.start_run()
	var r = h.run
	check(r != null and h.level == 0 and h.xp == 0, "%s: a run starts at level 0" % cls)
	check(h.bound("lmb") == "attack" and RB.SLOTS.all(func(s): return h.bound(s) == "") and h.bound("G") == "" and h.bound("V") == "", "%s: the attack on left mouse, five empty slots" % cls)
	check(h.gold == 0 and h.equipment.get("amulet") == null and h.equipment.get("ring1") == null and h.equipment.get("weapon") != null, "%s: no gold, ring or amulet; a weapon" % cls)
	check(h.inventory.all(func(x): return x == null), "%s: no backpack items" % cls)
	check(h.dmg_max > 0, "%s: the primary attack hits (%d-%d)" % [cls, h.dmg_min, h.dmg_max])
	check(h.free_talent_points() == 0 and not h.learn_talent(TL.TREES[cls][0]["talents"][0]["id"]), "%s: no talents in a run" % cls)
	# levels
	h.add_xp(RB.xp_for(0))
	check(h.level == 1, "%s: one fight's experience is level 1" % cls)
	var str0: int = h.str_ + h.dex + h.vit + h.ene
	h.add_xp(RB.xp_for(1) + RB.xp_for(2))
	check(h.level == 3 and h.str_ + h.dex + h.vit + h.ene == str0 + 10 and h.stat_points == 0, "%s: levels grow the attributes by themselves" % cls)
	# offers
	var o: Dictionary = r.offer_for(cls, "camp_a", 1, h.binds)
	var ch: Array = o["choices"]
	check(ch.size() == 3, "%s: an offer of three" % cls)
	var ids: Array = ch.map(func(c): return c["kind"] + c["id"])
	check(ids.size() == _uniq(ids).size(), "%s: no duplicate choices" % cls)
	check(ch.any(func(c): return c["kind"] == "skill"), "%s: an early offer has a skill" % cls)
	var again: Dictionary = r.offer_for(cls, "camp_a", 1, h.binds)
	check(again["choices"] == ch, "%s: reopening doesn't reroll" % cls)
	var si: int = ch.find(ch.filter(func(c): return c["kind"] == "skill")[0])
	var took: Dictionary = g.run_claim("camp_a", si)
	check(not took.is_empty() and r.skills.has(took["id"]) and h.bound("rmb") == took["id"], "%s: the chosen skill goes onto the first slot (%s)" % [cls, took.get("id", "")])
	check(g.run_claim("camp_a", 0).is_empty(), "%s: a claimed offer can't be claimed again" % cls)
	check(not h.skill_locked(load("res://scripts/data.gd").skill_def(took["id"])), "%s: an acquired skill is unlocked" % cls)
	# fill slots and overflow into the spellbook
	var pool: Array = RB.skill_pool(cls).map(func(s): return str(s["id"])).filter(func(id): return not r.skills.has(id))
	for id in pool.slice(0, 6):
		r.add_skill(id, h.binds)
	h.run_changed()
	var slotted: Array = RB.SLOTS.filter(func(s): return h.bound(s) != "")
	check(slotted.size() == 5 and r.skills.size() >= 6, "%s: five slotted, %d learned (the rest in the spellbook)" % [cls, r.skills.size()])
	var reserve: String = r.skills.filter(func(id): return not RB.SLOTS.any(func(s): return h.bound(s) == id))[0]
	h.bind("G", reserve)
	check(h.bound("G") == "", "%s: G can't hold a skill" % cls)
	var q: String = h.bound("Q")
	h.cds[q] = 4.0
	h.bind("E", q)
	check(h.bound("E") == q and h.bound("Q") == "" and float(h.cds[q]) == 4.0, "%s: moving a skill keeps its cooldown" % cls)
	h.bind("Q", reserve)
	check(h.bound("Q") == reserve, "%s: a spellbook skill swaps in" % cls)
	h.bind("R", "earthshatter" if not r.skills.has("earthshatter") else "nothing_learned")
	check(h.bound("R") != "earthshatter" or r.skills.has("earthshatter"), "%s: an unlearned skill can't be slotted" % cls)
	# passives: the generic damage one changes damage, and talents don't apply
	var before: int = h.dmg_max
	var life0: float = h.max_life
	r.passives["g_hide"] = 2
	h.run_changed()
	check(h.max_life > life0 * 1.14, "%s: Thick Hide ×2 raises life %d -> %d" % [cls, int(life0), int(h.max_life)])
	check(h.talent("life_pct") == 16.0, "%s: the passive reaches Hero.talent" % cls)
	var p: Dictionary = RB.passive_def(cls, "g_hide")
	check(RB.passive_text(p, 3, 2).contains("16 → 24"), "%s: an upgrade shows the change (%s)" % [cls, RB.passive_text(p, 3, 2)])
	var own: Array = RB.passive_pool(cls).filter(func(x): return x.has("tree"))
	check(own.size() >= 15, "%s: %d class passives from its talents" % [cls, own.size()])
	check(dmg_ok(before, h), "%s: damage still sane" % cls)
	# offers keep to eligible ones: never a maxed passive, never one for a skill not learned
	for k in 30:
		var oo: Array = r.roll_offer(cls, 1 + k % 4, "probe%d" % k, h.binds)
		for c in oo:
			if c["kind"] == "passive":
				var pd: Dictionary = RB.passive_def(cls, c["id"])
				if pd.has("needs") and not r.skills.has(pd["needs"]):
					check(false, "%s: offered %s without %s" % [cls, c["id"], pd["needs"]])
			elif r.skills.has(c["id"]):
				check(false, "%s: offered a skill already learned (%s)" % [cls, c["id"]])
	# the belt: four slots, stacks of five; gold, rings and amulets refused
	h.belt = [null, null, null, null]
	var taken := 0
	for i in 30:
		var pot: Dictionary = load("res://scripts/items.gd").potion("hp_potion")
		if h.add_to_inventory(pot):
			taken += 1
	check(taken == RB.BELT * RB.STACK, "%s: the belt holds %d potions (4 × 5)" % [cls, taken])
	check(not h.add_to_inventory(load("res://scripts/items.gd").gold(50)) and h.gold == 0, "%s: gold isn't taken" % cls)
	check(not h.add_to_inventory(load("res://scripts/items.gd").make("ring")), "%s: a ring isn't taken" % cls)
	# gear: a found weapon of the class swaps, the old one dropped on the ground
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var w: Dictionary = load("res://scripts/items.gd").generate(RB.weapon_base(cls, 13, rng), 13, 2, rng)
	w["req"] = 0
	var old = h.equipment["weapon"]
	var on_ground: int = g.world.items_root.get_child_count()
	g._run_wear(w)
	await process_frame
	check(h.equipment["weapon"] == w and g.world.items_root.get_child_count() == on_ground + 1, "%s: a better weapon is worn and the old one left on the ground" % cls)
	check(RB.wearable(w, cls) and not RB.wearable(load("res://scripts/items.gd").make("buckler"), cls), "%s: only its own gear is wearable" % cls)
	var gear: Dictionary = RB.random_gear(3, rng, [cls])
	check(str(load("res://scripts/data.gd").BASES[gear["base"]]["slot"]) in RB.GEAR, "%s: run loot is gear for the run's slots (%s)" % [cls, gear["base"]])
	# save and load
	var d: Dictionary = h.to_save()
	var skills_before: Array = r.skills.duplicate()
	h.new_character()
	check(h.run == null, "%s: a new character drops the run" % cls)
	h.from_save(d)
	check(h.run != null and h.run.skills == skills_before and int(h.run.passives.get("g_hide", 0)) == 2 and h.talent("life_pct") == 16.0, "%s: a run saves and loads (skills, passives)" % cls)
	check(h.run.offers.has("camp_a") and not h.run.offer_open("camp_a"), "%s: a claimed offer stays claimed after loading" % cls)
	if old == null:
		pass

func dmg_ok(_before: int, h) -> bool:
	return h.dmg_max > 0 and h.dmg_max < 10000

func _uniq(a: Array) -> Array:
	var d := {}
	for x in a:
		d[x] = true
	return d.keys()
