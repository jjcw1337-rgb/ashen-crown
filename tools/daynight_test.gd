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
	_ok(not (bank.get("night_forest", []) as Array).has(Sfx.ambience.stream), "by day the camp hears the wind, not the night")
	await _at(dn, 23.0)
	_ok(dn.moon_up and _lit() > 0, "23:00: the moon, the lanterns alight (%d lit)" % _lit())
	var beds: Array = bank.get("night_forest", [])
	var st: AudioStream = beds[dn.night_take()] if not beds.is_empty() else null
	_ok(st != null and Sfx.ambience.stream == st, "after dark the camp hears tonight's night ambience (%d)" % (dn.night_take() + 1))
	var loops := beds.size() > 0
	for b in beds:
		loops = loops and b is AudioStreamWAV and (b as AudioStreamWAV).loop_mode == AudioStreamWAV.LOOP_FORWARD
	_ok(loops, "... and every night's bed loops")
	await _at(dn, 7.0)
	_ok(not beds.has(Sfx.ambience.stream), "dawn: back to the wind")
	# the admin panel's time of day (the Escape menu's Admin column), pressed under the pause menu
	dn.live()
	g.dev_tools = true
	g.toggle_pause()
	var btns := {}
	for b in g.ui.test_panel.find_children("*", "Button", true, false):
		btns[(b as Button).text] = b
	_ok(btns.has("Midnight") and btns.has("Noon") and btns.has("Fast 30x") and btns.has("Live clock"), "the admin panel has the time of day")
	(btns["Midnight"] as Button).pressed.emit()
	await create_timer(0.3).timeout
	_ok(dn.fixed == 0.0 and dn.pace == 0.0 and dn.moon_up and _lit() > 0, "Midnight: held at 00:00 under the pause menu, the moon up")
	(btns["Noon"] as Button).pressed.emit()
	await create_timer(0.3).timeout
	_ok(absf(dn.hour - 13.0) < 0.01 and not dn.moon_up and _lit() == 0, "Noon: the sun, the lanterns out")
	(btns["Fast 30x"] as Button).pressed.emit()
	await create_timer(1.0).timeout
	_ok(dn.pace == 30.0 and dn.hour > 13.2, "Fast 30x runs the day on (%.2f after 1 s)" % dn.hour)
	var sl: HSlider = g.ui.test_panel.find_children("*", "HSlider", true, false)[0]
	_ok(absf(sl.value - dn.hour) < 0.5, "the slider follows the hour")
	sl.value = 21.0
	await create_timer(0.1).timeout
	_ok(absf(dn.hour - 21.0) < 0.2, "dragging the slider sets the hour (%.2f)" % dn.hour)
	(btns["Hold"] as Button).pressed.emit()
	var h0 := dn.hour
	await create_timer(0.5).timeout
	_ok(dn.pace == 0.0 and absf(dn.hour - h0) < 0.001, "Hold stops it")
	(btns["Live clock"] as Button).pressed.emit()
	await create_timer(0.2).timeout
	var wall := fposmod(Time.get_unix_time_from_system() / DayNight.DAY_LEN * 24.0, 24.0)
	_ok(dn.fixed < 0.0 and absf(dn.hour - wall) < 0.05, "Live clock: back to everyone's hour")
	# five unique nights in turn: consecutive nights get different beds, the same night the same one on every game
	var takes: Array = bank.get("night_forest", [])
	_ok(takes.size() == 5, "five night beds (%d)" % takes.size())
	var seen := {}
	for i in takes.size():
		dn.night_shift = i
		seen[dn.night_take()] = true
	dn.night_shift = 0
	_ok(seen.size() == takes.size(), "each night in turn has its own (%d of %d)" % [seen.size(), takes.size()])
	_ok(dn.night_take() == posmod(int(floor((Time.get_unix_time_from_system() / DayNight.DAY_LEN * 24.0 - DayNight.SUNSET) / 24.0)), takes.size()),
		"tonight's is the wall clock's (the same for a whole party)")
	(btns["Midnight"] as Button).pressed.emit()
	await create_timer(0.3).timeout
	var bed0: AudioStream = Sfx.ambience.stream
	(btns["Next night's sounds"] as Button).pressed.emit()
	await create_timer(0.2).timeout
	_ok(Sfx.ambience.stream != bed0 and takes.has(Sfx.ambience.stream), "Next night's sounds plays the next bed")
	dn.night_shift = 0
	(btns["Live clock"] as Button).pressed.emit()
	g.toggle_pause()
	# the HUD clock: shown in the camp
	await create_timer(0.4).timeout
	_ok(g.ui.day_clock != null and g.ui.day_clock.visible, "the HUD clock shows the camp's hour")
	print("[N] done, %d failed" % fails)
	quit()
