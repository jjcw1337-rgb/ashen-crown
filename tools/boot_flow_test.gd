extends SceneTree
## The real start (Blaine, 2026-11-06: no camp built behind the title): boot -> title with no world, how long it
## took and its worst frame; then Sandbox solo from the title and back; a character's world and back; the title
## always comes back with no world. Run with the real renderer:
##   godot --path . -s tools/boot_flow_test.gd -- --real-boot
var g
var fails := 0
var worst := 0
var last := 0
var measuring := false

func _initialize() -> void:
	BuildEnv.forced = {"env": "local", "cloud": "0"}
	g = load("res://main.tscn").instantiate()
	g.char_dir = "user://boot_flow_test/"
	g.old_save = g.char_dir + "absent.json"
	root.add_child(g)
	current_scene = g
	_run()

func check(ok: bool, text: String) -> void:
	print("[BOOT] ", "ok   " if ok else "FAIL ", text)
	if not ok:
		fails += 1

func _process(_dt: float) -> bool:
	var now := Time.get_ticks_usec()
	if measuring and last > 0:
		worst = maxi(worst, now - last)
	last = now
	if is_instance_valid(g):
		g._intro_skip = true
	return false

func _title_up() -> bool:
	return not g._busy and not g._intro_playing and g.ui.title_panel.visible

func _wait(cond: Callable, secs: float) -> bool:
	var t0 := Time.get_ticks_msec()
	while not cond.call():
		if Time.get_ticks_msec() - t0 > int(secs * 1000.0):
			return false
		await process_frame
	return true

func _run() -> void:
	var t0 := Time.get_ticks_msec()
	while g._intro_playing or not g.is_node_ready():
		await process_frame
	var after_intro := Time.get_ticks_msec()
	measuring = true
	check(await _wait(_title_up, 30.0), "the title comes up")
	measuring = false
	print("[BOOT] intro end -> title %d ms, worst frame %d ms (boot total %d ms)" % [
		Time.get_ticks_msec() - after_intro, worst / 1000, Time.get_ticks_msec() - t0])
	check(g.world == null, "no world is built behind the title")
	check(worst < 200000, "no long freeze between the intro and the title (worst %d ms)" % (worst / 1000))
	# Sandbox solo from the title, and back
	await g.open_sandbox("archer")
	check(g.world != null and g.cur_zone == Sandbox.ZONE, "Sandbox solo loads its own zone from the title")
	await g.close_sandbox()
	check(await _wait(_title_up, 30.0) and g.world == null, "leaving Sandbox returns to the title with no world")
	# a character's world, and back
	await g.start_game(false, "knight", "", "Bootflow")
	check(g.world != null and g.cur_zone == "town" and g.playing, "Enter World builds the camp")
	await g.exit_to_title()
	check(await _wait(_title_up, 30.0) and g.world == null, "back to the title: the world is gone")
	g.delete_character(g.list_characters()[0]["id"]) if not g.list_characters().is_empty() else null
	print("[BOOT] done, %d failed" % fails)
	g.queue_free()
	for i in 8:
		await process_frame
	quit(1 if fails else 0)
