extends SceneTree
## The quests (quests.gd): the main quest is on from the start; Captain Roth offers Embers on the Road ("!"), the
## Fallen killed count it up, it's ready ("?"), handing it in pays out; the smith's and the alchemist's open after,
## a Cinderheart and a Sunstar Bloom count; the log and the tracker fill; it all survives a save and a load.
##   godot --headless --path . -s tools/quest_test.gd
var g
var fails := 0

func _initialize():
	g = (load("res://main.tscn") as PackedScene).instantiate()
	get_root().add_child(g)
	_run()

func check(ok: bool, what: String) -> void:
	print("[Q] %s %s" % ["ok  " if ok else "FAIL", what])
	if not ok:
		fails += 1

func _run() -> void:
	while g.world == null or g._busy or g._intro_playing:
		g._intro_skip = true
		await process_frame
	await g.start_game(false, "knight")
	g.ui.close_all()
	var q: Quests = g.quests
	check(q.status("gilded_king") == "active", "the main quest, The Gilded King, is on from the start")
	check(q.mark("elder") == "!" and q.mark("smith") == "", "Captain Roth has work on offer (!), the smith not yet")
	# talking to Roth: the offer comes first
	var shown: bool = q.talk("elder", "Captain Roth", func(): pass)
	check(shown and g.ui.dialog_panel.visible and g.ui.dialog_text.text.contains("Fallen"), "talking to him opens the quest's offer")
	g.ui.dialog_panel.visible = false
	q.accept("embers_road")
	check(q.status("embers_road") == "active" and q.mark("elder") == "", "accepted: active, nothing more on offer from him yet")
	await process_frame
	check(g.ui.quest_tracker.get_child_count() > 0, "the tracker lists it (%d lines)" % g.ui.quest_tracker.get_child_count())
	# the Fallen on the moor
	await g.load_zone(0, "wild", "start")
	g.test_immortal = true
	var kinds := ["fallen_skirmisher", "fallen_reaver", "fallen_stalker"]
	for i in 10:
		var e: Enemy = g.spawn_enemy(kinds[i % 3], g.world.free_spot_near(g.hero.global_position + Vector3(6, 0, 0), 1.5), 1)
		await process_frame
		e.take_damage(99999.0, 0.0, g.hero.global_position, 0.0, false)
		await process_frame
	check(q.status("embers_road") == "ready", "ten Fallen slain: ready to hand in (%s)" % [q.counts("embers_road")])
	check(q.mark("elder") == "?", "Roth shows ? now")
	var z: Enemy = g.spawn_enemy("zombie", g.world.free_spot_near(g.hero.global_position + Vector3(6, 0, 0), 1.5), 1)
	await process_frame
	z.take_damage(99999.0, 0.0, g.hero.global_position, 0.0, false)
	check(q.counts("gilded_king")[0] == 0, "a zombie doesn't count for Grubb")
	# hand it in
	var gold0: int = g.hero.gold
	var items0: int = g.hero.inventory.filter(func(x): return x != null).size()
	q.turn_in("embers_road")
	var items1: int = g.hero.inventory.filter(func(x): return x != null).size()
	check(q.status("embers_road") == "done" and g.hero.gold == gold0 + 150 and items1 == items0 + 1, "handed in: done, +150 gold, a ring (%d -> %d items)" % [items0, items1])
	check(q.mark("smith") == "!" and q.mark("elder") == "!", "after it: Halvar's forge quest and Roth's Three Hollows are on offer")
	q.accept("dying_forge")
	q.accept("sunstar")
	q.on_pick("cinderheart")
	q.progress("flower")
	check(q.status("dying_forge") == "ready" and q.status("sunstar") == "ready", "a Cinderheart and a Sunstar Bloom finish the smith's and the alchemist's")
	var w = g.hero.equipment.get("weapon")
	var before: int = g.hero.inventory.filter(func(x): return x != null and x["base"] == (w["base"] if w != null else "")).size()
	q.turn_in("dying_forge")
	var after: int = g.hero.inventory.filter(func(x): return x != null and x["base"] == (w["base"] if w != null else "")).size()
	check(after == before + 1, "Halvar forges him a weapon of his own kind (%s)" % (w["base"] if w != null else "none"))
	# the log
	g.ui.toggle(g.ui.quest_panel)
	await process_frame
	await process_frame
	var labels: Array = g.ui.quest_list.find_children("*", "Label", true, false).map(func(l): return (l as Label).text)
	check(labels.any(func(t): return t.contains("The Gilded King")) and labels.any(func(t): return t.contains("(done)")), "the log (J) shows the main quest and the finished ones (%d lines)" % labels.size())
	g.ui.close_all()
	# save and load
	g.save_game()
	q.from_save({})
	check(q.status("embers_road") == "", "(cleared)")
	g.load_game()
	check(q.status("embers_road") == "done" and q.status("sunstar") == "ready" and q.status("gilded_king") == "active", "saved and loaded: done, ready and active as they were")
	# A2 has no quests yet: nothing on offer there
	g.difficulty = 1
	check(q.mark("elder") == "" and q.current().is_empty(), "A2: no quests (Act I's are its own)")
	g.difficulty = 0
	print("[Q] done, %d failed" % fails)
	quit()
