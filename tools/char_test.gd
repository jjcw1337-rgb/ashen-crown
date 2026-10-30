extends SceneTree
## Characters: the old single save is adopted as the first character, new characters get their own saves,
## the title lists them last played first, Play/Continue load the right one, Exit to Title works, Delete removes.
## Runs on its own folder (user://test_characters/), never the player's.
var g
const DIR := "user://test_characters/"
const OLD := "user://test_characters_old_save.json"
func _initialize():
	g = (load("res://main.tscn") as PackedScene).instantiate()
	get_root().add_child(g)
	_run()

func _wipe() -> void:
	var d := DirAccess.open(DIR)
	if d:
		d.include_hidden = true   # the .adopted marker too, or the next run can't adopt
		for fn in d.get_files():
			DirAccess.remove_absolute(DIR + fn)
	if FileAccess.file_exists(OLD):
		DirAccess.remove_absolute(OLD)

func _run() -> void:
	while g.world == null or g._busy:
		g._intro_skip = true
		await process_frame
	g.char_dir = DIR
	g.old_save = OLD
	_wipe()
	# an old-style save: a level 7 demon
	var f := FileAccess.open(OLD, FileAccess.WRITE)
	f.store_string(JSON.stringify({"hero": {"cls": "demon", "level": 7, "gold": 999}, "act": 0, "difficulty": 0}))
	f.close()
	var chars: Array = g.list_characters()
	print("[C] adopted old save: %d character(s), %s level %d, old file kept %s" % [chars.size(), chars[0]["cls"] if chars.size() > 0 else "-", chars[0]["level"] if chars.size() > 0 else 0, FileAccess.file_exists(OLD)])
	print("[C] adopted only once: ", g.list_characters().size() == 1)
	# two new characters
	await g.start_game(false, "warlock", "", "Fizz")
	g.hero.gold = 4321
	g.save_game()
	var fizz: String = g.char_id
	await g.exit_to_title()
	print("[C] exit to title: title visible %s, playing %s" % [g.ui.title_panel.visible, g.playing])
	await g.start_game(false, "wraith", "", "  ")
	print("[C] blank name gets a default: '%s'" % g.char_name)
	g.hero.level = 3
	g.save_game()
	await g.exit_to_title()
	chars = g.list_characters()
	var names := []
	for c in chars:
		names.append("%s %s L%d" % [c["name"], c["cls"], c["level"]])
	print("[C] list (last played first): ", names)
	print("[C] continue button: ", (g.ui.title_panel.find_child("continue", true, false) as Button).text)
	print("[C] characters button shown: ", (g.ui.title_panel.find_child("characters", true, false) as Button).visible)
	g.ui.open_characters()
	await process_frame
	print("[C] character rows: ", g.ui.chars_list.get_child_count())
	# play Fizz from the list
	await g.start_game(true, "knight", fizz)
	print("[C] played Fizz: class %s gold %d name %s" % [g.hero.cls, g.hero.gold, g.char_name])
	await g.exit_to_title()
	print("[C] Fizz now first: ", g.list_characters()[0]["name"] == "Fizz")
	# safe saves: backups kept, a damaged save recovered, a half-written one still listed
	for i in 4:
		g.char_id = fizz
		g.hero.gold = 5000 + i
		g.save_game()
	var fp: String = DIR + fizz + ".json"
	var baks := range(1, 5).filter(func(i): return FileAccess.file_exists("%s.bak%d" % [fp, i]))
	var ver = JSON.parse_string(FileAccess.get_file_as_string(fp)).get("version", -1)
	print("[C] safe saves: backups %s (3 kept), no .tmp left %s, version %s" % [baks, not FileAccess.file_exists(fp + ".tmp"), ver])
	var bad := FileAccess.open(fp, FileAccess.WRITE)
	bad.store_string("{\"hero\": {\"cls\": \"warl")       # cut off mid-write
	bad.close()
	await g.start_game(true, "knight", fizz)
	print("[C] damaged save: loaded %s gold %d from %s, repaired %s" % [g.hero.cls, g.hero.gold, g.save_recovered,
		typeof(JSON.parse_string(FileAccess.get_file_as_string(fp))) == TYPE_DICTIONARY])
	await g.exit_to_title()
	DirAccess.rename_absolute(fp, fp + ".tmp")
	DirAccess.remove_absolute(fp + ".bak1")
	print("[C] only a .tmp left: still listed %s" % g.list_characters().any(func(c): return c["id"] == fizz))
	# co-op: Host and Join ask which character comes along
	g.ui.open_characters("host")
	await process_frame
	var btn: Button = g.ui.chars_list.get_child(0).find_child("play", true, false)
	print("[C] co-op picker: title '%s', button '%s'" % [g.ui.chars_title.text, btn.text])
	g.ui.chars_panel.visible = false
	# delete Fizz
	g.delete_character(fizz)
	print("[C] delete removes the backups too: ", not range(1, 4).any(func(i): return FileAccess.file_exists("%s.bak%d" % [fp, i])) and not FileAccess.file_exists(fp + ".tmp"))
	chars = g.list_characters()
	print("[C] after delete: %d left, Fizz gone %s" % [chars.size(), chars.all(func(c): return c["name"] != "Fizz")])
	_wipe()
	DirAccess.remove_absolute(DIR)
	quit()
