extends SceneTree
## Triage 2026-11-04: a raid's antechamber chest opening (Battlegrounds.stash_fx, which every game plays) logged
## "Lambda capture at index 0 was freed" on every client 4.7 s later (2 players): a timer lambda kept the opening's
## smoke, which had already freed itself. This opens a chest the way a client does, lets every timer run out, opens
## a second one and has the gates rise under it (close_stashes frees the chest's fire and loop while their timers
## wait), then reads this process's log for the error.
## Usage: godot --headless --path . -s tools/nightly_stash_fx_test.gd
var g
var fails := 0

func _initialize():
	g = (load("res://main.tscn") as PackedScene).instantiate()
	get_root().add_child(g)
	_run()

func _log_size() -> int:
	var f := FileAccess.open("user://logs/godot.log", FileAccess.READ)
	return f.get_length() if f != null else 0

func _log_since(at: int) -> String:
	var f := FileAccess.open("user://logs/godot.log", FileAccess.READ)
	if f == null:
		return ""
	f.seek(mini(at, f.get_length()))
	return f.get_buffer(f.get_length() - f.get_position()).get_string_from_utf8()

func _check(name: String, ok: bool) -> void:
	print("[S] %s ok=%s%s" % [name, ok, "" if ok else "  FAIL"])
	if not ok:
		fails += 1

func _wait(secs: float) -> void:
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < int(secs * 1000.0):
		await process_frame

func _run() -> void:
	while g.world == null or g._busy or g._intro_playing:
		g._intro_skip = true
		await process_frame
	await g.start_game(false, "knight")
	g.ui.close_all()
	var BG = load("res://scripts/battlegrounds.gd")
	await g.load_zone(0, BG.ZONE, "start")
	while g._busy:
		await process_frame
	g.bg_mode = true
	g.bg_raid = {"state": "prep:17", "t": 60.0, "open": [], "len": 1200.0, "portals_at": 300.0, "wait": 17.0}
	var chests: Array = []
	for it in g.world.interactables:
		if is_instance_valid(it) and it.kind == "stash" and it.data.get("raid", false):
			chests.append(it)
	_check("raid chests found (%d)" % chests.size(), chests.size() >= 2)
	if chests.size() < 2:
		_finish()
		return
	var start := _log_size()
	# 1: one opens and burns on; every timer of the opening runs out (the smoke's last at 4.7 s)
	var a = chests[0]
	g.chest_lid(a, true, false)
	BG.stash_fx(g, g.world.interactables.find(a))
	await _wait(6.0)
	_check("opening: fire burning on", a.get_node_or_null("stash_fire") != null)
	# 2: another opens and the gates rise 0.3 s later, under its timers (fire 0.8 s, loop 1.6 s)
	var b = chests[1]
	g.chest_lid(b, true, false)
	BG.stash_fx(g, g.world.interactables.find(b))
	await _wait(0.3)
	BG.close_stashes(g)
	await _wait(5.0)
	_check("gates rose: chest fire gone", b.get_node_or_null("stash_fire") == null and a.get_node_or_null("stash_fire") == null)
	var txt := _log_since(start)
	var n := txt.count("Lambda capture")
	_check("no 'Lambda capture ... freed' in the log (%d)" % n, n == 0)
	_finish()

func _finish() -> void:
	print("[S] done fails=%d" % fails)
	quit(1 if fails > 0 else 0)
