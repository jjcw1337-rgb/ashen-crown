extends SceneTree
## The Warlock on the New Character screen (ClassStage): a strip of frames of her chosen and idle, hovered
## (her fidget) and doing her signature, cropped to her plinth, for judging how alive she looks. Needs a display.
##   godot --path . --resolution 1600x900 -s game/heroes/warlock/tools/warlock_stage_shots.gd -- <outdir> [class] [idle_frames]
## With "seq" (and --fixed-fps 12): every frame of 4 s idle, 3 s hovered and the signature, as s0000.png... for a clip.
var g

func _initialize():
	g = (load("res://main.tscn") as PackedScene).instantiate()
	get_root().add_child(g)
	_run()

func _snap(path: String) -> void:
	await process_frame
	var im := get_root().get_texture().get_image()
	var w := im.get_width()
	var h := im.get_height()
	im = im.get_region(Rect2i(int(w * 0.3), int(h * 0.08), int(w * 0.4), int(h * 0.62)))
	im.save_png(path)

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var out: String = args[0]
	var c: String = args[1] if args.size() > 1 else "warlock"
	var n: int = int(args[2]) if args.size() > 2 else 8
	while g.world == null or g._busy or g._intro_playing or not g.ui.title_panel.visible:
		g._intro_skip = true
		await process_frame
	g.ui.open_class_picker()
	var st = g.ui.class_stage
	st.snap_to(c)
	st.choose(c)
	st._sig_wait = 999.0
	await create_timer(2.0).timeout
	if args.has("seq"):
		var f := 0
		for i in 48:
			await _snap("%s/s%04d.png" % [out, f])
			f += 1
		st.hovered = c
		st._fid_t[c] = 0.0
		for i in 36:
			await _snap("%s/s%04d.png" % [out, f])
			f += 1
		st.hovered = ""
		st._sig_wait = 0.0
		for i in int(float(st.SIGNATURE[c][1]) * 12.0) + 10:
			await _snap("%s/s%04d.png" % [out, f])
			f += 1
		print("[WS] done")
		quit()
		return
	for i in n:
		await _snap("%s/idle_%02d.png" % [out, i])
		await create_timer(0.4).timeout
	st.hovered = c
	st._fid_t[c] = 0.0
	for i in 6:
		await create_timer(0.2).timeout
		await _snap("%s/hover_%02d.png" % [out, i])
	st.hovered = ""
	st._sig_wait = 0.0
	var sig: Array = st.SIGNATURE[c]
	var steps := 8
	for i in steps:
		await create_timer(float(sig[1]) / steps).timeout
		await _snap("%s/sig_%02d.png" % [out, i])
	print("[WS] done")
	quit()
