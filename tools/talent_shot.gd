extends SceneTree
## Screenshots of the talents window for every class (part spent, one talent hovered) and the bar's
## points badge:  godot --path . -s tools/talent_shot.gd -- outprefix
var g
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
	while g.world == null or g._busy:
		g._intro_skip = true
		await process_frame
	await g.start_game(false, "knight")
	await g.load_zone(0, "town", "start")
	var h = g.hero
	for cls in ["knight", "wraith", "demon", "warlock"]:
		h.set_class(cls)
		h.new_character()
		h.set_level(14)
		h.talents = Talents.auto_build(cls, 9)
		h._talents_changed()
		g.ui.close_all()
		g.ui.refresh()
		if cls == "knight":
			await _shot(out + "_badge.png")
		g.ui.toggle(g.ui.talent_panel)
		await process_frame
		var tr: Array = Talents.trees(cls)
		var hov: Dictionary = tr[0]["talents"][4]
		g.ui._talent_hover = hov["id"]
		g.ui._fill_talents()
		await _shot(out + "_" + cls + ".png")
	quit()
