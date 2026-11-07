extends SceneTree
## Standing bot games, through the real lobby service and a real match server (jj: "it just shows games created
## missing 1 player, i join it and the game starts"). One client, an admin, `-- arena` (the 1v1) or `-- duo` (the
## Battlegrounds duo):
##   - the list has the test lobby one seat short; joining it starts the match at once
##   - in the match: the bot players are there (their names, their heroes), and they move
##   - arena: the bot fights you (your life drops); duo: one bot is your pair (same team), the other two aren't
## Run the service first: python3 deploy/lobbies/service.py --dev --standing --state <dir> --game . --godot <godot>
##   godot --headless --path . -s tools/_late.gd -- arena res://game/systems/bots/tests/bot_match_test.gd --broker <url>
var g
var mode := "arena"
var fails := 0

func _initialize():
	node_added.connect(func(n):
		if n is SubViewport:
			n.disable_3d = true)
	var args := OS.get_cmdline_user_args()
	mode = "duo" if args.has("duo") else "arena"
	var url := "http://127.0.0.1:7352"
	var i := args.find("--broker")
	if i >= 0 and i + 1 < args.size():
		url = str(args[i + 1])
	load("res://scripts/build_env.gd").forced = {"env": "local", "cloud": "0", "lobby_url": url}
	g = load("res://main.tscn").instantiate()
	g.char_dir = "user://bot_match_test_" + mode + "/"
	get_root().disable_3d = true
	get_root().add_child(g)
	_run()

func check(ok: bool, label: String) -> void:
	print("[BOTGAME-", mode, "] ", "ok   " if ok else "FAIL ", label)
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
	var c = g.lobby_client
	c.auth = "Bearer dev-admin-jj"
	c.identity = c.auth.sha256_text().substr(0, 24)
	var want := "Test arena · 1v1" if mode == "arena" else "Test raid · duo"
	if mode == "arena":
		var SV = load("res://scripts/survivors.gd")
		SV.dir = "user://bot_match_test_sv/"
		DirAccess.make_dir_recursive_absolute(SV.dir)
		var h = g.hero
		h.set_class("knight")
		h.start_run()
		var RB = load("res://game/items/run_build.gd")
		for k in 4:
			h.add_xp(RB.xp_for(h.level))
		h.run_changed()
		g.char_name = "Bot Tester"
		c.survivor = str(SV.save(h, g.char_name)[0])
		c.selected_mode = "arena"
		c.open("arena")
	else:
		c.run_class = "knight"
		c.open("battlegrounds")
	check(await until(func(): return c.rooms.any(func(r): return str(r.name) == want), 30), "the list has %s" % want)
	var rows: Array = c.rooms.filter(func(r): return str(r.name) == want)
	if rows.is_empty():
		_end()
		return
	var r: Dictionary = rows[0]
	check(int(r.joined) == int(r.capacity) - 1, "one seat short (%d/%d)" % [int(r.joined), int(r.capacity)])
	await c.action("join", {"id": r.id})
	var in_match := func(): return g.playing and g.world != null and not g._busy and g.net.active and (g.arena_mode if mode == "arena" else g.bg_mode)
	check(await until(in_match, 150), "joining starts the match and takes you in")
	var bots_n := int(r.capacity) - 1
	check(await until(func(): return g.net.players.size() >= bots_n and g.net.puppets().all(func(p): return p.net_has), 60), "%d bot player(s) in the match: %s" % [bots_n, str(g.net.players.values().map(func(p): return p.name))])
	var starts := {}
	for pid in g.net.players:
		starts[pid] = g.net.players[pid].hero.global_position
	var moved := func() -> bool:
		for pid in starts:
			if is_instance_valid(g.net.players[pid].hero) and g.net.players[pid].hero.global_position.distance_to(starts[pid]) > 2.0:
				return true
		return false
	check(await until(moved, 60), "the bots move")
	if mode == "arena":
		var l0: float = g.hero.max_life
		check(await until(func(): return g.hero.life < l0 - 1.0 or g.hero.dead, 90), "the bot fights you (life %d / %d)" % [int(g.hero.life), int(l0)])
	else:
		var teams: Dictionary = g.get_meta("bg_teams", {})
		var me := str(g.net.multiplayer.get_unique_id())
		var mine := int(teams.get(me, -1))
		var mates: Array = g.net.players.keys().filter(func(pid): return int(teams.get(str(pid), -2)) == mine)
		check(mine >= 0 and mates.size() == 1, "one bot is your pair (team %d: %s)" % [mine, str(mates)])
	_end()

func _end() -> void:
	print("[BOTGAME-%s] done, %d failed" % [mode, fails])
	quit(1 if fails else 0)
