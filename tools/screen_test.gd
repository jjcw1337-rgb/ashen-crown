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
	# a key on the title reaches nothing of the game
	var e := InputEventKey.new()
	e.keycode = KEY_I
	e.pressed = true
	g._unhandled_input(e)
	check(not ui.inv_panel.visible, "title: I doesn't open the inventory")
	# a message shows over the title
	ui.message("hello")
	check(ui.msg_lbl.is_visible_in_tree() and ui.top.get_index() > ui.menus.get_index(), "title: a message is drawn over it")
	# the Battlegrounds screen over the title
	ui.open_battlegrounds()
	await frames(2)
	check(ui.bg_panel.is_visible_in_tree() and ui.title_panel.is_visible_in_tree(), "Battlegrounds: over the title (its backdrop)")
	check(ui.menu_shade != null and ui.menu_shade.visible, "Battlegrounds: the title is dimmed behind it")
	var card: Control = ui._title_cards["new"]
	check(not _in_front(card), "Battlegrounds: the title's cards can't be clicked through it")
	check(_in_front(ui.bg_panel.find_child("enter", true, false)), "Battlegrounds: Enter takes the click")
	check(not ui.quest_tracker.is_visible_in_tree() and not ui.hud.is_visible_in_tree(), "Battlegrounds: no HUD, no quest tracker")
	var txt: String = ""
	for l in ui.bg_panel.find_children("*", "Label", true, false):
		txt += (l as Label).text + " "
	check(not txt.contains("PERMANENT") and txt.to_lower().contains("level"), "Battlegrounds: it states today's rule (items lost, levels kept)")
	ui._bg_go()
	await frames(2)
	check(ui.dialog_panel.is_visible_in_tree(), "Battlegrounds: Enter asks first")
	var btns: Array = ui.dialog_btns.get_children()
	check(btns.size() > 0 and _in_front(btns[0]), "Battlegrounds: the dialog is on top and its button takes the click")
	check(not str(ui.dialog_text.text).contains("forever"), "Battlegrounds: the dialog states today's rule")
	ui.dialog_panel.visible = false
	(ui.bg_panel.find_children("*", "Button", true, false).filter(func(b): return b.text == "Back")[0] as Button).pressed.emit()
	await frames(2)
	check(not ui.bg_panel.visible and not ui.menu_shade.visible and ui.title_panel.visible, "Battlegrounds: Back is the title again")
	# the co-op screen the same way
	ui.open_join()
	await frames(2)
	check(ui.join_panel.is_visible_in_tree() and ui.menu_shade.visible and not _in_front(card), "co-op: over the dimmed title")
	ui.join_panel.visible = false
	g.net.stop_listening()
	await frames(1)
	check(not ui.menu_shade.visible, "co-op: closed, the shade goes")
	# play
	await g.start_game(false)
	await frames(10)
	check(ui.hud.is_visible_in_tree() and not ui.title_panel.visible, "play: the HUD is back, the title gone")
	check(ui.dialog_panel.get_parent() == ui.modals and ui.pause_panel.get_parent() == ui.modals and ui.modals.get_index() > ui.windows.get_index(), "play: dialogs and the pause menu are over the windows")
	for fn in DirAccess.get_files_at(DIR):
		DirAccess.remove_absolute(DIR + fn)
	print("[S] done, %d failed" % fails)
	quit()
