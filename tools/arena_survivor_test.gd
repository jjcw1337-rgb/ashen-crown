extends SceneTree
## Survivors in the Arena, through the real HTTP lobby service and a real Arena worker (Blaine's overhaul, step 7).
## Two clients, `-- a` and `-- b`, each with a survivor saved from a run (its own survivor folder):
##   1. a Battlegrounds lobby: a hosts, b joins, a changes class (the service's pick): b sees a's new class and a's
##      ready mark cleared; both leave
##   2. an Arena lobby: each brings its survivor; both ready, a starts; the ticket hands both into the Arena worker
##      with the survivor loaded (its class, level, skills and slots, passives); real PvP damage resolves the rounds;
##      the match ends back home with the survivor's file untouched (no deletion on a loss)
## Run through tools/nightly/lobby_gate.py arena <output> --godot <godot> --rendered.
var g
var role := "a"
var fails := 0
var checks := 0
var SV
var RB
var capture := ""

func _initialize():
	if not bool(ProjectSettings.get_setting("application/config/use_custom_user_dir", false)) or not OS.get_user_data_dir().get_file().begins_with("AshenCrown-"):
		printerr("ERROR: Arena fixture requires an isolated AshenCrown-* custom user directory")
		quit(2)
		return
	node_added.connect(func(n):
		if n is SubViewport and DisplayServer.get_name() == "headless":
			n.disable_3d = true)
	var args := OS.get_cmdline_user_args()
	role = "b" if args.has("b") else "a"
	var broker := ""
	if args.has("--broker"): broker = args[args.find("--broker") + 1]
	if args.has("--capture"): capture = args[args.find("--capture") + 1]
	if not broker.begins_with("http://127.0.0.1:"):
		printerr("Arena fixture requires an explicit loopback --broker")
		quit(2)
		return
	load("res://scripts/build_env.gd").forced = {"env": "local", "cloud": "0", "lobby_url": broker}
	g = load("res://main.tscn").instantiate()
	g.char_dir = "user://arena_survivor_test_" + role + "/"
	g.old_save = g.char_dir + "absent.json"
	get_root().disable_3d = DisplayServer.get_name() == "headless"
	get_root().add_child(g)
	current_scene = g
	SV = load("res://scripts/survivors.gd")
	RB = load("res://scripts/run_build.gd")
	_run()

func check(ok: bool, label: String) -> void:
	checks += 1
	print("[ARENA-", role, "] ", "ok " if ok else "FAIL ", label)
	if not ok:
		fails += 1

func until(test: Callable, seconds := 90.0) -> bool:
	var end := Time.get_ticks_msec() + int(seconds * 1000)
	while Time.get_ticks_msec() < end:
		g._intro_skip = true
		if test.call():
			return true
		await process_frame
	return false

func _run() -> void:
	Engine.max_fps = 30
	check(await until(func(): return g.world != null and not g._busy and not g._intro_playing), "home ready")
	SV.dir = "user://arena_survivor_test_sv_" + role + "/"
	DirAccess.make_dir_recursive_absolute(SV.dir)
	for fn in DirAccess.get_files_at(SV.dir):
		DirAccess.remove_absolute(SV.dir + fn)
	# a survivor as a run would leave it
	var cls := "archer" if role == "a" else "plague"
	var h = g.hero
	h.set_class(cls)
	h.start_run()
	for i in 6:
		h.add_xp(RB.xp_for(h.level))
	var pool: Array = RB.skill_pool(cls)
	for i in 6:
		h.run.add_skill(str(pool[i]["id"]), h.binds)
	h.run.passives = {"g_hide": 2}
	h.run_changed()
	g.char_name = "Survivor " + role
	var saved: Array = SV.save(h, g.char_name)
	var sid := str(saved[0])
	var want := {"cls": cls, "level": h.level, "skills": h.run.skills.duplicate(), "rmb": h.bound("rmb")}
	var file_before := FileAccess.get_file_as_string(SV.dir + sid + ".json")
	h.set_class("knight")
	h.new_character()
	check(sid != "" and h.run == null, "a survivor saved (%s level %d)" % [cls, want["level"]])
	var c = g.lobby_client
	c.auth = "Bearer dev-surv-" + role
	c.identity = c.auth.sha256_text().substr(0, 24)
	# 1. a Battlegrounds lobby: the class pick reaches the other player
	c.run_class = "archer"
	c.open("battlegrounds")
	await create_timer(1).timeout
	if role == "a":
		await c.action("create", {"mode": "battlegrounds", "name": "Class Test " + str(randi() % 1000)})
	else:
		check(await until(func(): return c.rooms.any(func(r): return str(r.name).begins_with("Class Test"))), "b sees the Battlegrounds lobby")
		var r0 = c.rooms.filter(func(r): return str(r.name).begins_with("Class Test"))
		if not r0.is_empty():
			await c.action("join", {"id": r0[0].id})
	check(await until(func(): return c.room.get("members", {}).size() == 2), "two players in the Battlegrounds lobby")
	if role == "a":
		await c.action("ready", {"ready": true})
		await create_timer(2).timeout
		c.run_class = "plague"
		await c.action("pick", {"id": str(c.room.id)})
		var me: Dictionary = c.room.members.get(c.identity, {})
		check(str(me.get("character", "")) == "run_plague" and not me.get("ready", true), "a's class change: run_plague, not ready any more")
	else:
		check(await until(func(): return c.room.get("members", {}).values().any(func(m): return str(m.get("character", "")) == "run_plague"), 30), "b sees a's new class (run_plague)")
	await create_timer(4).timeout
	await c.action("leave")
	await create_timer(3).timeout
	# 2. the Arena with the survivors
	c.survivor = sid
	c.selected_mode = "arena"
	c.draw()
	check(c.member_character("arena") == sid, "the Arena lobby brings the survivor")
	if role == "a":
		await c.action("create", {"mode": "arena", "team_size": 1, "name": "Survivor Arena " + str(randi() % 1000), "wager": false})
	else:
		check(await until(func(): return c.rooms.any(func(r): return str(r.name).begins_with("Survivor Arena"))), "b sees the Arena lobby")
		var r1 = c.rooms.filter(func(r): return str(r.name).begins_with("Survivor Arena"))
		if not r1.is_empty():
			await c.action("join", {"id": r1[0].id})
	check(await until(func(): return c.room.get("members", {}).size() == 2), "two players in the Arena lobby")
	await c.action("ready", {"ready": true})
	if role == "a":
		check(await until(func(): return c.room.members.values().all(func(m): return m.ready)), "both ready")
		await c.action("start")
	check(await until(func(): return g.net.is_client() and g.net.welcomed and not g.net.loading and not g._busy and g.cur_zone == "arena", 120), "handed into the Arena")
	check(g.arena_mode and g.hero.run != null and g.hero.cls == want["cls"] and g.hero.level == want["level"], "fighting as the survivor (%s level %d)" % [g.hero.cls, g.hero.level])
	check(g.hero.run.skills == want["skills"] and g.hero.bound("rmb") == want["rmb"], "with its skills and slots")
	check(await until(func(): return g.net.players.size() == 1), "the opponent is there")
	check(await until(func(): return g.arena_state.get("phase", "") == "fight", 120), "a round begins after both clients finish preparation")
	if DisplayServer.get_name() != "headless":
		check(not g.get_viewport().disable_3d and ResCache.status(g._zone_scope).ready and ResCache.status(g._combat_scope).ready, "Arena content ready and rendering restored before combat")
		if capture != "":
			get_root().disable_3d = false
			for i in 10: await process_frame
			await RenderingServer.frame_post_draw
			get_root().get_texture().get_image().save_png(capture)

	if role == "a":
		for round_index in 2:
			check(await until(func(): return g.arena_state.get("phase", "") == "fight", 30), "round %d" % (round_index + 1))
			var end := Time.get_ticks_msec() + 12000
			while Time.get_ticks_msec() < end and g.arena_state.get("phase", "") == "fight":
				for pid in g.net.players:
					g.net.send_pvp_hit(pid, 5000, g.hero.global_position)
				await create_timer(0.2).timeout
	check(await until(func(): return not g.playing and g.ui.title_panel.visible, 90), "the match ends back home")
	check(SV.exists(sid) and FileAccess.get_file_as_string(SV.dir + sid + ".json") == file_before, "the survivor is kept as it was (no deletion, no change)")
	await create_timer(6).timeout
	c.panel.hide()
	c.room = {}
	g.net.shutdown()
	g.queue_free()
	for i in 30:
		await process_frame
	check(ResCache.metrics().scopes == 0 and ResCache.metrics().pending == 0, "teardown releases content scopes and loading work")
	print("[ARENA-", role, "] done ", checks, " checks / ", fails, " failures")
	quit(1 if fails else 0)
