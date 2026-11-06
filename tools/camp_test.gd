extends SceneTree
## Battlegrounds camps (Camps, Blaine's overhaul 2026-11-06), on one game hosting the raid's zone with a run
## character: every camp has a tier, its monsters (its own pack) and a sealed chest; killing another camp's monsters
## doesn't open it; its last monster unseals it and gives the camp's experience; the chest drops gear and potions once
## (no gold, ring or amulet) and opens the upgrade (three choices); closing and reopening keeps the offer; choosing
## takes it once; a tier III camp's offer has better odds. Prints [CAMP] lines.
var g
var fails := 0
var CA
var RB
const MIN_CAMPS := 5

func _initialize():
	g = (load("res://main.tscn") as PackedScene).instantiate()
	get_root().add_child(g)
	CA = load("res://scripts/camps.gd")
	RB = load("res://scripts/run_build.gd")
	_run()

func check(ok: bool, what: String) -> void:
	if not ok:
		fails += 1
	print("[CAMP] %s %s" % ["ok  " if ok else "FAIL", what])

func secs(t: float) -> void:
	await create_timer(t).timeout

func _run() -> void:
	while g.world == null or g._busy:
		g._intro_skip = true
		await process_frame
	await g.start_game(false, "knight")
	g.ui.hide_title()
	g.hero.set_class("archer")
	g.hero.start_run()
	g.bg_mode = true
	await g.load_zone(0, "bg", "start")
	await secs(1.0)
	var camps: Array = CA.all(g.world)
	check(camps.size() >= int(MIN_CAMPS), "the raid's map has %d camps" % camps.size())
	var tiers := {}
	for c in camps:
		tiers[int(c["tier"])] = true
		var members: Array = g.world.enemies_root.get_children().filter(func(e): return e is Enemy and e.pack_id == int(c["pack"]))
		if members.is_empty():
			check(false, "%s has no monsters" % c["name"])
	check(tiers.size() >= 2, "camps of %d tiers" % tiers.size())
	var low: Array = camps.duplicate()
	low.sort_custom(func(x, y): return int(x["tier"]) < int(y["tier"]))
	var a: Dictionary = low[0]
	var b: Dictionary = low[1]
	var ch_a = a["chest_node"]
	check(g.chest_sealed(ch_a), "%s's chest is sealed while its monsters live" % a["name"])
	# another camp's deaths don't open it
	_kill_camp(b)
	await secs(0.5)
	check(b["cleared"] and not a["cleared"] and g.chest_sealed(ch_a), "clearing %s leaves %s sealed" % [b["name"], a["name"]])
	# the camp falls: unsealed, experience
	g.hero.global_position = g.world.free_spot_near(a["pos"], 2.0)
	var lvl0: int = g.hero.level
	var xp0: int = g.hero.xp
	var camps0: int = g.hero.run.camps
	_kill_camp(a)
	await secs(0.5)
	check(a["cleared"] and not g.chest_sealed(ch_a), "the last of %s unseals its chest" % a["name"])
	check(g.hero.run.camps == camps0 + 1 and (g.hero.level > lvl0 or g.hero.xp > xp0), "the camp's experience (level %d -> %d)" % [lvl0, g.hero.level])
	# the chest: loot once, then the upgrade window
	var before: int = g.world.items_root.get_child_count()
	g.hero.global_position = g.world.free_spot_near(ch_a.global_position, 1.2)
	g._interact(ch_a)
	await secs(0.6)
	var drops: Array = g.world.items_root.get_children().slice(before)
	check(drops.size() >= 2, "the chest dropped %d things" % drops.size())
	var bad := drops.filter(func(x): return x is GroundItem and str(load("res://scripts/data.gd").BASES[x.item["base"]]["slot"]) in ["gold", "ring", "amulet", "belt"])
	check(bad.is_empty(), "no gold, ring, amulet or belt in it")
	check(g.ui.run_ui.visible and g.ui.run_ui.mode == "offer", "and its upgrade window opened")
	var key: String = CA.offer_key(g, a)
	var first: Array = g.hero.run.offers[key]["choices"].duplicate(true)
	check(first.size() == 3, "three choices")
	g.ui.run_ui.close()
	var n2: int = g.world.items_root.get_child_count()
	g._interact(ch_a)
	await secs(0.4)
	check(g.world.items_root.get_child_count() == n2, "a second open drops nothing more")
	check(g.ui.run_ui.mode == "offer" and g.hero.run.offers[key]["choices"] == first, "the reopened offer is the same three")
	g.ui.run_ui._take(0)
	check(not g.hero.run.offer_open(key), "a choice taken: %s" % first[0]["id"])
	g._interact(ch_a)
	await secs(0.2)
	check(not g.ui.run_ui.visible, "and the chest has no second upgrade")
	# better odds deeper in: a tier III camp's offers lean rarer
	var r1 := 0
	var r3 := 0
	for k in 60:
		for c in g.hero.run.roll_offer("archer", 1, "p1_%d" % k, g.hero.binds):
			r1 += int(c["rarity"])
		for c in g.hero.run.roll_offer("archer", 3, "p3_%d" % k, g.hero.binds):
			r3 += int(c["rarity"])
	check(r3 > r1, "tier III offers are rarer than tier I (%d vs %d)" % [r3, r1])
	print("[CAMP] done, %d failure(s)" % fails)
	quit(1 if fails > 0 else 0)

func _kill_camp(c: Dictionary) -> void:
	for e in g.world.enemies_root.get_children():
		if e is Enemy and not e.dead and e.pack_id == int(c["pack"]):
			e.take_damage(999999.0, 0.0, e.global_position + Vector3(1, 0, 0), 0.0, false)
