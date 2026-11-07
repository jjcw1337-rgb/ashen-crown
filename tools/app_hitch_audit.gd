extends SceneTree
## The rest of the game's first-time costs (Blaine, 2026-11-05: "is that a universal thing ... make sure the whole app
## is properly cached, preloaded"): after the skill-effect fixes, what still freezes a frame the first time it happens.
## Camp -> each window opened twice -> loot of every rarity -> the Verdant Reach -> monster kinds spawned cold in
## view. Prints the worst frame of each step (first time and second time). Needs a display.
##   godot --path . -s tools/_late.gd -- res://tools/app_hitch_audit.gd [--monsters-only]
## Lines: [A] ...

var g
var _last := 0
var worst := 0.0
var rows: Array = []

func _initialize():
	g = (load("res://main.tscn") as PackedScene).instantiate()
	get_root().add_child(g)
	_last = Time.get_ticks_usec()
	_run()

func _process(_d: float) -> bool:
	var now := Time.get_ticks_usec()
	worst = maxf(worst, (now - _last) / 1000.0)
	_last = now
	return false

func frames(n: int) -> void:
	for i in n:
		await process_frame

## Worst frame (and the call's own time) of doing `f`, then `n` frames after it.
func step(what: String, f: Callable, n := 20) -> void:
	await process_frame
	worst = 0.0
	var t0 := Time.get_ticks_usec()
	await f.call()
	var ms := (Time.get_ticks_usec() - t0) / 1000.0
	await frames(n)
	rows.append([what, ms, worst])
	print("[A] %-38s call %7.1f ms   worst frame %7.1f ms" % [what, ms, worst])

func _zone(zone: String) -> void:
	await g.load_zone(0, zone, "waypoint")
	while g._busy:
		await process_frame

var _parked := 0

func _spawn_in_view(kind: String) -> void:
	var c: Vector3 = g.hero.global_position
	var e = null
	await step("spawn %s in %s" % [kind, g.cur_zone], func(): e = g.spawn_enemy(kind, c + Vector3(0, 0, -6), 1), 15)
	if e != null and is_instance_valid(e):
		e.global_position = c + Vector3(0, 0, 900.0 + _parked * 6.0)
		e.process_mode = Node.PROCESS_MODE_DISABLED
		_parked += 1

func _run() -> void:
	var a := OS.get_cmdline_user_args()
	while g.world == null or g._busy or g._intro_playing:
		g._intro_skip = true
		await process_frame
	await g.start_game(false, "knight")
	while g._busy:
		await process_frame
	g.test_immortal = true
	Sfx.set_muted(true)
	await frames(30)
	var ui = g.ui
	if not a.has("--monsters-only"):
		await step("the hall: 2 s after arriving", func(): await frames(1), 120)
		for pass_i in 2:
			var tag := " (first)" if pass_i == 0 else " (again)"
			for p in [["inventory", ui.inv_panel], ["character sheet", ui.char_panel], ["skills", ui.skills_panel],
					["talents", ui.talent_panel]]:
				await step("window " + str(p[0]) + tag, func(): ui.toggle(p[1]))
				ui.close_all()
				await frames(5)
			await frames(5)
			await step("pause menu" + tag, func(): g.toggle_pause())
			g.toggle_pause()
			await frames(5)
		var at: Vector3 = g.hero.global_position + Vector3(0, 0, -2.5)
		for pass_i in 2:
			var tag := " (first)" if pass_i == 0 else " (again)"
			for r in [0, 1, 2]:
				await step("loot drop rarity %d%s" % [r, tag], func():
					var it := Items.random_drop(5, 0.0, g.rng, false)
					it["rarity"] = r
					g.drop_item(it, at))
			await step("loot drop boss roll" + tag, func(): g.drop_item(Items.random_drop(20, 800.0, g.rng, true), at))
			await step("gold drop" + tag, func(): g.drop_item(Items.gold(50), at))
			await step("potion drop" + tag, func(): g.drop_item(Items.potion("hp_potion"), at))
			for c in g.world.items_root.get_children():
				c.queue_free()
			await frames(5)
		await step("travel the hall -> Verdant Reach (whole load)", func(): await _zone("bg"), 1)
		await step("forest: 2 s after arriving", func(): await frames(1), 120)
	else:
		await _zone("bg")
		await frames(60)
	# the monsters that turn up after the loading screen (MonsterWarm warms these)
	await _spawn_in_view("grabber")
	for k in ["bandit", "bandit_archer", "lion", "gladiator", "champion"]:
		await _spawn_in_view(k)
	# every kind cold (the first of its kind this session), in the forest: what isn't warmed anywhere
	if a.has("--all-monsters"):
		for kind in Data.ENEMIES.keys():
			if not ["goblin_king", "champion"].has(kind):
				await _spawn_in_view(str(kind))
	rows.sort_custom(func(x, y): return x[2] > y[2])
	print("[A] ---- slowest steps (worst frame)")
	for i in mini(30, rows.size()):
		print("[A] %-38s worst frame %7.1f ms (call %.1f)" % [rows[i][0], rows[i][2], rows[i][1]])
	quit()
