extends SceneTree
## What each skill effect costs every time it plays, after warming (the frame-time audit, Blaine 2026-11-05): on the
## moor, the classes' effects are warmed (SkillWarm), then every recorded event (SkillWarmData) is played on a
## puppet `rounds` times; prints each event's call time (median, worst) and the worst frame after it, slowest first.
## Needs a display.
##   godot --path . -s tools/_late.gd -- res://tools/fx_bench.gd [classes plague,demon,archer] [rounds 3] [top 40]

var g
var _last := 0
var dt := 0.0

func _initialize():
	g = (load("res://main.tscn") as PackedScene).instantiate()
	get_root().add_child(g)
	_last = Time.get_ticks_usec()
	_run()

func _process(_d: float) -> bool:
	var now := Time.get_ticks_usec()
	dt = maxf(dt, (now - _last) / 1000.0)
	_last = now
	return false

func _run() -> void:
	var a := OS.get_cmdline_user_args()
	var classes: Array = Array((a[1] if a.size() > 1 and not a[1].begins_with("--") else "plague,demon,archer").split(","))
	var rounds: int = int(a[2]) if a.size() > 2 and not a[2].begins_with("--") else 3
	var top: int = int(a[3]) if a.size() > 3 and not a[3].begins_with("--") else 40
	while g.world == null or g._busy or g._intro_playing:
		g._intro_skip = true
		await process_frame
	await g.start_game(false, "knight")
	while g._busy:
		await process_frame
	await g.load_zone(0, "sandbox", "start")
	while g._busy:
		await process_frame
	await SkillWarm.run(g, classes)
	Sfx.set_muted(true)
	var origin: Vector3 = g.hero.global_position + Vector3(0, 0, -3)
	var stats := {}          # "cls s/e" -> [call ms...], [frame ms...]
	for cls in classes:
		var p := Hero.new()
		p.puppet = true
		p.peer_id = 80
		p.name = "Bench_" + str(cls)
		g.add_child(p)
		p.setup(g)
		p.set_class(cls)
		p.global_position = origin
		p.net_pos = origin
		p.net_st = {"move": 0.0, "atk": -1.0, "style": "over", "block": 0.0, "hit": 0.0}
		p.net_has = true
		for i in 10:
			await process_frame
		for r in rounds:
			for w in SkillWarmData.EVENTS.get(cls, []):
				if not (w is Dictionary):
					continue
				var key := "%s %s/%s" % [cls, w.get("s", ""), w.get("e", "")]
				await process_frame
				dt = 0.0
				var t0 := Time.get_ticks_usec()
				SkillFx.play(p, SkillWarm._rebuild(w, origin))
				var ms := (Time.get_ticks_usec() - t0) / 1000.0
				for i in 3:
					await process_frame
				if not stats.has(key):
					stats[key] = [[], []]
				stats[key][0].append(ms)
				stats[key][1].append(dt)
			if cls == "plague" and p.pd != null:
				for ev in Array(SkillWarmData.PLAGUE) + SkillWarm.PLAGUE_TAIL:
					var key := "plague pd " + str(ev).split("|")[0]
					await process_frame
					dt = 0.0
					var t0 := Time.get_ticks_usec()
					p.pd.remote(SkillWarm._pd_rebuild(str(ev), origin))
					var ms := (Time.get_ticks_usec() - t0) / 1000.0
					for i in 3:
						await process_frame
					if not stats.has(key):
						stats[key] = [[], []]
					stats[key][0].append(ms)
					stats[key][1].append(dt)
			# let the round play out and clear it
			for i in 90:
				await process_frame
			SkillFx.clear(p)
			if p.pd != null:
				p.pd.clear()
			for c in g.world.fx_root.get_children():
				c.queue_free()
			for i in 5:
				await process_frame
		p.queue_free()
	var rows: Array = []
	for k in stats:
		var c: Array = stats[k][0].duplicate()
		c.sort()
		var f: Array = stats[k][1].duplicate()
		f.sort()
		# rounds after the first (the first may still hit the driver's pipeline compiles)
		var later: Array = (stats[k][0] as Array).slice(1) if rounds > 1 else stats[k][0]
		later.sort()
		rows.append([later[later.size() / 2], c[c.size() - 1], f[f.size() - 1], k, (stats[k][0] as Array)[0]])
	rows.sort_custom(func(x, y): return x[0] > y[0])
	print("[B] event: median call ms (rounds 2+), first round ms, worst call ms, worst frame ms")
	for i in mini(top, rows.size()):
		var row: Array = rows[i]
		print("[B] %-34s %6.1f  first %6.1f  worst %6.1f  frame %6.1f" % [row[3], row[0], row[4], row[1], row[2]])
	quit()
