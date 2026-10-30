extends SceneTree
## Screenshots of the New Character screen (UI._build_class_picker, ClassStage): the heroes idle with the
## Knight chosen, each class fidgeting under the mouse, and each signature move at its impact. Needs a
## display. Usage: -- outdir [frames]   (frames: also a 15 fps sequence of hover and signatures for a clip)
var g

func _initialize():
	g = (load("res://main.tscn") as PackedScene).instantiate()
	get_root().add_child(g)
	_run()

func _snap(path: String) -> void:
	await process_frame
	get_root().get_texture().get_image().save_png(path)

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var out: String = args[0]
	var frames := args.has("frames")
	while g.world == null or g._busy or g._intro_playing or not g.ui.title_panel.visible:
		g._intro_skip = true
		await process_frame
	g.ui.open_class_picker()
	var st = g.ui.class_stage
	await create_timer(2.5).timeout
	print("[CS] stage built: %d heroes" % st.heroes.size())
	await _snap(out + "/class_idle.png")
	var n := 0
	for c in st.CLASSES:
		st.hovered = c
		st._fid_t[c] = 0.0
		st.hovering.emit(c)
		for k in (30 if frames else 1):
			await create_timer(0.8 / 1.0 if not frames else 1.0 / 15.0).timeout
			if frames:
				await _snap(out + "/f%04d.png" % n)
				n += 1
		await _snap(out + "/hover_%s.png" % c)
		st.hovered = ""
		st.choose(c)
		st._sig_wait = 0.0
		var sig: Array = st.SIGNATURE[c]
		var tt := 0.0
		var shot := false
		while tt < float(sig[1]) + 0.4:
			await create_timer(1.0 / 15.0).timeout
			tt += 1.0 / 15.0
			if frames:
				await _snap(out + "/f%04d.png" % n)
				n += 1
			if not shot and tt > float(sig[1]) * float(sig[2]) + 0.12:
				shot = true
				await _snap(out + "/sig_%s.png" % c)
	print("[CS] done")
	quit()
