extends SceneTree
## WASD steering: the heading swings round toward the keys instead of snapping (Hero._steer). Prints [W] lines.
var g

func _initialize():
	g = (load("res://main.tscn") as PackedScene).instantiate()
	get_root().add_child(g)
	_run()

func _keys(down: Array) -> void:
	for k in [KEY_W, KEY_A, KEY_S, KEY_D]:
		var ev := InputEventKey.new()
		ev.keycode = k
		ev.physical_keycode = k
		ev.pressed = k in down
		Input.parse_input_event(ev)

func _yaw() -> int:
	return int(round(rad_to_deg(g.hero.rig.rotation.y)))

func _run() -> void:
	while g.world == null or g._busy:
		g._intro_skip = true
		await process_frame
	await g.start_game(false, "knight")
	await g.load_zone(0, "town", "start")
	for i in 10:
		await process_frame
	var h = g.hero
	h.rig.rotation.y = 0.0
	var seq := []
	# W for a bit, then W+A: the facing should pass through the angles in between
	_keys([KEY_W])
	for i in 20:
		await process_frame
	seq.append(_yaw())
	_keys([KEY_W, KEY_A])
	for i in 30:
		await process_frame
		seq.append(_yaw())
	var steps := {}
	for a in seq:
		steps[a] = true
	print("[W] facing while turning from W to W+A: ", seq.slice(0, 12), " ... ", seq[-1], "; distinct angles ", steps.size())
	# a full reversal swings round rather than flipping
	var rev := []
	_keys([KEY_S, KEY_D])
	for i in 20:
		await process_frame
		rev.append(_yaw())
	print("[W] reversing: ", rev.slice(0, 10), " ... ", rev[-1])
	_keys([])
	quit()
