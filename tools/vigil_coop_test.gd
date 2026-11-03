extends SceneTree
## The Last Flame (vigil.gd) on the online co-op server (coop_server.gd), three processes:
##   godot --headless --path . -s tools/vigil_coop_test.gd -- --server --coop --port 24661 server
##   godot --headless --path . -s tools/vigil_coop_test.gd -- a 24661 [addr <host>]
##   godot --headless --path . -s tools/vigil_coop_test.gd -- b 24661 [addr <host>]
## a and b join the server's camp, a steps through the Vigil Gate (b says yes to the ready check), both arrive at
## the Last Flame, a kindles it (the server runs it: the waves scaled for two), both see the state and the HUD,
## fight wave 1 off together (their blows reach the server's monsters) and see it held; the server reports it.

var g
var role := "a"
var port := 24661
var host := "127.0.0.1"
var fails := 0

func _initialize():
	var a := OS.get_cmdline_user_args()
	role = "server" if a.has("server") else ("b" if a.has("b") else "a")
	for i in a.size():
		if a[i].is_valid_int() and int(a[i]) > 1024:
			port = int(a[i])
	var ai := a.find("addr")
	if ai >= 0 and ai + 1 < a.size():
		host = a[ai + 1]
	g = (load("res://main.tscn") as PackedScene).instantiate()
	get_root().add_child(g)
	process_frame.connect(_answer_votes)
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

func _answer_votes() -> void:
	if role == "b" and g != null and g.ui != null and g.ui.vote_panel != null and g.ui.vote_panel.visible and g.ui.vote_yes.visible:
		g.ui.vote_yes.pressed.emit()

func _vigil():
	return g.world.get_meta("vigil") if g.world != null and g.world.has_meta("vigil") else null

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
	check(await until(func(): return g.coop_server != null and g.net.active and g.cur_zone == "town" and not g._busy, 40.0), "co-op server hosting the camp")
	check(await until(func(): return g.net.players.size() == 2, 90.0), "both players joined")
	check(await until(func(): return g.cur_zone == "vigil" and not g._busy, 90.0), "the party went down to the Last Flame")
	check(await until(func(): return _vigil() != null and _vigil().state != "idle", 60.0), "a player kindled it (the server runs it)")
	var v = _vigil()
	if v == null:
		return
	check(await until(func(): return v.state == "wave" and v.left > 0, 20.0), "wave 1 on the server")
	var n1: int = v.left
	check(n1 >= 9, "scaled for two players (%d monsters, 6 alone)" % n1)
	check(v.levels.size() == 2, "both players' levels known (%s)" % str(v.levels))
	check(await until(func(): return v.state == "break" and v.wave == 1, 150.0), "the players held wave 1 (flame %d/%d)" % [v.life, v.max_life])
	check(await until(func(): return g.net.players.is_empty(), 120.0), "both left at the end")

func _player() -> void:
	while g._busy:
		await wait(5)
	await secs(2.0 if role == "a" else 5.0)
	g.test_immortal = true
	g.test_onehit = true
	await g.start_join("%s:%d" % [host, port])
	check(await until(func(): return g.net.is_client() and g.cur_zone == "town" and not g._busy and not g.net.loading, 30.0), "joined the co-op server's camp")
	check(await until(func(): return g.net.puppets().size() == 1 and g.net.puppets()[0].net_has, 60.0), "the partner is here")
	if role == "a":
		await secs(6.0)
		var gate = null
		for t in g.world.interactables:
			if is_instance_valid(t) and t.kind == "vigil_gate":
				gate = t
		check(gate != null, "the camp's Vigil Gate")
		g.hero.global_position = g.world.free_spot_near(gate.global_position, 1.5)
		g._interact(gate)
	check(await until(func(): return g.cur_zone == "vigil" and not g._busy and not g.net.loading, 60.0), "the party went down to the Last Flame together")
	await secs(3.0)
	var v = _vigil()
	check(v != null and v.state == "idle", "the flame waits")
	if role == "a":
		for t in g.world.interactables:
			if is_instance_valid(t) and t.kind == "vigil":
				g._interact(t)
	check(await until(func(): return v.state in ["count", "wave"], 15.0), "the server kindled it (seen here: %s)" % v.state)
	check(await until(func(): return v.state == "wave" and v.wave == 1, 20.0), "wave 1 (seen here)")
	await until(func(): return g.ui.hud.get_node_or_null("vigil_hud") != null and str(g.ui.hud.get_node("vigil_hud").get_child(0).text).contains("WAVE 1"), 3.0)
	var hud = g.ui.hud.get_node_or_null("vigil_hud")
	check(hud != null and str(hud.get_child(0).text).contains("WAVE 1"), "the HUD shows it (%s)" % (hud.get_child(0).text if hud else "none"))
	# fight: go for the monster nearest the flame
	var kills := 0
	var end := Time.get_ticks_msec() + 140000
	while Time.get_ticks_msec() < end and v.state == "wave":
		var z = null
		var bd := INF
		for e in g.world.enemies_root.get_children():
			if "pvp_pid" in e and not e.dead and e.pvp_pid == 0:
				var d: float = e.global_position.distance_to(v.CENTER)
				if d < bd:
					bd = d
					z = e
		if z != null and (g.hero.target != z):
			g.hero.global_position = g.world.free_spot_near(z.global_position, 1.6)
			g.hero.target = z
			kills += 1
		await secs(0.25)
	check(v.state == "break" and v.wave == 1, "wave 1 held together (%d foes struck, flame %d/%d)" % [kills, v.life, v.max_life])
	await secs(2.0)
	g.net.shutdown()
	await secs(1.0)
