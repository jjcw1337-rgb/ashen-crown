extends SceneTree
## The admin role on the Battlegrounds server (Blaine's progression overhaul: "enforce authorization on the server"):
## "Go to level 20" gear (items marked "boost") is for admins only. Two processes:
##   godot --headless --path . -s tools/bg_admin_test.gd -- --server --port 24661 server
##   godot --headless --path . -s tools/bg_admin_test.gd -- client 24661
## The client goes in with a character in boosted gear and is turned away ("boosted"); then its per-PC id is put on
## the server's admin list (user://bg_server/admins.json, the stand-in for Nakama's role without Nakama) and it goes
## in and stays. Then it uses the admin's raid controls (Open gates, Open portals, Restart round: the crypt collapses on
## it) and gets back into the new round after the server has moved it past the time joining closes.
var g
var role := "client"
var port := 24661
var fails := 0
const ADMINS := "user://bg_server/admins.json"

func _initialize():
	var a := OS.get_cmdline_user_args()
	role = "server" if a.has("server") else "client"
	for x in a:
		if x.is_valid_int() and int(x) > 1024:
			port = int(x)
	if role == "client":
		Battlegrounds.id_path = "user://bg_admin_test_id.txt"
	else:
		DirAccess.make_dir_recursive_absolute("user://bg_server")
		DirAccess.remove_absolute(ADMINS)
	g = (load("res://main.tscn") as PackedScene).instantiate()
	get_root().add_child(g)
	_run()

func check(ok: bool, what: String) -> void:
	if not ok:
		fails += 1
	print(("[%s] " % ("S" if role == "server" else "C")) + ("ok   " if ok else "FAIL ") + what)

func until(f: Callable, t: float) -> bool:
	var end := Time.get_ticks_msec() + int(t * 1000.0)
	while Time.get_ticks_msec() < end:
		if f.call():
			return true
		await process_frame
	return false

func _run() -> void:
	Engine.max_fps = 60
	for i in 30:
		await process_frame
	if role == "server":
		await until(func(): return g.bg != null and g.net.active and not g._busy, 40.0)
		# the first visit: turned away; then the client writes its id here (the two share this PC's user://) and comes back
		check(await until(func(): return not g.net.players.is_empty(), 60.0), "a player came")
		check(await until(func(): return g.net.players.is_empty(), 20.0), "and was turned away")
		check(await until(func(): return not g.net.players.is_empty(), 60.0), "they came back as an admin")
		var stayed := await until(func(): return g.net.players.is_empty(), 10.0)
		check(not stayed, "and stayed")
		# the admin's raid controls (Escape → Admin in a raid): the gates, the portals, a restart
		check(await until(func(): return g.bg.state == "raid", 30.0), "an admin's \"Open gates\": the raid is on")
		check(await until(func(): return not g.bg.open.is_empty(), 20.0), "\"Open portals\": %d open" % g.bg.open.size())
		check(await until(func(): return g.bg.forced, 20.0), "\"Restart round\": a new round, off the clock")
		check(await until(func(): return g.bg.state == "lobby" and not g._busy, 20.0), "starting in the antechamber")
		g.bg.raid_t = Battlegrounds.secs(Battlegrounds.JOIN_CLOSE) + 5.0      # (late in the round: joining has closed)
		check(await until(func(): return not g.net.players.is_empty(), 60.0), "an admin still gets into a round closed to new players")
		await until(func(): return g.net.players.is_empty(), 30.0)
	else:
		while g._busy:
			await process_frame
		g.char_dir = "user://bg_admin_test_chars/"
		DirAccess.make_dir_recursive_absolute(g.char_dir)
		for fn in DirAccess.get_files_at(g.char_dir):
			DirAccess.remove_absolute(g.char_dir + fn)
		g.hero.set_class("knight")
		g.hero.new_character()
		g.char_id = g.new_char_id()
		g.char_name = "Boostric"
		g.dev_tools = true
		g.go_level_20()
		g.save_game()
		var id: String = g.char_id
		await g.start_battlegrounds("127.0.0.1:%d" % port, id)
		check(await until(func(): return g.bg_refusal == "boosted", 30.0), "in \"Go to level 20\" gear without the admin role: turned away")
		check("admins" in g.net.join_failure(""), "and told why: %s" % g.net.join_failure(""))
		while g._busy or g.net.active:
			await process_frame
		var f := FileAccess.open(ADMINS, FileAccess.WRITE)
		f.store_string(JSON.stringify([Battlegrounds.client_id()]))
		f.close()
		await create_timer(2.0).timeout
		await g.start_battlegrounds("127.0.0.1:%d" % port, id)
		check(await until(func(): return g.cur_zone == Battlegrounds.ZONE and not g._busy and not g.net.loading, 30.0), "on the admin list: in the crypt")
		await create_timer(6.0).timeout
		check(g.net.active and g.bg_refusal == "", "and still there after the server's gear check")
		g.net.send_bg_admin("gates")
		check(await until(func(): return str(g.bg_raid.get("state", "")) == "raid", 20.0), "Open gates: the raid is on")
		g.net.send_bg_admin("portals")
		check(await until(func(): return not (g.bg_raid.get("open", []) as Array).is_empty(), 20.0), "Open portals: they're open")
		g.net.send_bg_admin("restart")
		check(await until(func(): return g.hero.dead or not g.net.active, 20.0), "Restart round: the crypt collapsed on him")
		while g._busy or g.net.active:
			await process_frame
		await create_timer(6.0).timeout
		await g.start_battlegrounds("127.0.0.1:%d" % port, id)
		check(await until(func(): return g.cur_zone == Battlegrounds.ZONE and not g._busy and not g.net.loading, 40.0), "back in, though joining has closed")
		g.net.shutdown()
		DirAccess.remove_absolute(ADMINS)
	print("[%s] done, %d failed" % ["S" if role == "server" else "C", fails])
	quit()
