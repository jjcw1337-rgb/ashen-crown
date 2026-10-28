extends SceneTree
## Screenshots of the character screens (title, character list, class picker with the name field), on a
## throwaway folder of three characters:  godot --path . -s tools/char_shot.gd -- outprefix
var g
const DIR := "user://shot_characters/"
func _initialize():
	g = (load("res://main.tscn") as PackedScene).instantiate()
	get_root().add_child(g)
	_run()
func _shot(path: String) -> void:
	for i in 6:
		await process_frame
	get_root().get_texture().get_image().save_png(path)
	print("saved ", path)
func _run() -> void:
	var out: String = OS.get_cmdline_user_args()[0]
	while g.world == null or g._busy or g._intro_playing or not g.ui.title_panel.visible:
		g._intro_skip = true
		await process_frame
	g.char_dir = DIR
	g.old_save = DIR + "none.json"
	DirAccess.make_dir_recursive_absolute(DIR)
	var t := 1000
	for c in [["Aldric", "knight", 14, 1], ["Fizzwick", "warlock", 22, 2], ["Morwen", "wraith", 6, 0]]:
		var f := FileAccess.open(DIR + c[0] + ".json", FileAccess.WRITE)
		f.store_string(JSON.stringify({"name": c[0], "hero": {"cls": c[1], "level": c[2]}, "difficulty": c[3], "played": t}))
		f.close()
		t -= 1
	g.ui.show_title()
	await _shot(out + "_title.png")
	g.ui.open_characters()
	await _shot(out + "_list.png")
	g.ui.open_class_picker()
	g.ui.name_edit.text = "Grimble"
	await _shot(out + "_new.png")
	for fn in DirAccess.get_files_at(DIR):
		DirAccess.remove_absolute(DIR + fn)
	DirAccess.remove_absolute(DIR)
	quit()
