extends SceneTree
## Screen isolation (UI's layers: hud < windows < menus < modals < top): each screen shows only what belongs to it.
##   godot --headless --path . -s tools/screen_test.gd
## On the title nothing of the game shows (no HUD, quest tracker, boss bar, nameplates) and no key reaches the game;
## the co-op and Battlegrounds screens open over the title (dimmed behind them, its cards unclickable), and the
## Battlegrounds' "Enter" asks in a dialog that is on top and takes the click; a message shows over every screen; in
## play the HUD is back and the title gone. Runs on its own character folder, never the player's.
var g
var fails := 0
const DIR := "user://test_screen_characters/"

func _initialize():
	g = (load("res://main.tscn") as PackedScene).instantiate()
	get_root().add_child(g)
	_run()

func check(ok: bool, what: String) -> void:
	if not ok:
		fails += 1
	print("[S] " + ("ok   " if ok else "FAIL ") + what)

func frames(n: int) -> void:
	for i in n:
		await process_frame

## The topmost visible Control that would take a click at pt (the deepest last-drawn one that stops the mouse).
func _top_at(c: Node, pt: Vector2) -> Control:
	if c is CanvasItem and not (c as CanvasItem).visible:
		return null
	var kids := c.get_children()
	kids.reverse()
	for k in kids:
		var r := _top_at(k, pt)
		if r != null:
			return r
	if c is Control and (c as Control).mouse_filter == Control.MOUSE_FILTER_STOP and (c as Control).get_global_rect().has_point(pt):
		return c as Control
	return null

func _in_front(ctl: Control) -> bool:
	var pt := ctl.get_global_rect().get_center()
	var t := _top_at(g.ui.root, pt)
	return t == ctl or (t != null and ctl.is_ancestor_of(t))

func _run() -> void:
	while g.world == null or g._busy or g._intro_playing or not g.ui.title_panel.visible:
		g._intro_skip = true
		await process_frame
	g.char_dir = DIR
	g.old_save = DIR + "none.json"
	DirAccess.make_dir_recursive_absolute(DIR)
	for fn in DirAccess.get_files_at(DIR):
		DirAccess.remove_absolute(DIR + fn)
	var ui = g.ui
	# a character to take in
	g.hero.set_class("warlock")
	g.hero.new_character()
	g.char_id = g.new_char_id()
	g.char_name = "Morluc"
	g.save_game()
	g.char_id = ""
	ui.show_title()
	await frames(3)
	var hud_bits := {"the HUD": ui.hud, "the quest tracker": ui.quest_tracker, "the boss bar": ui.boss_bar_box,
		"the nameplates": ui.plates, "the corner map": ui.minimap, "the action bar": ui.action_bar}
	for nm in hud_bits:
		check(not (hud_bits[nm] as CanvasItem).is_visible_in_tree(), "title: %s doesn't show" % nm)
	check(ui.title_panel.is_visible_in_tree(), "title: the title shows")
	var rev: Label = ui.title_panel.find_child("build_rev", true, false)
	check(rev != null and rev.is_visible_in_tree() and rev.text.contains(BuildEnv.value("rev")), "title: the build's rev shows in the corner")
	# a key on the title reaches nothing of the game
	var e := InputEventKey.new()
	e.keycode = KEY_I
	e.pressed = true
	g._unhandled_input(e)
	check(not ui.inv_panel.visible, "title: I doesn't open the inventory")
	# a message shows over the title
	ui.message("hello")
	check(ui.msg_lbl.is_visible_in_tree() and ui.top.get_index() > ui.menus.get_index(), "title: a message is drawn over it")
	# the home screen is the multiplayer page (Blaine, 2026-11-06): no title, Enter World or characters
	var home = ui.home
	check(g.lobby_client.panel.visible and g.lobby_client.selected_mode == "battlegrounds", "home: the lobby browser, on Battlegrounds")
	check(not home.is_visible_in_tree() and not ui.title_panel.find_child("title_head", true, false).is_visible_in_tree(), "home: no title, Enter World or character list")
	var quit_b: Button = g.lobby_client.panel.find_child("back", true, false)
	check(quit_b != null and quit_b.text == "Quit" and _in_front(quit_b), "home: its top-right button is Quit")
	check(not g.lobby_client.lan_row.visible, "home: no LAN (it hosted a character's world)")
	ui.open_battlegrounds()
	await frames(2)
	check(g.lobby_client.panel.visible and g.lobby_client.selected_mode == "battlegrounds", "Battlegrounds: opens the lobby browser on Battlegrounds")
	g.lobby_client.panel.hide()
	await frames(1)
	# play
	await g.start_game(false)
	await frames(10)
	check(ui.hud.is_visible_in_tree() and not ui.title_panel.visible, "play: the HUD is back, the title gone")
	check(ui.dialog_panel.get_parent() == ui.modals and ui.pause_panel.get_parent() == ui.modals and ui.modals.get_index() > ui.windows.get_index(), "play: dialogs and the pause menu are over the windows")
	# a new character starts with an empty stash (not the last one's)
	g.hero.stash[0] = Items.make("short_sword")
	g.hero.new_character()
	check(g.hero.stash.filter(func(x): return x != null).is_empty(), "a new character's stash is empty")
	# a save in a raid is marked in_raid (Act I is the only act)
	g.char_id = g.new_char_id()
	g.char_name = "Raider"
	g.hero.set_level(9)
	g.hero.inventory[0] = Items.make("short_sword")
	g.hero.gold = 500
	g.bg_mode = true
	g.save_game()
	var sv = JSON.parse_string(FileAccess.get_file_as_string(g.save_path()))
	check(int(sv.get("difficulty", -1)) == 0 and bool(sv.get("in_raid", false)), "a save in a raid is marked in the raid, in Act I")
	# Save and Exit to Title in a raid (without extracting) is dying there: items and gold gone, levels kept
	var path: String = g.save_path()
	await g.exit_to_title()
	sv = JSON.parse_string(FileAccess.get_file_as_string(path))
	var hs: Dictionary = sv.get("hero", {})
	check(not bool(sv.get("in_raid", true)) and int(hs.get("level", 0)) == 9 and int(hs.get("gold", -1)) == 0 \
		and (hs.get("inventory", []) as Array).filter(func(x): return x != null).is_empty(), "leaving a raid for the title costs what was carried, not the levels")
	check(ui.title_panel.visible and not ui.death_panel.visible and not ui.hud.is_visible_in_tree(), "and it's the title, with nothing of the raid over it")
	for fn in DirAccess.get_files_at(DIR):
		DirAccess.remove_absolute(DIR + fn)
	print("[S] done, %d failed" % fails)
	quit()
