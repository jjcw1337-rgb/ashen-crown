extends SceneTree
## Day and night in Act I's camp (DayNight), headless: the cycle runs in the camp, the lanterns go out by day and
## light at night, the moon takes the light after dark, and the camp's bed turns to the night ambience (looping)
## after dark and back to the wind by day. Prints [N] lines.
## Usage: godot --headless --path . -s tools/_late.gd -- res://tools/daynight_test.gd
var g
var fails := 0

func _initialize():
	g = (load("res://main.tscn") as PackedScene).instantiate()
	get_root().add_child(g)
	_run()

func _ok(c: bool, what: String) -> void:
	print("[N] ", "ok   " if c else "FAIL ", what)
	if not c:
		fails += 1

func _lit() -> int:
	var n := 0
	for c in get_nodes_in_group(DayNight.LAMP_GROUP):
		if (c as Node3D).visible:
			n += 1
	return n

func _at(dn: DayNight, h: float) -> void:
	dn.fixed = h
	for i in 3:
		dn.update(0.0)
		await process_frame

func _run() -> void:
	while g.world == null or g._busy or g._intro_playing:
		g._intro_skip = true
		await process_frame
	await g.start_game(false, "knight")
	while g._busy:
		await process_frame
	var dn: DayNight = g.day_night
	_ok(dn != null and dn.on, "the cycle runs in the camp")
	await _at(dn, 13.0)
	_ok(not dn.moon_up and _lit() == 0, "noon: the sun, the lanterns out (%d lit)" % _lit())
	var bank: Dictionary = Sfx.bank
	_ok(bank.has("night_forest"), "the night ambience is in the sound bank")
	_ok(Sfx.ambience.stream != bank.get("night_forest", [null])[0], "by day the camp hears the wind, not the night")
	await _at(dn, 23.0)
	_ok(dn.moon_up and _lit() > 0, "23:00: the moon, the lanterns alight (%d lit)" % _lit())
	var st: AudioStream = bank.get("night_forest", [null])[0]
	_ok(st != null and Sfx.ambience.stream == st, "after dark the camp hears the night ambience")
	_ok(st is AudioStreamWAV and (st as AudioStreamWAV).loop_mode == AudioStreamWAV.LOOP_FORWARD, "... and it loops")
	await _at(dn, 7.0)
	_ok(Sfx.ambience.stream != st, "dawn: back to the wind")
	print("[N] done, %d failed" % fails)
	quit()
