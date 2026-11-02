extends SceneTree
## The Last Flame's balance probe: a bot hero defends the flame alone (no cheats; it goes for the monster nearest
## the flame, drinks a potion when low, rises by the altar when it falls) and reports each wave: the flame's life,
## its deaths, the time. godot --headless --path . -s tools/vigil_sim.gd -- [class] [level] [max seconds]
var g

func _initialize():
	g = (load("res://main.tscn") as PackedScene).instantiate()
	get_root().add_child(g)
	_run()

func _run() -> void:
	var a := OS.get_cmdline_user_args()
	var cls: String = a[0] if a.size() > 0 else "knight"
	var lvl: int = int(a[1]) if a.size() > 1 else 5
	var limit: float = float(a[2]) if a.size() > 2 else 900.0
	Engine.max_fps = 60
	while g.world == null or g._busy:
		g._intro_skip = true
		await process_frame
	await g.start_game(false, cls)
	g.ui.close_all()
	g.hero.set_level(lvl)
	g.hero.talents = {}
	await g.load_zone(0, "vigil", "start")
	var v = g.world.get_meta("vigil")
	v.begin()
	var t0 := Time.get_ticks_msec()
	var deaths := 0
	var wave := 0
	var was_dead := false
	var dbg := 0.0
	while (Time.get_ticks_msec() - t0) / 1000.0 < limit and v.state not in ["won", "lost"]:
		if v.wave != wave:
			print("[SIM] wave %d starts at %.0f s: flame %d/%d, deaths %d" % [v.wave, (Time.get_ticks_msec() - t0) / 1000.0, v.life, v.max_life, deaths])
			wave = v.wave
		if g.hero.dead:
			if not was_dead:
				deaths += 1
				was_dead = true
				await create_timer(3.0).timeout
				g.respawn()
		else:
			was_dead = false
			if g.hero.life < g.hero.max_life * 0.35:
				g.hero.drink(0)
			var z = null
			var bd := INF
			for e in g.world.enemies_root.get_children():
				if "pvp_pid" in e and not e.dead and e.pvp_pid == 0:
					var d: float = e.global_position.distance_to(v.CENTER)
					if d < bd:
						bd = d
						z = e
			if z != null and g.hero.target != z:
				g.hero.cmd_target(z)
			if v.state == "break":
				v.t = minf(v.t, 2.0)
		dbg += 0.2
		if dbg > 15.0:
			dbg = 0.0
			var ms := []
			for e in g.world.enemies_root.get_children():
				if "pvp_pid" in e and not e.dead:
					ms.append("%s@(%.0f,%.0f) aggro=%s taunt=%s atk=%.1f" % [e.kind, e.global_position.x, e.global_position.z, e.aggro, e.taunt != null, e.atk_t])
			print("[DBG] %s wave %d left %d queue %d alive %d hero (%.0f,%.0f) target=%s mons=%s" % [v.state, v.wave, v.left, v.queue.size(), v.alive.size(), g.hero.global_position.x, g.hero.global_position.z, g.hero.target != null, ms])
		await create_timer(0.2).timeout
	print("[SIM] %s level %d: %s at wave %d after %.0f s, flame %d/%d, %d deaths, hero level %d" % [cls, lvl, v.state, v.wave, (Time.get_ticks_msec() - t0) / 1000.0, v.life, v.max_life, deaths, g.hero.level])
	quit()
