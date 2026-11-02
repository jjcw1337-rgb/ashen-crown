extends SceneTree
## The drunken dwarves (dwarf_game.gd): rock-paper-scissors, best of three, played through the dialogs as a player
## would (pressing the throws); a win pays (an item on the ground, gold) and still lets you call them out; a loss
## sets them on you (three champion dwarves); either way it's once per character (Hero.dwarves, saved).
var g
var fails := 0
func _initialize():
	g = (load("res://main.tscn") as PackedScene).instantiate()
	get_root().add_child(g)
	_run()
func check(ok: bool, what: String) -> void:
	print("[W] ", "ok   " if ok else "FAIL ", what)
	if not ok:
		fails += 1
func dwarves() -> int:
	return g.world.enemies_root.get_children().filter(func(e): return e.kind == "dwarf" and not e.dead).size()
func play_out() -> String:
	# press throws until the dialog stops offering them
	for i in 40:
		await process_frame
		if not g.ui.dialog_panel.visible:
			return g.hero.dwarves
		var btns: Array = g.ui.dialog_btns.get_children()
		if g.ui.dialog_name.text != "Rock, Paper, Scissors":
			return g.hero.dwarves
		(btns[randi() % 3] as Button).pressed.emit()
		await process_frame
	return g.hero.dwarves
func _run() -> void:
	while g.world == null or g._busy:
		await process_frame
	await g.start_game(false, "knight")
	g.ui.close_all()
	g.hero.set_level(12)
	g.test_immortal = true
	await g.travel(0, "isle_verdant", "jetty")
	while g._busy:
		await process_frame
	var t = null
	for it in g.world.interactables:
		if it.kind == "dwarves":
			t = it
	check(t != null, "the dwarves' camp by the tunnel")
	var seen := {}
	for attempt in 12:
		g.hero.dwarves = ""
		t.used = false
		for e in g.world.enemies_root.get_children():
			if e.kind == "dwarf":
				e.queue_free()
		await process_frame
		var gold0: int = g.hero.gold
		var items0: int = g.net.items.size() if g.net.has_method("items") else 0
		g._interact(t)
		await process_frame
		check(g.ui.dialog_panel.visible and g.ui.dialog_name.text == "Rock, Paper, Scissors", "they offer the game") if attempt == 0 else null
		var res: String = await play_out()
		if res == "won" and not seen.has("won"):
			seen["won"] = true
			check(g.hero.gold > gold0, "a win pays (%d gold)" % (g.hero.gold - gold0))
			check(g.ui.dialog_panel.visible and g.ui.dialog_btns.get_child_count() == 2, "and lets you call them out")
			(g.ui.dialog_btns.get_child(1) as Button).pressed.emit()
			await process_frame
			check(dwarves() == 3 and g.hero.dwarves == "fought", "called out: three dwarves")
			g.ui.close_all()
			g._interact(t)
			await process_frame
			check(not g.ui.dialog_panel.visible, "and after that, nothing more to play")
		elif res == "lost" and not seen.has("lost"):
			seen["lost"] = true
			check(g.ui.dialog_panel.visible, "a loss: they come at you")
			(g.ui.dialog_btns.get_child(0) as Button).pressed.emit()
			await process_frame
			check(dwarves() == 3 and g.hero.dwarves == "lost", "three champion dwarves (%d)" % dwarves())
			var e = g.world.enemies_root.get_children().filter(func(x): return x.kind == "dwarf")[0]
			check(e.champion and e.level > g.world.level + 2, "strong ones (level %d champions)" % e.level)
		if seen.size() == 2:
			break
	check(seen.size() == 2, "both outcomes seen (%s)" % str(seen.keys()))
	g.hero.dwarves = "won"
	var d: Dictionary = g.hero.to_save()
	check(str(d.get("dwarves", "")) == "won", "the outcome is saved with the character")
	print("[W] done, %d failed" % fails)
	quit()
