extends SceneTree
## The shared stash (SharedStash, Game.stash_deposit / stash_withdraw, Game._stash_fix_hero): one stash for every
## character, five tabs; an item moves in and out; it never doubles: a crash between the two saves (simulated by
## putting the stash back as it was saved, or the character back as it was), a second copy of the game (another
## SharedStash on the same file), an old character's own stash moving in, twice. Not in a raid or the sandbox.
## Its own stash file (SharedStash.TEST_PATH) and the test save, never the player's.
var g
var fails := 0
func _initialize():
	DirAccess.remove_absolute(SharedStash.TEST_PATH)
	g = (load("res://main.tscn") as PackedScene).instantiate()
	get_root().add_child(g)
	_run()
func check(ok: bool, what: String) -> void:
	print("[ST] ", "ok   " if ok else "FAIL ", what)
	if not ok:
		fails += 1
func wait(n: int) -> void:
	for i in n:
		await process_frame
## Every item on the hero and in the stash with this name, counted.
func copies(nm: String) -> int:
	var n := 0
	for it in g.hero.inventory + g.hero.belt + g.hero.equipment.values():
		if it is Dictionary and str(it.get("name", "")) == nm:
			n += 1
	for row in g.stash.tabs:
		for it in row:
			if it is Dictionary and str(it.get("name", "")) == nm:
				n += 1
	return n
func _run() -> void:
	while g.world == null or g._busy:
		await wait(5)
	await g.start_game(false, "knight")
	while g._busy:
		await wait(5)
	g.ui.close_all()
	var h = g.hero
	check(g.stash != null and g.stash.path == SharedStash.TEST_PATH, "the stash is the test's own file")
	check(g.stash.tabs.size() == 5 and (g.stash.tabs[0] as Array).size() == 60, "five tabs of 60")
	# in and out
	var sword: Dictionary = Items.make("short_sword", 2, 10)
	sword["name"] = "Test Blade"
	h.inventory[0] = sword
	check(g.stash_deposit(0, 2), "into tab III")
	check(h.inventory[0] == null and g.stash.tabs[2][0] is Dictionary and g.stash.tabs[2][0].has("uid"), "it's in the stash, stamped, and out of the bag")
	var on_disk = JSON.parse_string(FileAccess.get_file_as_string(SharedStash.TEST_PATH))
	check(on_disk is Dictionary and (on_disk["tabs"][2][0] is Dictionary), "and the stash file has it")
	check(g.stash_withdraw(2, 0), "back out")
	check(h.inventory[0] is Dictionary and g.stash.tabs[2][0] == null and copies("Test Blade") == 1, "one copy, in the bag")
	# a crash after the deposit's stash save, before the last character save: the character's file still has it,
	# stamped (the first save)
	check(g.stash_deposit(0, 0), "into tab I again")
	h.inventory[0] = (g.stash.tabs[0][0] as Dictionary).duplicate(true)
	check(copies("Test Blade") == 2, "the crash left it in both")
	g._stash_fix_hero()
	check(copies("Test Blade") == 1 and g.stash.tabs[0][0] is Dictionary, "loading the character takes the copy out: one, in the stash")
	# a crash after the withdraw's first save (the character's), before the stash's
	var st_before: Dictionary = g.stash.to_dict().duplicate(true)
	check(g.stash_withdraw(0, 0), "out to the bag")
	g.stash.from_dict(st_before.duplicate(true))
	g.stash.save()
	check(copies("Test Blade") == 2, "this crash left it in both too")
	g._stash_fix_hero()
	check(copies("Test Blade") == 1 and g.stash.tabs[0][0] is Dictionary, "and the stash's copy wins: still one")
	# a second copy of the game on the same file takes it first
	var other := SharedStash.new(SharedStash.TEST_PATH)
	check(other.tabs[0][0] is Dictionary, "the other copy sees it")
	other.tabs[0][0] = null
	other.save()
	check(not g.stash_withdraw(0, 0) and copies("Test Blade") == 0, "this copy re-reads the stash first: nothing to take, no copy made")
	# a character's own old stash moves in once, even if the move is cut short and runs again
	var rock: Dictionary = Items.make("ring", 1, 5)
	rock["name"] = "Old Ring"
	h.stash[3] = rock
	g._stash_fix_hero()
	check(copies("Old Ring") == 1 and h.stash[3] == null, "an old character's stash item moves into the shared one")
	# (the cut-short case: the character kept its old stash entry, already stamped and already in the shared stash)
	var moved = null
	for row in g.stash.tabs:
		for it in row:
			if it is Dictionary and str(it.get("name", "")) == "Old Ring":
				moved = it
	h.stash[3] = (moved as Dictionary).duplicate(true)
	g._stash_fix_hero()
	check(copies("Old Ring") == 1 and h.stash[3] == null, "run again after a cut-short move: still one")
	# full
	for t in 5:
		for i in 60:
			if g.stash.tabs[t][i] == null:
				g.stash.tabs[t][i] = Items.make("ring", 0, 1)
	g.stash.save()
	h.inventory[1] = Items.make("ring", 0, 1)
	check(not g.stash_deposit(1, 4) and h.inventory[1] != null, "a full stash takes nothing (the item stays in the bag)")
	# where it opens
	g.bg_mode = true
	check(not g.stash_allowed(), "not in a raid")
	g.bg_mode = false
	check(g.stash_allowed(), "but in the camp")
	DirAccess.remove_absolute(SharedStash.TEST_PATH)
	print("[ST] done, %d failed" % fails)
	quit()
