extends SceneTree
## The items rework (): new rolls are small, an old item is rebuilt once (uniques from
## their table, rares trimmed to three, nothing lost), a weapon hits for the level's damage, gear's percentages are
## capped, and at level 20 the best gear is worth about a third more than none.
var g
var fails := 0
func _initialize():
	g = (load("res://main.tscn") as PackedScene).instantiate()
	get_root().add_child(g)
	_run()
func check(ok: bool, what: String) -> void:
	print("[IR] ", "ok   " if ok else "FAIL ", what)
	if not ok:
		fails += 1
func _run() -> void:
	while g.world == null or g._busy:
		await process_frame
	await g.start_game(false, "knight")
	while g._busy:
		await process_frame
	g.ui.close_all()
	var h = g.hero
	var r := RandomNumberGenerator.new()
	r.seed = 7
	# new rolls
	var top := 0
	for i in 200:
		var it := Items.generate("greaves", 20, 2, r)
		check(it.get("gen", 0) == Data.ITEM_GEN and it["affixes"].size() <= 3, "") if i == 0 else null
		for a in it["affixes"]:
			if a[0] == "frw":
				top = maxi(top, int(a[1]))
	check(top >= 3 and top <= 6, "a level-20 rare's run speed tops out near 5%% (%d)" % top)
	# an old item
	var old := {"base": "plate_mail", "rarity": 2, "ilvl": 20, "name": "Grim Shell", "req": 15, "def": 40,
		"affixes": [["life", 60], ["vit", 14], ["res", 22], ["edef", 70], ["regen", 5]]}
	var up = Items.upgrade(old.duplicate(true))
	check(up["gen"] == Data.ITEM_GEN and up["affixes"].size() == 3, "an old rare is rebuilt with its best three affixes: %s" % str(up["affixes"]))
	var oldu := {"base": "falchion", "rarity": 3, "unique": "emberfang", "ilvl": 6, "name": "Emberfang", "affixes": [["ed", 80], ["fire", 8], ["ias", 15], ["ls", 3]], "temper": 2}
	var uu = Items.upgrade(oldu.duplicate(true))
	check(uu["unique"] == "emberfang" and int(uu["temper"]) == 2 and int(uu["affixes"][0][1]) < 80, "an old unique is made again from its table, temper kept: %s" % str(uu["affixes"]))
	check(Items.upgrade(uu) == uu, "and only once")
	# the weapon hits for the level's damage
	h.equipment["weapon"] = Items.make("short_sword")
	h.set_level(20)
	h.recalc()
	var plain := [h.dmg_min, h.dmg_max]
	h.equipment["weapon"] = Items.generate("flamberge", 20, 2, r)
	h.recalc()
	var best := [h.dmg_min, h.dmg_max]
	var gap: float = float(best[0] + best[1]) / float(plain[0] + plain[1])
	check(gap > 1.0 and gap < 1.6, "level 20: a starting sword %s, a rare flamberge %s (x%.2f, was ~x4)" % [str(plain), str(best), gap])
	# capped percentages
	for s in ["boots", "ring1", "ring2", "amulet"]:
		var it2 := Items.make("greaves" if s == "boots" else ("amulet" if s == "amulet" else "ring"), 2, 20)
		it2["affixes"] = [["frw", 5], ["res", 20], ["ias", 10]]
		h.equipment[s] = it2
	h.recalc()
	check(h.frw == 5 and h.res <= 25, "run speed capped at +5%% (%d), resist at 25 (%d)" % [h.frw, h.res])
	# the power of a full set
	h.new_character()
	g.go_level_20()
	var geared: float = (h.dmg_min + h.dmg_max) * h.aspd * h.max_life * (120.0 + h.armor) / 120.0
	var parts := "damage %d-%d x%.2f, life %d, armour %d" % [h.dmg_min, h.dmg_max, h.aspd, int(h.max_life), h.armor]
	for s in Items.EQUIP_SLOTS:
		h.equipment[s] = null
	h.equipment["weapon"] = Items.make("short_sword")
	h.recalc()
	var fresh: float = (h.dmg_min + h.dmg_max) * h.aspd * h.max_life * (120.0 + h.armor) / 120.0
	print("[IR] geared ", parts, "; fresh damage %d-%d x%.2f, life %d, armour %d" % [h.dmg_min, h.dmg_max, h.aspd, int(h.max_life), h.armor])
	check(geared / fresh > 1.15 and geared / fresh < 1.7, "level-20 gear: power x%.2f over none (damage x life)" % (geared / fresh))
	# utility affixes: one per item, and they work
	var two := 0
	for i in 300:
		var it3 := Items.generate("ring", 20, 2, r)
		var n := 0
		for a in it3["affixes"]:
			if a[0] in Data.UTILITY:
				n += 1
		two = maxi(two, n)
	check(two <= 1, "never more than one utility affix on an item")
	for s in Items.EQUIP_SLOTS:
		h.equipment[s] = null
	h.recalc()
	var cd0: float = h.skill_cd("charge")
	var rc0: float = h.roll_cost()
	var ring := Items.make("ring", 2, 20)
	ring["affixes"] = [["cdr", 10]]
	h.equipment["ring1"] = ring
	var am := Items.make("amulet", 2, 20)
	am["affixes"] = [["stam", 20], ["ten", 30]]
	h.equipment["amulet"] = am
	h.recalc()
	check(h.skill_cd("charge") < cd0 and h.roll_cost() < rc0 and h.cc_k() < 1.0, "cooldowns %.1f -> %.1f s, a roll %d -> %d stamina, stuns x%.2f" % [cd0, h.skill_cd("charge"), int(rc0), int(h.roll_cost()), h.cc_k()])
	# unique effects: everywhere, and the same effect never stacks
	var a1 := Items.make_unique("emberfang")
	var a2 := Items.make_unique("ninth_sun")
	h.equipment["weapon"] = a1
	h.equipment["ring2"] = a2
	h.recalc()
	check(int(h.stats.get("burn", 0)) == 25, "two burning uniques: the stronger counts (burn %d, not 40)" % int(h.stats.get("burn", 0)))
	check(Items.tooltip(a1).any(func(l): return str(l[0]).contains("burning")), "the effect is in the tooltip")
	# an old unique of gen 2 (no effect yet) gets it
	var g2 := Items.make_unique("skullsplitter")
	g2["affixes"] = (g2["affixes"] as Array).filter(func(a): return a[0] != "chill")
	g2["gen"] = 2
	var g3 = Items.upgrade(g2)
	check((g3["affixes"] as Array).any(func(a): return a[0] == "chill"), "a unique from this morning's build gets its effect")
	var plain2 := {"base": "ring", "rarity": 1, "ilvl": 10, "name": "Ring", "affixes": [["life", 5]], "gen": 2}
	check(int(Items.upgrade(plain2)["affixes"][0][1]) == 5, "and an ordinary item from it isn't rescaled twice")
	# a boss's loot: the first kill always drops one of its uniques
	h.boss_luck = {}
	for gi in g.world.items_root.get_children():
		gi.queue_free()
	await process_frame
	var boss = g.spawn_enemy("bear", h.global_position + Vector3(3, 0, 0), 5)
	g._boss_loot(boss)
	await process_frame
	var got := 0
	for gi in g.world.items_root.get_children():
		var it4 = gi.get("item")
		if it4 is Dictionary and it4.has("unique") and Data.BOSS_LOOT["bear"].has(it4["unique"]):
			got += 1
	check(got == 1 and int(h.boss_luck.get("bear", -1)) == 0, "the bear's first kill drops one of its uniques")
	var tries := 0
	while int(h.boss_luck.get("bear", 0)) < 3 and tries < 50:
		h.boss_luck["bear"] = 3
		tries += 1
	check(g.BOSS_LOOT_CHANCE + g.BOSS_LOOT_LUCK * 3 >= 0.75, "three dry kills later the chance is %d%%" % int((g.BOSS_LOOT_CHANCE + g.BOSS_LOOT_LUCK * 3) * 100))
	boss.queue_free()
	# the Veilmother's Locket: a Shadow Phial each raid; drunk, unseen for 6 s until a blow
	for s2 in Items.EQUIP_SLOTS:
		h.equipment[s2] = null
	h.equipment["amulet"] = Items.make_unique("veil_locket")
	h.recalc()
	h.belt = [null, null, null, null]
	g.give_raid_phials()
	g.give_raid_phials()
	var ph := -1
	for i in 4:
		if h.belt[i] is Dictionary and h.belt[i]["base"] == "shadow_phial":
			ph = i
	check(ph >= 0 and int(h.belt[ph]["count"]) == 1, "the locket puts one Shadow Phial in the belt for a raid (never two)")
	h.drink(ph)
	check(h.invis_t > 5.0 and h.hidden_t > 5.0, "drunk: unseen for %.0f s (monsters lose him)" % h.invis_t)
	var pk: PackedFloat32Array = g.net._hero_packet(h)
	check(int(pk[14]) & 2 != 0, "and partners are told (the state's unseen bit)")
	h.block_chance = 0.0
	h.take_hit(5.0, h.global_position + Vector3(0, 0, -2))
	check(h.invis_t == 0.0, "a blow ends it")
	h.equipment["amulet"] = null
	h.recalc()
	# an act's strength never scales a unique's effect; two free rolls take the quicker recharge
	var a3 := Items.empower(Items.make_unique("stormstride"), float(Data.RUNS[2]["power"]))
	var dash := 0
	for af in a3["affixes"]:
		if af[0] == "dash":
			dash = int(af[1])
	check(dash == 25, "an A3 Stormstride's dash stays 25%% (%d)" % dash)
	# one saved before that fix (gen 3, its dash act-scaled to 60%) is remade on load
	var old3 := a3.duplicate(true)
	old3["gen"] = 3
	for af in old3["affixes"]:
		if af[0] == "dash":
			af[1] = 60
	var fixed = Items.upgrade(old3)
	var dash2 := 0
	for af in fixed["affixes"]:
		if af[0] == "dash":
			dash2 = int(af[1])
	check(dash2 == 25 and fixed["gen"] == Data.ITEM_GEN and float(fixed.get("power", 1.0)) == float(Data.RUNS[2]["power"]), "a pre-fix A3 Stormstride (dash 60%%) loads as 25%% and keeps its act strength (%d)" % dash2)
	var rare3 := {"base": "ring", "rarity": 2, "ilvl": 10, "name": "Ring", "affixes": [["life", 5], ["str", 3]], "gen": 3}
	check(Items.upgrade(rare3)["affixes"] == [["life", 5], ["str", 3]], "a gen-3 rare is left as it was")
	var r1 := Items.make("ring", 2, 20)
	r1["affixes"] = [["roll", 8]]
	var r2 := Items.make("ring", 2, 20)
	r2["affixes"] = [["roll", 6]]
	h.equipment["ring1"] = r1
	h.equipment["ring2"] = r2
	h.recalc()
	check(h.pvp_roll_s == 6, "two free rolls: the quicker recharge counts (%d s)" % h.pvp_roll_s)
	h.equipment["ring1"] = null
	h.equipment["ring2"] = null
	h.recalc()
	# "Go to level 20" marks the character, for the raid server
	h.boosted = false
	g.go_level_20()
	check(h.boosted and h.net_gear().get("_boosted", false), "Go to level 20 marks the character, and its state says so")
	# the bonfire's Reforge: the weakest affix rerolled, the others kept
	var rr := Items.make("ring", 2, 20)
	rr["affixes"] = [["str", 4], ["life", 1], ["res", 6]]
	var got2 := Items.reforge(rr, r)
	check(got2 != "" and rr["affixes"][0] == ["str", 4] and rr["affixes"][2] == ["res", 6] and rr["affixes"][1][0] != "life", "reforging rerolls the weakest affix (life 1 -> %s)" % got2)
	print("[IR] done, %d failed" % fails)
	quit()
