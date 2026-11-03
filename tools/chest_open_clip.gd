extends SceneTree
## Frames of an antechamber stash chest opening (jj: "go through it frame by frame"): the hero beside his corner
## room's chest in the Hollow Crypt, the game camera, then what the raid server's answer sets off on every game
## (Game.chest_lid: the padlock springs, the lid heaves back; Battlegrounds.stash_fx: the fire, the spray, the
## smoke, the loop). Saves every `step`th frame and a contact sheet. Needs a display; run with --fixed-fps 30.
## Usage: godot --path . --fixed-fps 30 -s tools/chest_open_clip.gd -- outdir [frames 90] [step 3] [close]
var g

func _initialize():
	g = (load("res://main.tscn") as PackedScene).instantiate()
	get_root().add_child(g)
	_run()

func _run() -> void:
	var a := OS.get_cmdline_user_args()
	var out: String = a[0]
	var frames := int(a[1]) if a.size() > 1 else 90
	var step := int(a[2]) if a.size() > 2 else 3
	var close := a.has("close")
	while g.world == null or g._busy or g._intro_playing:
		g._intro_skip = true
		await process_frame
	await g.start_game(false, "knight")
	g.ui.close_all()
	var BG = load("res://scripts/battlegrounds.gd")
	await g.load_zone(0, BG.ZONE, "start")
	while g._busy:
		await process_frame
	g.ui.close_all()
	var chest = null
	for it in g.world.interactables:
		if is_instance_valid(it) and it.kind == "stash":
			if chest == null or it.global_position.distance_to(g.hero.global_position) < chest.global_position.distance_to(g.hero.global_position):
				chest = it
	if chest == null:
		print("[CC] no chest")
		quit()
		return
	g.hero.global_position = g.world.free_spot_near(chest.global_position + Vector3(2.0, 0, 2.0), 0.5)
	g.hero.rig.rotation.y = atan2(chest.global_position.x - g.hero.global_position.x, chest.global_position.z - g.hero.global_position.z)
	g.bg_mode = true
	g.bg_raid = {"state": "prep:17", "t": 60.0, "open": [], "len": 1200.0, "portals_at": 300.0, "wait": 17.0}
	if close:
		g.zoom = float(a[a.find("close") + 1]) if a.find("close") + 1 < a.size() and a[a.find("close") + 1].is_valid_float() else 0.5
	for f in 40:
		await process_frame
	get_root().get_texture().get_image().save_png(out + "/pre.png")      # (closed, before anything)
	var idx: int = g.world.interactables.find(chest)
	var shots: Array[Image] = []
	g.ui.trade_with = chest         # (the opener's view: the banner and the shake)
	g.hero.stash_slow()
	g.chest_lid(chest, true)
	BG.stash_fx(g, idx)
	for f in frames:
		await process_frame
		if f % step == 0:
			var img := get_root().get_texture().get_image()
			img.save_png(out + "/open_%03d.png" % f)
			var sm := img.duplicate() as Image
			sm.resize(img.get_width() / 4, img.get_height() / 4, Image.INTERPOLATE_BILINEAR)
			shots.append(sm)
	# the contact sheet: six across
	if not shots.is_empty():
		var w := shots[0].get_width()
		var h := shots[0].get_height()
		var cols := 6
		var rows := int(ceil(shots.size() / float(cols)))
		var sheet := Image.create(w * cols, h * rows, false, shots[0].get_format())
		for i in shots.size():
			sheet.blit_rect(shots[i], Rect2i(0, 0, w, h), Vector2i((i % cols) * w, (i / cols) * h))
		sheet.save_png(out + "/sheet.png")
	print("[CC] %d frames saved" % shots.size())
	g.bg_mode = false
	quit()
