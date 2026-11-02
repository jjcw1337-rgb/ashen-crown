extends SceneTree
## The Battlegrounds' gear rules and item effects (Blaine's progression overhaul; Data.PVP_*, Hero.pvp_scaled):
## gear's flat stats count for a fifth in a raid and its percentages are capped (+5% run speed at most), the weapon's
## damage is the level's; the class uniques only fit their class, and in a raid their effects work: a ward that soaks
## blows and comes back out of combat, a free dodge roll that costs no stamina and recharges; outside a raid nothing
## changes. A boss's class unique is for a class near it.
var g
var DG     # dodge.gd, at run time (a static reference compiles its Sfx before the autoload)
var fails := 0
func _initialize():
	DG = load("res://scripts/dodge.gd")
	g = (load("res://main.tscn") as PackedScene).instantiate()
	get_root().add_child(g)
	_run()
func check(ok: bool, what: String) -> void:
	print("[I] ", "ok   " if ok else "FAIL ", what)
	if not ok:
		fails += 1
func wait(n: int) -> void:
	for i in n:
		await process_frame
func _run() -> void:
	while g.world == null or g._busy:
		await wait(5)
	await g.start_game(false, "doug")
	while g._busy:
		await wait(5)
	g.ui.close_all()
	var h = g.hero
	h.set_level(20)
	g.dev_tools = true
	g.go_level_20()
	var rng := RandomNumberGenerator.new()
	var boots := Items.make("greaves", 2, 20)
	boots["affixes"] = [["frw", 15], ["res", 15]]
	h.equipment["boots"] = boots
	h.recalc()
	var life_pve: float = h.max_life
	var arm_pve: int = h.armor
	check(h.frw >= 15, "outside a raid the boots' +15%% run speed counts (%d)" % h.frw)
	h.pvp_force = true
	h.recalc()
	check(h.frw == 5, "in a raid it's capped at +5%% (%d)" % h.frw)
	check(h.max_life < life_pve and h.armor < arm_pve, "and gear's life and armour count for less (%d -> %d life, %d -> %d armour)" % [int(life_pve), int(h.max_life), arm_pve, h.armor])
	var d: Array = Data.pvp_damage(20, [3, 7])
	var d2: Array = Data.pvp_damage(20, [30, 50])
	check(float(d2[1]) / float(d[1]) < 1.3 and d[0] > 3, "the weapon's damage is the level's: a starting weapon %s, the best %s" % [str(d), str(d2)])
	h.pvp_force = false
	# the class uniques
	var nose := Items.make_unique("lucky_nose")
	var plate := Items.make_unique("oathkeeper")
	check(Items.tooltip(nose).size() > 0, "The Lucky Nose has a tooltip")
	var slot0 = h.equipment.get("armor")
	h.inventory[0] = plate
	h.equip_from_inventory(0) if h.has_method("equip_from_inventory") else null
	check(h.equipment.get("armor") == slot0, "Doug can't wear the knight's Oathkeeper's Plate")
	h.inventory[0] = null
	h.equipment["amulet"] = nose
	h.recalc()
	check(h.pvp_roll_s == 0, "outside a raid the Nose's free roll is off")
	h.pvp_force = true
	h.recalc()
	check(h.pvp_roll_s == 6 and h.free_roll(), "in a raid: a free dodge roll every %d s" % h.pvp_roll_s)
	h.stamina = 0.0
	h.free_roll_t = 0.0
	check(DG.start(h, Vector3(1, 0, 0)), "he rolls with no stamina at all")
	check(h.free_roll_t > 5.0 and not h.free_roll(), "then it recharges (%.1f s)" % h.free_roll_t)
	await wait(40)
	h.stamina = 0.0
	check(not DG.can_roll(h), "and until it does, no stamina, no roll")
	# the ward (a knight in Oathkeeper's Plate)
	h.pvp_force = false
	await g.start_game(false, "knight")
	while g._busy:
		await wait(5)
	g.ui.close_all()
	h = g.hero
	h.set_level(20)
	h.equipment["armor"] = Items.make_unique("oathkeeper")
	h.pvp_force = true
	h.recalc()
	h.life = h.max_life
	h.combat_t = 999.0
	await wait(270)          # (it fills over 4 s out of combat)
	check(h.ward_max > 0.0 and h.ward >= h.ward_max * 0.95, "Oathkeeper's ward is up (%d of %d)" % [int(h.ward), int(h.ward_max)])
	var l0: float = h.life
	g.test_immortal = false
	h.take_hit(h.ward_max * 0.5, h.global_position + Vector3(0, 0, -2), "pvp", "fire")
	check(is_equal_approx(h.life, l0) and h.ward < h.ward_max, "a blow smaller than it is soaked (life %d -> %d, ward %d)" % [int(l0), int(h.life), int(h.ward)])
	h.combat_t = 999.0
	await wait(300)
	check(h.ward >= h.ward_max * 0.95, "and it comes back out of combat")
	h.pvp_force = false
	h.recalc()
	check(h.ward_max == 0.0, "no ward outside a raid")
	# a class unique for a class near
	for gi in g.world.items_root.get_children():
		gi.queue_free()
	await wait(2)
	g._drop_class_unique(h.global_position + Vector3(1, 0, 0))
	await wait(2)
	var got := ""
	for gi in g.world.items_root.get_children():
		var gitem = gi.get("item")
		if gitem is Dictionary and gitem.has("unique"):
			got = str(Data.UNIQUES[gitem["unique"]].get("cls", ""))
	check(got == "knight", "a boss's class unique is for the class near (%s)" % got)
	print("[I] done, %d failed" % fails)
	quit()
