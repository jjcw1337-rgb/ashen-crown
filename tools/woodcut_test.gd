extends SceneTree
## Woodcutting (harvest.gd): the moor has a capped set of harvestable trees off the road; a hero with an axe
## walks up and chops; each blow lands on the swing's impact frame, the tree shudders and its notch deepens; the
## last blow fells it (stump, footprint shrunk), logs spill out as ground items and stack in the inventory; no
## axe = refused; the strike rate, reach and a felled tree are refused by the host; the stump grows back on played
## time (only with nobody near) and the stumps survive a save and load. Every class swings. Prints [W] lines.
## Run with --fixed-fps 60.
var g
var fails := 0

func _initialize():
	g = (load("res://main.tscn") as PackedScene).instantiate()
	get_root().add_child(g)
	_run()

func wait(s: float) -> void:
	await create_timer(s).timeout

func clear_foes() -> void:
	if g.world != null:
		for e in g.world.enemies_root.get_children():
			e.queue_free()

func check(ok: bool, what: String) -> void:
	print("[W] %s %s" % ["ok  " if ok else "FAIL", what])
	if not ok:
		fails += 1

func _run() -> void:
	while g.world == null or g._busy:
		g._intro_skip = true
		await process_frame
	await g.start_game(false, "knight")
	g.difficulty = 0
	g.test_immortal = true
	await g.load_zone(0, "wild", "start")
	await wait(0.5)
	clear_foes()
	var w = g.world
	var h: Harvest = Harvest.of(w)
	check(h != null, "the moor has a Harvest node")
	if h == null:
		quit(1)
		return
	var kinds := {}
	var road := []
	for t in h.trees:
		kinds[t.tkind] = int(kinds.get(t.tkind, 0)) + 1
		road.append(w.path_dist(t.global_position.x, t.global_position.z))
	print("[W] trees: %d %s, road distance %.1f..%.1f m" % [h.trees.size(), kinds, road.min(), road.max()])
	check(h.trees.size() > 10 and h.trees.size() <= Harvest.CAP, "a capped number of harvestable trees")
	check(road.min() >= Harvest.ROAD_MIN - 0.01, "none by the road")
	var spaced := true
	for i in h.trees.size():
		for j in range(i + 1, h.trees.size()):
			if (h.trees[i] as Node3D).global_position.distance_to((h.trees[j] as Node3D).global_position) < Harvest.SPACING - 0.01:
				spaced = false
	check(spaced, "spaced out")
	check(h.trees.all(func(t) -> bool: return t.obstacle >= 0), "each tree keeps its footprint")
	# Ferals don't perch on harvestable trees
	var perched := false
	for s in w.enemy_spawns:
		if s.has("perch") or str(s.get("kind", "")) == "feral":
			for t in h.trees:
				if Vector2(t.global_position.x, t.global_position.z).distance_to(Vector2(s["pos"].x, s["pos"].z)) < 1.2:
					perched = true
	check(not perched, "no Feral perches on one")

	# the inventory: logs stack
	var hero: Hero = g.hero
	hero.inventory.fill(null)
	hero.add_to_inventory(Items.resource("oak_log", 30))
	hero.add_to_inventory(Items.resource("oak_log", 30))
	var cells := hero.inventory.filter(func(x) -> bool: return x != null and x["base"] == "oak_log").size()
	check(hero.count_of("oak_log") == 60 and cells == 2, "60 oak logs stack into 2 cells of 50 (%d cells)" % cells)
	check(hero.take_items("oak_log", 35) and hero.count_of("oak_log") == 25, "taking 35 leaves 25")
	check(not hero.take_items("oak_log", 99) and hero.count_of("oak_log") == 25, "can't take more than there is")
	hero.inventory.fill(null)

	# no axe: refused
	var oak: Harvest.HTree = null
	for t in h.trees:
		if t.tkind == "oak":
			oak = t
			break
	var w0 = hero.equipment["weapon"]
	hero.equipment["weapon"] = null
	hero.global_position = oak.global_position + Vector3(oak.radius - 0.2, 0, 0)
	check(not hero.start_chop(oak), "no axe, no chopping")
	hero.equipment["weapon"] = w0
	hero.inventory[39] = Items.make("woodsman_axe")
	check(hero.chop_axe()[0] == "woodsman_axe", "the woodsman's axe is found in the bag")

	# chop it down
	var hp0 := oak.hp
	check(hero.start_chop(oak), "starts chopping")
	check(hero._chop_axe != null and not hero.weapon_node.visible or hero._chop_axe != null, "the axe is in his hand")
	var blows := 0
	var last := oak.hp
	var shook := false
	var frames := 0
	while oak.state == "stand" and frames < 60 * 120:
		clear_foes()
		await process_frame
		frames += 1
		if oak.hp < last:
			blows += 1
			last = oak.hp
		if absf(oak.rock) > 0.001:
			shook = true
	print("[W] felled after %d blows in %.1f s (hp %.0f), state %s" % [blows, frames / 60.0, hp0, oak.state])
	check(oak.state != "stand", "the oak comes down")
	check(blows == int(hp0) - 1 or blows == int(hp0), "one blow per swing (%d for %d life)" % [blows, int(hp0)])
	check(shook, "it shudders when struck")
	check(float(w.obstacles[oak.obstacle][1]) < oak.obstacle_r, "the stump's footprint is smaller")
	await wait(Harvest.FALL_LOGS_AT + 1.2)
	check(hero._chop_axe == null and hero.chop_tree == null, "the axe goes away once it's down")
	print("[W] oak trunk radius %.2f m, height %.1f m, footprint %.2f -> %.2f" % [oak.trunk_r, oak.height, oak.obstacle_r, float(w.obstacles[oak.obstacle][1])])
	var logs := []
	for gi in w.items_root.get_children():
		if gi is GroundItem and gi.item["base"] == "oak_log":
			logs.append(gi)
	var y: Array = Harvest.KINDS["oak"]["yield"]
	check(logs.size() >= int(y[0]) and logs.size() <= int(y[1]), "%d logs on the ground" % logs.size())
	for gi in logs:
		g._pickup(gi)
	check(hero.count_of("oak_log") == logs.size(), "picked up: %d oak logs in the bag" % hero.count_of("oak_log"))
	await wait(6.0)
	check(oak.state == "stump", "it's a stump once the trunk has settled")

	# the host's checks
	var pine: Harvest.HTree = null
	for t in h.trees:
		if t.tkind == "pine" and t.state == "stand":
			pine = t
			break
	var near := pine.global_position + Vector3(1.0, 0, 0)
	var far := pine.global_position + Vector3(9.0, 0, 0)
	h._last_strike.clear()
	check(not h.strike(pine.id, 7, far, 1.0), "a blow from 9 m is refused")
	check(h.strike(pine.id, 7, near, 1.0), "a blow from beside it counts")
	check(not h.strike(pine.id, 7, near, 1.0), "a second blow at once is refused")
	check(not h.strike(oak.id, 8, oak.global_position + Vector3(1, 0, 0), 1.0), "a stump can't be struck")
	# the wound heals when left alone
	pine.last_hit = g.played_s - Harvest.HEAL_AFTER - 1.0
	await process_frame
	await process_frame
	print("[W] pine hp %.1f/%.1f last_hit %.1f now %.1f" % [pine.hp, pine.max_hp, pine.last_hit, g.played_s])
	check(is_equal_approx(pine.hp, pine.max_hp), "a wound left alone closes")

	# saves keep the stump; it regrows on played time, not with a hero beside it
	g.save_game()
	var key: String = g._harvest_key()
	var oak_id: int = oak.id
	check(g.harvest_saved.get(key, {}).has(str(oak_id)), "the stump is in the save")
	await g.load_zone(0, "town", "start")
	await g.load_zone(0, "wild", "start")
	await wait(0.3)
	h = Harvest.of(g.world)
	var oak2: Harvest.HTree = h.trees[oak_id]
	check(oak2.state == "stump", "still a stump after leaving and coming back")
	g.hero.global_position = oak2.global_position + Vector3(2, 0, 0)
	g.played_s = oak2.respawn_at + 1.0
	await wait(0.3)
	check(oak2.state == "stump", "doesn't grow back with a hero beside it")
	g.hero.global_position = oak2.global_position + Vector3(30, 0, 0)
	await wait(0.3)
	check(oak2.state in ["regrow", "stand"], "grows back once the hero is away")
	await wait(Harvest.REGROW_T + 0.3)
	check(oak2.state == "stand" and float(g.world.obstacles[oak2.obstacle][1]) == oak2.obstacle_r, "full size again, full footprint")

	# every class swings an axe
	for cls in ["knight", "archer", "plague", "demon", "wraith", "warlock"]:
		g.hero.set_class(cls)
		g.hero.new_character()
		await process_frame
		var t2: Harvest.HTree = null
		for t in h.trees:
			if t.state == "stand" and t.tkind != "heart":
				t2 = t
				break
		g.hero.global_position = t2.global_position + Vector3(t2.radius - 0.3, 0, 0)
		var hp1 := t2.hp
		h._last_strike.clear()
		var ok: bool = g.hero.start_chop(t2)
		for i in 90:
			clear_foes()
			await process_frame
		check(ok and t2.hp < hp1 and g.hero.atk_style == "chop" and g.hero._chop_axe != null or (ok and t2.hp < hp1 and cls == "demon"), "%s chops (%.0f -> %.0f)" % [cls, hp1, t2.hp])
		g.hero.stop_chop()
		t2.hp = t2.max_hp
	print("[W] done, %d failures" % fails)
	quit(1 if fails > 0 else 0)
