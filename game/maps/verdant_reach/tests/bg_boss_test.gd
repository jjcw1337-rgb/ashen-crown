extends SceneTree
## The Battlegrounds bosses' fights (game/monsters/hrimgar/, mossbeard/), offline on the raid map: Hrimgar, near a hero, aggroes and uses
## his moves (slam, lances, roar, swing; the avalanche under half life), and they hurt and freeze; Mossbeard
## sprouts poison mushrooms that hurt in their clouds, snares, bolts, steps out of a mushroom when hurt; when he
## dies his mushrooms wither, his camp's chest is no longer sealed, and no story ending plays (no Act I Complete screen,
## no portal to town: the Extraction Portals are the way out).
var g
var fails := 0
func _initialize():
	g = (load("res://main.tscn") as PackedScene).instantiate()
	get_root().add_child(g)
	_run()
func check(ok: bool, what: String) -> void:
	print("[B] ", "ok   " if ok else "FAIL ", what)
	if not ok:
		fails += 1
func secs(t: float) -> void:
	var end := Time.get_ticks_msec() + int(t * 1000.0)
	while Time.get_ticks_msec() < end:
		await process_frame
func _boss(k: String):
	for e in g.world.enemies_root.get_children():
		if e.kind == k:
			return e
	return null
func _run() -> void:
	while g.world == null or g._busy:
		await process_frame
	await g.start_game(false, "knight")
	g.ui.close_all()
	g.hero.start_run()
	g.bg_mode = true
	await g.load_zone(0, "bg", "start")
	var h = g.hero
	h.set_level(20)
	var moves := {}
	var troll = _boss("ice_troll")
	check(troll != null and troll.brain != null, "Hrimgar has his brain")
	# stand by him, a lot of life so the fight runs on
	h.max_life = 99999.0
	h.life = 99999.0
	h.global_position = g.world.free_spot_near(troll.global_position + Vector3(4.0, 0, 0), 1.0)
	var life0: float = h.life
	var t0 := Time.get_ticks_msec()
	var froze := false
	while Time.get_ticks_msec() - t0 < 22000:
		await process_frame
		if troll.brain.move != "":
			moves[troll.brain.move] = true
		froze = froze or h.daze_t > 0.0 or h.chill_t > 0.0
		h.global_position = g.world.free_spot_near(troll.global_position + Vector3(3.0 + 3.0 * sin(Time.get_ticks_msec() / 3000.0), 0, 2.0), 1.0) if Time.get_ticks_msec() % 4000 < 30 else h.global_position
		if troll.life > troll.max_life * 0.45 and Time.get_ticks_msec() - t0 > 12000:
			troll.life = troll.max_life * 0.45          # (into his second half: the avalanche)
	check(troll.aggro, "he noticed the hero")
	check(moves.size() >= 3, "and used his moves: %s" % str(moves.keys()))
	check(moves.has("bb_avalanche"), "the avalanche under half life")
	check(h.life < life0, "they hurt (%d)" % int(life0 - h.life))
	check(froze, "and froze or chilled the hero")
	# the hermit
	var her = _boss("hermit")
	check(her != null and her.brain != null, "Mossbeard has his brain")
	troll.life = 1.0
	troll.take_damage(999.0, 0.0, troll.global_position, 0.0, false)
	h.life = 99999.0
	h.global_position = g.world.free_spot_near(her.global_position + Vector3(6.0, 0, 3.0), 1.0)
	moves.clear()
	t0 = Time.get_ticks_msec()
	var most := 0
	var shroom_hurt := false
	while Time.get_ticks_msec() - t0 < 24000:
		await process_frame
		if her.brain.move != "":
			moves[her.brain.move] = true
		var ss: Array = her.brain._shrooms()
		most = maxi(most, ss.size())
		if Time.get_ticks_msec() - t0 > 14000 and her.life > her.max_life * 0.5:
			her.life = her.max_life * 0.5
		if not ss.is_empty() and not shroom_hurt:
			var l0: float = h.life
			h.global_position = ss[0].global_position + Vector3(0.8, 0, 0)
			await secs(1.7)
			shroom_hurt = h.life < l0
			h.global_position = g.world.free_spot_near(her.global_position + Vector3(6.0, 0, 3.0), 1.0)
	check(moves.size() >= 3, "he used his moves: %s" % str(moves.keys()))
	check(most >= 3, "his poison mushrooms sprouted (%d at once)" % most)
	check(shroom_hurt, "and their clouds hurt whoever stands in them")
	var gold: Array = [Camps.by_id(g.world, "grotto")["chest_node"]]
	check(g.chest_sealed(gold[0]), "the Grotto's chest sealed while he lives")
	var home: Vector3 = her.global_position
	her.global_position = gold[0].global_position + Vector3(70.0, 0, 0)
	check(g.chest_sealed(gold[0]), "still sealed with him lured 70 m off (Codex's audit)")
	her.global_position = home
	her.take_damage(99999.0, 0.0, her.global_position, 0.0, false)
	await secs(3.5)
	check(not g.chest_sealed(gold[0]), "he fell: the chest's seal is broken")
	var pack: int = her.pack_id
	check(g.world.enemies_root.get_children().filter(func(e): return e.kind == "spore_shroom" and not e.dead and e.pack_id == pack).is_empty(), "and his mushrooms withered")
	check(g.world.enemies_root.get_children().any(func(e): return e.kind == "spore_shroom" and not e.dead and e.pack_id != pack), "another camp's mushrooms stay (they were never his)")
	await secs(1.0)
	check(not g.ui.victory_panel.visible, "no story ending (no Act I Complete / Begin A2 screen)")
	check(g.world.interactables.filter(func(t): return t.kind == "portal" and t.has_meta("boss")).is_empty(), "and no portal to town: the Extraction Portals are the way out")
	print("[B] done, %d failed" % fails)
	quit()
