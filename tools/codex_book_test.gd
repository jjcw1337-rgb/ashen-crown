extends SceneTree
## The players' Codex (scripts/codex_book.gd): every hero's directions with their skills and rites, the shared ones,
## gems and consumables; locked until a camp chest shows them; saved per PC (a test file here); the window opens from
## the run's build window and the multiplayer screen, and the open offer marks its choices.
##   godot --headless --path . -s tools/_late.gd -- res://tools/codex_book_test.gd   [-- shots <outdir>] (shots need a display)
var g
var fails := 0
const TEST_PATH := "user://codex_seen_test.json"

func check(c: bool, what: String) -> void:
	print(("[CB] ok   " if c else "[CB] FAIL ") + what)
	if not c:
		fails += 1

func _initialize() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_PATH))
	CodexBook.use_file(TEST_PATH)
	g = (load("res://main.tscn") as PackedScene).instantiate()
	get_root().add_child(g)
	current_scene = g
	_run()

func _shot(dir: String, name: String) -> void:
	for i in 8:
		await process_frame
	if dir != "":
		get_root().get_texture().get_image().save_png(dir.path_join(name + ".png"))
		print("[SHOT] ", dir.path_join(name + ".png"))

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var shots := ""
	if args.size() >= 2 and args[args.size() - 2] == "shots":
		shots = args[args.size() - 1]
		DirAccess.make_dir_recursive_absolute(shots)
	while g.world == null or g._busy:
		g._intro_skip = true
		await process_frame
	await g.start_game(false, "warlock")
	await g.load_zone(0, "wild", "start")
	g.ui.hide_title()
	# the data
	var hs := CodexBook.heroes()
	check(hs.has("warlock") and hs.has("knight") and hs.size() >= 7, "every hero with a codex file is a page (%d)" % hs.size())
	var ws := CodexBook.hero_sections("warlock")
	var names := ws.map(func(s): return s["name"])
	check(names.has("Corruption") and names.has("Fear") and names.has("Drain"), "the Warlock's three directions: %s" % [names])
	var n := 0
	for s in ws:
		n += s["entries"].size()
		for x in s["entries"]:
			if str(x["text"]) == "" or str(x["name"]) == "":
				check(false, "%s has a name and text" % x["id"])
	check(n >= 25, "the Warlock's pages list her skills and rites (%d)" % n)
	check(CodexBook.gem_sections()[0]["entries"].size() >= 15, "the gems page")
	check(CodexBook.item_sections()[0]["entries"].size() >= 10, "the consumables page")
	check(CodexBook.count(ws) == Vector2i(0, n), "nothing discovered on a fresh PC")
	var design := false
	for e in Codex.hero("warlock").get("rites", []) + Codex.hero("warlock").get("skills", []):
		if not Codex.live(e):
			for s in ws:
				for x in s["entries"]:
					design = design or x["id"] == e["id"]
	check(not design, "design entries never show")
	# a chest's offer marks what it shows, and it is remembered
	var h = g.hero
	h.set_class("warlock")
	h.start_run()
	g.ui.close_all()
	g.ui.run_ui.open_offer("codex_test_camp", 2, "Test Hollow")
	var o: Dictionary = h.run.offers["codex_test_camp"]
	var marked := true
	for c in o["choices"]:
		marked = marked and CodexBook.seen("skill" if c["kind"] == "skill" else "rite", str(c["id"]))
	check(o["choices"].size() > 0 and marked, "the offer's %d choices are discovered" % o["choices"].size())
	for b in o.get("loot", []):
		check(CodexBook.seen("item", str(b)), "its consumable %s is discovered" % b)
	CodexBook.use_file(TEST_PATH)
	check(CodexBook.seen("skill" if o["choices"][0]["kind"] == "skill" else "rite", str(o["choices"][0]["id"])), "discoveries survive a restart (saved to the file)")
	# the window: from the build window's button, every tab, locked and open cards
	g.ui.run_ui.open_build()
	var btn = g.ui.run_ui.find_child("open_codex", true, false)
	check(btn != null, "the build window has a Codex button")
	if btn != null:
		btn.emit_signal("pressed")
	await process_frame
	check(g.ui.run_ui.visible and g.ui.run_ui.mode == "codex", "it opens the Codex")
	var cards: Array = g.ui.run_ui.find_children("card_*", "", true, false)
	var known: Array = cards.filter(func(c): return c.get_meta("known", false))
	check(cards.size() >= 25 and known.size() >= 1 and known.size() < cards.size(), "the Warlock's page: %d cards, %d discovered, the rest locked" % [cards.size(), known.size()])
	await _shot(shots, "codex_warlock")
	for tab in ["knight", "shared", "gems", "items"]:
		var t = g.ui.run_ui.find_child("tab_" + tab, true, false)
		check(t != null, "a %s tab" % tab)
		if t != null:
			t.emit_signal("pressed")
			await process_frame
			check(g.ui.run_ui.find_children("card_*", "", true, false).size() > 0, "the %s tab shows its cards" % tab)
			if tab == "gems":
				await _shot(shots, "codex_gems")
	CodexBook.reveal = true
	CodexBook.open(g.ui.run_ui, "warlock")
	await process_frame
	var all_known: bool = g.ui.run_ui.find_children("card_*", "", true, false).all(func(c): return c.get_meta("known", false))
	check(all_known, "Reveal all (dev) shows every card")
	await _shot(shots, "codex_warlock_revealed")
	CodexBook.reveal = false
	g.ui.run_ui.close()
	check(not g.ui.run_ui.visible, "it closes")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_PATH))
	print("[CB] done, %d failed" % fails)
	quit(1 if fails > 0 else 0)
