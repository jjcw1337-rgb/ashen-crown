extends SceneTree
## The Gauntlet of Kings (gauntlet.gd) on the online co-op server (coop_server.gd), three processes:
##   godot --headless --path . -s tools/gauntlet_coop_test.gd -- --server --coop --port 24663 server
##   godot --headless --path . -s tools/gauntlet_coop_test.gd -- a 24663 [addr <host>]
##   godot --headless --path . -s tools/gauntlet_coop_test.gd -- b 24663 [addr <host>]
## a and b join the server's camp, a steps through the Gauntlet Gate (b says yes to the ready check), both arrive in
## the throne hall, a strikes the gong (the server runs the run: lives and the kings' life scaled for two), both see
## the first king come with its life bar and the HUD, beat it together (their blows reach the server's king), b takes
## an offering (the server applies it and names him), both see the second king come wounded.

var g
var role := "a"
var port := 24663
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

func _gt():
	return g.world.get_meta("gauntlet") if g.world != null and g.world.has_meta("gauntlet") else null

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
	check(await until(func(): return g.cur_zone == "gauntlet" and not g._busy, 90.0), "the party went down to the Gauntlet")
	check(await until(func(): return _gt() != null and _gt().state != "idle", 60.0), "a player struck the gong (the server runs it)")
	var gt = _gt()
	if gt == null:
		return
	check(gt.lives == gt.LIVES + 1, "lives for two (%d)" % gt.lives)
	check(await until(func(): return gt.state == "fight" and gt.boss != null, 20.0), "the first king on the server")
	var k = gt.boss
	var solo: float = Data.ENEMIES["trex"]["life"] * (1.0 + 0.3 * (k.level - 1)) * g.run_mult("boss_life") * gt.KINGS[0]["life"]
	check(absf(k.max_life / solo - (1.0 + gt.PER_PLAYER)) < 0.05, "its life scaled for two (x%.2f)" % (k.max_life / solo))
	check(gt.levels.size() == 2, "both players' levels known (%s)" % str(gt.levels))
	check(await until(func(): return gt.state == "boon", 150.0), "the players beat the first king (%s)" % gt.clock(gt.run_t))
	check(await until(func(): return gt.boon == 1 and gt.state in ["count", "fight"], 40.0), "b's offering (Wrath) taken on the server")
	check(await until(func(): return gt.state == "fight" and gt.boss != null and gt.boss.kind == "sloth_fire", 15.0), "the second king comes")
	check(await until(func(): return g.net.players.is_empty(), 120.0), "both left at the end")
	await secs(1.0)
	check(gt.state == "idle", "the hall reset when the party left")

func _player() -> void:
	while g._busy:
		await wait(5)
	await secs(2.0 if role == "a" else 5.0)
	g.test_immortal = true
	g.test_onehit = false
	await g.start_join("%s:%d" % [host, port])
	check(await until(func(): return g.net.is_client() and g.cur_zone == "town" and not g._busy and not g.net.loading, 30.0), "joined the co-op server's camp")
	check(await until(func(): return g.net.puppets().size() == 1 and g.net.puppets()[0].net_has, 60.0), "the partner is here")
	if role == "a":
		await secs(6.0)
		var gate = null
		for t in g.world.interactables:
			if is_instance_valid(t) and t.kind == "gauntlet_gate":
				gate = t
		check(gate != null, "the camp's Gauntlet Gate")
		g.hero.global_position = g.world.free_spot_near(gate.global_position, 1.5)
		g._interact(gate)
	check(await until(func(): return g.cur_zone == "gauntlet" and not g._busy and not g.net.loading, 60.0), "the party went down to the Gauntlet together")
	await secs(3.0)
	var gt = _gt()
	check(gt != null and (gt.state == "idle" or role == "b"), "the gong waits (%s)" % (gt.state if gt else "-"))
	if role == "a":
		for t in g.world.interactables:
			if is_instance_valid(t) and t.kind == "gauntlet":
				g._interact(t)
	check(await until(func(): return gt.state in ["count", "fight"], 15.0), "the server started the run (seen here: %s)" % gt.state)
	check(await until(func(): return gt.state == "fight" and gt.boss != null and is_instance_valid(gt.boss), 20.0), "the first king came (seen here)")
	var k = gt.boss
	check(k != null and k.kind == "trex" and absf(k.max_life - k.life) < k.max_life * 0.2 and k.max_life > Data.ENEMIES["trex"]["life"], "its life from the server (%d/%d)" % [k.life if k else 0, k.max_life if k else 0])
	await until(func(): return g.ui.boss_ref == k, 5.0)
	check(g.ui.boss_ref == k, "its life bar on screen")
	await until(func(): return g.ui.hud.get_node_or_null("gauntlet_hud") != null and str(g.ui.hud.get_node("gauntlet_hud").get_child(0).text).contains("KING 1/4"), 3.0)
	var hud = g.ui.hud.get_node_or_null("gauntlet_hud")
	check(hud != null and str(hud.get_child(0).text).contains("KING 1/4"), "the HUD shows it (%s)" % (hud.get_child(0).text if hud else "none"))
	# fight it: stand by it and strike
	g.test_onehit = true
	var end := Time.get_ticks_msec() + 140000
	while Time.get_ticks_msec() < end and gt.state == "fight" and is_instance_valid(k) and not k.dead:
		if g.hero.target != k or g.hero.global_position.distance_to(k.global_position) > 5.0:
			g.hero.global_position = g.world.free_spot_near(k.global_position + (g.hero.global_position - k.global_position).normalized() * 3.0, 1.6)
			g.hero.target = k
		await secs(0.25)
	g.test_onehit = false
	check(await until(func(): return gt.state == "boon", 10.0), "the first king beaten together, the offerings open (seen here)")
	await secs(1.0)
	if role == "b":
		for t in g.world.interactables:
			if is_instance_valid(t) and t.kind == "gauntlet_boon" and int(t.data.get("i", -1)) == 1:
				g._interact(t)
	check(await until(func(): return gt.boon == 1 and gt.state in ["count", "fight"], 15.0), "Wrath taken (seen here)")
	check(await until(func(): return gt.state == "fight" and gt.boss != null and is_instance_valid(gt.boss) and gt.boss.kind == "sloth_fire", 20.0), "the second king came")
	await secs(1.5)
	var k2 = gt.boss
	check(k2 != null and is_instance_valid(k2) and absf(k2.life / k2.max_life - gt.WRATH) < 0.06, "wounded by Wrath (%d%%)" % int(100.0 * k2.life / maxf(1.0, k2.max_life)))
	await secs(2.0)
	g.net.shutdown()
	await secs(1.0)
