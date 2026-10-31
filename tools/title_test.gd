extends SceneTree
## The title screen (UI._build_title, TitleStage): Continue loads exactly the character it shows, Create New
## opens the class picker (and the stage stops drawing under it, and starts again on Back), with no saves
## Continue is disabled and does nothing, and the game's own 3D comes back once play starts.
## Runs on its own folder (user://test_title_characters/), never the player's.
##   godot --headless --path . -s tools/title_test.gd
var g
const DIR := "user://test_title_characters/"
func _initialize():
	g = (load("res://main.tscn") as PackedScene).instantiate()
	get_root().add_child(g)
	_run()

func _frames(n: int) -> void:
	for i in n:
		await process_frame

func _wipe() -> void:
	var d := DirAccess.open(DIR)
	if d:
		d.include_hidden = true
		for fn in d.get_files():
			DirAccess.remove_absolute(DIR + fn)

func _save(id: String, nm: String, cls: String, lvl: int, gold: int, played: int) -> void:
	var f := FileAccess.open(DIR + id + ".json", FileAccess.WRITE)
	f.store_string(JSON.stringify({"name": nm, "hero": {"cls": cls, "level": lvl, "gold": gold,
		"equipment": {"weapon": Items.make("short_sword")}}, "act": 0, "difficulty": 0, "played": played}))
	f.close()

func _run() -> void:
	while g.world == null or g._busy or g._intro_playing or not g.ui.title_panel.visible:
		g._intro_skip = true
		await process_frame
	g.char_dir = DIR
	g.old_save = DIR + "none.json"
	DirAccess.make_dir_recursive_absolute(DIR)
	_wipe()
	var ui = g.ui
	var now := int(Time.get_unix_time_from_system() * 1000.0)
	# --- no saves
	ui.show_title()
	await _frames(3)
	var cont := ui._title_cards["continue"] as Button
	print("[T] no saves: continue disabled %s, no figure %s, characters hidden %s, 3D off under the title %s" % [cont.disabled, ui.title_stage.hero == null, not (ui.title_panel.find_child("characters", true, false) as Button).visible, get_root().disable_3d])
	await ui._title_choose("continue")
	print("[T] no saves: Continue does nothing: still on title %s, playing %s" % [ui.title_panel.visible, g.playing])
	# --- two saves: the newer is shown and loaded
	_save("old_one", "Morwen", "wraith", 9, 111, now - 86400 * 1000)
	_save("new_one", "Roland", "knight", 21, 7777, now - 3600 * 1000)
	ui.show_title()
	await _frames(3)
	print("[T] two saves: card '%s' / '%s', figure %s, id %s" % [(cont.find_child("big", true, false) as Label).text, (cont.find_child("line", true, false) as Label).text, ui.title_stage.hero.cls if ui.title_stage.hero else "-", ui.title_stage.get_meta("char_id")])
	print("[T] the saves are untouched by showing them: ", FileAccess.get_file_as_string(DIR + "new_one.json").contains("\"gold\":7777"))
	# --- Create New: picker opens, stage stops drawing; Back: it draws again
	await ui._title_choose("new")
	await _frames(3)
	print("[T] create new: class picker open %s, stage paused %s, title still up %s, not playing %s" % [ui.class_panel.visible, ui.title_stage.vp.render_target_update_mode == SubViewport.UPDATE_DISABLED, ui.title_panel.visible, not g.playing])
	ui.class_panel.visible = false
	ui._close_class_stage()
	await _frames(3)
	print("[T] back from the picker: stage drawing again %s, fade cleared %s" % [ui.title_stage.vp.render_target_update_mode == SubViewport.UPDATE_ALWAYS, ui._title_fade.color.a < 0.01])
	# --- a second click while one is under way is ignored
	ui._title_busy = true
	await ui._title_choose("continue")
	print("[T] click during a choice ignored: ", not g.playing)
	ui._title_busy = false
	# --- Continue: loads exactly the one shown
	await ui._title_choose("continue")
	await _frames(3)
	print("[T] continue: playing %s, char %s (%s), class %s, level %d, gold %d, title hidden %s, 3D back on %s" % [g.playing, g.char_name, g.char_id, g.hero.cls, g.hero.level, g.hero.gold, not ui.title_panel.visible, not get_root().disable_3d])
	print("[T] no duplicate save made: ", DirAccess.get_files_at(DIR).size() == 2)
	await g.exit_to_title()
	print("[T] back to title: shows Roland again %s, 3D off %s" % [(cont.find_child("big", true, false) as Label).text == "Roland", get_root().disable_3d])
	_wipe()
	DirAccess.remove_absolute(DIR)
	quit()
