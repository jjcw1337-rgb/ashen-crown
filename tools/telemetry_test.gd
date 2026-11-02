extends SceneTree
## Telemetry and error reports (scripts/telemetry.gd) against a running Nakama:
##   godot --headless --path . -s tools/telemetry_test.gd -- cloud <nakama url> <server key>
## Signs in, makes an error (push_error: it reaches Godot's log, which the reporter reads), a crash left by a fake
## earlier session, and a performance sample, sends them, and prints the session id ("[T] session ...") so the rows
## can be looked up (tools/telemetry_query.sh). Without `cloud ...` it checks only what doesn't need the server.

var g
var fails := 0
var TM

func _initialize():
	var a := OS.get_cmdline_user_args()
	var ci := a.find("cloud")
	if ci >= 0 and ci + 2 < a.size():
		BuildEnv.forced = {"cloud": "1", "env": "staging", "nakama_url": a[ci + 1], "nakama_key": a[ci + 2]}
	g = (load("res://main.tscn") as PackedScene).instantiate()
	get_root().add_child(g)
	_run()

func check(ok: bool, what: String) -> void:
	if not ok:
		fails += 1
	print("[T] " + ("ok   " if ok else "FAIL ") + what)

func secs(t: float) -> void:
	var end := Time.get_ticks_msec() + int(t * 1000.0)
	while Time.get_ticks_msec() < end:
		await process_frame

func _run() -> void:
	TM = load("res://scripts/telemetry.gd")
	await secs(1.0)
	while g._busy:
		await process_frame
	g.start_game(false)
	await secs(1.0)
	while g._busy:
		await process_frame
	check(not TM.wanted(), "off in tools and tests")
	# a crash left by an earlier session: its run file still says running, its log is the newest rotated one
	var f := FileAccess.open(TM.RUN_FILE, FileAccess.WRITE)
	f.store_string(JSON.stringify({"running": true, "session": "testcrash", "context": {"zone": "wild", "class": "knight"},
		"crumbs": [{"k": "enter", "to": "wild"}]}))
	f.close()
	DirAccess.make_dir_recursive_absolute("user://logs")
	var lf := FileAccess.open("user://logs/godot9999-12-31T23.59.59.log", FileAccess.WRITE)
	lf.store_string("line one\nERROR: something broke before the crash\n   at: test (res://x.gd:1)\nhandle_crash: Program crashed with signal 11\n")
	lf.close()
	var t = TM.new(g)
	g.add_child(t)
	await secs(0.2)
	check(t.errors.size() == 1 and t.errors[0]["kind"] == "crash" and str(t.errors[0]["tail"]).contains("signal 11"), "a session that didn't end is reported as a crash, with its log's end")
	check(t.errors[0]["crumbs"].size() == 1 and t.errors[0]["context"].get("zone", "") == "wild", "with where it was and what it did")
	DirAccess.remove_absolute("user://logs/godot9999-12-31T23.59.59.log")
	# an error in this session, twice: one issue, counted
	TM.crumb("boss", {"kind": "test"})
	push_error("telemetry test error 1234")
	push_error("telemetry test error 5678")
	await secs(0.5)
	t._read_log()
	var mine: Array = t.errors.filter(func(e): return str(e["message"]).contains("telemetry test error"))
	check(mine.size() == 1 and int(mine[0]["count"]) == 2, "an error from the log, fingerprinted: one issue, counted twice (%d)" % (mine[0]["count"] if mine.size() else 0))
	check(mine.size() == 1 and mine[0]["crumbs"].back()["k"] == "boss" and mine[0]["context"].has("gpu"), "with the breadcrumbs and the PC")
	# the log read while the engine is still writing: half a line, or an error whose "at:" isn't there yet, waits
	var wl := func(s: String) -> int: return TM.whole_lines(s.to_utf8_buffer())
	check(wl.call("a\nb\n") == 4 and wl.call("a\nb") == 2 and wl.call("half") == 0, "the log is read in whole lines")
	check(wl.call("a\nERROR: x\n") == 2 and wl.call("ERROR: x\n") == 0 and wl.call("ERROR: x\n   at: f (a.h:1)\n") == 26,
		"an error waits for its at: line")
	# a performance sample
	t.frames.clear()
	for i in 120:
		t.frames.append(16.0 if i % 40 else 120.0)
	t.window_t = 2.0
	t._sample()
	check(t.samples.size() == 1 and t.samples[0]["hitches"] == 3 and t.samples[0].has("zone"), "a performance sample (hitches %d)" % (t.samples[0]["hitches"] if t.samples.size() else -1))
	print("[T] session ", t.session)
	if BuildEnv.cloud():
		g.cloud = load("res://scripts/cloud_saves.gd").new(g)
		g.add_child(g.cloud)
		await t._flush()
		check(t.errors.is_empty() and t.samples.is_empty(), "sent to Nakama (the queues are empty)")
	FileAccess.open(TM.RUN_FILE, FileAccess.WRITE).store_string("{}")
	print("[T] done, %d failed" % fails)
	quit()
