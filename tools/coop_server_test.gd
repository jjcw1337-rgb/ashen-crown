extends SceneTree
## Online co-op on a dedicated server (coop_server.gd), three processes:
##   godot --headless --path . -s tools/coop_server_test.gd -- --server --coop --port 24641 server
##   godot --headless --path . -s tools/coop_server_test.gd -- a 24641 [addr <host>]
##   godot --headless --path . -s tools/coop_server_test.gd -- b 24641 [addr <host>]
## Player a and player b join with their own characters, see each other in the camp, a asks to go to the moor
## (b says yes to the ready check), both arrive, a kills a monster, b sees it die; the server reports both and the
## zone change. Each prints "FAIL" lines on failure.

var g
var role := "a"
var port := 24641
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

## player b says yes to every ready check
func _answer_votes() -> void:
	if role == "b" and g != null and g.ui != null and g.ui.vote_panel != null and g.ui.vote_panel.visible and g.ui.vote_yes.visible:
		g.ui.vote_yes.pressed.emit()

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
	check(not g.hero.visible and g.hero.phased, "with no player of its own")
	check(await until(func(): return g.net.players.size() == 2, 90.0), "both players joined (%d)" % g.net.players.size())
	check(await until(func(): return g.cur_zone == "wild" and not g._busy, 90.0), "the party went to the moor")
	check(await until(func(): return g.net.players.is_empty(), 120.0), "both left at the end")

func _player() -> void:
	while g._busy:
		await wait(5)
	await secs(2.0 if role == "a" else 5.0)
	g.test_immortal = true
	g.test_onehit = true
	await g.start_join("%s:%d" % [host, port])
	check(await until(func(): return g.net.is_client() and g.cur_zone == "town" and not g._busy and not g.net.loading, 30.0), "joined the co-op server's camp")
	check(not g.net.players.has(1), "no host player in the party (the server has none)")
	check(await until(func(): return g.net.puppets().size() == 1 and g.net.puppets()[0].net_has, 60.0), "the partner is here")
	# War Cry is a team skill: a roars beside b, and b's own game gets the battle buff (Net.send_team_buff)
	if role == "a":
		await secs(3.0)
		var pal = g.net.puppets()[0]
		g.hero.global_position = g.world.free_spot_near(pal.global_position, 2.0)
		g.hero.mana = g.hero.max_mana
		for k in g.hero.cds.keys():
			g.hero.cds[k] = 0.0
		check(g.hero.use_skill("war_cry", g.hero.global_position), "roared a War Cry beside the partner")
		check(await until(func(): return g.hero.buff_t > 0.0, 3.0), "and got its fury (when the roar lands)")
	else:
		check(await until(func(): return g.hero.buff_t > 0.0, 20.0), "the partner's War Cry gave me its fury")
	if role == "a":
		await secs(6.0)        # (b is still finding its feet in the camp)
		g.travel(0, "wild", "from_town")
	check(await until(func(): return g.cur_zone == "wild" and not g._busy and not g.net.loading, 60.0), "the party travelled to the moor together")
	await secs(3.0)
	check(await until(func(): return g.world != null and g.world.enemies_root.get_child_count() > 0, 20.0), "the server's monsters are here")
	if role == "a":
		var z = null
		var bd := INF
		for e in g.world.enemies_root.get_children():
			if e is Enemy and not e.dead and e.global_position.distance_to(g.hero.global_position) < bd:
				bd = e.global_position.distance_to(g.hero.global_position)
				z = e
		if z:
			g.hero.global_position = g.world.free_spot_near(z.global_position, 1.6)
			g.hero.target = z
			var zid: int = z.net_id
			check(await until(func(): return not is_instance_valid(z) or z.dead, 25.0), "killed a monster (#%d)" % zid)
			print("[A] killed ", zid)
		await secs(6.0)
	else:
		# b watches for one of the server's monsters to die while it does nothing
		var dead0 := 0
		await until(func(): return g.world != null and not g._busy, 20.0)
		for e in g.world.enemies_root.get_children():
			if e is Enemy and e.dead:
				dead0 += 1
		check(await until(func():
			var n := 0
			if g.world == null:
				return false
			for e in g.world.enemies_root.get_children():
				if not is_instance_valid(e) or (e is Enemy and e.dead):
					n += 1
			return n > dead0, 40.0), "saw the partner's kill")
		await secs(3.0)
	g.net.shutdown()
	await secs(1.0)
