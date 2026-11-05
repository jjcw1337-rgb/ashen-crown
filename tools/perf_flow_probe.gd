extends SceneTree
## Targeted audit of actual title/story/transition/UI flow. No gameplay optimization.
## Use _late.gd -- res://tools/perf_flow_probe.gd --out /absolute/result.json
## Requires an isolated user directory; screenshots are saved beside the JSON.
var g
var rows: Array = []
var samples: Array = []
var last_usec := 0
var output := ""

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	output = args[args.find("--out") + 1]
	seed(420042)
	BuildEnv.forced = {"env": "local", "cloud": "0", "nakama_url": "http://127.0.0.1:1"}
	last_usec = Time.get_ticks_usec()
	call_deferred("run")

func _process(_delta: float) -> bool:
	var now := Time.get_ticks_usec()
	samples.append((now - last_usec) / 1000.0)
	last_usec = now
	if is_instance_valid(g):
		g._intro_skip = true
	return false

func wait_frames(n: int) -> void:
	for i in n:
		await process_frame

func summarize(label: String, start: int) -> void:
	var sorted := samples.duplicate()
	sorted.sort()
	var row := {"label": label, "elapsed_ms": (Time.get_ticks_usec() - start) / 1000.0,
		"frames": sorted.size(), "max_frame_ms": sorted.back() if not sorted.is_empty() else 0,
		"over100": sorted.filter(func(x): return x >= 100.0).size(),
		"wall_frames_ms": samples.duplicate()}
	rows.append(row)
	print("[FLOW] ", label, " elapsed=", row.elapsed_ms, " max_frame=", row.max_frame_ms, " over100=", row.over100)

func step(label: String, action: Callable, settle_frames := 2) -> void:
	await process_frame
	samples.clear()
	last_usec = Time.get_ticks_usec()
	var start := last_usec
	await action.call()
	await wait_frames(settle_frames)
	summarize(label, start)

func shot(label: String) -> void:
	await RenderingServer.frame_post_draw
	get_root().get_texture().get_image().save_png(output.get_basename() + "-" + label + ".png")

func run() -> void:
	var start := Time.get_ticks_usec()
	samples.clear()
	g = (load("res://main.tscn") as PackedScene).instantiate()
	g.char_dir = "user://perf_flow_chars/"
	get_root().add_child(g)
	g.rng.seed = 420042
	g.set_sound(false)
	while g.world == null or g._busy or g._intro_playing or g._boot_hold or not g.ui.title_panel.visible:
		await process_frame
	summarize("boot_to_title", start)
	await step("title_idle_3s", func(): await create_timer(3.0).timeout)
	await step("title_idle_again_3s", func(): await create_timer(3.0).timeout)
	await shot("title")
	await step("new_knight_in_camp", func(): await g.start_game(false, "knight", "", "Perf Audit"))
	g.test_immortal = true
	for pass_i in 2:
		await step("character_window_%d" % pass_i, func(): g.ui.toggle(g.ui.char_panel), 20)
		g.ui.close_all()
		await wait_frames(5)
	for pass_i in 2:
		await step("camp_to_moor_%d" % pass_i, func(): await g.load_zone(0, "wild", "waypoint"))
		await step("moor_idle_2s_%d" % pass_i, func(): await create_timer(2.0).timeout)
		if pass_i == 0:
			await shot("moor")
		await step("moor_to_camp_%d" % pass_i, func(): await g.load_zone(0, "town", "waypoint"))
	var f := FileAccess.open(output, FileAccess.WRITE)
	f.store_string(JSON.stringify({"rows": rows, "viewport": str(get_root().get_visible_rect().size),
		"preset": g.quality, "user_dir": OS.get_user_data_dir(),
		"pipeline_cache": ProjectSettings.get_setting("rendering/rendering_device/pipeline_cache/enable")}, " "))
	f.close()
	SkillFx.clear(g.hero)
	g.queue_free()
	await wait_frames(8)
	quit()
