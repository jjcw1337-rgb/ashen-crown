extends SceneTree
## Automated playtest: drives the real game through its main systems and reports errors.

var g
func _initialize():
	var scn: PackedScene = load("res://main.tscn")
	g = scn.instantiate()
	get_root().add_child(g)
	_run()

func wait(n: int) -> void:
	for i in n:
		await process_frame

func _run() -> void:
	Engine.max_fps = 60
	await wait(30)
	while g._busy:
		await wait(5)
	print("[1] title ok, town loaded, interactables=", g.world.interactables.size())
	g.start_game(false)
	await wait(10)
	while g._busy:
		await wait(5)
	g.ui.close_all()
	var h = g.hero
	print("[2] new game: hp=", h.life, " gold=", h.gold, " weapon=", h.equipment["weapon"]["name"])
	# shops
	for it in g.world.interactables:
		if it.kind == "vendor" and it.data.get("role") == "smith":
			g._interact(it)
	await wait(2)
	g.ui.open_shop("smith", g.shops["smith"][0], g.shops["smith"][1])
	h.gold = 5000
	g.ui._buy(0)
	g.ui._buy(0)
	print("[3] bought, gold=", h.gold, " inv0=", h.inventory[0]["name"] if h.inventory[0] else "none")
	h.equip_from_inventory(0)
	print("[4] equipped weapon=", h.equipment["weapon"]["name"], " dmg=", h.dmg_min, "-", h.dmg_max)
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_RIGHT
	ev.pressed = true
	g.ui._inv_click(1, ev)
	print("[5] sold, gold=", h.gold)
	g.ui.open_shop("gamble", "Gamble", g.shops["gamble"][1])
	g.ui._buy(0)
	g.ui.open_stash()
	g.ui.refresh()
	g.ui.toggle(g.ui.char_panel)
	h.stat_points = 3
	g.ui._add_stat("str")
	print("[6] stash/char ok, str=", h.total_str())
	g.ui.close_all()
	# into the moor
	await g.load_zone(0, "wild", "from_town")
	await wait(5)
	print("[7] wild loaded, enemies=", g.world.enemies_root.get_child_count())
	h.level = 12
	h.stat_points = 0
	h.str_ = 80
	h.vit = 120
	h.recalc()
	h.life = h.max_life
	h.mana = 500
	h.max_mana = 500
	var kills := 0
	var t0 := Time.get_ticks_msec()
	for round in 6:
		var es: Array = g.enemies_near(h.global_position, 200.0)
		if es.is_empty():
			break
		es.sort_custom(func(a, b): return a.global_position.distance_to(h.global_position) < b.global_position.distance_to(h.global_position))
		var e = es[0]
		h.global_position = g.world.free_spot_near(e.global_position + Vector3(0, 0, 2), 0.5)
		for f in 400:
			if not is_instance_valid(e) or e.dead:
				kills += 1
				break
			if h.can_act():
				h.cmd_target(e)
			if f % 60 == 0:
				h.cds["nova"] = 0
				h.mana = 500
				h.use_skill("nova", e.global_position)
			h.life = h.max_life
			await process_frame
	print("[8] kills=", kills, " xp=", h.xp, " lvl=", h.level, " items on ground=", g.world.items_root.get_child_count())
	await wait(60)
	var picked := 0
	for gi in g.world.items_root.get_children():
		if gi is GroundItem:
			g._pickup(gi)
			picked += 1
	print("[9] picked up ", picked, " gold=", h.gold)
	# regression: hovered/targeted objects deleted out from under the player
	g.drop_item(Items.gold(50), h.global_position + Vector3(2, 0, 0))
	g.drop_item(Items.potion("hp_potion"), h.global_position + Vector3(-2, 0, 0))
	await wait(60)
	var items: Array = g.world.items_root.get_children()
	g.hovered = items[0]
	h.target = items[1]
	items[0].queue_free()
	items[1].queue_free()
	var victim = g.enemies_near(h.global_position, 300.0)[0]
	await wait(3)
	g.hovered = victim
	h.target = victim
	victim.queue_free()
	await wait(5)
	var p0: Vector3 = h.global_position
	g.ground_pt = p0 + Vector3(4, 0, 0)
	h.cmd_move(p0 + Vector3(4, 0, 0))
	await wait(60)
	var moved: float = h.global_position.distance_to(p0)
	var foe = g.enemies_near(h.global_position, 300.0)[0]
	h.global_position = g.world.free_spot_near(foe.global_position + Vector3(0, 0, 2), 0.5)
	h.cmd_target(foe)
	var swung := false
	for f in 90:
		if h.atk_t >= 0.0:
			swung = true
		await process_frame
	print("[R] after stale refs: moved=", snappedf(moved, 0.1), "m attacked=", swung, " time_scale=", Engine.time_scale)
	g.hitstop(0.05)
	await wait(30)
	g.toggle_pause()
	var esc := InputEventKey.new()
	esc.keycode = KEY_ESCAPE
	esc.pressed = true
	g.ui._unhandled_key_input(esc)
	print("[P] hitstop reset time_scale=", Engine.time_scale, " paused after Esc=", g.paused)
	# movement while attacking, sprint and stamina
	var open_spot: Vector3 = g.world.free_spot_near(g.world.spawns["start"], 1.0)
	g.playing = false
	h.global_position = open_spot
	h.target = null
	await wait(60)
	var a0: Vector3 = h.global_position
	h.free_attack(a0 + Vector3(0, 0, -3))
	var was_attacking: bool = h.atk_t >= 0.0
	h.cmd_wasd(Vector3(0, 0, -1))
	await wait(15)
	var moved_during: float = h.global_position.distance_to(a0)
	var mid_attack: bool = h.atk_t >= 0.0
	h.cmd_wasd(Vector3.ZERO)
	await wait(40)
	h.global_position = open_spot
	var w0: Vector3 = h.global_position
	h.cmd_wasd(Vector3(0, 0, -1))
	await wait(30)
	var walk_d: float = h.global_position.distance_to(w0)
	h.global_position = open_spot
	var s0: Vector3 = h.global_position
	h.sprint = true
	h.stamina = h.max_stamina
	await wait(30)
	var run_d: float = h.global_position.distance_to(s0)
	print("[M] swing+move: attacking=", was_attacking and mid_attack, " moved=", snappedf(moved_during, 0.01), "m  walk 0.5s=", snappedf(walk_d, 0.01), "m  sprint 0.5s=", snappedf(run_d, 0.01), "m")
	var t_run := 0
	while not h.exhausted and t_run < 1200:
		h.global_position = open_spot
		await process_frame
		t_run += 1
	print("[S] stamina emptied after ", snappedf(t_run / 60.0, 0.1), "s exhausted=", h.exhausted, " running now=", h.running)
	h.sprint = false
	h.cmd_wasd(Vector3.ZERO)
	await wait(240)
	print("[S] recovered: exhausted=", h.exhausted, " stamina=", int(h.stamina), "/", int(h.max_stamina))
	var foe2 = null
	for e in g.enemies_near(h.global_position, 400.0):
		if e.kind != "skel_archer":
			foe2 = e
			break
	var hp_before: float = foe2.life
	for k in 3:
		if not is_instance_valid(foe2) or foe2.dead:
			break
		h.global_position = g.world.free_spot_near(foe2.global_position + Vector3(0, 0, 1.4), 0.2)
		h.free_attack(foe2.global_position)
		await wait(45)
	print("[F] free swing hit: ", is_instance_valid(foe2) and (foe2.life < hp_before or foe2.dead))
	g.playing = true
	g.cast_town_portal()
	print("[10] portal link=", g.tp_link.get("zone"))
	h.use_skill("charge", h.global_position + Vector3(5, 0, 0))
	h.cds["cry"] = 0
	await wait(40)
	h.use_skill("cry", h.global_position)
	await wait(40)
	# boss
	await g.load_zone(0, "lair", "start")
	await wait(5)
	var boss = null
	for e in g.world.enemies_root.get_children():
		if e.boss:
			boss = e
	print("[11] lair loaded, enemies=", g.world.enemies_root.get_child_count(), " boss=", boss.display_name if boss else "none")
	h.global_position = g.world.free_spot_near(boss.global_position + Vector3(0, 0, 2.6), 0.3)
	# one click = one swing
	g.playing = false
	g.lmb_held = false
	h.cmd_target(boss)
	var swings := 0
	var was := false
	for f in 180:
		var now: bool = h.atk_t >= 0.0
		if now and not was:
			swings += 1
		was = now
		h.life = h.max_life
		await process_frame
	# holding the button keeps attacking
	g.lmb_held = true
	h.cmd_target(boss)
	var held := 0
	var styles := []
	var last_style := ""
	for f in 180:
		var cur: String = h.atk_style if h.atk_t >= 0.0 else ""
		if cur != "" and cur != last_style:
			held += 1
			styles.append(cur)
		last_style = cur
		h.life = h.max_life
		await process_frame
	print("[B] held left-click combo: ", styles)
	# holy nova fires mid-combo and hurts the boss
	h.level = 12
	h.mana = h.max_mana
	h.cds["nova"] = 0.0
	while h.atk_t < 0.05:
		await process_frame
	var boss_hp: float = boss.life
	var mana0: float = h.mana
	var cast_ok: bool = h.use_skill("nova", boss.global_position)
	await wait(40)
	g.lmb_held = false
	h.target = null
	print("[B] single click swings=", swings, "  held swings=", held, "  nova cast mid-swing=", cast_ok, " mana used=", int(mana0 - h.mana), " boss damaged=", boss.life < boss_hp)
	g.playing = true
	h.str_ = 400
	h.recalc()
	var frames := 0
	while is_instance_valid(boss) and not boss.dead and frames < 6000:
		if h.can_act():
			# King Grubb: kill the grabbers hauling his gold back to him first
			var mark = boss.hoard.priority_target() if boss.hoard != null else boss
			if h.target != mark:
				h.cmd_target(mark)
		h.life = h.max_life
		h.blocking = (frames / 90) % 3 == 0
		frames += 1
		await process_frame
	print("[12] boss dead=", boss.dead if is_instance_valid(boss) else true, " frames=", frames, " boss_killed=", g.boss_killed, " minions=", g.world.enemies_root.get_child_count())
	await wait(260)
	print("[13] victory shown=", g.ui.victory_panel.visible)
	g.save_game()
	print("[14] saved; load=", g.load_game())
	h.life = 1
	h.blocking = false
	h.take_hit(9999, h.global_position + h.rig.global_transform.basis.z * 2.0)
	await wait(150)
	print("[15] death panel=", g.ui.death_panel.visible)
	print("PLAYTEST DONE in ", (Time.get_ticks_msec() - t0) / 1000.0, "s")
	quit()
