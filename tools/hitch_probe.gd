extends SceneTree
## Frame-time capture for hitches (Blaine, 2026-11-05: "the game lags a lot like on the title screen ... and when some
## abilities are firing"). Records every frame's wall time and prints the worst frames, with what was happening.
##   godot --path . -s tools/_late.gd -- res://tools/hitch_probe.gd title [secs 20]
##   godot --path . -s tools/_late.gd -- res://tools/hitch_probe.gd skills <class> [nowarm]
##   godot --path . -s tools/_late.gd -- res://tools/hitch_probe.gd camp [secs 20]
## (a display is needed: it measures the real renderer). Lines: [H] ...

var g
var frames: Array = []       # [t_ms, dt_ms, label]
var label := "boot"
var _last := 0

func _initialize():
	g = (load("res://main.tscn") as PackedScene).instantiate()
	get_root().add_child(g)
	_last = Time.get_ticks_usec()
	_run()

func _process(_d: float) -> bool:
	var now := Time.get_ticks_usec()
	frames.append([now / 1000.0, (now - _last) / 1000.0, label])
	_last = now
	return false

func wait(s: float) -> void:
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < int(s * 1000.0):
		await process_frame

func report(from_i: int, title: String) -> void:
	var fs := frames.slice(from_i)
	var dts: Array = fs.map(func(f): return float(f[1]))
	dts.sort()
	var n := dts.size()
	if n == 0:
		return
	var tot := 0.0
	for d in dts:
		tot += d
	print("[H] %s: %d frames, mean %.1f ms, p50 %.1f, p95 %.1f, p99 %.1f, worst %.1f ms; frames over 50 ms: %d, over 100 ms: %d" % [title, n, tot / n,
		dts[n / 2], dts[int(n * 0.95)], dts[mini(n - 1, int(n * 0.99))], dts[n - 1], dts.filter(func(d): return d > 50.0).size(), dts.filter(func(d): return d > 100.0).size()])
	var worst := fs.duplicate()
	worst.sort_custom(func(a, b): return a[1] > b[1])
	for i in mini(8, worst.size()):
		print("[H]    %.0f ms at %.1f s  (%s)" % [worst[i][1], (worst[i][0] - frames[0][0]) / 1000.0, worst[i][2]])

func _run() -> void:
	var a := OS.get_cmdline_user_args()
	var mode: String = a[1] if a.size() > 1 else "title"
	if mode == "title":
		var secs: float = float(a[2]) if a.size() > 2 else 20.0
		label = "boot to title"
		while g.world == null or g._busy:
			g._intro_skip = true
			await process_frame
		var i0 := frames.size()
		label = "title idle"
		await wait(secs * 0.5)
		# hover the two cards (the dais light, the camera lean, the puppet's signature move)
		label = "title hover"
		var vp := get_root().get_visible_rect().size
		for k in 6:
			var ev := InputEventMouseMotion.new()
			ev.position = Vector2(vp.x * (0.3 if k % 2 == 0 else 0.7), vp.y * 0.75)
			get_root().push_input(ev)
			await wait(secs * 0.08)
		report(0, "boot (to the title)")
		report(i0, "the title screen")
	elif mode == "camp":
		var secs: float = float(a[2]) if a.size() > 2 else 20.0
		label = "boot"
		while g.world == null or g._busy or g._intro_playing:
			g._intro_skip = true
			await process_frame
		label = "start_game"
		await g.start_game(false, "knight")
		while g._busy:
			await process_frame
		var i0 := frames.size()
		label = "camp idle"
		await wait(secs * 0.4)
		label = "camp walking"
		g.hero.global_position = Vector3(0, 0, 8)
		await wait(secs * 0.6)
		report(i0, "the camp")
	elif mode == "skills":
		var cls: String = a[2] if a.size() > 2 else "knight"
		label = "boot"
		while g.world == null or g._busy or g._intro_playing:
			g._intro_skip = true
			await process_frame
		label = "start_game " + cls
		await g.start_game(false, cls)
		while g._busy:
			await process_frame
		g.test_immortal = true
		g.test_allskills = true
		g.hero.mana = 9999.0
		await wait(1.0)
		var i0 := frames.size()
		var ids: Array = Data.skills_for(cls).map(func(s): return s["id"])
		ids = ["attack"] + ids
		var twice: Array = []
		for id in ids:
			twice.append(id)
			twice.append(id)
		for id in twice:
			label = "cast " + str(id)
			print("[H] >>> cast %s at %d" % [id, Time.get_ticks_msec()])
			g.hero.mana = 9999.0
			for k in g.hero.cds.keys():
				g.hero.cds[k] = 0.0
			var aim: Vector3 = g.hero.global_position + Vector3(0, 0, -4)
			var tc := Time.get_ticks_usec()
			if str(id) == "attack":
				g.hero.swipe_attack(aim)
			else:
				g.hero.use_skill(str(id), aim)
			var call_ms := (Time.get_ticks_usec() - tc) / 1000.0
			# the frames after: script time (process) vs the renderer's (frame setup + GPU)
			var worst_proc := 0.0
			var worst_rcpu := 0.0
			var worst_gpu := 0.0
			var vp := get_root().get_viewport_rid()
			RenderingServer.viewport_set_measure_render_time(vp, true)
			var t1 := Time.get_ticks_msec()
			while Time.get_ticks_msec() - t1 < 2200:
				await process_frame
				worst_proc = maxf(worst_proc, Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0)
				worst_rcpu = maxf(worst_rcpu, RenderingServer.viewport_get_measured_render_time_cpu(vp) + RenderingServer.get_frame_setup_time_cpu())
				worst_gpu = maxf(worst_gpu, RenderingServer.viewport_get_measured_render_time_gpu(vp))
			var fw := frames.slice(frames.size() - 140).map(func(f): return float(f[1]))
			fw.sort()
			print("[H]     %s: worst frame %.0f ms; the cast call %.0f ms; after it, worst process %.0f ms, render cpu %.0f ms, gpu %.0f ms" % [id, fw[fw.size() - 1], call_ms, worst_proc, worst_rcpu, worst_gpu])
		report(i0, "first casts, " + cls)
	quit()
