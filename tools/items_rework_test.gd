extends SceneTree
## The items rework (docs/queue_items_rework.md): new rolls are small, an old item is rebuilt once (uniques from
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
	print("[IR] done, %d failed" % fails)
	quit()
