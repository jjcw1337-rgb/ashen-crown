extends SceneTree
## The Plague Doctor in the Battlegrounds (PvP), three processes:
##   godot --headless --path . -s tools/plague_pvp_test.gd -- --server --port 24681 --raid-fast server
##   godot --headless --path . -s tools/plague_pvp_test.gd -- a 24681
##   godot --headless --path . -s tools/plague_pvp_test.gd -- b 24681
## a is a Plague Doctor, b stands still. a plants Corpse Bloom under b: its pulse snares b through the server
## (Net.sv_pvp_status -> Battlegrounds.pvp_status, with diminishing returns) and b's own game roots him and shows
## it (PvpStatusFx); then a's swarm harries b and Blights him. b's game sends what is on him in his state packet, so
## a sees the roots, the flies and the Blight marks on b's puppet, and nothing doubled on the stand-in a strikes.
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
		Battlegrounds.id_path = "user://plague_pvp_%s_id.txt" % role
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
	check(await until(func(): return not g.bg.pvp_dr.is_empty(), 90.0), "a status passed through the server, counted for diminishing returns")
	await until(func(): return g.net.players.is_empty(), 120.0)

func _player() -> void:
	while g._busy:
		await wait(5)
	await secs(2.0 if role == "a" else 4.0)
	g.char_dir = "user://plague_pvp_%s_chars/" % role
	DirAccess.make_dir_recursive_absolute(g.char_dir)
	for fn in DirAccess.get_files_at(g.char_dir):
		DirAccess.remove_absolute(g.char_dir + fn)
	g.hero.set_class("plague" if role == "a" else "knight")
	g.hero.new_character()
	g.hero.set_level(24)
	g.char_id = g.new_char_id()
	g.char_name = "Doctor" if role == "a" else "Patient"
	g.net.my_name = g.char_name
	g.save_game()
	await g.start_battlegrounds("%s:%d" % [host, port], g.char_id)
	check(await until(func(): return g.cur_zone == Battlegrounds.ZONE and not g._busy and not g.net.loading, 30.0), "entered the crypt")
	check(await until(func(): return g.net.puppets().size() == 1 and g.net.puppets()[0].net_has, 40.0), "the other player is here")
	g.test_immortal = true
	if role == "a":
		await _doctor()
	else:
		await _patient()
	g.net.shutdown()
	await secs(1.0)

func _doctor() -> void:
	var foe = g.net.puppets()[0]
	var h: Hero = g.hero
	check(await until(func(): return _proxy() != null, 10.0), "the other player is a target (a stand-in)")
	# close to him, the bloom planted beside him: he stands still through its warning, so its pulse roots him
	h.global_position = g.world.free_spot_near(foe.global_position + Vector3(5.0, 0, 0), 0.5)
	await secs(0.5)
	var spot: Vector3 = foe.global_position + Vector3(1.0, 0, 0)
	check(_use(h, "bloom", spot), "Corpse Bloom planted beside him")
	check(await until(func(): return is_instance_valid(foe) and foe.get_node_or_null("pvs_snare") != null, 15.0), "its pulse roots him, and I see the roots on him (from his own game)")
	# the swarm on him: harried, and Blighted from a second skill
	await until(func(): return h.atk_t < 0.0, 3.0)
	check(_use(h, "swarm", foe.global_position), "Swarmcraft sent onto him")
	check(await until(func(): return is_instance_valid(foe) and foe.get_node_or_null("pvs_harried") != null, 15.0), "the flies harry him, on his puppet")
	check(await until(func(): return is_instance_valid(foe) and foe.get_node_or_null("pd_blight") != null, 15.0), "his Blight marks show over him")
	var p = _proxy()
	check(p != null and p.get_node_or_null("pd_blight") == null and p.get_node_or_null("pd_fever") == null, "and nothing of it is doubled on the stand-in I strike")
	await secs(4.0)

func _patient() -> void:
	var h: Hero = g.hero
	check(await until(func(): return PvpStatus.has(h, "snare"), 60.0), "the doctor's bloom roots me (through the server)")
	check(await until(func(): return h.get_node_or_null("pvs_snare") != null, 1.0), "and I see the roots holding my feet")
	check(await until(func(): return PvpStatus.has(h, "harried") and h.get_node_or_null("pvs_harried") != null, 30.0), "his flies harry me, and I see them round my head")
	check(await until(func(): return PvpStatus.strength(h, "blight") >= 2.0 and h.get_node_or_null("pd_blight") != null, 30.0), "two of his skills Blight me, and I see the marks")
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
