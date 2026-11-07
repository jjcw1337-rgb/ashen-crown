extends SceneTree
## The chat line's neon (jj): Enter opens it lit, a TYPING tag over it, its border and glow sweeping green to blue;
## Enter (or Esc) fades it out and hides it. Shots of it green and blue into the folder given (default user://).
##   godot --path . --resolution 1280x720 -s tools/_late.gd -- res://game/ui/chat/tests/chat_neon_test.gd [out_dir]
var g
var fails := 0

func _initialize():
	BuildEnv.forced = {"env": "local", "cloud": "0"}
	g = (load("res://main.tscn") as PackedScene).instantiate()
	g.char_dir = "user://chat_neon_test/"
	g.old_save = "user://chat_neon_test/absent.json"
	get_root().add_child(g)
	current_scene = g
	_run()

func _process(_dt: float) -> bool:
	if is_instance_valid(g):
		g._intro_skip = true
	return false

func check(ok: bool, what: String) -> void:
	print("[NEON] ", "ok   " if ok else "FAIL ", what)
	if not ok:
		fails += 1

func frames(n: int) -> void:
	for i in n:
		await process_frame

func _shot(name: String) -> void:
	var dir: String = "user://"
	for a in OS.get_cmdline_user_args():
		if not str(a).begins_with("res://"):
			dir = str(a)
	await RenderingServer.frame_post_draw
	var img := get_root().get_texture().get_image()
	if img != null and not img.is_empty():
		img.save_png(dir.path_join(name))

func _run() -> void:
	while g.world == null or g._busy:
		await frames(5)
	await g.start_game(false, "knight")
	while g._busy:
		await frames(5)
	g.ui.close_all()
	var c: ChatBox = g.ui.chat
	c.allow_offline = true
	c.add("Blaine", "ready when you are", false)
	c.add("jj", "/t flank left, I've got the bear", true)
	await frames(10)
	var enter := InputEventKey.new()
	enter.keycode = KEY_ENTER
	enter.pressed = true
	Input.parse_input_event(enter)
	await frames(20)
	check(c.typing and c.input.visible and c.tag.visible and c.input.has_focus(), "Enter opens the line, focused, TYPING over it")
	var b0: Color = c.neon.border_color
	check(c.neon.border_width_top >= 2 and c.neon.shadow_size > 0 and b0.g > 0.6, "it's lit neon (border %s, glow %d)" % [b0.to_html(false), c.neon.shadow_size])
	c.input.text = "omw"
	await _shot("chat_neon_green.png")
	await frames(36)
	var b1: Color = c.neon.border_color
	check(b1.b > b0.b + 0.15, "and drifts to blue (%s -> %s)" % [b0.to_html(false), b1.to_html(false)])
	await _shot("chat_neon_blue.png")
	c.close()
	await frames(20)
	check(not c.typing and not c.input.visible and not c.tag.visible, "closing fades it out and hides it")
	print("[NEON] done, %d failed" % fails)
	quit(1 if fails else 0)
