extends SceneTree
## Day and night in Act I's camp (DayNight): the same view at hours through the day, as one contact sheet
## (daynight_<view>.jpg), plus the cycle's checks: the light swings round and climbs and sinks with the hour, the
## lanterns go out by day, the moon takes over at night. Needs a display. Prints [D] lines.
## Usage: godot --path . -s tools/_late.gd -- res://tools/daynight_shots.gd outdir
var g
var out := ""
const HOURS := [3.0, 6.3, 8.0, 10.5, 13.0, 16.0, 18.4, 19.3, 20.4, 21.5, 23.0, 1.0]

func _initialize():
	for a in OS.get_cmdline_user_args():
		if not a.begins_with("res://"):
			out = a
	g = (load("res://main.tscn") as PackedScene).instantiate()
	get_root().add_child(g)
	_run()

func _frame() -> Image:
	for i in 4:
		await process_frame
	return get_root().get_texture().get_image()

func _sheet(frames: Array, name: String, cols := 4, w := 480) -> void:
	var f0: Image = frames[0]
	var h := int(w * f0.get_height() / float(f0.get_width()))
	var rows := int(ceil(frames.size() / float(cols)))
	var sheet := Image.create(w * cols, h * rows, false, Image.FORMAT_RGB8)
	for i in frames.size():
		var im: Image = (frames[i] as Image).duplicate()
		im.convert(Image.FORMAT_RGB8)
		im.resize(w, h, Image.INTERPOLATE_LANCZOS)
		sheet.blit_rect(im, Rect2i(0, 0, w, h), Vector2i((i % cols) * w, (i / cols) * h))
	sheet.save_jpg(out + "/" + name + ".jpg", 0.88)
	print("[D] ", name)

func _run() -> void:
	while g.world == null or g._busy or g._intro_playing:
		g._intro_skip = true
		await process_frame
	await g.start_game(false, "knight")
	g.ui.close_all()
	while g._busy:
		await process_frame
	var dn: DayNight = g.day_night
	print("[D] %s the cycle runs in the camp" % ("ok  " if dn.on else "FAIL"))
	g.ui.root.visible = false
	# the game's own camera by the bonfire, then a wider look over the camp
	g.hero.global_position = g.world.free_spot_near(Vector3(1.5, 0, 0.5), 0.4)
	var frames := []
	var dirs := {}
	for h in HOURS:
		dn.fixed = h
		await create_timer(0.6).timeout
		frames.append(await _frame())
		dirs[h] = -g.sun.global_basis.z
		print("[D] %05.2f %s light %.2f lamps %.2f night %.2f dir %s" % [h, "moon" if dn.moon_up else "sun ", g.sun.light_energy, g.lamp_mul, dn.night, str(dirs[h])])
	await _sheet(frames, "daynight_game")
	var cam: Camera3D = g.get_viewport().get_camera_3d()
	g.set_process(false)
	frames = []
	for h in HOURS:
		dn.fixed = h
		dn.update(0.0)
		cam.global_transform = Transform3D(Basis(), Vector3(-14, 15, 18)).looking_at(Vector3(2, 0, -6))
		cam.fov = 55
		await create_timer(0.3).timeout
		frames.append(await _frame())
	await _sheet(frames, "daynight_wide")
	g.set_process(true)
	# checks: the sun comes up in the east and goes down in the west; noon's light is higher than the morning's
	var m: Vector3 = dirs[8.0]
	var e: Vector3 = dirs[18.4]
	var n: Vector3 = dirs[13.0]
	print("[D] %s morning light from the east, evening from the west" % ("ok  " if m.x < 0.0 and e.x > 0.0 else "FAIL"))
	print("[D] %s noon is higher than morning" % ("ok  " if -n.y > -m.y else "FAIL"))
	dn.fixed = 13.0
	dn.update(0.0)
	var lit_day := 0
	for c in get_nodes_in_group(DayNight.LAMP_GROUP):
		if (c as Node3D).visible:
			lit_day += 1
	dn.fixed = 23.0
	dn.update(0.0)
	await process_frame
	dn.update(0.0)
	var lit_night := 0
	for c in get_nodes_in_group(DayNight.LAMP_GROUP):
		if (c as Node3D).visible:
			lit_night += 1
	print("[D] %s lanterns out by day (%d lit), alight at night (%d)" % ["ok  " if lit_day == 0 and lit_night > 0 else "FAIL", lit_day, lit_night])
	print("[D] %s the moon at 23:00" % ("ok  " if dn.moon_up else "FAIL"))
	quit()
