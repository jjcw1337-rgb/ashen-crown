extends SceneTree
## The admin "Go to level 20" (Game.go_level_20, the F8 panel): level 20, stats spent, talents built, a level-20
## baseline on every slot with the class's own weapon; pressed again nothing is duplicated; what was equipped before
## is moved to the bag, never destroyed; without dev tools it does nothing.
var g
var fails := 0
func _initialize():
	g = (load("res://main.tscn") as PackedScene).instantiate()
	get_root().add_child(g)
	_run()
func check(ok: bool, what: String) -> void:
	print("[L] ", "ok   " if ok else "FAIL ", what)
	if not ok:
		fails += 1
func _boosted() -> int:
	var n := 0
	for k in g.hero.equipment:
		var it = g.hero.equipment[k]
		if it is Dictionary and it.get("boost", false):
			n += 1
	return n
func _bag() -> int:
	return g.hero.inventory.filter(func(it): return it != null).size()
func _run() -> void:
	while g.world == null or g._busy:
		await process_frame
	for cls in ["knight", "archer", "plague", "doug"]:
		await g.start_game(false, cls)
		g.ui.close_all()
		var h = g.hero
		g.dev_tools = false
		g.go_level_20()
		check(h.level < 20, "%s: without dev tools nothing happens" % cls)
		g.dev_tools = true
		var old = h.equipment.get("weapon")
		var bag0 := _bag()
		g.go_level_20()
		check(h.level == 20 and h.stat_points == 0, "%s: level 20, stats spent" % cls)
		check(h.free_talent_points() == 0, "%s: talents built" % cls)
		var n := _boosted()
		check(n >= 9, "%s: level-20 gear on %d slots" % [cls, n])
		var w = h.equipment.get("weapon")
		var mine := str(Data.CLASSES[cls].get("weapon", ""))      # the knight has none of his own: any weapon
		var want := str(Data.BASES[mine].get("kind", "")) if mine != "" else ""
		check(w is Dictionary and (want == "" or str(Data.BASES[w["base"]].get("kind", "")) == want), "%s: its own kind of weapon (%s)" % [cls, w["base"] if w is Dictionary else "-"])
		check(old == null or _bag() > bag0 or g.hero.inventory.has(old), "%s: what it wore before went to the bag" % cls)
		var bag1 := _bag()
		g.go_level_20()
		check(_boosted() == n and _bag() == bag1, "%s: pressed again, nothing duplicated" % cls)
	print("[L] done, %d failed" % fails)
	quit()
