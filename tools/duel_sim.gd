extends SceneTree
## Real duels between bots in the admins' sandbox (Sandbox, BotBrain): every class against every class at a level,
## both fresh or both geared, and each class geared against itself fresh; each pairing `rounds` times, the two spawned
## 9 m apart in the Proving Crypt and left to fight (free for all) until one falls or `cap` seconds pass. Prints the
## win rates and how long kills take, and flags what misses Blaine's targets:
## a geared class should beat the same class fresh (>= 80% at the same skill); no class pairing past 70/30 at equal
## gear.
##   godot --headless --fixed-fps 30 --path . -s tools/duel_sim.gd -- [levels=1,5,10,20] [classes=knight,demon]
##       [rounds=4] [cap=60] [gear=geared|fresh|both] [mirror] [out=x.json]
## Lines [DUEL] are the fights, [DUEL-ROW] each class's summary, [DUEL-FLAG] what misses a target.
var g
var SB
var levels: Array = [20]
var classes: Array = ["knight", "wraith", "demon", "warlock", "archer", "plague", "doug"]
var rounds := 4
var cap := 60.0
var gears: Array = ["geared"]
var mirror := false        # also each class geared against itself fresh
var b_first := false       # "b_first": spawn the second side first (to rule out an order bias)
var out_path := ""
var results := {}          # "a|b|lvl|gear" -> {wins_a, wins_b, draws, secs}

func _initialize():
	for a in OS.get_cmdline_user_args():
		if a.begins_with("levels="):
			levels = Array(a.substr(7).split(",")).map(func(x): return int(x))
		elif a.begins_with("classes="):
			classes = Array(a.substr(8).split(","))
		elif a.begins_with("rounds="):
			rounds = int(a.substr(7))
		elif a.begins_with("cap="):
			cap = float(a.substr(4))
		elif a.begins_with("gear="):
			gears = ["geared", "fresh"] if a.substr(5) == "both" else [a.substr(5)]
		elif a == "mirror":
			mirror = true
		elif a == "b_first":
			b_first = true
		elif a.begins_with("out="):
			out_path = a.substr(4)
	SB = load("res://scripts/sandbox.gd")
	g = (load("res://main.tscn") as PackedScene).instantiate()
	get_root().add_child(g)
	_run()

func frames(n: int) -> void:
	for i in n:
		await process_frame

func _run() -> void:
	while g.world == null or g._busy:
		await frames(5)
	await g.start_game(false, "knight")
	while g._busy:
		await frames(5)
	g.ui.close_all()
	g.dev_tools = true
	await g.open_sandbox()
	while g._busy:
		await frames(5)
	var sb = g.sandbox
	sb.ffa = true
	g.test_immortal = true
	g.hero.global_position = Vector3(0, 0, 18)      # the player out of the way, untouchable
	for lvl in levels:
		for gear in gears:
			for i in classes.size():
				for j in range(i + 1, classes.size()):
					await _pair(sb, classes[i], gear, classes[j], gear, lvl)
		if mirror:
			for c in classes:
				await _pair(sb, c, "geared", c, "fresh", lvl)
	_report()
	if out_path != "":
		var f := FileAccess.open(out_path, FileAccess.WRITE)
		f.store_string(JSON.stringify(results, " "))
	print("[DUEL] done")
	quit()

func _pair(sb, ca: String, ga: String, cb: String, gb: String, lvl: int) -> void:
	var key := "%s %s|%s %s|%d" % [ca, ga, cb, gb, lvl]
	var r := {"a": 0, "b": 0, "draw": 0, "secs": []}
	for k in rounds:
		sb.clear_bots()
		sb.clear_monsters()
		await frames(3)
		# sides swap every round, so neither always starts on the same spot
		var a
		var b
		if b_first or k % 2 == 1:          # (the spawn order alternates too: in a burst duel who acts first matters)
			b = sb.spawn_bot(cb, lvl, gb)
			a = sb.spawn_bot(ca, lvl, ga)
		else:
			a = sb.spawn_bot(ca, lvl, ga)
			b = sb.spawn_bot(cb, lvl, gb)
		var pa := Vector3(-4.5, 0, -2) if k % 2 == 0 else Vector3(4.5, 0, -2)
		a.global_position = g.world.free_spot_near(pa, 1.0)
		b.global_position = g.world.free_spot_near(Vector3(-pa.x, 0, -2), 1.0)
		var t := 0.0
		while t < cap and not a.dead and not b.dead:
			g.hero.global_position = Vector3(0, 0, 18)
			await process_frame
			t += 1.0 / 30.0
		if a.dead and not b.dead:
			r["b"] += 1
		elif b.dead and not a.dead:
			r["a"] += 1
		else:
			r["draw"] += 1
		r["secs"].append(snappedf(t, 0.1))
	results[key] = r
	print("[DUEL] L%-2d %-16s vs %-16s  %d-%d (%d draws)  %s s" % [lvl, ca + " " + ga, cb + " " + gb, r["a"], r["b"], r["draw"], str(r["secs"])])
	sb.clear_bots()

func _report() -> void:
	var wins := {}
	var games := {}
	for key in results:
		var p: Array = key.split("|")
		var a: String = p[0]
		var b: String = p[1]
		var r: Dictionary = results[key]
		var n: float = float(r["a"] + r["b"] + r["draw"])
		var wa: float = (float(r["a"]) + 0.5 * float(r["draw"])) / maxf(1.0, n)
		if a.split(" ")[0] == b.split(" ")[0]:
			# the same class, geared against fresh
			if wa < 0.8:
				print("[DUEL-FLAG] L%s %s: geared beat fresh only %d%%" % [p[2], a.split(" ")[0], int(wa * 100)])
			continue
		for side in [[a, wa], [b, 1.0 - wa]]:
			var c: String = str(side[0]) + " L" + p[2]
			wins[c] = float(wins.get(c, 0.0)) + float(side[1])
			games[c] = int(games.get(c, 0)) + 1
		if wa > 0.7 or wa < 0.3:
			print("[DUEL-FLAG] L%s %s vs %s: %d%%" % [p[2], a, b, int(wa * 100)])
	for c in wins:
		print("[DUEL-ROW] %-22s wins %d%% of its pairings" % [c, int(100.0 * float(wins[c]) / maxf(1, games[c]))])
