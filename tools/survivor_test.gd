extends SceneTree
## Survivors (Blaine's overhaul 2026-11-06): a run character who extracts gets the results with Save Character; one
## press saves it, a second press, reopening the results or saving the same run again writes nothing new; the
## roster lists it; a survivor loads with its real class, level, skills, slots, passives, gear and consumables (the
## Arena's join path); a fallen run offers no save; the single-player characters are untouched; Return goes back to
## the lobby browser. Uses its own survivor folder. Prints [SURV] lines.
var g
var fails := 0
var SV
var RB

func _initialize():
	g = (load("res://main.tscn") as PackedScene).instantiate()
	get_root().add_child(g)
	SV = load("res://scripts/survivors.gd")
	RB = load("res://game/items/run_build.gd")
	_run()

func check(ok: bool, what: String) -> void:
	if not ok:
		fails += 1
	print("[SURV] %s %s" % ["ok  " if ok else "FAIL", what])

func secs(t: float) -> void:
	await create_timer(t).timeout

func _btn(name: String) -> Button:
	return g.ui.run_ui.find_child(name, true, false) as Button

func _run() -> void:
	while g.world == null or g._busy:
		g._intro_skip = true
		await process_frame
	SV.dir = "user://survivor_test/"
	DirAccess.make_dir_recursive_absolute(SV.dir)
	for fn in DirAccess.get_files_at(SV.dir):
		DirAccess.remove_absolute(SV.dir + fn)
	var chars_before: Array = g.list_characters()
	await g.start_game(false, "knight")
	await g.load_zone(0, "sandbox", "start")
	g.ui.hide_title()
	var h = g.hero
	# a plague doctor's run, a few camps in
	h.set_class("plague")
	h.start_run()
	g.char_name = "Plague Doctor"
	for k in 4:
		h.add_xp(RB.xp_for(h.level))
	var pool: Array = RB.skill_pool("plague")
	for i in 6:
		h.run.add_skill(str(pool[i]["id"]), h.binds)
	h.run.passives = {"g_hide": 2, "p_venom": 1}
	h.run.camps = 5
	h.run.bosses = 1
	h.run_changed()
	h.bind("rmb", h.run.skills[5])      # (the spellbook's sixth swapped onto right mouse)
	var rmb: String = h.bound("rmb")
	h.belt[2] = load("res://game/items/items.gd").potion("hp_potion")
	var want := {"cls": h.cls, "level": h.level, "skills": h.run.skills.duplicate(), "binds": h.binds.duplicate(), "passives": h.run.passives.duplicate(),
		"weapon": str(h.equipment["weapon"]["name"]), "belt": h.belt.filter(func(x): return x != null).size(), "life": h.max_life}
	# the extraction (as Net.cl_extracted calls it)
	g.bg_mode = true
	await g.bg_extracted([])
	await secs(0.3)
	check(g.ui.run_ui.visible and g.ui.run_ui.mode == "results" and _btn("save") != null, "extracted: the results with Save Character")
	g.ui.close_all()
	check(g.ui.run_ui.mode == "results", "Esc and closing windows leave the results up")
	_btn("save").pressed.emit()
	await secs(0.1)
	var list: Array = SV.list()
	check(list.size() == 1 and _btn("save").disabled, "Save Character saved one survivor")
	var again: Array = g.run_save_survivor()
	check(not bool(again[1]) and SV.list().size() == 1, "saving the same run again writes nothing new")
	g.ui.run_ui.open_results(true)
	check(_btn("save").disabled and SV.list().size() == 1, "reopened results show it saved")
	# the roster
	g.ui.run_ui.open_roster(func(_id): pass, "")
	check(g.ui.run_ui.mode == "roster" and g.ui.run_ui.find_child("*", true, false) != null, "the roster lists it")
	g.ui.run_ui.close()
	# load it the way the Arena does (Game.start_join -> Survivors.load_into) onto a hero that was something else
	var sid: String = str(list[0]["id"])
	h.set_class("knight")
	h.new_character()
	check(SV.load_into(g, sid), "the survivor loads")
	check(h.cls == want["cls"] and h.level == want["level"], "its class and level (%s %d)" % [h.cls, h.level])
	check(h.run != null and h.run.skills == want["skills"] and h.bound("rmb") == rmb, "its skills and slots")
	check(h.run.passives == want["passives"] and is_equal_approx(h.max_life, want["life"]), "its passives (life %d)" % int(h.max_life))
	check(str(h.equipment["weapon"]["name"]) == want["weapon"] and h.belt.filter(func(x): return x != null).size() == want["belt"], "its gear and consumables")
	check(SV.summary(list[0]).contains("Level %d" % want["level"]), "its card: %s" % SV.summary(list[0]))
	# a fallen run: nothing to save
	g.ui.run_ui.close(true)
	g.run_results_open = false
	h.set_class("archer")
	h.start_run()
	g.bg_mode = true
	h.dead = true
	await g._leave_battlegrounds()
	await secs(0.2)
	check(g.ui.run_ui.mode == "results" and _btn("save") == null, "a fallen run's results offer no save")
	check(g.run_save_survivor()[0] == "" and SV.list().size() == 1, "and nothing can save it")
	h.dead = false
	# back to the lobby browser
	await g.run_return()
	await secs(0.5)
	check(not g.ui.run_ui.visible and g.hero.run == null and g.lobby_client.panel.visible, "Return: back at the lobby browser, the run gone")
	check(g.list_characters().size() == chars_before.size(), "single-player characters untouched (%d)" % chars_before.size())
	# the lobby: Arena members bring the survivor, Battlegrounds members a class
	var lc = g.lobby_client
	lc.selected_mode = "arena"
	lc.draw()
	check(lc.member_character("arena") == sid, "the Arena lobby picks the survivor")
	lc.run_class = "plague"
	check(lc.member_character("battlegrounds") == "run_plague", "the Battlegrounds lobby brings a class")
	for fn in DirAccess.get_files_at(SV.dir):
		DirAccess.remove_absolute(SV.dir + fn)
	lc.survivor = ""
	lc.draw()
	check(lc.member_character("arena") == "" and lc.survivor_lbl.text.begins_with("No survivors yet"), "no survivors: the Arena lobby says how to earn one")
	print("[SURV] done, %d failure(s)" % fails)
	quit(1 if fails > 0 else 0)
