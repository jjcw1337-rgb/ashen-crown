extends SceneTree
## The Gauntlet of Kings' balance probe: a bot hero runs the gauntlet alone (no cheats; it stands at the king and
## strikes, uses its class's first skills when it has the mana, drinks a potion when low, rises at the door when it
## falls; no offering is taken) and reports each king: how long it took and the lives it cost.
##   godot --headless --path . -s tools/gauntlet_sim.gd -- [class] [level] [max seconds] [geared]
var g

func _initialize():
	g = (load("res://main.tscn") as PackedScene).instantiate()
	get_root().add_child(g)
	_run()

func _run() -> void:
	var a := OS.get_cmdline_user_args()
	var cls: String = a[0] if a.size() > 0 else "knight"
	var lvl: int = int(a[1]) if a.size() > 1 else 10
	var limit: float = float(a[2]) if a.size() > 2 else 900.0
	Engine.max_fps = 60
	while g.world == null or g._busy:
		g._intro_skip = true
		await process_frame
	await g.start_game(false, cls)
	g.ui.close_all()
	if a.has("geared"):
		g.go_level_20()
		g.hero.set_level(lvl)
	else:
		g.hero.set_level(lvl)
		g.hero.talents = {}
	g.hero.recalc()
	g.hero.life = g.hero.max_life
	await g.load_zone(0, "gauntlet", "start")
	var gt = g.world.get_meta("gauntlet")
	gt.begin()
	var t0 := Time.get_ticks_msec()
	var k_t := 0.0
	var king := -1
	var falls := 0
	var was_dead := false
	var own: Array = Data.skills_for(cls)
	var n := 0
	while (Time.get_ticks_msec() - t0) / 1000.0 < limit and gt.state not in ["won", "lost"]:
		var now := (Time.get_ticks_msec() - t0) / 1000.0
		if gt.state == "fight" and gt.king != king:
			king = gt.king
			k_t = now
			print("[SIM] king %d (%s, level %d, %d life) comes at %.0f s" % [king + 1, gt.boss.kind, gt.boss.level, gt.boss.max_life, now])
		if gt.state == "boon":
			print("[SIM] king %d down after %.0f s (lives left %d, falls so far %d)" % [king + 1, now - k_t, gt.lives, falls])
			gt.t = 0.0
			while gt.state == "boon":
				await process_frame
		if g.hero.dead:
			if not was_dead:
				falls += 1
				was_dead = true
				await create_timer(3.0).timeout
				g.respawn()
		else:
			was_dead = false
			if g.hero.life < g.hero.max_life * 0.4:
				g.hero.drink(0)
			var b = gt.boss
			if b != null and is_instance_valid(b) and not b.dead:
				n += 1
				if n % 12 == 0 and not own.is_empty():
					var sk: Dictionary = own[(n / 12) % mini(4, own.size())]
					if g.hero.mana > float(sk.get("mana", 0)) + 5.0:
						g.hero.use_skill(str(sk["id"]), b.global_position)
				elif g.hero.target != b:
					g.hero.cmd_target(b)
		await create_timer(0.2).timeout
	var now2 := (Time.get_ticks_msec() - t0) / 1000.0
	print("[SIM] %s level %d%s: %s with %d of 4 kings down after %.0f s (%s), %d falls" % [cls, lvl, " geared" if a.has("geared") else "", gt.state, gt.splits.size(), now2, str(gt.splits), falls])
	quit()
