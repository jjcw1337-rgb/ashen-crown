extends SceneTree
## The Warlock in the Battlegrounds (PvP; WarlockHex), three processes:
##   godot --headless --path . -s game/heroes/warlock/tests/warlock_pvp_test.gd -- --server --port 24691 --raid-fast server
##   godot --headless --path . -s game/heroes/warlock/tests/warlock_pvp_test.gd -- a 24691
##   godot --headless --path . -s game/heroes/warlock/tests/warlock_pvp_test.gd -- b 24691
## a is the Warlock, b a knight standing still. Her skills run on the match server (ServerRules): a's curses tick on b
## there (each tick a PvP hit), Terrify makes b flee (PvpStatus "fear" through Battlegrounds.pvp_status, with
## diminishing returns), Festering Hex staggers him on its burst, and Leech Bolt heals a off him (the server gives a's
## game the life: Skill.give). a's own game keeps no curse of its own.
## Prints [SERVER]/[A]/[B] lines.
var role := "a"
var host := "127.0.0.1"
var port := 24681
var g
var fails := 0

func _initialize():
	var a := OS.get_cmdline_user_args()
	role = "server" if a.has("server") else ("b" if a.has("b") else "a")
	if role != "server":
		Battlegrounds.id_path = "user://warlock_pvp_%s_id.txt" % role
		DirAccess.remove_absolute(Battlegrounds.id_path)
		for x in a:
			if str(x).is_valid_int():
				port = int(x)
	g = (load("res://main.tscn") as PackedScene).instantiate()
	get_root().add_child(g)
	_run()

func check(ok: bool, what: String) -> void:
	if not ok:
		fails += 1
	print("[%s] %s%s" % [role.to_upper(), "ok   " if ok else "FAIL ", what])

func wait(n: int) -> void:
	for i in n:
		await process_frame

func secs(t: float) -> void:
	var end := Time.get_ticks_msec() + int(t * 1000.0)
	while Time.get_ticks_msec() < end:
		await process_frame

func until(f: Callable, t: float) -> bool:
	var end := Time.get_ticks_msec() + int(t * 1000.0)
	while Time.get_ticks_msec() < end:
		if f.call():
			return true
		await process_frame
	return false

func _run() -> void:
	Engine.max_fps = 60
	await wait(30)
	if role == "server":
		await _server()
	else:
		await _player()
	print("[%s] done, %d failed" % [role.to_upper(), fails])
	quit()

func _server() -> void:
	await until(func(): return g.bg != null and g.net.active and not g._busy, 40.0)
	check(await until(func(): return g.net.players.size() == 2, 60.0), "both players are in the crypt")
	check(await until(func(): return not g.bg.cc_dr.is_empty(), 90.0), "a status passed through the server, counted for diminishing returns")
	check(ServerRules.made_count >= 3, "her spells were made here, by the server's copy of her (%d made, %d refused)" % [ServerRules.made_count, ServerRules.refused_count])
	await until(func(): return g.net.players.is_empty(), 120.0)

func _player() -> void:
	while g._busy:
		await wait(5)
	await secs(2.0 if role == "a" else 4.0)
	g.char_dir = "user://warlock_pvp_%s_chars/" % role
	DirAccess.make_dir_recursive_absolute(g.char_dir)
	for fn in DirAccess.get_files_at(g.char_dir):
		DirAccess.remove_absolute(g.char_dir + fn)
	g.hero.set_class("warlock" if role == "a" else "knight")
	g.hero.new_character()
	g.hero.set_level(24)
	g.char_id = g.new_char_id()
	g.char_name = "Spirit" if role == "a" else "Victim"
	g.net.my_name = g.char_name
	g.save_game()
	await g.start_battlegrounds("%s:%d" % [host, port], g.char_id)
	check(await until(func(): return g.cur_zone == Battlegrounds.ZONE and not g._busy and not g.net.loading, 30.0), "entered the crypt")
	# a round starts in the antechambers, PvP off behind the gates: ring a bell and wait for the raid
	await until(func(): return not g.bg_raid.is_empty(), 10.0)
	if str(g.bg_raid.get("state", "")).begins_with("lobby"):
		var bells: Array = g.world.interactables.filter(func(t): return t.kind == "bell")
		if not bells.is_empty():
			g._interact(bells[0])
	check(await until(func(): return str(g.bg_raid.get("state", "")) == "raid", 30.0), "the bell rang and the raid is on")
	check(await until(func(): return g.net.puppets().size() == 1 and g.net.puppets()[0].net_has, 40.0), "the other player is here")
	g.test_immortal = role == "a"
	if role == "a":
		await _warlock()
	else:
		await _victim()
	g.net.shutdown()
	await secs(1.0)

func _warlock() -> void:
	var foe = g.net.puppets()[0]
	var h: Hero = g.hero
	g.test_allskills = true
	check(await until(func(): return _proxy() != null, 10.0), "the other player is a target (a stand-in)")
	h.global_position = g.world.free_spot_near(foe.global_position + Vector3(6.0, 0, 0), 0.5)
	await secs(0.6)
	check(_use(h, "w_corruption", foe.global_position), "Corruption cast at him")
	await secs(0.8)
	check(h.kit.get("hex") == null or h.kit["hex"].curses_on(_proxy()) == 0, "my game keeps no curse of its own: the server's copy of me cursed his stand-in")
	check(_use(h, "w_festering", foe.global_position), "Festering Hex on him too")
	await secs(1.0)
	check(_use(h, "w_terrify", foe.global_position), "Terrify at him")
	await secs(1.5)
	h.life = h.max_life * 0.5
	var l0 := h.life
	check(_use(h, "w_leechbolt", foe.global_position), "Leech Bolt at him")
	await secs(1.0)
	check(h.life > l0, "and it heals me off him (%+.0f)" % (h.life - l0))
	await secs(8.0)

func _victim() -> void:
	var h: Hero = g.hero
	h.set_level(30)
	h.life = h.max_life
	var l0 := h.life
	check(await until(func(): return h.life < l0 - 1.0, 40.0), "the curse's ticks reach me through the server (%.0f -> %.0f)" % [l0, h.life])
	var l1 := h.life
	await secs(2.5)
	check(h.life < l1, "and keep ticking (%.0f more)" % (l1 - h.life))
	check(await until(func(): return PvpStatus.landed.any(func(x): return x[0] == "fear"), 20.0), "Terrify makes me flee (a fear through the server)")
	check(await until(func(): return PvpStatus.landed.any(func(x): return x[0] == "stagger"), 20.0), "Festering Hex's burst staggers me")
	h.life = h.max_life
	await until(func(): return g.net.puppets().is_empty(), 30.0)

func _use(h: Hero, id: String, at: Vector3) -> bool:
	h.cds[id] = 0.0
	h.mana = h.max_mana
	h.cursor = at
	return h.use_skill(id, h.skill_aim(id, at))

func _proxy():
	for e in g.world.enemies_root.get_children():
		if e is Enemy and e.pvp_pid > 0:
			return e
	return null
