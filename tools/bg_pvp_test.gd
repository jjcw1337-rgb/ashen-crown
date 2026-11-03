extends SceneTree
## Battlegrounds PvP, three processes:
##   godot --headless --path . -s tools/bg_pvp_test.gd -- --server --port 24671 --raid-fast server
##   godot --headless --path . -s tools/bg_pvp_test.gd -- a 24671 [addr <host>] [cloud <nakama url> <server key>]
##   godot --headless --path . -s tools/bg_pvp_test.gd -- b 24671 [addr <host>] [cloud <nakama url> <server key>]
## Two real characters enter the crypt. On a's screen b is an invisible stand-in target (Battlegrounds.sync_proxies);
## a walks up to b and swings at it: b's life drops through the server (Net.sv_pvp_hit, PVP_MULT) until b falls.
## b's gear drops, the server announces who killed whom, and a picks b's things up. b keeps its level but loses
## everything it carried. Fallen, b spectates a (the camera on a) until a leaves, then leaves the crypt.
## With "doug" after the port on both players' lines, a plays Doug: his first skill is the Cream Pie, and b checks it
## was Pied by it (the crowd control crossing to another player: DougSkills._cc -> Net.send_pvp_effect).

var g
var role := "a"
var port := 24671
var host := "127.0.0.1"
var fails := 0

func _initialize():
	var a := OS.get_cmdline_user_args()
	role = "server" if a.has("server") else ("b" if a.has("b") else "a")
	for i in a.size():
		if a[i].is_valid_int() and int(a[i]) > 1024:
			port = int(a[i])
	if role != "server":
		Battlegrounds.id_path = "user://bg_pvp_%s_id.txt" % role
		DirAccess.remove_absolute(Battlegrounds.id_path)
		var ai := a.find("addr")
		if ai >= 0 and ai + 1 < a.size():
			host = a[ai + 1]
		var ci := a.find("cloud")
		if ci >= 0 and ci + 2 < a.size():
			BuildEnv.forced = {"cloud": "1", "nakama_url": a[ci + 1], "nakama_key": a[ci + 2]}
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
	check(await until(func(): return g.bg.last_hit.size() > 0, 60.0), "a player struck another (through the server)")
	check(await until(func(): return g.bg.died_items.size() > 0, 60.0), "and killed them: their body dropped its gear")
	await until(func(): return g.net.players.is_empty(), 90.0)

func _player() -> void:
	while g._busy:
		await wait(5)
	await secs(2.0 if role == "a" else 4.0)
	g.char_dir = "user://bg_pvp_%s_chars/" % role
	DirAccess.make_dir_recursive_absolute(g.char_dir)
	for fn in DirAccess.get_files_at(g.char_dir):
		DirAccess.remove_absolute(g.char_dir + fn)
	var doug := OS.get_cmdline_user_args().has("doug")
	g.hero.set_class(("doug" if doug else "knight") if role == "a" else "wraith")
	g.hero.new_character()
	g.hero.set_level(8)
	g.char_id = g.new_char_id()
	g.char_name = "Attacker" if role == "a" else "Victim"
	g.net.my_name = g.char_name
	g.save_game()
	var path: String = g.char_dir + g.char_id + ".json"
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
	if role == "a":
		g.test_immortal = true
		var foe = g.net.puppets()[0]
		check(await until(func(): return _proxy() != null, 10.0), "they are a target for my blows (a stand-in)")
		# a skill first: its effects go to the other player through the server (Net.pl_fx, relayed)
		g.hero.mana = g.hero.max_mana
		var sk: String = str(g.hero.skill_list()[0]["id"])
		check(g.hero.use_skill(sk, foe.global_position), "cast %s at them" % sk)
		var life_seen: Array = []
		for i in 60:
			if not is_instance_valid(foe) or foe.dead:
				break
			g.hero.global_position = g.world.free_spot_near(foe.global_position + Vector3(1.2, 0, 0), 0.5)
			var p = _proxy()
			if p != null:
				g.hero._hit_enemy(p, 3.0)
			if is_instance_valid(foe):
				life_seen.append(foe.life)
			await secs(0.25)
		check(life_seen.size() > 1 and float(life_seen.back()) < float(life_seen.front()), "their life fell as I hit them (%d -> %d)" % [int(life_seen.front()), int(life_seen.back())])
		check(await until(func(): return not is_instance_valid(foe) or foe.dead, 15.0), "they fell")
		var at: Vector3 = foe.global_position if is_instance_valid(foe) else g.hero.global_position     # (their puppet goes when they leave)
		await secs(4.0)
		var n0 := 0
		for it in g.hero.inventory:
			if it != null:
				n0 += 1
		for gi in g.world.items_root.get_children():
			if is_instance_valid(gi) and gi is GroundItem and gi.global_position.distance_to(at) < 6.0:
				g.hero.global_position = g.world.free_spot_near(gi.global_position, 0.8)
				g._pickup(gi)
				await secs(0.3)
		await secs(1.5)
		var n1 := 0
		for it in g.hero.inventory:
			if it != null:
				n1 += 1
		check(n1 > n0, "I took their things (%d -> %d)" % [n0, n1])
		await secs(3.0)
	else:
		g.test_immortal = false
		# (against full life: a slow start can find the attacker already at work, even done)
		var l0: float = g.hero.max_life
		if doug:
			check(await until(func(): return g.hero.pied_t > 0.0, 60.0), "Doug's cream pie Pied me (through the server)")
		check(await until(func(): return g.hero.life < l0 or g.hero.dead, 60.0), "I'm being hit by the other player")
		check(await until(func(): return g.hero.dead, 60.0), "and I fell")
		# fallen, I watch the one still alive (Game.spectate_*), until they leave too
		check(await until(func(): return g.ui.spectate_panel.visible, 6.0) and not g.ui.death_panel.visible, "I'm spectating (not the plain death screen)")
		check(g.ui.spectate_name() == "Attacker", "watching the Attacker (%s)" % g.ui.spectate_name())
		await secs(1.5)
		var att = g.spectate_hero()
		check(att != null and g.cam_target.distance_to(att.global_position) < 3.0, "the camera follows them")
		check(await until(func(): return g.net.puppets().is_empty(), 40.0), "they left")
		await secs(0.5)
		check(g.spectating == 0 and str(g.ui._spec_name.text).begins_with("No one"), "no one left to watch: it says so")
		(g.ui.spectate_panel.find_child("leave", true, false) as Button).pressed.emit()
		check(await until(func(): return not g.bg_mode and not g._busy, 20.0), "the raid is over for me")
		var d = JSON.parse_string(FileAccess.get_file_as_string(path))
		var h: Dictionary = d.get("hero", {}) if d is Dictionary else {}
		var inv: Array = (h.get("inventory", []) as Array).filter(func(x): return x != null)
		check(int(h.get("level", 0)) == 8 and inv.is_empty() and int(h.get("gold", -1)) == 0, "kept my level, lost my things")
		check(g.net.fx_got > 0, "I saw the other player's skill effects (%d events, through the server)" % g.net.fx_got)
	g.net.shutdown()
	await secs(1.0)

func _proxy():
	for e in g.world.enemies_root.get_children():
		if e is Enemy and e.pvp_pid > 0:
			return e
	return null
