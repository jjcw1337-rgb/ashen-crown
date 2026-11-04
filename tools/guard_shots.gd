extends SceneTree
## Screenshots of the Act I camp's guards (CampGuard), saved as contact sheets: each guard close up, each on his
## round from the game's height (frames a few seconds apart), one watching a hero walk up, and the three fighting
## zombies loose in the camp. Needs a display.
## Usage: godot --path . -s tools/_late.gd -- res://tools/guard_shots.gd outdir
var g
var out := ""

func _initialize():
	for a in OS.get_cmdline_user_args():
		if not a.begins_with("res://"):
			out = a
	g = (load("res://main.tscn") as PackedScene).instantiate()
	get_root().add_child(g)
	_run()

func _frame() -> Image:
	await process_frame
	await process_frame
	return get_root().get_texture().get_image()

## A grid of frames, each scaled to w wide, cols across.
func _sheet(frames: Array, name: String, cols := 3, w := 640) -> void:
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
	print("[S] ", name)

func _guards() -> Array:
	var gs := []
	for c in g.world.props_root.get_children():
		if c is CampGuard:
			gs.append(c)
	return gs

func _aim(cam: Camera3D, guard: CampGuard, dist: float, height: float, side := 0.0, look_h := 1.15) -> void:
	var f := Vector3(sin(guard.yaw + side), 0, cos(guard.yaw + side))
	var at := guard.global_position + Vector3(0, look_h, 0)
	cam.global_transform = Transform3D(Basis(), guard.global_position + f * dist + Vector3(0, height, 0)).looking_at(at)

func _run() -> void:
	while g.world == null or g._busy or g._intro_playing:
		g._intro_skip = true
		await process_frame
	await g.start_game(false, "knight")
	g.ui.close_all()
	while g._busy:
		await process_frame
	g.ui.root.visible = false
	var cam: Camera3D = g.get_viewport().get_camera_3d()
	g.set_process(false)
	g.hero.global_position = Vector3(0, 0, 60)
	await create_timer(1.0).timeout
	var gs := _guards()
	print("[S] guards: ", gs.size())
	# each close up: front, three-quarter, side
	var close := []
	for gd in gs:
		var guard: CampGuard = gd
		guard.set_process(false)
		guard.anim.play("idle")
		for side in [0.0, 0.7, 1.6]:
			_aim(cam, guard, 3.3, 1.25, side, 1.05)
			cam.fov = 40
			close.append(await _frame())
		guard.set_process(true)
	await _sheet(close, "guards_close", 3, 560)
	# on their rounds, from the game's height: four frames 4 s apart each
	cam.fov = 45
	for gd in gs:
		var guard: CampGuard = gd
		var fr := []
		for i in 6:
			var p := guard.global_position
			cam.global_transform = Transform3D(Basis(), p + Vector3(0, 9.0, 8.0)).looking_at(p + Vector3(0, 0.9, 0))
			fr.append(await _frame())
			await create_timer(3.0).timeout
		await _sheet(fr, "round_" + str(guard.def["id"]), 3, 560)
	# a hero walking up behind the warden: he turns to watch them
	var w: CampGuard = gs[0]
	g.set_process(true)
	w.watch_cd = 0.0
	g.hero.global_position = g.world.free_spot_near(w.global_position - Vector3(sin(w.yaw), 0, cos(w.yaw)) * 5.0, 0.4)
	var watch := []
	for i in 6:
		watch.append(await _frame())
		await create_timer(0.6).timeout
	await _sheet(watch, "watch", 3, 560)
	# zombies loose by the bonfire: all three come and fight
	g.hero.global_position = Vector3(0, 0, 60)
	g.set_process(false)
	var zs := []
	for i in 4:
		var e: Enemy = g.spawn_enemy("zombie", g.world.free_spot_near(Vector3(-2.0 + i * 1.6, 0, -1.0), 0.5), 3)
		if e != null:
			e.speed *= 0.3
			zs.append(e)
	var fight := []
	for i in 12:
		var c := Vector3.ZERO
		var n := 0
		for gd in gs:
			if (gd as CampGuard).state == "fight":
				c += (gd as CampGuard).global_position
				n += 1
		if n == 0:
			c = Vector3(0, 0, -1)
		else:
			c /= n
		cam.global_transform = Transform3D(Basis(), c + Vector3(0, 6.5, 7.5)).looking_at(c + Vector3(0, 0.9, 0))
		fight.append(await _frame())
		await create_timer(0.9).timeout
	await _sheet(fight, "fight", 4, 480)
	quit()
