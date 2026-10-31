extends SceneTree
## Screenshots of the title screen (TitleStage), on a throwaway character folder:
##   xvfb-run -a godot --rendering-driver opengl3 --resolution 1920x1080 --path . -s tools/title_shot.gd -- outprefix [class]
## Saves <out>_char.png (a saved level 14 character), <out>_hover.png (Continue hovered), <out>_newhover.png
## and <out>_none.png (no characters).
var g
const DIR := "user://shot_title_characters/"
func _initialize():
	g = (load("res://main.tscn") as PackedScene).instantiate()
	get_root().add_child(g)
	_run()

func _wait(sec: float) -> void:
	var end := Time.get_ticks_msec() + int(sec * 1000.0)
	var n := 0
	while Time.get_ticks_msec() < end or n < 3:
		await process_frame
		n += 1

func _shot(path: String) -> void:
	await _wait(0.2)
	get_root().get_texture().get_image().save_png(path)
	print("saved ", path, "  fps ", Engine.get_frames_per_second())

func _wipe() -> void:
	var d := DirAccess.open(DIR)
	if d:
		d.include_hidden = true
		for fn in d.get_files():
			DirAccess.remove_absolute(DIR + fn)

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var out: String = args[0]
	var cls: String = args[1] if args.size() > 1 else "knight"
	while g.world == null or g._busy or g._intro_playing or not g.ui.title_panel.visible:
		g._intro_skip = true
		await process_frame
	print("[T] title up")
	g.char_dir = DIR
	g.old_save = DIR + "none.json"
	DirAccess.make_dir_recursive_absolute(DIR)
	_wipe()
	var eq := {"weapon": Items.make(str(Data.CLASSES[cls].get("weapon", "short_sword"))), "armor": Items.make("quilted")}
	if cls == "knight":
		eq["shield"] = Items.make("buckler")
	var f := FileAccess.open(DIR + "aldric.json", FileAccess.WRITE)
	f.store_string(JSON.stringify({"name": "Aldric", "hero": {"cls": cls, "level": 14, "equipment": eq}, "difficulty": 0,
		"played": int(Time.get_unix_time_from_system() * 1000.0) - 2 * 3600 * 1000}))
	f.close()
	g.ui.show_title()
	await _wait(2.5)
	await _shot(out + "_char.png")
	g.ui.title_stage.set_focus("continue")
	await _wait(1.0)
	await _shot(out + "_hover.png")
	g.ui.title_stage.set_focus("new")
	await _wait(1.4)
	await _shot(out + "_newhover.png")
	g.ui.title_stage.set_focus("")
	_wipe()
	g.ui.show_title()
	await _wait(2.0)
	await _shot(out + "_none.png")
	_wipe()
	DirAccess.remove_absolute(DIR)
	quit()
