extends SceneTree
## Every screen and window of the game, screenshotted for the UX audit (docs/ux/): the title's home, the class
## picker, the characters list, the Battlegrounds page, co-op join, a dialog; then in the game the HUD and each
## window (inventory, character, skills, talents, quests, the trade window, the stash, the bonfire, waypoints, the
## pause menu, death). Run with a display:
##   godot --path . --resolution 1920x1080 -s tools/ux_shots.gd -- <outdir>
## Saves into user://ux_shots_chars/, never the player's characters.
var g
var out := ""
var n := 0
const DIR := "user://ux_shots_chars/"
func _initialize():
	g = (load("res://main.tscn") as PackedScene).instantiate()
	get_root().add_child(g)
	_run()
func shot(name: String, wait := 0.8) -> void:
	await create_timer(wait).timeout
	await RenderingServer.frame_post_draw
	get_root().get_texture().get_image().save_png("%s/%02d_%s.png" % [out, n, name])
	n += 1
func _run() -> void:
	while g.world == null or g._busy or g._intro_playing or not g.ui.title_panel.visible:
		g._intro_skip = true
		await process_frame
	out = OS.get_cmdline_user_args()[0]
	DirAccess.make_dir_recursive_absolute(out)
	g.char_dir = DIR
	g.old_save = DIR + "none.json"
	DirAccess.make_dir_recursive_absolute(DIR)
	for c in [["aldric", "Aldric", "knight", 14, 1200], ["morwen", "Morwen", "wraith", 9, 300], ["fen", "Fenwick", "plague", 20, 54000]]:
		var f := FileAccess.open(DIR + c[0] + ".json", FileAccess.WRITE)
		f.store_string(JSON.stringify({"name": c[1], "hero": {"cls": c[2], "level": c[3], "gold": c[4], "equipment": {}}, "difficulty": 0, "played": int(Time.get_unix_time_from_system() * 1000.0) - c[3] * 100000}))
		f.close()
	var ui = g.ui
	ui.show_title()
	await shot("title_home", 2.5)
	ui._title_choose("new")
	await shot("class_picker", 3.0)
	ui.class_panel.visible = false
	ui._close_class_stage()
	ui.show_title()
	if ui.has_method("open_characters"):
		ui.open_characters()
		await shot("characters_list", 1.5)
		ui.chars_panel.visible = false
	ui.open_battlegrounds()
	await shot("bg_lobbies", 1.5)
	g.lobby_client.panel.hide()
	ui.open_join()
	await shot("coop_join", 1.0)
	ui.join_panel.visible = false
	ui.open_dialog("Delete Aldric?", "Aldric and everything they carry will be gone for good.", [["Delete", func(): pass], ["Keep", func(): pass]])
	await shot("dialog", 0.8)
	ui.dialog_panel.visible = false
	# in the game
	await g.start_game(true, "knight", "aldric")
	while g._busy:
		await process_frame
	ui.close_all()
	await shot("hud_camp", 2.5)
	for p in [["inventory", ui.inv_panel], ["character", ui.char_panel], ["skills", ui.skills_panel], ["talents", ui.talent_panel], ["quests", ui.quest_panel]]:
		ui.toggle(p[1])
		await shot(p[0], 1.0)
		ui.close_all()
	ui.toggle(ui.inv_panel)
	ui.toggle(ui.char_panel)
	await shot("inventory_and_character", 1.0)
	ui.close_all()
	for t in g.world.interactables:
		if t.kind == "vendor":
			g.hero.global_position = g.world.free_spot_near(t.global_position, 2.0)
			g._interact(t)
			await shot("trade_%s" % str(t.data.get("role", "vendor")), 2.0)
			ui.close_all()
			break
	for t in g.world.interactables:
		if t.kind == "stash":
			g.hero.global_position = g.world.free_spot_near(t.global_position, 2.0)
			g._interact(t)
			await shot("stash", 1.2)
			ui.close_all()
			break
	for t in g.world.interactables:
		if t.kind == "bonfire":
			g.hero.global_position = g.world.free_spot_near(t.global_position, 2.0)
			g._interact(t)
			await shot("bonfire", 1.5)
			ui.close_all()
			break
	for t in g.world.interactables:
		if t.kind == "waypoint":
			g.hero.global_position = g.world.free_spot_near(t.global_position, 2.0)
			g._interact(t)
			await shot("waypoints", 1.5)
			ui.close_all()
			break
	g.toggle_pause()
	await shot("pause", 1.0)
	g.toggle_pause()
	await g.travel(0, "wild", "start")
	while g._busy:
		await process_frame
	await shot("hud_moor", 2.5)
	g.test_immortal = false
	g.hero.take_hit(99999.0, g.hero.global_position + Vector3(1, 0, 0))
	await shot("death", 2.5)
	for fn in DirAccess.get_files_at(DIR):
		DirAccess.remove_absolute(DIR + fn)
	quit()
