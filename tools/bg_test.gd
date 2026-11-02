extends SceneTree
## Battlegrounds (battlegrounds.gd), the Hollow Crypt, two processes on this machine:
##   godot --headless --path . -s tools/bg_test.gd -- --server --port 24611 --raid-fast server
##   godot --headless --path . -s tools/bg_test.gd -- client 24611 [addr <host>] [cloud <nakama url> <server key>]
## The client makes a real character (in a scratch character folder), takes it into the crypt (its save says
## in_raid), kills a monster, loots a chest, waits for the portals, extracts (the loot is in its own inventory and
## saved, in_raid off), goes back in, levels up and dies: it loses every item and its gold (a plain weapon given back),
## keeps its level, and its gear drops for others. The server
## checks the round (portals open, the collapse, a new round) and the drop. `--raid-fast` = a round of 150 s.

var g
var role := "client"
var port := 24611
var host := "127.0.0.1"
var fails := 0

func _initialize():
	var a := OS.get_cmdline_user_args()
	role = "server" if a.has("server") else "client"
	for i in a.size():
		if a[i].is_valid_int() and int(a[i]) > 1024:
			port = int(a[i])
	if role == "client":
		Battlegrounds.id_path = "user://bg_test_id.txt"
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
	check(g.net.server and g.net.is_host and Battlegrounds.fast, "dedicated server hosting the crypt (fast rounds)")
	check(not g.hero.visible and g.hero.phased, "the server's own hero is hidden and unseen")
	var mons := func() -> int:
		var n := 0
		for e in g.world.enemies_root.get_children():
			if e is Enemy and not e.dead:
				n += 1
		return n
	check(mons.call() >= 10, "%d monsters in the crypt" % mons.call())
	var e0 = g.world.enemies_root.get_child(0)
	check(e0 is Enemy and e0.max_life > Data.ENEMIES[e0.kind]["life"] * 2.0, "they are tougher than outside")
	check(Battlegrounds.portal_list(g.world).size() == 4, "four candidate portals")
	check(await until(func(): return not g.net.players.is_empty(), 60.0), "a player joined")
	check(await until(func(): return g.bg.open.size() == Battlegrounds.OPEN_PORTALS, 70.0), "two portals opened on time")
	var items0: int = g.net.items.size()
	check(await until(func(): return g.net.items.size() >= items0 + 3, 120.0), "the fallen hero's gear lay on the floor (%d items)" % (g.net.items.size() - items0))
	check(await until(func(): return g.bg.state == "reset", 120.0), "the crypt collapsed at the end of the round")
	check(await until(func(): return g.bg.state == "raid" and g.bg.raid_t < 5.0, 30.0), "and a new round began")

func _client() -> void:
	while g._busy:
		await wait(5)
	await secs(3.0)
	# a real character in a scratch folder
	g.char_dir = "user://bg_test_chars/"
	DirAccess.make_dir_recursive_absolute(g.char_dir)
	for fn in DirAccess.get_files_at(g.char_dir):
		DirAccess.remove_absolute(g.char_dir + fn)
	g.hero.set_class("knight")
	g.hero.new_character()
	g.char_id = g.new_char_id()
	g.char_name = "Testric"
	g.save_game()
	var id: String = g.char_id
	var path: String = g.char_dir + id + ".json"
	var inv0: int = _inv_count()
	var gold0: int = g.hero.gold
	check(FileAccess.file_exists(path), "made a character (%d items)" % inv0)
	g.test_immortal = true
	g.test_onehit = true
	await g.start_battlegrounds("%s:%d" % [host, port], id)
	check(await until(func(): return g.cur_zone == Battlegrounds.ZONE and not g._busy and not g.net.loading, 30.0), "entered the crypt as Testric")
	check(_save().get("in_raid", false), "the save says in_raid")
	check(await until(func(): return not g.bg_raid.is_empty(), 10.0), "the raid's clock arrived (%s)" % str(g.bg_raid.get("state", "?")))
	await secs(1.0)
	# one standard for attacks: the same timing, damage and cooldowns in the crypt as in the story game
	var same := true
	for sk in Data.skills_known(g.hero.cls):
		var sid := str(sk["id"]) if sk is Dictionary else str(sk)
		var inside := [g.hero.skill_cd(sid), g.hero.dmg_mult(sid)]
		g.bg_mode = false
		var outside := [g.hero.skill_cd(sid), g.hero.dmg_mult(sid)]
		g.bg_mode = true
		same = same and is_equal_approx(inside[0], outside[0]) and is_equal_approx(inside[1], outside[1])
	g.hero._start_attack("swipe1")
	var dur_in: float = g.hero.atk_dur
	g.bg_mode = false
	g.hero._start_attack("swipe1")
	var dur_out: float = g.hero.atk_dur
	g.bg_mode = true
	g.hero.atk_t = g.hero.atk_dur
	check(same and is_equal_approx(dur_in, dur_out), "attacks are the same in the crypt as outside (swing %.2f s)" % dur_in)
	var z = _nearest_enemy()
	check(z != null, "a monster nearby")
	if z:
		g.hero.global_position = g.world.free_spot_near(z.global_position, 1.6)
		g.hero.target = z
		check(await until(func(): return not is_instance_valid(z) or z.dead, 25.0), "killed it")
	var ch = _nearest("chest", true)
	if ch:
		g.hero.global_position = g.world.free_spot_near(ch.global_position, 1.6)
		await secs(0.5)
		g._interact(ch)
		await until(func(): return g.world.items_root.get_child_count() > 0, 10.0)
	await secs(1.5)
	var n: int = await _pick_all()
	check(n > 0, "picked up %d item(s)" % n)
	# a portal that isn't open refuses
	var ex = Battlegrounds.portal_list(g.world)[0]
	check(not bool(ex.data.get("open", false)) or not g.bg_raid["open"].is_empty(), "portals start closed")
	check(await until(func(): return not (g.bg_raid.get("open", []) as Array).is_empty(), 70.0), "the portals opened")
	var ps: Array = Battlegrounds.portal_list(g.world)
	var op = ps[int(g.bg_raid["open"][0])]
	g.hero.target = null
	g.hero.global_position = g.world.free_spot_near(op.global_position, 1.0)
	await secs(1.0)
	var held: int = _inv_count()
	g._interact(op)
	check(await until(func(): return not g.bg_mode, 15.0), "extracted")
	var sv := _save()
	check(FileAccess.file_exists(path) and not sv.get("in_raid", true), "the character is safe and saved (in_raid off)")
	var sgold: int = int((sv.get("hero", {}) as Dictionary).get("gold", 0))
	check((held > inv0 or sgold > gold0) and _count_saved(sv) >= held and sgold >= gold0, "and keeps what it found (%d -> %d items, %d -> %d gold)" % [inv0, held, gold0, sgold])
	# back in, and die
	await until(func(): return not g._busy and g.ui.title_panel.visible and g.ui.home.mode == "bg", 20.0)      # (back on the home screen, its Battlegrounds mode)
	await g.start_battlegrounds("%s:%d" % [host, port], id)
	check(await until(func(): return g.cur_zone == Battlegrounds.ZONE and not g._busy and not g.net.loading, 30.0), "went back in")
	await secs(2.0)
	g.hero.set_level(12)
	g.test_immortal = false
	for i in 10:      # (a shield can block a blow by chance)
		if not g.hero.dead:
			g.hero.take_hit(999999.0, g.hero.global_position + Vector3(1, 0, 0))
	check(g.hero.dead, "died")
	await secs(3.0)
	g.respawn()
	check(await until(func(): return not g.bg_mode and not g._busy, 20.0), "a death ends the raid")
	var after := _save(path)
	var eq: Dictionary = (after.get("hero", {}) as Dictionary).get("equipment", {})
	var worn: Array = eq.values().filter(func(x): return x != null)
	check(FileAccess.file_exists(path) and not after.get("in_raid", true), "the character lives on (saved, in_raid off)")
	check(int((after.get("hero", {}) as Dictionary).get("level", 0)) == 12, "with its level kept (12)")
	check(_count_saved(after) == 0 and int((after.get("hero", {}) as Dictionary).get("gold", -1)) == 0 and worn.size() == 1, "but every item and its gold are gone (a plain weapon left)")

func _save(p := "") -> Dictionary:
	if p == "":
		p = g.char_dir + g.char_id + ".json"
	if not FileAccess.file_exists(p):
		return {}
	var d = JSON.parse_string(FileAccess.get_file_as_string(p))
	return d if d is Dictionary else {}

func _count_saved(sv: Dictionary) -> int:
	var h: Dictionary = sv.get("hero", {})
	var n := 0
	for it in h.get("inventory", []):
		if it != null:
			n += 1
	return n

func _inv_count() -> int:
	var n := 0
	for it in g.hero.inventory:
		if it != null:
			n += 1
	return n

func _nearest_enemy():
	var best = null
	var bd := INF
	for e in g.world.enemies_root.get_children():
		if e is Enemy and not e.dead and e.pvp_pid == 0:
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
