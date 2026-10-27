extends SceneTree
## King Grubb the Gilded: his guards, the intro cackle, a Gilded Bomb, a burst sack (piles, grabbers
## from the tunnels), a hero taking a pile (gold, and it hurts him), a grabber hauling a pile back to him
## (heal), killing a hauling grabber (it drops the gold), the end of the scramble, the last sack
## enraging him, and cleanup on his death.
var g
func _initialize():
	g = (load("res://main.tscn") as PackedScene).instantiate()
	get_root().add_child(g)
	_run()
func wait(s: float) -> void:
	await create_timer(s).timeout
func alive(kind: String) -> Array:
	return g.world.enemies_root.get_children().filter(func(e): return e is Enemy and e.kind == kind and not e.dead)
func _run() -> void:
	while g.world == null or g._busy:
		await process_frame
	await g.start_game(false, "knight")
	g.ui.close_all()
	await g.load_zone(0, "lair", "start")
	var h = g.hero
	h.level = 10
	h.recalc()
	g.test_immortal = true
	var boss = null
	for e in g.world.enemies_root.get_children():
		if e is Enemy and e.boss:
			boss = e
	await wait(0.3)
	for e in g.enemies_near(boss.global_position, 18.0):
		if not e.boss and e.kind != "grabber":
			e.queue_free()
	var hd: Hoard = boss.hoard
	# hitbox: the camera's ray through his feet, his gut and his crown all pick him
	var cam: Camera3D = g.cam
	var picks := []
	for y in [0.2, 1.6, boss.top() - 0.3]:
		var sp := cam.unproject_position(boss.global_position + Vector3(0, y, 0))
		picks.append(g.pick_enemy(cam.project_ray_origin(sp), cam.project_ray_normal(sp)) == boss)
	print("[H] clickable at feet, gut, crown: %s (stands %.1f m, body radius %.2f)" % [picks, boss.top(), boss.body_r()])
	print("[H] boss %s (%s) has a hoard: %s, guards %d, tunnels %d" % [boss.kind, boss.display_name, hd != null, alive("grabber").size(), g.world.hoard_holes.size()])
	h.global_position = g.world.free_spot_near(boss.global_position + Vector3(0, 0, 4.0), 1.0)
	await wait(0.5)
	print("[H] aggro %s state %s cackling %s" % [boss.aggro, hd.state, boss.special == "cackle"])
	# a bomb: lands where the hero stood and hurts after the fuse
	await wait(2.0)
	boss.atk_t = -1.0
	hd.bomb_t = 0.0
	g.test_immortal = false
	h.life = h.max_life
	await wait(0.2)
	var bombing: bool = boss.special == "bomb"
	await wait(boss.atk_dur + Hoard.BOMB_FLY + Hoard.BOMB_FUSE + 0.3)
	print("[H] bomb thrown %s, hero hurt by it %s" % [bombing, h.life < h.max_life])
	g.test_immortal = true
	# first sack bursts at 75%
	boss.life = boss.max_life * 0.74
	for i in 40:
		await wait(0.1)
		if hd.state == "spill":
			break
	await wait(0.3)
	var heal_base: float = boss.life
	await wait(1.0)
	heal_base = boss.life
	var pn: Node3D = hd.piles[hd.piles.keys()[0]]["node"]
	print("[H] pile shown: scale %.2f, in tree %s" % [pn.scale.x, pn.is_inside_tree()])
	print("[H] spill: state %s, sacks %d, piles %d, grabbers %d, rig sacks %d" % [hd.state, hd.sacks, hd.piles.size(), alive("grabber").size(), int(boss.rig.get_meta("sacks")) if boss.rig.has_meta("sacks") else -1])
	# the hero takes a pile: gold, the pile gone, no heal from it
	var gold0: int = h.gold
	var robbed0: int = hd.robbed
	var id0: int = hd.piles.keys()[0]
	h.global_position = hd.piles[id0]["pos"]
	await wait(1.6)
	print("[H] hero took a pile: pile gone %s, gold +%d, it hurt him %s" % [not hd.piles.has(id0), h.gold - gold0, hd.robbed > robbed0])
	heal_base = boss.life
	h.global_position = g.world.free_spot_near(boss.home + Vector3(0, 0, 12.0), 1.0)
	# grabbers scoop and haul gold back; he heals
	var hauled := false
	var king_scooped := false
	var moved := 0.0
	var last: Vector3 = boss.global_position
	for i in 120:
		await wait(0.1)
		if not hd.carrying.is_empty():
			hauled = true
		if boss.special == "scoop":
			king_scooped = true
		moved += boss.global_position.distance_to(last)
		last = boss.global_position
		if boss.life > heal_base + 1.0:
			break
	print("[H] a grabber hauled gold %s, the king healed %s (%.0f%% -> %.0f%%)" % [hauled, boss.life > heal_base + 1.0, heal_base / boss.max_life * 100.0, boss.life / boss.max_life * 100.0])
	# kill a hauling grabber: it drops the gold
	var carrier: Enemy = null
	for i in 80:
		await wait(0.1)
		for e in hd.carrying.keys():
			if is_instance_valid(e) and not e.dead:
				carrier = e
		if carrier != null:
			break
	if carrier != null:
		var items0: int = g.world.items_root.get_child_count()
		carrier.take_damage(99999.0, 0.0, h.global_position, 0.0, false)
		await wait(0.2)
		print("[H] killed a hauling grabber: gold dropped %s, no longer hauling %s" % [g.world.items_root.get_child_count() > items0, not hd.carrying.has(carrier)])
	else:
		print("[H] killed a hauling grabber: none hauling (piles left %d)" % hd.piles.size())
	# the scramble ends once the gold is gone
	for i in 300:
		await wait(0.1)
		if boss.special == "scoop":
			king_scooped = true
		moved += boss.global_position.distance_to(last)
		last = boss.global_position
		if hd.state == "fight":
			break
	print("[H] scramble over: state %s piles %d; the king waddled %.1f m to the gold and scooped some himself: %s" % [hd.state, hd.piles.size(), moved, king_scooped])
	# skip to the last sack: he goes broke and enraged when it's gone
	hd.sacks = 1
	boss.life = boss.max_life * 0.2
	for i in 40:
		await wait(0.1)
		if hd.state == "spill":
			break
	for id in hd.piles.keys():
		hd._take(id, false)
	hd.carrying.clear()
	await wait(0.4)
	print("[H] last sack: sacks %d, enraged %s, state %s" % [hd.sacks, boss.enraged, hd.state])
	# death: grabbers gone, piles gone, gold shower, boss flag
	var items1: int = g.world.items_root.get_child_count()
	boss.take_damage(boss.life * 10.0 + 99999.0, 0.0, h.global_position, 0.0, false)
	await wait(0.5)
	print("[H] boss dead %s, grabbers cleared %s, piles cleared %s, gold shower %s, boss killed flag %s" % [boss.dead, alive("grabber").is_empty(), hd.piles.is_empty(), g.world.items_root.get_child_count() >= items1 + 8, g.boss_killed])
	quit()
