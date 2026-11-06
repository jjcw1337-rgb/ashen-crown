extends SceneTree
## Triage 2026-11-04: "Trying to call an RPC via a multiplayer peer which is not connected" (5a186a1ced052d71): while
## a raid join waited up to 8 s for a server that didn't answer, the loading screen was up but the camp behind it
## still took keys, so the Plague Doctor's skills sent their effects down the link still connecting. This joins a
## port nobody listens on, presses the skill keys and the right mouse behind the loading screen, and reads this
## process's log for the error; the hero mustn't have cast anything either.
## Usage: godot --headless --path . -s tools/nightly_join_wait_test.gd
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
	print("[J] %s ok=%s%s" % [name, ok, "" if ok else "  FAIL"])
	if not ok:
		fails += 1

func _press(ev: InputEvent) -> void:
	Input.parse_input_event(ev)
	await process_frame
	var up: InputEvent = ev.duplicate()
	up.pressed = false
	Input.parse_input_event(up)
	await process_frame

func _run() -> void:
	while g.world == null or g._busy or g._intro_playing:
		g._intro_skip = true
		await process_frame
	await g.start_game(false, "plague")
	g.ui.close_all()
	for k in 30:
		await process_frame
	var start := _log_size()
	# what Game.start_battlegrounds does: the loading screen up, then the join, then up to 8 s for an answer
	g.bg_mode = true
	g.loading.visible = true
	_check("join started", g.net.join("127.0.0.1", 24599) == OK)
	var sent0: int = g.net.fx_sent
	var mana0: float = g.hero.mana
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 4000:
		for k in [KEY_Q, KEY_E, KEY_R, KEY_F]:
			var ev := InputEventKey.new()
			ev.keycode = k
			ev.pressed = true
			await _press(ev)
		var mb := InputEventMouseButton.new()
		mb.button_index = MOUSE_BUTTON_RIGHT
		mb.pressed = true
		mb.position = Vector2(500, 300)
		await _press(mb)
		for f in 20:
			await process_frame
	_check("still connecting (no server)", g.net.peer != null and g.net.peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTING)
	_check("nothing cast behind the loading screen (mana %.0f -> %.0f)" % [mana0, g.hero.mana], g.hero.mana >= mana0 - 0.01 and g.net.fx_sent == sent0)
	g.net.shutdown()
	g.loading.visible = false
	g.bg_mode = false
	var n := _log_since(start).count("not connected")
	_check("no RPC down the unconnected link (%d)" % n, n == 0)
	print("[J] done fails=%d" % fails)
	quit(1 if fails > 0 else 0)
