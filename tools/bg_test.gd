extends SceneTree
## Battlegrounds (battlegrounds.gd), two processes on this machine:
##   godot --headless --path . -s tools/bg_test.gd -- --server --port 24611 server
##   godot --headless --path . -s tools/bg_test.gd -- client 24611 [cloud <nakama url> <server key>]
## With Nakama (the server started with ASHEN_NAKAMA_URL / ASHEN_NAKAMA_HTTP_KEY, the client with `cloud`), the client
## signs in and the stash is kept in Nakama; the server side then also reads it back from there.
## The server is the real dedicated server (Game boots it from --server); this side only reports on it.
## The client enters, kills a zombie, opens a chest and picks up the loot, extracts (the server files it in the
## stash), then enters again, picks something up and dies: the loot falls where they died and their stash keeps
## only what they extracted.

var g
var role := "client"
var port := 24611
var fails := 0

func _initialize():
	var a := OS.get_cmdline_user_args()
	role = "server" if a.has("server") else "client"
	for i in a.size():
		if a[i].is_valid_int() and int(a[i]) > 1024:
			port = int(a[i])
	if role == "client":
		Battlegrounds.id_path = "user://bg_test_id.txt"
		DirAccess.remove_absolute(Battlegrounds.id_path)    # a new player every run (a stash in Nakama outlives the run)
		Battlegrounds.cache_path = "user://bg_test_cache.json"
		var ci := a.find("cloud")
		if ci >= 0 and ci + 2 < a.size():
			BuildEnv.forced = {"cloud": "1", "nakama_url": a[ci + 1], "nakama_key": a[ci + 2]}
	g = (load("res://main.tscn") as PackedScene).instantiate()
	get_root().add_child(g)
	_run()

func check(ok: bool, what: String) -> void:
	if not ok:
		fails += 1
	print(("[%s] " % ("S" if role == "server" else "C")) + ("ok   " if ok else "FAIL ") + what)

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
		await _client()
	print("[%s] done, %d failed" % ["S" if role == "server" else "C", fails])
	quit()

func _server() -> void:
	await until(func(): return g.bg != null and g.net.active and g.cur_zone == Battlegrounds.ZONE and not g._busy, 40.0)
	g.bg.stash = {}
	g.bg.save_stash()
	check(g.net.server and g.net.is_host, "dedicated server hosting the raid")
	check(not g.hero.visible and g.hero.phased, "the server's own hero is hidden and unseen")
	var zombies := func() -> int:
		var n := 0
		for e in g.world.enemies_root.get_children():
			if e is Enemy and not e.dead:
				n += 1
		return n
	check(zombies.call() >= Battlegrounds.ZOMBIES, "%d zombies on the map" % zombies.call())
	check(await until(func(): return not g.net.players.is_empty(), 60.0), "a player joined")
	var pid: int = g.net.players.keys()[0] if not g.net.players.is_empty() else 0
	# the client's first raid ends in an extraction
	var got := await until(func(): return g.bg.stash.size() > 0 and (g.bg.stash.values()[0] as Array).size() > 0, 90.0)
	check(got, "the extraction filed the loot in the stash: %s" % str(g.bg.stash.values()[0].size() if got else 0))
	var first: int = (g.bg.stash.values()[0] as Array).size() if got else 0
	if g.bg.nk != null:
		var uid: String = g.bg.stash.keys()[0] if got else ""
		check(uid.begins_with("nk:"), "the player's account was confirmed by Nakama")
		# (the extraction's write to Nakama finishes just after the server's own copy changes)
		var n := -1
		for i in 20:
			var r: Dictionary = await g.bg.nk.server_rpc("bg_stash_read", {"user_id": uid.substr(3)}, g.bg.nk_key)
			n = (r["items"] as Array).size() if r.get("items") is Array else 0
			if n == first:
				break
			await secs(0.25)
		check(n == first, "and Nakama holds the stash (%d)" % n)
	else:
		check(FileAccess.file_exists(g.bg.stash_path), "the stash is saved on the server")
	# second raid: they die with loot
	check(await until(func(): return not g.net.players.is_empty() and (g.bg.carried.get(g.net.players.keys()[0], []) as Array).size() > 0, 60.0), "back in a second raid, carrying loot")
	# watch what they carry; when it empties (the death), it must be lying on the ground
	var w := {"last": []}       # (a lambda can't assign to the locals it captures, so a Dictionary carries it)
	var dropped := await until(func():
		if g.net.players.is_empty():
			return false
		var c: Array = g.bg.carried.get(g.net.players.keys()[0], [])
		if not c.is_empty():
			w["last"] = c.duplicate()
			return false
		return not (w["last"] as Array).is_empty(), 40.0)
	var last: Array = w["last"]
	await secs(0.5)
	var on_ground := 0
	for id in g.net.items:
		var gi = g.net.items[id]
		if is_instance_valid(gi) and last.has(gi.item):
			on_ground += 1
	check(dropped and on_ground == last.size(), "their death dropped what they carried (%d of %d on the ground)" % [on_ground, last.size()])
	await secs(3.0)
	check((g.bg.stash.values()[0] as Array).size() == first, "and the stash kept only what was extracted (%d)" % first)
	# zombies rise again after the kills
	await until(func(): return zombies.call() >= Battlegrounds.ZOMBIES, 30.0)
	check(zombies.call() >= Battlegrounds.ZOMBIES, "zombies respawned (%d)" % zombies.call())
	await until(func(): return g.net.players.is_empty(), 20.0)

func _client() -> void:
	while g._busy:
		await wait(5)
	await secs(2.0)
	g.test_immortal = true
	g.test_onehit = true
	await g.start_battlegrounds("127.0.0.1:%d" % port, "knight")
	check(await until(func(): return g.cur_zone == Battlegrounds.ZONE and not g._busy and not g.net.loading, 30.0), "entered the Battlegrounds")
	check(g.bg_mode and g.net.is_client() and not g.net.players.has(1), "as a raid player, with no host player in the roster")
	await secs(1.5)
	check(await until(func(): return g.world.enemies_root.get_child_count() > 0, 10.0), "the server's zombies are here (%d)" % g.world.enemies_root.get_child_count())
	# kill the nearest zombie
	var z = _nearest_enemy()
	check(z != null, "found a zombie")
	if z:
		g.hero.global_position = g.world.free_spot_near(z.global_position, 1.6)
		g.hero.target = z
		check(await until(func(): return not is_instance_valid(z) or z.dead, 20.0), "killed it")
	# a chest's loot
	var ch = _nearest("chest")
	g.hero.global_position = g.world.free_spot_near(ch.global_position, 1.6)
	await secs(0.5)
	g._interact(ch)
	check(await until(func(): return g.world.items_root.get_child_count() > 0, 10.0), "the chest dropped loot (%d)" % g.world.items_root.get_child_count())
	await secs(1.5)
	var n: int = await _pick_all()
	check(n > 0, "picked up %d item(s)" % n)
	# extract
	var ex = _nearest("extract")
	g.hero.target = null
	g.hero.global_position = g.world.free_spot_near(ex.global_position, 1.0)
	await secs(1.0)
	g._interact(ex)
	check(await until(func(): return not g.bg_mode, 15.0), "extracted and left the raid")
	check(g.bg_stash.size() > 0 and Battlegrounds.cached_stash().size() == g.bg_stash.size(), "the stash came back from the server (%d)" % g.bg_stash.size())
	check(await until(func(): return g.ui.bg_panel.visible, 15.0), "the Battlegrounds screen shows it")
	var stash0: int = g.bg_stash.size()
	# second raid: pick something up, then die
	await until(func(): return not g._busy, 20.0)
	await g.start_battlegrounds("127.0.0.1:%d" % port, "wraith")
	check(await until(func(): return g.cur_zone == Battlegrounds.ZONE and not g._busy and not g.net.loading, 30.0), "entered again as a wraith")
	await secs(1.5)
	var ch2 = _nearest("chest", true)
	if ch2:
		g.hero.global_position = g.world.free_spot_near(ch2.global_position, 1.6)
		await secs(0.5)
		g._interact(ch2)
		await until(func(): return g.world.items_root.get_child_count() > 0, 10.0)
	else:
		var z2 = _nearest_enemy()
		if z2:
			g.hero.global_position = g.world.free_spot_near(z2.global_position, 1.6)
			g.hero.target = z2
		await until(func(): return g.world.items_root.get_child_count() > 0, 30.0)
	await secs(1.5)
	var n2: int = await _pick_all()
	check(n2 > 0, "picked up %d item(s) in the second raid" % n2)
	await secs(1.0)
	g.test_immortal = false
	g.hero.take_hit(99999.0, g.hero.global_position + Vector3(1, 0, 0))
	check(g.hero.dead, "died")
	await secs(3.0)
	g.respawn()
	check(await until(func(): return not g.bg_mode, 15.0), "a death ends the raid")
	check(g.bg_stash.size() == stash0, "the stash still holds only the extracted loot (%d)" % g.bg_stash.size())

func _nearest_enemy():
	var best = null
	var bd := INF
	for e in g.world.enemies_root.get_children():
		if e is Enemy and not e.dead:
			var d: float = e.global_position.distance_to(g.hero.global_position)
			if d < bd:
				bd = d
				best = e
	return best

func _nearest(kind: String, unused := false):
	var best = null
	var bd := INF
	for t in g.world.interactables:
		if is_instance_valid(t) and t.kind == kind and not (unused and t.used):
			var d: float = t.global_position.distance_to(g.hero.global_position)
			if d < bd:
				bd = d
				best = t
	return best

## Picks up everything on the ground; returns how many the server took off the ground for us.
func _pick_all() -> int:
	var asked: Array = []
	for gi in g.world.items_root.get_children():
		# (items can vanish while we walk the list: someone else picked them up, or the server removed them)
		if is_instance_valid(gi) and gi is GroundItem and not gi.is_queued_for_deletion():
			g.hero.global_position = g.world.free_spot_near(gi.global_position, 0.8)
			g._pickup(gi)
			asked.append(gi)
			await secs(0.3)
	await secs(1.0)
	return asked.filter(func(x): return not is_instance_valid(x) or x.is_queued_for_deletion()).size()
