extends SceneTree
## Skills unlock by level (Blaine's progression overhaul): every ultimate at 20; a fresh character has its first
## skill, the rest wait on the bar greyed with their level, can't be cast or bound from the skills window, and open as
## the character reaches their level (announced); the F8 panel's "All skills" opens everything.
var g
var fails := 0
func _initialize():
	g = (load("res://main.tscn") as PackedScene).instantiate()
	get_root().add_child(g)
	_run()
func check(ok: bool, what: String) -> void:
	print("[U] ", "ok   " if ok else "FAIL ", what)
	if not ok:
		fails += 1
func wait(n: int) -> void:
	for i in n:
		await process_frame
func _run() -> void:
	while g.world == null or g._busy:
		await wait(5)
	# the data
	var ults := []
	for s in Data.SKILLS:
		if "ultimate" in s.get("tags", []):
			ults.append(s["id"])
			check(int(s["lvl"]) == 20, "%s (%s's ultimate) opens at 20" % [s["name"], s["cls"]])
	check(ults.has("night") and ults.has("wrath") and ults.has("experiment") and ults.has("car"), "the ultimates: %s" % str(ults))
	for cls in ["knight", "wraith", "demon", "warlock", "archer", "plague", "doug"]:
		var own := Data.skills_for(cls)
		check(own.size() > 0 and int(own[0]["lvl"]) == 1, "%s starts with %s" % [cls, own[0]["name"]])
	# a fresh knight
	await g.start_game(false, "knight")
	g.ui.close_all()
	var h = g.hero
	g.test_allskills = false
	h.set_level(1)
	h.mana = h.max_mana
	check(h.use_skill("cleave", h.global_position + Vector3(0, 0, -3)), "level 1: Holy Slam casts")
	await wait(90)
	h.mana = h.max_mana
	check(not h.use_skill("nova", h.global_position), "level 1: Holy Nova (level 3) is refused")
	check(str(h.binds.get("E", "")) == "nova", "it waits on its key, greyed (E = %s)" % str(h.binds.get("E", "")))
	await wait(3)
	var slot = g.ui.skill_slots.get("E")
	var lock = slot.get_node_or_null("hole/lock") if slot != null else null
	check(lock != null and lock.visible and lock.text == "Lv 3", "the slot shows its level (%s)" % (lock.text if lock != null else "-"))
	h.bind("G", "war_cry")
	check(str(h.binds.get("G", "")) != "war_cry", "a locked shared skill (War Cry, 6) can't be bound")
	h.bind("G", "nova")
	check(str(h.binds.get("G", "")) == "nova", "but one already on the bar can move to another key")
	h.bind("E", "nova")
	# levelling up opens them
	h.xp = 0
	h.add_xp(Data.xp_for_level(1) + Data.xp_for_level(2) + 1)
	check(h.level == 3, "levelled to 3")
	check(g.ui.big_lbl.text.contains("Holy Nova"), "and was told: %s" % g.ui.big_lbl.text)
	h.mana = h.max_mana
	for k in h.cds.keys():
		h.cds[k] = 0.0
	await wait(90)
	check(h.use_skill("nova", h.global_position), "level 3: Holy Nova casts")
	# the testing panel opens everything
	await wait(90)
	g.test_allskills = true
	h.mana = h.max_mana
	check(h.use_skill("cry", h.global_position), "All skills (F8): Battle Cry at level 3")
	g.test_allskills = false
	# Doug at 1: the pie and the peels; the clown car waits for 20
	await g.start_game(false, "doug")
	while g._busy:
		await wait(5)
	g.ui.close_all()
	h = g.hero
	await wait(30)
	h.set_level(1)
	h.mana = h.max_mana
	check(not h.use_skill("car", h.global_position), "Doug at 1: no clown car")
	h.set_level(20)
	await wait(5)
	h.mana = h.max_mana
	for k in h.cds.keys():
		h.cds[k] = 0.0
	var ok: bool = h.use_skill("car", h.global_position)
	check(ok, "Doug at 20: the clown car (level %d, mana %d, atk '%s', cd %.1f)" % [h.level, int(h.mana), h.atk_skill, float(h.cds.get("car", 0.0))])
	print("[U] done, %d failed" % fails)
	quit()
