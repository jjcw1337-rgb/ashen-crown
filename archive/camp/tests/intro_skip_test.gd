extends SceneTree
## The intro's skip (Game._is_skip_press, Game._input): volume/media keys, letters and modifiers never skip it;
## Esc / Space / Enter / a click / gamepad A need a second press within Game.INTRO_CONFIRM seconds.
var g
var fails := 0
func check(ok: bool, what: String) -> void:
	if not ok:
		fails += 1
	print("[I] " + ("ok   " if ok else "FAIL ") + what)
func key(k: Key) -> InputEventKey:
	var e := InputEventKey.new()
	e.keycode = k
	e.pressed = true
	return e
func click() -> InputEventMouseButton:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = true
	return e
func reset(t := 5.0) -> void:
	g._intro_playing = true
	g._intro_skip = false
	g._intro_armed = -100.0
	g._intro_t = t
func _initialize():
	g = (load("res://main.tscn") as PackedScene).instantiate()
	get_root().add_child(g)
	_run()
func _run() -> void:
	for i in 20:
		await process_frame
	reset()
	for k in [KEY_VOLUMEUP, KEY_VOLUMEDOWN, KEY_VOLUMEMUTE, KEY_MEDIAPLAY, KEY_A, KEY_SHIFT, KEY_F11, KEY_W]:
		g._input(key(k))
	check(not g._intro_skip and g._intro_armed < 0.0, "volume, media, letters and modifiers do nothing")
	g._input(key(KEY_SPACE))
	check(not g._intro_skip and g._intro_armed == 5.0, "one Space only asks to press again")
	g._intro_t = 6.0
	g._input(key(KEY_ESCAPE))
	check(g._intro_skip, "a second press within 3 s skips")
	reset()
	g._input(key(KEY_SPACE))
	g._intro_t = 5.0 + g.INTRO_CONFIRM + 0.5
	g._input(key(KEY_SPACE))
	check(not g._intro_skip, "a second press after the window only asks again")
	reset()
	g._input(click())
	g._input(click())
	check(g._intro_skip, "two clicks skip")
	reset(0.2)
	g._input(key(KEY_SPACE))
	g._input(key(KEY_SPACE))
	check(not g._intro_skip, "nothing skips in the first half second")
	g._intro_playing = false
	print("[I] done, %d failed" % fails)
	quit(1 if fails > 0 else 0)
