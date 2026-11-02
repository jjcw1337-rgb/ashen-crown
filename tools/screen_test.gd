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
	# the home screen (TitleHome): the character sidebar, the modes and Play; the Battlegrounds is one of its modes
	var home = ui.home
	check(home.is_visible_in_tree() and home.sel != "", "home: the sidebar lists the characters and one is chosen")
	check(_in_front(home.get_node("sidebar").find_child("char_" + home.sel, true, false)), "home: a character's card takes the click")
	check(_in_front(home.get_node("sidebar").find_child("create", true, false)), "home: Create New Character takes the click")
	ui.open_battlegrounds()
	await frames(2)
	check(home.mode == "bg" and ui.title_panel.is_visible_in_tree() and not ui.bg_panel.visible, "Battlegrounds: a mode of the home screen, over the gate")
	check(_in_front(home._play) and home._play.text == "Enter the Crypt", "Battlegrounds: its Play button takes the click")
	check(not ui.quest_tracker.is_visible_in_tree() and not ui.hud.is_visible_in_tree(), "Battlegrounds: no HUD, no quest tracker")
	check(not home._note.text.contains("PERMANENT") and home._note.text.to_lower().contains("levels are kept"), "Battlegrounds: it states today's rule in one line (items lost, levels kept)")
	home.play()
	await frames(2)
	check(ui.dialog_panel.is_visible_in_tree(), "Battlegrounds: Enter asks first")
	var btns: Array = ui.dialog_btns.get_children()
	check(btns.size() > 0 and _in_front(btns[0]), "Battlegrounds: the dialog is on top and its button takes the click")
	check(not str(ui.dialog_text.text).contains("forever"), "Battlegrounds: the dialog states today's rule")
	ui.dialog_panel.visible = false
	# turned away late in a round (Net.cl_bg_refused): the home screen counts down to the next raid and rejoins by itself
	g.bg_retry = ["127.0.0.1:1", home.sel]
	g.bg_refused("closed", 1.0)
	await frames(3)
	check(home._status.visible and home._status.text.contains("next raid opens"), "Battlegrounds: turned away, it counts down to the next raid (%s)" % home._status.text)
	check(g.net.join_failure("x").contains("next raid opens"), "and says so instead of 'the host left'")
	var tried := false
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 4500 and not tried:
		tried = g.playing or g.loading.visible
		await process_frame
	check(tried, "and when the wait is over it goes in by itself")
	g.bg_retry = []
	while g._busy or g.playing:
		if g.net.active:
			g.net.shutdown()
		g.bg_mode = false
		await process_frame
		if g.playing and not g._busy:
			await g.exit_to_title()
	await frames(2)
	home.set_mode("story")
	check(ui.title_panel.visible and not ui.menu_shade.visible and home.mode == "story", "Battlegrounds: back to the title, Story again")
	# the co-op screen the same way
	ui.open_join()
	await frames(2)
	check(ui.join_panel.is_visible_in_tree() and ui.menu_shade.visible and not _in_front(home._play), "co-op: over the dimmed title (its Play can't be clicked through it)")
	ui.join_panel.visible = false
	g.net.stop_listening()
	await frames(1)
	check(not ui.menu_shade.visible, "co-op: closed, the shade goes")
	# play
	await g.start_game(false)
	await frames(10)
	check(ui.hud.is_visible_in_tree() and not ui.title_panel.visible, "play: the HUD is back, the title gone")
	check(ui.dialog_panel.get_parent() == ui.modals and ui.pause_panel.get_parent() == ui.modals and ui.modals.get_index() > ui.windows.get_index(), "play: dialogs and the pause menu are over the windows")
	# a new character starts with an empty stash (not the last one's)
	g.hero.stash[0] = Items.make("short_sword")
	g.hero.new_character()
	check(g.hero.stash.filter(func(x): return x != null).is_empty(), "a new character's stash is empty")
	# in a raid a save keeps the character's own act (the raid is Act I's)
	g.char_id = g.new_char_id()
	g.char_name = "Raider"
	g.hero.set_level(9)
	g.hero.inventory[0] = Items.make("short_sword")
	g.hero.gold = 500
	g.bg_mode = true
	g.bg_home_run = 2
	g.difficulty = 0
	g.save_game()
	var sv = JSON.parse_string(FileAccess.get_file_as_string(g.save_path()))
	check(int(sv.get("difficulty", -1)) == 2 and bool(sv.get("in_raid", false)), "a save in a raid keeps the character's own act")
	# Save and Exit to Title in a raid (without extracting) is dying there: items and gold gone, levels kept
	var path: String = g.save_path()
	await g.exit_to_title()
	sv = JSON.parse_string(FileAccess.get_file_as_string(path))
	var hs: Dictionary = sv.get("hero", {})
	check(not bool(sv.get("in_raid", true)) and int(hs.get("level", 0)) == 9 and int(hs.get("gold", -1)) == 0 \
		and (hs.get("inventory", []) as Array).filter(func(x): return x != null).is_empty(), "leaving a raid for the title costs what was carried, not the levels")
	check(int(sv.get("difficulty", -1)) == 2 and g.difficulty == 2 and g.bg_home_run == -1, "and the character is back in its own act")
	check(ui.title_panel.visible and not ui.death_panel.visible and not ui.hud.is_visible_in_tree(), "and it's the title, with nothing of the raid over it")
	for fn in DirAccess.get_files_at(DIR):
		DirAccess.remove_absolute(DIR + fn)
	print("[S] done, %d failed" % fails)
	quit()
